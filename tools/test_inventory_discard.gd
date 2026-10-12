extends "res://tools/test_clarity_ui.gd"
## 境界fixtureとViewport入力。通常進行の既存在庫・難度は変更しない。
func select_item(item: int):
	var ui = main.inventory_ui
	ui._refresh(true)
	for i in ui._model().stacks.size():
		if ui._model().stacks[i].item == item:
			ui._select(i)
			break
	await frames()

func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.set_process(false)
	main.director.enabled = false
	for w in main.workers:
		w.stop_work()
		w.set_process(false)
		w.ai.state = CharacterAI.State.IDLE
	main.processor.set_process(false)
	main.build_queue.clear()
	main.transfer_queue.clear()
	main.storage.inventory.counts = {GameData.Item.WOOD: 90}
	var item := GameData.Item.WOOD
	var ui = main.inventory_ui
	check(main.storage.current_weight() == main.storage.max_weight(), "満載fixture")
	check(main.warehouse_discard_snapshot(item, 0).is_empty(), "0個は拒否")
	check(main.warehouse_discard_snapshot(item, -1).is_empty(), "負数は拒否")
	check(main.warehouse_discard_snapshot(item, 91).is_empty(), "在庫超過は拒否")
	main.request_build("workbench")
	check(main.warehouse_discard_available(item) == 87, "建設待ち3個を保護")
	main.build_queue.clear()
	var worker = main.workers[0]
	worker.ai.state = CharacterAI.State.HAUL_TAKE
	worker.ai.haul_recipe = {"in": {item: 2}}
	check(main.warehouse_discard_available(item) == 88, "自動加工の引当を保護")
	worker.ai.state = CharacterAI.State.IDLE
	worker.ai.haul_recipe = {}
	main.request_transfer(item, 5, "to_workshop")
	check(main.warehouse_discard_available(item) == 85, "運搬依頼5個を保護")
	main.transfer_queue.clear()
	for pair in [[CharacterAI.State.EAT_TAKE, GameData.Item.FOOD], [CharacterAI.State.REFUEL_TAKE, GameData.Item.FUEL], [CharacterAI.State.REPAIR_TAKE, GameData.Item.REPAIR_KIT]]:
		main.storage.inventory.add(pair[1], 2)
		worker.ai.state = pair[0]
		worker.ai.haul_item = pair[1]
		check(main.warehouse_discard_available(pair[1]) == 1, "生活行動の予約保護 %d" % pair[0])
		main.storage.inventory.take_n(pair[1], 2)
	worker.ai.state = CharacterAI.State.IDLE
	await key(KEY_TAB)
	await select_item(item)
	ui._qty.set_value(5)
	await click(ui._discard_btn)
	check(ui._discard_dialog.visible and ui._discard_text.text.contains("×5") and ui._discard_text.text.contains("360 → 340"), "実クリックで品目・数量・重量確認")
	await click(ui._discard_no)
	check(not ui._discard_dialog.visible and main.storage.count_of(item) == 90, "取消クリックで在庫維持")
	await click(ui._discard_btn)
	await key(KEY_ESCAPE)
	check(not ui._discard_dialog.visible and ui.is_open() and main.storage.count_of(item) == 90, "Escは確認だけ取消")
	await click(ui._discard_btn)
	await click(ui._move_btn)
	check(main.transfer_queue.is_empty(), "確認の背後の運搬ボタンを遮断")
	await click(ui._discard_yes)
	check(main.storage.count_of(item) == 85 and main.storage.current_weight() == 340, "満載から5個だけ廃棄")
	ui._confirm_discard()
	check(main.storage.count_of(item) == 85, "連続確認で二重消費しない")
	await select_item(item)
	await click(ui._discard_btn)
	main.request_transfer(item, 1, "to_workshop")
	await click(ui._discard_yes)
	check(main.storage.count_of(item) == 85 and ui._msg_text.contains("変わりました"), "確認中の予約変更を拒否")
	main.transfer_queue.clear()
	await select_item(item)
	await click(ui._discard_btn)
	main.processor.output.append(item)
	await click(ui._discard_yes)
	check(main.storage.count_of(item) == 85 and ui._msg_text.contains("変わりました"), "加工完了による重量変化は再確認")
	main.processor.output.clear()
	await select_item(item)
	await click(ui._discard_btn)
	main.storage.inventory.take(item)
	await click(ui._discard_yes)
	check(main.storage.count_of(item) == 84, "確認中の在庫変更を拒否")
	await select_item(item)
	await click(ui._discard_btn)
	ui.close()
	ui.open()
	ui._confirm_discard()
	check(main.storage.count_of(item) == 84 and ui._discard_snapshot.is_empty(), "閉じて再表示した古い確認は無効")
	main.processor.stock.add(item, 3)
	main.processor.current = {"in": {item: 2}, "out": GameData.Item.FUEL, "n": 1}
	main.processor.output.append(item)
	worker.carrying = item
	worker.carry_n = 4
	worker.weapon = GameData.Item.SIMPLE_SPEAR
	var weight: int = main.storage.current_weight()
	await select_item(item)
	await click(button_named(ui._detail, "全部"))
	await click(ui._discard_btn)
	await click(ui._discard_yes)
	check(main.storage.count_of(item) == 0 and main.storage.current_weight() == weight - 84 * 4, "全数廃棄は倉庫だけを減らす")
	check(main.processor.stock.count(item) == 3 and main.processor.current["in"][item] == 2 and main.processor.output.size() == 1 and worker.carry_n == 4 and worker.weapon == GameData.Item.SIMPLE_SPEAR, "加工中・完成品・運搬・装備は保持")
	ui._set_tab(1)
	await select_item(item)
	check(ui._discard_btn == null, "作業場には廃棄操作なし")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
