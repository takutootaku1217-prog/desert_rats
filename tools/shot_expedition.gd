extends SceneTree
## 遠征（遺跡の探索）の見た目の確認。実行（ウィンドウが一瞬開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_expedition.gd -- <出力フォルダ>

var main


func _shot(dir: String, name: String, wait := 0.6) -> void:
	await create_timer(wait).timeout
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "."
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var d: Director = main.director
	var ex: Expedition = main.expedition
	d.enabled = false
	main.storage.add_item(GameData.Item.FOOD, 10)
	main.storage.add_item(GameData.Item.REPAIR_KIT, 3)
	await create_timer(3.0).timeout
	# 遺跡を見つけた（左下の欄）
	d.trigger("ruins_large")
	await _shot(dir, "x1_offer_hud", 1.0)
	# 編成画面
	main.expedition_ui.open()
	main.expedition_ui._picker.selected[main.workers[0]] = true
	main.expedition_ui._picker.selected[main.workers[1]] = true
	main.expedition_ui._picker.refresh()
	main.expedition_ui._rebuild()
	await _shot(dir, "x2_party_ui", 0.8)
	main.expedition_ui.close()
	# 出発 → 探索中
	ex.start([main.workers[0], main.workers[1]], "normal", true)
	ex.step_time = 4.0
	ex.step_left = 4.0
	await _shot(dir, "x3_running_hud", 1.5)
	main.expedition_ui.open()
	await _shot(dir, "x4_running_ui", 6.0)
	main.expedition_ui.close()
	# 帰還
	var guard := 0
	while ex.state == "running" and guard < 40:
		guard += 1
		ex.tick(ex.step_time + 0.1)
	await _shot(dir, "x5_done_hud", 1.0)
	main.expedition_ui.open()
	await _shot(dir, "x6_done_ui", 0.8)
	quit()
