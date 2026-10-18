extends "res://tools/test_equipment_ui.gd"

const PROGRESS := "user://save-slots-progress.json"
const CHECKPOINT := "user://save-slots-checkpoint.json"

func _clear(path: String) -> void:
	for suffix in ["", ".bak", ".damaged", ".tmp"]:
		if SaveGame.exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await main.ready
	paused = true
	_clear(PROGRESS)
	_clear(CHECKPOINT)

	# 初期地点用 checkpoint は、都市未到達・依頼未受領の完全な状態でも作れる。
	check(SaveGame.write(main, CHECKPOINT, true, SaveGame.SLOT_CHECKPOINT), "initial checkpoint write " + SaveGame.last_error)
	var checkpoint := SaveGame.read_slot(CHECKPOINT, SaveGame.SLOT_CHECKPOINT)
	check(not checkpoint.is_empty(), "initial checkpoint is isolated")

	# 報酬受領、在庫、補充予約を含めた途中経過を別枠へ保存する。
	main.town.credits = 31
	main.storage.store_owned(GameData.Item.WOOD, 5)
	main.quarry.visit_generated = {GameData.Item.IRON_ORE: 4}
	main.quarry.visit_nearby = {GameData.Item.STONE: 2}
	main.town.claimed.supply = 1
	check(SaveGame.write(main, PROGRESS, true, SaveGame.SLOT_PROGRESS), "mid-run save write " + SaveGame.last_error)
	var progress := SaveGame.read_slot(PROGRESS, SaveGame.SLOT_PROGRESS)
	check(not progress.is_empty(), "mid-run slot is isolated")
	check(progress.town.claimed.supply == 1 and progress.quarry.visit_generated == {GameData.Item.IRON_ORE: 4}, "reward and respawn reservation captured together")

	# 途中から続ける: 同一時点の全状態だけを戻し、checkpoint は混同しない。
	main.town.credits = 2
	main.storage.inventory.counts.clear()
	main.quarry.visit_generated.clear()
	check(SaveGame.apply(main, progress), "continue applies the progress slot")
	check(main.town.credits == 31 and main.storage.count_of(GameData.Item.WOOD) == 5 and main.quarry.visit_generated == {GameData.Item.IRON_ORE: 4}, "continue restores currency, inventory, and reservation")
	check(checkpoint != progress, "slots keep distinct payloads")

	# 出撃前からやり直す: 毎回ファイル上の checkpoint を起点にするため損失は非累積。
	main.town.credits = 40
	check(SaveGame.write(main, CHECKPOINT, true, SaveGame.SLOT_CHECKPOINT), "city departure checkpoint write")
	main.town.credits = 99
	main.storage.store_owned(GameData.Item.STONE, 8)
	check(SaveGame.restart_from_checkpoint(main, {"credits_fixed": 7}, CHECKPOINT), "restart from checkpoint")
	check(main.town.credits == 33 and main.storage.count_of(GameData.Item.STONE) == 0, "restart restores checkpoint then applies one test loss")
	main.town.credits = 1
	check(SaveGame.restart_from_checkpoint(main, {"credits_fixed": 7}, CHECKPOINT), "repeat restart")
	check(main.town.credits == 33, "restart loss is non-cumulative")

	# Approved test policy: ten percent of checkpoint credits, truncating, no debt,
	# and no resource loss.  Restarts always re-read the untouched checkpoint.
	main.town.credits = 49
	main.storage.store_owned(GameData.Item.WOOD, 3)
	var wood_at_checkpoint: int = main.storage.count_of(GameData.Item.WOOD)
	check(SaveGame.write(main, CHECKPOINT, true, SaveGame.SLOT_CHECKPOINT), "ratio checkpoint write")
	main.town.credits = 0
	main.storage.inventory.counts.clear()
	check(SaveGame.restart_from_checkpoint(main, SaveGame.DEFAULT_RESTART_LOSS, CHECKPOINT), "ratio restart")
	check(main.town.credits == 45 and main.storage.count_of(GameData.Item.WOOD) == wood_at_checkpoint, "10 percent truncates and leaves resources intact")
	main.town.credits = 0
	check(SaveGame.restart_from_checkpoint(main, SaveGame.DEFAULT_RESTART_LOSS, CHECKPOINT) and main.town.credits == 45, "ratio loss is non-cumulative")
	main.town.credits = 0
	check(SaveGame.write(main, CHECKPOINT, true, SaveGame.SLOT_CHECKPOINT), "zero-credit checkpoint write")
	check(SaveGame.restart_from_checkpoint(main, SaveGame.DEFAULT_RESTART_LOSS, CHECKPOINT) and main.town.credits == 0, "zero credits never creates debt")

	# A checkpoint has its own backup restore path.
	main.town.credits = 77
	check(SaveGame.write(main, CHECKPOINT, true, SaveGame.SLOT_CHECKPOINT), "checkpoint backup source write")
	main.town.credits = 88
	check(SaveGame.write(main, CHECKPOINT, true, SaveGame.SLOT_CHECKPOINT), "checkpoint backup rotation write")
	var broken_checkpoint := FileAccess.open(CHECKPOINT, FileAccess.WRITE)
	broken_checkpoint.store_string("broken")
	broken_checkpoint.close()
	check(SaveGame.restart_from_checkpoint(main, SaveGame.DEFAULT_RESTART_LOSS, CHECKPOINT + ".bak") and main.town.credits == 70, "checkpoint backup restores after primary corruption")

	# A confirmed New Game must replace a previous run's checkpoint without
	# deleting the separate progress save.
	_clear(SaveGame.CHECKPOINT_PATH)
	main.save_run_id = "old-run"
	main.town.credits = 123
	check(SaveGame.write_checkpoint(main, true), "old run checkpoint write")
	main.save_run_id = "new-run"
	main.town.credits = 17
	check(SaveGame.ensure_initial_checkpoint(main, true), "new game refreshes checkpoint " + SaveGame.last_error)
	main.town.credits = 999
	check(SaveGame.restart_from_checkpoint(main, SaveGame.DEFAULT_RESTART_LOSS) and main.save_run_id == "new-run" and main.town.credits == 16, "new game cannot restart into old run " + SaveGame.last_error)

	# 途中書き込みが失敗しても、既存の progress と backup を維持する。
	var before := FileAccess.get_file_as_bytes(PROGRESS)
	DirAccess.make_dir_absolute(PROGRESS + ".bak.tmp")
	check(not SaveGame.write(main, PROGRESS, true, SaveGame.SLOT_PROGRESS) and FileAccess.get_file_as_bytes(PROGRESS) == before, "failed backup write preserves progress")
	DirAccess.remove_absolute(PROGRESS + ".bak.tmp")
	print("== result: %s ==" % ("PASS" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)
