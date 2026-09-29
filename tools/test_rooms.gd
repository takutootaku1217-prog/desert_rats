extends SceneTree
## 部屋の変更（部屋の部品化。data/rooms.gd・ui/base_ui.gd）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_rooms.gd
## 確かめる流れ: 表の整合（費用は今の素材・絵の大きさ）→ 初期配置が今までのゲームと同じ位置 → 建てられる・建てられない条件 →
##   空き → 建てる → 建て替え（材料の消費）→ 加工室・倉庫・寝室・機関室を移す（設備と仲間の動きが追従する）→ 効果（休憩・元気）→
##   画面（区画の選択・建設ボタン・Rキー・Bキーの競合なし）→ 通し（ふつうのゲームで部屋の変更を繰り返しても回り続けるか）。
## 「車体の見た目が変わる」ことは、ウィンドウ表示の tools/shot_rooms.gd で画面に撮って確かめる。

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
	seed(20260927)
	await _run()
	Engine.time_scale = 1.0
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## 新しいゲームを作る。出来事は止め、資源が流れないようにして、倉庫を空にし、加工の方針を全部0にする。
## keep_defaults = true なら、初期の蓄え・加工の方針・速度はふつうのゲームのまま。
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


## W[0] だけが運搬と加工をする
func _only_hauler() -> void:
	for w in W:
		for j in GameData.job_list():
			w.priorities[j] = 0
	W[0].priorities[GameData.Job.HAUL] = 5
	W[0].priorities[GameData.Job.PROCESS] = 5
	for w in W:
		w.ai.on_priority_changed()


## 部屋の費用を、ちょうど1回ぶん（extra 個多めに）倉庫へ入れる
func _give(rtype: String, extra := 0) -> void:
	var c: Dictionary = Rooms.TYPES[rtype]["cost"]
	for it in c:
		st.add_item(it, int(c[it]) + extra)


func _until(cond: Callable, limit: float) -> float:
	var t0: float = main.director.elapsed
	while main.director.elapsed - t0 < limit:
		if cond.call():
			return main.director.elapsed - t0
		await process_frame
	return -1.0


func _run() -> void:
	_test_tables()
	await _test_default_positions()
	_test_rules()
	await _test_build_flow()
	await _test_workshop_move()
	await _test_storage_move()
	await _test_bedroom_move()
	await _test_engine_fallback()
	await _test_effects()
	await _test_ui()
	await _test_soak()


## 画像の大きさ px が、基準の大きさ units の縦横同じ整数倍か（絵の細かさ = その倍率。今は1）
func _uniform_multiple(px: Vector2, units: Vector2) -> bool:
	var kx := px.x / units.x
	var ky := px.y / units.y
	return absf(kx - ky) < 0.0001 and absf(kx - roundf(kx)) < 0.0001 and kx >= 1.0


func _png_size(path: String) -> Vector2i:
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return Vector2i(-1, -1)
	return img.get_size()


# ---------------------------------------------------------------- 表の整合
func _test_tables() -> void:
	print("-- 部屋の表の整合")
	var quota := CargoDB.default_quota()
	var valid_items: Array = GameData.Item.values()
	for t in Rooms.TYPES:
		var d: Dictionary = Rooms.TYPES[t]
		check(d.has_all(["name", "floors", "unique", "required", "min_base_level", "cost", "desc", "effects"]), "%s: 必要な項目がそろっている" % t)
		var ok := true
		for it in d["cost"]:
			if not (it in valid_items) or CargoDB.bay_of(it) < 0 or int(d["cost"][it]) > int(quota.get(it, 0)):
				ok = false            # 旧素材（今の GameData.Item にない）・倉庫に置けない物・初期の枠より多い量は不可
		check(ok, "%s: 費用は今の素材で、倉庫に置ける物・初期の枠に収まる量" % t)
	var order: Array = Rooms.TYPE_ORDER.duplicate()
	var keys: Array = Rooms.TYPES.keys()
	order.sort()
	keys.sort()
	check(order == keys, "画面に並べる順番（TYPE_ORDER）が、部屋の表と過不足なく一致する")
	# 重ね絵: 全ての（区画, 置ける部屋）に絵があり、区画の大きさに合っている
	var hull_units := Vector2(ArtSpec.HULL)
	var art_ok := true
	var msg := ""
	var n := 0
	for slot in Rooms.SLOT_ORDER:
		var r: Rect2 = Rooms.overlay_rect(slot)
		var rel: Rect2 = Rect2((r.position - GameData.HULL_POS) / float(Rooms.UNIT), r.size / float(Rooms.UNIT))
		if rel.position.x < 0 or rel.position.y < 0 or rel.end.x > hull_units.x or rel.end.y > hull_units.y:
			art_ok = false
			msg += " 車体からはみ出す:" + slot
		for t in Rooms.TYPE_ORDER:
			if not Rooms.can_place(t, slot):
				continue
			n += 1
			var sz := _png_size(Rooms.overlay_path(slot, t))
			if sz.x < 0:
				art_ok = false
				msg += " 無い:" + Rooms.overlay_path(slot, t)
			elif not _uniform_multiple(Vector2(sz), Rooms.slot_size(slot)):        # 区画の大きさ（ユニット）の整数倍（絵の細かさは何倍でもよいが、縦横で同じ）
				art_ok = false
				msg += " 大きさ違い:" + Rooms.overlay_path(slot, t)
	check(art_ok, "重ね絵 %d 枚がそろっていて、区画の大きさと一致する%s" % [n, msg])
	# 設備は、部屋の中に置く（その部屋は1つだけ・必須なので、設備の場所が1つに決まる）
	for id in FacilityDB.ids():
		var rt: String = FacilityDB.room_of(id)
		check(Rooms.TYPES[rt]["unique"] and Rooms.TYPES[rt]["required"], "%s: 置く部屋（%s）は1つだけで、なくせない" % [id, rt])
	# 初期配置は、機能を持つ4つの部屋がそろっている
	var lay := Rooms.default_layout()
	check(Rooms.count(lay, "workshop") == 1 and Rooms.count(lay, "bedroom") == 1 and Rooms.count(lay, "storage") == 1
			and Rooms.count(lay, "engine") == 1, "初期配置: 加工室・寝室・倉庫・機関室が1つずつ")
	check(Rooms.sanitize(lay) == lay and Rooms.sanitize({}) == lay, "配置の検査: 正しい配置はそのまま・壊れた配置は初期配置に戻る")


# ---------------------------------------------------------------- 初期配置は、今までのゲームと同じ位置
func _test_default_positions() -> void:
	print("-- 初期配置（これまでのゲームと同じ位置）")
	await _fresh(false)
	check(main.room_layout == Rooms.default_layout(), "最初の配置は初期配置")
	check(main.processor.position == Vector2(GameData.MACHINE_X, GameData.UP_Y), "加工設備は、これまでと同じ位置（上の階・左）")
	check(st.position == Vector2(GameData.STORAGE_X, GameData.LO_Y), "倉庫は、これまでと同じ位置（下の階・右）")
	check(main.base.engine_point() == Vector2(GameData.ENGINE_X, GameData.LO_Y), "燃料の投入口は、これまでと同じ位置（下の階・左）")
	check(main.base.part_point(GameData.Part.MACHINE) == Vector2(GameData.MACHINE_X + 60.0, GameData.UP_Y), "加工設備の修理の位置も同じ")
	check(main.base.facility_spots("workbench") == [Vector2(244.0, GameData.UP_Y)], "ワークベンチの置き場所は、これまでと同じ")
	var bs: Array = main.base.facility_spots("bed")
	check(bs.size() == 3 and bs[0] == Vector2(GameData.BED_X[0], GameData.UP_Y) and bs[1] == Vector2(GameData.BED_X[1], GameData.UP_Y)
			and bs[2] == Vector2(GameData.BED_X[2], GameData.UP_Y), "ベッドの置き場所（3つ）は、これまでと同じ")
	check(main.room_effect("rest_rate") == 0.0, "初期配置では、休憩を強める部屋の効果はない")
	check(main.base.facility_count("workbench") == 0 and main.base.facility_count("bed") == 0, "設備は建てるまでない（建設は、これまでどおり）")


# ---------------------------------------------------------------- 建てられる・建てられない条件
func _test_rules() -> void:
	print("-- 建てられる・建てられない条件")
	var lay := Rooms.default_layout()
	var r := func(slot: String, t: String, lv := 1) -> String: return Rooms.block_reason(lay, slot, t, lv)
	check(r.call("u1", "storage") == "この階には置けない" and r.call("u2", "engine") == "この階には置けない", "倉庫・機関室は下の階だけ")
	check(String(r.call("u2", "empty")).begins_with("最後の寝室"), "最後の寝室は壊せない")
	check(String(r.call("u1", "mess")).begins_with("最後の加工室"), "最後の加工室は壊せない")
	check(String(r.call("l2", "engine")).begins_with("最後の倉庫") and String(r.call("l2", "empty")).begins_with("最後の倉庫"), "最後の倉庫は壊せない")
	check(String(r.call("l1", "engine")).begins_with("すでに"), "同じ部屋には建てられない")
	check(r.call("l1", "empty") == "", "機関室は壊せる（区画を空けられる）")
	check(r.call("l1", "infirmary") == "" and r.call("l1", "mess") == "", "機関室のあとに別の部屋を建てられる")
	check(r.call("l1", "workshop") == "" and r.call("l1", "storage") == "" and r.call("l1", "bedroom") == "", "加工室・倉庫・寝室は、機関室の区画へ移せる（移設）")
	check(r.call("l1", "training") == "拠点Lv2で解放" and r.call("l1", "training", 2) == "", "訓練室は拠点Lv2から（拠点レベルは未実装なので、今は建てられない）")
	check(Rooms.is_relocation(lay, "l1", "workshop") and not Rooms.is_relocation(lay, "l1", "mess"), "加工室を別の区画に建てるのは移設・食堂は新設")
	var moved := Rooms.with_room(lay, "l1", "workshop")
	check(moved["u1"] == "empty" and moved["l1"] == "workshop" and moved["u2"] == "bedroom" and moved["l2"] == "storage",
			"移設すると、元の区画は空き部屋になる")
	check(Rooms.slot_of(moved, "workshop") == "l1" and Rooms.slot_of(moved, "engine") == "", "部屋のある区画が引ける（なければ空）")
	# 1つだけ空けた状態から、どの区画も「空き → 建てる → 別の部屋」にできる（詰まない）
	var lay2 := Rooms.with_room(lay, "l1", "empty")
	for s in Rooms.SLOT_ORDER:
		# 区画 s の部屋を、空いた区画（l1）へ移して空けられるか（機能を持つ部屋は移設、それ以外は壊せる）
		var cur: String = lay2[s]
		var freed: bool = cur == "empty" or not Rooms.TYPES[cur]["required"] or Rooms.block_reason(lay2, "l1", cur, 1) == ""
		check(freed, "区画 %s（%s）は、空いた区画を使って空けられる" % [s, cur])


# ---------------------------------------------------------------- 空き → 建てる → 建て替え
func _test_build_flow() -> void:
	print("-- 空き → 部屋を建てる → 別の部屋へ建て替え（材料の消費）")
	await _fresh(true)
	var lay0: Dictionary = main.room_layout.duplicate()
	check(not main.can_build_room("l1", "infirmary"), "材料がなければ建てられない")
	check(not main.build_room("l1", "infirmary") and main.room_layout == lay0 and main.total_rooms_built == 0, "失敗しても、配置も記録も変わらない")
	var log_n: int = main.director.log.size()
	check(main.build_room("l1", "empty"), "機関室を壊して、空き部屋にできる（費用なし）")
	check(main.room_layout["l1"] == "empty" and main.total_rooms_built == 1, "区画が空きになる")
	check(main.director.log.size() > log_n and String(main.director.log[-1]["text"]).contains("空き部屋"), "記録に「空き部屋にした」が出る")
	check(main.base.engine_point() == Rooms.fallback_fuel_pos(), "機関室がなくなると、燃料は搬入口で補給する")
	# 建てる: 材料は、費用ぶんだけ減る
	var cost: Dictionary = Rooms.TYPES["infirmary"]["cost"]
	_give("infirmary", 1)
	check(main.can_build_room("l1", "infirmary"), "材料がそろうと建てられる")
	check(main.build_room("l1", "infirmary"), "空き部屋に医務室を建てる")
	var used_ok := true
	for it in cost:
		if st.count_of(it) != 1:
			used_ok = false
	check(used_ok, "材料が費用ぶんだけ消費された（%s。1個ずつ余分に入れてあった）" % _cost_text(cost))
	check(main.room_layout["l1"] == "infirmary" and is_equal_approx(main.room_effect("rest_rate"), 0.25), "医務室ができて、休憩の回復 +25%")
	# 建て替え
	_give("mess")
	check(main.build_room("l1", "mess"), "医務室を食堂に建て替える")
	check(main.room_layout["l1"] == "mess" and main.room_effect("rest_rate") == 0.0,
			"食堂に変わると、医務室の休憩効果はなくなる")
	check(not main.build_room("l1", "mess"), "同じ部屋への建て替えはできない")
	check(not main.build_room("u1", "storage"), "置けない階には建てられない")
	_give("training")
	check(not main.can_build_room("l1", "training") and not main.build_room("l1", "training"), "訓練室は、材料があっても建てられない（拠点Lv2）")
	# 空きに戻す → もう一度別の部屋
	check(main.build_room("l1", "empty") and main.room_layout["l1"] == "empty", "食堂を壊して空きに戻せる")
	_give("bedroom")
	check(main.build_room("l1", "bedroom"), "空き部屋に寝室を建てる（寝室は移設）")
	check(main.room_layout["l1"] == "bedroom" and main.room_layout["u2"] == "empty", "寝室が下の階へ移り、元の区画は空き部屋になる")
	# 積載の枠を超えない（費用は、倉庫の初期の枠に収まる）
	for t in Rooms.TYPES:
		var fits := true
		for it in Rooms.TYPES[t]["cost"]:
			if st.quota_of(it) < int(Rooms.TYPES[t]["cost"][it]):
				fits = false
		check(fits, "%s: 費用が倉庫の枠に収まる（集めても貯まらない、にならない）" % t)


func _cost_text(cost: Dictionary) -> String:
	var l: Array = []
	for it in cost:
		l.append("%s×%d" % [GameData.ITEM_NAMES[it], cost[it]])
	return "＋".join(PackedStringArray(l))


# ---------------------------------------------------------------- 加工室を移す（加工設備・ワークベンチが追従して、実際に加工できる）
func _test_workshop_move() -> void:
	print("-- 加工室を下の階へ移す（加工設備・ワークベンチが追従する）")
	await _fresh(false)
	_give("workshop")
	check(Rooms.is_relocation(main.room_layout, "l1", "workshop"), "加工室を下の階・左に建てるのは移設")
	check(main.build_room("l1", "workshop"), "加工室を下の階・左へ移す")
	check(main.room_layout["u1"] == "empty" and main.room_layout["l1"] == "workshop" and main.room_layout["l2"] == "storage", "元の区画は空き部屋・倉庫はそのまま")
	check(main.processor.position == Rooms.processor_pos("l1") and is_equal_approx(main.processor.position.y, GameData.LO_Y), "加工設備が下の階へ移った")
	check(main.base.part_point(GameData.Part.MACHINE) == main.processor.position + Vector2(60.0, 0.0), "加工設備の修理の位置も追従する")
	main.base.add_facility("workbench")
	check(main.base.facility_spots("workbench") == [Vector2(244.0, GameData.LO_Y)], "ワークベンチも、新しい加工室の中の位置になる")
	check(main.base.facility_point("workbench") == main.base.facility_spots("workbench")[0], "ワークベンチで作業する場所も追従する")
	# 実際に加工する: 手作業（加工設備）と、ワークベンチ
	_only_hauler()
	Engine.time_scale = 8.0
	main.recipe_priority["cook"] = 5
	st.add_item(GameData.Item.MEAT, 2)
	var w0 = W[0]
	var near := {"n": 0, "far": 0}
	var food0: int = st.count_of(GameData.Item.FOOD)
	var cond := func() -> bool:
		if main.processor.is_active_at("") and not main.processor.current.is_empty():
			near["n"] += 1
			if w0.position.distance_to(main.processor.position) > 60.0:
				near["far"] += 1
		return st.count_of(GameData.Item.FOOD) >= food0 + 2
	var t: float = await _until(cond, 90.0)
	check(t >= 0.0, "移した加工室で、仲間が調理して食料ができる（%.0f秒）" % t)
	check(near["n"] > 0 and near["far"] == 0, "仲間は新しい加工設備の場所（下の階）で作業した（作業中 %d回・離れていた %d回）" % [near["n"], near["far"]])
	main.recipe_priority["cook"] = 0
	main.recipe_priority["repair_iron"] = 5
	st.add_item(GameData.Item.IRON, 1)
	st.add_item(GameData.Item.WOOD, 1)
	var kits0: int = st.count_of(GameData.Item.REPAIR_KIT)
	var bench := {"n": 0, "far": 0}
	var cond2 := func() -> bool:
		if main.processor.is_active_at("workbench") and main.processor.current.get("station", "") == "workbench":   # 作業中だけ（終わった直後に運びに出た分は数えない）
			bench["n"] += 1
			if w0.position.distance_to(main.base.facility_spots("workbench")[0]) > 60.0:
				bench["far"] += 1
		return st.count_of(GameData.Item.REPAIR_KIT) >= kits0 + 2
	var t2: float = await _until(cond2, 90.0)
	check(t2 >= 0.0, "移したワークベンチで、修理部品ができる（%.0f秒）" % t2)
	check(bench["n"] > 0 and bench["far"] == 0, "作業は新しいワークベンチの場所（作業中 %d回・離れていた %d回）" % [bench["n"], bench["far"]])
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 倉庫を移す
func _test_storage_move() -> void:
	print("-- 倉庫を下の階・左へ移す（荷物の運び入れが追従する）")
	await _fresh(false)
	_give("storage")
	check(main.build_room("l1", "storage"), "倉庫を、機関室があった区画へ移す")
	check(main.room_layout["l2"] == "empty" and main.room_layout["l1"] == "storage", "元の区画は空き部屋になる")
	check(st.position == Rooms.storage_pos("l1") and st.position.x < GameData.STORAGE_X, "倉庫が左の区画へ移った")
	check(main.storage.access_point() == st.position, "仲間の行き先（倉庫の入口）も追従する")
	var w = W[2]
	w.position = Vector2(700.0, GameData.LO_Y)
	w.carrying = GameData.Item.WOOD
	w.carry_n = 1
	w.ai._set_state(CharacterAI.State.MOVE_TO_STORAGE)
	var wood0: int = st.count_of(GameData.Item.WOOD)
	Engine.time_scale = 8.0
	var seen := {"dist": -1.0}
	var cond := func() -> bool:
		if st.count_of(GameData.Item.WOOD) > wood0 and seen["dist"] < 0.0:
			seen["dist"] = w.position.distance_to(st.position)
		return st.count_of(GameData.Item.WOOD) > wood0
	var t: float = await _until(cond, 40.0)
	check(t >= 0.0, "荷物を持った仲間が、新しい倉庫へ運び入れる（%.0f秒）" % t)
	check(seen["dist"] >= 0.0 and seen["dist"] < 80.0, "倉庫の場所まで歩いて入れた（距離 %.0f）" % seen["dist"])
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 寝室を移す（ベッドが追従する。眠っていた仲間は歩き直す）
func _test_bedroom_move() -> void:
	print("-- 寝室を下の階へ移す（ベッドが追従する）")
	await _fresh(true)                                       # ワークベンチ・ベッド3つがある状態
	Engine.time_scale = 8.0
	var w = W[1]
	w.priorities[GameData.Job.REST] = 5
	w.fatigue = 80.0
	w.ai.on_priority_changed()
	var t: float = await _until(func(): return w.sleeping, 60.0)
	check(t >= 0.0 and w.bed_index == 0 and absf(w.position.x - float(GameData.BED_X[0])) < 8.0, "疲れた仲間が、上の階の寝室で眠る（%.0f秒）" % t)
	_give("bedroom")
	check(main.build_room("l1", "bedroom"), "寝室を下の階・左へ移す（移設）")
	check(main.room_layout["u2"] == "empty" and main.base.room_slot("bedroom") == "l1", "元の区画は空き部屋になる")
	check(main.base.facility_count("bed") == 3, "ベッド（建設した設備）は失われない")
	var spots: Array = main.base.facility_spots("bed")
	check(spots.size() == 3 and spots[0] == Vector2(244.0, GameData.LO_Y) and spots[1] == Vector2(304.0, GameData.LO_Y), "ベッドの位置が、新しい寝室の中へ移った")
	check(main.base.bed_point(0) == spots[0], "眠る場所（ベッドの位置）も追従する")
	check(w.ai.state == CharacterAI.State.REST_MOVE, "眠っていた仲間は、新しいベッドへ向かい直す")
	var t2: float = await _until(func(): return w.sleeping and absf(w.position.x - 244.0) < 8.0 and absf(w.position.y - GameData.LO_Y) < 2.0, 60.0)
	check(t2 >= 0.0, "仲間が新しい寝室（下の階）まで歩いて、また眠る（%.0f秒）" % t2)
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 機関室がないとき: 燃料は搬入口で補給する
func _test_engine_fallback() -> void:
	print("-- 機関室を壊したあとの燃料の補給")
	await _fresh(false)
	check(main.build_room("l1", "empty"), "機関室を壊す")
	_only_hauler()
	st.add_item(GameData.Item.FUEL, 2)
	main.base.fuel = 20.0
	Engine.time_scale = 8.0
	var seen := {"n": 0, "far": 0}
	var w0 = W[0]
	var cond := func() -> bool:
		if w0.ai.state == CharacterAI.State.REFUEL:
			seen["n"] += 1
			if w0.position.distance_to(Rooms.fallback_fuel_pos()) > 60.0:
				seen["far"] += 1
		return main.base.total_refuel >= 1
	var t: float = await _until(cond, 90.0)
	check(t >= 0.0 and main.base.fuel > 20.0, "機関室がなくても、燃料を補給できる（%.0f秒・タンク %.0f）" % [t, main.base.fuel])
	check(seen["n"] > 0 and seen["far"] == 0, "搬入口の補給の場所で作業した（作業中 %d回・離れていた %d回）" % [seen["n"], seen["far"]])
	# 機関室を建て直すと、また炉の口で補給する
	_give("engine")
	check(main.build_room("l1", "engine") and main.base.engine_point() == Rooms.engine_pos("l1"), "機関室を建て直すと、燃料の投入口は炉の口に戻る")
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 部屋の効果（医務室・食堂）
func _rest_gain(w) -> float:
	w.ai.state = CharacterAI.State.REST
	w.fatigue = 60.0
	w._process(1.0)
	return 60.0 - w.fatigue


func _test_effects() -> void:
	print("-- 部屋の効果（HP・疲労度の休憩回復）")
	await _fresh(true)
	for x in W:
		x.set_process(false)
		for j in GameData.job_list():
			x.priorities[j] = 0
	var w = W[0]
	var base_rest := _rest_gain(w)
	check(is_equal_approx(base_rest, CrewStatusDB.FATIGUE_REST_RATE), "基準: 眠ると疲労度が %.2f/秒下がる" % base_rest)
	_give("infirmary")
	check(main.build_room("l1", "infirmary"), "医務室を建てる")
	var r2 := _rest_gain(w)
	check(is_equal_approx(r2 / base_rest, 1.25), "医務室で、眠ったときの回復が 25%% 早くなる（%.2f → %.2f）" % [base_rest, r2])
	_give("mess")
	check(main.build_room("l1", "mess"), "食堂に建て替える")
	check(is_equal_approx(_rest_gain(w) / base_rest, 1.0), "食堂に替えると、医務室の効果はなくなる")
	check(Rooms.TYPES["mess"]["effects"].is_empty(), "食堂にはスタミナ関連の効果が残っていない")


# ---------------------------------------------------------------- 画面
func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


func _buttons_with_tooltip(node: Node, out: Array) -> void:
	if node is Button and (node as Button).tooltip_text != "":
		out.append(node)
	for c in node.get_children():
		_buttons_with_tooltip(c, out)


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _rows(ui: BaseUI) -> Array:
	var l: Array = []
	for c in ui._right.get_children():
		if c is PanelContainer:
			l.append(c)
	return l


func _row_button(row: Node) -> Button:
	var h: Node = row.get_child(0)
	return h.get_child(h.get_child_count() - 1)


func _test_ui() -> void:
	print("-- 部屋の変更の画面")
	await _fresh(false)
	var ui: BaseUI = main.room_ui
	check(ui != null and main.room_ui.game == main, "部屋の変更の画面がある")
	await process_frame
	var btn: Button = _find_button(ui, "部屋の変更 (R)")
	check(btn != null, "右のボタン列に「部屋の変更 (R)」がある（UI上から開ける）")
	var build_btn: Button = _find_button(main.build_ui, "建設 (B)")
	check(build_btn != null, "「建設 (B)」のボタンも残っている")
	var gauge_rect: Rect2 = main.status._weight.get_global_rect()
	check(not btn.get_global_rect().intersects(build_btn.get_global_rect()) and not btn.get_global_rect().intersects(gauge_rect),
			"新しいボタンは、建設ボタンと積載重量のゲージに重ならない")
	btn.pressed.emit()
	await process_frame
	check(ui.is_open(), "ボタンで画面が開く")
	# Bキーは建設のもの。Rキーが部屋の変更
	ui._unhandled_input(_key(KEY_B))
	check(ui.is_open(), "Bキーでは、部屋の変更の画面は動かない（建設のキーを譲った）")
	main.build_ui._unhandled_input(_key(KEY_B))
	check(main.build_ui._overlay.visible and not ui.is_open(), "Bキーで建設の画面が開き、部屋の変更の画面は閉じる（重ならない）")
	main.build_ui._unhandled_input(_key(KEY_B))
	check(not main.build_ui._overlay.visible, "もう一度Bキーで建設の画面が閉じる（これまでの操作）")
	ui._unhandled_input(_key(KEY_R))
	check(ui.is_open(), "Rキーで開く")
	ui._unhandled_input(_key(KEY_ESCAPE))
	check(not ui.is_open(), "Escで閉じる")
	# 建設の画面 ⇄ 部屋の変更の画面
	main.build_ui.open()
	_find_button(main.build_ui, "部屋の変更へ (R)").pressed.emit()
	check(ui.is_open() and not main.build_ui._overlay.visible, "建設の画面の「部屋の変更へ」で、部屋の変更の画面へ移れる")
	_find_button(ui, "建設・製作へ (B)").pressed.emit()
	check(not ui.is_open() and main.build_ui._overlay.visible, "部屋の変更の画面の「建設・製作へ」で、建設の画面へ戻れる")
	main.build_ui.close()
	# 区画の選択
	ui.open()
	await process_frame
	var hull_btns: Array = []
	_buttons_with_tooltip(ui._left, hull_btns)
	check(hull_btns.size() == 4, "車体の断面図に、区画のボタンが4つある")
	for b in hull_btns:
		if String(b.tooltip_text).begins_with("上階・右"):
			b.pressed.emit()
	check(ui._slot == "u2", "断面図の区画を押すと、その区画が選ばれる")
	ui.select_slot("u1")
	check(_rows(ui).size() == 6, "上の階の区画には、6種類（加工室・寝室・医務室・食堂・訓練室・空き部屋）が並ぶ")
	ui.select_slot("l1")
	check(_rows(ui).size() == 8, "下の階の区画には、8種類（倉庫・機関室を含む）が並ぶ")
	# 画面から建てる
	var order: Array = []
	for t in Rooms.TYPE_ORDER:
		if Rooms.can_place(t, "l1"):
			order.append(t)
	var rows := _rows(ui)
	var b_empty: Button = _row_button(rows[order.find("empty")])
	check(not b_empty.disabled and b_empty.text == "壊して空ける", "機関室の区画に「壊して空ける」が押せる")
	b_empty.pressed.emit()
	check(main.room_layout["l1"] == "empty", "画面のボタンで、区画が空きになる")
	rows = _rows(ui)
	var b_inf: Button = _row_button(rows[order.find("infirmary")])
	check(b_inf.disabled, "材料がないので、医務室の「建てる」は押せない")
	_give("infirmary")
	ui._rebuild()
	rows = _rows(ui)
	b_inf = _row_button(rows[order.find("infirmary")])
	check(not b_inf.disabled and b_inf.text == "建てる", "材料がそろうと、「建てる」が押せる")
	b_inf.pressed.emit()
	check(main.room_layout["l1"] == "infirmary" and st.count_of(GameData.Item.HIDE) == 0 and st.count_of(GameData.Item.BONE) == 0,
			"画面のボタンで、医務室が建ち、材料が消費される")
	rows = _rows(ui)
	var b_mv: Button = _row_button(rows[order.find("workshop")])
	check(b_mv.text == "移設する", "加工室の行は「移設する」")
	check(_row_button(rows[order.find("infirmary")]).text == "現在の部屋" and _row_button(rows[order.find("infirmary")]).disabled, "今の部屋は「現在の部屋」で押せない")
	# 建設の画面は、これまでどおり動く
	main.build_ui.open()
	await process_frame
	check(main.build_ui._fac_rows.size() == FacilityDB.ids().size(), "建設の画面は、設備の行がこれまでどおり並ぶ")
	main.build_ui._fac_rows["workbench"]["build"].pressed.emit()
	check(main.build_queue == ["workbench"], "建設の画面から、ワークベンチを依頼できる（これまでどおり）")
	main.build_queue.clear()
	main.build_ui.close()
	ui.close()


# ---------------------------------------------------------------- 通し: ふつうのゲームで、部屋の変更を繰り返しても回り続けるか
func _test_soak() -> void:
	await _soak("ふつうの間隔（45〜90秒に1回）で10分", 10.0, 45.0, 90.0, false)
	await _soak("でたらめに短い間隔（5〜12秒に1回。ふつうはしない）で7分", 7.0, 5.0, 12.0, true)


## minutes 分（ゲーム内。12倍速）、gap_min〜gap_max 秒ごとに、いま建てられる部屋の変更のどれかを行う。
## 材料は、倉庫にある分（建設のために取ってある分を含む）とは別に、その費用ぶんを足す（材料を別に集めたプレイヤー）。
func _soak(title: String, minutes: float, gap_min: float, gap_max: float, stress: bool) -> void:
	print("-- 通し: %s（ふつうのゲームで、部屋の変更を繰り返す。12倍速・出来事なし）" % title)
	await _fresh(false, true)
	Engine.time_scale = 12.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var t0: float = main.director.elapsed
	var next_op := t0 + gap_min
	var wb_at := -1.0
	var ops := 0
	var done := 0
	var bad_layout := 0
	var bad_pos := 0
	var bad_worker := 0
	var sleepers_in_air := 0
	var kinds := {}
	main.request_build("workbench")
	while main.director.elapsed - t0 < minutes * 60.0 and not main.game_over:
		await process_frame
		var now: float = main.director.elapsed
		if wb_at < 0.0 and main.has_facility("workbench"):
			wb_at = now - t0
		for id in FacilityDB.ids():                            # 熱心なプレイヤー: 建設も、建てられるようになったら依頼する
			if main.build_blocked_reason(id) == "":
				main.request_build(id)
		if now >= next_op:
			next_op = now + rng.randf_range(gap_min, gap_max)
			var options: Array = []                                # いま建てられる（区画, 部屋）を全部挙げて、その中から選ぶ
			for s in Rooms.SLOT_ORDER:
				for t in Rooms.TYPE_ORDER:
					if main.room_block_reason(s, t) == "":
						options.append([s, t])
			ops += 1
			if not options.is_empty():
				var pick: Array = options[rng.randi() % options.size()]
				var slot: String = pick[0]
				var t: String = pick[1]
				var c: Dictionary = Rooms.TYPES[t]["cost"]
				for it in c:
					st.add_item(it, int(c[it]))
				var reloc: bool = Rooms.is_relocation(main.room_layout, slot, t)
				if main.build_room(slot, t):
					done += 1
					var k: String = ("移設:" if reloc else "") + t
					kinds[k] = int(kinds.get(k, 0)) + 1
		# 不変条件: 必須の部屋は1つずつ・機関室は0か1・加工設備と倉庫は部屋の位置にある
		var lay: Dictionary = main.room_layout
		if Rooms.count(lay, "workshop") != 1 or Rooms.count(lay, "bedroom") != 1 or Rooms.count(lay, "storage") != 1 or Rooms.count(lay, "engine") > 1:
			bad_layout += 1
		if main.processor.position != Rooms.processor_pos(Rooms.slot_of(lay, "workshop")) or st.position != Rooms.storage_pos(Rooms.slot_of(lay, "storage")):
			bad_pos += 1
		for w in W:
			if not is_finite(w.position.x) or not is_finite(w.position.y) or w.position.y < 150.0 or w.position.y > 760.0:
				bad_worker += 1
			if w.ai.state == CharacterAI.State.REST and w.bed_index >= 0 and w.position.distance_to(main.base.bed_point(w.bed_index)) > 30.0:
				sleepers_in_air += 1                           # ベッドがない場所で眠っている
	Engine.time_scale = 1.0
	var made: String = ""
	for k in kinds:
		made += " %s×%d" % [k, kinds[k]]
	print("   部屋の変更を試した %d 回・実際に変わった %d 回:%s" % [ops, done, made])
	print("   ワークベンチ %s・ベッド %d・加工 %d 回・回収 %d 個・狩猟 %d・建設 %d・空腹 %s・車体 %.0f・仲間の疲労度 %s" % [
			("%.0f秒" % wb_at) if wb_at >= 0.0 else "なし", main.base.facility_count("bed"), main.processor.total_done, main.total_gathered,
			main.total_hunted, main.total_built, "あり" if main.hungry else "なし", main.base.parts[GameData.Part.HULL],
			str(W.map(func(w): return int(w.fatigue)))])
	check(not main.game_over, "ゲームオーバーにならない")
	check(done >= (20 if stress else 5), "部屋の変更が何度も行われた（%d回）" % done)
	if not stress:
		check(wb_at >= 0.0 and wb_at < 5.0 * 60.0, "部屋を変えながらでも、ワークベンチが5分以内に建つ（建設は、これまでどおり進む）")
		check(main.total_built >= 2 and main.processor.total_done >= 20, "建設・加工が、ふだんと同じように進む（建設 %d・加工 %d）" % [main.total_built, main.processor.total_done])
	check(bad_layout == 0, "どの時点でも、加工室・寝室・倉庫は1つずつ・機関室は0か1つ（違反 %d回）" % bad_layout)
	check(bad_pos == 0, "加工設備と倉庫は、いつも部屋の位置にある（ずれ %d回）" % bad_pos)
	check(bad_worker == 0, "仲間の位置が壊れない（%d回）" % bad_worker)
	check(sleepers_in_air == 0, "眠っている仲間は、いつもベッドの上にいる（ずれ %d回）" % sleepers_in_air)
	check(main.processor.total_done >= 5 and main.total_gathered >= 5, "部屋を変え続けても、回収・運搬・加工が回り続ける")
	check(main.processor.incoming.size() <= 3 and main.build_queue.size() <= 2, "予約・依頼が取り残されない")
