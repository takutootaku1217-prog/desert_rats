extends SceneTree
## 仲間のステータス（HP・満腹度・疲労度・精神状態）の表示を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 --fixed-fps 60 -s res://tools/shot_crew_status.gd -- <出力フォルダ>
## 出力: s1_normal.png（元気な状態）／s2_mixed.png（悪い状態がいろいろ。頭上の警告つき）／s3_detail.png（仲間の管理画面）／
##   s_hud.png（人数によらない上部HUD）／s_heads.png（仲間の頭上の警告を拡大）／s_detail_nonum.png（詳細の数字なし）

var main
var dir := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260927)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	for w in main.workers:
		w.set_process(false)                              # 撮影の間、値も位置も動かさない
		for j in GameData.job_list():
			w.priorities[j] = 0
	await _frames(6)
	root.get_texture().get_image().save_png("%s/s1_normal.png" % dir)
	# いろいろな悪い状態（手で値を置く）
	var W: Array = main.workers
	var y: float = GameData.deck_y(1)
	for i in W.size():
		W[i].floor_i = 1
		W[i].position = Vector2(560.0 + 150.0 * i, y)
		W[i].target = W[i].position
	# 1人目: HPが低め・疲労度が高め（注意）
	W[0].hp = 35.0
	W[0].fatigue = 80.0
	W[0].mental = CrewStatusDB.Mental.BAD
	# 2人目: とても空腹・疲労度が高い（危険）
	W[1].hunger = 10.0
	W[1].fatigue = 82.0
	W[1].mental = CrewStatusDB.Mental.LIMIT
	# 3人目: 少し疲れ気味
	W[2].fatigue = 55.0
	W[2].hunger = 45.0
	W[2].mental = CrewStatusDB.Mental.ANXIOUS
	for w in W:
		w.queue_redraw()
	await _frames(8)
	var img := root.get_texture().get_image()
	img.save_png("%s/s2_mixed.png" % dir)
	# 通常HUDは仲間管理の入口と追従状態だけ。人数分のカードは常設しない。
	var hud := img.get_region(Rect2i(0, 0, 330, 72))
	hud.resize(hud.get_width() * 2, hud.get_height() * 2, Image.INTERPOLATE_NEAREST)
	hud.save_png("%s/s_hud.png" % dir)
	# 頭上の警告を拡大（仲間3人の周り）
	var heads := img.get_region(Rect2i(500, int(y) - 190, 520, 230))
	heads.resize(heads.get_width() * 2, heads.get_height() * 2, Image.INTERPOLATE_NEAREST)
	heads.save_png("%s/s_heads.png" % dir)
	# 仲間の管理画面
	main.detail.toggle()
	main.detail._select(W[1])
	await _frames(10)
	root.get_texture().get_image().save_png("%s/s3_detail.png" % dir)
	UIKit.show_icon_numbers = false
	main.detail._update_live()
	await _frames(6)
	root.get_texture().get_image().save_png("%s/s_detail_nonum.png" % dir)
	UIKit.show_icon_numbers = true
	main.detail.close()
	print("saved")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
