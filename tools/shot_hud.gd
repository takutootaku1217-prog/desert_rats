extends SceneTree
## 右上の拠点の状態（盾・ジェリカン・重り・倉庫のアイコン）と、その場で休む仲間の見た目を、実際のゲーム画面（ウィンドウ表示）で撮る。実行:
##   Godot --path . --windowed --resolution 1280x720 --fixed-fps 60 -s res://tools/shot_hud.gd -- <出力フォルダ>
## 出力: h1_full（満タン・全部良好）／h2_mixed（耐久・燃料がいろいろ。空腹。ベッドで眠る仲間とその場で休む仲間）／h_panel（右上の拡大）

var main
var dir := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260927)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	var W: Array = main.workers
	for w in W:
		w.set_process(false)
		for j in GameData.job_list():
			w.priorities[j] = 0
	await _frames(8)
	root.get_texture().get_image().save_png("%s/h1_full.png" % dir)
	# いろいろな状態
	var b = main.base
	b.parts[GameData.Part.HULL] = 82.0
	b.parts[GameData.Part.DRIVE] = 22.0
	b.parts[GameData.Part.MACHINE] = 9.0
	b.fuel = 12.0
	var st: BaseStorage = main.storage
	st.inventory.counts.clear()
	for it in [GameData.Item.FOOD, GameData.Item.FUEL, GameData.Item.REPAIR_KIT, GameData.Item.IRON, GameData.Item.MEAT, GameData.Item.HIDE, GameData.Item.BONE,
			GameData.Item.FAT, GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE]:
		st.inventory.counts[it] = 1 + randi() % 9
	st.inventory.counts[GameData.Item.WOOD] = st.quota_of(GameData.Item.WOOD)          # 満
	W[1].hunger = 12.0                                                                # 空腹（食料のアイコンが警告）
	main.hungry = true
	# 1人目はベッドで眠る、2人目はその場で休む
	W[0].floor_i = 2
	W[0].position = main.base.bed_point(0)
	W[0].ai.state = CharacterAI.State.REST
	W[0].sleeping = true
	W[1].floor_i = 1
	W[1].position = Vector2(700.0, GameData.deck_y(1))
	W[1].ai.state = CharacterAI.State.REST_HERE
	W[1].resting = true
	W[1].stamina = 8.0
	W[2].position = Vector2(140.0, GameData.deck_y(1))
	for w in W:
		w.queue_redraw()
	await _frames(10)
	var img := root.get_texture().get_image()
	img.save_png("%s/h2_mixed.png" % dir)
	var panel := img.get_region(Rect2i(995, 0, 285, 180))
	panel.resize(panel.get_width() * 3, panel.get_height() * 3, Image.INTERPOLATE_NEAREST)
	panel.save_png("%s/h_panel.png" % dir)
	var rest := img.get_region(Rect2i(480, 330, 300, 190))
	rest.resize(rest.get_width() * 3, rest.get_height() * 3, Image.INTERPOLATE_NEAREST)
	rest.save_png("%s/h_rest.png" % dir)
	print("saved")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
