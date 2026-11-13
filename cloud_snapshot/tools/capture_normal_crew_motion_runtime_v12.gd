extends SceneTree
## Direct normal-role runtime observation. The X11 video is a 10fps observer;
## the field itself runs through Godot's inherited _process(delta) loop.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const ROOT_BASE_URI := "res://prototypes/recovery_map_lab/evidence/normal_crew_motion_runtime_v12"
const RESULT_BASE_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime"
const OBSERVATION_FPS := 10
const VIDEO_CAPTURE_FPS := 10
const VIDEO_DURATION_MSEC := 12000
const VIDEO_FINISH_GRACE_MSEC := 4000

var tag := ""
var main
var field
var samples: Array[Dictionary] = []
var screenshots := {}
var entry := {}
var initial_depot := 0
var start_msec := 0
var next_sample_msec := 0.0
var initial_process_frames := 0
var max_foot_error := 0.0
var scale_values := {}
var saw_v3 := false
var video_pid := -1
var video_uri := ""
var failure := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	tag = OS.get_environment("NORMAL_CREW_CAPTURE_TAG").strip_edges()
	if tag not in ["before", "after"]:
		_finish_failure("NORMAL_CREW_CAPTURE_TAG must be before or after")
		return
	SaveGame.disabled = true
	if DisplayServer.get_name() != "X11":
		_finish_failure("normal runtime evidence requires X11")
		return
	if not await _prepare_field():
		return
	if not _prepare_output() or not _start_x11_video_capture():
		_finish_failure("ffmpeg output setup")
		return
	# The capture begins only after the fully rendered normal field is resumed.
	# No field._process call or session.tick call appears below this line.
	# V12_RUNTIME_RECORDING_NO_MANUAL_TICK_BEGIN
	field.process_mode = Node.PROCESS_MODE_INHERIT
	start_msec = Time.get_ticks_msec()
	next_sample_msec = float(start_msec)
	initial_process_frames = Engine.get_process_frames()
	while Time.get_ticks_msec() - start_msec < VIDEO_DURATION_MSEC:
		await RenderingServer.frame_post_draw
		var now_msec := Time.get_ticks_msec()
		if float(now_msec) + 0.001 < next_sample_msec:
			continue
		# Missed observation deadlines are skipped, never backfilled with a
		# duplicated frame. The video is also direct X11 input only.
		next_sample_msec += 1000.0 / float(OBSERVATION_FPS)
		if next_sample_msec <= float(now_msec):
			next_sample_msec = float(now_msec) + 1000.0 / float(OBSERVATION_FPS)
		if not _sample_post_draw(now_msec):
			return
	field.process_mode = Node.PROCESS_MODE_DISABLED
	if not await _finish_video():
		return
	var result := _result()
	if not _write_result(result):
		_finish_failure("result write")
		return
	print("NORMAL_CREW_MOTION_RUNTIME_CAPTURE_COMPLETE ", _result_uri())
	_cleanup()
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
		_finish_failure("A to C route setup")
		return false
	var created: Dictionary = RouteSession.create_from_game(main, "normal-crew-motion-runtime-v12-%s" % tag, {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		_finish_failure(str(created.get("reason", "normal session setup")))
		return false
	main.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	field = FieldAdapter.new()
	field.configure(main, created.session)
	field.process_mode = Node.PROCESS_MODE_DISABLED
	layer.add_child(field)
	await process_frame
	await RenderingServer.frame_post_draw
	if field.session.is_single_worker_demo() or str(field.session.actors.get("worker:0", {}).get("role", "")) != "harvest":
		_finish_failure("normal role precondition")
		return false
	# This is an ordinary user-visible route control state. It reveals normal
	# bridge movement without borrowing the single-demo screen projection.
	field.session.set_gate_closed(true)
	entry = {
		"seed": int(main.get_meta("diagnostic_seed", -1)),
		"outpost_enabled": bool(field.session.outpost_enabled),
		"gate_closed": bool(field.session.gate_closed),
		"dock_count": int(field.session.dock_count),
		"resources": _resource_snapshot(field.session),
		"roles": _role_snapshot(field.session),
	}
	initial_depot = int(field.session.state_summary().get("depot", 0))
	return true

func _move(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 300:
		main._process(0.2)
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
		if unused % 24 == 0:
			await process_frame
	return false

func _sample_post_draw(now_msec: int) -> bool:
	var actor: Dictionary = field.session.actors.get("worker:0", {})
	var crew_views = field.canyon_hub.get_node_or_null("CanyonCrewViews")
	if crew_views == null or not crew_views.has_method("debug_snapshot"):
		_finish_failure("crew presentation unavailable")
		return false
	var raw: Dictionary = crew_views.call("debug_snapshot", "worker:0")
	var expected_foot: Vector2 = field.canyon_hub.map_point(Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0))))
	var foot: Vector2 = raw.get("foot_point", expected_foot)
	var scale: Vector2 = raw.get("sprite_scale", Vector2.ONE)
	var key := str(raw.get("sprite_key", "idle"))
	var visual_kind := str(raw.get("visual_kind", key))
	var frame_name := str(raw.get("frame_name", "v2_%s_0" % key))
	var motion_asset := str(raw.get("motion_asset", "v2_static"))
	var presentation := {
		"visual_kind": visual_kind,
		"motion_asset": motion_asset,
		"frame_index": int(raw.get("frame_index", 0)),
		"frame_name": frame_name,
		"direction": str(raw.get("direction", "")),
		"foot_point": _vector_array(foot),
		"foot_anchor": _vector_array(raw.get("foot_anchor", Vector2.ZERO)),
		"foot_error": snappedf(foot.distance_to(expected_foot), 0.001),
		"scale": _vector_array(scale),
		"cargo_visible": bool(raw.get("cargo_visible", int(actor.get("carry_n", 0)) > 0)),
		"texture_path": str(raw.get("texture_path", "")),
	}
	max_foot_error = maxf(max_foot_error, float(presentation.foot_error))
	scale_values["%.3f,%.3f" % [scale.x, scale.y]] = true
	saw_v3 = saw_v3 or motion_asset == "v3"
	var summary: Dictionary = field.session.state_summary()
	var sample := {
		"wall_msec": now_msec - start_msec,
		"session_elapsed": snappedf(float(field.session.elapsed), 0.001),
		"engine_fps": snappedf(float(Engine.get_frames_per_second()), 0.01),
		"engine_process_frames": int(Engine.get_process_frames()),
		"actor": _actor_summary(actor),
		"presentation": presentation,
		"summary": {
			"source_remaining": int(summary.get("source_remaining", 0)),
			"relay": int(summary.get("relay", 0)),
			"carried": int(summary.get("carried", 0)),
			"depot": int(summary.get("depot", 0)),
			"dock_queue": int(summary.get("dock_queue", 0)),
			"conservation_ok": bool(summary.get("conservation_ok", false)),
		},
	}
	samples.append(sample)
	if visual_kind == "walk" and not screenshots.has("walk") and not _save_viewport("walk"):
		_finish_failure("walk screenshot")
		return false
	if visual_kind == "harvest" and not screenshots.has("harvest") and not _save_viewport("harvest"):
		_finish_failure("harvest screenshot")
		return false
	if int(actor.get("carry_n", 0)) > 0 and not screenshots.has("carry") and not _save_viewport("carry"):
		_finish_failure("carry screenshot")
		return false
	if int(summary.get("depot", 0)) > initial_depot and not screenshots.has("depot") and not _save_viewport("depot"):
		_finish_failure("depot screenshot")
		return false
	return true

func _save_viewport(key: String) -> bool:
	var uri := _root_uri().path_join("normal_crew_motion_%s_%s.png" % [tag, key])
	var path := ProjectSettings.globalize_path(uri)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var image: Image = root.get_texture().get_image()
	if image == null or image.get_width() != 1280 or image.get_height() != 720:
		return false
	if image.save_png(path) != OK:
		return false
	screenshots[key] = uri
	return true

func _prepare_output() -> bool:
	var root_path := ProjectSettings.globalize_path(_root_uri())
	if DirAccess.make_dir_recursive_absolute(root_path) != OK:
		return false
	video_uri = _root_uri().path_join("normal_crew_motion_%s.mp4" % tag)
	return not FileAccess.file_exists(ProjectSettings.globalize_path(video_uri))

func _start_x11_video_capture() -> bool:
	var display := OS.get_environment("DISPLAY")
	if display.is_empty():
		return false
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-n",
		"-f", "x11grab", "-framerate", str(VIDEO_CAPTURE_FPS),
		"-video_size", "1280x720", "-draw_mouse", "0", "-i", display + "+0,0",
		"-t", "%.3f" % (float(VIDEO_DURATION_MSEC) / 1000.0),
		"-an", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18",
		"-pix_fmt", "yuv420p", "-movflags", "+faststart",
		ProjectSettings.globalize_path(video_uri),
	])
	video_pid = OS.create_process("ffmpeg", args)
	return video_pid > 0

func _finish_video() -> bool:
	var deadline := Time.get_ticks_msec() + VIDEO_FINISH_GRACE_MSEC
	while video_pid > 0 and OS.is_process_running(video_pid) and Time.get_ticks_msec() < deadline:
		await process_frame
	if video_pid > 0 and OS.is_process_running(video_pid):
		_finish_failure("ffmpeg did not finish")
		return false
	var file := FileAccess.open(ProjectSettings.globalize_path(video_uri), FileAccess.READ)
	if file == null:
		_finish_failure("ffmpeg output missing")
		return false
	var bytes := file.get_length()
	file.close()
	if bytes < 1024:
		_finish_failure("ffmpeg output empty")
		return false
	return true

func _result() -> Dictionary:
	var first: Dictionary = samples.front() if not samples.is_empty() else {}
	var last: Dictionary = samples.back() if not samples.is_empty() else {}
	return {
		"schema": 1,
		"tag": tag,
		"display_server": DisplayServer.get_name(),
		"mode": "normal_roles",
		"single_worker_demo": false,
		"normal_user_save_touched": false,
		"runtime_driver": "inherited_adapter_process",
		"manual_adapter_ticks": 0,
		"observation_fps": OBSERVATION_FPS,
		"video_capture_fps": VIDEO_CAPTURE_FPS,
		"capture_method": "direct X11 1280x720 video at 10fps plus Godot post-draw observation; no interpolation, copied frames, or manual adapter ticks",
		"presentation_revision": "v12_harvest_v3" if saw_v3 else "v2_static",
		"entry": entry,
		"video": video_uri,
		"screenshots": screenshots,
		"samples": samples,
		"timing": {
			"wall_elapsed_seconds": snappedf(float(last.get("wall_msec", 0)) / 1000.0, 0.001),
			"session_elapsed_span": snappedf(float(last.get("session_elapsed", 0.0)) - float(first.get("session_elapsed", 0.0)), 0.001),
			"engine_process_frame_span": int(last.get("engine_process_frames", initial_process_frames)) - initial_process_frames,
			"max_foot_error": max_foot_error,
			"scale_variant_count": scale_values.size(),
		},
	}

func _resource_snapshot(session) -> Dictionary:
	var result := {}
	for raw_id in session.resources:
		var id := str(raw_id)
		var row: Dictionary = session.resources[raw_id]
		result[id] = {"item": int(row.get("item", -1)), "initial": int(row.get("initial", 0)), "remaining": int(row.get("remaining", 0))}
	return result

func _role_snapshot(session) -> Dictionary:
	var result := {}
	for raw_id in session.actors:
		var id := str(raw_id)
		var actor: Dictionary = session.actors[raw_id]
		result[id] = {"role": str(actor.get("role", "")), "carry_limit": int(actor.get("carry_limit", 0)), "support": int(actor.get("work_support", -1))}
	return result

func _actor_summary(actor: Dictionary) -> Dictionary:
	return {
		"state": str(actor.get("state", "")),
		"route": str(actor.get("route", "")),
		"carry_n": int(actor.get("carry_n", 0)),
		"carry_item": int(actor.get("carry_item", -1)),
		"x": snappedf(float(actor.get("x", 0.0)), 0.001),
		"y": snappedf(float(actor.get("y", 0.0)), 0.001),
	}

func _vector_array(value: Variant) -> Array:
	var vector: Vector2 = value as Vector2 if value is Vector2 else Vector2.ZERO
	return [snappedf(vector.x, 0.001), snappedf(vector.y, 0.001)]

func _root_uri() -> String:
	return ROOT_BASE_URI.path_join(tag)

func _result_uri() -> String:
	return RESULT_BASE_URI.path_join("normal_crew_motion_runtime_v12_%s.json" % tag)

func _write_result(result: Dictionary) -> bool:
	var path := ProjectSettings.globalize_path(_result_uri())
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
	_write_result({"schema": 1, "tag": tag, "display_server": DisplayServer.get_name(), "mode": "normal_roles", "failure": failure, "samples": samples, "normal_user_save_touched": false})
	if video_pid > 0 and OS.is_process_running(video_pid):
		OS.kill(video_pid)
	_cleanup()
	print("NORMAL_CREW_MOTION_RUNTIME_CAPTURE_FAILED ", reason)
	quit(1)

func _cleanup() -> void:
	if field != null and is_instance_valid(field):
		field.queue_free()
	if main != null and is_instance_valid(main):
		main.queue_free()
