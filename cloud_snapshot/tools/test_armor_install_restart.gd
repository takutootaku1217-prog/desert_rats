extends SceneTree
var fails := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("%s %s" % ["ok" if ok else "FAIL",label])
	if not ok: fails += 1
func run() -> void:
	if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2); return
	SaveGame.disabled = true
	var game = load("res://scenes/main.tscn").instantiate()
	game.first_region_a_pilot = true
	root.add_child(game)
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var path := "user://armor-recovery-test.json"
	var before := FileAccess.get_sha256(path)
	check(SaveGame.apply(game,SaveGame.read(path)), "new PID loads actual equipped save")
	check(game.base.vehicle_loadout.armor == "plate" and game.storage.count_of(GameData.Item.ARMOR_PLATE_KIT) == 0 and game.storage.current_weight() == 20, "shared armor and consumed kit persist without duplication")
	check(game.base.vehicle_defense() == 4 and game.base._armor_pending.is_empty(), "effect restored but pending transaction is never restored")
	check(FileAccess.get_sha256(path) == before, "restart does not rewrite source save")
	game.free()
	quit(1 if fails else 0)
