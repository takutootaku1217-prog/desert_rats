extends SceneTree
## 積載量（倉庫の容量。重量制）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_cargo.gd
## 表・あふれ・拠点の強化・回収と狩猟の判断・加工の判断・遠征の持ち帰り・画面・長時間の安定を確かめる。
## 2026-09-30: 素材ごとの「枠」を割り当てる方式から、拠点全体の「重さ」1本で管理する方式（ARK風）に作り替えた
## （data/cargo.gd）。それに合わせて自己診断も作り直した。

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
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## 倉庫を空にして、積載量を初期に戻す。出来事は止め、地面の資源も消す。
func _reset() -> void:
	main.director.enabled = false
	main.director.active.clear()
	main.director.forecast.clear()
	main.scroll_speed = 0.0                    # 世界を止めて、回収の「選び方」だけを確かめる（追いつけるかは test_gather.gd で）
	for w in main.workers:
		if w.away:
			w.arrive(0.0)
		w.ai._release_task()
		w.carrying = -1
		w.ai._set_state(CharacterAI.State.SEARCH)
	for root_node in [main.resources_root, main.creatures_root]:
		for c in root_node.get_children():
			root_node.remove_child(c)          # queue_free だと次のフレームまで残るので、すぐ消す
			c.free()
	st.enforce = true
	st.inventory.counts.clear()
	st.capacity_bonus = 0
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
	for it in GameData.RAW_ITEMS + GameData.PRODUCT_ITEMS:
		check(CargoDB.SIZES.has(it) and CargoDB.size_of(it) > 0, "%s に重さが決まっている（%d）" % [GameData.ITEM_NAMES[it], CargoDB.size_of(it)])
	check(CargoDB.bay_of(GameData.Item.CARCASS) < 0 and CargoDB.bay_of(GameData.Item.WOOD) == CargoDB.Bay.RAW
			and CargoDB.bay_of(GameData.Item.FOOD) == CargoDB.Bay.PRODUCT, "獲物は倉庫に置かない。素材は素材棚、加工品は加工品置き場（表示の区分だけ）")
	check(CargoDB.bay_of(GameData.Item.HAMMER) < 0, "道具は積載量の対象外（従来どおり）")
	check(CargoDB.CAPACITY > 0 and st.max_weight() == CargoDB.CAPACITY, "拠点全体の基本の積載量が決まっている（%d）" % CargoDB.CAPACITY)

	print("== 積載量の上限と、あふれたときの挙動 ==")
	_reset()
	var signals := []
	st.overflowed.connect(func(item, n): signals.append([item, n]))
	var wq: int = st.quota_of(GameData.Item.WOOD)
	check(st.add_item(GameData.Item.WOOD, wq) == wq and st.count_of(GameData.Item.WOOD) == wq, "積める分（%d）までは入る" % wq)
	check(st.is_full(GameData.Item.WOOD) and st.free_for(GameData.Item.WOOD) == 0, "積載量がいっぱいになる")
	var got: int = st.add_item(GameData.Item.WOOD, 3)
	check(got == 0 and st.count_of(GameData.Item.WOOD) == wq, "いっぱいのときは入らない（入った数 %d）" % got)
	check(st.wasted.get(GameData.Item.WOOD, 0) == 3 and main.total_wasted == 3 and signals.size() == 1, "入りきらない分は捨てられ、数と通知が残る")
	_reset()
	st.add_item(GameData.Item.STONE, st.quota_of(GameData.Item.STONE) - 1)
	check(st.add_item(GameData.Item.STONE, 3) == 1 and main.total_wasted == 2, "あと1個ぶんの重さに3個入れると、1個入って2個捨てる")
	# 拠点全体の重さ1本で管理するため、素材棚だけでも積載量を使い切れる（以前の「区画が別」とは違う。ARK風）
	_reset()
	for it in GameData.RAW_ITEMS:
		st.add_item(it, 99)
	check(st.current_weight() == st.max_weight(), "素材棚の素材だけでも、拠点全体の積載量を使い切れる（%d/%d）" % [st.current_weight(), st.max_weight()])
	check(st.add_item(GameData.Item.FOOD, 1) == 0 and st.add_item(GameData.Item.FUEL, 1) == 0,
			"積載量を使い切ると、原因が素材棚でも、食料・燃料はもう置けない（区画で分けていた頃と違う。重い素材を積みすぎない判断が要る）")
	# 制限なしのモード（自己診断・将来の拡張用）
	_reset()
	st.enforce = false
	check(st.add_item(GameData.Item.WOOD, 500) == 500 and main.total_wasted == 0, "enforce=false なら制限なし")
	st.enforce = true

	print("== 拠点の強化（荷台の増設など。capacity_bonus） ==")
	_reset()
	check(st.free_for(GameData.Item.WOOD) == CargoDB.CAPACITY / CargoDB.size_of(GameData.Item.WOOD), "最初は基本の積載量ぶんだけ置ける")
	st.capacity_bonus = 60
	check(st.max_weight() == CargoDB.CAPACITY + 60, "capacity_bonus が増えると、最大の重さが増える（荷台の増設。data/facilities.gd の cargo_rack）")
	check(st.free_for(GameData.Item.WOOD) == (CargoDB.CAPACITY + 60) / CargoDB.size_of(GameData.Item.WOOD), "増えた分だけ、置ける量も増える")
	st.capacity_bonus = 0

	print("== 解体（獲物）と狩り ==")
	_reset()
	check(st.drop_fit("hump") == 1.0 and main.hunt_has_room("hump"), "空いていれば、獲物の素材はすべて入る")
	st.add_item(GameData.Item.FOOD, st.free_for(GameData.Item.FOOD))     # 拠点全体の重さをちょうど使い切る
	check(st.drop_fit("hump") == 0.0 and not main.hunt_has_room("hump") and not main.hunt_has_room("hare"),
			"積載量がいっぱいだと、獲物の素材はまったく入らないので、大小どちらの獲物も狩らない")
	var c := Creature.new()
	c.setup(main, "hump")
	c.position = Vector2(700, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.creatures_root.add_child(c)
	main.hunt_policy["hump"] = true
	check(not W[1].ai._try_start(GameData.Job.HUNT), "積載量がいっぱいのときは、狩猟の仕事に入らない")
	st.inventory.counts[GameData.Item.FOOD] = 0                          # 空ける
	check(st.drop_fit("hump") == 1.0 and W[1].ai._try_start(GameData.Job.HUNT), "空きができたら、狩猟の仕事に入る")
	W[1].ai._release_task()
	W[1].ai._set_state(CharacterAI.State.SEARCH)
	c.queue_free()
	# 解体で、入る分だけ入って残りは捨てる（この場面だけ最大の重さを絞って、あふれの計算をわかりやすくする）
	_reset()
	st.capacity_bonus = -(CargoDB.CAPACITY - 20)
	check(st.max_weight() == 20, "テスト用に最大の重さを絞れる（capacity_bonus はマイナスにもできる）")
	st.add_item(GameData.Item.MEAT, 9)                                    # 重さ18（残り2）
	st.butcher("hump")                                                    # 肉2＋脂2＋皮1＋骨1（合計の重さ8）が増えようとする → 残り2しか入らない
	check(st.count_of(GameData.Item.MEAT) == 10 and st.count_of(GameData.Item.FAT) == 0 and st.count_of(GameData.Item.HIDE) == 0
			and st.count_of(GameData.Item.BONE) == 0 and st.wasted.get(GameData.Item.MEAT, 0) == 1 and st.wasted.get(GameData.Item.FAT, 0) == 2,
			"解体: 入る分（肉1個。残りの重さ2で足りたのはここまで）だけ入り、あふれた分は捨てる")

	print("== 回収の判断（回収AIへの影響） ==")
	_reset()
	var wood := _drop_resource(GameData.Item.WOOD)
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == wood, "空きがあれば、木材を回収しに行く")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	wood.queue_free()
	# 残りの重さを絞ると、重い素材（鉄鉱石）から先にいっぱいになる（軽い素材の木材はまだ入る）
	_reset()
	st.capacity_bonus = -(CargoDB.CAPACITY - 7)
	check(st.free_for(GameData.Item.IRON_ORE) == 0 and st.free_for(GameData.Item.WOOD) > 0,
			"残りの重さが少ないと、重い素材（鉄鉱石）のほうが先にいっぱいになる")
	var ore := _drop_resource(GameData.Item.IRON_ORE, 650.0)
	var wood2 := _drop_resource(GameData.Item.WOOD, 700.0)
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == wood2, "いっぱいの鉄鉱石は拾わず、まだ入る木材を拾う")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	ore.queue_free()
	wood2.queue_free()
	# 残り1個ぶんの重さに、同時に2人が向かわない（運んでいる分も数える）
	_reset()
	st.capacity_bonus = -(CargoDB.CAPACITY - 8)                           # 鉄鉱石（重さ8）があと1個だけ入る残りにする
	_drop_resource(GameData.Item.IRON_ORE, 600.0)
	_drop_resource(GameData.Item.IRON_ORE, 640.0)
	var a1: bool = W[0].ai._try_start(GameData.Job.GATHER)
	var a2: bool = W[1].ai._try_start(GameData.Job.GATHER)
	check(a1 and not a2, "残り1個ぶんの重さには、2人目は向かわない（1人目 %s・2人目 %s）" % [a1, a2])
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 運んでいる最中の分も、残りの重さを予約している
	W[2].carrying = GameData.Item.IRON_ORE
	W[2].ai._set_state(CharacterAI.State.MOVE_TO_STORAGE)
	check(not W[0].ai._try_start(GameData.Job.GATHER), "運んでいる途中の分も、空きとして数える")
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
	st.capacity_bonus = -CargoDB.CAPACITY                                 # 積載量を0にする
	check(not W[0].ai._try_start(GameData.Job.GATHER), "素材の入らない獲物は、拾わない")
	carcass.queue_free()

	print("== 運搬・加工・保管への影響 ==")
	_reset()
	# 積載量に余裕がない（食料2個ぶん入らない）なら、加工は選ばない
	st.add_item(GameData.Item.MEAT, 5)
	main.recipe_priority = GameData.DEFAULT_RECIPE_PRIORITY.duplicate()
	var r1: Dictionary = main.choose_recipe()
	check(r1.get("id", "") == "cook", "材料があり積載量に余裕があれば、加工を選ぶ（%s）" % r1.get("id", "なし"))
	st.capacity_bonus = -(CargoDB.CAPACITY - 11)                          # 残りの重さを1にする（食料2個ぶんの重さ2に届かない）
	var r2: Dictionary = main.choose_recipe()
	check(r2.get("id", "") != "cook", "残りの積載量が小さくて食料2個ぶん入らないなら、調理は選ばない")
	st.capacity_bonus = -CargoDB.CAPACITY                                 # 残りの重さを0にする
	st.inventory.counts[GameData.Item.FOOD] = 0
	check(main.choose_recipe().get("id", "") != "cook", "積載量が0なら、調理は選ばない")
	# 積載量が作り置きの目標（食料12）より大きくても、目標で止まる（従来どおり）
	_reset()
	st.add_item(GameData.Item.MEAT, 5)
	st.add_item(GameData.Item.FOOD, 12)
	check(main.choose_recipe().get("id", "") != "cook", "作り置きの目標（食料12）に届いたら、積載量に余裕があっても作らない")
	# 積載量がいっぱいのときは、加工した物も置けず捨てる（区画に関係なく、拠点全体で見る。以前の「区画が別」とは違う）
	_reset()
	st.capacity_bonus = -CargoDB.CAPACITY
	main.processor.output.append(GameData.Item.FUEL)
	W[2].carrying = main.processor.take_output()
	W[2].ai._set_state(CharacterAI.State.STORE)
	W[2].ai.timer = 0.0
	W[2].ai.tick(0.1)
	check(W[2].carrying == -1 and st.count_of(GameData.Item.FUEL) == 0 and main.total_wasted == 1,
			"積載量がいっぱいのときに届いた完成品は捨てられ、仲間は次の仕事へ戻る")
	W[2].ai._set_state(CharacterAI.State.SEARCH)
	# 運搬（材料を倉庫から取り出す）は、積載量に影響されない
	_reset()
	st.add_item(GameData.Item.WOOD, st.quota_of(GameData.Item.WOOD))
	var fw: Dictionary = GameData.recipe_by_id("firewood")
	check(st.take_set(fw["in"]) and st.count_of(GameData.Item.WOOD) == st.quota_of(GameData.Item.WOOD) - 1, "材料の取り出し（運搬）は、いっぱいでも普通にできる")
	st.add_item(GameData.Item.WOOD, 1)
	check(st.count_of(GameData.Item.WOOD) == st.quota_of(GameData.Item.WOOD), "取り出して空いた重さは、また使える")

	print("== 遠征の持ち帰り ==")
	_reset()
	st.add_item(GameData.Item.FOOD, 6)
	st.capacity_bonus = -(CargoDB.CAPACITY - 6 - 18)                      # 食料6のあと、残りの重さを18にする
	var ex: Expedition = main.expedition
	ex.state = "idle"
	ex.offer("ruins_large")
	ex.loot.clear()
	ex.loot[GameData.Item.FUEL] = 3                                       # 重さ12（先に処理される）
	ex.loot[GameData.Item.IRON] = 5                                       # 重さ30（あとから処理され、残り6ぶん＝1個しか入らない）
	ex.party = [W[0]]
	W[0].depart()
	W[0].fatigue = 50.0
	ex.steps = ["explore"]
	ex.ok_count = 1
	ex.retreated = true                 # 踏破のおまけ（追加の戦利品）を出さず、持ち帰りだけを確かめる
	ex._finish()
	check(st.count_of(GameData.Item.IRON) == 1 and ex.lost.get(GameData.Item.IRON, 0) == 4,
			"戦利品が積載量に入りきらないときは、入る分だけ持ち帰る（鉄4個を諦めた）")
	check(ex.loot.get(GameData.Item.FUEL, 0) == 3 and st.count_of(GameData.Item.FUEL) == 3, "先に処理されて入りきった分（燃料3）は持ち帰れる")
	check(ex.summary().contains("持ち帰れず"), "結果の文に、持ち帰れなかった分が出る: " + ex.summary())
	ex.state = "idle"
	W[0].arrive(20.0) if W[0].away else null

	print("== 画面 ==")
	_reset()
	var pol: PolicyUI = main.policy
	pol.toggle()
	for page in [0, 1]:
		pol._page = page
		pol._rebuild()
	check(pol._page == 1, "運営の方針の画面に「積載状況」のページが出る")
	pol.toggle()
	main.status._process(0.0)
	check(main.status._weight.text == str(st.current_weight()) and main.status._weight.tooltip_text.contains("素材棚"),
			"積載重量のアイコンゲージに重量が出る（数字は絵の内側）: " + main.status._weight.text)
	st.capacity_bonus = -(CargoDB.CAPACITY - 8)                           # 最大の重さを8にして、木材2個で満杯になるようにする
	st.add_item(GameData.Item.WOOD, 99)
	main.status._process(0.0)
	check(st.count_of(GameData.Item.WOOD) == 2 and main.status.stock_summary().contains("木材 2満"), "いっぱいの素材に「満」が付く: " + main.status.stock_summary())
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
	var over_cap := 0
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
		if st.current_weight() > st.max_weight():
			over_cap += 1
		max_raw = maxi(max_raw, st.used_in(CargoDB.Bay.RAW))
		max_prod = maxi(max_prod, st.used_in(CargoDB.Bay.PRODUCT))
	Engine.time_scale = 1.0
	paused = false
	print("       走行 %.1f km・回収%d 狩猟%d 加工%d・捨てた%d・空腹 %d秒・素材棚 最大の重さ %d・加工品 最大の重さ %d・積載量 %d/%d" % [
			main.director.distance / 2500.0, main.total_gathered, main.total_hunted, main.processor.total_done, main.total_wasted,
			int(hungry_t), max_raw, max_prod, st.current_weight(), st.max_weight()])
	check(over_cap == 0, "積載量（重さ）の上限を超えなかった")
	check(main.total_gathered > 5 and main.processor.total_done > 2, "積載量があっても、回収と加工は回り続ける")
	if main.game_over:
		print("       （途中で車体が壊れてゲームオーバーになった。出来事を本来の頻度で起こしているため）")
