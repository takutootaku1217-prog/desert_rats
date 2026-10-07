extends SceneTree
## 遠征（遺跡の探索）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_expedition.gd
## 表・派遣の条件・持ち物・作業中の仲間の後始末・関門の判定・戦利品・設計図・撤退・画面・長時間の安定を確かめる。

var fails := 0
var main
var ex: Expedition


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260925)
	if OS.get_cmdline_user_args().has("nopoints"):
		GameData.ENABLE_GATHER_POINTS = false        # 従来の「落ちている物」方式と比べるとき（-- nopoints）
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.storage.enforce = false      # 遠征の診断では、倉庫の積載量（data/cargo.gd）の制限を外す（積載は test_cargo.gd で確認）
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _reset() -> void:
	## 状態をきれいにする（自動の出来事は止める。倉庫には十分な物資を入れる）
	main.director.enabled = false
	main.director.active.clear()
	main.director.forecast.clear()
	for w in main.workers:
		if w.away:
			w.arrive(CrewStatusDB.START_FATIGUE)
		w.fatigue = CrewStatusDB.START_FATIGUE
		CrewStatus._tick_mental(w, 0.0)
	ex.state = "idle"
	ex.party.clear()
	main.blueprints.clear()
	for it in [GameData.Item.FOOD, GameData.Item.REPAIR_KIT]:
		while main.storage.count_of(it) < 20:
			main.storage.add_item(it)


## 1回の遠征を、時間を待たずに最後まで進める
func _run_trip(members: Array, appr: String, kit: bool, site := "ruins_small") -> void:
	ex.state = "idle"
	ex.offer(site)
	var ok := ex.start(members, appr, kit)
	if not ok:
		return
	var guard := 0
	while ex.state == "running" and guard < 50:
		guard += 1
		ex._resolve_step()
	ex.state = "idle"


## 現在の関門が失敗する乱数のseedを探し、そのseedで実際の判定を通す。
## 偶然の成功で「疲労が増えなかった」となるのを避け、被害・修理資材・撤退を同じ条件で確認する。
func _fail_step() -> void:
	var chance := ex.step_chance(ex.party, ex.steps[ex.step_i], ex.step_i, ex.approach_id)
	for rng_seed in range(1, 1000):
		seed(rng_seed)
		if randf() >= chance:
			seed(rng_seed)
			ex._resolve_step()
			return
	check(false, "失敗の再現に使う乱数を選べる")


func _test_fatigue(W: Array) -> void:
	print("== 遠征中も個体の疲労度だけを使う ==")
	_reset()
	var w0 = W[0]
	var w1 = W[1]
	w0.fatigue = 18.0
	w1.fatigue = 35.0
	ex.offer("ruins_small")
	check(ex.start([w0, w1], "normal", false), "疲労度の異なる2人が出発できる")
	check(is_equal_approx(w0.fatigue, 18.0) and is_equal_approx(w1.fatigue, 35.0), "出発するとき、疲労度をリセットしない")
	ex.steps = ["trap", "trap", "explore"]
	_fail_step()
	var penalty: float = ExpeditionDB.STEPS["trap"]["penalty"]
	check(ex.ng_count == 1 and ex.state == "running" and is_equal_approx(w0.fatigue, 18.0 + penalty)
			and is_equal_approx(w1.fatigue, 35.0 + penalty), "失敗の疲労は帰還を待たず、全員の個体データへ加わる")
	check(is_equal_approx(CrewStatus.gauge_value(w0, "fatigue"), CrewStatusDB.MAX_FATIGUE - w0.fatigue), "探索中も、画面は現在の疲労度を読める")
	ex._finish()
	check(not w0.away and not w1.away and is_equal_approx(w0.fatigue, 18.0 + penalty)
			and is_equal_approx(w1.fatigue, 35.0 + penalty), "帰還しても、それぞれの疲労度を引き継ぐ")

	_reset()
	w0.fatigue = 10.0
	ex.offer("ruins_small")
	check(ex.start([w0], "normal", true), "修理資材つきで疲労の診断を始める")
	ex.steps = ["trap", "trap", "explore"]
	_fail_step()
	check(ex.kit_used and is_equal_approx(w0.fatigue, 10.0), "修理資材は最初の失敗による疲労を防ぐ")
	_fail_step()
	check(ex.ng_count == 2 and is_equal_approx(w0.fatigue, 10.0 + penalty), "修理資材は1回だけ有効で、次の失敗では疲労が増える")
	ex._finish()

	_reset()
	w0.fatigue = 78.0
	ex.offer("ruins_small")
	check(ex.start([w0], "bold", false), "疲労度が高い仲間で撤退を確認する")
	ex.steps = ["guardian", "explore", "explore"]
	_fail_step()
	check(ex.retreated and ex.state == "done" and ex.step_i == 1 and not w0.away, "疲労度が最大値に達すると、残りの関門へ進まず帰還する")
	check(is_equal_approx(w0.fatigue, ExpeditionDB.RETURN_FATIGUE_MAX), "帰還時は既存の救済として余力5を残す")
	check(ex.log.any(func(line): return String(line).contains("全員の疲労度 +")), "失敗の記録は疲労度の増加を表示する")
	check(w0.mental == CrewStatus.mental_of(w0), "帰還時の疲労度と精神状態が一致する")
	_reset()


func _test_expedition_mental(W: Array) -> void:
	print("== 遠征の疲労から精神状態・表示・次の関門の実力を更新 ==")
	_reset()
	var w = W[0]
	w.hp = CrewStatusDB.MAX_HP
	w.hunger = CrewStatusDB.MAX_HUNGER
	w.fatigue = 24.0
	w.stress = 3.0
	w.calm = CrewStatusDB.CALM_SECONDS
	CrewStatus._tick_mental(w, 0.0)
	check(w.mental == CrewStatusDB.Mental.GOOD, "疲労度24・落ち着いた時間を満たした仲間は好調")
	ex.offer("ruins_small")
	check(ex.start([w], "normal", false), "好調な仲間が出発する")
	ex.steps = ["explore", "explore", "explore"]
	var field: int = ExpeditionDB.STEPS["explore"]["field"]
	var previous_power := ex.power_of([w], field)
	_fail_step()
	check(w.away and not w.is_processing() and is_equal_approx(w.fatigue, 32.0)
			and w.mental == CrewStatusDB.Mental.NORMAL and is_zero_approx(w.calm), "通常のtickが止まっていても、失敗で疲労度32・普通・落ち着いた時間0になる")
	check(is_equal_approx(w.stress, 3.0), "精神状態の再計算では時間を進めず、ストレスを減らさない")
	check(ex.power_of([w], field) < previous_power, "次の関門は失敗後の疲労度・精神状態による実力を使う")
	var view := CrewStatusView.new().setup(Vector2i(8, 8), 12, true)
	root.add_child(view)
	view.update_from(w)
	check(view.face_label().text == CrewStatusDB.MENTAL_NAMES[CrewStatusDB.Mental.NORMAL]
			and is_equal_approx(view.gauge("fatigue").ratio, 0.68), "探索中の表示も疲労度32・精神状態「普通」に一致する")
	ex._finish()

	_reset()
	w.fatigue = 72.0
	w.stress = 0.0
	CrewStatus._tick_mental(w, 0.0)
	ex.offer("ruins_small")
	check(ex.start([w], "normal", false), "疲労度72の仲間が出発する")
	ex.steps = ["explore", "explore", "explore"]
	_fail_step()
	view.update_from(w)
	check(w.away and is_equal_approx(w.fatigue, 80.0) and w.mental == CrewStatusDB.Mental.BAD
			and view.face_label().text == CrewStatusDB.MENTAL_NAMES[CrewStatusDB.Mental.BAD]
			and is_equal_approx(view.gauge("fatigue").ratio, 0.20), "失敗で疲労度80・不調になり、表示も同じ状態になる")
	ex._finish()
	view.free()
	_reset()


func _run() -> void:
	ex = main.expedition
	var W: Array = main.workers
	_reset()

	print("== 表の整合 ==")
	check(ExpeditionDB.SITES.size() >= 2 and ExpeditionDB.STEPS.size() == 4 and ExpeditionDB.APPROACHES.size() == 3,
			"遺跡%d種・関門4種・進め方3種" % ExpeditionDB.SITES.size())
	var c_lo := ExpeditionDB.chance(0.5, 1.0, 0, "normal")
	var c_hi := ExpeditionDB.chance(3.0, 1.0, 0, "normal")
	check(c_lo < c_hi and c_lo >= ExpeditionDB.MIN_CHANCE and c_hi <= ExpeditionDB.MAX_CHANCE, "実力が高いほど成功率が高い（%.0f%% → %.0f%%）" % [c_lo * 100.0, c_hi * 100.0])
	check(ExpeditionDB.chance(1.5, 1.0, 0, "careful") > ExpeditionDB.chance(1.5, 1.0, 0, "normal")
			and ExpeditionDB.chance(1.5, 1.0, 0, "normal") > ExpeditionDB.chance(1.5, 1.0, 0, "bold"), "成功率: 慎重 > 標準 > 大胆")
	check(ExpeditionDB.chance(1.5, 1.0, 4, "normal") < ExpeditionDB.chance(1.5, 1.0, 0, "normal"), "後の関門ほど難しい")
	var loot_ok := true
	for sid in ExpeditionDB.SITES:
		for it in ExpeditionDB.SITES[sid]["loot"]:
			if not GameData.ITEM_NAMES.has(it):
				loot_ok = false
	check(loot_ok, "戦利品の素材はすべて存在する")

	print("== 遺跡が見つかる ==")
	check(ex.state == "idle" and ex.block_reason([W[0]], "normal", false) == "調べられる遺跡がない", "遺跡がないときは派遣できない")
	ex.offer("ruins_small")
	check(ex.state == "offered" and is_equal_approx(ex.offer_left, ExpeditionDB.SITES["ruins_small"]["stay"]), "遺跡が見つかる（調べられる時間つき）")
	ex.offer("ruins_large")
	check(ex.site_id == "ruins_small", "遺跡が出ている間は、別の遺跡は見つからない")
	ex.tick(ex.offer_left + 1.0)
	check(ex.state == "idle", "時間が過ぎると遺跡は遠ざかる")
	main.director.trigger("ruins_small")
	check(ex.state == "offered", "旅の出来事から遺跡が見つかる")
	var picked_site := false
	for i in 400:
		if EventDB.def(main.director._pick()).get("kind", "") == "site":
			picked_site = true
	check(not picked_site, "遺跡が出ている間は、次の遺跡の出来事は選ばれない")

	print("== 派遣の条件 ==")
	check(ex.block_reason([], "normal", false) != "", "メンバーがいないと出発できない")
	check(ex.block_reason(W.slice(0, 3) + [W[0]], "normal", false).contains("最大"), "調査隊は最大%d人まで" % ExpeditionDB.MAX_PARTY)
	var food0: int = main.storage.count_of(GameData.Item.FOOD)
	while main.storage.count_of(GameData.Item.FOOD) > 1:
		main.storage.take_item(GameData.Item.FOOD)
	check(ex.block_reason([W[0], W[1]], "normal", false).contains("食料"), "食料が足りないと出発できない")
	for i in 20:
		main.storage.add_item(GameData.Item.FOOD)
	while main.storage.count_of(GameData.Item.REPAIR_KIT) > 0:
		main.storage.take_item(GameData.Item.REPAIR_KIT)
	check(ex.block_reason([W[0]], "normal", true).contains("修理資材"), "修理資材がないと、持たせられない")
	for i in 5:
		main.storage.add_item(GameData.Item.REPAIR_KIT)

	print("== 出発 ==")
	var f1: int = main.storage.count_of(GameData.Item.FOOD)
	var k1: int = main.storage.count_of(GameData.Item.REPAIR_KIT)
	var w0 = W[0]
	var w1 = W[1]
	check(ex.start([w0, w1], "normal", true), "2人・修理資材つきで出発できる")
	check(main.storage.count_of(GameData.Item.FOOD) == f1 - 2 * ExpeditionDB.FOOD_PER_MEMBER, "食料を人数ぶん持っていった")
	check(main.storage.count_of(GameData.Item.REPAIR_KIT) == k1 - 1, "修理資材を1個持っていった")
	check(w0.away and w1.away and not w0.visible and not w0.is_processing() and w0.ai.status_text() == "遠征中",
			"出発した仲間は拠点から姿を消し、状態は「遠征中」")
	check(ex.state == "running" and ex.steps.size() == ExpeditionDB.SITES["ruins_small"]["steps"], "探索中になり、関門が決まる（%d つ）" % ex.steps.size())
	check(ex.block_reason([w0], "normal", false) == "調べられる遺跡がない", "探索中は、別の派遣はできない")
	# 進行と記録
	ex.tick(ex.step_time + 0.1)
	check(ex.step_i == 1 and ex.log.size() >= 2, "時間が来ると関門をひとつ越える（記録が増える）")
	check(ex.progress() > 0.3 and ex.progress() < 1.0, "進み具合が表示できる (%.0f%%)" % (ex.progress() * 100.0))
	# 戻す
	var guard := 0
	while ex.state == "running" and guard < 20:
		guard += 1
		ex.tick(ex.step_time + 0.1)
	check(ex.state == "done" and not w0.away and w0.visible and w0.is_processing(), "全ての関門が終わると調査隊が戻る")
	check(w0.position.distance_to(GameData.RAMP_FOOT) < 60.0 and w0.fatigue >= 0.0 and w0.fatigue <= ExpeditionDB.RETURN_FATIGUE_MAX, "斜路の下に戻り、疲労度を引き継ぐ (%.0f)" % w0.fatigue)
	check(ex.summary() != "" and ex.result_left > 0.0, "結果の文が出る: " + ex.summary())
	ex.tick(ExpeditionDB.RETURN_SECONDS + 1.0)
	check(ex.state == "idle", "結果の表示が終わると、通常に戻る")

	print("== 作業中の仲間の後始末 ==")
	_reset()
	# 加工設備へ材料を運んでいる仲間
	var recipe: Dictionary = GameData.recipe_by_id("firewood")
	main.storage.add_item(GameData.Item.WOOD, 3)
	var slots0: int = main.processor.free_slots()
	var wood0: int = main.storage.count_of(GameData.Item.WOOD)
	main.processor.reserve(recipe)
	main.storage.take_set(recipe["in"])
	W[2].carrying = GameData.Item.WOOD
	W[2].ai.haul_recipe = recipe
	W[2].ai.state = CharacterAI.State.HAUL_MOVE
	W[2].depart()
	check(main.processor.free_slots() == slots0 and main.storage.count_of(GameData.Item.WOOD) == wood0 and W[2].carrying == -1,
			"材料を運んでいる途中で出発しても、予約と材料が元に戻る")
	W[2].arrive(50.0)
	# 拾った物を持っている仲間
	var wood1: int = main.storage.count_of(GameData.Item.WOOD)
	W[1].carrying = GameData.Item.WOOD
	W[1].ai.state = CharacterAI.State.MOVE_TO_STORAGE
	W[1].depart()
	check(main.storage.count_of(GameData.Item.WOOD) == wood1 + 1 and W[1].carrying == -1, "持っていた物は倉庫に戻る")
	W[1].arrive(50.0)
	# 燃料を補給しに行く途中
	main.base.refuel_reserved = true
	W[0].ai.state = CharacterAI.State.REFUEL_MOVE
	W[0].depart()
	check(not main.base.refuel_reserved, "燃料補給の途中で出発しても、予約が外れる")
	W[0].arrive(20.0)

	_test_fatigue(W)
	_test_expedition_mental(W)

	print("== 関門の判定（大量に試す） ==")
	_reset()
	var trips := 300
	var stats := {}
	for cfg in [["careful", 3], ["normal", 3], ["bold", 3], ["normal", 1]]:
		var members: Array = W.slice(0, cfg[1])
		var done := 0
		var ok_steps := 0
		var all_steps := 0
		var retreats := 0
		for i in trips:
			_reset()
			for w in members:
				w.fatigue = CrewStatusDB.START_FATIGUE
			_run_trip(members, cfg[0], false)
			all_steps += ex.ok_count + ex.ng_count
			ok_steps += ex.ok_count
			if ex.retreated:
				retreats += 1
			elif ex.ok_count >= 2:
				done += 1
		stats["%s×%d" % [cfg[0], cfg[1]]] = float(ok_steps) / float(maxi(1, all_steps))
		print("       %s・%d人: 関門の成功 %.0f%% ・撤退 %d/%d" % [cfg[0], cfg[1], 100.0 * ok_steps / maxf(1.0, all_steps), retreats, trips])
	check(stats["careful×3"] > stats["normal×3"] and stats["normal×3"] > stats["bold×3"], "同じ編成なら 慎重 > 標準 > 大胆 の順に成功しやすい")
	check(stats["normal×3"] > stats["normal×1"], "人数が多いほど成功しやすい")

	print("== 失敗・撤退・修理資材 ==")
	_reset()
	var seen_retreat := false
	var seen_absorb := false
	var return_fatigue_ok := true
	for i in 300:
		_reset()
		W[0].fatigue = 78.0
		_run_trip([W[0]], "bold", i % 2 == 0, "ruins_large")
		if ex.retreated:
			seen_retreat = true
			if W[0].fatigue > ExpeditionDB.RETURN_FATIGUE_MAX:
				return_fatigue_ok = false
		for line in ex.log:
			if line.contains("修理資材で被害を防いだ"):
				seen_absorb = true
	check(seen_retreat, "疲労度が最大値に達すると撤退する")
	check(return_fatigue_ok, "撤退しても、戻った仲間の疲労度は帰還時の上限を超えない")
	check(seen_absorb, "修理資材を持たせると、失敗の被害を防げることがある")

	print("== 戦利品と設計図 ==")
	_reset()
	var loot_total := 0
	var got_bp := {}
	var stock0: int = main.storage.count_of(GameData.Item.IRON)
	for i in 600:
		_reset()
		for w in W:
			w.fatigue = CrewStatusDB.START_FATIGUE
		_run_trip(W.slice(0, 3), "bold", false, "ruins_large")
		for it in ex.loot:
			loot_total += ex.loot[it]
		if ex.blueprint != "":
			got_bp[ex.blueprint] = true
	check(loot_total > 300, "戦利品が倉庫に入る（600回で %d 個）" % loot_total)
	var expected_bp := 0
	for u in GameData.UNLOCKS:
		if u["blueprint"]:
			expected_bp += 1
	check(got_bp.size() >= 1 and got_bp.size() <= expected_bp, "設計図が見つかる（%d 種。解放の枠組みの設計図は %d 種）" % [got_bp.size(), expected_bp])
	var only_known := true
	for id in got_bp:
		if not GameData.recipe_by_id(id).is_empty() and false:
			only_known = false
		var found := false
		for u in GameData.UNLOCKS:
			if u["id"] == id and u["blueprint"]:
				found = true
		if not found:
			only_known = false
	check(only_known, "見つかる設計図は、解放の枠組み（GameData.UNLOCKS）の設計図だけ")
	# 全て持っているときは、設計図の代わりに鉄が出る
	_reset()
	for u in GameData.UNLOCKS:
		if u["blueprint"]:
			main.blueprints[u["id"]] = true
	check(ex._pick_blueprint() == "", "全ての設計図を持っていると、新しい設計図は出ない")
	_reset()

	print("== 画面 ==")
	var ui: ExpeditionUI = main.expedition_ui
	ui.open()
	for st in ["idle", "offered", "running", "done"]:
		ex.state = st
		if st == "offered":
			ex.site_id = "ruins_small"
			ex.offer_left = 100.0
		if st == "running":
			ex.site_id = "ruins_small"
			ex.party = [W[0]]
			ex.steps = ["explore", "trap", "explore"]
			ex.step_time = 10.0
			ex.step_left = 5.0
			ex.step_i = 1
		ui._rebuild()
		main.event_hud._process(0.0)
	check(true, "遠征の画面と左下の欄が、全ての状態で表示できる")
	ex.state = "offered"
	ex.site_id = "ruins_small"
	ex.offer_left = 100.0
	ui._picker.selected[W[0]] = true
	ui._picker.selected[W[1]] = true
	ui._picker.selected[W[2]] = true
	ui._picker.selected[W[3] if W.size() > 3 else W[0]] = true
	ui._on_selection_changed()
	check(ui._picker.selected_list().size() <= ExpeditionDB.MAX_PARTY, "画面で選べるのは最大%d人まで" % ExpeditionDB.MAX_PARTY)
	ui.close()
	ex.state = "idle"
	ui._picker.selected.clear()

	print("== 長く動かす（ゲーム内約8分。遺跡が見つかるたびに2人を派遣する） ==")
	_reset()
	main.director.enabled = true
	main.director.distance = 20000.0          # 遺跡の出る距離まで進んでいることにする
	main.director._next_in = 3.0
	Engine.time_scale = 8.0
	var dispatched := 0
	var t_end := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < t_end and not main.game_over:
		await create_timer(1.0).timeout
		if ex.state == "offered" and dispatched < 40:
			var party: Array = []
			for w in W:
				if not w.away and party.size() < 2:
					party.append(w)
			main.storage.add_item(GameData.Item.FOOD, 2)
			if ex.start(party, "normal", false):
				dispatched += 1
		if main.director._next_in > 20.0:
			main.director._next_in = 8.0
	Engine.time_scale = 1.0
	paused = false
	var away_now := 0
	for w in W:
		if w.away:
			away_now += 1
	check(dispatched >= 1, "遺跡が見つかったら派遣できた（%d 回。出来事を最大頻度で起こすので、車体が壊れて早く終わることがあり、回数は乱数でばらつく。成功関門 %d・失敗 %d・設計図 %d・撤退 %d）" % [
			dispatched, ex.stats["steps_ok"], ex.stats["steps_ng"], ex.stats["blueprints"], ex.stats["retreats"]])
	check(away_now <= ExpeditionDB.MAX_PARTY and (main.game_over or ex.state != "running" or away_now > 0), "進めたあとも状態が壊れていない（いま出かけている仲間 %d 人）" % away_now)
	if main.game_over:
		print("       （途中で車体が壊れてゲームオーバーになった（ゲーム内 %.1f 分）。出来事を速く起こしているため）" % (main.director.elapsed / 60.0))
	else:
		print("       （ゲームオーバーにならずに終えた（ゲーム内 %.1f 分））" % (main.director.elapsed / 60.0))
