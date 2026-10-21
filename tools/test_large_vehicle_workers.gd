extends SceneTree
## Regression for the isolated large-fortress prototype.  It uses the normal
## hauler/processor AI after the chassis switch; it must not inject a movement
## destination into a worker.

var main
var failures := 0
var saved_time_scale := 1.0


func check(ok: bool, message: String) -> void:
	print(("OK " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	saved_time_scale = Engine.time_scale
	Engine.time_scale = 10.0
	main.director.enabled = false
	main.target_speed = 0.0
	main.apply_vehicle_combat_preset()
	# Let the visual walkthrough finish before asserting normal work.  The
	# later work target is selected only by CharacterAI.
	var arrivals := {}
	var walkthrough_done := await _until(func() -> bool:
		for i in main.workers.size():
			var worker = main.workers[i]
			if worker.prototype_walk_target == null and not arrivals.has(i):
				arrivals[i] = worker.floor_i == 3 and worker.position.distance_to(LargeVehicleLayout.top_room_anchor(i)) <= 4.1
		return arrivals.size() == main.workers.size(), 4.0)
	for i in main.workers.size():
		check(bool(arrivals.get(i, false)), "worker %d finishes walkthrough at its actual upper-deck anchor" % i)
	check(walkthrough_done, "large chassis walkthrough reaches all three upper-deck anchors")
	for worker in main.workers:
		for job in GameData.job_list():
			worker.priorities[job] = 0
		worker.ai.on_priority_changed()
	var hauler = main.workers[0]
	hauler.priorities[GameData.Job.HAUL] = 5
	hauler.priorities[GameData.Job.PROCESS] = 5
	hauler.ai.on_priority_changed()
	main.finish_build("workbench")
	main.storage.inventory.counts = {GameData.Item.WOOD: 2}
	main.request_order("tool_wood_pick", 1)
	var route_seen := {"lower_ladder": false, "middle_deck": false, "previous_floor": hauler.floor_i}
	var crafted := await _until(func() -> bool:
		if int(route_seen.previous_floor) == 1 and hauler.floor_i == 2:
			route_seen.lower_ladder = true
		if hauler.floor_i == 2:
			route_seen.middle_deck = true
		route_seen.previous_floor = hauler.floor_i
		return main.processor.total_done >= 1, 8.0)
	check(route_seen.lower_ladder and route_seen.middle_deck, "normal hauling uses the lower-deck ladder and middle deck")
	check(crafted, "normal hauling and processing complete after large chassis switch")
	check(hauler.position.distance_to(main.processor.position) > 0.0 or main.processor.total_done >= 1, "worker position is advanced by normal AI rather than a fixed interior marker")
	# SaveGame restores the loadout first; the next regular Base tick must also
	# restore the matching facility floor coordinates before worker AI runs.
	var snapshot := SaveGame.capture(main)
	main.base.vehicle_loadout["chassis"] = "medium"
	await process_frame
	check(not GameData.large_three_deck_enabled and is_equal_approx(main.storage.position.y, GameData.LO_Y), "switching back restores ordinary storage floor")
	check(SaveGame.apply(main, snapshot), "large chassis snapshot applies")
	await process_frame
	check(GameData.large_three_deck_enabled and is_equal_approx(main.storage.position.y, LargeVehicleLayout.deck_y(1)), "save restore synchronizes large storage floor before AI resumes")
	Engine.time_scale = saved_time_scale
	main.queue_free()
	print("== large vehicle workers: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)


func _until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()
