extends SceneTree
## 加工品（修理資材）を使う設備「物資庫」の、加工→製作→設置→効果の流れを、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_supply_cache.gd -- <出力フォルダ>
## 段階: 建設の画面（ワークベンチはあるが修理資材が足りない・不足数が見える）→ 材料がそろって依頼 → ワークベンチで作業中 →
##   完成（拠点に物資庫ができる）→ 右上の状態（スタミナの消耗が減る効果は数値では出ないので、room_effect の値を記録）。

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
	Engine.time_scale = 1.5
	var P: BaseProcessor = main.processor
	main.base.add_facility("workbench")                 # ワークベンチは最初からある状態にして、物資庫だけを見る
	await process_frame
	print("effect before: ", main.room_effect("drain_cut"))
	main.build_ui.open()
	await process_frame
	await process_frame
	_shot("e0_build_ui_no_material")                    # 物資庫が一覧にあるが、修理資材が足りない（不足数が見える）
	main.build_ui.close()
	main.storage.add_item(GameData.Item.REPAIR_KIT, 3)
	main.storage.add_item(GameData.Item.WOOD, 2)
	main.build_ui.open()
	await process_frame
	await process_frame
	_shot("e1_build_ui_ready")                          # 材料がそろい、依頼できる
	main.build_ui.close()
	main.request_build("supply_cache")
	var ok: bool = await _wait(func(): return P.current.get("build", "") == "supply_cache" and P.progress > 1.0 and P.is_active_at("workbench"), 90.0)
	print("supply_cache crafting at workbench: ", ok)
	_shot("e2_crafting")                                # ワークベンチで作業中
	ok = await _wait(func(): return main.has_facility("supply_cache"), 60.0)
	print("supply_cache built: ", ok)
	await create_timer(0.5).timeout
	_shot("e3_built")                                   # 完成! の合図。物資庫の絵が拠点に乗る
	print("effect after: ", main.room_effect("drain_cut"))
	main.policy.toggle()
	main.policy._page = 0
	main.policy._rebuild()
	await process_frame
	await process_frame
	_shot("e4_status")                                  # 右上の状態（見た目に変化はないが、数値は変わっている）
	Engine.time_scale = 1.0
	quit()
