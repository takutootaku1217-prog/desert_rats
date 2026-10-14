extends SceneTree
## 地点の移動・有限残量・帰還は製品の状態機械。量/疲労/満載の注入は境界条件用。
var main
var fails := 0
func check(ok: bool, msg: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", msg])
	if not ok: fails += 1

func fresh(all_facilities := false) -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = all_facilities
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	seed(951)
	main.director.enabled = false
	if "rear" in OS.get_cmdline_user_args():
		main.room_layout = Rooms.with_room(main.room_layout, "u3", "workshop")
		main.room_layout = Rooms.with_room(main.room_layout, "l3", "storage")
		main.base.apply_layout()
	for w in main.workers:
		w.stop_work()
		for j in GameData.job_list(): w.priorities[j] = 0
	for k in main.hunt_policy: main.hunt_policy[k] = false

func step() -> void:
	main._process(0.2)
	for r in main.resources_root.get_children():
		if not r.is_queued_for_deletion(): r._process(0.2)
	for c in main.creatures_root.get_children():
		if not c.is_queued_for_deletion(): c._process(0.2)
	for w in main.workers: w._process(0.2)
	await process_frame

func until(done: Callable, seconds: float) -> bool:
	for i in ceili(seconds / 0.2):
		if done.call(): return true
		await step()
	return done.call()

func park_fixture() -> void:
	main.quarry.select()
	main.quarry.left = 0.0
	main.quarry.tick(0.0)

func _initialize() -> void:
	await flow()
	await capacity()
	await life_and_safety()
	await hauling()
	await stay()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)

func flow() -> void:
	print("-- 目的地→移動→停車採取→帰還→街道→再訪")
	await fresh()
	var q = main.quarry
	check(q.select() and not q.select(), "目的地選択の連打で残量・移動を二重作成しない")
	check(q.cancel() and not q.cancel() and q.visits == 0, "途中キャンセルは地点を生成しない")
	q.select()
	var f0: float = main.base.fuel
	check(await until(func(): return q.state == "parked", 50), "実走行して地点で停車")
	check(main.director.distance >= QuarryDB.TRAVEL_DISTANCE and main.base.fuel < f0, "移動距離と燃料を払う")
	check(q.points.size() == 4 and q.group_left("近場") == 12 and q.group_left("奥") == 72, "固定の近場小群と奥の密集群")
	main.target_speed = 200
	await step()
	check(main.scroll_speed == 0.0, "速度キーを変えても滞在中は走り出さない")
	# カメラを右へ寄せても、地点の残量は画面外だからという理由で消えない。
	main.camera.position.x = 1000
	for p in q.points: p._process(1.0)
	check(q.points.all(func(p): return not p.is_queued_for_deletion()), "カメラ移動で奥の鉱床が消えない")
	main.camera.position.x = 0
	var w = main.workers[0]
	w.priorities[GameData.Job.GATHER] = 5
	w.priorities[GameData.Job.HAUL] = 3
	w.priorities[GameData.Job.PROCESS] = 3
	main.gather_policy = {GameData.Item.IRON_ORE: 5, GameData.Item.WOOD: 0, GameData.Item.STONE: 0}
	w.tools = {"mine": GameData.Item.HAMMER}
	main.tool_auto = false
	check(await until(func(): return q.group_left("近場") == 0, 200), "既存AIが近場を有限量まで採掘する")
	check(q.group_left("奥") == 72, "近場のみなら奥には着手しない")
	check(await until(func(): return main.storage.count_of(GameData.Item.IRON) > 1, 120), "採った鉄鉱石を倉庫へ運び、既存精錬で鉄にする")
	q.near_only = false
	check(await until(func(): return w.ai.state == CharacterAI.State.GATHER and w.carrying >= 0, 200), "奥の鉱床で掘りかけの袋を作る")
	check(q.request_departure() and not q.request_departure(), "帰還指示の連打を拒否")
	await step()
	check(q.cancel() and q.state == "parked", "帰還途中でも取消できる")
	check(q.request_departure(), "再度帰還を依頼できる")
	check(await until(func(): return q.ready_to_leave(), 300), "全員・運搬中の袋が拠点へ戻る")
	check(main.workers.all(func(x): return x.floor_i != 0 and x.carrying < 0), "屋外や手持ちを残して出発しない")
	var left_near: int = q.group_left("近場")
	var left_far: int = q.group_left("奥")
	check(q.leave() and not q.leave(), "出発は一度だけ受理")
	check(await until(func(): return q.state == "road", 60), "街道復帰の移動も完了する")
	w.priorities[GameData.Job.GATHER] = 0
	q.select()
	check(await until(func(): return q.state == "parked", 60), "同じ1地点へ再訪できる")
	check(q.group_left("近場") == left_near and q.group_left("奥") == left_far, "枯渇・掘りかけの残量を復元し、出入りで増えない")
	check(q.points.size() == 4 and q.visits == 2, "再訪時のノード重複なし")
	main.quarry_ui.open()
	main.quarry_ui._refresh()
	check(main.quarry_ui._info.text.contains("食材は自動補充されません") and main.quarry_ui._recall.disabled == false, "UIは停車状態と供給の限界を表示")

func capacity() -> void:
	print("-- 満載・残置の回収・取消")
	await fresh()
	park_fixture()
	var q = main.quarry
	main.storage.inventory.counts.clear()
	main.storage.capacity_bonus = -CargoDB.CAPACITY
	# 保有済みの袋を容量0へ返すケースと、新規取得の残置を混同しない。
	main.storage.add_item(GameData.Item.IRON_ORE,3)
	main.storage.add_item(GameData.Item.STONE,1)
	q.request_departure()
	check(q.loose.get(GameData.Item.IRON_ORE,0) == 3 and q.loose.get(GameData.Item.STONE,0) == 1 and main.total_wasted == 0,
		"新規取得の収納不能分と副産物を残置へ保全")
	check(not q.ready_to_leave() and not q.leave() and q.status_text().contains("満載"), "残置がある間は明示して出発を止める")
	main.quarry_ui.open()
	main.quarry_ui._refresh()
	check(main.quarry_ui._info.text.contains("鉄鉱石×3") and main.quarry_ui._leave.disabled, "UIにも残置数量と出発不可を表示")
	check(q.cancel(), "満載の帰還を取消可能")
	main.storage.capacity_bonus = 0
	q.tick(0.0)
	check(q.loose.is_empty() and main.storage.count_of(GameData.Item.IRON_ORE) == 3 and main.storage.count_of(GameData.Item.STONE) == 1,
		"空きができたら残置を一度だけ回収")
	q.tick(0.0)
	check(main.storage.count_of(GameData.Item.IRON_ORE) == 3, "回収を繰り返しても増殖しない")
	q.request_departure()
	check(await until(func(): return q.ready_to_leave(), 100), "残置解消後に出発可能へ戻る")
	check(q.leave(), "満載から復帰して出発できる")

func life_and_safety() -> void:
	print("-- 停車中の消耗・生活・安全な入場")
	await fresh(true)
	var q = main.quarry
	main.director.trigger("raid_scorpion", true)
	q.select()
	q.left = 0.0
	q.tick(0.0)
	check(q.state == "approach" and q.status_text().contains("襲撃"), "街道の襲撃予報を安全地点へ持ち込まない")
	# 予報終了の境界を再現。既存戦闘そのものは別の診断。
	main.director.forecast.clear()
	main.director.trigger("raid_scorpion", false)
	q.tick(0.0)
	check(q.state == "approach" and main.enemies_root.get_child_count() > 0, "既にいる敵を消して安全を装わず、入場を待つ")
	# この境界診断だけは撃退完了を再現し、入場後の発生抑止へ進む。
	for e in main.enemies_root.get_children():
		main.enemies_root.remove_child(e)
		e.free()
	main.director.active.clear()
	q.tick(0.0)
	main.director.trigger("raid_scorpion", false)
	main.director.trigger("raid_scorpion", true)
	main.director._begin_timed("raid_scorpion")
	check(main.enemies_root.get_child_count() == 0 and not main.director._busy("attack"), "滞在中は即時・予報・発生経路の襲撃を抑止")
	main.director.distance = 100000
	var safe := true
	for i in 100:
		var id: String = main.director._pick()
		if id != "" and EventDB.def(id)["kind"] == "attack": safe = false
	check(safe, "滞在中の抽選にも襲撃を含めない")
	main.base.fuel = 100
	main.base.parts[GameData.Part.HULL] = 100
	main.base.parts[GameData.Part.DRIVE] = 100
	main._spawn_dist = 300
	main._creature_dist = 300
	var n: int = main.resources_root.get_child_count()
	main._process(10.0)
	check(main.resources_root.get_child_count() == n and main._spawn_dist == 300 and main._creature_dist == 300,
		"停車しても資源や生物は自動補充されない")
	check(main.base.fuel == 100 and main.base.parts[GameData.Part.DRIVE] == 100 and main.base.parts[GameData.Part.HULL] < 100,
		"停車中は移動燃料・車軸摩耗ゼロ、車体の時間消耗は続く")
	main.storage.inventory.counts.clear()
	var w = main.workers[0]
	w.position = Vector2(200, 630)
	w.floor_i = 0
	w.fatigue = 95
	w.hp = 40
	w.hunger = 10
	q.request_departure()
	check(await until(func(): return q.ready_to_leave(), 360), "食料不足・疲労・負傷でも既存休憩で回復して帰還できる")
	check(await until(func(): return w.hp >= 80 and w.fatigue <= 30, 200), "帰還後も休憩でHP・疲労を回復できる")
	check(w.hp >= 80 and w.fatigue <= 30 and w.hunger < 10, "帰還でHP/疲労を無償リセットせず、空腹も継続")
	main.storage.add_item(GameData.Item.FOOD, 1)
	var eaten: int = main.total_eaten
	check(await until(func(): return main.total_eaten > eaten, 30), "帰還待ちでも食事を実消費する")
	check(await until(func(): return q.ready_to_leave(), 50), "食事後も帰還完了へ戻る")
	q.leave()
	main.director.trigger("raid_scorpion", true)
	check(main.director._busy("attack"), "街道復帰中は元の襲撃経路を維持")

func hauling() -> void:
	print("-- 加工入力の運搬途中・出力取り出しの途中")
	await fresh()
	park_fixture()
	var q = main.quarry
	var w = main.workers[0]
	main.storage.inventory.counts.clear()
	main.storage.add_item(GameData.Item.MEAT, 1)
	for id in main.recipe_priority: main.recipe_priority[id] = 5 if id == "cook" else 0
	check(w.ai._try_start(GameData.Job.HAUL), "加工入力の運搬を開始")
	check(await until(func(): return w.ai.state == CharacterAI.State.HAUL_MOVE, 30), "材料を持った途中まで進む")
	q.request_departure()
	check(await until(func(): return q.ready_to_leave(), 60), "材料は加工設備まで届けてから集合")
	check(main.processor.incoming.is_empty() and main.processor.orders.size() == 1 and w.carrying < 0, "予約を重複・消失させず室内の注文として保持")
	q.cancel()
	w.priorities[GameData.Job.PROCESS] = 5
	check(await until(func(): return not main.processor.current.is_empty(), 30), "加工の途中まで進める")
	q.request_departure()
	check(await until(func(): return q.ready_to_leave(), 60), "加工中でも入力と進捗を残して担当が帰還")
	check(not main.processor.current.is_empty() and main.processor.worker == null, "加工を二重消費せず一時停止")
	q.cancel()
	check(await until(func(): return main.storage.count_of(GameData.Item.FOOD) == 2, 90), "取消後に加工が再開して出力2個を収納（無限待ちなし）")
	q.request_departure()
	check(await until(func(): return q.ready_to_leave(), 60), "再度の帰還でも予約を残さない")
	check(main.processor.worker == null and main.processor.incoming.is_empty(), "担当と入力予約が解放される")


func stay() -> void:
	print("-- 設備あり・初期備蓄で20ゲーム内分の滞在（出来事なし）")
	await fresh(true)
	# 採掘準備後の長期滞在fixture。新規開始は道具なしなので、ここでは明示して装備。
	main.workers[0].tools = {"mine": GameData.Item.HAMMER}
	park_fixture()
	main.quarry.near_only = false
	for i in main.workers.size():
		main.workers[i].priorities = main.WORKER_DEFS[i]["prio"].duplicate()
	var waited := 0.0
	var maximum := 0.0
	var sleep_seen := false
	var dist: float = main.director.distance
	var fuel: float = main.base.fuel
	var t0: float = main.director.elapsed
	while main.director.elapsed - t0 < 1200.0 and not main.game_over:
		await step()
		if not main.processor.output.is_empty() and main.processor.worker == null:
			waited += 0.2
			maximum = maxf(maximum, waited)
		else:
			waited = 0.0
		for w in main.workers:
			if w.sleeping or w.resting: sleep_seen = true
	print("  滞在: 出力担当不在最長 %.1f秒、食事%d、修理%d、加工%d、残量%d、残置%s" % [maximum, main.total_eaten, main.base.total_repair, main.processor.total_done, main.quarry.group_left("近場") + main.quarry.group_left("奥"), main.quarry.cargo_text()])
	check(not main.game_over and main.director.distance == dist, "20分間停車を維持して完走")
	check(main.total_eaten >= 3 and sleep_seen and main.base.total_repair > 0, "初期備蓄による食事・休憩・修理が続く")
	check(main.processor.total_done > 0 and main.base.fuel < fuel, "採取物を加工し、精錬の燃料は停車中も消費")
	check(maximum <= 60.0 and main.processor.output.is_empty(), "完成品は60秒以内に担当がつき、出力を取り残さない")
	var active_bags := 0
	for w in main.workers:
		if w.ai.state == CharacterAI.State.GATHER and w.carrying == GameData.Item.IRON_ORE: active_bags += w.carry_n
	check(main.quarry.group_left("近場") + main.quarry.group_left("奥") + main.total_gathered + active_bags == 84, "20分後も未採取残量+回収数=84（満載で止まっても資源を消さない）")
	main.quarry.request_departure()
	check(await until(func(): return main.quarry.ready_to_leave(), 300), "長居の後も全員帰還して出発できる")
