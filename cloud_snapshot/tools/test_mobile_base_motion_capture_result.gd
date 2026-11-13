extends SceneTree
## Post-capture integrity check. It validates only the isolated proof evidence.

const EVIDENCE_PREFIX := "res://prototypes/recovery_map_lab/evidence/sideview_mobile_base_motion_"
const RESULT_PREFIX := "res://prototypes/recovery_map_lab/results/sideview_mobile_base_motion_"

var failures := 0
var capture_tag := "v1"
var root_uri := ""
var result_uri := ""
var video_uri := ""
var shots: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _run() -> void:
	_configure_paths()
	var result := _read_result()
	_check(not result.is_empty(), "motion proof capture: result JSON exists and parses")
	if result.is_empty():
		_finish()
		return
	_check(str(result.get("display_server", "")) == "X11" and str(result.get("mode", "")) == "isolated_sideview_motion_proof", "motion proof capture: evidence came from the isolated X11 proof")
	if capture_tag == "v2":
		_check(str(result.get("capture_identity", "")) == "sideview_mobile_base_motion_v2" and str(result.get("runtime_os", "")) == "Linux" and str(result.get("engine_version", "")).begins_with("4.6.3") and str(result.get("validation_scope", "")).contains("Windows/Godot 4.7.2"), "motion proof capture: v2 records its actual Linux/Godot runtime and pending Windows validation")
	_check(not bool(result.get("gameplay_state_constructed", true)) and not bool(result.get("normal_user_save_touched", true)), "motion proof capture: no gameplay state or user save was constructed")
	_check(str(result.get("view_coverage", "")).contains("single verified sideview"), "motion proof capture: result does not claim unsupported directions")
	var png_dimensions_ok := true
	for label in shots:
		var path := ProjectSettings.globalize_path(str(shots[label]))
		var image := Image.load_from_file(path)
		png_dimensions_ok = png_dimensions_ok and image != null and image.get_width() == 1280 and image.get_height() == 720
	_check(png_dimensions_ok, "motion proof capture: all three direct Godot PNGs are native 1280x720")
	var screenshot_data: Dictionary = result.get("screenshots", {})
	var parked: Dictionary = (screenshot_data.get(shots["parked"], {}) as Dictionary).get("snapshot", {})
	var rolling: Dictionary = (screenshot_data.get(shots["rolling"], {}) as Dictionary).get("snapshot", {})
	var stopped: Dictionary = (screenshot_data.get(shots["stopped"], {}) as Dictionary).get("snapshot", {})
	_check(str(parked.get("phase", "")) == "parked" and float(parked.get("distance", -1.0)) == 0.0 and str(rolling.get("phase", "")) == "rolling" and float(rolling.get("distance", 0.0)) > 0.0 and str(stopped.get("phase", "")) == "parked" and float(stopped.get("distance", 0.0)) >= 126.0, "motion proof capture: parked → rolling → stopped snapshots retain the same travel contract")
	_check(absf(float(rolling.get("suspension_y", 99.0))) <= 2.0 and float(stopped.get("suspension_y", 99.0)) == 0.0 and float(rolling.get("wheel_angle", 0.0)) != 0.0, "motion proof capture: wheels turn only during traveled distance and the sprung body settles")
	var samples: Array = result.get("samples", [])
	var rolling_samples := 0
	var parked_wheel_static := true
	var road_wheel_coupled := true
	var previous_rolling_distance := -1.0
	var prior_phase := ""
	var prior_parked_angle := 0.0
	var have_parked_angle := false
	for raw_sample in samples:
		if not raw_sample is Dictionary:
			continue
		var sample := raw_sample as Dictionary
		var phase := str(sample.get("phase", ""))
		var distance := float(sample.get("distance", -1.0))
		var wheel_angle := float(sample.get("wheel_angle", -1.0))
		var road_scroll := float(sample.get("road_scroll_x", 9999.0))
		road_wheel_coupled = road_wheel_coupled and absf(road_scroll + distance) <= 0.001 and absf(wheel_angle - fposmod(distance / 56.0, TAU)) <= 0.001
		if phase == "rolling":
			rolling_samples += 1
			if previous_rolling_distance >= 0.0:
				parked_wheel_static = parked_wheel_static and distance >= previous_rolling_distance
			previous_rolling_distance = distance
		elif phase == "parked":
			if prior_phase == "parked" and have_parked_angle:
				parked_wheel_static = parked_wheel_static and absf(wheel_angle - prior_parked_angle) <= 0.001
			parked_wheel_static = parked_wheel_static and float(sample.get("speed_px_per_second", -1.0)) == 0.0 and float(sample.get("suspension_y", 99.0)) == 0.0
			prior_parked_angle = wheel_angle
			have_parked_angle = true
		prior_phase = phase
	_check(rolling_samples >= 20 and parked_wheel_static and road_wheel_coupled, "motion proof capture: every parked span freezes wheel angle, while road scroll and wheel phase remain coupled to travel")
	var video_probe := _probe_video()
	_check(bool(video_probe.get("ok", false)), "motion proof capture: direct MP4 decodes as 1280x720, 10fps, 70 frames")
	_check(_video_depicts_proof(), "motion proof capture: a directly decoded rolling video frame has the proof's title/body/road signature")
	var digest := _decoded_digest_check()
	_check(bool(digest.get("ok", false)), "motion proof capture: all decoded direct-video frames are present and distinct")
	_finish()


func _read_result() -> Dictionary:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(result_uri)):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(result_uri))
	return parsed as Dictionary if parsed is Dictionary else {}


func _probe_video() -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute("ffprobe", PackedStringArray([
		"-v", "error", "-count_frames",
		"-show_entries", "stream=width,height,avg_frame_rate,nb_read_frames",
		"-of", "json", ProjectSettings.globalize_path(video_uri),
	]), output, true)
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var parsed = JSON.parse_string(raw)
	if exit_code != 0 or not (parsed is Dictionary):
		return {"ok": false}
	var streams: Array = (parsed as Dictionary).get("streams", [])
	var stream: Dictionary = streams[0] if not streams.is_empty() and streams[0] is Dictionary else {}
	return {"ok": int(stream.get("width", 0)) == 1280 and int(stream.get("height", 0)) == 720 and str(stream.get("avg_frame_rate", "")) == "10/1" and int(stream.get("nb_read_frames", "0")) == 70}


func _decoded_digest_check() -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute("ffmpeg", PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-i", ProjectSettings.globalize_path(video_uri),
		"-map", "0:v:0", "-an", "-f", "framemd5", "-",
	]), output, true)
	if exit_code != 0:
		return {"ok": false}
	var hashes := {}
	var rows := 0
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	for raw_line in raw.split("\n"):
		var fields := raw_line.split(",")
		if fields.size() != 6:
			continue
		var hash := fields[5].strip_edges()
		if hash.length() != 32:
			continue
		rows += 1
		hashes[hash] = true
	return {"ok": rows == 70 and hashes.size() == 70}


func _video_depicts_proof() -> bool:
	# Validate a decoded source frame rather than trusting x11grab's display
	# coordinates. The temporary PNG is only a test decode and is not evidence.
	var temporary := "/tmp/mobile-base-motion-proof-%s-video-%d.png" % [capture_tag, OS.get_process_id()]
	var exit_code := OS.execute("ffmpeg", PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-y", "-ss", "2.000",
		"-i", ProjectSettings.globalize_path(video_uri), "-frames:v", "1", temporary,
	]), [], true)
	if exit_code != 0:
		return false
	var image := Image.load_from_file(temporary)
	var title_amber := false
	var body_amber := false
	var road_brown := false
	if image != null and image.get_width() == 1280 and image.get_height() == 720:
		for y in range(26, 80, 6):
			for x in range(30, 650, 8):
				var title := image.get_pixel(x, y)
				title_amber = title_amber or (title.r > 0.65 and title.g > 0.45 and title.b < 0.45)
		for y in range(180, 580, 18):
			for x in range(210, 1080, 20):
				var body := image.get_pixel(x, y)
				body_amber = body_amber or (body.r > 0.50 and body.g > 0.24 and body.g < body.r and body.b < body.g * 0.92)
		for y in range(600, 710, 10):
			for x in range(20, 1260, 20):
				var road := image.get_pixel(x, y)
				road_brown = road_brown or (road.r > 0.30 and road.g > 0.16 and road.g < road.r and road.b < road.g)
	return title_amber and body_amber and road_brown


func _configure_paths() -> void:
	var requested := OS.get_environment("MOBILE_BASE_MOTION_PROOF_CAPTURE_TAG").strip_edges()
	if requested in ["v1", "v2"]:
		capture_tag = requested
	root_uri = EVIDENCE_PREFIX + capture_tag
	result_uri = RESULT_PREFIX + capture_tag + ".json"
	video_uri = root_uri + "/sideview_mobile_base_motion_%s.mp4" % capture_tag
	shots = {
		"parked": root_uri + "/sideview_mobile_base_parked.png",
		"rolling": root_uri + "/sideview_mobile_base_rolling.png",
		"stopped": root_uri + "/sideview_mobile_base_stopped.png",
	}


func _finish() -> void:
	print("== Result: %s ==" % ("PASS" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
