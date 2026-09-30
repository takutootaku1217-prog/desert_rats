extends SceneTree
## 背景・重なり順の修正（QA報告書 BG-01・BG-02・BG-04）を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_bg_scroll.gd -- <出力フォルダ>
## 段階:
##   f0_normal        通常表示（これまでと画素まで同じはず）
##   f1_pan_left       報告書と同じ再現条件（仲間を世界x=300へ配置・追従）→ カメラの目標左端が-190になる場面。
##                      以前はここで画面左側に灰色の欠けが出ていた（BG-01）。
##   f2_pan_right      報告書と同じ再現条件（仲間を世界x=1150へ配置・追従）→ カメラの目標左端が360になる場面。
##                      以前はここで画面右側に灰色の欠けが出ていた（BG-01）。
##   f3_seam_zoom      通常表示のまま、空と山の継ぎ目付近（BG-02。ズームはしていないので、報告書の指摘箇所がそのまま見える）。
##   f4_depth_overlap   仲間の足元(650,580)・岩の採取ポイントの足元(650,620)を重ねる（報告書と同じ座標）。
##                      以前は奥の仲間が岩の上から描かれていた（BG-04）。手前の岩の後ろに仲間の上半身が隠れていれば直っている。

var main
var dir := "."


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name, "  camera.position=", main.camera.position)


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20261001)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	var W: Array = main.workers
	await _settle(10)
	_shot("f0_normal")

	print("-- BG-01: 報告書と同じ再現条件で、カメラをパンする --")
	main._select(W[0])
	W[0].position = Vector2(300.0, GameData.LO_Y)     # 報告書: 世界x=300へ配置し追従 → 目標左端-190
	await _settle(90)
	_shot("f1_pan_left")

	W[0].position = Vector2(1150.0, GameData.LO_Y)    # 報告書: 世界x=1150へ配置し追従 → 目標左端360
	await _settle(90)
	_shot("f2_pan_right")

	main.follow_target = null
	W[0].position = Vector2(GameData.STORAGE_X - 120.0, GameData.LO_Y)
	await _settle(90)
	_shot("f3_seam_zoom")     # BG-02: 通常表示（空と山の継ぎ目。カメラ位置0）

	print("-- BG-04: 仲間と採取ポイントの重なり（報告書と同じ座標） --")
	for w in W:
		w.priorities[GameData.Job.GATHER] = 0    # 他の仲間が採取ポイントへ寄ってこないようにする（重なりだけを見たいので）
		w.priorities[GameData.Job.HUNT] = 0
	var pt := GatherPoint.new()
	pt.setup(main, "rock")
	pt.position = Vector2(650.0, 620.0)
	main.resources_root.add_child(pt)
	W[0].position = Vector2(650.0, 580.0)
	W[0].set_process(false)                     # このスクリーンショットだけのため、AI・移動を止めて狙った座標に固定する
	W[0].queue_redraw()
	await process_frame
	_shot("f4_depth_overlap")

	print("done")
	quit()
