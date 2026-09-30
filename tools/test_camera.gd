extends SceneTree
## カメラ追従（個体管理タブとカメラ追従_仕様書のうち、カメラ追従の最小構成）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_camera.gd
## 確かめる: カメラの初期状態・選ぶと追従が始まる・追いすぎない（デッドゾーン）・揺れない・切り替え・解除・
##   対象が無効（遠征中・拠点の中）のときに無効な位置へ飛ばず表示だけ変わる・クリック判定の窓口（get_global_mouse_position）・
##   クリックで選ぶ判定そのもの（main._pick_worker_at。絵の範囲で当たる・遠征中や見えない仲間は選べない。QA報告書 CAM-01・CAM-02 対策）。

var fails := 0
var main
var W: Array


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260930)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	W = main.workers
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _tick(n: int, dt := 0.1) -> void:
	for i in n:
		main._update_camera(dt)


func _run() -> void:
	print("-- カメラの初期状態 --")
	check(main.camera != null and main.camera is Camera2D, "Camera2D がある")
	check(main.camera.anchor_mode == Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT, "position が画面左上の世界座標になる設定（カメラなしのときと同じ見え方の基準）")
	check(main.camera.position == Vector2.ZERO, "最初はカメラの位置が0（これまでと同じ見え方）")
	check(main.camera.zoom == Vector2.ONE, "拡大縮小はしない（ドット絵がぼやけない）")
	check(main.camera.position_smoothing_enabled, "内蔵のスムージングが有効（滑らかに追う）")
	check(main.follow_target == W[0], "起動時は、最初に選ばれている仲間（W[0]）を追従先にしている")

	print("-- 選ぶと追従が始まる（既存の選択方法。main._select） --")
	W[0].position = Vector2(640.0, GameData.LO_Y)     # 画面中央付近から始める
	main.camera.position = Vector2.ZERO
	_tick(5)
	check(main.camera.position.x == 0.0, "対象が画面中央付近（デッドゾーン内）なら、カメラは動かさない")

	print("-- 追いすぎない（デッドゾーン）・急に飛ばない --")
	W[0].position.x = 640.0 + main.FOLLOW_DEADZONE_HALF - 10.0    # デッドゾーンのすぐ内側
	_tick(5)
	check(main.camera.position.x == 0.0, "デッドゾーンの内側では、カメラは動かない（無駄な揺れを避ける）")
	W[0].position.x = 900.0     # デッドゾーンの外（画面中央+150 を超える）
	var before: float = main.camera.position.x
	main._update_camera(0.1)
	var after1: float = main.camera.position.x
	check(after1 > before, "デッドゾーンの外に出ると、カメラが追いつき始める")
	_tick(200, 0.1)
	var settled: float = main.camera.position.x
	var screen_x: float = W[0].position.x - settled
	check(screen_x <= 640.0 + main.FOLLOW_DEADZONE_HALF + 0.5, "追いついたあと、対象はデッドゾーンの端に収まる（画面外へ出ない。screen_x=%.1f）" % screen_x)
	check(settled > 0.0, "対象が右にいるので、カメラも右へ動く")

	print("-- 別の仲間を選ぶと追従先が切り替わる --")
	W[1].position = Vector2(300.0, GameData.LO_Y)
	main._select(W[1])
	check(main.follow_target == W[1], "選ぶと追従先が切り替わる")
	_tick(200, 0.1)
	var screen_x2: float = W[1].position.x - main.camera.position.x
	check(absf(screen_x2 - 640.0) <= main.FOLLOW_DEADZONE_HALF + 0.5, "切り替え後、新しい対象がまた画面内に収まる（screen_x=%.1f）" % screen_x2)
	check(main._follow_label.text.contains(W[1].char_name), "追従中の表示に名前が出る: %s" % main._follow_label.text)

	print("-- 追従の解除（Escキー相当） --")
	main.follow_target = null
	_tick(300, 0.1)
	check(is_equal_approx(main.camera.position.x, 0.0), "解除すると、通常の拠点を見渡す構図（カメラ位置0）に戻る")
	check(main._follow_label.text == "", "解除すると、追従の表示も消える")
	check(W[1].selected, "追従を解除しても、仲間の選択（優先度パネルなどの対象）はそのまま")

	print("-- 対象が無効なときは、無効な位置へ飛ばず、表示だけ変える --")
	main._select(W[0])
	W[0].position.x = 900.0
	_tick(100, 0.1)
	check(main.camera.position.x > 50.0, "（前提）ここまでは追従してカメラが動いている")
	W[0].away = true                       # 調査隊に出た
	var cam_before_away: float = main.camera.position.x
	_tick(5, 0.1)
	check(main.camera.position.x < cam_before_away, "遠征中は追従をやめて、通常の構図へ戻り始める（対象の位置へは飛ばない）")
	check(main._follow_label.text.contains("遠征中"), "「遠征中」で追従できないことが表示される: %s" % main._follow_label.text)
	W[0].away = false
	W[0].visible = false                   # 拠点の中にいて、外装表示では見えない状態を模す
	_tick(5, 0.1)
	check(main._follow_label.text.contains("拠点の中"), "見えない（外装表示）ときは「拠点の中」で追従できないことが表示される: %s" % main._follow_label.text)
	check(main.camera.position.x >= 0.0 and main.camera.position.x <= 900.0, "見えない対象の位置（画面外）へカメラが飛ばない")
	W[0].visible = true

	# 実際のマウス位置（get_global_mouse_position）はヘッドレスでは確かめられないが、
	# クリックした世界座標から誰を選ぶかを決める部分（main._pick_worker_at）は分離してあるので、ここから直接確認できる。
	main.camera.position = Vector2.ZERO

	print("-- クリックで選ぶ判定（main._pick_worker_at。QA報告書 CAM-01・CAM-02 対策） --")
	W[0].away = false
	W[0].visible = true
	W[0].position = Vector2(500.0, GameData.LO_Y)
	check(main._pick_worker_at(W[0].position) == W[0], "足元をクリックすると選べる（これまでどおり）")
	check(main._pick_worker_at(W[0].position + Vector2(0, -50)) == W[0], "頭の少し上（足元から50px上）をクリックしても選べる（CAM-01: 以前は半径34pxしかなく、絵の上のほうが外れていた）")
	check(main._pick_worker_at(W[0].position + Vector2(0, -63)) == W[0], "絵のいちばん上（足元から63px上）に近い位置でも選べる")
	check(main._pick_worker_at(W[0].position + Vector2(0, -70)) == null, "絵の外（頭よりさらに上）はさすがに選ばない")
	check(main._pick_worker_at(W[0].position + Vector2(40, 0)) == null, "絵の外（横に大きく外れた位置）は選ばない")
	W[0].away = true
	check(main._pick_worker_at(W[0].position) == null, "遠征中の仲間は、絵の場所をクリックしても選べない（CAM-02）")
	W[0].away = false
	W[0].visible = false
	check(main._pick_worker_at(W[0].position) == null, "外装表示で拠点の中にいて見えない仲間も、選べない（CAM-02: 以前は車体越しに選べてしまっていた）")
	W[0].visible = true

	print("-- 既存の自動行動・仕事は変わらない --")
	check(W[0].ai != null and W[0].ai.state != null, "追従中でも、仲間のAIは通常どおり存在し動いている（状態を持つ）")
