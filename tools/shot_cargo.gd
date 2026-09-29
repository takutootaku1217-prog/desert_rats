extends SceneTree
## 積載量（倉庫の容量）の見た目の確認。実行（ウィンドウが一瞬開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_cargo.gd -- <出力フォルダ>

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
	main.director.enabled = false
	var st: BaseStorage = main.storage
	# 木材がいっぱい・石が満杯に近い・肉は半分・皮も満杯。加工品は燃料がいっぱい
	st.add_item(GameData.Item.WOOD, 14)
	st.add_item(GameData.Item.STONE, 7)
	st.add_item(GameData.Item.MEAT, 5)
	st.add_item(GameData.Item.HIDE, 6)
	st.add_item(GameData.Item.BONE, 3)
	st.add_item(GameData.Item.IRON_ORE, 8)
	st.add_item(GameData.Item.FUEL, 12)
	st.add_item(GameData.Item.IRON, 2)
	st.add_item(GameData.Item.WOOD, 3)            # あふれる（捨てた数と記録に出る）
	await _shot(dir, "c1_main", 1.5)
	main.policy.toggle()
	main.policy._page = 1
	main.policy._rebuild()
	await _shot(dir, "c2_cargo_page", 0.8)
	# さらに積んで、積載率が上がった（重量制）見た目を確認
	st.add_item(GameData.Item.MEAT, 10)
	st.add_item(GameData.Item.STONE, 10)
	main.policy._rebuild()
	await _shot(dir, "c3_cargo_page_fuller", 0.6)
	main.policy._page = 0
	main.policy._rebuild()
	await _shot(dir, "c4_policy_page", 0.6)
	quit()
