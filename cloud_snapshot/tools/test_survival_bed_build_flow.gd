extends SceneTree
## Regression contract for the initial survival-loop bed path.  This uses the
## real Main, worker AI, processor and facility queue; the direct item setup
## only isolates the build pipeline from the separately tested animal hunt.

var main
var failures := 0
const STEP := 0.2


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


func _pipeline_state() -> String:
	var current_id := String(main.processor.current.get("id", "none"))
	return "queue=%s incoming=%d orders=%d current=%s output=%d" % [
		str(main.build_queue),
		main.processor.incoming.size(),
		main.processor.orders.size(),
		current_id,
		main.processor.output.size(),
	]


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

	# Workbench is the existing prerequisite for bed-pack production.
	main.storage.add_item(GameData.Item.WOOD, 3)
	_check(main.request_build("workbench"), "normal build request accepts the workbench")
	var bench_done := await _advance_home_until(func(): return main.has_facility("workbench"), 120.0)
	_check(bench_done, "workers and processor complete the workbench request (%s)" % _pipeline_state())

	# The animal hunt/hauling contract supplies these exact bed inputs.  This
	# assertion proves that a normal accepted bed request then crafts the pack
	# and installs the facility without a second player action.
	main.storage.add_item(GameData.Item.HIDE, 2)
	main.storage.add_item(GameData.Item.BONE, 1)
	_check(main.request_build("bed"), "normal build request accepts the bed")
	var bed_done := await _advance_home_until(func(): return main.has_facility("bed"), 120.0)
	_check(bed_done, "workers and processor complete the bed request (%s)" % _pipeline_state())

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	SaveGame.disabled = false
	quit(1 if failures > 0 else 0)
