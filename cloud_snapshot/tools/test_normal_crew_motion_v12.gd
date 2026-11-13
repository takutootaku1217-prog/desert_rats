extends SceneTree
## Normal-role motion contract. The bridge session owns cargo and movement;
## this test observes only the quarter-view presentation.

const Adapter = preload("res://bridge/route_connection_adapter.gd")
const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 1.0 / 30.0
const LIMIT := 1800

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	SaveGame.disabled = true
	var main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	main.director.enabled = false
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.priorities[job] = 0
	var travel_ok := await _move_to_quarry(main)
	_check(travel_ok, "normal motion: existing WorldTrip reaches C quarry")
	if not travel_ok:
		main.queue_free()
		quit(1)
		return
	var created: Dictionary = RouteSession.create_from_game(main, "normal-crew-motion-v12", {"outpost_enabled": false})
	_check(bool(created.get("ok", false)), "normal motion: ordinary harvest/carry/escort session is created")
	if not bool(created.get("ok", false)):
		main.queue_free()
		quit(1)
		return
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var adapter = Adapter.new()
	adapter.configure(main, created.session)
	layer.add_child(adapter)
	adapter.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var crew_views = adapter.canyon_hub.get_node_or_null("CanyonCrewViews")
	_check(crew_views != null and crew_views.has_method("debug_snapshot"), "normal motion: presentation exposes read-only snapshot")
	if crew_views == null:
		adapter.queue_free()
		layer.queue_free()
		main.queue_free()
		quit(1)
		return
	var walk_frames := {}
	var harvest_frames := {}
	var foot_ok := true
	var scale_ok := true
	var cargo_matches_session := true
	var v2_carry_seen := false
	var cargo_cleared_after_relay := false
	var standard_motion_scope_safe := true
	var dock_v2_seen := false
	var previously_carried := false
	for step_index in LIMIT:
		adapter._process(STEP)
		if step_index % 30 == 0:
			await process_frame
		var harvest_actor: Dictionary = adapter.session.actors.get("worker:0", {})
		var harvest_snapshot: Dictionary = crew_views.call("debug_snapshot", "worker:0")
		var expected_foot: Vector2 = adapter.canyon_hub.map_point(Vector2(float(harvest_actor.get("x", 0.0)), float(harvest_actor.get("y", 0.0))))
		var snapshot_foot: Vector2 = harvest_snapshot.get("foot_point", Vector2.INF)
		var snapshot_scale: Vector2 = harvest_snapshot.get("sprite_scale", Vector2.ZERO)
		foot_ok = foot_ok and snapshot_foot.distance_to(expected_foot) <= 0.01
		scale_ok = scale_ok and snapshot_scale == Vector2.ONE
		var carried := int(harvest_actor.get("carry_n", 0)) > 0
		cargo_matches_session = cargo_matches_session and bool(harvest_snapshot.get("cargo_visible", false)) == carried
		var state := str(harvest_actor.get("state", ""))
		if state in ["to_resource", "to_relay"] and not carried:
			walk_frames[str(harvest_snapshot.get("frame_name", ""))] = true
		if state == "harvesting":
			harvest_frames[str(harvest_snapshot.get("frame_name", ""))] = true
		if carried:
			v2_carry_seen = v2_carry_seen or str(harvest_snapshot.get("motion_asset", "")) == "v2"
		# The session may deposit and let the carrier pick up in the same tick, so
		# relay stock can already be zero when the harvester becomes empty.
		var carrier_actor: Dictionary = adapter.session.actors.get("worker:1", {})
		if previously_carried and not carried:
			var handoff_owned_by_session := int(adapter.session.state_summary().get("relay", 0)) > 0 or int(carrier_actor.get("carry_n", 0)) > 0
			cargo_cleared_after_relay = cargo_cleared_after_relay or handoff_owned_by_session and not bool(harvest_snapshot.get("cargo_visible", true))
		previously_carried = carried
		# Audit every normal actor, not only the visible harvest/carrier pair.
		# v3 is intentionally available only to an empty-handed harvest worker
		# during walk/harvest. Carry, dock, escort, and every other role remain
		# in v2 until their direction/occlusion art contracts exist.
		for raw_actor_id in adapter.session.actors:
			var actor_id := str(raw_actor_id)
			var observed_actor: Dictionary = adapter.session.actors.get(actor_id, {})
			var observed: Dictionary = crew_views.call("debug_snapshot", actor_id)
			var observed_role := str(observed_actor.get("role", ""))
			var observed_carrying := int(observed_actor.get("carry_n", 0)) > 0
			var observed_state := str(observed_actor.get("state", ""))
			var observed_asset := str(observed.get("motion_asset", ""))
			var observed_kind := str(observed.get("visual_kind", ""))
			cargo_matches_session = cargo_matches_session and bool(observed.get("cargo_visible", false)) == observed_carrying
			if observed_asset == "v3":
				standard_motion_scope_safe = standard_motion_scope_safe and observed_role == "harvest" and not observed_carrying and observed_kind in ["walk", "harvest"]
			if observed_carrying or observed_state == "dock_wait" or observed_role != "harvest":
				standard_motion_scope_safe = standard_motion_scope_safe and observed_asset == "v2"
			if observed_state == "dock_wait":
				dock_v2_seen = dock_v2_seen or observed_asset == "v2"
		if walk_frames.size() >= 2 and harvest_frames.size() >= 2 and v2_carry_seen and cargo_cleared_after_relay and dock_v2_seen:
			break
	_check(walk_frames.size() >= 2, "normal motion: harvest role advances existing v3 walk frames in normal mode")
	_check(harvest_frames.size() >= 2, "normal motion: harvest role advances existing v3 harvest frames without moving its feet")
	_check(foot_ok and scale_ok, "normal motion: every observed standard pose keeps an integer map foot and 1x scale")
	_check(cargo_matches_session and v2_carry_seen and cargo_cleared_after_relay, "normal motion: normal carry art follows session cargo and clears after relay")
	_check(standard_motion_scope_safe, "normal motion: only empty-handed harvest walk/harvest uses v3; every carry, dock, escort, and other role remains v2")
	_check(dock_v2_seen, "normal motion: a normal carrier reaches dock_wait and remains on the safe v2 path")
	var before_refresh: Dictionary = adapter.session.to_dict()
	adapter.canyon_hub.refresh(0.0)
	_check(adapter.session.to_dict() == before_refresh and adapter.session.conservation_ok(), "normal motion: refresh does not write any serialized session authority or conservation state")
	adapter.queue_free()
	layer.queue_free()
	await process_frame
	main.queue_free()
	print("== Result: %s ==" % ("PASS" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)

func _move_to_quarry(main) -> bool:
	for destination in ["b_forest", "c_quarry"]:
		if not main.world.request(destination):
			return false
		for unused in 240:
			main._process(0.2)
			if main.world.phase == "stopped" and main.world.region == destination:
				break
			if unused % 24 == 0:
				await process_frame
		if main.world.phase != "stopped" or main.world.region != destination:
			return false
	return true
