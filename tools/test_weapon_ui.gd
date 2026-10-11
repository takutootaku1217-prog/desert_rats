extends "res://tools/test_equipment_ui.gd"
func reveal(button: Button):
	main.detail._scroll.ensure_control_visible(button)
	await frames()
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.set_process(false)
	main.director.enabled = false
	for w in main.workers: w.set_process(false)
	main.base.add_facility("workbench", true)
	main.processor.stock.add(GameData.Item.WOOD, 1)
	main.processor.stock.add(GameData.Item.IRON, 1)
	await key(KEY_F)
	for button in main.craft_ui._cat_row.get_children():
		if button.text == "装備":
			await click(button)
			break
	check(main.craft_ui.selected_entry().get("id", "") == "simple_spear", "F→装備分類を実入力で選択")
	await click(main.craft_ui._craft_btn)
	check(main.craft_queue.any(func(q): return q["id"] == "simple_spear"), "実入力で武器製作を注文")
	# 完成・収納はtest_weaponの実AI試験で検証。ここではUI境界の在庫を注入。
	main.storage.add_item(GameData.Item.SIMPLE_SPEAR)
	await key(KEY_C)
	check(main.detail._overlay.visible and not main.craft_ui._overlay.visible, "Cで個体情報へ集約・他画面を閉じる")
	var first = main.detail._worker
	await reveal(main.detail._live["weapon_equip"])
	await click(main.detail._live["weapon_equip"])
	check(first.weapon == GameData.Item.SIMPLE_SPEAR and main.storage.count_of(GameData.Item.SIMPLE_SPEAR) == 0, "装備ボタン実入力で単一所有")
	await click(main.detail._live["weapon_equip"])
	check(first.weapon == GameData.Item.SIMPLE_SPEAR and main.storage.count_of(GameData.Item.SIMPLE_SPEAR) == 0, "装備連打で増減しない")
	await click(main.detail._live["weapon_off"])
	check(first.weapon == -1 and main.storage.count_of(GameData.Item.SIMPLE_SPEAR) == 1, "外すボタン実入力で倉庫へ戻す")
	var second = main.workers[1]
	await click(main.detail._picker._rows[second])
	check(main.detail._worker == second, "一覧実入力で別個体を選択")
	await reveal(main.detail._live["weapon_equip"])
	await click(main.detail._live["weapon_equip"])
	check(second.weapon == GameData.Item.SIMPLE_SPEAR and first.weapon == -1, "別個体の装備ボタンで持替え")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
