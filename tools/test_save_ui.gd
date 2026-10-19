extends "res://tools/test_clarity_ui.gd"

func write_v2_envelope(path: String, snapshot: Dictionary) -> void:
	var legacy := snapshot.duplicate(true)
	legacy.version = 2
	legacy.erase("world")
	var bytes := var_to_bytes(legacy)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "payload": Marshalls.raw_to_base64(bytes), "sha256": hash.finish().hex_encode()}))
	f.close()

func clear_save_paths() -> void:
	for save_path in [SaveGame.PROGRESS_PATH, SaveGame.CHECKPOINT_PATH, SaveGame.PATH]:
		for suffix in ["", ".bak", ".damaged", ".legacy-v2", ".tmp"]:
			if SaveGame.exists(save_path + suffix): DirAccess.remove_absolute(save_path + suffix)

func jp(codes: Array[int]) -> String:
	var text := ""
	for code in codes: text += String.chr(code)
	return text

func action_button(ui, action: String) -> Button:
	match action:
		"save": return button_named(ui, jp([0x624b, 0x52d5, 0x3067, 0x4fdd, 0x5b58]))
		"load": return button_named(ui, jp([0x7d9a, 0x304d, 0x304b, 0x3089]))
		"new": return button_named(ui, jp([0x30cb, 0x30e5, 0x30fc, 0x30b2, 0x30fc, 0x30e0]))
		"checkpoint": return button_named(ui, jp([0x51fa, 0x6483, 0x524d, 0x304b, 0x3089, 0x3084, 0x308a, 0x76f4, 0x3059]))
	return null

func activate_ui(button: Button) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.grab_focus()
	await key(KEY_ENTER)
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
	# A valid progress backup is the recovery source when its paired primary is
	# unreadable or absent. Exercise the real SaveUI path, rather than only the
	# comparison helper, so a primary-read failure cannot block recovery again.
	main.storage.store_owned(GameData.Item.WOOD, 5)
	var corrupt_progress := FileAccess.open(ui.path, FileAccess.WRITE); corrupt_progress.store_string("broken"); corrupt_progress.close()
	ui.ask("backup")
	ui.execute()
	check(main.storage.count_of(GameData.Item.WOOD) == initial, "SaveUI recovers a valid progress backup after primary corruption")
	main.storage.store_owned(GameData.Item.WOOD, 6)
	DirAccess.remove_absolute(ui.path)
	ui.ask("backup")
	ui.execute()
	check(main.storage.count_of(GameData.Item.WOOD) == initial, "SaveUI recovers a valid progress backup when the primary is missing")
	# The current checkpoint remains an authority boundary after the progress
	# primary is damaged.  Do not accept an otherwise valid backup from another
	# run simply because the primary can no longer be parsed.
	var checkpoint_snapshot := SaveGame.capture(main)
	checkpoint_snapshot.main.save_run_id = "save-ui-primary-run"
	main.save_run_id = "save-ui-primary-run"
	check(SaveGame.write(main, ui.checkpoint_path, true, SaveGame.SLOT_CHECKPOINT, checkpoint_snapshot), "same-run checkpoint anchors damaged-primary recovery")
	var foreign_only_backup := checkpoint_snapshot.duplicate(true)
	foreign_only_backup.main.save_run_id = "save-ui-foreign-run"
	check(SaveGame.write(main, ui.path + ".bak", true, SaveGame.SLOT_PROGRESS, foreign_only_backup), "foreign backup fixture writes")
	var broken_primary := FileAccess.open(ui.path, FileAccess.WRITE); broken_primary.store_string("broken"); broken_primary.close()
	var before_damaged_foreign := SaveGame.capture(main)
	ui.ask("backup")
	ui.execute()
	check(SaveGame.capture(main) == before_damaged_foreign and ui._text.text.contains("different run"), "damaged primary rejects a readable backup from another run")
	# A readable primary remains an authority boundary: a normal backup from a
	# different run must not replace it just because the backup is valid itself.
	var primary_snapshot := SaveGame.capture(main)
	primary_snapshot.main.save_run_id = "save-ui-primary-run"
	var foreign_backup := primary_snapshot.duplicate(true)
	foreign_backup.main.save_run_id = "save-ui-foreign-run"
	check(SaveGame.write(main, ui.path, true, SaveGame.SLOT_PROGRESS, primary_snapshot) and SaveGame.write(main, ui.path + ".bak", true, SaveGame.SLOT_PROGRESS, foreign_backup), "paired primary and foreign backup fixtures write")
	main.storage.store_owned(GameData.Item.WOOD, 9)
	var before_foreign_backup := SaveGame.capture(main)
	ui.ask("backup")
	ui.execute()
	check(SaveGame.capture(main) == before_foreign_backup and ui._text.text.contains("different run"), "SaveUI rejects a readable primary paired with another run backup")
	check(SaveGame.continue_progress(main, primary_snapshot), "restores the baseline fixture after foreign backup rejection")
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
	DirAccess.remove_absolute(ui.path + ".bak")
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
	# Startup starts neutral whenever a saved run exists. Escaping its resume UI
	# commits the currently simulated scene as a new run, creates only its initial
	# checkpoint, and leaves old progress untouched until a manual save.
	clear_save_paths()
	SaveGame.run_selected = true
	SaveGame.active_checkpoint.clear()
	main.save_run_id = "saved-run"
	main.town.credits = 90
	check(SaveGame.write_checkpoint(main, true), "saved-run checkpoint fixture")
	main.town.credits = 71
	check(SaveGame.write_progress(main, true), "saved-run progress fixture")
	var saved_progress_bytes := FileAccess.get_file_as_bytes(SaveGame.PROGRESS_PATH)
	root.get_tree().reload_current_scene()
	await frames()
	main = current_scene
	ui = main.save_ui
	ui.open() # Headless diagnostics invoke the same startup resume screen explicitly.
	check(not SaveGame.run_selected and ui.is_open(), "startup resume screen is neutral")
	main.town.credits = 13 # Simulate state advancing before a neutral choice settles.
	main.storage.store_owned(GameData.Item.WOOD, 2)
	await key(KEY_ESCAPE)
	var cancelled_run: String = str(main.save_run_id)
	var cancelled_checkpoint := SaveGame.read_slot(SaveGame.CHECKPOINT_PATH, SaveGame.SLOT_CHECKPOINT)
	check(SaveGame.run_selected and cancelled_run != "saved-run" and SaveGame.snapshot_run_id(cancelled_checkpoint) == cancelled_run, "resume cancel selects simulated new run and writes its initial checkpoint")
	check(FileAccess.get_file_as_bytes(SaveGame.PROGRESS_PATH) == saved_progress_bytes, "resume cancel preserves existing progress")
	var before_foreign_restart := SaveGame.capture(main)
	check(not SaveGame.restart_from_checkpoint(main, SaveGame.DEFAULT_RESTART_LOSS, SaveGame.CHECKPOINT_PATH + ".bak") and SaveGame.capture(main) == before_foreign_restart, "cancelled new run rejects saved-run checkpoint backup")
	ui.open()
	var save_button := action_button(ui, "save")
	await activate_ui(save_button)
	await activate_ui(ui._confirm)
	var cancelled_progress := SaveGame.read_progress()
	check(not cancelled_progress.is_empty(), "manual save after cancel creates progress")
	check(SaveGame.snapshot_run_id(cancelled_progress) == cancelled_run, "manual save after cancel records the new run")
	check(cancelled_progress.town.credits == 13, "manual save after cancel retains simulated progress")
	await key(KEY_ESCAPE)

	# A real v2 envelope must use the visible Continue -> migrate UI, and that
	# migration must settle run selection rather than leaving a neutral run behind.
	clear_save_paths()
	main.save_run_id = "legacy-v2-run"
	main.town.credits = 37
	write_v2_envelope(SaveGame.PATH, SaveGame.capture(main))
	root.get_tree().reload_current_scene()
	await frames()
	main = current_scene
	ui = main.save_ui
	ui.open()
	var load_button := action_button(ui, "load")
	await activate_ui(load_button)
	await activate_ui(ui._confirm)
	check(ui._legacy.visible and not SaveGame.run_selected, "v2 Continue exposes migration without selecting a run")
	await click(ui._legacy)
	await frames()
	var confirm_area: Rect2 = ui._confirm.get_global_rect()
	var scroll_area: Rect2 = ui._scroll.get_global_rect()
	var panel_area: Rect2 = ui._panel.get_global_rect()
	var viewport_area: Rect2 = root.get_visible_rect()
	check(panel_area.position.x >= viewport_area.position.x - 1.0 and panel_area.position.y >= viewport_area.position.y - 1.0 and panel_area.end.x <= viewport_area.end.x + 1.0 and panel_area.end.y <= viewport_area.end.y + 1.0, "save panel scales inside the current viewport")
	check(confirm_area.position.y >= scroll_area.position.y - 1.0 and confirm_area.end.y <= scroll_area.end.y + 1.0, "migration confirmation remains reachable in the visible save panel")
	await click(ui._confirm)
	check(SaveGame.run_selected and main.save_run_id == "legacy-v2-run" and main.town.credits == 37 and SaveGame.read(SaveGame.PATH, true).get("version") == 2, "v2 migration UI restores and selects the legacy run without rewriting it")
	ui.open()
	await key(KEY_ESCAPE)

	# With only a checkpoint, ordinary Continue remains neutral, explicit restart
	# adopts exactly that run, and New Game replaces it with a distinct run.
	clear_save_paths()
	SaveGame.run_selected = true
	SaveGame.active_checkpoint.clear()
	main.save_run_id = "checkpoint-only-ui-run"
	main.town.credits = 64
	check(SaveGame.write_checkpoint(main, true), "checkpoint-only UI fixture")
	root.get_tree().reload_current_scene()
	await frames()
	main = current_scene
	ui = main.save_ui
	ui.open()
	await click(action_button(ui, "load"))
	await click(ui._confirm)
	check(not SaveGame.run_selected and main.save_run_id != "checkpoint-only-ui-run", "ordinary Continue does not adopt checkpoint-only run")
	await click(action_button(ui, "checkpoint"))
	await click(ui._confirm)
	check(SaveGame.run_selected and main.save_run_id == "checkpoint-only-ui-run" and main.town.credits == 58, "explicit checkpoint UI restart adopts checkpoint-only run")
	ui.open()
	await click(action_button(ui, "new"))
	await click(ui._confirm)
	await frames()
	main = current_scene
	var replacement_checkpoint := SaveGame.read_slot(SaveGame.CHECKPOINT_PATH, SaveGame.SLOT_CHECKPOINT)
	check(SaveGame.run_selected and main.save_run_id != "checkpoint-only-ui-run" and SaveGame.snapshot_run_id(replacement_checkpoint) == main.save_run_id, "New Game selects and checkpoints a distinct run")
	print("== " + jp([0x7d50, 0x679c]) + ": " + jp([0x3059, 0x3079, 0x3066, 0x6210, 0x529f]) + " ==" if fails == 0 else "%d failures" % fails)
	quit(1 if fails else 0)
