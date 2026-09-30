extends SceneTree
## 積載量（拠点全体の総重量）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_cargo.gd
## 表・重量の計算・超過時の扱い（捨てない）・回収と狩猟の判断・加工の判断・画面・長時間の安定を確かめる。

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
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（木製荷台も建っている。設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## 倉庫・作業場・仲間の持ち物を空にする。出来事は止め、地面の資源も消す。
func _reset() -> void:
	main.director.enabled = false
	main.director.active.clear()
	main.director.forecast.clear()
	main.scroll_speed = 0.0                    # 世界を止めて、回収の「選び方」だけを確かめる（追いつけるかは test_gather.gd で）
	for w in main.workers:
		w.ai._release_task()
		w.carrying = -1
		w.carry_n = 1
		w.carry_bonus.clear()
		w.tools.clear()
		w.ai._set_state(CharacterAI.State.SEARCH)
	for root_node in [main.resources_root, main.creatures_root]:
		for c in root_node.get_children():
			root_node.remove_child(c)          # queue_free だと次のフレームまで残るので、すぐ消す
			c.free()
	st.enforce = true
	st.inventory.counts.clear()
	main.processor.stock.counts.clear()
	main.processor.orders.clear()
	main.processor.incoming.clear()
	main.processor.current = {}
	main.processor.output.clear()
	main.transfer_queue.clear()
	main.transfer_worker = null
	main.craft_queue.clear()


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

	print("== 重さの表 ==")
	check(CargoDB.missing_weights().is_empty(), "GameData.Item のうち CARCASS 以外は、すべて重さが登録されている（登録漏れの検査）")
	check(CargoDB.item_weight(GameData.Item.FOOD) == 1 and CargoDB.item_weight(GameData.Item.MEAT) == 1
			and CargoDB.item_weight(GameData.Item.WOOD) == 2 and CargoDB.item_weight(GameData.Item.STONE) == 3
			and CargoDB.item_weight(GameData.Item.IRON_ORE) == 4 and CargoDB.item_weight(GameData.Item.IRON) == 3
			and CargoDB.item_weight(GameData.Item.FUEL) == 2 and CargoDB.item_weight(GameData.Item.REPAIR_KIT) == 2
			and CargoDB.item_weight(GameData.Item.HAMMER) == 4 and CargoDB.item_weight(GameData.Item.AXE) == 4
			and CargoDB.item_weight(GameData.Item.PICKAXE) == 6 and CargoDB.item_weight(GameData.Item.IRON_AXE) == 6
			and CargoDB.item_weight(GameData.Item.ADV_PICK) == 8, "実装指示書どおりの重さの表")
	check(CargoDB.BASE_MAX_WEIGHT == 200, "基本の最大重量は200")

	print("== 重量の計算 ==")
	_reset()
	check(main.total_weight() == 0 and main.max_weight() == 300, "空なら 0/300（設備は最初から全部あり、木製荷台の +100 を含む）")
	st.add_item(GameData.Item.WOOD, 10)
	check(main.total_weight() == 20, "木材10個なら重量20")
	_reset()
	st.add_item(GameData.Item.STONE, 10)
	check(main.total_weight() == 30, "石10個なら重量30")
	_reset()
	st.add_item(GameData.Item.FOOD, 100)
	check(main.total_weight() == 100, "食料100個なら重量100")
	_reset()
	st.add_item(GameData.Item.WOOD, 5)
	st.add_item(GameData.Item.STONE, 4)
	st.add_item(GameData.Item.FOOD, 3)
	check(main.total_weight() == 5 * 2 + 4 * 3 + 3 * 1, "違うアイテムを混ぜても合計が正しい（木材5・石4・食料3）")

	print("== 重量へ含める場所（倉庫だけでなく拠点全体） ==")
	_reset()
	main.processor.stock.add(GameData.Item.STONE, 6)
	check(main.total_weight() == 18 and st.current_weight() == 0, "作業場（processor.stock）へ移した材料も、拠点全体の重量に入る（倉庫自体の重さは0のまま）")
	_reset()
	main.processor.orders.append({"in": {GameData.Item.IRON: 1, GameData.Item.WOOD: 1}, "out": GameData.Item.REPAIR_KIT, "n": 2})
	check(main.total_weight() == CargoDB.item_weight(GameData.Item.IRON) + CargoDB.item_weight(GameData.Item.WOOD), "加工設備へ投入済みの材料（orders の in）も重量に入る")
	main.processor.orders.clear()
	_reset()
	main.processor.output.append(GameData.Item.FUEL)
	main.processor.output.append(GameData.Item.FUEL)
	check(main.total_weight() == CargoDB.item_weight(GameData.Item.FUEL) * 2, "取り出し待ちの完成品（output）も重量に入る")
	main.processor.output.clear()
	_reset()
	W[0].tools["mine"] = GameData.Item.PICKAXE
	check(main.total_weight() == CargoDB.item_weight(GameData.Item.PICKAXE), "仲間が装備している道具も重量に入る")
	W[0].tools.clear()
	_reset()
	W[0].ai.haul_recipe = {"in": {GameData.Item.WOOD: 3}}
	W[0].ai._set_state(CharacterAI.State.HAUL_MOVE)
	check(main.total_weight() == CargoDB.item_weight(GameData.Item.WOOD) * 3, "倉庫→作業場を運搬中のアイテム（HAUL_MOVE）も重量に入る")
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	W[0].ai.haul_recipe = {}
	_reset()
	W[0].ai.xfer_item = GameData.Item.STONE
	W[0].carry_n = 2
	W[0].ai._set_state(CharacterAI.State.XFER_MOVE)
	check(main.total_weight() == CargoDB.item_weight(GameData.Item.STONE) * 2, "運搬の依頼で運んでいるアイテム（XFER_MOVE）も重量に入る")
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	W[0].ai.xfer_item = -1
	W[0].carry_n = 1
	_reset()
	check(main.total_weight() == 0, "獲物（CARCASS）は、倉庫に入っていない間は重量に含めない（解体するまで一時データ）")

	print("== 収納できるかの判定・予約（重量が同じでも二重計上しない） ==")
	_reset()
	st.add_item(GameData.Item.WOOD, 90)              # 重量180（最大300のうち）
	check(main.request_transfer(GameData.Item.WOOD, 5, "to_workshop") == 5, "倉庫から作業場へ移す（運搬の依頼）")
	check(main.total_weight() == 180, "倉庫から作業場へ移しても、拠点全体の総重量は変わらない（依頼を作っただけで、まだ運んでいない）")
	main.cancel_transfers()

	print("== 重量超過でアイテムを消さない（実装指示書 2.3） ==")
	_reset()
	st.enforce = true
	var cap: int = main.max_weight()                 # 300（木製荷台込み）
	var wood_max: int = cap / CargoDB.item_weight(GameData.Item.WOOD)   # 150
	check(st.add_item(GameData.Item.WOOD, wood_max) == wood_max and main.total_weight() == cap, "最大重量ぴったりまでは入る")
	check(main.remaining_weight() == 0, "残り重量が0になる")
	var before: int = main.total_weight()
	var got := st.add_item(GameData.Item.WOOD, 5)
	check(got == 0, "満杯のとき、倉庫にはこれ以上そのまま入らない（入った数 %d）" % got)
	check(main.processor.stock.count(GameData.Item.WOOD) == 5, "入らなかった5個は、捨てずに作業場（processor.stock）へ移る")
	check(main.total_weight() == before + 10, "総重量としては消えていない（一時的に最大重量を超える。実装指示書どおり削除しない）")
	_reset()
	st.add_item(GameData.Item.STONE, wood_max)  # 何かのアイテムで重量を使い切る量は種類によって違うので、次は個別に検証
	_reset()
	# 残り重量10、木材(重さ2)を10個収納しようとした場合は5個だけ収納し、残り5個を保持する
	st.add_item(GameData.Item.STONE, (cap - 10) / CargoDB.item_weight(GameData.Item.STONE))   # 残りをちょうど10近くに詰める
	var rem: int = main.remaining_weight()
	var n_try := 10
	var expect_store: int = mini(n_try, int(rem / CargoDB.item_weight(GameData.Item.WOOD)))
	var got2 := st.add_item(GameData.Item.WOOD, n_try)
	check(got2 == expect_store and got2 + main.processor.stock.count(GameData.Item.WOOD) == n_try, "残り重量に一部だけ入る場合、入った個数と残った個数の合計が、元の個数と一致する（試した%d個・入った%d個・残り重量は事前に%d）" % [n_try, got2, rem])
	_reset()
	# 残り重量1のとき、重量2の木材は0個収納する
	st.add_item(GameData.Item.STONE, (cap - 1) / CargoDB.item_weight(GameData.Item.STONE))
	while main.remaining_weight() != 1:               # 石だけでは端数が合わないことがあるので、食料(重さ1)で微調整する
		if main.remaining_weight() > 1:
			st.add_item(GameData.Item.FOOD, 1)
		else:
			st.inventory.counts[GameData.Item.FOOD] = maxi(0, st.inventory.counts.get(GameData.Item.FOOD, 0) - 1)
	check(main.remaining_weight() == 1, "（準備）残り重量をちょうど1にした")
	check(st.add_item(GameData.Item.WOOD, 1) == 0, "残り重量1のとき、重さ2の木材は0個しか倉庫に収納しない")

	print("== 解体（獲物）と狩り（重量ベースの入る割合） ==")
	_reset()
	check(st.drop_fit("hump") == 1.0 and main.hunt_has_room("hump"), "空いていれば、獲物の素材はすべて入る")
	# コブ獣: 肉2 脂2 皮1 骨1（重さ合計6）。残り重量2にすると、6のうち2しか入らない（入る割合33%）
	st.add_item(GameData.Item.MEAT, (main.max_weight() - 2) / CargoDB.item_weight(GameData.Item.MEAT))
	check(st.drop_fit("hump") < CargoDB.MIN_DROP_FIT and not main.hunt_has_room("hump"), "素材の重さの大半が入らない獲物は狩らない（入る割合 %.0f%%）" % (st.drop_fit("hump") * 100.0))
	_reset()
	st.add_item(GameData.Item.STONE, (main.max_weight() - 2) / CargoDB.item_weight(GameData.Item.STONE))
	check(main.hunt_has_room("hare"), "ウサギ（肉1・皮1。重さ2）は、残りわずかでも入るので狩る（入る割合 %.0f%%）" % (st.drop_fit("hare") * 100.0))
	_reset()
	main.hunt_policy["hump"] = true
	st.add_item(GameData.Item.MEAT, (main.max_weight() - 2) / CargoDB.item_weight(GameData.Item.MEAT))
	var c := Creature.new()
	c.setup(main, "hump")
	c.position = Vector2(700, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.creatures_root.add_child(c)
	check(not W[1].ai._try_start(GameData.Job.HUNT), "重量がいっぱいのときは、狩猟の仕事に入らない")
	st.inventory.counts[GameData.Item.MEAT] = 0
	check(W[1].ai._try_start(GameData.Job.HUNT), "空きができたら、狩猟の仕事に入る")
	W[1].ai._release_task()
	W[1].ai._set_state(CharacterAI.State.SEARCH)
	# 解体で、入る分だけ入って残りは作業場へ（捨てない）
	_reset()
	st.add_item(GameData.Item.MEAT, (main.max_weight() - 1) / CargoDB.item_weight(GameData.Item.MEAT))
	var meat_before := st.count_of(GameData.Item.MEAT)
	st.butcher("hump")
	check(st.count_of(GameData.Item.MEAT) + main.processor.stock.count(GameData.Item.MEAT) == meat_before + 2, "解体: 入りきらない分は、捨てずに作業場へ（肉が%d→%d、作業場に%d）" % [meat_before, st.count_of(GameData.Item.MEAT), main.processor.stock.count(GameData.Item.MEAT)])

	print("== 回収の判断（回収AIへの影響） ==")
	_reset()
	var wood := _drop_resource(GameData.Item.WOOD)
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == wood, "空きがあれば、木材を回収しに行く")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	st.add_item(GameData.Item.WOOD, main.max_weight() / CargoDB.item_weight(GameData.Item.WOOD))
	check(not W[0].ai._try_start(GameData.Job.GATHER), "重量がいっぱいのときは、拾いに行かない")
	# 別の素材でも、重量がいっぱいなら拾わない（区画という概念が無くなったので、木材以外もいっぱいなら拾えない）
	var stone := _drop_resource(GameData.Item.STONE, 700.0)
	check(not W[0].ai._try_start(GameData.Job.GATHER), "重量がいっぱいなら、別の素材（石）も拾いに行かない")
	stone.queue_free()
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 残りわずかな重量に、同時に2人が向かわない（運んでいる分も数える）
	_reset()
	var iron_room := int(main.max_weight() / CargoDB.item_weight(GameData.Item.IRON_ORE)) - 1
	st.add_item(GameData.Item.IRON_ORE, iron_room)
	_drop_resource(GameData.Item.IRON_ORE, 600.0)
	_drop_resource(GameData.Item.IRON_ORE, 640.0)
	var a1: bool = W[0].ai._try_start(GameData.Job.GATHER)
	var a2: bool = W[1].ai._try_start(GameData.Job.GATHER)
	check(a1 and not a2, "残りわずかな重量には、2人目は向かわない（1人目 %s・2人目 %s）" % [a1, a2])
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 運んでいる最中の分も、重量を予約している
	W[2].carrying = GameData.Item.IRON_ORE
	W[2].ai._set_state(CharacterAI.State.MOVE_TO_STORAGE)
	check(not W[0].ai._try_start(GameData.Job.GATHER), "運んでいる途中の分も、空き重量として数える")
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
	st.add_item(GameData.Item.MEAT, (main.max_weight() - 2) / CargoDB.item_weight(GameData.Item.MEAT))
	check(not W[0].ai._try_start(GameData.Job.GATHER), "素材の重さが大半入らない獲物は、拾わない")

	print("== 運搬・加工・保管への影響 ==")
	_reset()
	# 作った結果が最大重量を超えるなら作らない（実装指示書2.4）。食料は cook（生肉1→食料2）で重量が+1増える
	st.add_item(GameData.Item.MEAT, 5)
	main.recipe_priority = GameData.DEFAULT_RECIPE_PRIORITY.duplicate()
	var r1: Dictionary = main.choose_recipe()
	check(r1.get("id", "") == "cook", "材料があり重量に余裕があれば、加工を選ぶ（%s）" % r1.get("id", "なし"))
	# 拠点をほぼ満杯にする（残り重量をちょうど0にする。石だけでは端数が余ることがあるので、食料で微調整する）
	st.add_item(GameData.Item.STONE, main.remaining_weight() / CargoDB.item_weight(GameData.Item.STONE))
	if main.remaining_weight() > 0:
		st.add_item(GameData.Item.FOOD, main.remaining_weight())
	check(main.remaining_weight() == 0, "（準備）拠点の残り重量をちょうど0にした")
	var r2: Dictionary = main.choose_recipe()
	check(r2.get("id", "") != "cook", "拠点がほぼ満杯で、作ると重量が増えるレシピ（調理）は選ばない")
	# 作り置きの目標（食料12）に届いたら、重量に余裕があっても作らない（従来どおり）
	_reset()
	st.add_item(GameData.Item.MEAT, 5)
	st.add_item(GameData.Item.FOOD, 12)
	check(main.choose_recipe().get("id", "") != "cook", "作り置きの目標（食料12）に届いたら、重量が余っていても作らない")
	# 倉庫が満杯でも、加工品置き場（区画は無いが）に完成品はそのまま届く/作業場へ逃げる（詰み防止・実装指示書2.3）
	_reset()
	st.add_item(GameData.Item.STONE, main.max_weight() / CargoDB.item_weight(GameData.Item.STONE))
	main.processor.output.clear()
	main.processor.output.append(GameData.Item.FUEL)
	W[2].carrying = main.processor.take_output()
	W[2].ai._set_state(CharacterAI.State.STORE)
	W[2].ai.timer = 0.0
	W[2].ai.tick(0.1)
	check((st.count_of(GameData.Item.FUEL) + main.processor.stock.count(GameData.Item.FUEL)) == 1 and W[2].carrying == -1,
			"拠点がほぼ満杯でも、加工した燃料は消えない（倉庫か作業場のどちらかに必ず入る）")
	# 運搬（材料を倉庫から取り出す）は、重量に影響されない
	_reset()
	st.add_item(GameData.Item.WOOD, main.max_weight() / CargoDB.item_weight(GameData.Item.WOOD))
	var w_before := st.count_of(GameData.Item.WOOD)
	var fw: Dictionary = GameData.recipe_by_id("firewood")
	check(st.take_set(fw["in"]) and st.count_of(GameData.Item.WOOD) == w_before - 1, "材料の取り出し（運搬）は、いっぱいでも普通にできる")
	st.add_item(GameData.Item.WOOD, 1)
	check(st.count_of(GameData.Item.WOOD) == w_before, "取り出して空いた分は、また使える")

	print("== 同時運搬でも最大重量の予約を超えない（reserved_weight） ==")
	_reset()
	var room: int = main.max_weight()
	var wood_pt := GatherPoint.new()
	wood_pt.setup(main, "tree")
	wood_pt.remaining = 999
	wood_pt.position = Vector2(600.0, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.resources_root.add_child(wood_pt)
	check(W[0].ai._try_start(GameData.Job.GATHER), "1人目が採取ポイントを予約する")
	var reserved1: int = main.reserved_weight()
	check(reserved1 > 0, "予約した分の重さが、reserved_weight に反映される")
	var wood_pt2 := GatherPoint.new()
	wood_pt2.setup(main, "tree")
	wood_pt2.remaining = 999
	wood_pt2.position = Vector2(640.0, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.resources_root.add_child(wood_pt2)
	st.add_item(GameData.Item.STONE, (room - reserved1 - 2) / CargoDB.item_weight(GameData.Item.STONE))  # 残りをぎりぎりまで詰める
	var a3: bool = W[1].ai._try_start(GameData.Job.GATHER)
	check(main.reserved_weight() + main.total_weight() <= main.max_weight() or not a3, "2人目の予約を足しても、最大重量の予約を超えない（超えるなら2人目は始めない）")
	W[0].ai._release_task()
	W[1].ai._release_task()

	print("== 画面 ==")
	_reset()
	var pol: PolicyUI = main.policy
	pol.toggle()
	for page in [0, 1]:
		pol._page = page
		pol._rebuild()
	check(pol._page == 1, "運営の方針の画面に「積載重量」のページが出る（読み取り専用）")
	pol._page = 0
	main.status._process(0.0)
	check(main.status._weight.text == str(main.total_weight()), "積載重量のアイコンゲージに、拠点全体の総重量が出る（数字は絵の内側）: " + main.status._weight.text)
	st.add_item(GameData.Item.WOOD, main.max_weight())
	main.status._process(0.0)
	check(absf(main.status._weight.ratio - st.weight_ratio()) < 0.0001, "積載ゲージの充填は、拠点全体の積載率と一致する")
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
	var over_max := 0
	var max_seen := 0
	var hungry_t := 0.0
	var last := Time.get_ticks_msec()
	while Time.get_ticks_msec() < t_end and not main.game_over:
		await process_frame
		var now := Time.get_ticks_msec()
		if main.hungry:
			hungry_t += float(now - last) / 1000.0 * 8.0
		last = now
		if main.total_weight() > main.max_weight():
			over_max += 1
		max_seen = maxi(max_seen, main.total_weight())
	Engine.time_scale = 1.0
	paused = false
	print("       走行 %.1f km・回収%d 狩猟%d 加工%d・空腹 %d秒・重量 最大 %d/%d" % [
			main.director.distance / 2500.0, main.total_gathered, main.total_hunted, main.processor.total_done,
			int(hungry_t), max_seen, main.max_weight()])
	check(over_max == 0, "放置しているだけでは、最大重量を超えなかった（重量超過は競合・強制の場合だけ）")
	check(main.total_gathered > 5 and main.processor.total_done > 2, "積載量（重量）があっても、回収と加工は回り続ける")
	if main.game_over:
		print("       （途中で車体が壊れてゲームオーバーになった。出来事を本来の頻度で起こしているため）")
