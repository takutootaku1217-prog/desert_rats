extends SceneTree
## 積載重量のアイコンゲージ（ui/icon_gauge.gd）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_icon_gauge.gd
## 確かめる: 重量の取得口（current_weight / max_weight / weight_ratio）→ 絵（枠と充填範囲）→ 充填の規則（下から・実際のドットの面積が基準）→
##   色の段階（増えるほど濃い・差し替えできる）→ 部品の見た目（充填数・色・数字の位置）→ 右上の状態への組み込み → 別の形でも使い回せるか。

var fails := 0
var main


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260926)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	_test_weight_api()
	_test_art()
	_test_fill_rules()
	_test_colors()
	await _test_gauge()
	await _test_status_panel()
	_test_reuse()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## 色が同じか（画像に書くと8bitに丸められるので、少しの差は同じとみなす）
func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


func _clear() -> void:
	main.storage.inventory.counts.clear()


## 先頭から n ドット埋めたときの、埋めた高さの割合（全体の高さに対する。途中の行は、その行のドットのうち埋めた割合だけ数える）
func _fill_height(order: Array, n: int) -> float:
	var rows := {}                                  # 行 -> その行のドット数
	for p in order:
		rows[p.y] = int(rows.get(p.y, 0)) + 1
	var filled := {}
	for i in n:
		filled[order[i].y] = int(filled.get(order[i].y, 0)) + 1
	var h := 0.0
	for y in filled:
		h += float(filled[y]) / float(rows[y])
	return h / float(rows.size())


# ---------------------------------------------------------------- 重量の取得口
func _test_weight_api() -> void:
	print("-- 重量の取得口（既存の積載量の計算をそのまま使う）")
	var st: BaseStorage = main.storage
	_clear()
	check(st.current_weight() == 0 and st.weight_ratio() == 0.0, "空なら重量0・積載率0")
	var cap := 0
	for bay in CargoDB.BAY_NAMES:
		cap += CargoDB.CAPACITY[bay]
	check(st.max_weight() == cap, "最大積載重量は、区画ごとの積載量の合計（%d）" % cap)
	st.add_item(GameData.Item.WOOD, 6)
	st.add_item(GameData.Item.FOOD, 4)
	check(st.current_weight() == st.used_in(CargoDB.Bay.RAW) + st.used_in(CargoDB.Bay.PRODUCT) and st.current_weight() == 10,
			"重量は、素材棚と加工品置き場の合計（used_in の合計）")
	check(absf(st.weight_ratio() - 10.0 / float(cap)) < 0.0001, "積載率 = 重量 ÷ 最大重量")
	st.add_item(GameData.Item.HAMMER, 3)
	check(st.current_weight() == 10, "道具は倉庫の積載量の対象外なので、重量に入らない（従来どおり）")
	st.capacity_bonus[CargoDB.Bay.RAW] = 12
	check(st.max_weight() == cap + 12 and st.weight_ratio() < 10.0 / float(cap), "拠点の強化で積載量が増えると、最大重量が増え、積載率が下がる")
	st.capacity_bonus.clear()
	for it in st.quota:
		st.inventory.counts[it] = st.quota_of(it)
	check(st.current_weight() == st.max_weight() and st.weight_ratio() == 1.0, "すべての枠が埋まると積載率は1（満載）")
	_clear()
	# 既存の積載管理は変わっていない（枠がいっぱいなら入りきらない分は捨てる）
	st.add_item(GameData.Item.WOOD, 99)
	check(st.count_of(GameData.Item.WOOD) == st.quota_of(GameData.Item.WOOD), "積載管理（枠を超えると捨てる）は従来どおり")
	_clear()


# ---------------------------------------------------------------- 絵
func _test_art() -> void:
	print("-- 絵（16x16のオリジナル。枠と充填範囲の2枚）")
	check(FileAccess.file_exists("res://assets/ui/weight.png") and FileAccess.file_exists("res://assets/ui/weight_mask.png"), "枠と充填範囲の絵がある")
	var frame := IconGauge._load_image("res://assets/ui/weight.png")
	var mask := IconGauge._load_image("res://assets/ui/weight_mask.png")
	check(frame.get_size() == Vector2i(16, 16) and mask.get_size() == Vector2i(16, 16), "どちらも 16x16")
	var dots := IconGauge.fill_order(mask)
	check(dots.size() >= 40, "充填範囲のドット数が十分にある（%d）" % dots.size())
	var overlap := 0
	for p in dots:
		if frame.get_pixelv(p).a > 0.0:
			overlap += 1
	check(overlap == 0, "枠は充填範囲にかぶらない（充填した色が見える）")
	var frame_dots := 0
	for y in 16:
		for x in 16:
			if frame.get_pixel(x, y).a > 0.0:
				frame_dots += 1
	check(frame_dots >= 40, "枠の輪郭がある（%dドット）" % frame_dots)
	# 底が広く上が細い形（面積基準の意味が出る形）
	var widths := {}
	for p in dots:
		widths[p.y] = int(widths.get(p.y, 0)) + 1
	var ys: Array = widths.keys()
	ys.sort()
	check(widths[ys[ys.size() - 1]] > widths[ys[0]], "下の行のほうが広い（上 %d ドット → 下 %d ドット）" % [widths[ys[0]], widths[ys[ys.size() - 1]]])


# ---------------------------------------------------------------- 充填の規則
func _test_fill_rules() -> void:
	print("-- 充填の規則（下から上へ・実際のドットの面積が基準）")
	var mask := IconGauge._load_image("res://assets/ui/weight_mask.png")
	var order := IconGauge.fill_order(mask)
	var total := order.size()
	var monotone := true
	for i in range(1, total):
		if order[i].y > order[i - 1].y:
			monotone = false
	check(monotone, "充填の順は、下の行から上の行へ（上の行を先に埋めない）")
	check(IconGauge.fill_count(0.0, total) == 0, "0% は何も埋めない")
	check(IconGauge.fill_count(0.004, total) == 1, "ほんの少しでも積んでいれば、1ドットは見せる")
	check(IconGauge.fill_count(1.0, total) == total, "100% は全部を埋める")
	check(IconGauge.fill_count(0.999, total) == total - 1, "満載になるまでは全部を埋めない")
	var prev := -1
	var inc := true
	var max_err := 0.0
	for i in range(0, 101):
		var r := float(i) / 100.0
		var n := IconGauge.fill_count(r, total)
		if n < prev:
			inc = false
		prev = n
		if i >= 3 and i <= 97:
			max_err = maxf(max_err, absf(float(n) / float(total) - r))
	check(inc, "割合が増えると、埋めるドットは減らない")
	check(max_err <= 0.5 / float(total) + 0.0001, "埋めた面積の割合は、割合との差が半ドット以内（最大 %.3f）" % max_err)
	# 面積基準: 底が広い形では、50% の面積は「高さの半分」より低い所までで埋まる
	var n50 := IconGauge.fill_count(0.5, total)
	var hf := _fill_height(order, n50)
	check(hf < 0.5, "50%% の重量は、高さの半分より低い所まで（高さ %.0f%%）＝ 底が広い分、見た目にも約半分の量" % (hf * 100.0))
	# 高さで埋めた場合（面積を見ない従来の方式）との違い: 50%の高さまで埋めると、面積は半分を超える
	var area_at_half_height := 0
	var y_mid := (float(order[0].y) + float(order[total - 1].y)) / 2.0
	for p in order:
		if float(p.y) >= y_mid:
			area_at_half_height += 1
	check(float(area_at_half_height) / float(total) > 0.5, "参考: 高さで50%%まで埋める方式だと、面積は %.0f%% になってしまう（面積基準にした理由）" % (100.0 * float(area_at_half_height) / float(total)))
	# 行の途中は中心から左右へ
	var y_row: int = order[0].y
	var xs: Array = []
	for p in order:
		if p.y == y_row:
			xs.append(p.x)
	var center_first: bool = absf(float(xs[0]) - (float(xs.min()) + float(xs.max())) / 2.0) <= 0.5
	check(center_first, "1つの行は、中心のドットから左右へ埋まる")


# ---------------------------------------------------------------- 色の段階
func _test_colors() -> void:
	print("-- 重量による色（増えるほど濃い。差し替えできる）")
	var st := UIKit.GAUGE_STAGES_LOAD
	check(st.size() == 5, "色の段階は5つ（薄い・少し濃い・中間・濃い・非常に濃い）")
	var idx := func(r: float) -> int:
		for i in st.size():
			if r <= float(st[i][0]):
				return i
		return st.size() - 1
	check(idx.call(0.0) == 0 and idx.call(0.25) == 0, "0〜25% は薄い")
	check(idx.call(0.26) == 1 and idx.call(0.50) == 1, "25〜50% は少し濃い")
	check(idx.call(0.51) == 2 and idx.call(0.75) == 2, "50〜75% は中間")
	check(idx.call(0.76) == 3 and idx.call(0.90) == 3, "75〜90% は濃い")
	check(idx.call(0.91) == 4 and idx.call(1.0) == 4, "90〜100% は非常に濃い")
	var dark := true
	for i in range(1, st.size()):
		var a: Color = st[i - 1][1]
		var b: Color = st[i][1]
		if b.get_luminance() >= a.get_luminance():
			dark = false
	check(dark, "段階が上がるほど、色は濃く（暗く）なる")
	check(IconGauge.stage_color(st, 0.6) == st[2][1] and IconGauge.stage_color(st, 5.0) == st[4][1], "割合から色が決まる（範囲外でも最後の色）")
	var custom := [[0.5, Color.GREEN], [1.01, Color.RED]]
	check(IconGauge.stage_color(custom, 0.3) == Color.GREEN and IconGauge.stage_color(custom, 0.8) == Color.RED, "色の表は差し替えられる")


# ---------------------------------------------------------------- 部品の見た目
func _test_gauge() -> void:
	print("-- アイコンゲージの部品（充填数・色・数字の位置）")
	var g := IconGauge.new().setup("weight")
	root.add_child(g)
	await process_frame
	check(g.custom_minimum_size == Vector2(64, 64) and g.display_size == ArtSpec.px_size(ArtSpec.UI_ICON), "画面上の大きさは、基準の大きさ（16ユニット）× 4px で 64x64（絵のドット数に依存しない）")
	var total: int = g.fill_dots().size()
	var read := func() -> Dictionary:
		var img: Image = g.interior_image()
		var filled := 0
		var empty := 0
		var color := Color(0, 0, 0, 0)
		for p in g.fill_dots():
			var c: Color = img.get_pixelv(p)
			if _same(c, g.empty_color):
				empty += 1
			else:
				filled += 1
				color = c
		return {"filled": filled, "empty": empty, "color": color}
	for r in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]:
		g.set_value(r * 200.0, 200.0, str(int(r * 200.0)))
		await process_frame
		var d: Dictionary = read.call()
		check(d["filled"] == IconGauge.fill_count(r, total) and d["filled"] + d["empty"] == total,
				"%d%%: 充填 %d / %d ドット" % [int(r * 100.0), d["filled"], total])
		if r > 0.0:
			check(_same(d["color"], IconGauge.stage_color(UIKit.GAUGE_STAGES_LOAD, r)), "%d%%: 段階の色で埋まる" % int(r * 100.0))
		check(g.text == str(int(r * 200.0)), "%d%%: 数字は絵の内側に出す（%s）" % [int(r * 100.0), g.text])
	# 下から埋まっている（埋めたドットの最上行より上は、すべて空）
	g.set_value(0.4, 1.0, "80")
	var img: Image = g.interior_image()
	var top_filled := 99
	var bottom_empty := -1
	for p in g.fill_dots():
		var c: Color = img.get_pixelv(p)
		if _same(c, g.empty_color):
			bottom_empty = maxi(bottom_empty, p.y)
		else:
			top_filled = mini(top_filled, p.y)
	check(top_filled >= 0 and bottom_empty <= top_filled, "40%%: 埋まっているのは下の部分だけ（空の最下行 %d・埋めた最上行 %d）" % [bottom_empty, top_filled])
	# 数字の位置 = 充填範囲の中心（外ではなく、絵の内側）
	var c: Vector2 = g._text_center
	var inside := false
	for p in g.fill_dots():
		if int(c.x) == p.x and int(c.y) == p.y:
			inside = true
	check(inside, "数字の位置は充填範囲の内側（ドット %s）" % str(c))
	# 値のはみ出し・0除算
	g.set_value(500.0, 200.0, "500")
	check(g.ratio == 1.0, "最大を超えても 100% で止まる")
	g.set_value(10.0, 0.0, "0")
	check(g.ratio == 0.0, "最大が0でも壊れない")
	g.set_blink(true)
	check(g.is_processing(), "点滅を有効にできる（危険域のゲージ用）")
	g.set_blink(false)
	g.queue_free()


# ---------------------------------------------------------------- 右上の状態への組み込み
func _test_status_panel() -> void:
	print("-- 右上の状態への組み込み（既存の積載重量表示の置き換え）")
	var sp: StatusPanel = main.status
	var st: BaseStorage = main.storage
	_clear()
	sp._process(0.0)
	var w: IconGauge = sp._weight
	check(w != null and w.text == "0" and w.ratio == 0.0, "空のとき、重りは空で数字は 0")
	check(sp.get("_cargo") == null and not ("_bars" in sp), "横長ゲージや「積載 x/y」の文字表示は使わない")
	st.add_item(GameData.Item.WOOD, 8)
	st.add_item(GameData.Item.FOOD, 10)
	st.add_item(GameData.Item.STONE, 6)
	sp._process(0.0)
	check(w.text == str(st.current_weight()) and w.text == "24", "数字は実際の積載重量（%s）" % w.text)
	check(absf(w.ratio - st.weight_ratio()) < 0.0001, "充填率は実際の積載率（%.2f）" % w.ratio)
	check(w.tooltip_text.contains("素材棚") and w.tooltip_text.contains("加工品置き場") and w.tooltip_text.contains("%d / %d" % [st.current_weight(), st.max_weight()]),
			"マウスを載せると、区画ごとの内訳が出る")
	main.total_wasted = 3
	sp._process(0.0)
	check(w.tooltip_text.contains("捨てた 3"), "捨てた数もツールチップに出る（画面から消えない）")
	main.total_wasted = 0
	for it in st.quota:
		st.inventory.counts[it] = st.quota_of(it)
	sp._process(0.0)
	check(w.ratio == 1.0 and w.filled_count() == w.fill_dots().size(), "満載: 重りが全部埋まる")
	_clear()
	sp._process(0.0)
	# 位置: 右上の拠点の状態の中（ほかのゲージと並ぶ）。右のボタン列には重ならない
	var wr: Rect2 = w.get_global_rect()
	check(wr.position.x >= 1000.0 and wr.end.y < 200.0, "積載重量のアイコンは、右上の状態の中の、ほかのゲージと並ぶ位置にある（%s）" % str(wr))
	for k in ["hull", "drive", "machine", "fuel", "weight"]:
		check(sp._gauges.has(k) and sp._gauges[k] is IconGauge, "アイコンゲージ（%s）がある" % k)
	await process_frame


# ---------------------------------------------------------------- 別の形でも使い回せるか
func _test_reuse() -> void:
	print("-- 使い回し（HP・満腹度など別の形のアイコンにも使える共通処理）")
	# 上が細く下が太い三角形と、上が広い逆三角形。どちらでも「下から・面積基準」で埋まる
	var tri := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var inv := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		var half := 0.5 + float(y) * 0.5                  # 上は細く下は太い
		for x in 8:
			if absf(float(x) + 0.5 - 4.0) <= half:
				tri.set_pixel(x, y, Color(1, 1, 1, 1))
			if absf(float(x) + 0.5 - 4.0) <= 4.0 - float(y) * 0.5:
				inv.set_pixel(x, y, Color(1, 1, 1, 1))
	for pair in [["下が太い形", tri], ["上が太い形", inv]]:
		var o := IconGauge.fill_order(pair[1])
		var t := o.size()
		var n := IconGauge.fill_count(0.5, t)
		print("       %s: 50%% で埋まる高さ %.0f%%" % [pair[0], _fill_height(o, n) * 100.0])
		check(absf(float(n) / float(t) - 0.5) <= 0.5 / float(t) + 0.0001, "%s: 50%% の面積を埋める（%d/%dドット）" % [pair[0], n, t])
	var ot := IconGauge.fill_order(tri).size()
	var oi := IconGauge.fill_order(inv).size()
	check(ot > 0 and oi > 0, "別のマスクでも充填の順を作れる（面積 %d・%d）" % [ot, oi])
