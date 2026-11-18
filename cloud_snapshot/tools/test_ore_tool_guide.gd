extends SceneTree

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.2

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _read_step(main) -> Dictionary:
	var before := SaveGame.capture(main)
	var step: Dictionary = main.navigation.guide_snapshot().next_step
	_check(SaveGame.capture(main) == before, "reading the guide leaves the save snapshot unchanged")
	return step

func _step_world(main) -> void:
	main._process(STEP)
	for worker in main.workers:
		worker._process(STEP)

func _travel(main, destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for tick in range(500):
		_step_world(main)
		if main.world.region == destination and main.world.phase == "stopped":
			return true
		if tick % 30 == 0:
			await process_frame
	return false

func _check_quarry(main, tool: int, expect_ore: bool) -> void:
	if not main.equip_tool(main.workers[0], tool):
		_check(false, "the quarry harvester can equip the test mining tool")
		return
	var made := RouteSession.create_from_game(main, "ore-tool-%d" % tool, {"mine_path_engineering": true})
	_check(made.ok, "ordinary C session starts from the live world")
	if not made.ok:
		return
	var session = made.session
	var ore := GameData.Item.IRON_ORE
	var before: int = main.storage.count_of(ore)
	var ore_reserved := false
	var tool_explained := false
	for tick in range(2500):
		session.tick(STEP)
		session.apply_projection_to_workers(main)
		for id in session.reservations:
			ore_reserved = ore_reserved or session.resources[id].item == ore
		if expect_ore and int(session.depot_stock.get(ore, 0)) > 0:
			break
		if not expect_ore and session.actors["worker:0"].state == "idle":
			for entry in session.event_log:
				tool_explained = tool_explained or "鉱床にはピッケル" in entry.text
			if tool_explained:
				break
	_check(ore_reserved == expect_ore and (int(session.depot_stock.get(ore, 0)) > 0) == expect_ore, "only the stone pickaxe reserves and delivers iron ore")
	if not expect_ore:
		_check(tool_explained and int(session.depot_stock.get(GameData.Item.STONE, 0)) > 0, "wood pick collects stone and reaches the blocked vein with room still available")
	session.request_recall()
	for tick in range(1500):
		if session.phase == "ready_to_exit":
			break
		session.tick(STEP)
		session.apply_projection_to_workers(main)
	_check(session.phase == "ready_to_exit", "both tools let the harvester recall safely")
	var committed: Dictionary = session.commit_to_game(main)
	_check(committed.ok and (main.storage.count_of(ore) > before) == expect_ore, "both returns commit, with ore only for the stone pickaxe")

func _run() -> void:
	SaveGame.disabled = true
	var main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 261109)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.finish_build("workbench")
	main.storage.store_owned(GameData.Item.WOOD_PICK, 1, Inventory.SOURCE_TRANSFER)
	_check(main.equip_tool(main.workers[0], GameData.Item.WOOD_PICK), "equipped the wood pick using the normal inventory API")
	var step := _read_step(main)
	_check(step.id == "ore_tool" and "石のピッケル" in step.body and "鉱床" in step.body, "wood pick alone leads to ore tool advice")
	_check(main.request_order("tool_hammer", 1) == 1, "stone pickaxe order accepted")
	step = _read_step(main)
	_check(step.id == "ore_tool" and "依頼済み" in step.body and "待って" in step.body and "作成 → 道具" not in step.body, "pending order guidance asks the player to wait")
	main.storage.store_owned(GameData.Item.STONE, 2, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.WOOD, 1, Inventory.SOURCE_TRANSFER)
	for tick in range(1500):
		if main.storage.count_of(GameData.Item.HAMMER) > 0:
			break
		_step_world(main)
		if tick % 120 == 0:
			await process_frame
	_check(main.storage.count_of(GameData.Item.HAMMER) == 1, "the actual order is crafted and delivered to storage")
	step = _read_step(main)
	_check(step.id == "ore_tool" and "倉庫に石のピッケル" in step.body and "作成 → 道具" not in step.body, "stored pickaxe guidance asks the player to equip it")
	_check(main.equip_tool(main.workers[0], GameData.Item.HAMMER), "equipped the stone pickaxe using the normal inventory API")
	_check(_read_step(main).id == "visit_c", "equipping the stone pickaxe advances the guide to C")
	_check("ピッケル" in GatherDB.requirement("vein"), "vein requirement names the pickaxe")
	_check(GameData.ITEM_NAMES[GameData.Item.HAMMER] == "石のピッケル", "legacy item ID displays the stone pickaxe name")
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.set_priority(job, 0)
	var reached_c := await _travel(main, "b_forest") and await _travel(main, "c_quarry")
	_check(reached_c, "real A to B to C route reaches the quarry")
	if reached_c:
		_check_quarry(main, GameData.Item.WOOD_PICK, false)
		_check_quarry(main, GameData.Item.HAMMER, true)
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	quit(1 if failures else 0)
