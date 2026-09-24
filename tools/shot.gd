extends SceneTree
## 画面確認用。実行（ウィンドウが一瞬開く）:
##   Godot --path . -s res://tools/shot.gd -- <出力フォルダ>
## HUD・仲間の詳細・部署・拠点（部屋の入れ替え）を PNG に保存して終了する。セーブは触らない。

var main


func _shot(dir: String, name: String) -> void:
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name, " ", img.get_size())


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "."
	SaveGame.disabled = true     # 遊んでいるセーブを読まない・書かない
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._no_save = true
	# 見栄えの確認用に、数人募集して少し育てる
	main.storage.add_item(GameData.Item.FOOD, 10)
	main.recruit()
	main.recruit()
	main.workers[0].gain_xp(30.0)
	await create_timer(6.0).timeout
	main.select_worker(main.workers[0])
	await _shot(dir, "1_hud")
	main.detail.toggle()
	await _shot(dir, "2_detail")
	main.dept_ui.toggle()
	await _shot(dir, "3_dept")
	# 拠点画面（部屋の入れ替え）。材料を足して、建てられる状態にする
	for it in GameData.PRODUCT_ITEMS:
		main.storage.add_item(it, 12)
	main.base_ui.toggle()
	await _shot(dir, "4_base_ui")
	main.base_ui._select_slot("l1")
	await _shot(dir, "5_base_ui_l1")
	main.base_ui.toggle()
	# 実際に入れ替える: 機関室 → 医務室
	main.build_room("l1", "infirmary")
	await create_timer(1.0).timeout
	await _shot(dir, "6_built_infirmary")
	# 全部入れ替えた配置（加工室を上階・右、倉庫を下階・左、寝室を上階・左へ）で動かす
	main.room_layout = {"u1": "bedroom", "u2": "workshop", "l1": "storage", "l2": "infirmary"}
	main._apply_layout()
	await create_timer(10.0).timeout
	await _shot(dir, "7_swapped_running")
	# 新しい部屋の見た目（規則を無視した確認用の配置）
	main.room_layout = {"u1": "mess", "u2": "training", "l1": "infirmary", "l2": "empty"}
	main._apply_layout()
	await _shot(dir, "8_new_rooms")
	quit()
