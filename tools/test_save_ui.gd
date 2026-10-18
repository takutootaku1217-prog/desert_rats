extends "res://tools/test_clarity_ui.gd"
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await frames()
	main.set_process(false)
	for w in main.workers: w.set_process(false)
	var ui = main.save_ui
	ui.path = "user://save-ui-test.json"
	ui.legacy_path = "user://save-ui-legacy.json"
	for suffix in ["", ".bak", ".damaged"]:
		if SaveGame.exists(ui.path+suffix): DirAccess.remove_absolute(ui.path+suffix)
		if SaveGame.exists(ui.legacy_path+suffix): DirAccess.remove_absolute(ui.legacy_path+suffix)
	var initial: int = main.storage.count_of(GameData.Item.WOOD)
	await click(main.navigation.buttons["メニュー"])
	await click(button_named(main.navigation,"保存 / 続きから"))
	check(paused and ui.is_open(),"実入力で保存画面を開き停止")
	await click(button_named(ui,"手動で保存"))
	check(ui._confirm.visible and ui._text.text.contains("最初"),"初回保存を明示して確認")
	await click(ui._confirm)
	check(SaveGame.exists(ui.path) and ui._text.text.contains("保存しました"),"初回手動保存")
	var saved := FileAccess.get_file_as_bytes(ui.path)
	main.storage.store_owned(GameData.Item.WOOD,3)
	await click(button_named(ui,"手動で保存"))
	check(ui._text.text.contains("上書き"),"既存保存に上書き確認")
	await key(KEY_ESCAPE)
	check(not ui.is_open() and not paused and FileAccess.get_file_as_bytes(ui.path) == saved,"Escで上書き取消・保存維持")
	ui.open()
	await click(button_named(ui,"続きから"))
	check(main.storage.count_of(GameData.Item.WOOD) == initial+3,"ロード確認前に現在進行を破棄しない")
	await click(ui._confirm)
	check(main.storage.count_of(GameData.Item.WOOD) == initial and paused,"ロードして停止状態維持")
	main.storage.store_owned(GameData.Item.WOOD,7)
	await click(button_named(ui,"手動で保存"))
	await click(ui._confirm)
	check(FileAccess.get_file_as_bytes(ui.path+".bak") == saved,"上書き前の保存をバックアップ")
	await click(button_named(ui,"バックアップから再開"))
	await click(ui._confirm)
	check(main.storage.count_of(GameData.Item.WOOD) == initial,"バックアップ再開")
	# The checkpoint confirmation reports the exact configured test loss, and its
	# backup route is independently usable after primary corruption.
	main.town.credits = 49
	check(SaveGame.write(main, ui.checkpoint_path, true, SaveGame.SLOT_CHECKPOINT), "UI checkpoint write")
	main.town.credits = 0
	ui.ask("checkpoint")
	check(ui._text.text.contains("4"), "checkpoint confirmation displays exact ten percent loss")
	ui.execute()
	check(main.town.credits == 45, "UI checkpoint restart applies truncating ten percent loss")
	main.town.credits = 77
	check(SaveGame.write(main, ui.checkpoint_path, true, SaveGame.SLOT_CHECKPOINT), "UI checkpoint backup source")
	main.town.credits = 88
	check(SaveGame.write(main, ui.checkpoint_path, true, SaveGame.SLOT_CHECKPOINT), "UI checkpoint backup rotation")
	var checkpoint_primary := FileAccess.open(ui.checkpoint_path, FileAccess.WRITE); checkpoint_primary.store_string("broken"); checkpoint_primary.close()
	ui.ask("checkpoint_backup")
	ui.execute()
	check(main.town.credits == 70, "UI checkpoint backup restart works after primary corruption")
	# Exercise the actual SaveUI continuation route with only the legacy save.
	check(SaveGame.write(main, ui.legacy_path, true), "legacy progress write")
	DirAccess.remove_absolute(ui.path)
	main.storage.store_owned(GameData.Item.WOOD, 11)
	ui.ask("load")
	ui.execute()
	check(main.storage.count_of(GameData.Item.WOOD) == initial, "SaveUI continues from legacy save when separated slot is absent")
	# A present separated slot is authoritative, including when it is damaged.
	main.storage.store_owned(GameData.Item.WOOD, 4)
	var before_separated_failure := SaveGame.capture(main)
	var separated := FileAccess.open(ui.path,FileAccess.WRITE); separated.store_string("broken"); separated.close()
	ui.ask("load")
	ui.execute()
	check(SaveGame.capture(main) == before_separated_failure, "damaged separated progress never falls back to legacy")
	var f := FileAccess.open(ui.path,FileAccess.WRITE); f.store_string("broken"); f.close()
	var before := SaveGame.capture(main)
	await click(button_named(ui,"続きから"))
	await click(ui._confirm)
	check(SaveGame.capture(main) == before and ui._text.text.contains("破損"),"ロード失敗時は現状・ファイル保全")
	await click(button_named(ui,"ニューゲーム"))
	check(ui._text.text.contains("削除しません") and SaveGame.capture(main) == before,"ニューゲーム確認前に変更なし")
	await click(button_named(ui,"キャンセル / ゲームへ戻る"))
	check(FileAccess.get_file_as_string(ui.path) == "broken","ニューゲーム取消で既存保存維持")
	ui.open()
	await click(button_named(ui,"ニューゲーム"))
	await click(ui._confirm)
	main = current_scene
	var new_game_checkpoint := SaveGame.read_slot("user://checkpoint.json", SaveGame.SLOT_CHECKPOINT)
	check(not new_game_checkpoint.is_empty() and new_game_checkpoint.main.save_run_id == main.save_run_id, "New Game replaces the previous run checkpoint")
	# A checkpoint-only application restart remains neutral until its explicit UI
	# restart is confirmed; that confirmation adopts the verified checkpoint run.
	for save_path in [SaveGame.PROGRESS_PATH, SaveGame.PATH]:
		for suffix in ["", ".bak"]:
			if SaveGame.exists(save_path + suffix): DirAccess.remove_absolute(save_path + suffix)
	SaveGame.active_checkpoint.clear()
	SaveGame.run_selected = true
	main.save_run_id = "checkpoint-only-run"
	main.town.credits = 64
	check(SaveGame.write_checkpoint(main, true), "checkpoint-only city state write")
	var checkpoint_only_bytes := FileAccess.get_file_as_bytes(SaveGame.CHECKPOINT_PATH)
	root.get_tree().reload_current_scene()
	await frames()
	main = current_scene
	ui = main.save_ui
	check(not SaveGame.run_selected and main.save_run_id != "checkpoint-only-run", "checkpoint-only restart starts neutral")
	ui.ask("checkpoint")
	check(not SaveGame.run_selected, "checkpoint confirmation preview does not adopt a run")
	ui.execute()
	check(SaveGame.run_selected and main.save_run_id == "checkpoint-only-run" and main.town.credits == 58 and FileAccess.get_file_as_bytes(SaveGame.CHECKPOINT_PATH) == checkpoint_only_bytes, "checkpoint-only UI restart restores city state and adopts its run")
	check(is_instance_valid(main) and main.storage.count_of(GameData.Item.WOOD) == 0 and not paused,"確認後に新規ゲームへ移行")
	check(FileAccess.get_file_as_string("user://save-ui-test.json") == "broken","新規開始しても保存を勝手に削除しない")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
