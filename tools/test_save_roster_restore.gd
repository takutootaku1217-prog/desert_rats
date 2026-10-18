extends SceneTree

## Cross-roster save regression.  A historical three-person snapshot must be
## recoverable from a current five-person New Game, while a backup from another
## roster is never offered as that run's fallback.
var fails := 0
var main

func check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func clear_paths() -> void:
	for base in [SaveGame.PROGRESS_PATH, SaveGame.CHECKPOINT_PATH, SaveGame.PATH]:
		for suffix in ["", ".bak", ".damaged", ".legacy-v2", ".tmp"]:
			if SaveGame.exists(base + suffix):
				DirAccess.remove_absolute(base + suffix)

func dispose() -> void:
	if main == null:
		return
	main.queue_free()
	main = null
	await process_frame
	await process_frame

func spawn(crew_count: int, force_new := true) -> void:
	await dispose()
	SaveGame.disabled = false
	SaveGame.new_run_requested = force_new
	SaveGame.active_checkpoint.clear()
	SaveGame.run_selected = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set_meta("diagnostic_crew_count", crew_count)
	root.add_child(main)
	# A replacement scene can enter ready synchronously; waiting for its signal
	# after add_child would miss that emission. Two tree frames cover both paths.
	await process_frame
	await process_frame
	main.set_process(false)
	for worker in main.workers:
		worker.set_process(false)

func v2_of(snapshot: Dictionary) -> Dictionary:
	var old := snapshot.duplicate(true)
	old.version = 2
	old.erase("world")
	return old

func _initialize() -> void:
	clear_paths()
	await spawn(3)
	main.save_run_id = "historic-three"
	main.town.credits = 29
	var three_snapshot := SaveGame.capture(main)
	check(main.workers.size() == 3 and SaveGame.validate(three_snapshot, main), "three-person historical snapshot is valid")
	check(SaveGame.write_checkpoint(main, true), "three-person checkpoint writes")

	# A new five-person fixture must restore the exact historic roster through
	# the same Continue path used by SaveUI.
	await spawn(5)
	check(main.workers.size() == 5, "new game fixture begins with five workers")
	check(SaveGame.continue_progress(main, three_snapshot), "Continue accepts a three-person progress snapshot")
	check(main.workers.size() == 3 and main.town.credits == 29 and main.save_run_id == "historic-three", "Continue reconstructs the saved roster before applying fields")
	check(main.workers.map(func(w): return w.char_name) == three_snapshot.crew.map(func(row): return row.worker.char_name), "restored roster identity follows the snapshot")
	check(SaveGame.write_checkpoint(main, true), "restored historic run writes its own checkpoint")

	# Restart is allowed to adopt a checkpoint-only historic run, and must also
	# rebuild the roster rather than rejecting it because New Game is now five.
	await spawn(5, false)
	check(main.workers.size() == 5 and not SaveGame.run_selected, "checkpoint-only boot remains a neutral five-person scene")
	check(SaveGame.restart_from_checkpoint(main), "checkpoint-only historic run can be explicitly restarted")
	check(main.workers.size() == 3 and main.save_run_id == "historic-three", "checkpoint restore reconstructs the historic three-person roster")

	# v2 conversion has no world field but must use the same reconstruction path.
	await spawn(5)
	var converted := SaveGame.migrate_v2(v2_of(three_snapshot), main)
	check(not converted.is_empty() and SaveGame.apply(main, converted), "v2 three-person migration applies to a five-person scene")
	check(main.workers.size() == 3 and main.save_run_id == "historic-three", "v2 migration preserves the original roster size")

	await spawn(5)
	var five_snapshot := SaveGame.capture(main)
	five_snapshot.main.save_run_id = "same-lineage"
	var mismatched_backup := three_snapshot.duplicate(true)
	mismatched_backup.main.save_run_id = "same-lineage"
	check(not SaveGame.backup_matches_progress(five_snapshot, mismatched_backup), "different-size backup is rejected even when its run id is forged equal")
	check(SaveGame.backup_matches_progress(five_snapshot, five_snapshot.duplicate(true)), "same-run same-roster backup remains eligible")

	print("== RESULT: %s ==" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
