extends SceneTree
## Direct X11 viewport evidence for the opt-in C-quarry parking vertical slice.
## The field simulation runs through the production adapter's normal _process;
## this script never advances the session directly.  The cloud has no supported
## physical pointer injector, so the wired Button.pressed route is recorded as
## programmatic UI input rather than as a real click claim.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

## v9 preserves v8 as the shared-formation checkpoint and records the
## post-review relay-corridor continuity fix in a fresh X11 run.  The
## closed-gate state is stored directly in every snapshot as well as in its UI
## event so the bypass geometry is not inferred after the fact.
const EVIDENCE_ROOT_URI := "res://prototypes/recovery_map_lab/evidence/canyon_parking_vertical_slice_v9"
const ENTRY_URI := EVIDENCE_ROOT_URI + "/parking_entry_hud.png"
const CLEAR_URI := EVIDENCE_ROOT_URI + "/parking_cleared_hud.png"
const REPOSITION_URI := EVIDENCE_ROOT_URI + "/parking_reposition_hud.png"
const RELAY_URI := EVIDENCE_ROOT_URI + "/parking_relay_hud.png"
const CLOSED_BYPASS_URI := EVIDENCE_ROOT_URI + "/parking_closed_bypass_hud.png"
const FIRST_DELIVERY_URI := EVIDENCE_ROOT_URI + "/parking_first_delivery_hud.png"
const VIDEO_URI := EVIDENCE_ROOT_URI + "/canyon_parking_vertical_slice.mp4"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/canyon_parking_vertical_slice_capture_v9.json"
const VIDEO_FPS := 10
const VIDEO_SECONDS := 64.0
const VIDEO_GRACE_MSEC := 5000
const VIDEO_RATE_TOLERANCE := 0.1

var main
var field
var video_pid := -1
var failure := ""
var snapshots := {}
var events: Array[Dictionary] = []
var video_started_msec := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	SaveGame.disabled = true
	if DisplayServer.get_name() != "X11":
		_finish_failure("X11 viewport unavailable")
		return
	if not _prepare_output():
		_finish_failure("refusing to overwrite vertical-slice evidence")
		return
	if not await _prepare_field():
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(ENTRY_URI, "entry-hud"):
		_finish_failure("entry screenshot")
		return
	if not _start_video():
		_finish_failure("ffmpeg x11grab start")
		return
	if field.maintenance_button == null:
		_finish_failure("maintenance control unavailable")
		return
	field.maintenance_button.emit_signal("pressed")
	_record_event("maintenance_button", {"intermediate_access": field.session.state_summary().get("intermediate_access", "")})
	if not await _wait_until(func(): return str(field.session.state_summary().get("intermediate_access", "")) == "cleared", 25.0):
		_finish_failure("maintenance did not clear")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(CLEAR_URI, "cleared-hud"):
		_finish_failure("cleared screenshot")
		return
	field._update_controls()
	if field.reposition_button == null or field.reposition_button.disabled:
		_finish_failure("reposition control unavailable")
		return
	field.reposition_button.emit_signal("pressed")
	_record_event("reposition_button", {"phase": field.session.phase})
	await RenderingServer.frame_post_draw
	if not _save_viewport(REPOSITION_URI, "reposition-hud"):
		_finish_failure("reposition screenshot")
		return
	if not await _wait_until(func():
		var summary: Dictionary = field.session.state_summary()
		return str(field.session.phase) == "local" and str(summary.get("parking_slot", "")) == "relay",
		35.0):
		_finish_failure("reposition did not reach relay")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(RELAY_URI, "relay-hud"):
		_finish_failure("relay screenshot")
		return
	if field.gate_button == null:
		_finish_failure("gate control unavailable")
		return
	field.gate_button.emit_signal("pressed")
	_record_event("gate_close_button", {"gate_closed": field.session.gate_closed})
	field._update_controls()
	field.canyon_hub.refresh()
	await RenderingServer.frame_post_draw
	if not _save_viewport(CLOSED_BYPASS_URI, "closed-bypass-hud"):
		_finish_failure("closed bypass screenshot")
		return
	field.gate_button.emit_signal("pressed")
	_record_event("gate_reopen_button", {"gate_closed": field.session.gate_closed})
	field._update_controls()
	field.canyon_hub.refresh()
	if not await _wait_until(func(): return int(field.session.state_summary().get("depot", 0)) > 0, 38.0):
		_finish_failure("first delivery did not reach vehicle depot")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(FIRST_DELIVERY_URI, "first-delivery-hud"):
		_finish_failure("first-delivery screenshot")
		return
	_record_event("first_delivery", field.session.state_summary())
	if not await _finish_video():
		return
	var video_probe := _probe_video()
	if not bool(video_probe.get("ok", false)):
		_finish_failure("video probe")
		return
	var result := {
		"schema": 6,
		"display_server": DisplayServer.get_name(),
		"actual_viewport": true,
		"engine_version": str(Engine.get_version_info().get("string", "unknown")),
		"validation_scope": "Linux/X11 evidence only; Windows/Godot 4.7.2, physical input, audio, and performance remain unverified",
		"input_method": "programmatic_button_signal",
		"physical_pointer": false,
		"input_note": "No installed, supported OS-level X11 click injector in this cloud environment; Button.pressed exercises the same production callbacks but is not physical-click evidence.",
		"capture_method": "direct X11 1280x720 viewport PNGs and x11grab MP4 at %d fps; no generated, interpolated, cropped, scaled, or speed-altered frames" % VIDEO_FPS,
		"video": VIDEO_URI,
		"video_probe": video_probe,
		"screenshots": snapshots,
		"events": events,
		"final_session": field.session.state_summary(),
		"conservation_ok": field.session.conservation_ok(),
		"normal_user_save_touched": false,
		"vehicle_art_note": "v15.4 moves the same-facing existing truck layers only after the authoritative parking slot settles. The relay dock is authored right of the bridge foot; worker formations and the selected main/bypass ground path share that dock. Relay route projection chooses the nearest source centreline through overlapping formation corridors, preventing an edge snap. This is a replaceable parked-pose contract, not free driving or finished vehicle animation.",
	}
	if not _write_result(result):
		_finish_failure("result write")
		return
	_cleanup()
	print("CANYON_PARKING_VERTICAL_SLICE_CAPTURE_COMPLETE ", RESULT_URI)
	quit()

func _prepare_field() -> bool:
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
	if not await _move("b_forest") or not await _move("c_quarry"):
		_finish_failure("horizontal route to C")
		return false
	var created: Dictionary = RouteSession.create_from_game(main, "parking-runtime-capture", {"outpost_enabled": false, "vertical_slice": true})
	if not bool(created.get("ok", false)):
		_finish_failure(str(created.get("reason", "vertical session")))
		return false
	main.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	field = FieldAdapter.new()
	field.configure(main, created.session)
	layer.add_child(field)
	await process_frame
	return true

func _move(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 300:
		main._process(0.2)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return false

func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if predicate.call():
			return true
	return predicate.call()

func _record_event(name: String, data: Dictionary) -> void:
	events.append({"name": name, "wall_elapsed_msec": maxi(0, Time.get_ticks_msec() - video_started_msec), "state": data.duplicate(true)})

func _prepare_output() -> bool:
	for uri in [ENTRY_URI, CLEAR_URI, REPOSITION_URI, RELAY_URI, CLOSED_BYPASS_URI, FIRST_DELIVERY_URI, VIDEO_URI, RESULT_URI]:
		if FileAccess.file_exists(ProjectSettings.globalize_path(uri)):
			return false
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE_ROOT_URI)) == OK

func _start_video() -> bool:
	var display := OS.get_environment("DISPLAY")
	if display.is_empty():
		return false
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-n",
		"-f", "x11grab", "-framerate", str(VIDEO_FPS),
		"-video_size", "1280x720", "-draw_mouse", "0", "-i", display + "+0,0",
		"-t", "%.3f" % VIDEO_SECONDS,
		"-an", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
		ProjectSettings.globalize_path(VIDEO_URI),
	])
	video_pid = OS.create_process("ffmpeg", args)
	video_started_msec = Time.get_ticks_msec()
	return video_pid > 0

func _finish_video() -> bool:
	var deadline := Time.get_ticks_msec() + int(VIDEO_SECONDS * 1000.0) + VIDEO_GRACE_MSEC
	while OS.is_process_running(video_pid) and Time.get_ticks_msec() < deadline:
		await process_frame
	if OS.is_process_running(video_pid):
		_finish_failure("ffmpeg x11grab timeout")
		return false
	var path := ProjectSettings.globalize_path(VIDEO_URI)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var length := file.get_length()
	file.close()
	return length > 1024

func _probe_video() -> Dictionary:
	var output: Array = []
	var args := PackedStringArray(["-v", "error", "-count_frames", "-show_entries", "stream=codec_type,width,height,avg_frame_rate,nb_read_frames:format=duration,size", "-of", "json", ProjectSettings.globalize_path(VIDEO_URI)])
	var exit_code := OS.execute("ffprobe", args, output, true)
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var parsed: Variant = JSON.parse_string(raw)
	if exit_code != 0 or not parsed is Dictionary:
		return {"ok": false, "raw": raw}
	var streams: Array = (parsed as Dictionary).get("streams", [])
	var stream: Dictionary = streams[0] if not streams.is_empty() and streams[0] is Dictionary else {}
	var frames := int(stream.get("nb_read_frames", "0"))
	var frame_rate := _fraction_as_float(str(stream.get("avg_frame_rate", "0/1")))
	var format: Dictionary = (parsed as Dictionary).get("format", {})
	var duration := float(format.get("duration", 0.0))
	## x11grab's direct X11 scheduling can report 636–639 frames over this
	## 64.0-second nominal 10fps capture (about 9.9–10.0fps) rather than an
	## impossible exact 10/1.  Keep the tolerance narrow and expose the measured
	## values; no frames are synthesized, dropped deliberately, or retimed.
	var minimum_frame_rate := float(VIDEO_FPS) - VIDEO_RATE_TOLERANCE
	var expected_frame_floor := floori(VIDEO_SECONDS * minimum_frame_rate)
	return {
		"ok": int(stream.get("width", 0)) == 1280 and int(stream.get("height", 0)) == 720 and duration >= VIDEO_SECONDS - 0.1 and duration <= VIDEO_SECONDS + 0.1 and frame_rate >= minimum_frame_rate and frame_rate <= float(VIDEO_FPS) + VIDEO_RATE_TOLERANCE and frames >= expected_frame_floor,
		"decoded_frame_count": frames,
		"decoded_frame_rate": frame_rate,
		"decoded_duration_seconds": duration,
		"ffprobe": parsed,
	}

func _fraction_as_float(value: String) -> float:
	var parts := value.split("/", false, 1)
	if parts.size() != 2:
		return 0.0
	var divisor := float(parts[1])
	return float(parts[0]) / divisor if absf(divisor) > 0.0001 else 0.0

func _save_viewport(uri: String, label: String) -> bool:
	var image: Image = root.get_texture().get_image()
	if image == null or image.get_width() != 1280 or image.get_height() != 720:
		return false
	var error := image.save_png(ProjectSettings.globalize_path(uri))
	var snapshot_state: Dictionary = field.session.state_summary().duplicate(true)
	# state_summary intentionally stays compact for HUD consumers. Evidence adds
	# the selected route bit explicitly so a closed-bypass frame proves both the
	# visible path and the session state that selected it.
	snapshot_state["gate_closed"] = field.session.gate_closed
	snapshot_state["all_routes_closed"] = field.session.all_routes_closed
	snapshots[label] = {"uri": uri, "error": error, "state": snapshot_state, "visual": _visual_state()}
	return error == OK

func _visual_state() -> Dictionary:
	if field == null or field.canyon_hub == null:
		return {}
	var hub = field.canyon_hub
	var rear := hub.get_node_or_null("BaseRear") as Node2D
	var front := hub.get_node_or_null("BaseFront") as Node2D
	var crate := hub.get_node_or_null("Props/DockCrate") as Node2D
	var crew: Node = hub.get_node_or_null("CanyonCrewViews") as Node
	var terrain: Node = hub.get_node_or_null("Terrain") as Node
	var crew_feet := {}
	if crew != null and crew.has_method("debug_snapshot"):
		for raw_actor_id in field.session.actors:
			var snapshot: Dictionary = crew.call("debug_snapshot", str(raw_actor_id))
			var foot: Vector2 = snapshot.get("foot_point", Vector2.ZERO)
			crew_feet[str(raw_actor_id)] = _point_data(foot)
	var contact: Vector2 = hub.active_unload_contact() if hub.has_method("active_unload_contact") else Vector2.ZERO
	var transport_path: Array = terrain.call("active_transport_path", hub) if terrain != null and terrain.has_method("active_transport_path") else []
	var transport_points := []
	for raw_point in transport_path:
		if raw_point is Vector2:
			transport_points.append(_point_data(raw_point as Vector2))
	return {
		"active_unload_contact": _point_data(contact),
		"base_rear_offset": _point_data(rear.position) if rear != null else [],
		"base_front_offset": _point_data(front.position) if front != null else [],
		"dock_crate_offset": _point_data(crate.position) if crate != null else [],
		"crew_feet": crew_feet,
		"active_transport_path": transport_points,
	}

func _point_data(point: Vector2) -> Array:
	return [int(roundf(point.x)), int(roundf(point.y))]

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
	_write_result({"display_server": DisplayServer.get_name(), "actual_viewport": DisplayServer.get_name() == "X11", "failure": failure, "screenshots": snapshots, "events": events, "normal_user_save_touched": false})
	if video_pid > 0 and OS.is_process_running(video_pid):
		OS.kill(video_pid)
	_cleanup()
	print("CANYON_PARKING_VERTICAL_SLICE_CAPTURE_FAILED ", reason)
	quit(1)

func _cleanup() -> void:
	if field != null and is_instance_valid(field):
		field.queue_free()
	if main != null and is_instance_valid(main):
		main.queue_free()
