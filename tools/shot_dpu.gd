extends SceneTree
## 絵の細かさ（1ユニットのドット数）を変えても、画面が変わらないことを、実際の画面で比べるための撮影ツール（ウィンドウ表示）。
## 決まった場面を、毎回同じ手順で撮る（世界を止め、仲間は動かさず、フレーム数を固定する。--fixed-fps 60 で実行すること）:
##   Godot --path . --windowed --resolution 1280x720 --fixed-fps 60 -s res://tools/shot_dpu.gd -- <出力フォルダ> [--art-root=<絵のフォルダ>]
## 出力: d_interior.png（内装）/ d_exterior.png（外装。初期）/ d_exterior_late.png（外装。後半・部屋を変えたあと）/ d_rooms_ui.png（部屋の変更の画面）/
##   d_build_ui.png（建設の画面）。同じ手順で、元の絵と、2倍の細かさに差し替えた絵（tools/make_dpu_fixture.py）を撮って、画像を比べる
##   （tools/compare_shots.py）。一致すれば、絵の差し替えだけでゲームの見た目・配置が変わらない。

var main
var dir := "."


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not String(a).begins_with("--"):
			dir = a
	seed(7)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame                              # _ready が終わるのを待つ（ここではまだ、最初の _process は動いていない）
	seed(7)                                          # Main._ready が randomize() したあとで、もう一度種を決める（毎回同じ乱数にする）
	# 世界を止める（仲間・拠点・出現・時間の進みを止め、最初の位置・最初のコマのまま撮る。乱数や時間による違いを消すため）
	main.set_process(false)
	main.base.set_process(false)
	for w in main.workers:
		w.set_process(false)
	main.scroll_speed = 0.0
	main.director.enabled = false
	for c in main.get_children():
		if c is WorldScroll:
			c.set_process(false)
			c.scroll_x = 0.0                          # 背景を動かさない
	# 絵の格子（1ドット）に乗る位置にそろえる。細かい絵では、格子に合わせる処理が細かくなるので、格子に乗っていない位置は、
	# 2pxずれて描かれる（正しい動き。ただし比べるときに紛れる）。積載も空にして、ゲージの埋まり方の細かさの差も消す。
	for i in main.workers.size():
		main.workers[i].position = Vector2(520.0 + i * 92.0, 484.0)
		main.workers[i].queue_redraw()                # 止めた仲間は自分では描き直さない。位置を変えたら、描き直させる
	main.storage.inventory.counts.clear()
	await _frames(30)
	_shot("d_interior")
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	await _frames(20)
	_shot("d_exterior")
	# 後半・部屋を変える（外装のまま）
	main.director.distance = 46000.0
	main.build_room("l1", "empty")
	for rt in ["infirmary", "mess"]:
		for it in Rooms.TYPES[rt]["cost"]:
			main.storage.add_item(it, Rooms.TYPES[rt]["cost"][it])
	main.build_room("l1", "infirmary")
	main.build_room("u1", "mess")
	main.base.room_built_at.clear()                  # 「できた!」の表示は実時間で動くので、比べる画面には出さない
	main.storage.inventory.counts.clear()
	await _frames(20)
	_shot("d_exterior_late")
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
	main.room_ui.open()
	main.room_ui.select_slot("l1")
	await _frames(90)                                # 画面が0.4秒ごとに更新されるので、十分に待つ
	_shot("d_rooms_ui")
	main.room_ui.close()
	main.build_ui.open()
	await _frames(90)
	_shot("d_build_ui")
	quit()
