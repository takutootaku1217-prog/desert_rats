extends SceneTree
## 出来事（天候・トラブル・好機）の見た目の確認。実行（ウィンドウが一瞬開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_events.gd -- <出力フォルダ>

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
	d.enabled = false
	await create_timer(4.0).timeout
	await _shot(dir, "e0_calm")
	# 砂嵐の予報 → 発生（突っ切る）
	d.trigger("sandstorm", true)
	await _shot(dir, "e1_sand_forecast", 1.5)
	d.forecast[0]["left"] = 0.05
	await create_timer(0.3).timeout
	d.set_stance("sandstorm", "push")
	await _shot(dir, "e2_sand_push", 4.0)
	d.set_stance("sandstorm", "halt")
	await _shot(dir, "e3_sand_halt", 3.0)
	# 酷暑
	d.active.clear()
	d.trigger("heatwave", false)
	await _shot(dir, "e4_heat", 4.0)
	# 寒波 + 記録 + テスト欄
	d.active.clear()
	d.trigger("coldsnap", false)
	d.trigger("breakdown")
	d.trigger("herd")
	main.event_hud._test_box.visible = true
	await _shot(dir, "e5_cold_test", 4.0)
	# 襲撃（天候と同時。2枠）
	d.active.clear()
	d.forecast.clear()
	d.trigger("sandstorm", true)
	d.trigger("raid_scorpion", true)
	await _shot(dir, "e6_raid_forecast", 1.5)
	d.forecast.clear()
	d.trigger("raid_scorpion", false)
	d.trigger("sandstorm", false)
	d.set_stance("sandstorm", "slow")
	await _shot(dir, "e7_raid_active", 7.0)
	quit()
