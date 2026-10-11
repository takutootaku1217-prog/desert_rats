extends "res://tools/test_equipment_ui.gd"
func button_named(node: Node, text: String):
	if node is Button and node.text==text:return node
	for c in node.get_children():
		var b=button_named(c,text)
		if b!=null:return b
	return null
func _initialize():
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.set_process(false) # UI境界専用fixture。正規進行はtest_progressionで別に検証。
	for w in main.workers:
		w.stop_work()
		w.set_process(false)
	for id in ["bed_pack","storage_box","simple_spear","repair_iron","build:bed","build:cargo_rack"]:
		main.craft_ui.open_entry(id)
		await frames()
		check(not main.craft_ui.selected_entry()["name"].contains("製作の製作"),"製作の段階名が重複しない")
		var label=main.craft_ui._detail.get_node("EffectDetail")
		check(label.text.length()>0 and label.get_global_rect().end.x<=1240,"選択詳細に効果が表示され横へはみ出さない: "+id)
		if id=="bed_pack":check(label.text.contains("33%") and label.text.contains("1.2") and label.text.contains("0.7") and label.text.contains("製作段階"),"寝床の回復差と未設置段階")
		if id=="storage_box":check(label.text.contains("＋60") and label.text.contains("容量は増えません"),"箱は設置時にだけ容量増加")
		if id=="simple_spear":check(label.text.contains("＋20%") and label.text.contains("狩猟"),"槍は本人迎撃だけ")
		if id=="repair_iron":check(label.text.contains("25.0") and label.text.contains("上限100") and label.text.contains("未予約"),"修理量・上限・対象条件")
		check(main.craft_ui._detail.get_parent() is ScrollContainer,"長い詳細は縦スクロール")
	main.build_ui.open()
	await frames()
	await click(button_named(main.build_ui._overlay,"効果・手順"))
	check(main.craft_ui.is_open() and not main.build_ui._overlay.visible,"Bの効果ボタンはFの選択詳細へ移る")
	main.quarry.select()
	main.quarry.left=0
	main.quarry.tick(0)
	main.quarry.record_generated(GameData.Item.IRON_ORE,12)
	main.total_eaten+=2
	main.quarry_ui.open()
	await frames()
	await click(button_named(main.quarry_ui._overlay,"採取記録"))
	check(main.quarry_ui._report.visible and main.quarry_ui._report_text.text.contains("鉄鉱石×12") and main.quarry_ui._report_text.text.contains("食料：2個"),"G記録ボタン実入力で生成と食事を別表示")
	check(main.quarry_ui._report_text.text.contains("持帰り数ではありません"),"生成数を持帰りと誤表示しない")
	check(main.quarry_ui._report_text.get_global_rect().end.y<680,"採取記録の本文は画面内")
	await key(KEY_ESCAPE)
	check(not main.quarry_ui._report.visible and main.quarry_ui.is_open(),"Escは採取記録だけ閉じる")
	var before=main.quarry.visit_generated.duplicate()
	check(main.quarry.request_departure(),"記録を保持したまま帰還指示")
	check(main.quarry.cancel(),"帰還取消を受理")
	check(main.quarry.visit_generated==before,"帰還取消で採取記録を消さない")
	print("== 結果: %s ==" % ("すべて成功" if fails==0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
