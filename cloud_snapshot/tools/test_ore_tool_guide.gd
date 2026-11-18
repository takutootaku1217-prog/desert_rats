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

func _check_quarry(main, scenario: String) -> void:
	var wood_tool := scenario == "wood"
	var expect_ore := scenario == "ore first"
	var capacity_limited := scenario == "capacity"
	var tool := GameData.Item.WOOD_PICK if wood_tool else GameData.Item.HAMMER
	if int(main.workers[0].tools.get("mine", -1)) != tool and not main.equip_tool(main.workers[0], tool):
		_check(false, "%s: the quarry harvester can equip the test mining tool" % scenario)
		return
	var made := RouteSession.create_from_game(main, "ore-tool-" + scenario, {"mine_path_engineering": true})
	_check(made.ok, "%s: ordinary C session starts from the live world" % scenario)
	if not made.ok:
		return
	var session = made.session
	var ore := GameData.Item.IRON_ORE
	var stone := GameData.Item.STONE
	var before: int = main.storage.count_of(ore)
	var stone_before: int = main.storage.count_of(stone)
	var vein_remaining := 0
	for resource in session.resources.values():
		if resource.kind == "vein":
			vein_remaining += int(resource.remaining)
	_check((vein_remaining > 0) == (scenario != "depleted"), "%s: vein remaining at entry is %d" % [scenario, vein_remaining])
	if capacity_limited:
		session.field_capacity_limit_weight = CargoDB.size_of(stone)
		_check(session.normal_collection_room_for(ore) == 0 and session.normal_collection_room_for(stone) == 1, "remaining field capacity fits one stone and zero ore")
	var first_reserved := -1
	var first_cargo: Array = []
	var ore_reserved := false
	var tool_explained := false
	for tick in range(2500):
		session.tick(STEP)
		session.apply_projection_to_workers(main)
		for id in session.reservations:
			var item: int = session.resources[id].item
			if first_reserved < 0:
				first_reserved = item
			ore_reserved = ore_reserved or item == ore
		if first_cargo.is_empty() and not session.depot_stock.is_empty():
			first_cargo = session.depot_stock.keys()
		if expect_ore and int(session.depot_stock.get(ore, 0)) >= vein_remaining:
			break
		if (wood_tool or capacity_limited) and session.actors["worker:0"].state == "idle":
			for entry in session.event_log:
				tool_explained = tool_explained or "鉱床にはピッケル" in entry.text
			if tool_explained or capacity_limited:
				break
		if scenario == "depleted" and int(session.depot_stock.get(stone, 0)) > 0:
			break
	var expected_item := ore if expect_ore else stone
	_check(first_reserved == expected_item and first_cargo == [expected_item], "%s: first reservation and first delivered cargo match" % scenario)
	_check(ore_reserved == expect_ore and (int(session.depot_stock.get(ore, 0)) > 0) == expect_ore, "%s: ore reservation and delivery match" % scenario)
	if wood_tool:
		_check(tool_explained and int(session.depot_stock.get(stone, 0)) > 0, "wood pick collects stone and reaches the blocked vein with room still available")
	if capacity_limited:
		_check(session.actors["worker:0"].wait_reason == RouteSession.NORMAL_CAPACITY_WAIT and not tool_explained, "once stone fills the budget, the wait is about capacity")
	if expect_ore:
		_check(int(session.depot_stock.get(ore, 0)) == vein_remaining, "pickaxe run naturally depletes the veins for the next entry")
	session.request_recall()
	for tick in range(1500):
		if session.phase == "ready_to_exit":
			break
		session.tick(STEP)
		session.apply_projection_to_workers(main)
	_check(session.phase == "ready_to_exit", "%s: harvester recalls safely" % scenario)
	var committed: Dictionary = session.commit_to_game(main)
	_check(committed.ok and (main.storage.count_of(ore) > before) == expect_ore and (expect_ore or main.storage.count_of(stone) > stone_before), "%s: return commits the expected cargo" % scenario)

func _prepare_harvester(main) -> void:
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.set_priority(job, 0)

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
	_prepare_harvester(main)
	var reached_c := await _travel(main, "b_forest") and await _travel(main, "c_quarry")
	_check(reached_c, "real A to B to C route reaches the quarry")
	if reached_c:
		_check_quarry(main, "capacity")
		_check_quarry(main, "ore first")
		_check_quarry(main, "depleted")
	main.queue_free()
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 261109)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.storage.store_owned(GameData.Item.WOOD_PICK, 1, Inventory.SOURCE_TRANSFER)
	_prepare_harvester(main)
	reached_c = await _travel(main, "b_forest") and await _travel(main, "c_quarry")
	_check(reached_c, "wood-tool run reaches C with fresh veins by the real route")
	if reached_c:
		_check_quarry(main, "wood")
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	quit(1 if failures else 0)
