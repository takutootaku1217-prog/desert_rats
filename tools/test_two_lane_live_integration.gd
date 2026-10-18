extends "res://tools/test_quarry.gd"
## 通常 Main / Worker / CharacterAI に限定した、連続奥行き帯の小規模接続試験。
## 固定線・固定横断路ではない。通常マップ全体にはまだ展開しない。

const BACK_Y := 570.0
const FRONT_Y := 625.0


func _configure_depth_strip() -> void:
	check(main.world.depth_strip_active(), "prototype harvest location starts with the continuous depth strip")
	var config: Dictionary = main.get_meta("ground_depth_strip_config")
	check(is_equal_approx(float(config.back_y), BACK_Y) and is_equal_approx(float(config.front_y), FRONT_Y) and String(config.location) == "region:south_oasis", "prototype uses the documented back/front anchors at south_oasis")
	main.target_speed = 0.0
	main.tool_auto = false
	main.gather_policy = {GameData.Item.WOOD: 0, GameData.Item.STONE: 0, GameData.Item.IRON_ORE: 5}
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.priorities[job] = 0


func _step_live() -> void:
	await step()


func _until_live(done: Callable, seconds: float) -> bool:
	for _frame in ceili(seconds / 0.2):
		if done.call():
			return true
		await _step_live()
	return done.call()


func _add_front_vein() -> GatherPoint:
	var point := GatherPoint.new()
	point.setup(main, "vein")
	point.max_amount = 1
	point.remaining = 1
	point.position = Vector2(1140.0, FRONT_Y - 4.0)
	main.resources_root.add_child(point)
	return point


func _sample_depth_motion(worker, xs: Array) -> bool:
	if worker.floor_i != 0:
		return false
	if worker.position.y <= BACK_Y + 1.0 or worker.position.y >= FRONT_Y - 1.0:
		return false
	xs.append(worker.position.x)
	return true


func _initialize() -> void:
	print("-- continuous two-lane-width depth strip: south_oasis prototype --")
	await _world_locations_quarry_and_save()
	await _gather_and_haul()
	await _combat_return_and_selection()
	await _viewport_hud_selection()
	if fails == 0:
		print("DEPTH_ROLLOUT_OK")
	print("== result: %s ==" % ("all passed" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)


func _location(region: String, road := "") -> void:
	main.world._archive()
	main.world.region = region
	main.world.road = road
	main.world.progress = 0.0
	main.world.direction = 1
	main.world.phase = "stopped" if road == "" else "travel"
	main.world.origin = "" if road == "" else WorldMapDB.ROADS[road][0]
	main.world.destination = "" if road == "" else WorldMapDB.ROADS[road][1]
	main.world._ensure_location()


func _lane_y(y: float) -> bool:
	return is_equal_approx(y, BACK_Y) or is_equal_approx(y, FRONT_Y)


func _world_locations_quarry_and_save() -> void:
	await fresh()
	_configure_depth_strip()
	_location("south_oasis")
	var all_rows_in_lanes := true
	for records in main.world.locations.values():
		for row in records.values():
			all_rows_in_lanes = all_rows_in_lanes and _lane_y(row.data.position.y) and _lane_y(row.initial_data.position.y)
	check(all_rows_in_lanes, "south_oasis resources and fauna use the two outdoor depth anchors")
	await fresh()
	_configure_depth_strip()
	var snapshot := SaveGame.capture(main)
	var middle_y := 597.5
	var row_index := 0
	for records in snapshot.world.locations.values():
		for row in records.values():
			var source_y := middle_y if row_index == 0 else 680.0
			row.data.position.y = source_y
			row.initial_data.position.y = source_y
			row_index += 1
	for row in snapshot.resources:
		if row.quarry_id == "":
			row.resource.position.y = 680.0
	for row in snapshot.creatures:
		row.position.y = 680.0
	for row in snapshot.enemies:
		row.position.y = 680.0
	var slope_pos := Vector2(948.0, 516.0)
	snapshot.crew[0].worker.floor_i = 0
	snapshot.crew[0].worker.position = slope_pos
	snapshot.crew[0].worker.target = GameData.RAMP_TOP
	snapshot.crew[0].worker._climb_dest = GameData.RAMP_TOP
	snapshot.crew[0].worker._climb_floor = 1
	snapshot.crew[0].worker._climb_kind = "ramp"
	var interior_pos := Vector2(640.0, GameData.LO_Y)
	snapshot.crew[1].worker.floor_i = 1
	snapshot.crew[1].worker.position = interior_pos
	snapshot.crew[1].worker.target = interior_pos
	check(SaveGame.apply(main, snapshot), "older continuous outdoor Y values load without changing save format")
	var restored_strip_values := true
	var middle_preserved := false
	for records in main.world.locations.values():
		for row in records.values():
			restored_strip_values = restored_strip_values and row.data.position.y >= BACK_Y and row.data.position.y <= FRONT_Y and row.initial_data.position.y >= BACK_Y and row.initial_data.position.y <= FRONT_Y
			middle_preserved = middle_preserved or (is_equal_approx(row.data.position.y, middle_y) and is_equal_approx(row.initial_data.position.y, middle_y))
	check(restored_strip_values and middle_preserved, "save restore retains an in-band middle Y and clamps legacy outside-Y WorldTrip records")
	check(main.workers[0].position == slope_pos and main.workers[0]._climb_dest == GameData.RAMP_TOP, "save restore preserves a worker partway through the existing ramp")
	check(main.workers[1].floor_i == 1 and main.workers[1].position == interior_pos, "save restore preserves interior worker coordinates")
	await fresh()
	_configure_depth_strip()
	var outside_snapshot := SaveGame.capture(main)
	outside_snapshot.world.region = "east_sands"
	outside_snapshot.world.phase = "stopped"
	outside_snapshot.world.road = ""
	outside_snapshot.world.origin = ""
	outside_snapshot.world.destination = ""
	outside_snapshot.world.locations["region:east_sands"] = outside_snapshot.world.locations["region:south_oasis"]
	outside_snapshot.world.locations.erase("region:south_oasis")
	for records in outside_snapshot.world.locations.values():
		for row in records.values():
			row.data.position.y = 680.0
			row.initial_data.position.y = 680.0
	check(SaveGame.apply(main, outside_snapshot), "non-target-region save restores without schema changes")
	var outside_preserved := true
	for records in main.world.locations.values():
		for row in records.values():
			outside_preserved = outside_preserved and is_equal_approx(row.data.position.y, 680.0) and is_equal_approx(row.initial_data.position.y, 680.0)
	check(not main.world.depth_strip_active() and outside_preserved, "non-target-region save values are not normalized by the south_oasis prototype")


func _gather_and_haul() -> void:
	await fresh()
	_configure_depth_strip()
	var worker = main.workers[0]
	worker.tools = {"mine": GameData.Item.HAMMER}
	worker.priorities[GameData.Job.GATHER] = 5
	var point := _add_front_vein()
	var before: int = main.storage.count_of(GameData.Item.IRON_ORE)
	var reservation_seen := false
	var mid_depth_seen := false
	var mid_depth_xs: Array = []
	for _frame in 300:
		reservation_seen = reservation_seen or (point.claimed_by == worker and point.reserved >= 1)
		mid_depth_seen = _sample_depth_motion(worker, mid_depth_xs) or mid_depth_seen
		if main.storage.count_of(GameData.Item.IRON_ORE) == before + 1 and worker.floor_i != 0 and worker.carrying < 0:
			break
		await _step_live()
	check(reservation_seen, "normal CharacterAI reserves a front-depth vein")
	check(main.storage.count_of(GameData.Item.IRON_ORE) == before + 1 and worker.floor_i != 0 and worker.carrying < 0, "normal Worker gathers, moves through the strip, uses the existing ramp and unloads")
	check(main.operations.delivered.get(GameData.Item.IRON_ORE, 0) == 1, "normal FieldOperations receives returned gather cargo")
	var depth_span := 0.0
	if not mid_depth_xs.is_empty():
		depth_span = mid_depth_xs.max() - mid_depth_xs.min()
	check(mid_depth_seen and depth_span > 30.0, "depth changes at multiple X positions, not at a fixed crossing")
	check(not main.get_meta("ground_depth_strip_config").has("crossing_x"), "depth strip config contains no crossing or bridge point")


func _combat_return_and_selection() -> void:
	await fresh()
	_configure_depth_strip()
	var worker = main.workers[0]
	var back_worker = main.workers[1]
	var front_worker = main.workers[2]
	worker.floor_i = 0
	worker.position = Vector2(930.0, BACK_Y)
	worker.target = worker.position
	back_worker.floor_i = 0
	back_worker.position = Vector2(780.0, BACK_Y)
	front_worker.floor_i = 0
	front_worker.position = Vector2(780.0, FRONT_Y)
	var enemy := Enemy.new()
	enemy.setup(main, 120.0)
	enemy.position = Vector2(930.0, FRONT_Y)
	main.enemies_root.add_child(enemy)
	var full_hp: float = enemy.hp
	check(main._pick_worker_at(Vector2(780.0, BACK_Y)) == back_worker and main._pick_worker_at(Vector2(780.0, FRONT_Y)) == front_worker, "same-X back/front workers are chosen by visible depth")
	var tracker := Enemy.new()
	tracker.setup_kind(main, "dust_guard")
	tracker.ecological = true
	tracker.position = Vector2(850.0, BACK_Y)
	tracker.home_x = tracker.position.x
	tracker.target_index = main.workers.find(front_worker)
	main.enemies_root.add_child(tracker)
	tracker._process(0.2)
	check(tracker.position.y > BACK_Y and tracker.position.y < FRONT_Y, "ecological pursuit enters the target depth at its current X instead of a fixed crossing")
	check(worker.ai.order_attack(enemy), "normal CharacterAI accepts a cross-depth attack order")
	await _step_live()
	var started_through_depth: bool = worker.position.y > BACK_Y + 2.0 and worker.position.y < FRONT_Y - 2.0
	check(is_equal_approx(enemy.hp, full_hp) and worker.ai.state == CharacterAI.State.COMBAT_MOVE and started_through_depth, "same-X opponent is not hit before closing depth distance")
	var hit := await _until_live(func(): return enemy.hp < full_hp, 20.0)
	check(hit and worker.position.distance_to(enemy.position) <= 46.0, "melee hit uses physical distance after direct depth travel")
	var hp_after_first_hit: float = enemy.hp
	check(worker.ai.request_return(), "individual return can be requested during depth-strip combat")
	var return_mid_depth_seen := false
	var returned := false
	for _frame in 150:
		return_mid_depth_seen = _sample_depth_motion(worker, []) or return_mid_depth_seen
		if worker.floor_i != 0 and worker.ai.return_request and worker.ai.state == CharacterAI.State.RETURN_BASE:
			returned = true
			break
		await _step_live()
	check(returned and return_mid_depth_seen, "individual return crosses the continuous strip then uses the existing base ramp")
	for _frame in 8:
		await _step_live()
	check(is_equal_approx(enemy.hp, hp_after_first_hit) and not worker.ai.manual_attack and worker.ai.return_request, "individual return does not resume combat or gathering")


func _viewport_hud_selection() -> void:
	await fresh()
	_configure_depth_strip()
	var back_worker = main.workers[1]
	var front_worker = main.workers[2]
	for worker in [back_worker, front_worker]:
		worker.stop_work()
		worker.floor_i = 0
		worker.target = worker.position
	back_worker.position = Vector2(780.0, BACK_Y)
	front_worker.position = Vector2(780.0, FRONT_Y)
	main._select(back_worker)
	var hud_rect: Rect2 = main.navigation.bar.get_global_rect()
	check(front_worker.position.y + 6.0 < hud_rect.position.y, "front anchor and feet remain above the 720p navigation bar")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	# InputEvent coordinates are viewport/screen coordinates; choose a point in
	# the front sprite and transform the intended world click through the camera.
	click.position = main.get_canvas_transform() * Vector2(front_worker.position.x, front_worker.position.y - 18.0)
	click.global_position = click.position
	# fresh() pauses gameplay processing for deterministic tests. Re-enable this
	# scene briefly so Viewport routing reaches _unhandled_input normally.
	main.process_mode = Node.PROCESS_MODE_INHERIT
	main.get_viewport().push_input(click, true)
	await process_frame
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	check(main.follow_target == front_worker, "Viewport left-click selects the front worker without direct _pick_worker_at use")
