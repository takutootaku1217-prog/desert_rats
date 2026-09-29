extends SceneTree
## 建設の流れの各段階を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_build.gd -- <出力フォルダ>
## 段階: 最初（設備なし）→ 建設の画面（ベッドは押せない）→ ワークベンチを建設中 → 完成 → 建設の画面（ベッドが押せる）→
##   ワークベンチでベッドを作っている → ベッド完成 → ベッドで眠る。出来事は止めて、建設だけを見る。

var main
var dir := "."


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _wait(cond: Callable, limit: float) -> bool:
	var t0: float = main.director.elapsed
	while main.director.elapsed - t0 < limit:
		if cond.call():
			return true
		await process_frame
	return false


func _give(id: String) -> void:
	var c: Dictionary = FacilityDB.def(id)["cost"]
	for it in c:
		main.storage.add_item(it, c[it])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260926)
	FacilityDB.start_all = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	Engine.time_scale = 1.5
	var P: BaseProcessor = main.processor
	await _wait(func(): return main.director.elapsed > 4.0, 10.0)
	_shot("b0_start")                                   # 設備なし。ワークベンチの置き場だけが薄く見える
	main.build_ui.open()
	await process_frame
	await process_frame
	_shot("b1_build_ui_start")                          # ワークベンチは依頼できる。ベッドは押せない
	main.build_ui.close()
	_give("workbench")
	main.request_build("workbench")
	main.build_ui.open()
	await process_frame
	await process_frame
	_shot("b2_build_ui_requested")                      # 依頼中（取り消せる）
	main.build_ui.close()
	var ok: bool = await _wait(func(): return P.current.get("build", "") == "workbench" and P.progress > 2.0, 90.0)
	print("workbench in progress: ", ok)
	_shot("b3_building_workbench")                      # 加工設備で組み立て中。ワークベンチの置き場が点滅
	ok = await _wait(func(): return main.has_facility("workbench"), 60.0)
	print("workbench built: ", ok)
	await create_timer(0.5).timeout
	_shot("b4_workbench_built")                         # 完成! の合図
	main.build_ui.open()
	await process_frame
	await process_frame
	_shot("b5_build_ui_after")                          # ワークベンチが必要な製作物の★が出る。ベッドが押せる
	main.build_ui.close()
	_give("bed")
	main.request_build("bed")
	ok = await _wait(func(): return P.current.get("build", "") == "bed" and P.progress > 1.0 and P.is_active_at("workbench"), 90.0)
	print("bed crafting at workbench: ", ok)
	_shot("b6_crafting_bed")                            # ワークベンチで作業（槌を振る・足元に進捗）
	ok = await _wait(func(): return main.base.facility_count("bed") >= 1, 60.0)
	print("bed built: ", ok)
	await create_timer(0.4).timeout
	_shot("b7_bed_built")
	for w in main.workers:
		w.fatigue = 80.0
		w.ai.on_priority_changed()
	ok = await _wait(func(): return main.workers.any(func(w): return w.sleeping), 40.0)
	print("someone sleeping: ", ok)
	await create_timer(0.3).timeout
	_shot("b8_sleeping")
	Engine.time_scale = 1.0
	quit()
