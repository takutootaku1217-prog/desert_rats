extends SceneTree
## 実際のViewport入力経路。ボタンsignalや要求APIの直呼びをクリックの代用にしない。
var main
var fails := 0
func check(ok: bool, message: String):
	print(("OK " if ok else "FAIL ") + message)
	if not ok: fails += 1
func frames():
	for i in 8: await process_frame
func mouse(pos: Vector2, button: int):
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion, true)
	await process_frame
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = button
		ev.pressed = down
		root.push_input(ev, true)
		await process_frame
	await frames()
func click(button: Button):
	await mouse(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
func key(code: int):
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = down
		root.push_input(ev, true)
		await process_frame
	await frames()
func find_scroll(node: Node):
	if node is ScrollContainer: return node
	for c in node.get_children():
		var found = find_scroll(c)
		if found != null: return found
	return null
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.director.enabled = false
	main.target_speed = 0
	main.set_process(false) # fixtureの摩耗・自動注文のみ停止。UI入力とUI更新は通常経路。
	main.base.add_facility("workbench", true)
	main.storage.add_item(GameData.Item.BED_PACK)
	main.storage.add_item(GameData.Item.STORAGE_BOX)
	for w in main.workers:
		w.stop_work()
		for j in GameData.job_list(): w.priorities[j] = 0
	main.base.parts[GameData.Part.HULL] = 40
	await key(KEY_B)
	check(main.build_ui._overlay.visible, "B入力で設置画面を開く")
	var scroll = find_scroll(main.build_ui._overlay)
	for i in 8: await mouse(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(main.build_ui._fac_rows["supply_cache"]["build"].get_global_rect().end.y <= 678, "ホイール入力で最下段を表示")
	for id in ["bed", "cargo_rack"]:
		var item: int = FacilityDB.def(id)["packed_item"]
		check(main.build_pending(id) == 0, "クリック前は注文なし: " + id)
		await click(main.build_ui._fac_rows[id]["build"])
		check(main.build_pending(id) == 1, "ホイール後のクリックで設置を依頼: " + id)
		await click(main.build_ui._fac_rows[id]["cancel"])
		check(main.build_pending(id) == 0 and main.storage.count_of(item) == 1, "取消クリックで注文消去・製作物保持: " + id)
	var repairs: int = main.base.total_repair
	await click(main.status._repair)
	check(main.base.total_repair == repairs, "モーダル背後の修理ボタンは反応しない")
	await key(KEY_B)
	# 背後の位置を押して閉じるUIであっても明示的に閉じた状態を確保。
	if main.build_ui._overlay.visible: await key(KEY_B)
	var kits: int = main.storage.count_of(GameData.Item.REPAIR_KIT)
	await click(main.status._repair)
	check(main.base.parts[GameData.Part.HULL] == 65 and main.storage.count_of(GameData.Item.REPAIR_KIT) == kits - 1, "修理ボタン実入力で1枚消費・25回復")
	for part in main.base.parts: main.base.parts[part] = 100
	await frames()
	kits = main.storage.count_of(GameData.Item.REPAIR_KIT)
	await click(main.status._repair)
	check(main.status._repair.disabled and main.storage.count_of(GameData.Item.REPAIR_KIT) == kits, "全快の無効ボタンで消費しない")
	main.processor.stock.add(GameData.Item.HIDE, 2)
	main.processor.stock.add(GameData.Item.BONE, 1)
	await key(KEY_F)
	check(main.craft_ui._overlay.visible, "F入力で製作画面を開く")
	for b in main.craft_ui._cat_row.get_children():
		if b.text == "建設":
			await click(b)
			break
	check(main.craft_ui.selected_entry().get("id", "") == "bed_pack", "分類クリックで寝床の製作を選択")
	await click(main.craft_ui._craft_btn)
	check(main.craft_queue.any(func(q): return q["id"] == "bed_pack"), "製作ボタン実入力で注文")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
