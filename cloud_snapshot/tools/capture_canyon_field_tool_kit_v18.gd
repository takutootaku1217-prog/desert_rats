extends SceneTree
## Direct-X11 evidence for the v18 same-worker field-carried mine-tool swap.
## The field simulation runs through the production adapter.  Button.pressed is
## recorded as programmatic UI input only; it is not a physical-pointer claim.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const EVIDENCE_ROOT_URI := "res://prototypes/recovery_map_lab/evidence/canyon_field_tool_kit_v18_final"
const SCHEDULED_URI := EVIDENCE_ROOT_URI + "/field_tool_scheduled_hud.png"
const COMPLETED_URI := EVIDENCE_ROOT_URI + "/field_tool_completed_hud.png"
const VIDEO_URI := EVIDENCE_ROOT_URI + "/canyon_field_tool_kit_v18.mp4"
const RESULT_URI := EVIDENCE_ROOT_URI + "/capture_result.json"
const VIDEO_FPS := 10
const VIDEO_SECONDS := 64.0

var main
var field
var video_pid := -1
var failure := ""
var snapshots := {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	SaveGame.disabled = true
	if DisplayServer.get_name() != "X11":
		_finish_failure("X11 viewport unavailable")
		return
	if not _prepare_output():
		_finish_failure("refusing to overwrite v18 evidence")
		return
	if not await _prepare_field():
		return
	await RenderingServer.frame_post_draw
	if field.field_tool_button == null or field.field_tool_button.disabled:
		_finish_failure("field tool control unavailable")
		return
	if not _start_video():
		_finish_failure("ffmpeg x11grab start")
		return
	field.field_tool_button.emit_signal("pressed")
	await RenderingServer.frame_post_draw
	if str(Dictionary(field.session.equipment_status().get("field_tool", {})).get("status", "")) != "scheduled":
		_finish_failure("field tool did not schedule")
		return
	if not _save_viewport(SCHEDULED_URI, "scheduled"):
		_finish_failure("scheduled screenshot")
		return
	if not await _wait_until(func(): return str(Dictionary(field.session.equipment_status().get("field_tool", {})).get("status", "")) == "completed", 52.0):
		_finish_failure("field tool did not complete at relay")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(COMPLETED_URI, "completed"):
		_finish_failure("completed screenshot")
		return
	if not await _finish_video():
		_finish_failure("ffmpeg video")
		return
	var probe := _probe_video()
	if not bool(probe.get("ok", false)):
		_finish_failure("ffprobe")
		return
	var result := {
		"schema": 1,
		"display_server": DisplayServer.get_name(),
		"actual_viewport": true,
		"engine_version": str(Engine.get_version_info().get("string", "unknown")),
		"validation_scope": "Linux/X11 evidence only; Windows/Godot 4.7.2, physical input, audio, and performance remain unverified",
		"input_method": "programmatic_button_signal",
		"physical_pointer": false,
		"capture_method": "direct X11 1280x720 PNGs and x11grab MP4 at 10fps; no generated, interpolated, cropped, scaled, or speed-altered frames",
		"video": VIDEO_URI,
		"video_probe": probe,
		"screenshots": snapshots,
		"final_field_tool": Dictionary(field.session.equipment_status().get("field_tool", {})),
		"conservation_ok": field.session.conservation_ok(),
		"normal_user_save_touched": false,
	}
	if not _write_result(result):
		_finish_failure("result")
		return
	_cleanup()
	print("CANYON_FIELD_TOOL_KIT_V18_CAPTURE_COMPLETE ", RESULT_URI)
	quit()

func _prepare_field() -> bool:
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 260129)
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	main.director.enabled = false
	main.tool_auto = false
	main.workers[0].ranks[GameData.Field.GATHERER] = 2
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
	main.storage.store_owned(GameData.Item.HAMMER, 1, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.PICKAXE, 1, Inventory.SOURCE_TRANSFER)
	if not main.equip_tool(main.workers[0], GameData.Item.HAMMER):
		_finish_failure("seed hammer")
		return false
	var created: Dictionary = RouteSession.create_from_game(main, "field-tool-v18-runtime-capture", {"outpost_enabled": false, "vertical_slice": true})
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

func _prepare_output() -> bool:
	for uri in [SCHEDULED_URI, COMPLETED_URI, VIDEO_URI, RESULT_URI]:
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
	return video_pid > 0

func _finish_video() -> bool:
	var deadline := Time.get_ticks_msec() + int((VIDEO_SECONDS + 5.0) * 1000.0)
	while OS.is_process_running(video_pid) and Time.get_ticks_msec() < deadline:
		await process_frame
	if OS.is_process_running(video_pid):
		return false
	var file := FileAccess.open(ProjectSettings.globalize_path(VIDEO_URI), FileAccess.READ)
	if file == null:
		return false
	var size := file.get_length()
	file.close()
	return size > 1024

func _probe_video() -> Dictionary:
	var output: Array = []
	var args := PackedStringArray(["-v", "error", "-count_frames", "-show_entries", "stream=width,height,avg_frame_rate,nb_read_frames:format=duration,size", "-of", "json", ProjectSettings.globalize_path(VIDEO_URI)])
	var exit_code := OS.execute("ffprobe", args, output, true)
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var parsed: Variant = JSON.parse_string(raw)
	if exit_code != 0 or not parsed is Dictionary:
		return {"ok": false, "raw": raw}
	var streams: Array = (parsed as Dictionary).get("streams", [])
	var stream: Dictionary = streams[0] if not streams.is_empty() and streams[0] is Dictionary else {}
	var frame_rate := _fraction_as_float(str(stream.get("avg_frame_rate", "0/1")))
	var format: Dictionary = (parsed as Dictionary).get("format", {})
	return {
		"ok": int(stream.get("width", 0)) == 1280 and int(stream.get("height", 0)) == 720 and int(stream.get("nb_read_frames", "0")) >= 140 and frame_rate >= 9.8 and float(format.get("duration", 0.0)) >= VIDEO_SECONDS - 0.2,
		"decoded_frame_count": int(stream.get("nb_read_frames", "0")),
		"decoded_frame_rate": frame_rate,
		"decoded_duration_seconds": float(format.get("duration", 0.0)),
		"size": int(format.get("size", "0")),
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
	snapshots[label] = {
		"uri": uri,
		"error": error,
		"state": field.session.state_summary().duplicate(true),
		"field_tool": Dictionary(field.session.equipment_status().get("field_tool", {})),
	}
	return error == OK

func _write_result(data: Dictionary) -> bool:
	var file := FileAccess.open(ProjectSettings.globalize_path(RESULT_URI), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()
	return true

func _cleanup() -> void:
	if field != null and is_instance_valid(field):
		field.queue_free()
	if main != null and is_instance_valid(main):
		main.queue_free()

func _finish_failure(reason: String) -> void:
	failure = reason
	_cleanup()
	push_error("CANYON_FIELD_TOOL_KIT_V18_CAPTURE_FAILED " + failure)
	quit(1)
