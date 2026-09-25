extends SceneTree
## 積載量（倉庫の容量）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_cargo.gd
## 表・枠・あふれ・割り当ての変更・回収と狩猟の判断・加工の判断・遠征の持ち帰り・画面・長時間の安定を確かめる。

var fails := 0
var main
var st: BaseStorage


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260926)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## 倉庫を空にして、割り当てを初期に戻す。出来事は止め、地面の資源も消す。
func _reset() -> void:
	main.director.enabled = false
	main.director.active.clear()
	main.director.forecast.clear()
	for w in main.workers:
		if w.away:
			w.arrive(100.0)
		w.ai._release_task()
		w.carrying = -1
		w.ai._set_state(CharacterAI.State.SEARCH)
	for root_node in [main.resources_root, main.creatures_root]:
		for c in root_node.get_children():
			root_node.remove_child(c)          # queue_free だと次のフレームまで残るので、すぐ消す
			c.free()
	st.enforce = true
	st.inventory.counts.clear()
	st.quota = CargoDB.default_quota()
	st.capacity_bonus.clear()
	st.wasted.clear()
	main.total_wasted = 0
	main.processor.orders.clear()
	main.processor.incoming.clear()
	main.processor.current = {}
	main.processor.output.clear()


func _drop_resource(item: int, x := 600.0) -> ResourceNode:
	var r := ResourceNode.new()
	r.game = main
	r.item = item
	r.position = Vector2(x, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.resources_root.add_child(r)
	return r


func _run() -> void:
	st = main.storage
	var W: Array = main.workers
	_reset()

	print("== 表の整合 ==")
	for bay in [CargoDB.Bay.RAW, CargoDB.Bay.PRODUCT]:
		var sum := 0
		var all_have := true
		for it in CargoDB.items_of(bay):
			sum += int(CargoDB.DEFAULT_QUOTA.get(it, -1)) * CargoDB.size_of(it)
			if not CargoDB.DEFAULT_QUOTA.has(it):
				all_have = false
		check(all_have, "%s の全素材に初期の枠がある" % CargoDB.BAY_NAMES[bay])
		check(sum == CargoDB.CAPACITY[bay], "%s: 枠の合計 %d = 積載量 %d" % [CargoDB.BAY_NAMES[bay], sum, CargoDB.CAPACITY[bay]])
	check(CargoDB.bay_of(GameData.Item.CARCASS) < 0 and CargoDB.bay_of(GameData.Item.WOOD) == CargoDB.Bay.RAW
			and CargoDB.bay_of(GameData.Item.FOOD) == CargoDB.Bay.PRODUCT, "獲物は倉庫に置かない。素材は素材棚、加工品は加工品置き場")
	check(st.unallocated_in(CargoDB.Bay.RAW) == 0 and st.unallocated_in(CargoDB.Bay.PRODUCT) == 0, "最初は積載量をすべて割り当て済み")

	print("== 容量の上限と、あふれたときの挙動 ==")
	_reset()
	var signals := []
	st.overflowed.connect(func(item, n): signals.append([item, n]))
	var wq: int = st.quota_of(GameData.Item.WOOD)
	check(st.add_item(GameData.Item.WOOD, wq) == wq and st.count_of(GameData.Item.WOOD) == wq, "枠（%d）までは入る" % wq)
	check(st.is_full(GameData.Item.WOOD) and st.free_for(GameData.Item.WOOD) == 0, "枠がいっぱいになる")
	var got: int = st.add_item(GameData.Item.WOOD, 3)
	check(got == 0 and st.count_of(GameData.Item.WOOD) == wq, "いっぱいのときは入らない（入った数 %d）" % got)
	check(st.wasted.get(GameData.Item.WOOD, 0) == 3 and main.total_wasted == 3 and signals.size() == 1, "入りきらない分は捨てられ、数と通知が残る")
	_reset()
	st.add_item(GameData.Item.STONE, st.quota_of(GameData.Item.STONE) - 1)
	check(st.add_item(GameData.Item.STONE, 3) == 1 and main.total_wasted == 2, "あと1個の空きに3個入れると、1個入って2個捨てる")
	# 区画が別なので、素材棚がいっぱいでも加工品は置ける（食料・燃料が置けなくなって詰まらない）
	_reset()
	for it in GameData.RAW_ITEMS:
		st.add_item(it, 99)
	check(st.used_in(CargoDB.Bay.RAW) == CargoDB.CAPACITY[CargoDB.Bay.RAW], "素材棚を満杯にできる（%d/%d）" % [st.used_in(CargoDB.Bay.RAW), CargoDB.CAPACITY[CargoDB.Bay.RAW]])
	check(st.add_item(GameData.Item.FOOD, 1) == 1 and st.add_item(GameData.Item.FUEL, 1) == 1, "素材棚が満杯でも、食料・燃料は置ける")
	# 制限なしのモード（自己診断・将来の拡張用）
	_reset()
	st.enforce = false
	check(st.add_item(GameData.Item.WOOD, 500) == 500 and main.total_wasted == 0, "enforce=false なら制限なし")
	st.enforce = true

	print("== 割り当ての変更 ==")
	_reset()
	var raw := CargoDB.Bay.RAW
	check(st.set_quota(GameData.Item.MEAT, st.quota_of(GameData.Item.MEAT) + 4) == 10, "余りがないときは、枠を増やせない")
	st.set_quota(GameData.Item.WOOD, st.quota_of(GameData.Item.WOOD) - 4)
	check(st.quota_of(GameData.Item.WOOD) == 10 and st.unallocated_in(raw) == 4, "木材の枠を減らすと、割り当てていない積載量が増える")
	check(st.set_quota(GameData.Item.MEAT, 10 + 6) == 14, "余り（4）の分だけ、肉の枠を増やせる")
	check(st.unallocated_in(raw) == 0 and st.allocated_in(raw) == CargoDB.CAPACITY[raw], "枠の合計が積載量を超えない")
	st.set_quota(GameData.Item.MEAT, -5)
	check(st.quota_of(GameData.Item.MEAT) == 0, "枠は0（集めない）まで減らせる")
	# 枠を減らしても、いま置いてある分は消えない（新しく入らないだけ）
	_reset()
	st.add_item(GameData.Item.HIDE, 6)
	st.set_quota(GameData.Item.HIDE, 2)
	check(st.count_of(GameData.Item.HIDE) == 6 and st.free_for(GameData.Item.HIDE) == 0 and st.add_item(GameData.Item.HIDE, 1) == 0,
			"枠を減らしても、置いてある分は消えず、新しくは入らない")
	# 積載量の増加（将来の拠点強化）
	_reset()
	st.capacity_bonus[raw] = 10
	check(st.capacity_of(raw) == CargoDB.CAPACITY[raw] + 10 and st.unallocated_in(raw) == 10, "積載量が増えると、割り当てられる量が増える（将来の拠点強化）")
	check(st.set_quota(GameData.Item.STONE, st.quota_of(GameData.Item.STONE) + 10) == 18, "増えた分を枠に割り当てられる")

	print("== 解体（獲物）と狩り ==")
	_reset()
	check(st.drop_fit("hump") == 1.0 and main.hunt_has_room("hump"), "空いていれば、獲物の素材はすべて入る")
	st.add_item(GameData.Item.MEAT, 10)
	st.add_item(GameData.Item.FAT, 8)
	# コブ獣: 肉2 脂2 皮1 骨1 → 皮と骨だけ入る（2/6）
	check(st.drop_fit("hump") < CargoDB.MIN_DROP_FIT and not main.hunt_has_room("hump"), "素材の大半が入らない獲物は狩らない（入る割合 %.0f%%）" % (st.drop_fit("hump") * 100.0))
	check(main.hunt_has_room("hare"), "ウサギ（肉1・皮1）は皮が入るので狩る（入る割合 %.0f%%）" % (st.drop_fit("hare") * 100.0))
	var c := Creature.new()
	c.setup(main, "hump")
	c.position = Vector2(700, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.creatures_root.add_child(c)
	main.hunt_policy["hump"] = true
	check(not W[1].ai._try_start(GameData.Job.HUNT), "枠がいっぱいのときは、狩猟の仕事に入らない")
	st.inventory.counts[GameData.Item.MEAT] = 0
	st.inventory.counts[GameData.Item.FAT] = 0
	check(W[1].ai._try_start(GameData.Job.HUNT), "空きができたら、狩猟の仕事に入る")
	W[1].ai._release_task()
	W[1].ai._set_state(CharacterAI.State.SEARCH)
	c.queue_free()
	# 解体で、入る分だけ入って残りは捨てる
	_reset()
	st.add_item(GameData.Item.MEAT, 9)
	st.butcher("hump")
	check(st.count_of(GameData.Item.MEAT) == 10 and st.count_of(GameData.Item.FAT) == 2 and st.count_of(GameData.Item.HIDE) == 1
			and st.wasted.get(GameData.Item.MEAT, 0) == 1, "解体: 入る分だけ入り、あふれた肉1個は捨てる")

	print("== 回収の判断（回収AIへの影響） ==")
	_reset()
	var wood := _drop_resource(GameData.Item.WOOD)
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == wood, "空きがあれば、木材を回収しに行く")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	st.add_item(GameData.Item.WOOD, st.quota_of(GameData.Item.WOOD))
	check(not W[0].ai._try_start(GameData.Job.GATHER), "枠がいっぱいの木材は、拾いに行かない")
	# 別の素材があれば、そちらを拾う
	var stone := _drop_resource(GameData.Item.STONE, 700.0)
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == stone, "木材がいっぱいでも、空きのある石は拾う")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 残り1個の枠に、同時に2人が向かわない（運んでいる分も数える）
	_reset()
	st.add_item(GameData.Item.IRON_ORE, st.quota_of(GameData.Item.IRON_ORE) - 1)
	_drop_resource(GameData.Item.IRON_ORE, 600.0)
	_drop_resource(GameData.Item.IRON_ORE, 640.0)
	var a1: bool = W[0].ai._try_start(GameData.Job.GATHER)
	var a2: bool = W[1].ai._try_start(GameData.Job.GATHER)
	check(a1 and not a2, "残り1個の枠には、2人目は向かわない（1人目 %s・2人目 %s）" % [a1, a2])
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 運んでいる最中の分も、枠を予約している
	W[2].carrying = GameData.Item.IRON_ORE
	W[2].ai._set_state(CharacterAI.State.MOVE_TO_STORAGE)
	check(not W[0].ai._try_start(GameData.Job.GATHER), "運んでいる途中の分も、空き枠として数える")
	W[2].carrying = -1
	W[2].ai._set_state(CharacterAI.State.SEARCH)
	# 方針にない物（敵が落とした肉・皮）も拾える（以前は方針にないため拾われなかった）
	_reset()
	var meat := _drop_resource(GameData.Item.MEAT)
	check(main.gather_weight(GameData.Item.MEAT) > 0.0 and W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == meat,
			"敵が落とした肉は、方針になくても拾いに行く")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 獲物（地面に残った獲物）: 入らないときは拾わない
	_reset()
	var carcass := ResourceNode.new()
	carcass.game = main
	carcass.item = GameData.Item.CARCASS
	carcass.species = "hump"
	carcass.position = Vector2(650, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.resources_root.add_child(carcass)
	st.add_item(GameData.Item.MEAT, 10)
	st.add_item(GameData.Item.FAT, 8)
	check(not W[0].ai._try_start(GameData.Job.GATHER), "素材の入らない獲物は、拾わない")
	carcass.queue_free()

	print("== 運搬・加工・保管への影響 ==")
	_reset()
	# 作り置きの目標より大きな枠は使わない。枠が小さければ枠に合わせる
	st.add_item(GameData.Item.MEAT, 5)
	main.recipe_priority = GameData.DEFAULT_RECIPE_PRIORITY.duplicate()
	var r1: Dictionary = main.choose_recipe()
	check(r1.get("id", "") == "cook", "材料があり枠に余裕があれば、加工を選ぶ（%s）" % r1.get("id", "なし"))
	st.set_quota(GameData.Item.FOOD, 1)
	var r2: Dictionary = main.choose_recipe()
	check(r2.get("id", "") != "cook", "食料の枠が小さくて2個入らないなら、調理は選ばない")
	st.set_quota(GameData.Item.FOOD, 0)
	st.inventory.counts[GameData.Item.FOOD] = 0
	check(main.choose_recipe().get("id", "") != "cook", "食料の枠が0なら、調理は選ばない")
	# 枠が作り置きの目標（食料12）より大きくても、目標で止まる（従来どおり）
	_reset()
	st.add_item(GameData.Item.MEAT, 5)
	st.add_item(GameData.Item.FOOD, 12)
	check(main.choose_recipe().get("id", "") != "cook", "作り置きの目標（食料12）に届いたら、枠が余っていても作らない")
	# 加工品は素材棚の使用量に関係なく置ける（詰み防止）
	_reset()
	for it in GameData.RAW_ITEMS:
		st.add_item(it, 99)
	main.processor.output.append(GameData.Item.FUEL)
	W[2].carrying = main.processor.take_output()
	W[2].ai._set_state(CharacterAI.State.STORE)
	W[2].ai.timer = 0.0
	W[2].ai.tick(0.1)
	check(st.count_of(GameData.Item.FUEL) == 1 and W[2].carrying == -1, "素材棚が満杯でも、加工した燃料は倉庫に入る")
	# 加工品置き場がいっぱいのとき、運んできた完成品は捨てる（詰まらない）
	_reset()
	st.add_item(GameData.Item.FUEL, 99)
	main.total_wasted = 0
	W[2].carrying = GameData.Item.FUEL
	W[2].ai._set_state(CharacterAI.State.STORE)
	W[2].ai.timer = 0.0
	W[2].ai.tick(0.1)
	check(W[2].carrying == -1 and st.count_of(GameData.Item.FUEL) == st.quota_of(GameData.Item.FUEL) and main.total_wasted == 1,
			"いっぱいのときに届いた完成品は捨てられ、仲間は次の仕事へ戻る")
	W[2].ai._set_state(CharacterAI.State.SEARCH)
	# 運搬（材料を倉庫から取り出す）は、枠に影響されない
	_reset()
	st.add_item(GameData.Item.WOOD, st.quota_of(GameData.Item.WOOD))
	var fw: Dictionary = GameData.recipe_by_id("firewood")
	check(st.take_set(fw["in"]) and st.count_of(GameData.Item.WOOD) == st.quota_of(GameData.Item.WOOD) - 1, "材料の取り出し（運搬）は、いっぱいでも普通にできる")
	st.add_item(GameData.Item.WOOD, 1)
	check(st.count_of(GameData.Item.WOOD) == st.quota_of(GameData.Item.WOOD), "取り出して空いた枠は、また使える")

	print("== 遠征の持ち帰り ==")
	_reset()
	st.add_item(GameData.Item.FOOD, 6)
	st.add_item(GameData.Item.IRON, st.quota_of(GameData.Item.IRON))
	var ex: Expedition = main.expedition
	ex.state = "idle"
	ex.offer("ruins_large")
	ex.loot.clear()
	ex.loot[GameData.Item.IRON] = 5
	ex.loot[GameData.Item.FUEL] = 3
	ex.party = [W[0]]
	W[0].depart()
	ex.energy = {W[0]: 50.0}
	ex.steps = ["explore"]
	ex.ok_count = 1
	ex.retreated = true                 # 踏破のおまけ（追加の戦利品）を出さず、持ち帰りだけを確かめる
	ex._finish()
	check(st.count_of(GameData.Item.IRON) == st.quota_of(GameData.Item.IRON) and ex.lost.get(GameData.Item.IRON, 0) == 5,
			"戦利品が枠に入りきらないときは持ち帰れない（鉄%d個を諦めた）" % ex.lost.get(GameData.Item.IRON, 0))
	check(ex.loot.get(GameData.Item.FUEL, 0) == 3 and st.count_of(GameData.Item.FUEL) == 3, "入る分（燃料3）は持ち帰れる")
	check(ex.summary().contains("持ち帰れず"), "結果の文に、持ち帰れなかった分が出る: " + ex.summary())
	ex.state = "idle"
	W[0].arrive(80.0) if W[0].away else null

	print("== 画面 ==")
	_reset()
	var pol: PolicyUI = main.policy
	pol.toggle()
	for page in [0, 1]:
		pol._page = page
		pol._rebuild()
	check(pol._page == 1, "運営の方針の画面に「積載の割り当て」のページが出る")
	pol._page = 1
	# ＋／－のボタン相当の操作
	st.set_quota(GameData.Item.WOOD, 8)
	pol._rebuild()
	pol.toggle()
	pol._page = 0
	main.status._process(0.0)
	check(main.status._cargo.text.begins_with("積載 素材棚"), "右上の状態に積載量が出る: " + main.status._cargo.text)
	st.add_item(GameData.Item.WOOD, 99)
	main.status._process(0.0)
	check(main.status._stock.text.contains("木%s満" % 8), "枠がいっぱいの素材に「満」が付く: " + main.status._stock.text.replace("\n", " / "))
	st.queue_redraw()
	await process_frame

	print("== 長く動かす（ゲーム内約8分。放置） ==")
	_reset()
	st.add_item(GameData.Item.FOOD, 8)
	st.add_item(GameData.Item.FUEL, 2)
	st.add_item(GameData.Item.REPAIR_KIT, 2)
	main.director.enabled = true
	Engine.time_scale = 8.0
	var t_end := Time.get_ticks_msec() + 60000
	var over_quota := 0
	var max_raw := 0
	var max_prod := 0
	var hungry_t := 0.0
	var last := Time.get_ticks_msec()
	while Time.get_ticks_msec() < t_end and not main.game_over:
		await process_frame
		var now := Time.get_ticks_msec()
		if main.hungry:
			hungry_t += float(now - last) / 1000.0 * 8.0
		last = now
		for it in st.quota:
			if st.count_of(it) > st.quota_of(it):
				over_quota += 1
		max_raw = maxi(max_raw, st.used_in(raw))
		max_prod = maxi(max_prod, st.used_in(CargoDB.Bay.PRODUCT))
	Engine.time_scale = 1.0
	paused = false
	print("       走行 %.1f km・回収%d 狩猟%d 加工%d・捨てた%d・空腹 %d秒・素材棚 最大 %d/%d 加工品 最大 %d/%d" % [
			main.director.distance / 2500.0, main.total_gathered, main.total_hunted, main.processor.total_done, main.total_wasted,
			int(hungry_t), max_raw, st.capacity_of(raw), max_prod, st.capacity_of(CargoDB.Bay.PRODUCT)])
	check(over_quota == 0, "どの素材も、枠を超えて置かれなかった")
	check(max_raw <= st.capacity_of(raw) and max_prod <= st.capacity_of(CargoDB.Bay.PRODUCT), "区画の積載量を超えなかった")
	check(main.total_gathered > 5 and main.processor.total_done > 2, "積載量があっても、回収と加工は回り続ける")
	if main.game_over:
		print("       （途中で車体が壊れてゲームオーバーになった。出来事を本来の頻度で起こしているため）")
