extends SceneTree

const Model = preload("res://scripts/two_lane_prototype_model.gd")
var fails := 0


func check(ok: bool, text: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", text])
	if not ok:
		fails += 1


func _initialize() -> void:
	print("-- continuous two-lane-width depth-strip model --")
	var model: GroundTwoLanePrototypeModel = Model.new()
	model.reset()
	model.run_for(70.0)
	check(model.complete(), "same total six resources gather, haul, existing ramp return and unload")
	check(model.delivered == Model.TOTAL_RESOURCE and model.remaining_resource() == 0, "resource amount and initial conditions stay fixed")
	check(not model.depth_motion_xs.is_empty() and model.depth_motion_xs.max() - model.depth_motion_xs.min() > 30.0, "depth travel occurs at multiple X positions with no fixed crossing")
	check(model.max_depth_step <= Model.WALK_SPEED * 0.05 + 0.01, "depth motion is continuous per frame, never a teleport")
	check(model.min_worker_distance >= Model.MIN_SPACING - 0.01, "near workers are separated without a queue or bottleneck")
	var combat: GroundTwoLanePrototypeModel = Model.new()
	combat.reset()
	check(combat.depth_melee_is_blocked(), "same-X back/front target is outside melee reach")
	check(combat.start_chase(0), "direct depth chase order starts")
	combat.run_for(35.0)
	check(combat.combat_hits == 1, "chase closes physical distance before one melee hit")
	var retreat: GroundTwoLanePrototypeModel = Model.new()
	retreat.reset()
	retreat.run_for(4.0)
	check(retreat.start_personal_retreat(1), "individual retreat order starts")
	retreat.run_for(35.0)
	check(String(retreat.agents[1].state) == "retreated", "individual retreat uses the existing ramp to return to base")
	check(retreat.retreat_violations == 0, "retreat does not resume gathering or combat")
	print("  completion %.2fs / closest %s" % [model.completion_time, model.closest_pair])
	print("== result: %s ==" % ("all passed" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)
