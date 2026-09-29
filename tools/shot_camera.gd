extends SceneTree
## カメラ追従（最小構成）の見た目を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_camera.gd -- <出力フォルダ>
## 段階: 通常（追従なしと画素まで同じはず）→ 選ぶと追従が始まり右へ動く仲間についていく →
##   別の仲間へ切り替え（左にいる仲間へカメラが動く）→ Escで解除（通常の構図に戻る）→
##   遠征中の仲間を追おうとしても飛ばず「追従できません」と出る。

var main
var dir := "."


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name, "  camera.position=", main.camera.position, "  label=", main._follow_label.text)


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260930)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	var W: Array = main.workers
	await _settle(10)
	_shot("f0_normal")                                  # 追従なしと画素まで同じはずの通常表示

	# 選ぶと追従が始まり、対象が右へ動くとカメラがついていく
	main._select(W[0])
	W[0].position = Vector2(640.0, GameData.LO_Y)
	await _settle(5)
	W[0].position.x = 950.0                             # デッドゾーンの外（画面右寄り）へ
	await _settle(90)                                   # 内蔵スムージングが追いつくのを待つ
	_shot("f1_following_right")                         # 対象が画面内（右寄りのデッドゾーンの端）に収まっている

	# 別の仲間（画面の左寄りにいる）へ切り替え
	W[1].position = Vector2(300.0, GameData.LO_Y)
	main._select(W[1])                                  # 既存の選択方法（main.gd の中心の入口）
	await _settle(90)
	_shot("f2_switch_left")                             # カメラが新しい対象を追って左へ動く

	# 追従の解除（Escキー相当）
	main.follow_target = null
	await _settle(90)
	_shot("f3_released")                                # 通常の、拠点を見渡す構図に戻る

	# 遠征中の仲間を追おうとしても、無効な位置へは飛ばず「追従できません」と出る
	main._select(W[0])
	W[0].position.x = 950.0
	await _settle(90)
	W[0].depart()                                       # 調査隊に出す（away=true・画面外の待避位置へ）
	await _settle(20)
	_shot("f4_away_no_jump")                            # カメラは通常の構図へ戻り、遠征中の待避位置へは飛ばない
	W[0].arrive(80.0)

	print("done")
	quit()
