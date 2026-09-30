extends SceneTree
## 木製荷台・道具棚・積載重量ページの見た目を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_wood_cargo_tool_rack.gd -- <出力フォルダ>

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
	seed(20260930)
	FacilityDB.start_all = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	Engine.time_scale = 4.0
	main.base.add_facility("workbench")
	_give("wood_cargo")
	main.request_build("wood_cargo")
	var ok: bool = await _wait(func(): return main.has_facility("wood_cargo"), 60.0)
	print("wood_cargo built: ", ok)
	_give("tool_rack")
	main.request_build("tool_rack")
	ok = await _wait(func(): return main.has_facility("tool_rack"), 60.0)
	print("tool_rack built: ", ok)
	main.storage.add_item(GameData.Item.HAMMER, 1)
	main.storage.add_item(GameData.Item.PICKAXE, 2)
	await create_timer(0.4).timeout
	_shot("w0_interior_built")                      # 内装。加工室に木製荷台・道具棚が見え、棚に余り道具のアイコンが出る

	main.policy.toggle()
	main.policy._page = 1
	main.policy._rebuild()
	await process_frame
	await process_frame
	_shot("w1_weight_page")                          # 運営の方針「積載重量」ページ（読み取り専用）
	main.policy.toggle()

	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	await create_timer(0.4).timeout
	_shot("w2_exterior")                             # 外装。後ろの荷台（木製荷台）と工具かけ（道具棚）が付く

	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
	await process_frame
	main.detail.toggle()
	main.detail._worker = main.workers[0]
	main.detail._build_detail()
	await process_frame
	await process_frame
	_shot("w3_crew_equip")                           # 個体管理画面「配属・人事」タブの「装備」区画
	main.detail.toggle()

	Engine.time_scale = 1.0
	print("done")
	quit()
