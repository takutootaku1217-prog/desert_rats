extends SceneTree
## Direct Godot/X11 evidence for the opt-in single-worker verification mode.
## PNG frames are the primary evidence; this script never synthesizes motion.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const ROOT_URI := "res://prototypes/recovery_map_lab/evidence/canyon_single_worker_runtime_v6"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/canyon_single_worker_capture_v6.json"
const HUD_URI := "res://prototypes/recovery_map_lab/evidence/canyon_single_worker_runtime_v6/single_worker_hud_departure.png"
const DEPOT_URI := "res://prototypes/recovery_map_lab/evidence/canyon_single_worker_runtime_v6/single_worker_depot_after_unload.png"
const BRIDGE_URI := "res://prototypes/recovery_map_lab/evidence/canyon_single_worker_runtime_v6/single_worker_bypass_bridge.png"
const TARGET_FRAME_COUNTS := {"walk": 4, "harvest": 3, "carry": 4, "unload": 3}
const FRAME_CYCLE_LENGTHS := {"walk": 4, "harvest": 4, "carry": 4, "unload": 3}
const TARGET_CYCLES := 3
const CAPTURE_TIMEOUT_MSEC := 150000

var main
var field
var screenshots := {}
var captured_frames := {"walk": [], "harvest": [], "carry": [], "unload": []}
var sequence_candidates := {}
var completed_sequences := {}
var state_trace: Array[Dictionary] = []
var cycle_log: Array[Dictionary] = []
var last_signature := ""
var last_sequence_kind := ""
var bridge_snapshot := {}
var failure := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
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
	if DisplayServer.get_name() == "headless":
		_finish_failure("headless does not provide real viewport evidence")
		return
	if not await _move("b_forest") or not await _move("c_quarry"):
		_finish_failure("horizontal route to C")
		return
	var created: Dictionary = RouteSession.create_from_game(main, "canyon-single-worker-render", {"outpost_enabled": false, "single_worker_demo": true})
	if not bool(created.get("ok", false)):
		_finish_failure(str(created.get("reason", "single-worker session")))
		return
	main.visible = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	field = FieldAdapter.new()
	field.configure(main, created.session)
	layer.add_child(field)
	await process_frame
	await RenderingServer.frame_post_draw
	if field.detail_label == null or not field.detail_label.text.contains("単独追跡"):
		_finish_failure("single worker HUD label")
		return
	if not _save_viewport(HUD_URI):
		_finish_failure("single worker HUD screenshot")
		return
	# Deliberately route the actual session across its existing bypass bridge.
	# No button click is claimed here; OS-level input remains separately unverified.
	field.session.set_gate_closed(true)
	var tracked_id := str(field.session.tracked_worker_id())
	var depot_before := int(field.session.state_summary().get("depot", 0))
	var conservation_ok := true
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < CAPTURE_TIMEOUT_MSEC:
		# frame_post_draw is the synchronization point: the actor, presentation
		# snapshot, and texture readback below all describe this same rendered frame.
		await RenderingServer.frame_post_draw
		var actor: Dictionary = field.session.actors.get(tracked_id, {})
		var crew_views = field.canyon_hub.get_node_or_null("CanyonCrewViews")
		if crew_views == null or not crew_views.has_method("debug_snapshot"):
			_finish_failure("tracked crew view")
			return
		var visual: Dictionary = crew_views.call("debug_snapshot", tracked_id)
		_record_state(actor, visual)
		if not _capture_distinct_frame(visual):
			return
		if not _capture_bridge_frame(visual):
			return
		var summary: Dictionary = field.session.state_summary()
		conservation_ok = conservation_ok and bool(summary.get("conservation_ok", false))
		var depot_now := int(summary.get("depot", 0))
		if depot_now > depot_before:
			if int(actor.get("carry_n", 0)) != 0 or not bool(summary.get("conservation_ok", false)):
				_finish_failure("depot changed before session cargo cleared")
				return
			cycle_log.append({
				"cycle": cycle_log.size() + 1,
				"elapsed": field.session.elapsed,
				"actor_id": tracked_id,
				"state": str(actor.get("state", "")),
				"carried": int(actor.get("carry_n", 0)),
				"source_remaining": int(summary.get("source_remaining", 0)),
				"depot_before": depot_before,
				"depot_after": depot_now,
				"conservation_ok": bool(summary.get("conservation_ok", false)),
			})
			depot_before = depot_now
			if not screenshots.has(DEPOT_URI):
				if not _save_viewport(DEPOT_URI):
					_finish_failure("post-unload depot screenshot")
					return
		if _all_frame_targets_captured() and not bridge_snapshot.is_empty() and cycle_log.size() >= TARGET_CYCLES:
			var result := {
				"display_server": DisplayServer.get_name(),
				"mode": "single_worker_demo",
				"actor_id": tracked_id,
				"normal_user_save_touched": false,
				"input_evidence": "No OS-level click injection attempted; capture configures the explicit verification mode/session directly.",
				"screenshots": screenshots,
				"captured_frames": captured_frames,
				"completed_animation_sequences": completed_sequences,
				"bridge_snapshot": bridge_snapshot,
				"state_trace": state_trace,
				"cycle_log": cycle_log,
				"session": summary,
				"trace_conservation_ok": conservation_ok,
				"screenshot_error": 0,
			}
			if not _write_result(result):
				_finish_failure("capture result write")
				return
			print("CANYON_SINGLE_WORKER_CAPTURE_COMPLETE ", DEPOT_URI)
			quit()
			return
	_finish_failure("did not capture coherent worker phases, bridge traversal, and three cycles before timeout")

func _move(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 300:
		main._process(0.2)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return false

func _record_state(actor: Dictionary, visual: Dictionary) -> void:
	var summary: Dictionary = field.session.state_summary()
	var signature := "%s|%s|%d|%d|%s" % [str(actor.get("state", "")), str(visual.get("direction", "")), int(actor.get("carry_n", 0)), int(summary.get("depot", 0)), str(visual.get("frame_name", ""))]
	if signature == last_signature:
		return
	last_signature = signature
	state_trace.append({
		"elapsed": field.session.elapsed,
		"actor_id": str(visual.get("actor_id", "")),
		"state": str(actor.get("state", "")),
		"visual_kind": str(visual.get("visual_kind", "")),
		"direction": str(visual.get("direction", "")),
		"frame_index": int(visual.get("frame_index", -1)),
		"frame": str(visual.get("frame_name", "")),
		"carried": int(actor.get("carry_n", 0)),
		"source_remaining": int(summary.get("source_remaining", 0)),
		"depot": int(summary.get("depot", 0)),
		"conservation_ok": bool(summary.get("conservation_ok", false)),
		"foot_point": [snappedf(float((visual.get("foot_point", Vector2.ZERO) as Vector2).x), 0.01), snappedf(float((visual.get("foot_point", Vector2.ZERO) as Vector2).y), 0.01)],
	})

func _capture_distinct_frame(visual: Dictionary) -> bool:
	var kind := str(visual.get("visual_kind", ""))
	if kind != last_sequence_kind:
		if not last_sequence_kind.is_empty() and not completed_sequences.has(last_sequence_kind):
			sequence_candidates.erase(last_sequence_kind)
		last_sequence_kind = kind
	if not TARGET_FRAME_COUNTS.has(kind):
		return true
	if completed_sequences.has(kind):
		return true
	var frame_name := str(visual.get("frame_name", ""))
	if frame_name.is_empty():
		return true
	var frame_index := int(visual.get("frame_index", -1))
	var direction := str(visual.get("direction", ""))
	var state := str(visual.get("state", ""))
	var candidate: Dictionary = Dictionary(sequence_candidates.get(kind, {})).duplicate(true)
	var steps: Array = Array(candidate.get("steps", [])).duplicate(true)
	var same_track := str(candidate.get("direction", "")) == direction and str(candidate.get("state", "")) == state and not steps.is_empty()
	if same_track and int(steps.back().get("frame_index", -1)) == frame_index:
		return true
	elif same_track and frame_index == (int(steps.back().get("frame_index", -1)) + 1) % int(FRAME_CYCLE_LENGTHS[kind]):
		pass
	else:
		steps = []
	var index: int = captured_frames[kind].size() + 1
	var uri := ROOT_URI.path_join("single_worker_%s_%02d.png" % [kind, index])
	if not _save_viewport(uri):
		_finish_failure("%s frame %d" % [kind, index])
		return false
	var step := {
		"elapsed": field.session.elapsed,
		"state": state,
		"direction": direction,
		"frame_index": frame_index,
		"frame": frame_name,
		"screenshot": uri,
	}
	steps.append(step)
	captured_frames[kind].append(step)
	sequence_candidates[kind] = {"direction": direction, "state": state, "steps": steps}
	if not state_trace.is_empty():
		state_trace.back()["screenshot"] = uri
	if steps.size() >= int(TARGET_FRAME_COUNTS[kind]):
		completed_sequences[kind] = {"direction": direction, "state": state, "steps": steps.slice(steps.size() - int(TARGET_FRAME_COUNTS[kind])).duplicate(true)}
	return true

func _capture_bridge_frame(visual: Dictionary) -> bool:
	if not bridge_snapshot.is_empty():
		return true
	var bridge = field.canyon_hub.get_node_or_null("Bridge")
	var foot: Vector2 = visual.get("foot_point", Vector2.INF)
	if bridge == null or not bridge.has_method("presentation_deck_contains") or not bool(bridge.call("presentation_deck_contains", foot)):
		return true
	if not _save_viewport(BRIDGE_URI):
		_finish_failure("single worker bridge screenshot")
		return false
	bridge_snapshot = {
		"elapsed": field.session.elapsed,
		"state": str(visual.get("state", "")),
		"direction": str(visual.get("direction", "")),
		"frame": str(visual.get("frame_name", "")),
		"presentation_deck": true,
		"foot_point": [snappedf(foot.x, 0.01), snappedf(foot.y, 0.01)],
		"screenshot": BRIDGE_URI,
	}
	return true

func _all_frame_targets_captured() -> bool:
	for kind in TARGET_FRAME_COUNTS:
		if not completed_sequences.has(kind) or Array(completed_sequences[kind].get("steps", [])).size() < int(TARGET_FRAME_COUNTS[kind]):
			return false
	return true

func _save_viewport(uri: String) -> bool:
	var path := ProjectSettings.globalize_path(uri)
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK:
		failure = "directory %s" % directory_error
		return false
	var image: Image = root.get_texture().get_image()
	if not _has_canyon_render_signature(image):
		failure = "render signature missing"
		screenshots[uri] = {"error": failure}
		return false
	var error := image.save_png(path)
	screenshots[uri] = {"error": error, "render_signature": "canyon-single-worker-hud"}
	return error == OK

func _has_canyon_render_signature(image: Image) -> bool:
	if image == null or image.get_width() != 1280 or image.get_height() != 720:
		return false
	var samples := [Vector2i(8, 8), Vector2i(180, 210), Vector2i(250, 300), Vector2i(580, 500), Vector2i(900, 500), Vector2i(1180, 170), Vector2i(1100, 620)]
	var distinct := {}
	for point in samples:
		distinct[image.get_pixel(point.x, point.y).to_rgba32()] = true
	return distinct.size() >= 5 and _contains_cyan_ore(image) and _contains_amber_base(image)

func _contains_cyan_ore(image: Image) -> bool:
	for y in range(110, 410, 12):
		for x in range(60, 470, 12):
			var color := image.get_pixel(x, y)
			if color.a > 0.8 and color.b > color.r * 1.20 and color.g > color.r * 1.08:
				return true
	return false

func _contains_amber_base(image: Image) -> bool:
	for y in range(390, 650, 12):
		for x in range(740, 1180, 12):
			var color := image.get_pixel(x, y)
			if color.a > 0.8 and color.r > 0.62 and color.g > 0.28 and color.g < color.r and color.b < color.g * 0.92:
				return true
	return false

func _write_result(result: Dictionary) -> bool:
	var path := ProjectSettings.globalize_path(RESULT_URI)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	return true

func _finish_failure(reason: String) -> void:
	failure = reason
	_write_result({"display_server": DisplayServer.get_name(), "screenshots": screenshots, "failure": failure, "normal_user_save_touched": false})
	print("CANYON_SINGLE_WORKER_CAPTURE_FAILED ", reason)
	quit(1)
