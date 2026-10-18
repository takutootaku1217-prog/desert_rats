extends "res://tools/test_quarry.gd"
## 独立表示モデルではなく、既存Main / Worker / CharacterAIを使う固定2レーンの最小接続試験。

const BACK_Y := 600.0
const FRONT_Y := 680.0
const CROSSING_X := 820.0


func _configure_fixed_lanes() -> void:
	main.set_meta("ground_lane_config", {
		"enabled": true,
		"back_y": BACK_Y,
		"front_y": FRONT_Y,
		"crossing_x": CROSSING_X,
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


func _flat_crossing_seen(worker, required_crossings: int) -> bool:
	return worker.ground_lane_crossings >= required_crossings and is_equal_approx(worker.ground_lane_last_crossing_x, CROSSING_X)


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
	point.position = Vector2(1140.0, FRONT_Y)
	main.resources_root.add_child(point)
	return point


func _initialize() -> void:
	print("-- 固定2レーン: 既存Worker/CharacterAI接続 --")
	await _gather_and_haul()
	await _combat_and_personal_return()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d件失敗" % fails))
	quit(1 if fails else 0)


func _gather_and_haul() -> void:
	await fresh()
	_configure_fixed_lanes()
	var worker = main.workers[0]
	worker.tools = {"mine": GameData.Item.HAMMER}
	worker.priorities[GameData.Job.GATHER] = 5
	var point := _add_front_vein()
	var before: int = main.storage.count_of(GameData.Item.IRON_ORE)
	var reservation_seen := false
	for _frame in 60:
		reservation_seen = reservation_seen or (point.claimed_by == worker and point.reserved >= 1)
		if reservation_seen:
			break
		await _step_live()
	check(reservation_seen, "既存CharacterAIが手前レーンの鉱脈を予約する")
	var stored := await _until_live(func(): return main.storage.count_of(GameData.Item.IRON_ORE) == before + 1 and worker.floor_i != 0 and worker.carrying < 0, 60.0)
	check(stored, "既存Workerが採取・在庫搬送・拠点スロープ帰還・荷卸しまで完走する")
	check(main.operations.delivered.get(GameData.Item.IRON_ORE, 0) == 1, "既存FieldOperationsの持帰り集計に採取物が入る")
	check(_flat_crossing_seen(worker, 2), "往復とも固定Xの平地横断路だけでレーンを移る")


func _combat_and_personal_return() -> void:
	await fresh()
	_configure_fixed_lanes()
	var worker = main.workers[0]
	worker.floor_i = 0
	worker.position = Vector2(930.0, BACK_Y)
	worker.target = worker.position
	var enemy := Enemy.new()
	enemy.setup(main, 120.0)
	enemy.position = Vector2(930.0, FRONT_Y)
	main.enemies_root.add_child(enemy)
	var full_hp: float = enemy.hp
	check(worker.ai.order_attack(enemy), "既存CharacterAIが別レーンの敵を追跡指示として受ける")
	for _frame in 4:
		await _step_live()
	check(is_equal_approx(enemy.hp, full_hp) and worker.ai.state == CharacterAI.State.COMBAT_MOVE, "同じXでも別レーンへの近接攻撃は即時命中しない")
	var hit := await _until_live(func(): return enemy.hp < full_hp, 20.0)
	check(hit and _flat_crossing_seen(worker, 1), "実CharacterAIは横断路を通ってから近接攻撃する")
	var hp_after_first_hit: float = enemy.hp
	check(worker.ai.request_return(), "既存Workerへ個人退却を指示できる")
	var returned := await _until_live(func(): return worker.floor_i != 0 and worker.ai.return_request and worker.ai.state == CharacterAI.State.RETURN_BASE, 30.0)
	check(returned and _flat_crossing_seen(worker, 2), "個人退却は平地横断路と既存拠点スロープを経由する")
	for _frame in 8:
		await _step_live()
	check(is_equal_approx(enemy.hp, hp_after_first_hit) and not worker.ai.manual_attack and worker.ai.return_request, "個人退却中に既存AIが再攻撃・再採取へ戻らない")
