extends SceneTree
## 積載重量のアイコンゲージを、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_gauge.gd -- <出力フォルダ>
## 出力: g_full_<割合>.png（画面全体。右上の状態・ボタンとの重なりを見る）と、g_sheet.png（積載率ごとのゲージ部分だけを並べた画像）。

var main
var dir := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260926)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	var st: BaseStorage = main.storage
	var levels := [0.0, 0.15, 0.30, 0.50, 0.65, 0.80, 0.95, 1.0]
	var crops: Array = []
	for lv in levels:
		# 素材棚・加工品置き場の両方が、その割合になるように置く（枠の割合）
		st.inventory.counts.clear()
		for it in st.quota:
			st.inventory.counts[it] = int(round(float(st.quota_of(it)) * lv))
		for k in 4:
			await process_frame
		var img := root.get_texture().get_image()
		if lv == 0.5 or lv == 0.8 or lv == 1.0:
			img.save_png("%s/g_full_%03d.png" % [dir, int(lv * 100.0)])
		var g: IconGauge = main.status._weight
		var r := g.get_global_rect().grow(10.0)
		crops.append(img.get_region(Rect2i(r)))
		print("%3d%%: 重量 %d/%d  数字 %s  充填 %d/%d" % [int(lv * 100.0), st.current_weight(), st.max_weight(), g.text, g.filled_count(), g.fill_dots().size()])
	var cw: int = crops[0].get_width()
	var ch: int = crops[0].get_height()
	var sheet := Image.create(crops.size() * (cw + 6) + 6, ch + 12, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.12))
	for i in crops.size():
		sheet.blit_rect(crops[i], Rect2i(0, 0, cw, ch), Vector2i(6 + i * (cw + 6), 6))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png("%s/g_sheet.png" % dir)
	print("saved g_sheet")
	quit()
