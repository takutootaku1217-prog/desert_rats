extends SceneTree
## Direct continuous X11 viewport evidence for one opt-in single-worker loop.
## ffmpeg records the ready 1280×720 X11 viewport directly at TARGET_HZ while
## Godot records same-session post-draw metadata.  Neither path synthesizes,
## duplicates, crops, scales, or interpolates a frame.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")
const CaptureContract = preload("res://tools/canyon_continuous_capture_contract.gd")

const ROOT_URI := "res://prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v10"
const VIDEO_URI := "res://prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v10/canyon_single_worker_continuous_v10.mp4"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/canyon_single_worker_continuous_v10.json"
const TARGET_HZ := 10.0
const TARGET_CYCLES := 3
const MIN_CAPTURE_SECONDS := 8.0
const POST_DEPARTURE_SAMPLES := 3
const CAPTURE_TIMEOUT_MSEC := 90000
const VIDEO_DURATION_MSEC := 36000
const VIDEO_SAFE_MARGIN_MSEC := 1000
const VIDEO_FINISH_GRACE_MSEC := 4000
# At 10 Hz this holds at most two initial encoded frames.  The decoded digest
# contract still rejects three identical frames, so a stalled field cannot be
# hidden behind this capture-only dock pre-roll.
const PRE_ROLL_MSEC := 180

var main
var field
var tracked_id := ""
var samples: Array[Dictionary] = []
var cycle_log: Array[Dictionary] = []
var initial_depot := 0
var last_depot := 0
var capture_started_msec := 0
var next_capture_msec := 0.0
var post_departure_frames := 0
var video_pid := -1
var video_started_msec := 0
var pre_roll_duration_msec := 0
var pre_roll_session_unchanged := false
var failure := ""
var frame_digest_validation: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	SaveGame.disabled = true
	# Reject this before scene setup: headless cannot produce viewport evidence
	# and should not spend time traversing the horizontal map first.
	var contract = CaptureContract.new()
	if not bool(contract.validate_preconditions(DisplayServer.get_name(), true, true).get("ok", false)):
		_finish_failure("preconditions:headless")
		return
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
		return
	var created: Dictionary = RouteSession.create_from_game(main, "canyon-single-worker-continuous", {"outpost_enabled": false, "single_worker_demo": true})
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
	# The direct field must render its dock state before it receives its first
	# adapter process callback.  This pauses only the display adapter; the
	# session stays read-only to the recorder until it is resumed below.
	field.process_mode = Node.PROCESS_MODE_DISABLED
	layer.add_child(field)
	await process_frame
	await RenderingServer.frame_post_draw
	tracked_id = str(field.session.tracked_worker_id())
	var single_demo_ready: bool = field.detail_label != null and field.detail_label.text.contains("単独追跡") and bool(field.session.call("is_single_worker_demo")) and bool(field.session.gate_closed) and tracked_id == "worker:0"
	var preconditions: Dictionary = contract.validate_preconditions(DisplayServer.get_name(), _prepare_video_output(), single_demo_ready)
	if not bool(preconditions.get("ok", false)):
		_finish_failure("preconditions:%s" % ",".join(PackedStringArray(preconditions.get("errors", []))))
		return
	# The demo already fixes the bridge route. Observe that authority without
	# calling a session setter or changing the live route for the recording.
	initial_depot = int(field.session.state_summary().get("depot", 0))
	last_depot = initial_depot
	if not _start_x11_video_capture():
		_finish_failure("ffmpeg-x11-start")
		return
	if not await _hold_capture_pre_roll():
		return
	field.process_mode = Node.PROCESS_MODE_INHERIT
	capture_started_msec = video_started_msec
	next_capture_msec = float(Time.get_ticks_msec())
	while Time.get_ticks_msec() - capture_started_msec < CAPTURE_TIMEOUT_MSEC:
		await RenderingServer.frame_post_draw
		var now_msec := Time.get_ticks_msec()
		if float(now_msec) + 0.001 < next_capture_msec:
			continue
		# Do not backfill missed deadlines with duplicates. The contract rejects
		# a real cadence below 10 Hz rather than fabricating frames for video.
		var scheduled_msec := next_capture_msec
		next_capture_msec += 1000.0 / TARGET_HZ
		if next_capture_msec <= float(now_msec):
			next_capture_msec = float(now_msec) + 1000.0 / TARGET_HZ
		if not _capture_post_draw_sample(now_msec, scheduled_msec):
			return
		if _cycle_complete_and_restarted():
			post_departure_frames += 1
			if post_departure_frames >= POST_DEPARTURE_SAMPLES and _video_finished(now_msec):
				_finish_success(contract)
				return
	_finish_failure("timeout before three continuous loops and restart")

func _move(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 300:
		main._process(0.2)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return false

func _prepare_video_output() -> bool:
	var path := ProjectSettings.globalize_path(ROOT_URI)
	if DirAccess.make_dir_recursive_absolute(path) != OK:
		return false
	# Refuse an existing movie: it could otherwise be mistaken for this trace.
	return not FileAccess.file_exists(ProjectSettings.globalize_path(VIDEO_URI))

func _start_x11_video_capture() -> bool:
	var display := OS.get_environment("DISPLAY")
	if display.is_empty():
		return false
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-y",
		"-f", "x11grab", "-framerate", str(int(TARGET_HZ)),
		"-video_size", "1280x720", "-draw_mouse", "0", "-i", display + "+0,0",
		"-t", "%.3f" % (float(VIDEO_DURATION_MSEC) / 1000.0),
		"-an", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18",
		"-pix_fmt", "yuv420p", "-movflags", "+faststart",
		ProjectSettings.globalize_path(VIDEO_URI),
	])
	video_pid = OS.create_process("ffmpeg", args)
	if video_pid <= 0:
		return false
	video_started_msec = Time.get_ticks_msec()
	return true

func _video_finished(now_msec: int) -> bool:
	if now_msec - video_started_msec < VIDEO_DURATION_MSEC:
		return false
	if OS.is_process_running(video_pid):
		if now_msec - video_started_msec > VIDEO_DURATION_MSEC + VIDEO_FINISH_GRACE_MSEC:
			_finish_failure("ffmpeg-x11-timeout")
		return false
	var file := FileAccess.open(ProjectSettings.globalize_path(VIDEO_URI), FileAccess.READ)
	if file == null:
		_finish_failure("ffmpeg-x11-output")
		return false
	var length := file.get_length()
	file.close()
	if length < 1024:
		_finish_failure("ffmpeg-x11-empty")
		return false
	return true

func _hold_capture_pre_roll() -> bool:
	var before: Dictionary = field.session.to_dict()
	var started_msec := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_msec < PRE_ROLL_MSEC:
		await RenderingServer.frame_post_draw
	pre_roll_duration_msec = Time.get_ticks_msec() - started_msec
	pre_roll_session_unchanged = field.session.to_dict() == before
	if not pre_roll_session_unchanged:
		_finish_failure("pre-roll-session-mutation")
		return false
	return true

func _capture_post_draw_sample(capture_msec: int, scheduled_msec: float) -> bool:
	var actor: Dictionary = field.session.actors.get(tracked_id, {})
	var crew_views = field.canyon_hub.get_node_or_null("CanyonCrewViews")
	if crew_views == null or not crew_views.has_method("debug_snapshot"):
		_finish_failure("tracked crew view")
		return false
	var visual: Dictionary = crew_views.call("debug_snapshot", tracked_id)
	var summary: Dictionary = field.session.state_summary()
	var source := Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0)))
	var foot: Vector2 = visual.get("foot_point", Vector2.INF)
	var expected_foot: Vector2 = field.canyon_hub.presentation_point_for_actor(actor)
	var frame_number := samples.size() + 1
	var prior: Dictionary = samples.back() if not samples.is_empty() else {}
	var prior_source := Vector2(float(prior.get("source_x", source.x)), float(prior.get("source_y", source.y)))
	var prior_foot := Vector2(float(prior.get("foot_x", foot.x)), float(prior.get("foot_y", foot.y)))
	var source_delta := source.distance_to(prior_source) if not prior.is_empty() else 0.0
	var foot_delta := foot.distance_to(prior_foot) if not prior.is_empty() else 0.0
	var speed_ratio := _presentation_speed_ratio(prior_source, source)
	var state := str(actor.get("state", ""))
	var bridge_progress := _bridge_progress(actor)
	var bridge_surface: Dictionary = _bridge_surface(foot)
	var sprite_scale: Vector2 = visual.get("sprite_scale", Vector2.ONE)
	var sample := {
		"frame_number": frame_number,
		"capture_msec": capture_msec,
		"scheduled_msec": snappedf(scheduled_msec, 0.01),
		"video_elapsed_msec": capture_msec - video_started_msec,
		"session_elapsed": field.session.elapsed,
		"actor_id": tracked_id,
		"state": state,
		"direction": str(visual.get("direction", "")),
		"frame_index": int(visual.get("frame_index", -1)),
		"frame": str(visual.get("frame_name", "")),
		"visual_kind": str(visual.get("visual_kind", "")),
		"carried": int(actor.get("carry_n", 0)),
		"source_x": snappedf(source.x, 0.01),
		"source_y": snappedf(source.y, 0.01),
		"foot_x": snappedf(foot.x, 0.01),
		"foot_y": snappedf(foot.y, 0.01),
		"foot_anchor": _vector_array(visual.get("foot_anchor", Vector2.ZERO)),
		"scale": _vector_array(sprite_scale),
		"presentation_error": snappedf(foot.distance_to(expected_foot), 0.001),
		"source_delta": snappedf(source_delta, 0.001),
		"foot_delta": snappedf(foot_delta, 0.001),
		"speed_ratio": snappedf(speed_ratio, 0.001),
		"foot_stationary": state == "harvesting" and str(prior.get("state", "")) == "harvesting" and foot_delta <= 0.01,
		"bridge_progress": snappedf(bridge_progress, 0.001),
		"bridge_region": str(bridge_surface.get("region", "outside")),
		"bridge_path": str(bridge_surface.get("region", "outside")) != "outside",
		"bridge_deck": str(bridge_surface.get("region", "outside")) == "deck",
		"source_remaining": int(summary.get("source_remaining", 0)),
		"depot": int(summary.get("depot", 0)),
		"conservation_ok": bool(summary.get("conservation_ok", false)),
		"status_text": str(field.status_label.text) if field.status_label != null else "",
		"detail_text": str(field.detail_label.text) if field.detail_label != null else "",
	}
	samples.append(sample)
	var depot_now := int(summary.get("depot", 0))
	if depot_now > last_depot:
		if int(actor.get("carry_n", 0)) != 0 or not bool(summary.get("conservation_ok", false)):
			_finish_failure("depot changed before cargo cleared")
			return false
		cycle_log.append({
			"cycle": cycle_log.size() + 1,
			"frame_number": frame_number,
			"video_elapsed_msec": sample.video_elapsed_msec,
			"session_elapsed": field.session.elapsed,
			"actor_id": tracked_id,
			"depot_before": last_depot,
			"depot_after": depot_now,
			"carried": int(actor.get("carry_n", 0)),
			"source_remaining": int(summary.get("source_remaining", 0)),
			"conservation_ok": bool(summary.get("conservation_ok", false)),
			"status_text": sample.status_text,
			"detail_text": sample.detail_text,
		})
		last_depot = depot_now
	return true

func _presentation_speed_ratio(previous_source: Vector2, source: Vector2) -> float:
	if previous_source.distance_to(source) <= 2.0:
		return -1.0
	if _on_source_segment(previous_source, RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.BYPASS) and _on_source_segment(source, RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.BYPASS):
		var path: Array = field.canyon_hub.single_demo_service_path()
		var path_length := 0.0
		for index in range(path.size() - 1):
			path_length += (path[index + 1] as Vector2).distance_to(path[index] as Vector2)
		return path_length / RecoveryRouteConnectionSession.BASE.distance_to(RecoveryRouteConnectionSession.BYPASS)
	if _on_source_segment(previous_source, RecoveryRouteConnectionSession.BYPASS, RecoveryRouteConnectionSession.RESOURCE) and _on_source_segment(source, RecoveryRouteConnectionSession.BYPASS, RecoveryRouteConnectionSession.RESOURCE):
		var bridge_path: Array = field.canyon_hub.single_demo_bridge_path()
		var bridge_path_length := 0.0
		for index in range(bridge_path.size() - 1):
			bridge_path_length += (bridge_path[index + 1] as Vector2).distance_to(bridge_path[index] as Vector2)
		return bridge_path_length / RecoveryRouteConnectionSession.BYPASS.distance_to(RecoveryRouteConnectionSession.RESOURCE)
	return -1.0

func _on_source_segment(point: Vector2, a: Vector2, b: Vector2) -> bool:
	var segment := b - a
	if segment.length_squared() <= 0.001:
		return point.distance_to(a) <= 0.5
	var t := clampf((point - a).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(a + segment * t) <= 0.5

func _bridge_progress(actor: Dictionary) -> float:
	if str(actor.get("route", "")) != "bypass":
		return -1.0
	var source := Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0)))
	return field.canyon_hub.single_demo_bridge_progress_for_source(source) if field.canyon_hub != null and field.canyon_hub.has_method("single_demo_bridge_progress_for_source") else -1.0

func _on_bridge_deck(foot: Vector2) -> bool:
	return str(_bridge_surface(foot).get("region", "outside")) == "deck"

func _on_bridge_path(foot: Vector2) -> bool:
	return str(_bridge_surface(foot).get("region", "outside")) != "outside"

func _bridge_surface(foot: Vector2) -> Dictionary:
	var bridge = field.canyon_hub.get_node_or_null("Bridge")
	if bridge == null or not bridge.has_method("surface_sample"):
		return {"region": "outside"}
	var sample = bridge.call("surface_sample", foot, field.canyon_hub)
	return sample as Dictionary if sample is Dictionary else {"region": "outside"}

func _cycle_complete_and_restarted() -> bool:
	if cycle_log.size() < TARGET_CYCLES or samples.is_empty():
		return false
	var latest: Dictionary = samples.back()
	var elapsed_span := float(latest.get("session_elapsed", 0.0)) - float(samples.front().get("session_elapsed", 0.0))
	return str(latest.get("state", "")) == "to_resource" and int(latest.get("carried", -1)) == 0 and int(latest.get("depot", 0)) > initial_depot and elapsed_span >= MIN_CAPTURE_SECONDS

func _vector_array(value: Variant) -> Array:
	var vector: Vector2 = value as Vector2 if value is Vector2 else Vector2.ZERO
	return [snappedf(vector.x, 0.001), snappedf(vector.y, 0.001)]

func _finish_success(contract) -> void:
	var contract_result: Dictionary = contract.validate(samples, cycle_log, TARGET_HZ, true)
	if not bool(contract_result.get("ok", false)):
		_finish_failure("continuous-contract:%s" % ",".join(PackedStringArray(contract_result.get("errors", []))))
		return
	var video_probe: Dictionary = _probe_video(contract)
	if not bool(video_probe.get("ok", false)):
		_finish_failure("ffprobe:%s" % ",".join(PackedStringArray(video_probe.get("errors", []))))
		return
	frame_digest_validation = _audit_decoded_frames(contract)
	if not bool(frame_digest_validation.get("ok", false)):
		_finish_failure("frame-digests:%s" % ",".join(PackedStringArray(frame_digest_validation.get("errors", []))))
		return
	var actual_video_duration_msec := int(round(float(video_probe.get("duration_seconds", 0.0)) * 1000.0))
	var video_window_result: Dictionary = contract.validate_video_window(samples, cycle_log, actual_video_duration_msec, TARGET_CYCLES, VIDEO_SAFE_MARGIN_MSEC, true)
	if not bool(video_window_result.get("ok", false)):
		_finish_failure("continuous-video-window:%s" % ",".join(PackedStringArray(video_window_result.get("errors", []))))
		return
	var result := {
		"display_server": DisplayServer.get_name(),
		"mode": "single_worker_demo",
		"actor_id": tracked_id,
		"normal_user_save_touched": false,
		"input_evidence": "No OS-level click injection attempted; capture configures the explicit verification mode/session directly.",
		"capture_method": "ffmpeg x11grab records the ready 1280x720 Godot X11 viewport at %.0f fps; Godot logs same-session post-draw state without extra ticks." % TARGET_HZ,
		"target_hz": TARGET_HZ,
		"target_cycles": TARGET_CYCLES,
		"video_safe_margin_msec": VIDEO_SAFE_MARGIN_MSEC,
		"capture_pre_roll_msec": pre_roll_duration_msec,
		"capture_pre_roll_session_unchanged": pre_roll_session_unchanged,
		"bridge_witness_mode": "strict calibrated presentation regions for outbound and loaded return",
		"video": VIDEO_URI,
		"samples": samples,
		"cycle_log": cycle_log,
		"contract": contract_result,
		"video_probe": video_probe,
		"video_window_contract": video_window_result,
		"frame_digest_validation": frame_digest_validation,
		"video_note": "ffmpeg is limited to direct x11grab input, %.0f fps, no audio, and H.264 encoding. No generated, interpolated, duplicated, cropped, or scaled frames are permitted." % TARGET_HZ,
	}
	if not _write_result(result):
		_finish_failure("capture result write")
		return
	print("CANYON_SINGLE_WORKER_CONTINUOUS_CAPTURE_COMPLETE ", RESULT_URI)
	quit()

func _probe_video(contract) -> Dictionary:
	var output: Array = []
	var args := PackedStringArray([
		"-v", "error", "-count_frames",
		"-show_entries", "stream=codec_type,codec_name,width,height,avg_frame_rate,nb_read_frames:format=duration,size",
		"-of", "json", ProjectSettings.globalize_path(VIDEO_URI),
	])
	var exit_code := OS.execute("ffprobe", args, output, true)
	var raw := ""
	for line in output:
		raw += str(line)
	if exit_code != 0:
		return {"ok": false, "errors": ["ffprobe-exit-%d" % exit_code], "ffprobe_output": raw}
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {"ok": false, "errors": ["ffprobe-json"], "ffprobe_output": raw}
	var result: Dictionary = contract.validate_video_probe(parsed as Dictionary, TARGET_HZ, VIDEO_DURATION_MSEC)
	result["ffprobe_exit_code"] = exit_code
	result["ffprobe"] = parsed
	return result

func _audit_decoded_frames(contract) -> Dictionary:
	var output: Array = []
	# Decode the finalized direct recording only; no filters, replacement
	# images, scaling, frame insertion, or time changes are involved.
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-i", ProjectSettings.globalize_path(VIDEO_URI),
		"-map", "0:v:0", "-an", "-f", "framemd5", "-",
	])
	var exit_code := OS.execute("ffmpeg", args, output, true)
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var digests: Array = contract.parse_frame_digest_rows(raw)
	var expected_frames := int(round(TARGET_HZ * float(VIDEO_DURATION_MSEC) / 1000.0))
	var result: Dictionary = contract.validate_frame_digest_sequence(digests, expected_frames)
	result["ffmpeg_exit_code"] = exit_code
	result["frame_digests"] = digests
	if exit_code != 0:
		result["ok"] = false
		result["errors"].append("framemd5-exit-%d" % exit_code)
	return result

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
	_write_result({"display_server": DisplayServer.get_name(), "failure": failure, "samples": samples, "cycle_log": cycle_log, "frame_digest_validation": frame_digest_validation, "video_safe_margin_msec": VIDEO_SAFE_MARGIN_MSEC, "capture_pre_roll_msec": pre_roll_duration_msec, "capture_pre_roll_session_unchanged": pre_roll_session_unchanged, "normal_user_save_touched": false})
	if video_pid > 0 and OS.is_process_running(video_pid):
		OS.kill(video_pid)
	print("CANYON_SINGLE_WORKER_CONTINUOUS_CAPTURE_FAILED ", reason)
	quit(1)
