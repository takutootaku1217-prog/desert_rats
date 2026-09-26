extends SceneTree
## 建設・必要設備（拠点製作の進行）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_build.gd
## 確かめる流れ: 表の整合 → 最初の状態（設備なし・ベッドなし）→ 依頼の受け付け → 建設の流れ（依頼→材料→運搬→作業→完成）→
##   材料の取り置き → 設備による解放 → ベッド → 途中でやめたときの依頼の戻り → 画面 → 通し（放置＋依頼だけで、ワークベンチ・ベッドまで進むか）。
## 設備なしで始める（FacilityDB.start_all = false）。ほかの診断は、設備が最初から全部ある状態で動かす。

var fails := 0
var main
var st: BaseStorage
var W: Array


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260926)
	await _run()
	Engine.time_scale = 1.0
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## 新しいゲームを作る（設備なし）。出来事は止め、資源が流れないようにして、倉庫を空にし、加工の方針を全部0にする。
## keep_defaults = true なら、初期の蓄え・加工の方針・速度はふつうのゲームのまま（通しの確認用）。
func _fresh(all_facilities := false, keep_defaults := false) -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = all_facilities
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	st = main.storage
	W = main.workers
	if keep_defaults:
		return
	main.target_speed = 0.0
	st.inventory.counts.clear()
	for k in main.recipe_priority:
		main.recipe_priority[k] = 0


## W[0] だけが運搬と加工をする（建設の流れだけを見る）
func _only_hauler() -> void:
	for w in W:
		for j in GameData.job_list():
			w.priorities[j] = 0
	W[0].priorities[GameData.Job.HAUL] = 5
	W[0].priorities[GameData.Job.PROCESS] = 5
	for w in W:
		w.ai.on_priority_changed()


## 設備 id の材料を、ちょうど1回ぶん倉庫に入れる（材料の量は表から読む。数値を変えても診断が崩れないように）
func _give_cost(id: String) -> void:
	var c: Dictionary = FacilityDB.def(id)["cost"]
	for it in c:
		st.add_item(it, c[it])


func _need(id: String, item: int) -> int:
	return int(FacilityDB.def(id)["cost"].get(item, 0))


## 条件が満たされるまで待つ。かかったゲーム内の秒数（間に合わなければ -1）
func _until(cond: Callable, limit: float) -> float:
	var t0: float = main.director.elapsed
	while main.director.elapsed - t0 < limit:
		if cond.call():
			return main.director.elapsed - t0
		await process_frame
	return -1.0


func _run() -> void:
	_test_tables()
	await _test_initial_state()
	await _test_requests()
	await _test_flow()
	await _test_reserve()
	await _test_unlock()
	await _test_beds()
	await _test_interrupt()
	await _test_ui()
	await _test_full_run()


# ---------------------------------------------------------------- 表の整合
func _test_tables() -> void:
	print("-- 設備の表の整合")
	var quota := CargoDB.default_quota()
	for id in FacilityDB.ids():
		var d: Dictionary = FacilityDB.def(id)
		check(d.has_all(["name", "desc", "cost", "time", "field", "max", "requires", "station", "room", "dx", "sprite", "frame", "stride"]),
				"%s: 必要な項目がそろっている" % id)
		check(Rooms.TYPES.has(d["room"]), "%s: 置く部屋（%s）が部屋の表にある" % [id, d["room"]])
		check(String(d["requires"]) == "" or FacilityDB.has(d["requires"]), "%s: 必要設備が表にある" % id)
		var hops := 0
		var cur: String = id
		while cur != "" and hops < 10:                       # 必要設備をたどると、手作業（""）に行き着く（輪になっていない）
			cur = FacilityDB.def(cur)["requires"]
			hops += 1
		check(cur == "", "%s: 必要設備の連鎖が手作業に届く" % id)
		check(d["dx"].size() >= int(d["max"]), "%s: 置き場所が最大数ぶんある" % id)
		var cost_ok := true
		for it in d["cost"]:
			if CargoDB.bay_of(it) < 0 or int(d["cost"][it]) > int(quota.get(it, 0)):
				cost_ok = false                              # 倉庫の初期の枠より多い材料は、集めても貯まらない
		check(cost_ok, "%s: 材料は倉庫に置ける物で、初期の枠に収まる" % id)
		var sprites_ok := true
		for i in int(d["max"]):
			if not FileAccess.file_exists(FacilityDB.sprite_path(id, i)):
				sprites_ok = false
		check(sprites_ok, "%s: 絵のファイルがある" % id)
		var r: Dictionary = FacilityDB.recipe_of(id)
		check(r["build"] == id and r["out"] == -1 and r["in"] == d["cost"] and r["station"] == d["requires"],
				"%s: 建設のレシピ（out=-1・材料＝cost・作業する設備＝必要設備）" % id)
	for r in GameData.RECIPES:
		var s: String = GameData.recipe_station(r)
		check(s == "" or (FacilityDB.has(s) and FacilityDB.def(s)["station"]), "%s: 必要設備は「製作できる設備」" % r["id"])
	var wb: Dictionary = FacilityDB.def("workbench")
	check(wb["cost"].keys().size() == 2 and wb["cost"].has(GameData.Item.WOOD) and wb["cost"].has(GameData.Item.IRON),
			"ワークベンチは 木材＋鉄 で建てる")
	check(String(FacilityDB.def("bed")["requires"]) == "workbench", "ベッドはワークベンチがないと建てられない")
	check(String(wb["requires"]) == "", "ワークベンチは手作業（加工設備）で建てられる")
	var hand := 0
	var gated := 0
	for r in GameData.RECIPES:
		if GameData.recipe_station(r) == "":
			hand += 1
		else:
			gated += 1
	check(hand >= 5 and gated >= 3, "手作業でできる物（%d）と、ワークベンチが必要な物（%d）がある" % [hand, gated])
	# 鉄の道具・効率のよい修理部品は、ワークベンチが必要。最初の道具・簡易な修理は手作業でできる
	for id in ["tool_hammer", "tool_axe", "repair_stone", "repair_hide", "smelt", "cook", "firewood", "tallow"]:
		check(GameData.recipe_station(GameData.recipe_by_id(id)) == "", "%s は手作業でできる" % id)
	for id in ["tool_pick", "tool_iron_axe", "tool_adv_pick", "repair_iron"]:
		check(GameData.recipe_station(GameData.recipe_by_id(id)) == "workbench", "%s はワークベンチが必要" % id)


# ---------------------------------------------------------------- 最初の状態
func _test_initial_state() -> void:
	print("-- 最初の状態（設備なし）")
	await _fresh(false)
	check(main.has_facility(""), "手作業（加工設備）はいつでもある")
	check(not main.has_facility("workbench"), "ワークベンチはまだない")
	check(main.base.facility_count("bed") == 0, "ベッドは1つもない")
	check(main.base.claim_bed(W[0]) == -1, "ベッドがないので、割り当てられない")
	W[0].energy = 10.0
	W[0].priorities[GameData.Job.REST] = 5
	check(not W[0].ai._try_start(GameData.Job.REST), "休憩の仕事は、ベッドがなければ始められない（詰まらず次へ進む）")
	# 材料がすべてあっても、必要設備の要る物は作らない
	for k in ["repair_iron", "tool_pick", "tool_iron_axe", "tool_adv_pick"]:
		main.recipe_priority[k] = 5
	st.add_item(GameData.Item.IRON, 6)
	st.add_item(GameData.Item.WOOD, 10)
	st.add_item(GameData.Item.REPAIR_KIT, 4)
	check(main.choose_recipe().is_empty(), "ワークベンチがないうちは、鉄の道具・修理部品（鉄＋木材）は選ばれない")
	check(not main._tools_need_iron(), "作れない道具のために、精錬を急がない")
	main.recipe_priority["tool_hammer"] = 5
	st.add_item(GameData.Item.STONE, 4)
	check(main.choose_recipe().get("id", "") == "tool_hammer", "手作業でできる物（簡易ハンマー）は作れる")


# ---------------------------------------------------------------- 依頼の受け付け
func _test_requests() -> void:
	print("-- 建設の依頼")
	await _fresh(false)
	check(main.build_blocked_reason("bed").contains("ワークベンチ"), "ベッドは「ワークベンチが必要」と断られる")
	check(not main.request_build("bed"), "ワークベンチがなければ、ベッドの依頼は出せない")
	check(main.build_queue.is_empty(), "断られた依頼は待ちに入らない")
	check(main.build_blocked_reason("workbench") == "", "ワークベンチは依頼できる")
	check(main.request_build("workbench"), "ワークベンチを依頼する")
	check(main.build_queue == ["workbench"] and main.build_pending("workbench") == 1, "待ちに入る")
	check(not main.request_build("workbench"), "ワークベンチは1つだけ（依頼中は重ねて出せない）")
	check(main.cancel_build("workbench") and main.build_queue.is_empty(), "待ちの依頼は取り消せる")
	check(not main.cancel_build("workbench"), "取り消す依頼がなければ何も起きない")
	check(main.request_build("workbench"), "取り消したあと、もう一度依頼できる")
	check(main.choose_recipe().is_empty(), "材料がそろうまでは、建設は選ばれない")
	main.build_queue.clear()


# ---------------------------------------------------------------- 建設の流れ（仲間が実際に作る）
func _test_flow() -> void:
	print("-- 建設の流れ（依頼 → 材料を運ぶ → 作業 → 完成）")
	await _fresh(false)
	_only_hauler()
	Engine.time_scale = 8.0
	_give_cost("workbench")
	check(main.request_build("workbench"), "ワークベンチを依頼する（材料 %s がある）" % FacilityDB.cost_text("workbench"))
	var r: Dictionary = main.choose_recipe()
	check(r.get("build", "") == "workbench" and r["station"] == "", "材料がそろうと、建設のレシピが選ばれる（作業は手作業の加工設備）")
	check(main.build_queue.size() == 1, "選ぶだけでは、待ちは変わらない")
	var w0 = W[0]
	var seen := {"take": false, "carry_ok": false, "reserved": {}}
	var log_before: int = main.director.log.size()
	var cond := func() -> bool:
		if w0.ai.state == CharacterAI.State.HAUL_TAKE and w0.ai.haul_recipe.has("build"):
			seen["take"] = true
			if seen["reserved"].is_empty():
				seen["reserved"] = main.reserved_for_builds()
		if w0.ai.state == CharacterAI.State.HAUL_MOVE and w0.ai.haul_recipe.has("build") and w0.carrying == GameData.Item.WOOD:
			seen["carry_ok"] = true
		return main.has_facility("workbench")
	var t: float = await _until(cond, 120.0)
	check(t >= 0.0, "仲間が材料を運んで、ワークベンチが完成する（%.0f秒）" % t)
	check(seen["take"], "仲間が倉庫へ材料を取りに行った")
	check(seen["reserved"].get(GameData.Item.WOOD, 0) == _need("workbench", GameData.Item.WOOD)
			and seen["reserved"].get(GameData.Item.IRON, 0) == _need("workbench", GameData.Item.IRON),
			"取りに行っている間も、その材料は取り置きされている")
	check(seen["carry_ok"], "材料を持って加工設備へ向かった")
	check(main.base.facility_count("workbench") == 1 and main.total_built == 1, "ワークベンチが拠点に1つできた")
	check(st.count_of(GameData.Item.WOOD) == 0 and st.count_of(GameData.Item.IRON) == 0, "材料（%s）が使われた" % FacilityDB.cost_text("workbench"))
	check(main.build_queue.is_empty() and main.processor.pending_build("workbench") == 0, "依頼は残っていない")
	check(main.director.log.size() > log_before and String(main.director.log[-1]["text"]).contains("ワークベンチ"), "記録に「ワークベンチができた」が出る")
	check(main.base.facility_point("workbench") == main.base.facility_spots("workbench")[0], "ワークベンチで作業する場所が決まる")
	# ベッド: ワークベンチで作る。作業する仲間は、ワークベンチの場所へ行く
	await process_frame
	check(main.build_blocked_reason("bed") == "", "ワークベンチができたので、ベッドを依頼できる")
	_give_cost("bed")
	check(main.request_build("bed"), "ベッドを依頼する（材料 %s がある）" % FacilityDB.cost_text("bed"))
	var near := {"n": 0, "far": 0}
	var cond2 := func() -> bool:
		if main.processor.is_active_at("workbench") and main.processor.current.get("build", "") == "bed":
			near["n"] += 1
			if absf(w0.position.x - main.base.facility_spots("workbench")[0].x) > 60.0:
				near["far"] += 1
		return main.base.facility_count("bed") >= 1
	var t2: float = await _until(cond2, 120.0)
	check(t2 >= 0.0, "ベッドが完成する（%.0f秒）" % t2)
	check(near["n"] > 0 and near["far"] == 0, "ベッドはワークベンチの場所で作られる（作業中 %d回・離れていた %d回）" % [near["n"], near["far"]])
	check(main.base.built["bed"] == [0], "ベッドが1つ、最初の区画にできた")
	# ベッドができたら、疲れた仲間が休める
	var w1 = W[1]
	w1.priorities[GameData.Job.REST] = 5
	w1.energy = 10.0
	w1.ai.on_priority_changed()
	var t3: float = await _until(func(): return w1.sleeping, 60.0)
	check(t3 >= 0.0 and w1.bed_index == 0, "疲れた仲間が、できたベッドで眠る（%.0f秒）" % t3)
	check(absf(w1.position.x - main.base.bed_point(0).x) < 8.0, "眠る場所はベッドの位置")
	# ワークベンチが必要な製作物（修理部品 = 鉄＋木材）を、仲間がワークベンチで作る
	w1.priorities[GameData.Job.REST] = 0
	w1.ai.on_priority_changed()
	main.recipe_priority["repair_iron"] = 5
	st.add_item(GameData.Item.IRON, 1)
	st.add_item(GameData.Item.WOOD, 1)
	var kits_before: int = st.count_of(GameData.Item.REPAIR_KIT)
	var at_bench := {"n": 0, "far": 0}
	var cond3 := func() -> bool:
		if main.processor.is_active_at("workbench") and main.processor.current.get("id", "") == "repair_iron":
			at_bench["n"] += 1
			if absf(w0.position.x - main.base.facility_spots("workbench")[0].x) > 60.0:
				at_bench["far"] += 1
		return st.count_of(GameData.Item.REPAIR_KIT) >= kits_before + 2
	var t4: float = await _until(cond3, 120.0)
	check(t4 >= 0.0, "ワークベンチが必要な修理部品を、仲間が作って倉庫へ運ぶ（%.0f秒）" % t4)
	check(at_bench["n"] > 0 and at_bench["far"] == 0, "作業はワークベンチの場所（作業中 %d回・離れていた %d回）" % [at_bench["n"], at_bench["far"]])
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 材料の取り置き
func _test_reserve() -> void:
	print("-- 建設の材料の取り置き")
	await _fresh(false)
	main.recipe_priority["firewood"] = 5
	var need_w := _need("workbench", GameData.Item.WOOD)
	var have_w := need_w - 1                              # 木材が1つ足りない
	st.add_item(GameData.Item.WOOD, have_w)
	check(main.choose_recipe().get("id", "") == "firewood", "依頼がなければ、木材は薪（燃料）に使われる")
	st.add_item(GameData.Item.IRON, _need("workbench", GameData.Item.IRON))
	main.request_build("workbench")                       # 木材は足りない・鉄はそろっている
	check(main.reserved_for_builds() == {GameData.Item.WOOD: have_w, GameData.Item.IRON: _need("workbench", GameData.Item.IRON)},
			"倉庫にある分だけ取り置く")
	check(main.choose_recipe().is_empty(), "木材が足りないあいだは、薪に使わない（建設のために取っておく）")
	main.base.fuel = 10.0
	check(main.choose_recipe().get("id", "") == "firewood", "燃料の在庫がなくタンクも尽きかけなら、取り置きに構わず燃料を作る")
	main.base.fuel = 100.0
	st.add_item(GameData.Item.WOOD, need_w)               # 不足ぶん＋建設ぶん → 建設ぶん ＋ 余り（need_w − 1）
	check(main.choose_recipe().get("build", "") == "workbench", "材料がそろったら、建設が先に選ばれる")
	main.cancel_build("workbench")
	check(main.choose_recipe().get("id", "") == "firewood", "依頼を取り消すと、また薪に使える")
	main.request_build("workbench")
	st.inventory.counts[GameData.Item.IRON] = 0            # 鉄が足りない → 依頼は待ち。木材の余り（need_w − 1 ≧ 1）は薪に使える
	check(main.choose_recipe().get("id", "") == "firewood", "取り置きを超える木材（余り）は、ほかの加工に使える")
	main.build_queue.clear()


# ---------------------------------------------------------------- 設備による解放
func _test_unlock() -> void:
	print("-- ワークベンチによる解放")
	await _fresh(false)
	st.add_item(GameData.Item.IRON, 3)
	st.add_item(GameData.Item.WOOD, 4)
	main.recipe_priority["repair_iron"] = 5
	check(main.choose_recipe().is_empty(), "ワークベンチの前: 修理部品（鉄＋木材）は作れない")
	main.base.add_facility("workbench")
	check(main.choose_recipe().get("id", "") == "repair_iron", "ワークベンチの後: 修理部品（鉄＋木材）が作れる")
	check(main.choose_recipe().get("station", "") == "workbench" and main.processor.station_point(main.choose_recipe()) == main.base.facility_spots("workbench")[0],
			"作る場所はワークベンチ")
	main.recipe_priority["repair_iron"] = 0
	main.recipe_priority["tool_pick"] = 5
	check(main.choose_recipe().get("id", "") == "tool_pick", "ワークベンチの後: 鉄製ピッケルが作れる")
	check(main.processor.station_point(GameData.recipe_by_id("tool_hammer")) == main.processor.global_position, "手作業の物は加工設備で作る")


# ---------------------------------------------------------------- ベッド
func _test_beds() -> void:
	print("-- ベッド")
	await _fresh(false)
	main.base.add_facility("workbench")
	for i in 3:
		check(main.base.add_facility("bed") == i, "ベッドを建てる（%d/3）" % (i + 1))
	check(main.base.add_facility("bed") == -1, "4つ目は建てられない")
	check(main.build_blocked_reason("bed") == "完成", "3つ建てると「完成」")
	var got: Array = []
	for w in W:
		got.append(main.base.claim_bed(w))
	check(got == [0, 1, 2], "建てたベッドが、仲間に順に割り当てられる")
	await _fresh(false)
	main.base.add_facility("workbench")
	main.base.add_facility("bed")
	check(main.base.claim_bed(W[0]) == 0 and main.base.claim_bed(W[1]) == -1, "ベッド1つなら、2人目は休めない")
	main.base.release_bed(W[0])
	check(main.base.claim_bed(W[1]) == 0, "空いたベッドを次の仲間が使う")


# ---------------------------------------------------------------- 途中でやめたときの依頼の戻り
func _test_interrupt() -> void:
	print("-- 途中で中断したときの依頼")
	await _fresh(false)
	_only_hauler()
	Engine.time_scale = 8.0
	_give_cost("workbench")
	main.request_build("workbench")
	var w0 = W[0]
	var t: float = await _until(func(): return w0.ai.state == CharacterAI.State.HAUL_TAKE, 30.0)
	check(t >= 0.0, "仲間が材料を取りに向かう")
	check(main.build_queue.is_empty() and main.processor.pending_build("workbench") == 1, "待ちから外れ、運搬中になる")
	w0.ai._release_task()                                  # 優先度の変更などで仕事をやめた
	check(main.build_queue == ["workbench"] and main.processor.incoming.is_empty(), "取りに行く途中でやめると、依頼は待ちに戻る")
	w0.ai._set_state(CharacterAI.State.SEARCH)
	var t2: float = await _until(func(): return w0.ai.state == CharacterAI.State.HAUL_MOVE, 40.0)
	check(t2 >= 0.0 and st.count_of(GameData.Item.WOOD) == 0, "もう一度、材料を持って向かう")
	w0.depart()                                            # 調査隊に出る
	check(main.build_queue == ["workbench"], "材料を運んでいる途中で調査隊に出ても、依頼は待ちに戻る")
	check(st.count_of(GameData.Item.WOOD) == _need("workbench", GameData.Item.WOOD)
			and st.count_of(GameData.Item.IRON) == _need("workbench", GameData.Item.IRON), "運んでいた材料は倉庫に戻る")
	check(main.processor.incoming.is_empty() and main.processor.pending_build("workbench") == 0, "運搬中の予約も消える")
	w0.arrive(100.0)
	var t3: float = await _until(func(): return main.has_facility("workbench"), 120.0)
	check(t3 >= 0.0, "戻ったあと、建設が最後まで進む（%.0f秒）" % t3)
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 画面
func _test_ui() -> void:
	print("-- 建設の画面")
	await _fresh(false)
	var ui: BuildUI = main.build_ui
	check(ui != null, "建設の画面がある")
	ui.open()
	await process_frame
	await process_frame
	check(ui._overlay.visible, "開くと表示される")
	check(ui._fac_rows.size() == FacilityDB.ids().size(), "設備の行が表のとおりに並ぶ")
	var bed_btn: Button = ui._fac_rows["bed"]["build"]
	check(bed_btn.disabled and bed_btn.text.contains("ワークベンチ"), "ベッドは押せず、理由（ワークベンチが必要）が出る")
	check(String(ui._fac_rows["bed"]["state"].text).contains("まだ建てられない"), "ベッドの状態は「まだ建てられない」")
	var wb_btn: Button = ui._fac_rows["workbench"]["build"]
	check(not wb_btn.disabled, "ワークベンチは押せる")
	check(not ui._fac_rows["workbench"]["cancel"].visible, "依頼前は「取り消す」が出ない")
	var lbl: Label = ui._fac_rows["workbench"]["costs"][GameData.Item.WOOD]
	check(lbl.text.contains("0/%d" % _need("workbench", GameData.Item.WOOD)), "材料の在庫が出る（%s）" % lbl.text)
	wb_btn.pressed.emit()
	await process_frame
	check(main.build_queue == ["workbench"], "ボタンを押すと、建設の依頼が出る")
	ui._refresh()
	check(ui._fac_rows["workbench"]["cancel"].visible and wb_btn.disabled, "依頼中は「取り消す」が出て、重ねて押せない")
	check(String(ui._fac_rows["workbench"]["state"].text).contains("材料集め中"), "状態は「材料集め中」")
	ui._fac_rows["workbench"]["cancel"].pressed.emit()
	check(main.build_queue.is_empty(), "「取り消す」で依頼が消える")
	# 製作の一覧: ワークベンチが必要な物は、建てるまで「作れない」
	var locked := 0
	for rr in ui._recipe_rows:
		if GameData.recipe_station(rr["recipe"]) == "workbench" and String(rr["stars"].text) == "作れない":
			locked += 1
	check(locked >= 3, "ワークベンチが必要な製作物は「作れない」と出る（%d件）" % locked)
	main.base.add_facility("workbench")
	ui._refresh()
	locked = 0
	for rr in ui._recipe_rows:
		if GameData.recipe_station(rr["recipe"]) == "workbench" and String(rr["stars"].text).begins_with("★"):
			locked += 1
	check(locked >= 3, "ワークベンチができると、製作物の優先（★）が出る（%d件）" % locked)
	check(not bed_btn.disabled and String(ui._fac_rows["workbench"]["state"].text).contains("完成"), "ベッドが押せるようになり、ワークベンチは「完成」")
	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.pressed = true
	ui._unhandled_input(ev)
	check(not ui._overlay.visible, "Bキーで閉じる")
	ui._unhandled_input(ev)
	check(ui._overlay.visible, "Bキーで開く")
	ui.close()
	# 方針の画面: 必要設備がない加工は、その旨が出る
	main.policy.toggle()
	await process_frame
	check(main.policy._overlay.visible, "運営の方針の画面も開ける（必要設備の表示を含む）")
	main.policy.close()


# ---------------------------------------------------------------- 通し: 設備なしで始めて、依頼だけで進むか
func _test_full_run() -> void:
	print("-- 通し（設備なしで始め、建設を依頼していくだけ。出来事なし・12倍速）")
	var good := 0
	for n in 3:
		await _fresh(false, true)                         # 初期の蓄え・仲間・優先度・方針・速度は、ふつうのゲームのまま
		Engine.time_scale = 12.0
		var done := {}                                    # 設備 -> 完成した時刻の一覧
		var min_energy := 100.0
		var energy0_sec := 0.0
		var t0: float = main.director.elapsed
		var last: float = t0
		main.request_build("workbench")                   # 熱心なプレイヤー: すぐ依頼し、ベッドも建てられるようになったら依頼する
		while main.director.elapsed - t0 < 12.0 * 60.0 and not main.game_over:
			await process_frame
			var now: float = main.director.elapsed
			for id in FacilityDB.ids():
				var c: int = main.base.facility_count(id)
				while done.get(id, []).size() < c:
					done[id] = done.get(id, []) + [now - t0]
				if main.build_blocked_reason(id) == "":
					main.request_build(id)
			var lo := 100.0
			for w in W:
				lo = minf(lo, w.energy)
			min_energy = minf(min_energy, lo)
			if lo <= 0.0:
				energy0_sec += now - last
			last = now
		Engine.time_scale = 1.0
		var wb: Array = done.get("workbench", [])
		var bd: Array = done.get("bed", [])
		print("   [回%d] ワークベンチ %s ／ ベッド %s ／ 元気の最低 %.0f（0だった時間 %.0f秒）／ 空腹はゲーム内 %s ／ 車体 %.0f" % [
				n + 1, _times(wb), _times(bd), min_energy, energy0_sec, "あり" if main.hungry else "なし", main.base.parts[GameData.Part.HULL]])
		check(not main.game_over, "[回%d] ゲームオーバーにならない" % (n + 1))
		# 運（木が来るか・獲物が獲れるか）で遅れる回があるので、1回ごとではなく「3回のうち2回以上」で確かめる
		if wb.size() == 1 and wb[0] < 4.0 * 60.0 and bd.size() >= 1 and bd[0] < 5.0 * 60.0:
			good += 1
		check(wb.size() <= 1 and bd.size() <= 3, "[回%d] 建てた数が最大数を超えない" % (n + 1))
		# 建ったあとは、ワークベンチが必要な物が作られはじめる
		var made_iron_tool: bool = main.storage.count_of(GameData.Item.PICKAXE) + main.storage.count_of(GameData.Item.IRON_AXE) \
				+ main.storage.count_of(GameData.Item.ADV_PICK) > 0
		for w in W:
			for s in w.tools:
				if int(w.tools[s]) in [GameData.Item.PICKAXE, GameData.Item.IRON_AXE, GameData.Item.ADV_PICK]:
					made_iron_tool = true
		print("   [回%d] 鉄の道具ができた: %s ／ 加工回数 %d" % [n + 1, "はい" if made_iron_tool else "いいえ", main.processor.total_done])
	check(good >= 2, "3回のうち2回以上で、ワークベンチが4分以内・最初のベッドが5分以内に建つ（%d/3）" % good)


func _times(a: Array) -> String:
	var l: Array = []
	for x in a:
		l.append("%.0f秒" % x)
	return "・".join(PackedStringArray(l)) if not l.is_empty() else "なし"
