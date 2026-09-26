extends SceneTree
## 採取ポイント＋道具の見た目の確認。実行（ウィンドウが一瞬開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_gather.gd -- <出力フォルダ>

var main


func _shot(dir: String, name: String, wait := 0.6) -> void:
	await create_timer(wait).timeout
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _point(kind: String, x: float, y: float, amount := -1) -> GatherPoint:
	var pt := GatherPoint.new()
	pt.setup(main, kind)
	if amount >= 0:
		pt.max_amount = maxi(pt.max_amount, amount)
		pt.remaining = amount
	pt.position = Vector2(x, y)
	main.resources_root.add_child(pt)
	return pt


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "."
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0                    # 絵が動かないように止める
	var W: Array = main.workers
	# 3種類の採取ポイント。ひとつは減った・ひとつは枯れた見本
	_point("rock", 1060.0, 600.0)
	_point("vein", 1190.0, 660.0)
	_point("tree", 860.0, 640.0)
	_point("rock", 1130.0, 560.0, 3)
	_point("vein", 760.0, 690.0, 0)
	# 道具: ネズ吉はハンマーと斧、チュー太はピッケル
	main.equip_tool(W[0], GameData.Item.HAMMER)
	main.storage.add_item(GameData.Item.PICKAXE, 1)
	main.storage.add_item(GameData.Item.AXE, 1)
	main.tool_auto = true
	main.manage_tools()
	await _shot(dir, "g1_points", 0.8)
	# 掘っているところ
	for w in W:
		w.priorities[GameData.Job.GATHER] = 5
		w.ai._set_state(CharacterAI.State.SEARCH)
	await create_timer(4.5).timeout
	await _shot(dir, "g2_digging", 0.5)
	# 方針の「採取の道具」ページ
	main.policy.toggle()
	main.policy._page = 2
	main.policy._rebuild()
	await _shot(dir, "g3_tools_page", 0.6)
	quit()
