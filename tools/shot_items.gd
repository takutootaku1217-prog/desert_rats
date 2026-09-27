extends SceneTree
## インベントリの画面・制作の画面・作業場の在庫の見た目を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 --fixed-fps 60 -s res://tools/shot_items.gd -- <出力フォルダ>
## 出力: i0_main（右のボタン列）／i1_inventory（倉庫。分割した束）／i2_workshop（作業場。運搬の依頼）／
##   c1_craft_ok（作れる）／c2_craft_short（材料不足）／c3_craft_locked（解放待ち）／c4_craft_build（建設）／w1_world（作業場の在庫が見える加工設備）

var main
var dir := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260927)
	FacilityDB.start_all = false                     # ワークベンチなし（解放待ちの見せ方も撮る）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	for w in main.workers:
		w.set_process(false)
	var st: BaseStorage = main.storage
	st.inventory.counts.clear()
	for it in [[GameData.Item.MEAT, 8], [GameData.Item.HIDE, 15], [GameData.Item.BONE, 7], [GameData.Item.FAT, 4], [GameData.Item.WOOD, 20], [GameData.Item.STONE, 18],
			[GameData.Item.IRON_ORE, 12], [GameData.Item.IRON, 1], [GameData.Item.REPAIR_KIT, 2], [GameData.Item.FOOD, 8], [GameData.Item.FUEL, 2], [GameData.Item.HAMMER, 1], [GameData.Item.AXE, 1]]:
		st.inventory.counts[it[0]] = it[1]
	st.quota[GameData.Item.WOOD] = 40
	await _frames(6)
	root.get_texture().get_image().save_png("%s/i0_main.png" % dir)
	# インベントリ（倉庫）: 木材を選んで分割
	main.inventory_ui.open()
	await _frames(4)
	var ui: InventoryUI = main.inventory_ui
	for i in ui._model().stacks.size():
		if ui._model().stacks[i].item == GameData.Item.WOOD:
			ui._select(i)
	await _frames(4)
	ui._model().split(ui._sel, 8)
	ui._refresh(true)
	main.request_transfer(GameData.Item.STONE, 6, "to_workshop")
	ui._refresh(true)
	ui._say("木材 ×20 を ×12 と ×8 に分けた")
	await _frames(6)
	root.get_texture().get_image().save_png("%s/i1_inventory.png" % dir)
	# 作業場: 材料と、加工待ちの注文
	main.processor.stock.add(GameData.Item.WOOD, 5)
	main.processor.stock.add(GameData.Item.STONE, 2)
	var cook: Dictionary = GameData.recipe_by_id("cook").duplicate()
	main.processor.orders.append(cook)
	ui._set_tab(1)
	await _frames(6)
	root.get_texture().get_image().save_png("%s/i2_workshop.png" % dir)
	# 制作: 作れる（簡易の斧 = 石1＋木材2。作業場に石2・木材5がある）
	main.craft_ui.open_entry("tool_axe")
	await _frames(6)
	root.get_texture().get_image().save_png("%s/c1_craft_ok.png" % dir)
	# 材料不足（簡易ハンマー ×5回 = 石10＋木材5）
	main.craft_ui.open_entry("tool_hammer")
	main.craft_ui._qty_val = 5
	main.craft_ui._refresh(true)
	await _frames(4)
	root.get_texture().get_image().save_png("%s/c2_craft_short.png" % dir)
	# 解放待ち
	main.craft_ui.open_entry("tool_pick")
	await _frames(4)
	root.get_texture().get_image().save_png("%s/c3_craft_locked.png" % dir)
	# 建設
	main.craft_ui.open_entry("build:workbench")
	await _frames(4)
	root.get_texture().get_image().save_png("%s/c4_craft_build.png" % dir)
	main.craft_ui.close()
	main.request_craft("tool_axe", 1)
	await _frames(20)
	root.get_texture().get_image().save_png("%s/w1_world.png" % dir)
	print("saved")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
