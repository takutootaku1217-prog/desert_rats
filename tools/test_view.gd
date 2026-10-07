extends SceneTree
## 外装・内装の切り替えと、外装パーツ（data/exterior.gd・scripts/base_view.gd・base_exterior.gd・ui/view_switch.gd）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_view.gd
## 確かめる流れ: 表と絵の整合（窓の穴・屋根・煙の位置・車体の大きさ）→ 最初の状態（内装・これまでと同じ）→ 外装への切り替え
##   （仲間・加工設備・倉庫の見え方）→ 同じ拠点データを読んでいること（部屋を変える・設備を建てる）→ 外装の成長（初期→中盤→後半）→
##   画面（ボタン・O/Iキー・ほかのキーと競合しない・演出）→ 通し（切り替えを繰り返しても、仲間・建設・回収・加工が止まらない）。
## 見た目は、ウィンドウ表示の tools/shot_view.gd で画面に撮って確かめる。

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
	seed(20260928)
	await _run()
	Engine.time_scale = 1.0
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


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


func _until(cond: Callable, limit: float) -> float:
	var t0: float = main.director.elapsed
	while main.director.elapsed - t0 < limit:
		if cond.call():
			return main.director.elapsed - t0
		await process_frame
	return -1.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	_test_tables()
	await _test_initial()
	await _test_switch()
	await _test_same_data()
	await _test_growth()
	await _test_ui()
	await _test_bob()
	await _test_soak()


func _image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return null
	return img


# ---------------------------------------------------------------- 表と絵の整合
func _test_tables() -> void:
	print("-- 外装パーツの表と絵の整合")
	var g := ExteriorDB.geo()
	check(not g.is_empty() and String(g["style"]) == Rooms.STYLE, "parts.json が読め、系統（%s）が部屋の系統と同じ" % Rooms.STYLE)
	var hull := _image("res://assets/base/hull.png")
	var body := _image(ExteriorDB.dir() + "body.png")
	var d := int(ExteriorDB.body_dpu())                          # 外装の車体の細かさ（1ユニットのドット数。今は1）
	check(body != null and hull != null and Vector2(body.get_size()) == Vector2(ArtSpec.HULL) * float(d)
			and Vector2(hull.get_size()) / Vector2(ArtSpec.HULL) == Vector2(hull.get_size()) / Vector2(ArtSpec.HULL) and body.get_height() == MobileBase.HULL_H * d,
			"外装の車体の絵は、基準の大きさ（%s ユニット）の整数倍（細かさ %d）で、内装の断面図と同じ大きさの基準（%s）" % [str(ArtSpec.HULL), d, str(body.get_size() if body != null else "なし")])
	var ids := {}
	var layers_ok := true
	var frames_ok := true
	var msg := ""
	for p in ExteriorDB.PARTS:
		if ids.has(p["id"]):
			msg += " 重複:" + p["id"]
		ids[p["id"]] = true
		if not (p["layer"] in ["wall", "armor", "roof"]):
			layers_ok = false
		var sheet: Dictionary = g["sheets"].get(p["sheet"], {})
		if sheet.is_empty() or not sheet["frames"].has(p["id"]):
			frames_ok = false
			msg += " 絵なし:" + p["id"]
			continue
		var img := _image(ExteriorDB.dir() + String(sheet["file"]))
		var f := ExteriorDB.frame_of(p)
		if img == null or f.position.x < 0 or f.end.x > img.get_width() or f.end.y > img.get_height():
			frames_ok = false
			msg += " 範囲外:" + p["id"]
			continue
		var opaque := 0                                                           # 切り出した範囲に、絵が描かれている
		for y in f.size.y:
			for x in f.size.x:
				if img.get_pixel(f.position.x + x, f.position.y + y).a > 0.0:
					opaque += 1
		if opaque < f.size.x * f.size.y / 6:
			frames_ok = false
			msg += " ほぼ空:" + p["id"]
	check(layers_ok and msg == "" and frames_ok, "全パーツ（%d）に、絵と切り出し範囲がある%s" % [ExteriorDB.PARTS.size(), msg])
	var rules_ok := true
	for p in ExteriorDB.PARTS:
		for k in p.get("unlock", {}):
			if not (k in ["distance", "facility", "beds", "room"]):
				rules_ok = false
		if p.has("replaces") and not ids.has(p["replaces"]):
			rules_ok = false
		if String(p.get("kind", "fixed")) == "slot" and not Rooms.TYPES.has(p["room"]):
			rules_ok = false
		if String(p.get("kind", "fixed")) == "fixed" and not g["at"].has(p["id"]):
			rules_ok = false
	check(rules_ok, "見える条件・置き換え・部屋の種類・置き場所の指定が、表に沿っている")
	# 窓: 区画ごとに1つ。区画の内側にあり、車体の絵では透明な穴（ガラスの色が後ろから見える）
	var win_ok: bool = g["windows"].keys().size() == Rooms.SLOT_ORDER.size()
	var holes_ok := true
	for s in Rooms.SLOT_ORDER:
		var w := ExteriorDB.window_rect(s)
		var sl: Dictionary = Rooms.SLOTS[s]
		if w.position.x < sl["x0"] or w.end.x > sl["x1"] + 1 or w.position.y < sl["top"] or w.end.y > sl["feet"]:
			win_ok = false
		for y in w.size.y * d:
			for x in w.size.x * d:
				if body.get_pixel(w.position.x * d + x, w.position.y * d + y).a > 0.0:
					holes_ok = false
	check(win_ok, "窓は、4つの区画それぞれの内側にある")
	check(holes_ok, "窓の場所は、車体の絵で透明な穴になっている（ガラスの色が見える）")
	var cab := ExteriorDB.cab_rect()
	check(body.get_pixel((cab.position.x + 6) * d, (cab.position.y + 4) * d).a == 0.0, "運転席の窓も穴になっている")
	var arches_ok := true
	for cx in g["arches"]:
		if body.get_pixel(int(cx) * d, 78 * d).a > 0.0 or body.get_pixel(int(cx) * d, 70 * d).a > 0.0:
			arches_ok = false
	check(arches_ok, "車輪の覆い（穴）が、車輪の位置（%s）にある" % str(g["arches"]))
	var wheel_ok := true
	for i in MobileBase.WHEEL_X.size():
		if absf((MobileBase.WHEEL_X[i] - float(GameData.HULL_POS.x)) / float(ArtSpec.UNIT_PX) - float(g["arches"][i])) > 0.5:
			wheel_ok = false
	check(wheel_ok, "覆いの位置が、車輪（MobileBase.WHEEL_X）と一致する")
	for rt in Rooms.TYPES:
		check(ExteriorDB.GLASS.has(rt), "%s: 窓のガラスの色がある" % rt)
	# 屋根: 車体の上端の上に乗っていて、画面の上の状態表示にかからない。内装の断面図（hull.png）には屋根の物を焼き込んでいない
	var roof_ok := true
	var top_ok := true
	for p in ExteriorDB.PARTS:
		if p["layer"] != "roof" or String(p.get("kind", "fixed")) != "fixed":
			continue
		var fu := ExteriorDB.frame_units(p)                                        # 基準の大きさ（ユニット）
		var at := ExteriorDB.at_of(p)
		if at.y + fu.y > int(g["foot_row"]) + 1:
			roof_ok = false
		if float(GameData.HULL_POS.y) + float(at.y) * float(ArtSpec.UNIT_PX) < 168.0:
			top_ok = false
	check(roof_ok, "屋根の上の物は、車体の上端の行の上に乗っている")
	check(top_ok, "屋根の上の物は、画面上の状態表示（下端 y=165）にかからない")
	var burned := 0
	var hd := int(float(hull.get_width()) / float(ArtSpec.HULL.x))              # 断面図の細かさ
	for y in 10 * hd:
		for x in hull.get_width():
			if hull.get_pixel(x, y).a > 0.0:
				burned += 1
	check(burned == 0, "内装の断面図（hull.png）の屋根の行には、物が焼き込まれていない（屋根は外装パーツが重ねる）")
	var stack_a := {}
	for p in ExteriorDB.PARTS:
		if p["id"] == "stack_a":
			stack_a = p
	var sf := ExteriorDB.frame_units(stack_a)
	var sx: float = float(GameData.HULL_POS.x) + (float(ExteriorDB.at_of(stack_a).x) + float(sf.x) / 2.0) * float(ArtSpec.UNIT_PX)
	check(absf(sx - (float(MobileBase.STACK_X[0]) + 4.0)) <= 4.0, "排気管の位置が、煙が出る位置（MobileBase.STACK_X）と合っている（%.0f）" % sx)
	var rr := ExteriorDB.at_of({"id": "rear_rack", "sheet": "wall_parts", "layer": "wall"})
	check(float(GameData.HULL_POS.x) + float(rr.x) * float(ArtSpec.UNIT_PX) >= 0.0, "後ろの荷台は画面の内側に収まる")


# ---------------------------------------------------------------- 最初の状態
func _test_initial() -> void:
	print("-- 最初の状態（これまでと同じ内装）")
	await _fresh(false)
	check(main.base_view != null and main.base_view.mode == BaseView.Mode.INTERIOR, "最初は内装（これまでの画面）")
	check(not main.base.view_exterior and main.base.exterior != null, "拠点は内装の見え方で、外装の描画ノードを持つ")
	check(main.processor.visible and main.storage.visible, "加工設備・倉庫が見える")
	var all_vis := true
	for w in W:
		if not w.visible or w.modulate.a != 1.0:
			all_vis = false
	check(all_vis, "仲間がみんな見える")
	check(is_equal_approx(main.base.modulate.a, 1.0) and main.base.body_bob == 0.0, "内装は透明でも跳ねてもいない")
	check(main.view_switch != null, "切り替えのボタンがある")
	# 内装の断面図の上には、屋根の物（外装と同じ絵）が出る。最初は簡素
	check(ExteriorDB.visible_ids(main, ["roof"]) == ["deck_rail", "stack_a", "stack_b", "flag", "antenna_small", "crates_small", "cloth_roll"],
			"最初の屋根は簡素（柵・排気管・旗・小さなアンテナ・木箱・丸めた布）")
	check(ExteriorDB.visible_ids(main, ["wall", "armor"]) == ["fuel_port"], "最初の壁には燃料の口だけ（装甲・荷台・工具かけはまだない）")


# ---------------------------------------------------------------- 外装への切り替え
func _test_switch() -> void:
	print("-- 外装への切り替え（仲間・加工設備・倉庫）")
	await _fresh(true)
	var lay: Dictionary = main.room_layout
	var wpos: Array = []
	for w in W:
		wpos.append(w.position)
	var proc_pos: Vector2 = main.processor.position
	var stor_pos: Vector2 = st.position
	# 地面・斜路・搬入口の入口・車体の中にいる仲間
	W[0].position = Vector2(620.0, 640.0)                      # 地面
	W[1].position = Vector2(950.0, 516.0)                      # 斜路の途中
	W[2].position = Vector2(GameData.RAMP_TOP.x, GameData.RAMP_TOP.y)   # 搬入口の入口（ここから中）
	check(not main.base.is_inside(W[0].position) and not main.base.is_inside(W[1].position) and main.base.is_inside(W[2].position),
			"車体の中か外かの判定: 地面・斜路は外、搬入口の入口から中")
	check(main.base.is_inside(Vector2(600.0, GameData.LO_Y)) and main.base.is_inside(Vector2(340.0, GameData.UP_Y)), "下の階・上の階は中")
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	check(main.base_view.mode == BaseView.Mode.EXTERIOR and main.base.view_exterior and main.base_view.is_exterior(), "外装に切り替わる")
	check(not main.processor.visible and not main.storage.visible, "外装では、内装の物（加工設備・倉庫）は描かない")
	check(W[0].visible and W[1].visible and not W[2].visible, "外の仲間（地面・斜路）は見え、中の仲間は見えない")
	# 状態は変わらない
	check(main.room_layout == lay and main.processor.position == proc_pos and st.position == stor_pos, "部屋の配置・加工設備・倉庫の位置は、そのまま")
	check(main.base.facility_count("workbench") == 1 and main.base.facility_count("bed") == 3, "建てた設備も、そのまま")
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
	var same := true
	for w in W:
		if not w.visible:
			same = false
	check(same and main.processor.visible and main.storage.visible and main.base.modulate.a == 1.0, "内装へ戻すと、全員と加工設備・倉庫がまた見える")
	# 調査隊に出ている間は、どちらでも見えない。戻ると、外にいるので外装でも見える
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	W[1].depart()
	await process_frame
	check(not W[1].visible, "調査隊に出ている仲間は、外装でも見えない")
	W[1].arrive(0.0)
	await process_frame
	check(W[1].visible, "戻った仲間（斜路の下に現れる）は、外装でも見える")
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)


# ---------------------------------------------------------------- 外装・内装が同じ拠点データを読んでいる
func _test_same_data() -> void:
	print("-- 外装と内装は同じ拠点データ（部屋の変更・設備の建設が外装にも反映される）")
	await _fresh(false)
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	var lay_before: Dictionary = main.room_layout.duplicate()
	check(ExteriorDB.glass_color(main.room_layout["u1"]) == ExteriorDB.GLASS["workshop"]
			and ExteriorDB.glass_color(main.room_layout["u2"]) == ExteriorDB.GLASS["bedroom"], "窓の色は、区画の部屋の種類から決まる（加工室・寝室）")
	check(main.base.room_slot("engine") == "l1", "燃料の口は機関室のある区画（下・左）")
	# 外装のまま、部屋を変える
	main.build_room("l1", "empty")
	var infirm_cost: Dictionary = Rooms.TYPES["infirmary"]["cost"]
	for it in infirm_cost:
		st.add_item(it, infirm_cost[it])
	check(main.build_room("l1", "infirmary"), "外装を見たまま、部屋を変えられる（下・左 → 医務室）")
	check("sign_cross:l1" in ExteriorDB.visible_ids(main, ["wall"]), "外装に、医務室の十字の看板が出る（部屋の配置が外観に映る）")
	check(main.base.room_slot("engine") == "" and Rooms.slot_of(main.room_layout, "infirmary") == "l1", "機関室を壊したので、燃料の口は別の場所（機関室なし）")
	var mess_cost: Dictionary = Rooms.TYPES["mess"]["cost"]
	for it in mess_cost:
		st.add_item(it, mess_cost[it])
	check(main.build_room("l1", "mess"), "医務室 → 食堂に建て替える")
	var ids: Array = ExteriorDB.visible_ids(main, ["wall", "roof"])
	check(not ("sign_cross:l1" in ids) and ("roof_vent:l1" in ids), "看板は消え、食堂の換気管が屋根に出る")
	check(ExteriorDB.glass_color(main.room_layout["l1"]) == ExteriorDB.GLASS["mess"], "下・左の窓の色が食堂の色になる")
	# 内装から見ても同じ拠点
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
	check(main.room_layout["l1"] == "mess" and "roof_vent:l1" in ExteriorDB.visible_ids(main, ["roof"]), "内装に戻しても、同じ部屋の配置・同じ屋根")
	check(lay_before["l1"] == "engine", "（元は機関室だった）")
	# 設備の建設
	var n0: int = ExteriorDB.visible_ids(main, ["wall", "roof"]).size()
	main.base.add_facility("workbench")
	check("tool_rack" in ExteriorDB.visible_ids(main, ["wall"]), "ワークベンチを建てると、外装に工具かけが付く")
	main.base.add_facility("bed")
	check("canopy" in ExteriorDB.visible_ids(main, ["roof"]), "最初のベッドができると、屋根に布（日よけ）が張られる")
	check("wash_line" not in ExteriorDB.visible_ids(main, ["wall"]), "ベッドが1つでは、まだ物干しはない")
	main.base.add_facility("bed")
	check("wash_line" in ExteriorDB.visible_ids(main, ["wall"]), "ベッドが2つになると、物干しが出る")
	check(ExteriorDB.visible_ids(main, ["wall", "roof"]).size() > n0, "設備が増えると、見た目のパーツも増える")


# ---------------------------------------------------------------- 外装の成長
func _test_growth() -> void:
	print("-- 外装の成長（走行距離。初期 → 中盤 → 後半）")
	await _fresh(false)
	var prev: Array = ExteriorDB.visible_ids(main, ["wall", "armor", "roof"])
	var steps := [
		[ExteriorDB.STAGE_SMALL, "crates_big", "crates_small"],
		[ExteriorDB.STAGE_MID, "water_tank", "cloth_roll"],
		[ExteriorDB.STAGE_MID, "antenna_mast", "antenna_small"],
		[ExteriorDB.STAGE_RACK, "rear_rack", ""],
		[ExteriorDB.STAGE_TANK, "fuel_tank_roof", ""],
		[ExteriorDB.STAGE_LATE, "antenna_comm", "antenna_mast"],
		[ExteriorDB.STAGE_LATE, "armor_side", ""],
		[ExteriorDB.STAGE_LATE, "armor_front", ""],
	]
	for s in steps:
		main.director.distance = s[0] - 1.0
		var before: Array = ExteriorDB.visible_ids(main, ["wall", "armor", "roof"])
		check(not (s[1] in before), "%s: 距離 %.0f では、まだ出ない" % [s[1], s[0] - 1.0])
		main.director.distance = s[0]
		var now_ids: Array = ExteriorDB.visible_ids(main, ["wall", "armor", "roof"])
		check(s[1] in now_ids and (s[2] == "" or not (s[2] in now_ids)), "%s: 距離 %.0f で出る%s" % [s[1], s[0], "（%s は置き換わって消える）" % s[2] if s[2] != "" else ""])
	var late: Array = ExteriorDB.visible_ids(main, ["wall", "armor", "roof"])
	check(late.size() > prev.size(), "後半は、最初よりパーツが増えている（%d → %d）" % [prev.size(), late.size()])
	# 二重に描かない: 置き換えられたものと置き換えたものは同時に出ない
	var dup := false
	for p in ExteriorDB.PARTS:
		if p.has("replaces") and (p["id"] in late) and (p["replaces"] in late):
			dup = true
	check(not dup, "置き換えたパーツと、置き換えられたパーツは、同時に出ない")
	# 内装の断面図の上の屋根も、同じ段階（同じ拠点データ）
	var roof: Array = ExteriorDB.visible_ids(main, ["roof"])
	check("antenna_comm" in roof and "fuel_tank_roof" in roof and not ("armor_side" in roof), "屋根の物は内装の断面図の上にも出る（装甲は外装だけ）")
	# 走行距離は Director が数えている（同じ数字が外装の成長に使われる）
	check(main.director.distance == ExteriorDB.STAGE_LATE, "成長は Director の走行距離を読んでいる")


# ---------------------------------------------------------------- 画面
func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _test_ui() -> void:
	print("-- 切り替えの画面（ボタン・O/Iキー・演出）")
	await _fresh(false)
	await process_frame
	var vs: ViewSwitchUI = main.view_switch
	var b_ext: Button = _find_button(vs, "外装 (O)")
	var b_int: Button = _find_button(vs, "内装 (I)")
	check(b_ext != null and b_int != null, "[外装 (O)] [内装 (I)] のボタンがある")
	var overlap := false
	for t in ["仲間の管理 (C)", "運営の方針 (P)", "遠征 (X)", "建設 (B)", "部屋の変更 (R)"]:
		var o: Button = _find_button(main, t)
		if o == null:
			overlap = true
			continue
		for b in [b_ext, b_int]:
			if b.get_global_rect().intersects(o.get_global_rect()):
				overlap = true
	check(not overlap and not b_ext.get_global_rect().intersects(b_int.get_global_rect()), "切り替えのボタンは、ほかのボタンに重ならない")
	check(b_ext.get_global_rect().position.y >= 195.0, "状態表示（右上）にもかからない")
	# ボタン: 演出つき（消える → 切り替わる → 現れる）
	Engine.time_scale = 1.0
	b_ext.pressed.emit()
	check(main.base_view.mode == BaseView.Mode.EXTERIOR and main.base_view.is_fading(), "[外装] を押すと、切り替えが始まる（演出つき）")
	var seen_dim := false
	var seen_switch := false
	var n := 0
	while main.base_view.is_fading() and n < 5000:
		await process_frame
		n += 1
		if main.base.modulate.a < 0.99:
			seen_dim = true
		if main.base.view_exterior:
			seen_switch = true
	check(seen_dim and seen_switch and not main.base_view.is_fading(), "車体が一瞬薄くなり、外装に切り替わって、また現れる（%dフレーム）" % n)
	check(is_equal_approx(main.base.modulate.a, 1.0) and main.base.view_exterior, "終わると、透明でない・外装のまま")
	b_int.pressed.emit()
	await _until_idle()
	check(main.base_view.mode == BaseView.Mode.INTERIOR and not main.base.view_exterior and main.processor.visible, "[内装] を押すと内装へ戻る")
	# キー
	vs._unhandled_input(_key(KEY_O))
	await _until_idle()
	check(main.base.view_exterior, "Oキーで外装")
	vs._unhandled_input(_key(KEY_I))
	await _until_idle()
	check(not main.base.view_exterior, "Iキーで内装")
	# 切り替え中に反対を押しても、壊れない
	b_ext.pressed.emit()
	await process_frame
	b_int.pressed.emit()
	await _until_idle()
	check(main.base_view.mode == BaseView.Mode.INTERIOR and not main.base.view_exterior and is_equal_approx(main.base.modulate.a, 1.0), "切り替えの途中で戻しても、内装のまま・透明にならない")
	# ほかのキー・画面と競合しない
	main.build_ui._unhandled_input(_key(KEY_B))
	check(main.build_ui._overlay.visible, "Bキー（建設）はこれまでどおり")
	main.build_ui._unhandled_input(_key(KEY_B))
	main.room_ui._unhandled_input(_key(KEY_R))
	check(main.room_ui.is_open(), "Rキー（部屋の変更）はこれまでどおり")
	main.room_ui._unhandled_input(_key(KEY_R))
	var keys := {}
	var dup := false
	for k in [KEY_B, KEY_R, KEY_P, KEY_X, KEY_C, KEY_O, KEY_I]:
		if keys.has(k):
			dup = true
		keys[k] = true
	check(not dup, "O・I は、ほかの操作のキー（B・R・P・X・C）と重ならない")
	# 外装のまま、ほかの画面が開ける
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	main.build_ui.open()
	await process_frame
	check(main.build_ui._overlay.visible and main.base.view_exterior, "外装のままでも、建設の画面が開く")
	main.build_ui.close()
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)


func _until_idle() -> void:
	var n := 0
	while main.base_view.is_fading() and n < 5000:
		await process_frame
		n += 1


# ---------------------------------------------------------------- 走行の跳ね
func _test_bob() -> void:
	print("-- 外装の走行（車体が段差で跳ねる。内装は跳ねない）")
	await _fresh(false, true)
	Engine.time_scale = 12.0
	var seen_bob := false
	var interior_bob := false
	var t0: float = main.director.elapsed
	while main.director.elapsed - t0 < 20.0:
		await process_frame
		if main.base.body_bob != 0.0:
			interior_bob = true
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	var speed_ok: bool = main.scroll_speed > 5.0
	t0 = main.director.elapsed
	while main.director.elapsed - t0 < 40.0:
		await process_frame
		if main.base.body_bob < 0.0:
			seen_bob = true
	Engine.time_scale = 1.0
	check(speed_ok, "拠点は走っている（速度 %.0f）" % main.scroll_speed)
	check(not interior_bob, "内装では、車体は跳ねない（仲間の足元が動かない）")
	check(seen_bob, "外装では、走っている間に、車体が跳ねる")
	main.target_speed = 0.0
	await _frames(3)
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	await _frames(3)
	check(main.base.body_bob == 0.0 or main.scroll_speed > 5.0, "止まっているときは跳ねない")


# ---------------------------------------------------------------- 通し: 切り替えを繰り返しても、ゲームが止まらない
func _test_soak() -> void:
	print("-- 通し（外装・内装を切り替え続けながら、建設・部屋の変更・回収・加工。10分・12倍速）")
	await _fresh(false, true)
	Engine.time_scale = 12.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var t0: float = main.director.elapsed
	var next_sw := t0 + 2.0
	var next_room := t0 + 60.0
	var switches := 0
	var jump := 0
	var prev_pos: Array = []
	var prev_away: Array = []
	for w in W:
		prev_pos.append(w.position)
		prev_away.append(w.away)
	var vis_bad := 0
	var wb_at := -1.0
	var lay_bad := 0
	var max_step := 0.0
	main.request_build("workbench")
	while main.director.elapsed - t0 < 10.0 * 60.0 and not main.game_over:
		await process_frame
		var now: float = main.director.elapsed
		if wb_at < 0.0 and main.has_facility("workbench"):
			wb_at = now - t0
		for id in FacilityDB.ids():
			if main.build_blocked_reason(id) == "":
				main.request_build(id)
		if now >= next_sw:
			next_sw = now + rng.randf_range(0.7, 4.0)
			main.base_view.set_mode(BaseView.Mode.INTERIOR if main.base_view.mode == BaseView.Mode.EXTERIOR else BaseView.Mode.EXTERIOR,
					rng.randf() < 0.5)
			switches += 1
		if now >= next_room:
			next_room = now + rng.randf_range(45.0, 90.0)
			var options: Array = []
			for s in Rooms.SLOT_ORDER:
				for t in Rooms.TYPE_ORDER:
					if main.room_block_reason(s, t) == "":
						options.append([s, t])
			if not options.is_empty():
				var pick: Array = options[rng.randi() % options.size()]
				for it in Rooms.TYPES[pick[1]]["cost"]:
					st.add_item(it, int(Rooms.TYPES[pick[1]]["cost"][it]))
				main.build_room(pick[0], pick[1])
		# 仲間の位置が、切り替えで飛ばない（1フレームで動ける距離を超えない）。調査隊から戻った瞬間（away→在籍）の
		# テレポート（Worker.arrive）は、切り替えとは別の理由なので数えない。
		for i in W.size():
			var w = W[i]
			var d: float = w.position.distance_to(prev_pos[i])
			if not w.away and not prev_away[i] and d > 90.0:
				jump += 1
			max_step = maxf(max_step, d) if not w.away else max_step
			prev_pos[i] = w.position
			prev_away[i] = w.away
			var inside: bool = main.base.is_inside(w.position)
			var should_show: bool = (not w.away) and (main.base_view._shown == BaseView.Mode.INTERIOR or not inside)
			if w.visible != should_show:
				vis_bad += 1
		var lay: Dictionary = main.room_layout
		if Rooms.count(lay, "workshop") != 1 or Rooms.count(lay, "bedroom") != 1 or Rooms.count(lay, "storage") != 1:
			lay_bad += 1
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
	Engine.time_scale = 1.0
	print("   切り替え %d 回・ワークベンチ %s・ベッド %d・加工 %d 回・回収 %d 個・狩猟 %d・建設 %d・空腹 %s・仲間の疲労度 %s・1フレームの最大の動き %.0f" % [
			switches, ("%.0f秒" % wb_at) if wb_at >= 0.0 else "なし", main.base.facility_count("bed"), main.processor.total_done,
			main.total_gathered, main.total_hunted, main.total_built, "あり" if main.hungry else "なし", str(W.map(func(w): return int(w.fatigue))), max_step])
	check(not main.game_over, "ゲームオーバーにならない")
	check(switches >= 100, "切り替えを何度も行った（%d回）" % switches)
	check(jump == 0, "切り替えで、仲間の位置が飛ばない（%d回）" % jump)
	check(vis_bad == 0, "仲間の見え方が、いつも「中は外装で見えない・外は見える」になっている（ずれ %d回）" % vis_bad)
	check(lay_bad == 0, "部屋の配置が壊れない")
	check(wb_at >= 0.0 and wb_at < 6.0 * 60.0, "切り替えながらでも、ワークベンチが建つ（%.0f秒）" % wb_at)
	check(main.total_built >= 2 and main.processor.total_done >= 20 and main.total_gathered >= 20, "建設・加工・回収が、いつもどおり進む（建設%d・加工%d・回収%d）" % [main.total_built, main.processor.total_done, main.total_gathered])
	# build_queue の上限は、建てられる設備が増えるほど緩める（ワークベンチ1＋ベッド最大3＋荷台の増設最大3＋物資庫最大1 = 同時に最大8）
	var max_pending := 0
	for id in FacilityDB.ids():
		max_pending += FacilityDB.max_of(id)
	check(main.processor.incoming.size() <= 3 and main.build_queue.size() <= max_pending, "予約・依頼が取り残されない（待ち %d / 上限 %d）" % [main.build_queue.size(), max_pending])
