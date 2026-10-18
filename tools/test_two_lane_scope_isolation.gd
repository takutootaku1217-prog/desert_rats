extends "res://tools/test_quarry.gd"
## Verifies that the opt-in depth strip never changes ordinary map, road, or
## other-region movement. Run once without and once with the prototype flag.

const BACK_Y := 570.0
const FRONT_Y := 625.0


func _initialize() -> void:
	await fresh()
	var enabled := OS.get_cmdline_user_args().has("two-lane-depth-prototype")
	if enabled:
		await _prototype_scope()
	else:
		_normal_scope()
	if fails == 0:
		print("TWO_LANE_SCOPE_OK")
	print("== result: %s ==" % ("all passed" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)


func _move_outside_band(worker, label: String) -> void:
	worker.stop_work()
	worker.floor_i = 0
	worker.position = Vector2(700.0, 600.0)
	worker.target = Vector2(920.0, 680.0)
	for _i in 8:
		worker.move_to_target(0.2)
	check(worker.position.y > FRONT_Y + 20.0, "%s ground movement is not clamped to the prototype strip" % label)


func _normal_scope() -> void:
	var worker = main.workers[0]
	check(not main.has_meta("ground_depth_strip_config"), "normal startup does not install prototype metadata")
	check(not main.world.depth_strip_active() and not worker.ground_depth_strip_active(), "normal south_oasis uses ordinary outdoor movement")
	_move_outside_band(worker, "normal startup")


func _move_location(region: String, road := "") -> void:
	main.world._archive()
	main.world.region = region
	main.world.road = road
	main.world.phase = "stopped" if road == "" else "travel"
	main.world.progress = 0.0
	main.world.direction = 1
	main.world.origin = "" if road == "" else WorldMapDB.ROADS[road][0]
	main.world.destination = "" if road == "" else WorldMapDB.ROADS[road][1]
	main.world._ensure_location()


func _prototype_scope() -> void:
	var worker = main.workers[0]
	check(main.world.depth_strip_active() and worker.ground_depth_strip_active(), "prototype is active at south_oasis only")
	check(is_equal_approx(main.world.clamp_outdoor_y(680.0), FRONT_Y), "active south_oasis clamps targets to documented front edge")
	_move_location("east_sands")
	check(not main.world.depth_strip_active() and not worker.ground_depth_strip_active(), "other region disables strip despite prototype metadata")
	check(is_equal_approx(main.world.clamp_outdoor_y(680.0), 680.0), "other region keeps unmodified outdoor Y values")
	_move_outside_band(worker, "other region")
	_move_location("south_oasis", "01")
	check(not main.world.depth_strip_active() and not worker.ground_depth_strip_active(), "road disables strip despite south_oasis endpoint")
	check(is_equal_approx(main.world.clamp_outdoor_y(680.0), 680.0), "road keeps unmodified outdoor Y values")
	_move_outside_band(worker, "road")
