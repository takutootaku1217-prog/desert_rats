extends SceneTree
## 絵の細かさ（1ユニットのドット数）に依存しない構造（data/art_spec.gd）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_artscale.gd
## 確かめる流れ: 決まり（ユニット・細かさ・切り出し・格子）→ 今の絵が、基準の大きさの整数倍（今は1倍）になっている →
##   絵を2倍の細かさに差し替えても（実行中に、最近傍で拡大した絵を作って差し替える）、ゲーム側の座標・大きさ・置き場所が変わらない →
##   絵ごとに細かさが違っても動く（車体だけ先に高精細にする、など）→ 描画のコードが、絵のドット数を決め打ちしていない（ソースの検査）→
##   部屋の論理データ（区画の大きさ・入口・決まった位置）。
## 画面が画素まで同じになることは、tools/shot_dpu.gd と tools/compare_shots.py（tools/make_dpu_fixture.py の絵）で比べる。

var fails := 0
var main

const ENV_HEIGHTS := {"sky": 100, "clouds": 40, "mesa_far": 46, "mesa_mid": 42, "dunes": 30, "ground": 46, "props": 26}   # 背景の基準の高さ（ユニット）
const GROUPS := ["characters", "creatures", "items", "gather", "environment", "ui", "rooms", "exterior", "base"]


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260929)
	await _run()
	ArtSpec.set_root_override("")
	Engine.time_scale = 1.0
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _run() -> void:
	_test_functions()
	_test_contracts({}, 1.0, "今の絵（1ユニット=1ドット）")
	_test_rooms_logic()
	_test_source_scan()
	await _test_swap(2, GROUPS, "全部を2倍の細かさに差し替える")
	await _test_swap(2, ["base", "rooms", "exterior"], "車体まわりだけ2倍にする（段階的な高精細化）")
	await _test_swap(3, ["characters", "creatures", "items", "gather", "environment", "ui"], "仲間・生物・素材・背景・UIだけ3倍にする")


# ---------------------------------------------------------------- 決まり
func _test_functions() -> void:
	print("-- 絵の細かさの決まり（data/art_spec.gd）")
	check(ArtSpec.UNIT_PX == 4 and GameData.PX == ArtSpec.UNIT_PX, "論理ユニット1つ＝画面4px。GameData.PX は同じ値の別名（定義は1か所）")
	check(ArtSpec.world(Vector2(3, 2)) == Vector2(12, 8) and ArtSpec.px_size(Vector2i(16, 16)) == Vector2(64, 64), "ユニット → 画面のpx")
	var t1 := ImageTexture.create_from_image(Image.create(208, 16, false, Image.FORMAT_RGBA8))
	var t2 := ImageTexture.create_from_image(Image.create(416, 32, false, Image.FORMAT_RGBA8))
	var uw := ArtSpec.sheet_units_w(ArtSpec.WORKER)
	check(uw == 208.0, "仲間の絵の基準の幅は 16×13コマ＝208 ユニット")
	check(ArtSpec.dpu(t1, uw) == 1.0 and ArtSpec.dpu(t2, uw) == 2.0, "細かさは、絵の幅 ÷ 基準の幅（208→1倍・416→2倍）")
	check(ArtSpec.dot_px(t1, uw) == 4.0 and ArtSpec.dot_px(t2, uw) == 2.0, "絵の1ドットの画面上の大きさ（4px・2px）")
	check(ArtSpec.frame_src(t1, ArtSpec.WORKER, 3) == Rect2(48, 0, 16, 16) and ArtSpec.frame_src(t2, ArtSpec.WORKER, 3) == Rect2(96, 0, 32, 32),
			"コマの切り出しは、基準の大きさ × 細かさ（1倍と2倍で、同じコマを指す）")
	check(ArtSpec.snap_offset(Vector2(482, 10), 4.0) == Vector2(2, 2) and ArtSpec.snap_offset(Vector2(482, 10), 2.0) == Vector2(0, 0),
			"位置を絵のドットの格子に合わせる量は、細かい絵ほど小さい（4px格子・2px格子）")
	var cs := GameData.creature_spec("hare")
	check(cs["cell"] == Vector2i(14, 12) and cs["stride"] == 14 and cs["frames"] == ArtSpec.CREATURE_FRAMES, "生物の基準は、表（CREATURES の size）から決まる")
	check(GameData.creature_height_px("hump") == 16.0 * 4.0, "生物の画面上の高さは、基準の大きさ×UNIT_PX（絵に依存しない）")
	var c1 := ImageTexture.create_from_image(Image.create(42, 12, false, Image.FORMAT_RGBA8))      # 生物（14x12 ユニットを3コマ）の絵。1倍
	var c2 := ImageTexture.create_from_image(Image.create(84, 24, false, Image.FORMAT_RGBA8))      # 同じ絵の2倍
	var cspec := ArtSpec.spec_of(Vector2i(14, 12), 3)
	check(ArtSpec.frame_src(c1, cspec, 2) == Rect2(28, 0, 14, 12) and ArtSpec.frame_src(c2, cspec, 2) == Rect2(56, 0, 28, 24),
			"コマ数が共通の絵（生物・採取ポイント）の切り出し（1倍・2倍で同じコマ）")
	# 差し替え先の指定
	check(ArtSpec.overridden("res://assets/base/hull.png") == "" and ArtSpec.overridden("res://scripts/main.gd") == "", "差し替えがなければ、通常どおり（assets の絵）")


# ---------------------------------------------------------------- 絵が基準の大きさの整数倍になっているか
## 絵 path が、基準の大きさ（units_w × units_h ユニット）の何倍か（縦横で同じ整数）を返す。違えば -1。
func _dpu_of(path: String, units_w: float, units_h: float) -> float:
	var t := GameData.tex(path)
	var dx := float(t.get_width()) / units_w
	var dy := float(t.get_height()) / units_h
	if absf(dx - dy) > 0.0001 or absf(dx - roundf(dx)) > 0.0001 or dx < 1.0:
		return -1.0
	return dx


## 全ての絵について、細かさ（dpu）を測る。expect = {グループ: 期待する細かさ}（書いていないグループは default）。
func _test_contracts(expect: Dictionary, default: float, label: String) -> void:
	print("-- 絵の細かさが揃っている（%s）" % label)
	var bad := {}
	var count := {}
	var check_one := func(group: String, path: String, uw: float, uh: float) -> void:
		var want: float = float(expect.get(group, default))
		var got := _dpu_of(path, uw, uh)
		count[group] = int(count.get(group, 0)) + 1
		if got != want:
			bad[group] = String(bad.get(group, "")) + " %s（%.2f）" % [path.get_file(), got]
	for pal in ["grey", "tan", "pink"]:
		check_one.call("characters", "res://assets/characters/mouse_%s.png" % pal, ArtSpec.sheet_units_w(ArtSpec.WORKER), float(ArtSpec.WORKER["cell"].y))
	for sp in GameData.CREATURES:
		var cs := GameData.creature_spec(sp)
		check_one.call("creatures", "res://assets/creatures/%s.png" % sp, ArtSpec.sheet_units_w(cs), float(cs["cell"].y))
	var seen := {}
	for it in GameData.ITEM_FILES:
		var f: String = GameData.ITEM_FILES[it]
		if seen.has(f):
			continue
		seen[f] = true
		check_one.call("items", "res://assets/resources/item_%s.png" % f, float(ArtSpec.ITEM.x), float(ArtSpec.ITEM.y))
	for kind in GatherDB.POINTS:
		var gs := ArtSpec.spec_of(GatherDB.POINTS[kind]["size"], ArtSpec.GATHER_FRAMES)
		check_one.call("gather", "res://assets/gather/%s.png" % kind, ArtSpec.sheet_units_w(gs), float(gs["cell"].y))
	for layer in ENV_HEIGHTS:
		check_one.call("environment", "res://assets/environment/%s.png" % layer, float(ArtSpec.BACKGROUND_W), float(ENV_HEIGHTS[layer]))
	for f in ["weight", "weight_mask"]:
		check_one.call("ui", "res://assets/ui/%s.png" % f, float(ArtSpec.UI_ICON.x), float(ArtSpec.UI_ICON.y))
	for slot in Rooms.SLOT_ORDER:
		var su := Rooms.slot_size(slot)
		for t in Rooms.TYPE_ORDER:
			if Rooms.can_place(t, slot):
				check_one.call("rooms", Rooms.overlay_path(slot, t), su.x, su.y)
	# 車体まわり（base）: 車体・斜路・車輪・加工機・設備
	check_one.call("base", "res://assets/base/hull.png", float(ArtSpec.HULL.x), float(ArtSpec.HULL.y))
	check_one.call("base", "res://assets/base/ramp.png", float(ArtSpec.RAMP.x), float(ArtSpec.RAMP.y))
	check_one.call("base", "res://assets/base/wheels.png", ArtSpec.sheet_units_w(ArtSpec.WHEELS), 30.0)
	check_one.call("base", "res://assets/base/machine.png", ArtSpec.sheet_units_w(ArtSpec.MACHINE), 26.0)
	for id in FacilityDB.ids():
		var spec := FacilityDB.sprite_spec(id)
		for i in int(FacilityDB.def(id)["max"]):
			var path := FacilityDB.sprite_path(id, i)
			check_one.call("base", path, ArtSpec.sheet_units_w(spec), float(spec["cell"].y))
			if String(FacilityDB.def(id)["sprite"]).find("%d") < 0:
				break
	# 外装: 車体と、絵の詰め合わせ（parts.json の units）
	var g := ExteriorDB.geo()
	check_one.call("exterior", ExteriorDB.dir() + "body.png", float(g["body"]["units"][0]), float(g["body"]["units"][1]))
	for sh in g["sheets"]:
		var u: Array = g["sheets"][sh]["units"]
		check_one.call("exterior", ExteriorDB.dir() + String(g["sheets"][sh]["file"]), float(u[0]), float(u[1]))
	for group in GROUPS:
		check(not bad.has(group) and int(count.get(group, 0)) > 0, "%s: %d 枚が、基準の大きさの %.0f 倍%s" % [group, int(count.get(group, 0)),
				float(expect.get(group, default)), String(bad.get(group, ""))])


# ---------------------------------------------------------------- 部屋の論理データ（絵から切り離されている）
func _test_rooms_logic() -> void:
	print("-- 部屋の論理データ（区画の大きさ・入口・決まった位置は、絵とは別）")
	for slot in Rooms.SLOT_ORDER:
		var s: Dictionary = Rooms.SLOTS[slot]
		var size := Rooms.slot_size(slot)
		check(size == Vector2(float(s["x1"] - s["x0"] + 1), float(s["feet"] - s["top"] + 2)) and Rooms.overlay_rect(slot).size == size * float(Rooms.UNIT),
				"%s: 区画の大きさ %s ユニット。画面上は ×%d（絵のドット数に依存しない）" % [slot, str(size), Rooms.UNIT])
		var dx: int = s["door_x"]
		check(dx < s["x0"] or dx > s["x1"], "%s: 入口の列 %d は区画の外側（隣との境）" % [slot, dx])
	check(Rooms.processor_pos("u1") == Vector2(GameData.MACHINE_X, GameData.UP_Y) and Rooms.storage_pos("l2") == Vector2(GameData.STORAGE_X, GameData.LO_Y)
			and Rooms.engine_pos("l1") == Vector2(GameData.ENGINE_X, GameData.LO_Y), "決まった位置（加工設備・倉庫・炉の口）は、初期配置ではこれまでと同じ位置")
	for rt in Rooms.ANCHORS:
		for an in Rooms.ANCHORS[rt]:
			check(Rooms.anchor_pos("u1" if Rooms.can_place(rt, "u1") else "l1", rt, an) == Rooms.local_to_world("u1" if Rooms.can_place(rt, "u1") else "l1", float(Rooms.ANCHORS[rt][an])),
					"%s の %s: 部屋の中の論理座標から、ワールド座標を計算する" % [rt, an])
	check(Rooms.local_to_world("u1", 10.0, 5.0) == Rooms.local_to_world("u1", 10.0) - Vector2(0, 5.0 * Rooms.UNIT), "床からの高さ（dy）は、上が正")
	check(Rooms.fallback_fuel_pos().x == GameData.HULL_POS.x + float(Rooms.FIXED[1]["anchors"]["fuel"]) * Rooms.UNIT, "搬入口の燃料の位置も、固定の部屋のデータから決まる")
	for id in FacilityDB.ids():
		check(FacilityDB.def(id).has("dx") and FacilityDB.def(id).has("room") and FacilityDB.def(id).has("frame") and FacilityDB.def(id).has("frames"),
				"%s: 設備は 部屋・部屋の中の位置（ユニット）・絵の基準の大きさ を、絵とは別に持つ" % id)


# ---------------------------------------------------------------- 描画のコードが、絵のドット数を決め打ちしていないか
func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _test_source_scan() -> void:
	print("-- 描画のコードの検査（絵のドット数を決め打ちしていない）")
	var files: Array = []
	for d in ["res://scripts", "res://ui", "res://data"]:
		var da := DirAccess.open(d)
		for f in da.get_files():
			if f.ends_with(".gd"):
				files.append(d + "/" + f)
	# 休眠中のPC側ファイル（個体・部署・セーブなど。現行ゲームでは読み込まれない）は対象外
	var dormant := ["balance.gd", "skill_db.gd", "unlocks.gd", "crew_gen.gd", "department.gd", "save_game.gd", "department_ui.gd", "desert_background.gd"]
	var patterns := {
		"絵の大きさ×PX（画面上の大きさを、絵のドット数から出している）": "(get_size\\(\\)|get_width\\(\\)|get_height\\(\\))\\)?\\s*\\*\\s*(GameData\\.|ArtSpec\\.)?(PX|UNIT_PX)",
		"4pxの格子への固定（位置を 4.0 で丸めている）": "\\(position\\s*/\\s*4\\.0\\)",
		"コマの切り出しの決め打ち（× 16 / × 30 など）": "\\*\\s*(14|16|22|28|30)\\s*,\\s*0\\s*,\\s*\\d+\\s*,",
	}
	# 検査そのものが働いていること（悪い書き方の例を見つけられる）
	var bad_samples := {
		"絵の大きさ×PX（画面上の大きさを、絵のドット数から出している）": "draw_texture_rect(hull, Rect2(p, Vector2(hull.get_size()) * GameData.PX), false)",
		"4pxの格子への固定（位置を 4.0 で丸めている）": "var snap := ((position / 4.0).round() * 4.0) - position",
		"コマの切り出しの決め打ち（× 16 / × 30 など）": "draw_texture_rect_region(t, r, Rect2(fr * 16, 0, 16, 16))",
	}
	for k in bad_samples:
		var re0 := RegEx.new()
		re0.compile(patterns[k])
		check(re0.search(bad_samples[k]) != null, "検査の確認: 悪い書き方を見つける（%s）" % k.left(12))
	var found := {}
	for k in patterns:
		found[k] = []
	for path in files:
		if path.get_file() in dormant or path.get_file() == "art_spec.gd":
			continue
		var text := _read(path)
		var lines := text.split("\n")
		for k in patterns:
			var re := RegEx.new()
			re.compile(patterns[k])
			for i in lines.size():
				var line: String = lines[i]
				if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"):
					continue
				if re.search(line) != null:
					found[k].append("%s:%d" % [path.get_file(), i + 1])
	for k in patterns:
		check(found[k].is_empty(), "%s: なし%s" % [k, "" if found[k].is_empty() else "（違反 %s）" % ", ".join(PackedStringArray(found[k]))])


# ---------------------------------------------------------------- 絵を差し替える（実行中に、最近傍で拡大した絵を作る）
func _walk(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for d in da.get_directories():
		_walk(dir + "/" + d, out)
	for f in da.get_files():
		if f.ends_with(".png") or f == "parts.json":
			out.append(dir + "/" + f)


func _group_of(rel: String) -> String:
	if rel.begins_with("characters/"):
		return "characters"
	if rel.begins_with("creatures/"):
		return "creatures"
	if rel.begins_with("resources/"):
		return "items"
	if rel.begins_with("gather/"):
		return "gather"
	if rel.begins_with("environment/"):
		return "environment"
	if rel.begins_with("ui/"):
		return "ui"
	if rel.begins_with("base/rooms/"):
		return "rooms"
	if rel.begins_with("base/exterior/"):
		return "exterior"
	return "base"


## groups の絵だけを factor 倍の細かさ（最近傍で拡大したもの）にして user:// に書き、絵の置き場所をそこへ向ける。
func _make_fixture(factor: int, groups: Array) -> String:
	var root_dir := "user://art_fixture_x%d_%d" % [factor, groups.size()]
	var files: Array = []
	_walk("res://assets", files)
	var n := 0
	for path in files:
		var rel: String = String(path).trim_prefix("res://assets/")
		if not (_group_of(rel) in groups):
			continue
		var dst := root_dir + "/" + rel
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst.get_base_dir()))
		if rel.ends_with(".png"):
			var img := Image.new()
			img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
			img.resize(img.get_width() * factor, img.get_height() * factor, Image.INTERPOLATE_NEAREST)
			img.save_png(ProjectSettings.globalize_path(dst))
		else:
			var geo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			for sh in geo["sheets"].values():
				for k in sh["frames"]:
					var f: Array = sh["frames"][k]
					sh["frames"][k] = [f[0] * factor, f[1] * factor, f[2] * factor, f[3] * factor]
			var fh := FileAccess.open(ProjectSettings.globalize_path(dst), FileAccess.WRITE)
			fh.store_string(JSON.stringify(geo, " "))
			fh.close()
		n += 1
	return root_dir


## ゲーム側の「座標・大きさ・置き場所」の一覧（絵の細かさに依存してはいけないものだけ）
func _signature() -> Dictionary:
	var sig := {}
	sig["processor"] = main.processor.position
	sig["storage"] = main.storage.position
	sig["engine"] = main.base.engine_point()
	sig["beds"] = main.base.facility_spots("bed")
	sig["bench"] = main.base.facility_spots("workbench")
	var rects := []
	for s in Rooms.SLOT_ORDER:
		rects.append(Rooms.overlay_rect(s))
	sig["overlays"] = rects
	sig["inside"] = [main.base.is_inside(Vector2(600, 482)), main.base.is_inside(Vector2(950, 516)), main.base.is_inside(Vector2(620, 640))]
	var parts := []
	for p in ExteriorDB.PARTS:
		parts.append([p["id"], ExteriorDB.frame_units(p), ExteriorDB.at_of(p, "u1" if String(p.get("kind", "fixed")) == "slot" else "", -1.0)])
	sig["parts"] = parts
	sig["windows"] = [ExteriorDB.window_rect("u1"), ExteriorDB.window_rect("l2"), ExteriorDB.cab_rect()]
	sig["worker_px"] = ArtSpec.px_size(ArtSpec.WORKER["cell"])
	sig["wheel_px"] = ArtSpec.px_size(ArtSpec.WHEELS["cell"])
	sig["gauge"] = main.status._weight.display_size
	var hp: BaseHPGauge = main.status._gauges["hull"]
	hp.update_appearance(main)
	sig["hp_silhouette"] = [hp.display_size, hp._text_center, hp._frame.get_image().get_data(), hp.fill_dots()]
	return sig


func _new_game() -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false


func _test_swap(factor: int, groups: Array, label: String) -> void:
	print("-- 絵の差し替え: %s（×%d）" % [label, factor])
	ArtSpec.set_root_override("")
	await _new_game()
	var before := _signature()
	var dir := _make_fixture(factor, groups)
	ArtSpec.set_root_override(dir)
	var expect := {}
	for g in groups:
		expect[g] = float(factor)
	_test_contracts(expect, 1.0, "差し替え後")
	await _new_game()                                                # 新しいゲームを、差し替えた絵で始める
	var after := _signature()
	check(before == after, "座標・大きさ・置き場所（加工設備・倉庫・ベッド・部屋の重ね絵・外装パーツ・窓・仲間と車輪の大きさ・ゲージ）が、差し替え前と完全に同じ")
	# 差し替えた絵で、内装・外装・部屋の変更・建設の画面を動かす（描画のコードがエラーを出さない。出力にエラーが出れば実行ツールが検出する）
	var draws := {"n": 0}
	main.base.exterior.draw.connect(func(): draws["n"] += 1)
	Engine.time_scale = 4.0
	for m in [BaseView.Mode.INTERIOR, BaseView.Mode.EXTERIOR, BaseView.Mode.INTERIOR]:
		main.base_view.set_mode(m, true)
		for i in 60:
			await process_frame
	main.build_room("l1", "empty")
	main.room_ui.open()
	main.build_ui.open()
	for i in 30:
		await process_frame
	main.room_ui.close()
	main.build_ui.close()
	Engine.time_scale = 1.0
	check(true, "差し替えた絵で、内装・外装・部屋の変更・建設の画面を動かした（描画 %d 回。エラーなし）" % int(draws["n"]))
	# アイコンゲージ: 画面上の大きさは同じで、充填は細かくなる
	var g: IconGauge = main.status._weight
	check(g.display_size == Vector2(48, 48) and is_equal_approx(g.pixel * float(g._icon_size.x), 48.0), "積載ゲージの画面上の大きさは 48x48 のまま（絵のドットは %d 個。1ドット %.1fpx）" % [g.fill_dots().size(), g.pixel])
	var total := g.fill_dots().size()
	g.set_value(0.5, 1.0, "")
	check(absf(float(g.filled_count()) / float(total) - 0.5) < 0.02, "充填は、絵のドットの面積が基準なので、細かい絵でも 50%% は半分（%d/%d）" % [g.filled_count(), total])
	ArtSpec.set_root_override("")
	await _new_game()
	check(_signature() == before, "元の絵に戻すと、元どおり")
