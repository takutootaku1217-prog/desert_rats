extends SceneTree
## Direct viewport evidence for the isolated sideview proof. It never loads Main.

const PROOF_SCENE = preload("res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.tscn")
## v1 output remains immutable. This current recorder targets a fresh v2
## identity after the roof-gun origins were snapped to integer pixels.
const EVIDENCE_ROOT := "res://prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_v2"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/sideview_mobile_base_motion_v2.json"
const IDLE_URI := EVIDENCE_ROOT + "/sideview_mobile_base_parked.png"
const ROLL_URI := EVIDENCE_ROOT + "/sideview_mobile_base_rolling.png"
const STOP_URI := EVIDENCE_ROOT + "/sideview_mobile_base_stopped.png"
const VIDEO_URI := EVIDENCE_ROOT + "/sideview_mobile_base_motion_v2.mp4"
const OBSERVATION_FPS := 10
const VIDEO_SECONDS := 7.0
const VIDEO_GRACE_MSEC := 4000

var proof: Node2D
var snapshots: Array[Dictionary] = []
var screenshots := {}
var video_pid := -1
var video_started_msec := 0
var failure := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "X11":
		_finish_failure("requires non-headless X11 viewport")
		return
	if not _prepare_output():
		_finish_failure("refusing to overwrite proof evidence")
		return
	proof = PROOF_SCENE.instantiate() as Node2D
	if proof == null or not proof.has_method("debug_snapshot"):
		_finish_failure("isolated proof scene unavailable")
		return
	root.add_child(proof)
	await RenderingServer.frame_post_draw
	if not _save_viewport(IDLE_URI, "parked"):
		_finish_failure("parked viewport capture")
		return
	if not _start_video():
		_finish_failure("direct ffmpeg x11grab start")
		return
	var next_sample_msec := float(Time.get_ticks_msec())
	var captured_roll := false
	var captured_stop := false
	while float(Time.get_ticks_msec() - video_started_msec) < VIDEO_SECONDS * 1000.0:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_msec()
		if float(now) >= next_sample_msec:
			next_sample_msec += 1000.0 / float(OBSERVATION_FPS)
			if next_sample_msec <= float(now):
				next_sample_msec = float(now) + 1000.0 / float(OBSERVATION_FPS)
			_record_snapshot(now)
		var state: Dictionary = proof.call("debug_snapshot")
		var elapsed := float(state.get("elapsed_seconds", 0.0))
		if not captured_roll and elapsed >= 2.0:
			if not _save_viewport(ROLL_URI, "rolling"):
				_finish_failure("rolling viewport capture")
				return
			captured_roll = true
		if not captured_stop and elapsed >= 5.0:
			if not _save_viewport(STOP_URI, "stopped"):
				_finish_failure("stopped viewport capture")
				return
			captured_stop = true
	if not captured_roll or not captured_stop:
		_finish_failure("proof phases were not visibly captured")
		return
	if not await _finish_video():
		return
	var video_probe := _probe_video()
	if not bool(video_probe.get("ok", false)):
		_finish_failure("video probe: %s" % ",".join(PackedStringArray(video_probe.get("errors", []))))
		return
	var result := {
		"schema": 1,
		"capture_identity": "sideview_mobile_base_motion_v2",
		"display_server": DisplayServer.get_name(),
		"runtime_os": OS.get_name(),
		"engine_version": str(Engine.get_version_info().get("string", "unknown")),
		"validation_scope": "Linux/X11 evidence only; Windows/Godot 4.7.2, real input, audio, and performance remain unverified",
		"mode": "isolated_sideview_motion_proof",
		"normal_user_save_touched": false,
		"gameplay_state_constructed": false,
		"view_coverage": "single verified sideview only; no right/front/rear/quarter direction claim",
		"capture_method": "unmodified Godot X11 viewport PNGs plus direct ffmpeg x11grab at %d fps; no AI frames, interpolation, crop, scale, or speed change" % OBSERVATION_FPS,
		"capture_fps": OBSERVATION_FPS,
		"runtime_fps_note": "capture_fps is observation rate, not renderer fps; sampled Engine FPS is stored independently",
		"movement_expression": "body stays framed; road scroll, wheel angle, rolling dust, and sprung-body offset share model distance/time",
		"component_contract": "body/wheel/shutter/crane/gun/flag use existing fortress_moving sideview parts; shutter/crane/guns remain static whole parts",
		"effects": "flag strips, procedural exhaust, procedural rolling dust, and low-alpha lamp overlay are runtime effects, not new asset claims",
		"screenshots": screenshots,
		"samples": snapshots,
		"video": VIDEO_URI,
		"video_probe": video_probe,
	}
	if not _write_result(result):
		_finish_failure("result write")
		return
	print("MOBILE_BASE_MOTION_PROOF_CAPTURE_COMPLETE ", RESULT_URI)
	_cleanup()
	quit()


func _prepare_output() -> bool:
	var evidence_path := ProjectSettings.globalize_path(EVIDENCE_ROOT)
	if DirAccess.make_dir_recursive_absolute(evidence_path) != OK:
		return false
	for uri in [IDLE_URI, ROLL_URI, STOP_URI, VIDEO_URI, RESULT_URI]:
		if FileAccess.file_exists(ProjectSettings.globalize_path(uri)):
			return false
	return true


func _start_video() -> bool:
	var display := OS.get_environment("DISPLAY")
	if display.is_empty():
		return false
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-n",
		"-f", "x11grab", "-framerate", str(OBSERVATION_FPS),
		"-video_size", "1280x720", "-draw_mouse", "0", "-i", display + "+0,0",
		"-t", "%.3f" % VIDEO_SECONDS,
		"-an", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18",
		"-pix_fmt", "yuv420p", "-movflags", "+faststart",
		ProjectSettings.globalize_path(VIDEO_URI),
	])
	video_pid = OS.create_process("ffmpeg", args)
	if video_pid <= 0:
		return false
	video_started_msec = Time.get_ticks_msec()
	return true


func _record_snapshot(now_msec: int) -> void:
	var state: Dictionary = proof.call("debug_snapshot")
	state["wall_elapsed_msec"] = now_msec - video_started_msec
	state["engine_fps"] = snappedf(Engine.get_frames_per_second(), 0.01)
	snapshots.append(state)


func _save_viewport(uri: String, label: String) -> bool:
	var image: Image = root.get_texture().get_image()
	if not _has_proof_signature(image):
		screenshots[uri] = {"label": label, "error": "proof render signature missing"}
		return false
	var error := image.save_png(ProjectSettings.globalize_path(uri))
	screenshots[uri] = {
		"label": label,
		"error": error,
		"width": image.get_width(),
		"height": image.get_height(),
		"snapshot": proof.call("debug_snapshot"),
	}
	return error == OK


func _has_proof_signature(image: Image) -> bool:
	if image == null or image.get_width() != 1280 or image.get_height() != 720:
		return false
	var distinct := {}
	for point in [Vector2i(20, 20), Vector2i(260, 260), Vector2i(638, 460), Vector2i(1020, 520), Vector2i(600, 620), Vector2i(1180, 685)]:
		distinct[image.get_pixelv(point).to_rgba32()] = true
	return distinct.size() >= 5


func _finish_video() -> bool:
	var deadline := Time.get_ticks_msec() + VIDEO_GRACE_MSEC
	while OS.is_process_running(video_pid) and Time.get_ticks_msec() < deadline:
		await process_frame
	if OS.is_process_running(video_pid):
		_finish_failure("ffmpeg x11grab timeout")
		return false
	var video_path := ProjectSettings.globalize_path(VIDEO_URI)
	var file := FileAccess.open(video_path, FileAccess.READ)
	if file == null:
		_finish_failure("ffmpeg output missing")
		return false
	var length := file.get_length()
	file.close()
	if length < 1024:
		_finish_failure("ffmpeg output empty")
		return false
	return true


func _probe_video() -> Dictionary:
	var output: Array = []
	var args := PackedStringArray([
		"-v", "error", "-count_frames",
		"-show_entries", "stream=codec_type,codec_name,width,height,avg_frame_rate,nb_read_frames:format=duration,size",
		"-of", "json", ProjectSettings.globalize_path(VIDEO_URI),
	])
	var exit_code := OS.execute("ffprobe", args, output, true)
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var parsed = JSON.parse_string(raw)
	var errors := PackedStringArray()
	if exit_code != 0 or not (parsed is Dictionary):
		errors.append("ffprobe")
		return {"ok": false, "errors": errors, "raw": raw}
	var streams: Array = (parsed as Dictionary).get("streams", [])
	var stream: Dictionary = streams[0] if not streams.is_empty() and streams[0] is Dictionary else {}
	var frame_count := int(stream.get("nb_read_frames", "0"))
	var dimensions_ok := int(stream.get("width", 0)) == 1280 and int(stream.get("height", 0)) == 720
	var rate_ok := str(stream.get("avg_frame_rate", "")) == "%d/1" % OBSERVATION_FPS
	if not dimensions_ok:
		errors.append("dimensions")
	if not rate_ok:
		errors.append("rate")
	if frame_count < int(VIDEO_SECONDS * float(OBSERVATION_FPS)):
		errors.append("frame-count")
	return {"ok": errors.is_empty(), "errors": errors, "ffprobe_exit_code": exit_code, "ffprobe": parsed, "decoded_frame_count": frame_count}


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
	_write_result({"display_server": DisplayServer.get_name(), "failure": failure, "screenshots": screenshots, "samples": snapshots, "normal_user_save_touched": false, "gameplay_state_constructed": false})
	if video_pid > 0 and OS.is_process_running(video_pid):
		OS.kill(video_pid)
	_cleanup()
	print("MOBILE_BASE_MOTION_PROOF_CAPTURE_FAILED ", reason)
	quit(1)


func _cleanup() -> void:
	if proof != null and is_instance_valid(proof):
		proof.queue_free()
