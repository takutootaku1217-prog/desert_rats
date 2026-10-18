extends "res://tools/test_quarry.gd"
## 通常 Main / Worker / CharacterAI に限定した、連続奥行き帯の小規模接続試験。
## 固定線・固定横断路ではない。通常マップ全体にはまだ展開しない。

const BACK_Y := 570.0
const FRONT_Y := 625.0


func _configure_depth_strip() -> void:
	main.set_meta("ground_depth_strip_config", {
		"enabled": true,
		"back_y": BACK_Y,
		"front_y": FRONT_Y,
	})
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
	if worker.position.y <= BACK_Y + 4.0 or worker.position.y >= FRONT_Y - 4.0:
		return false
	xs.append(worker.position.x)
	return true


func _initialize() -> void:
	print("-- continuous two-lane-width depth strip: live Main/AI --")
	await _gather_and_haul()
	await _combat_return_and_selection()
	print("== result: %s ==" % ("all passed" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)


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
