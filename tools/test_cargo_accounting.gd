extends "res://tools/test_quarry.gd"
func setup():
	await fresh()
	park_fixture()
	main.storage.inventory.counts.clear()
	for k in main.recipe_priority: main.recipe_priority[k] = 0
	main.tool_auto = false
func _initialize():
	await transfers()
	await transformation()
	await finite_yield()
	await bonus_conservation()
	await full_escape()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
func transfers():
	await setup()
	var st = main.storage
	st.add_item(GameData.Item.IRON_ORE, 43)
	main.workers[0].priorities[GameData.Job.HAUL] = 5
	check(main.request_transfer(GameData.Item.IRON_ORE, 36, "to_workshop") == 36, "重量再現と同じ36個運搬")
	var bad := 0
	for i in 900:
		await step()
		if st.current_weight() != 344: bad += 1
		if main.processor.stock.count(GameData.Item.IRON_ORE) == 36: break
	check(bad == 0 and main.processor.stock.count(GameData.Item.IRON_ORE) == 36, "倉庫→運搬中→作業場の各フレームで重量344")
	check(main.request_transfer(GameData.Item.IRON_ORE, 36, "to_storage") == 36, "内部返却は空き重量を要求しない")
	check(await until(func(): return st.count_of(GameData.Item.IRON_ORE) == 43, 180), "内部返却が実AIで完了")
	check(st.current_weight() == 344, "往復しても重量不変")
	# 複数材料の自動運搬。表示用carryingは材料全量ではない。
	var w = main.workers[1]
	w.ai.haul_recipe = GameData.recipe_by_id("repair_iron")
	w.ai._set_state(CharacterAI.State.HAUL_MOVE)
	w.carrying = GameData.Item.IRON
	check(st.carried_weight() == 10, "複数材料運搬は鉄1+木材1を一度ずつ数える")
	w.stop_work()
	check(st.current_weight() == 354 and st.carried_weight() == 0, "中断返却で複製・消失なし")
func transformation():
	await setup()
	var st = main.storage
	main.processor.stock.add(GameData.Item.IRON_ORE)
	st.add_item(GameData.Item.FOOD, 352)
	check(st.current_weight() == 360 and main.request_craft("smelt",1) == 1, "満載でも減量する精錬を依頼できる")
	main.workers[0].priorities[GameData.Job.PROCESS] = 5
	var bad := 0
	for i in 500:
		await step()
		var expected := 360 if main.processor.total_done == 0 else 358
		if st.current_weight() != expected: bad += 1
		if st.count_of(GameData.Item.IRON) == 1: break
	check(bad == 0 and st.count_of(GameData.Item.IRON) == 1, "材料→加工中→完成待ち→運搬→倉庫、精錬差分2だけ減少")
	await setup()
	main.processor.stock.add(GameData.Item.FAT)
	main.storage.add_item(GameData.Item.FOOD,359)
	check(main.request_craft("tallow",1) == 0, "重量が7増す加工は満載時に拒否")
	main.storage.inventory.take_n(GameData.Item.FOOD,7)
	check(main.request_craft("tallow",1) == 1, "正味増量7の空きだけで受付")
	main._feed_crafts()
	check(main.storage.processing_reserve() == 7 and main.storage.free_for(GameData.Item.FOOD) == 0, "加工増量を新規取得から予約")
	main.workers[0].priorities[GameData.Job.PROCESS] = 5
	check(await until(func(): return main.storage.count_of(GameData.Item.FUEL) == 2,100), "満載になる完成品も内部運搬で収納")
	check(main.storage.current_weight() == 360 and main.storage.processing_reserve() == 0, "完了時に予約を実重量へ置換し二重計上しない")
func finite_yield():
	await setup()
	var pt = main.quarry.points[0]
	pt.remaining = 6
	var w = main.workers[0]
	w.ai.res = pt
	pt.claimed_by = w
	w.ai.bag_limit = 3
	w.tools = {"mine":GameData.Item.HAMMER}
	w.ai.gather_ev = w.gather_eval(pt.kind)
	w.ai._set_state(CharacterAI.State.GATHER)
	w.ai._work_point(0.3 * float(w.ai.gather_ev.seconds) / float(w.ai.gather_ev.eff))
	check(pt.remaining == 6 and is_equal_approx(pt.work,0.3), "弱い道具の未完作業は資源を消さない")
	w.ai._release_task()
	check(is_equal_approx(pt.work,0.3), "取消でも地点の端数を保持")
	for i in 2:
		w.ai.res = pt
		pt.claimed_by = w
		w.ai.bag_limit = 3
		w.ai.gather_ev = w.gather_eval(pt.kind)
		w.ai._set_state(CharacterAI.State.GATHER)
		for tick in 60:
			if w.ai.state != CharacterAI.State.GATHER: break
			w.ai._work_point(0.2)
		w.unload_owned()
	check(pt.remaining == 0 and main.storage.count_of(GameData.Item.IRON_ORE) == 6, "消費鉱床6=回収6。袋の区切りで永久掘り損なし")
	check(main.quarry.visit_generated.get(GameData.Item.IRON_ORE,0) == 6, "現地生成記録は回収した主素材6に一致")
	pt.remaining = 1
	pt.work = 0.25
	w.ai.res = pt
	w.tools.clear()
	w.ai.gather_ev = w.gather_eval(pt.kind)
	w.ai._set_state(CharacterAI.State.GATHER)
	w.ai._work_point(100)
	check(pt.remaining == 1 and is_equal_approx(pt.work,0.25), "効率0は生成も資源消費も進捗増加もない")
	main.storage.capacity_bonus = main.storage.current_weight() - CargoDB.CAPACITY
	w.ai.res = pt
	w.tools = {"mine":GameData.Item.HAMMER}
	w.ai.gather_ev = w.gather_eval(pt.kind)
	w.ai._set_state(CharacterAI.State.GATHER)
	w.ai._work_point(100)
	check(pt.remaining == 1 and is_equal_approx(pt.work,0.25), "満載中は無料の作業進捗を貯めない")
	main.storage.capacity_bonus = 0
	main.quarry.request_departure()
	check(await until(func(): return main.quarry.ready_to_leave(),90), "端数を保持したまま帰還")
	check(main.quarry.leave(), "端数のある鉱床から出発")
	main.quarry.left = 0
	main.quarry.tick(0)
	main.quarry.select()
	main.quarry.left = 0
	main.quarry.tick(0)
	check(main.quarry.points[0].remaining == 1 and is_equal_approx(main.quarry.points[0].work,0.25), "再訪で残量と作業端数を復元し補充しない")
func full_escape():
	await setup()
	main.storage.add_item(GameData.Item.IRON_ORE,45)
	main.storage.add_item(GameData.Item.IRON_ORE,1)
	main.base.fuel = 0
	main.workers[0].priorities[GameData.Job.HAUL] = 5
	main.request_transfer(GameData.Item.IRON_ORE,1,"to_workshop")
	check(await until(func(): return main.processor.stock.count(GameData.Item.IRON_ORE) == 1,60), "満載でも内部移動はできる")
	check(main.storage.current_weight() == 360 and main.quarry.loose.get(GameData.Item.IRON_ORE,0) == 1, "内部移動で残置を回収する抜け道は塞がる")
	main.quarry.request_departure()
	check(await until(func(): return main.quarry.crew_ready_to_leave(),60), "残置があっても全員は帰還できる")
	check(not main.quarry.leave(), "通常出発は無断で残置を捨てない")
	var wrong := {GameData.Item.IRON_ORE:2}
	check(not main.quarry.discard_and_leave(wrong), "表示した数量が違えば破棄しない")
	check(main.quarry.discard_and_leave(main.quarry.loose.duplicate()), "確認した1個のみ放棄して正規出発")
	check(main.storage.current_weight() == 360 and main.quarry.discarded[GameData.Item.IRON_ORE] == 1, "所有物は保全、放棄履歴を記録")
	check(not main.quarry.discard_and_leave(wrong), "再入力で二度目の破棄はしない")

func bonus_conservation():
	await setup()
	var expected := 0
	seed(1120)
	for i in 12:
		if randf() < 0.5: expected += 1
	seed(1120)
	var pt = main.quarry.points[0]
	pt.remaining = 12
	var w = main.workers[0]
	w.ai.res = pt
	pt.claimed_by = w
	w.ai.bag_limit = 12
	w.tools = {"mine":GameData.Item.ADV_PICK}
	w.ai.gather_ev = w.gather_eval(pt.kind)
	w.ai._set_state(CharacterAI.State.GATHER)
	for i in 50:
		if w.ai.state != CharacterAI.State.GATHER: break
		w.ai._work_point(0.2)
	w.unload_owned()
	check(pt.remaining == 0 and main.storage.count_of(GameData.Item.IRON_ORE) == 12, "効率1超でも主素材は残量12に一致")
	check(main.storage.count_of(GameData.Item.STONE) == expected, "副産物は実際に採れた12単位につき1回だけ抽選")
	await setup()
	main.storage.add_item(GameData.Item.FOOD,352)
	pt = main.quarry.points[0]
	pt.remaining = 1
	w = main.workers[0]
	w.ai.res = pt
	pt.claimed_by = w
	w.ai.bag_limit = 1
	w.tools = {"mine":GameData.Item.ADV_PICK}
	w.ai.gather_ev = w.gather_eval(pt.kind)
	# 実道具の副産物確率0.5が当たるseedを固定（性能キャッシュの注入なし）。
	var bonus_seed := 1
	seed(bonus_seed)
	while randf() >= 0.5:
		bonus_seed += 1
		seed(bonus_seed)
	seed(bonus_seed)
	w.ai._set_state(CharacterAI.State.GATHER)
	w.ai._work_point(1.0)
	check(main.storage.current_weight() == 360 and pt.remaining == 0 and main.quarry.loose.get(GameData.Item.STONE,0) == 1, "主素材で満載になった副産物は残置へ保存")
	w.unload_owned()
	check(main.storage.current_weight() == 360 and main.storage.count_of(GameData.Item.IRON_ORE) == 1 and main.total_wasted == 0, "満載荷下ろしで主素材も副産物も失わない")
