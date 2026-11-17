extends SceneTree
## Regression: a finished packed facility that the player moved to the workshop
## must not stall its installation order.  Real Main, worker AI, transfer queue,
## processor and build queue; the only fixture is the starting stock.

var main
var failures := 0
const STEP := 0.2
const BOX := GameData.Item.STORAGE_BOX


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _configure_home_workers() -> void:
	main.refill_settings = {}
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.set_priority(job, 0)
	main.workers[0].set_priority(GameData.Job.HAUL, 5)
	main.workers[1].set_priority(GameData.Job.PROCESS, 5)


func _home_step() -> void:
	main._process(STEP)
	for worker in main.workers:
		worker._process(STEP)


func _advance_home_until(predicate: Callable, seconds: float) -> bool:
	for frame in ceili(seconds / STEP):
		_home_step()
		if predicate.call():
			return true
		if frame % 48 == 0:
			await process_frame
	return bool(predicate.call())


func _carried(item: int) -> int:
	var n := 0
	for w in main.workers:
		if w.carrying == item: n += w.carry_n
	return n


func _state() -> String:
	return "queue=%s transfers=%s storage=%d workshop=%d carried=%d orders=%d" % [
		str(main.build_queue), str(main.transfer_queue), main.storage.count_of(BOX),
		main.workshop_count(BOX), _carried(BOX), main.processor.orders.size()]


func _run() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 0.0
	_configure_home_workers()

	main.storage.add_item(GameData.Item.WOOD, 3)
	_check(main.request_build("workbench"), "workbench request accepted")
	_check(await _advance_home_until(func(): return main.has_facility("workbench"), 120.0), "workbench built (%s)" % _state())

	# One finished storage box, no spare materials: it cannot be crafted again.
	var before_boxes: int = main.base.facility_count("cargo_rack")
	_check(main.storage.add_item(BOX, 1) == 1, "one finished storage box is in the warehouse")
	_check(main.request_transfer(BOX, 1, "to_workshop") == 1, "player moves the box to the workshop with the normal transfer")
	_check(await _advance_home_until(func(): return main.workshop_count(BOX) == 1, 120.0), "a worker carries the box to the workshop (%s)" % _state())
	_check(main.storage.count_of(BOX) == 0 and main.transfer_queue.is_empty(), "the box is only at the workshop")

	# Without an installation order the box stays where the player put it.
	await _advance_home_until(func(): return false, 20.0)
	_check(main.workshop_count(BOX) == 1 and main.transfer_queue.is_empty(), "no order: the box is not moved back on its own (%s)" % _state())

	_check(main.request_build("cargo_rack"), "installation order accepted while the box is at the workshop")
	var saw_return := [false]
	var max_total := [0]
	var built := await _advance_home_until(func():
		for w in main.workers:
			if w.carrying == BOX and w.ai.state == CharacterAI.State.XFER_MOVE and w.ai.xfer_dir == "to_storage": saw_return[0] = true
		max_total[0] = maxi(max_total[0], main.storage.count_of(BOX) + main.workshop_count(BOX) + _carried(BOX))
		return main.base.facility_count("cargo_rack") == before_boxes + 1, 240.0)
	_check(built, "the order installs the box that was at the workshop (%s)" % _state())
	_check(saw_return[0], "a worker physically carried the box back to the warehouse (XFER_MOVE to_storage)")
	_check(max_total[0] <= 1, "the box was never duplicated (max seen %d)" % max_total[0])
	_check(main.storage.count_of(BOX) == 0 and main.workshop_count(BOX) == 0 and _carried(BOX) == 0, "exactly the one box was consumed (%s)" % _state())
	_check(main.build_queue.is_empty() and main.transfer_queue.is_empty(), "no order or transfer is left behind (%s)" % _state())

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	SaveGame.disabled = false
	quit(1 if failures > 0 else 0)
