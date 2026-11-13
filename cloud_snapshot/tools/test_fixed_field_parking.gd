extends SceneTree
const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.5
var main
var fails := 0
func _init():
	call_deferred("_run")
func _run():
	await _fresh()
	var session = await _make_session("fixed-parking", {"vertical_slice": true})
	_check(session != null, "Existing line travel A→B→C remains available")
	if session != null:
		var before = session.to_dict()
		var denied = session.request_reposition("relay")
		_check(not denied.ok, "In-field reposition rejected")
		_check(session.to_dict() == before, "Rejected relocation does not mutate session")
		_check(session.parking_anchor() == RouteSession.BASE, "Entrance anchor fixed")
		_check(session.request_intermediate_clearance().ok, "Road maintenance remains available")
		var legacy_clearing: Dictionary = session.to_dict()
		legacy_clearing.schema = 7
		legacy_clearing.erase("rescue")
		legacy_clearing.erase("mine_path_engineering")
		var legacy_clearing_loaded := RouteSession.from_dict(legacy_clearing)
		_check(legacy_clearing_loaded.ok and str(legacy_clearing_loaded.session.intermediate_access) == "clearing", "Schema-7 vertical clearing snapshot remains loadable")
		_check(_advance_until(session, func(): return session.intermediate_access == "cleared", 180), "Individual moves and clears obstruction")
		var legacy_cleared: Dictionary = session.to_dict()
		legacy_cleared.schema = 7
		legacy_cleared.erase("rescue")
		legacy_cleared.erase("mine_path_engineering")
		var legacy_cleared_loaded := RouteSession.from_dict(legacy_cleared)
		_check(legacy_cleared_loaded.ok and str(legacy_cleared_loaded.session.intermediate_access) == "cleared", "Schema-7 vertical cleared snapshot remains loadable")
		_check(not session.request_reposition("relay").ok, "Even cleared road does not unlock parking")
		_check(_advance_until(session, func():
			for actor in session.actors.values():
				if int(actor.get("carry_n", 0)) > 0:
					return true
			return false, 120), "Migration fixture has actual in-flight recovered cargo")
		for old_phase in ["local", "reposition_recall", "reposition_travel", "recall"]:
			var legacy = session.to_dict()
			legacy.parking_slot = "relay"
			legacy.phase = old_phase
			legacy.reposition_target_slot = "entry" if old_phase.begins_with("reposition") else ""
			legacy.reposition_seconds_left = 1.0
			var loaded = RouteSession.from_dict(legacy)
			_check(loaded.ok, "Legacy snapshot accepted: " + old_phase)
			if loaded.ok:
				var restored = loaded.session
				_check(restored.parking_slot == "entry" and restored.reposition_target_slot == "" and restored.reposition_seconds_left == 0, "Legacy parking normalized: " + old_phase)
				_check(restored.phase == ("local" if old_phase.begins_with("reposition") else old_phase), "Preserve recall; cancel obsolete relocation")
				_check(restored.resources == session.resources and restored.depot_stock == session.depot_stock and restored.relay_stock == session.relay_stock and restored.conservation_ok(), "No resource loss/creation on migration")
				for actor_id in session.actors:
					_check(restored.actors[actor_id].x == session.actors[actor_id].x and restored.actors[actor_id].y == session.actors[actor_id].y and restored.actors[actor_id].carry_n == session.actors[actor_id].carry_n, "No actor teleport or cargo loss")
				restored.request_recall()
				_check(_advance_until(restored, func(): return restored.phase == "ready_to_exit", 300), "Migrated session recalls successfully")
				_check(restored.conservation_ok(), "Migrated recall conserves all resources")
		# Legacy dock-in-progress: requeue the same cargo physically, never credit it twice.
		var docking = session.to_dict()
		docking.parking_slot = "relay"
		for actor_id in docking.actors:
			if int(docking.actors[actor_id].get("carry_n", 0)) > 0:
				docking.actors[actor_id].state = "dock_wait"
				docking.dock_busy = {actor_id: 0.1}
				break
		var dock_loaded = RouteSession.from_dict(docking)
		_check(dock_loaded.ok, "Legacy busy dock accepted")
		if dock_loaded.ok:
			var ds = dock_loaded.session
			_check(ds.dock_busy.is_empty() and ds.dock_queue.is_empty() and ds.depot_stock == session.depot_stock, "Dock migration does not prematurely credit cargo")
			ds.request_recall()
			_check(_advance_until(ds, func(): return ds.phase == "ready_to_exit", 300) and ds.conservation_ok(), "Legacy dock cargo reaches fixed entrance exactly once")
	_free_main()
	print("FIXED PARKING failures=", fails)
	quit(1 if fails else 0)
func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _free_main() -> void:
	if main != null and is_instance_valid(main):
		root.remove_child(main)
		main.free()
	main = null

func _fresh() -> void:
	_free_main()
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
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

func _step_world() -> void:
	main._process(STEP)
	await process_frame

func _move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 240:
		await _step_world()
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return main.world.phase == "stopped" and main.world.region == destination

func _move_to_quarry() -> bool:
	if main.world.region == "a_start" and not await _move_leg("b_forest"):
		return false
	if main.world.region == "b_forest":
		return await _move_leg("c_quarry")
	return main.world.region == "c_quarry" and main.world.phase == "stopped"

func _make_session(tag: String, options: Dictionary):
	if not await _move_to_quarry():
		_check(false, tag + ": A→B→Cの既存横移動")
		return null
	var created: Dictionary = RouteSession.create_from_game(main, tag, options)
	_check(bool(created.get("ok", false)), tag + ": C有限資源と既存仲間からsessionを作成")
	return created.get("session", null)

func _advance_until(session, predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		session.tick(STEP)
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return false
		if predicate.call():
			return true
	return predicate.call()

func _has_state(session, wanted: String) -> bool:
	for actor_id in session.actors:
		if str(session.actors[actor_id].get("state", "")) == wanted:
			return true
	return false

