extends SceneTree
## Real Main/inventory/crafting/save tests. Materials are explicit fixtures, not natural GUI acquisition.
## Catches free armor, partial commits, ignored reservations, stale/load-identical quotes and missing item integration.
var game
var failures := 0
var assertions := 0
var kit := -1
var pristine := {}
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	print("%s %s" % ["ok" if ok else "FAIL", label])
	if not ok: failures += 1
func reset() -> void:
	if not pristine.is_empty(): check(SaveGame.apply(game,pristine), "reset restores real pristine state")
	game.base.cancel_armor_preview()
	game.base.vehicle_loadout = VehicleLoadout.initial_state()
	game.storage.inventory.counts = {kit: 1}
	game.storage.capacity_bonus = 0
	game.processor.stock.counts = {}
	game.processor.orders.clear()
	game.processor.current = {}
	game.processor.output.clear()
	game.transfer_queue.clear()
	game.craft_queue.clear()
	for worker in game.workers: worker.stop_work()
func snapshot() -> Dictionary:
	return {"counts":game.storage.inventory.counts.duplicate(true), "loadout":game.base.vehicle_loadout.duplicate(true), "hp":game.base.hp, "fuel":game.base.fuel, "parts":game.base.parts.duplicate(true), "credits":game.town.credits}
func run() -> void:
	SaveGame.disabled = true
	game = load("res://scenes/main.tscn").instantiate()
	game.first_region_a_pilot = true
	root.add_child(game)
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.director.enabled = false
	for worker in game.workers: worker.stop_work()
	pristine = SaveGame.capture(game)
	check(SaveGame.validate(pristine,game), "fresh first-region fixture validates before prototype actions")
	var recipe := GameData.recipe_by_id("armor_plate_kit")
	check(not recipe.is_empty(), "armor can be manufactured through canonical recipe")
	check(not game.base.equip_vehicle_part("armor", "plate"), "generic base setter cannot grant free armor")
	game.base.vehicle_loadout.armor = "none"
	game.apply_vehicle_combat_preset()
	check(game.base.vehicle_loadout.armor == "none", "combat preset cannot grant armor")
	check(game.base.has_method("begin_armor_preview"), "guarded comparison/confirmation contract exists")
	if recipe.is_empty() or not game.base.has_method("begin_armor_preview"): finish(); return
	kit = int(recipe.out)
	reset()
	check(kit == 29 and GameData.Item.RIFLE == 28 and kit in ItemDB.ORDER and CargoDB.bay_of(kit) == CargoDB.Bay.PRODUCT, "appended item preserves old IDs and is visible cargo")
	check(game.storage.current_weight() == 20 and CraftDB.entry_of("armor_plate_kit").cat == "装備", "kit contributes weight and appears in equipment crafting")
	game.processor.stock.counts = {GameData.Item.IRON:3, GameData.Item.HIDE:2}
	game.storage.inventory.counts = {}
	check(game.request_craft("armor_plate_kit",1) == 0, "craft requires workbench despite complete materials")
	game.finish_build("workbench")
	check(game.request_craft("armor_plate_kit",1) == 1 and game.request_craft("armor_plate_kit",1) == 0, "real craft queue reserves exactly one materials set")
	check(game.storage.current_weight() == 20, "queued craft does not duplicate material weight")
	check(SaveGame.validate(SaveGame.capture(game),game), "queued new recipe is save-valid")
	game.refill_settings = {}
	game._feed_crafts()
	check(game.processor.stock.count(GameData.Item.IRON) == 0 and game.processor.stock.count(GameData.Item.HIDE) == 0 and game.processor.orders.size() == 1 and game.storage.current_weight() == 20, "real feed consumes exact materials into committed ownership")
	game.processor.work(1.0, func(_field): return 1.0)
	check(not game.processor.current.is_empty() and SaveGame.validate(SaveGame.capture(game),game) and game.storage.current_weight() == 20, "active armor craft saves with conserved weight")
	game.processor.work(5.0, func(_field): return 1.0)
	check(game.processor.output == [kit] and game.storage.current_weight() == 20 and SaveGame.validate(SaveGame.capture(game),game), "real processing produces one weighted save-valid kit")
	var item: int = game.processor.take_output()
	var carrier = game.workers[0]
	carrier.carrying = item; carrier.carry_n = 1
	check(game.storage.current_weight() == 20 and not game.base.begin_armor_preview("plate").ok, "carried completed kit remains weighted but cannot install early")
	carrier.carrying = -1; carrier.carry_n = 0
	game.storage.store_owned(item,1)
	check(game.storage.current_weight() == 20 and game.base.begin_armor_preview("plate").ok, "normal owned storage exposes completed kit for installation")
	reset()
	var before := snapshot()
	var q: Dictionary = game.base.begin_armor_preview("plate")
	check(q.ok and q.used == 20 and q.defense == 4 and q.damage_after == 4, "comparison replaces warehouse kit with shared plate weight and total defense")
	check(snapshot() == before, "preview changes no gameplay state")
	game.base.cancel_armor_preview()
	check(not game.base.confirm_armor_install(q.token) and snapshot() == before, "cancel invalidates token without consumption")
	q = game.base.begin_armor_preview("plate")
	var observed := []
	var listener := func(): observed.append([game.base.vehicle_loadout.armor, game.storage.count_of(kit), game.storage.current_weight(), game.base.confirm_armor_install(q.token)])
	game.storage.inventory.changed.connect(listener)
	check(game.base.confirm_armor_install(q.token), "confirm installs once")
	game.storage.inventory.changed.disconnect(listener)
	check(observed == [["plate",0,20,false]], "synchronous observer sees whole atomic commit and cannot reenter")
	check(not game.base.confirm_armor_install(q.token) and game.base.hp == before.hp and game.base.fuel == before.fuel and game.base.parts == before.parts and game.town.credits == before.credits, "double confirm cannot charge or heal")
	check(not game.base.begin_armor_preview("none").ok and not game.base.begin_armor_preview("composite").ok, "unsupported removal/replacement cannot destroy existing plate")
	for owner in ["missing","stock","output","outbound"]:
		reset()
		if owner != "outbound": game.storage.inventory.counts = {}
		if owner == "stock": game.processor.stock.counts = {kit:1}
		if owner == "output": game.processor.output = [kit]
		if owner == "outbound": game.request_transfer(kit,1,"to_workshop")
		before = snapshot()
		check(not game.base.begin_armor_preview("plate").ok and snapshot() == before, "cannot consume kit owned by " + owner)
	reset()
	game.storage.inventory.counts[GameData.Item.FOOD] = 340
	q = game.base.begin_armor_preview("plate")
	check(q.ok and q.left == 0 and game.base.confirm_armor_install(q.token) and game.storage.current_weight() == 360, "exact-full weight-neutral install succeeds without dropping cargo")
	reset()
	game.storage.capacity_bonus = 10
	game.storage.inventory.counts[GameData.Item.FOOD] = 350
	q = game.base.begin_armor_preview("plate")
	check(q.ok and q.left == 0, "capacity upgrade is included in comparison")
	game.storage.inventory.counts[GameData.Item.FOOD] += 1
	check(not game.base.confirm_armor_install(q.token), "weight changed since comparison rejects stale confirm")
	check(not game.base.begin_armor_preview("plate").ok, "over-capacity install is conservative and non-destructive")
	reset()
	q = game.base.begin_armor_preview("plate")
	game.base.equip_vehicle_part("drive","wheels")
	check(not game.base.confirm_armor_install(q.token), "other equipment invalidates old quote")
	reset()
	game.base.vehicle_loadout.chassis = "reinforced_large"
	q = game.base.begin_armor_preview("plate")
	check(q.defense == 5 and q.damage_after == 3, "preview includes chassis plus armor defense")
	reset()
	var saved := SaveGame.capture(game)
	check(SaveGame.validate(saved,game), "warehouse kit save is valid")
	q = game.base.begin_armor_preview("plate")
	check(not SaveGame.apply(game,{}) and game.base.confirm_armor_install(q.token), "invalid load preserves valid pending transaction")
	check(SaveGame.apply(game,saved), "kit snapshot restores")
	q = game.base.begin_armor_preview("plate")
	check(SaveGame.apply(game,saved) and not game.base.confirm_armor_install(q.token), "identical successful load invalidates old quote")
	for armor in ["none","plate","composite"]:
		game.base.vehicle_loadout.armor = armor
		var old := SaveGame.capture(game)
		check(SaveGame.apply(game,old) and game.base.vehicle_loadout.armor == armor and game.storage.count_of(kit) == 1, "legacy " + armor + " preserved without retroactive fee")
	reset()
	check(game.vehicle_ui.has_method("preview_armor"), "normal UI has explicit armor comparison")
	if game.vehicle_ui.has_method("preview_armor"):
		game.vehicle_ui.open()
		before = snapshot()
		game.vehicle_ui.preview_armor("plate")
		check(game.vehicle_ui._armor_dialog.visible and snapshot() == before, "UI comparison is visible and non-destructive")
		game.vehicle_ui.close()
		check(not game.vehicle_ui._armor_dialog.visible and snapshot() == before, "closing UI cancels comparison without charge")
		game.vehicle_ui.open()
		game.vehicle_ui.preview_armor("plate")
		game.vehicle_ui._armor_dialog.confirmed.emit()
		check(game.base.vehicle_loadout.armor == "plate" and game.storage.count_of(kit) == 0, "UI confirm uses one paid atomic transaction")
		game.vehicle_ui.close()
	SaveGame.disabled = false
	check(not OS.get_environment("FLUID_TEST_HOME").is_empty() and SaveGame.write(game,"user://armor-recovery-test.json",true), "equipped state written to isolated real save for next PID")
	finish()
func finish() -> void:
	print("ARMOR ASSERTIONS %d FAILURES %d" % [assertions,failures])
	game.free()
	quit(1 if failures else 0)
