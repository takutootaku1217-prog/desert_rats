extends SceneTree
## Regression: the normal map/JourneyPlan route must reach C and surface the
## same mine-arrival decision as a direct destination request.

const STEP := 0.2
var failures := 0
var main = null

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	print("  %s %s" % ["ok" if value else "FAIL", message])
	if not value:
		failures += 1

func _run() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 60.0
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	for worker in main.workers:
		worker.stop_work()
	for job in GameData.job_list():
		for worker in main.workers:
			worker.set_priority(job, 0)
	_check(main.world.region == "a_start" and main.world.phase == "stopped", "normal route starts stopped at A")
	# Exercise the same public map UI route selection used by an ordinary click,
	# rather than calling JourneyPlan directly.
	main.map_ui.open()
	main.map_ui.select_region("c_quarry")
	main.map_ui._go()
	_check(not main.map_ui.is_open(), "map UI closes after accepting the normal A-B-C route")
	_check(main.journey.remaining == ["b_forest", "c_quarry"], "map UI records the normal A-B-C route")
	for frame in 360:
		main._process(STEP)
		if frame % 24 == 0:
			await process_frame
		if main.world.region == "c_quarry" and main.world.phase == "stopped":
			break
	await process_frame
	_check(main.world.region == "c_quarry" and main.world.phase == "stopped", "normal map route arrives stopped at C")
	_check(main.mine_arrival_gate != null and main.mine_arrival_gate.visible_state() == "arrival_choice", "normal map route opens the C mine entry choice")
	if is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	await process_frame
	print("== first-region mine journey gate: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
