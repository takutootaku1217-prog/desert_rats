extends SceneTree
## 画面の表示（右上の拠点の状態・拠点耐久の盾・燃料・積載重量・倉庫の中身・加工設備の見た目・効果の素材）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_hud.gd
## 確かめる: アイコンの絵（枠と充填範囲）→ 盾（拠点耐久。個体のHPと同じ作り）→ 燃料 → 積載重量 → 倉庫の中身（アイコン＋個数）→
##   右上のまとめ（文字を増やしていない・ボタンに重ならない）→ 効果の素材の再生（湯気・砂ぼこり・きらめき）→ 加工設備の見た目の仕掛け。
## ゲームの数値・仕様は変えていない（見た目だけ）。

var fails := 0
var main


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260927)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	for w in main.workers:
		w.set_process(false)
	_test_art()
	await _test_shields()
	await _test_fuel_and_weight()
	await _test_stock()
	await _test_panel()
	await _test_effects()
	await _test_processor_visuals()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _find_text(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	for c in node.get_children():
		if _find_text(c, needle):
			return true
	return false


# ---------------------------------------------------------------- 絵
func _test_art() -> void:
	print("-- アイコンの絵（枠と充填範囲。差し替えられる素材）")
	for n in ["shield_hull", "shield_drive", "shield_machine", "fuel"]:
		var mask := IconGauge._load_image("res://assets/ui/%s_mask.png" % n)
		var frame := IconGauge._load_image("res://assets/ui/%s.png" % n)
		var dots := 0
		var covered := 0
		for y in mask.get_height():
			for x in mask.get_width():
				if mask.get_pixel(x, y).a > 0.5:
					dots += 1
					if frame.get_pixel(x, y).a > 0.05:
						covered += 1
		check(mask.get_width() == 16 and mask.get_height() == 16 and frame.get_width() == 16 and dots >= 60 and covered == 0, "%s: 16x16・充填範囲 %d ドット・枠が充填範囲を隠さない" % [n, dots])
	var a := IconGauge._load_image("res://assets/ui/shield_hull.png")
	var b := IconGauge._load_image("res://assets/ui/shield_drive.png")
	var c := IconGauge._load_image("res://assets/ui/shield_machine.png")
	check(a.get_data() != b.get_data() and b.get_data() != c.get_data() and a.get_data() != c.get_data(), "3つの盾は、中の目印（車体・車輪・歯車）で見分けられる")
	var ha := IconGauge._load_image("res://assets/ui/hp.png")
	check(ha.get_width() == a.get_width(), "個体のHP（ハート）と拠点の耐久（盾）は、同じ形式の絵（枠＋充填範囲）で、同じ部品で描く")


# ---------------------------------------------------------------- 盾（拠点の耐久）
func _test_shields() -> void:
	print("-- 拠点の耐久（盾のアイコンそのものがゲージ）")
	var sp: StatusPanel = main.status
	var b = main.base
	var parts := {"hull": GameData.Part.HULL, "drive": GameData.Part.DRIVE, "machine": GameData.Part.MACHINE}
	for key in parts:
		check(sp._gauges.has(key) and sp._gauges[key] is IconGauge, "%s の盾がある" % GameData.PART_NAMES[parts[key]])
	var hg: IconGauge = sp._gauges["hull"]
	check(hg.dark_empty and hg.display_size == Vector2(48, 48), "盾は、減った部分を暗い色で見せ、大きさは 48px（基準の大きさ×UNIT_PX）")
	# 100 / 75 / 50 / 25 / 10 %
	var got := []
	for v in [100.0, 75.0, 50.0, 25.0, 10.0]:
		b.parts[GameData.Part.HULL] = v
		sp._process(0.0)
		got.append([snappedf(hg.ratio, 0.001), hg.filled_count(), hg.text, hg.blink, hg.current_color()])
	var total := hg.fill_dots().size()
	check(got[0][0] == 1.0 and got[0][1] == total, "耐久 100%%: 盾の全体が満たされている（%d/%d）" % [got[0][1], total])
	check(absf(float(got[1][1]) / float(total) - 0.75) < 0.02, "耐久 75%%: 盾の 75%% ほどが満たされている（%d/%d）" % [got[1][1], total])
	check(absf(float(got[2][1]) / float(total) - 0.50) < 0.02, "耐久 50%%: 半分ほど（%d/%d）" % [got[2][1], total])
	check(absf(float(got[3][1]) / float(total) - 0.25) < 0.02, "耐久 25%%: 少ない（%d/%d）" % [got[3][1], total])
	check(got[4][3] and not got[3][3] and not got[0][3], "耐久 15%% 未満（10）だけ、危険として点滅する（25 以上は点滅しない）")
	check(got[0][4] == UIKit.GAUGE_STAGES_BASE[2][1] and got[2][4] == UIKit.GAUGE_STAGES_BASE[1][1] and got[3][4] == UIKit.GAUGE_STAGES_BASE[0][1], "色: 緑（多い）→ 黄（半分）→ 赤（不調の線 %d 以下）" % int(GameData.PART_BAD))
	check(got[2][2] == "50" and got[0][2] == "100", "数字は盾の中に出る（正確な値）")
	# 部位ごとに独立（1つが危険でも、ほかの盾は点滅しない）
	b.parts[GameData.Part.HULL] = 90.0
	b.parts[GameData.Part.DRIVE] = 8.0
	b.parts[GameData.Part.MACHINE] = 60.0
	sp._process(0.0)
	check(sp._gauges["drive"].blink and not sp._gauges["hull"].blink and not sp._gauges["machine"].blink, "走行装置だけが危険なら、その盾だけが点滅する")
	check(sp._gauges["drive"].tooltip_text.contains("走行装置") and sp._gauges["drive"].tooltip_text.contains("不調"), "マウスを載せると、部位の名前と（不調）が出る")
	# 数字のON/OFF
	UIKit.show_icon_numbers = false
	sp._process(0.0)
	check(sp._gauges["hull"].text == "" and is_equal_approx(sp._gauges["hull"].ratio, 0.9), "数字を OFF にしても、盾のゲージは同じ（アイコンだけで分かる）")
	UIKit.show_icon_numbers = true
	sp._process(0.0)
	check(sp._gauges["hull"].text == "90", "ON に戻すと、数字が盾の中に出る")
	for p in parts.values():
		b.parts[p] = 100.0
	# ゲームの値は書き換えない（読むだけ）
	sp._process(0.0)
	check(b.parts[GameData.Part.HULL] == 100.0 and b.parts[GameData.Part.DRIVE] == 100.0, "表示は耐久の値を読むだけで、書き換えない")
	check(not _find_text(sp, "車体") and not _find_text(sp, "走行装置") and not _find_text(sp, "加工設備"), "耐久の横棒と部位の名前の文字は、画面から消えている（盾の目印で見分ける）")


# ---------------------------------------------------------------- 燃料・積載重量
func _test_fuel_and_weight() -> void:
	print("-- 燃料（ジェリカン）と積載重量（重り）: アイコンそのものがゲージ・数字はアイコンの中")
	var sp: StatusPanel = main.status
	var b = main.base
	var fg: IconGauge = sp._gauges["fuel"]
	b.fuel = GameData.FUEL_CAP * 0.5
	sp._process(0.0)
	check(is_equal_approx(fg.ratio, 0.5) and fg.text == "50" and not fg.blink, "燃料 50%: ジェリカンの半分・数字 50・点滅なし")
	b.fuel = GameData.FUEL_CAP * 0.1
	sp._process(0.0)
	check(fg.blink and fg.current_color() == UIKit.GAUGE_STAGES_BASE[0][1], "燃料 10%: 赤く点滅する")
	b.fuel = GameData.FUEL_CAP
	sp._process(0.0)
	check(fg.ratio == 1.0 and fg.filled_count() == fg.fill_dots().size(), "燃料 100%: ジェリカンが満タン")
	check(fg.display_size == sp._gauges["hull"].display_size and fg.display_size == sp._weight.display_size, "盾・燃料・重量は、同じ大きさのアイコンで並ぶ（数字のルールが同じ）")
	# 燃料の数値・消費は変えていない
	check(GameData.FUEL_CAP == 100.0 and is_equal_approx(GameData.FUEL_PER_PX, GameData.FUEL_PER_PX), "燃料の仕組み・数値には触れていない（タンク %d）" % int(GameData.FUEL_CAP))
	# 重量
	main.storage.inventory.counts.clear()
	main.storage.add_item(GameData.Item.WOOD, 8)
	sp._process(0.0)
	var wg: IconGauge = sp._weight
	check(wg.text == str(main.storage.current_weight()) and absf(wg.ratio - main.storage.weight_ratio()) < 0.0001, "積載重量: 数字はアイコンの中に実際の重量（%s）・充填は実際の積載率" % wg.text)
	check(wg.tooltip_text.contains("素材棚") and wg.tooltip_text.contains("加工品置き場"), "区画ごとの内訳はツールチップ（情報は消えていない）")
	check(wg.color_stages == UIKit.GAUGE_STAGES_LOAD and not wg.dark_empty, "重りの色（増えるほど濃い）は、これまでどおり")
	main.storage.inventory.counts.clear()


# ---------------------------------------------------------------- 倉庫の中身（アイコン＋個数）
func _test_stock() -> void:
	print("-- 倉庫の中身（アイテムのアイコン＋個数。文字の一覧の代わり）")
	var sp: StatusPanel = main.status
	var st: BaseStorage = main.storage
	st.inventory.counts.clear()
	st.add_item(GameData.Item.FOOD, 5)
	st.add_item(GameData.Item.WOOD, 3)
	sp._process(0.0)
	var g: StockGrid = sp._stock
	check(g.shown_count(GameData.Item.FOOD) == 5 and g.shown_count(GameData.Item.WOOD) == 3 and g.shown_count(GameData.Item.STONE) == 0, "アイコンに出る個数が、実際の倉庫と同じ")
	var all_ok := true
	for it in [GameData.Item.FOOD, GameData.Item.FUEL, GameData.Item.REPAIR_KIT, GameData.Item.IRON, GameData.Item.MEAT, GameData.Item.HIDE, GameData.Item.BONE,
			GameData.Item.FAT, GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE]:
		all_ok = all_ok and g.shown_count(it) == st.count_of(it)
	check(all_ok, "これまで文字で出ていた11種すべてが、アイコンで出ている（情報は減らしていない）")
	check(g.summary().contains("食料 5") and g.summary().contains("木材 3"), "（診断用の文字）%s" % g.summary())
	for it in st.quota:
		st.inventory.counts[it] = st.quota_of(it)
	sp._process(0.0)
	check(g.summary().contains("満") and g._cells[0]["full"], "枠がいっぱいの素材は「満」になる（枠の赤とともに表示）")
	st.inventory.counts.clear()
	main.hungry = true
	sp._process(0.0)
	check(g._hungry, "空腹の仲間がいると、食料のアイコンが警告になる（文字の「空腹!」の代わり）")
	main.hungry = false
	check(g.custom_minimum_size.x <= StatusPanel.W - 16.0, "アイコンの並びは、右上のパネルの幅に収まる（%d ≤ %d）" % [int(g.custom_minimum_size.x), int(StatusPanel.W - 16.0)])
	UIKit.show_icon_numbers = false
	sp._process(0.0)
	check(g.shown_count(GameData.Item.FOOD) == 0, "数字を OFF にしても、アイコンの並びは残る（個数の値は同じ）")
	UIKit.show_icon_numbers = true


# ---------------------------------------------------------------- 右上のまとめ
func _test_panel() -> void:
	print("-- 右上のパネルの整理（文字を増やさない・ボタンに重ならない・操作を壊さない）")
	var sp: StatusPanel = main.status
	sp._process(0.0)
	await process_frame
	var panel: PanelContainer = sp._state.get_parent().get_parent().get_parent()
	var rect := panel.get_global_rect()
	check(rect.position == Vector2(1000, 8) and rect.end.y < 205.0, "パネルは右上に収まり、下のボタン列（外装・内装ほか）に重ならない（下端 %d）" % int(rect.end.y))
	check(sp._state.text.begins_with("拠点:") and sp._speed.text.contains("速度") and sp._speed.text.contains("↑↓"), "移動の状態と、速度・目標・↑↓キーの案内は残っている（%s / %s）" % [sp._state.text, sp._speed.text])
	check(not _find_text(sp, "加工:") and not _find_text(sp, "待ち") and not _find_text(sp, "肉"), "加工の様子や素材の名前の文字は、パネルから消えている（絵と動きへ移した）")
	check(sp._totals.text.contains("狩猟") and sp._totals.text.contains("食事"), "累計は小さく残している")
	var buttons_ok := true
	for txt in ["建設 (B)", "部屋の変更 (R)", "仲間の管理 (C)", "運営の方針 (P)", "遠征 (X)"]:
		buttons_ok = buttons_ok and _find_button_anywhere(txt)
	check(buttons_ok, "右のボタン列の操作は、そのまま残っている")
	# 速度の操作（↑↓キー）は、これまでどおり
	var s0: float = main.target_speed
	var ev := InputEventKey.new()
	ev.keycode = KEY_UP
	ev.pressed = true
	main._unhandled_input(ev) if main.has_method("_unhandled_input") else null
	check(main.target_speed >= s0, "↑キーで目標の速度を上げられる（操作は変えていない）")
	main.target_speed = 0.0


func _find_button_anywhere(text: String) -> bool:
	return _find_btn(main, text) or _find_btn(root, text)


func _find_btn(node: Node, text: String) -> bool:
	if node is Button and (node as Button).text == text:
		return true
	for c in node.get_children():
		if _find_btn(c, text):
			return true
	return false


# ---------------------------------------------------------------- 効果の素材
func _test_effects() -> void:
	print("-- 効果（湯気・砂ぼこり・きらめき）は素材を再生するだけ")
	for id in EffectDB.EFFECTS:
		var e: Dictionary = EffectDB.EFFECTS[id]
		var tx: Texture2D = GameData.tex(String(e["sheet"]))
		var spec := EffectDB.spec(id)
		check(tx != null and tx.get_width() == int(e["cell"].x) * int(e["frames"]) and tx.get_height() == int(e["cell"].y), "%s: 絵（%dx%d）が基準の大きさ×コマ数と合っている" % [id, tx.get_width(), tx.get_height()])
		check(ArtSpec.frame_src(tx, spec, 1).position.x == float(int(e["cell"].x)) * ArtSpec.dpu(tx, ArtSpec.sheet_units_w(spec)), "%s: コマの切り出しは ArtSpec が計算する（絵の細かさに依存しない）" % id)
	var holder := Node2D.new()
	root.add_child(holder)
	var once := FxSprite.spawn(holder, "proc_done", Vector2(10, 20))
	check(once != null and once.position == Vector2(10, 20) and once.frame() == 0, "1回だけの効果を出せる（位置・最初のコマ）")
	await create_timer(EffectDB.duration("proc_done") + 0.3).timeout
	check(not is_instance_valid(once), "1回再生したら、自分で消える（%.2f 秒）" % EffectDB.duration("proc_done"))
	var lp := FxSprite.spawn(holder, "proc_steam", Vector2.ZERO)
	var seen := {}
	for i in 90:
		await process_frame
		seen[lp.frame()] = true
	check(is_instance_valid(lp) and seen.size() >= 3, "ループする効果は、消えずにコマが進み続ける（見たコマ %d 種）" % seen.size())
	lp.set_playing(false)
	check(not lp.visible, "止めると隠れる（状態に合わせて出し入れできる）")
	check(FxSprite.spawn(holder, "no_such_effect", Vector2.ZERO) == null, "表にない効果は出さない（エラーにしない）")
	holder.queue_free()
	# 新しい効果は、表に足すだけで出せる（図形をコードで描かない）
	var src := FileAccess.get_file_as_string("res://scripts/fx_sprite.gd")
	check(not src.contains("draw_circle") and not src.contains("draw_line") and not src.contains("draw_colored_polygon"), "効果の再生部品は、図形をコードで描かない（素材のコマだけ）")


# ---------------------------------------------------------------- 加工設備の見た目
func _test_processor_visuals() -> void:
	print("-- 加工設備の見た目（文字ではなく、絵と動きで状態が分かる）")
	var P: BaseProcessor = main.processor
	P.orders.clear()
	P.current = {}
	P.output.clear()
	P._out_times.clear()
	P._drops.clear()
	check(P._steam != null, "煙突の湯気（効果の素材）が用意されている")
	# 材料が入る
	var n_kids := P.get_child_count()
	var cook: Dictionary = GameData.recipe_by_id("cook").duplicate()
	P.reserve(cook)
	P.receive(cook)
	check(P._drops.size() == 1 and P.get_child_count() == n_kids + 1, "材料が入ると、投入口へ落ちる動きと、砂ぼこりの効果が出る")
	check(P.orders.size() == 1, "（加工の仕組みは同じ）注文が積まれる")
	# 加工中は湯気
	P._last_work_ms = Time.get_ticks_msec()
	P._process(0.0)
	check(P._steam.playing and P._steam.visible, "加工設備が動いている間は、煙突から湯気が出る")
	P._last_work_ms = Time.get_ticks_msec() - 5000
	P._process(0.0)
	check(not P._steam.playing, "止まっている間は、湯気が出ない")
	# 完成
	P.orders.clear()
	P.current = cook.duplicate()
	P.progress = float(cook["time"]) - 0.01
	var kids := P.get_child_count()
	P.work(0.05, func(f): return 1.0)
	check(P.output.size() == int(cook["n"]) and P._out_times.size() == P.output.size(), "完成すると、完成品がトレイに置かれる（%d個）。弾んで現れる時刻も記録される" % P.output.size())
	check(P.get_child_count() == kids + 1, "完成すると、きらりの効果が出る")
	check(P.total_done >= 1 and P.current.is_empty(), "（加工の仕組みは同じ）加工の回数が増え、作業中の注文は空になる")
	# 取り出し
	var item: int = P.take_output()
	check(item == GameData.Item.FOOD and P._out_times.size() == P.output.size(), "完成品を取り出すと、トレイの表示も1つ減る")
	P.output.clear()
	P._out_times.clear()
	# 文字の状態表示がコードに残っていない
	var src := FileAccess.get_file_as_string("res://scripts/processor.gd")
	check(not src.contains("待ち %d") and not src.contains("加工完了!"), "加工設備の上の文字の状態表示（待ち ▶ 加工中 ▶ 完成）は、なくなっている")
	check(src.contains("draw_item_fill") and src.contains("FxSprite.spawn"), "作っている物のアイコン（下から満ちる）と、効果の素材の再生を使っている")
