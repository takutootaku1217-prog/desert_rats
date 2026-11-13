extends SceneTree
## Actual X11 observation of the existing single-worker verification path.
## It does not invent a rock-crossing route and never changes the production
## scene's depth order. The resulting frames establish which visible CanvasItem
## layers carry the crew across the existing painted bridge and base foreground.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const EVIDENCE_ROOT_URI := "res://prototypes/recovery_map_lab/evidence/v13_quarterview_occlusion_acceptance"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/v13_quarterview_occlusion_acceptance.json"
const VIDEO_FPS := 10
const VIDEO_DURATION_MSEC := 14000
const VIDEO_GRACE_MSEC := 5000
const OBSERVATION_TIMEOUT_MSEC := 28000

var main
var field
var snapshots := {}
var bridge_samples := {}
var video_pid := -1
var video_uri := ""
var failure := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	SaveGame.disabled = true
	if DisplayServer.get_name() != "X11":
		_finish_failure("quarter-view evidence requires X11")
		return
	if not await _prepare_field():
		return
	if not _prepare_output() or not _start_x11_video_capture():
		_finish_failure("X11 video output setup")
		return
	var deadline := Time.get_ticks_msec() + OBSERVATION_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline and not _all_witnesses_captured():
		await RenderingServer.frame_post_draw
		if not await _observe_visible_worker():
			_finish_failure("visible crew or bridge surface unavailable")
			return
	if not _all_witnesses_captured():
		_finish_failure("timed out before entry/deck/exit/dock witness")
		return
	if not await _finish_video():
		return
	var result := {
		"schema": 1,
		"display_server": DisplayServer.get_name(),
		"actual_viewport": true,
		"mode": "single_worker_demo",
		"verification_mode": true,
		"mode_note": "Existing one-worker bridge verification path; normal-role roster and balance are not changed by this observation.",
		"visible_worker_node": "CanyonCrewViews",
		"native_projected_workers_hidden": _native_projected_workers_hidden(),
		"layers": _layer_snapshot(),
		"snapshots": snapshots,
		"bridge_samples": bridge_samples,
		"video": video_uri,
		"video_capture_fps": VIDEO_FPS,
		"video_capture_note": "Direct X11 1280x720 recording at 10fps; no AI interpolation, copied frames, or manual session ticks.",
		"occlusion_issue_reproduced": false,
		"production_depth_fix_applied": false,
		"generic_y_sort_applied": false,
		"rock_crossing_not_tested": true,
		"rock_crossing_note": "Existing session routes avoid decorative foreground-rock footprints. Forcing an actor through one would be invalid evidence.",
		"normal_user_save_touched": false,
	}
	if not _write_result(result):
		_finish_failure("result write")
		return
	_cleanup()
	print("V13_QUARTERVIEW_OCCLUSION_ACCEPTANCE_COMPLETE ", RESULT_URI)
	quit(0)

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
	var created: Dictionary = RouteSession.create_from_game(main, "v13-quarterview-occlusion-acceptance", {"outpost_enabled": false, "single_worker_demo": true})
	if not bool(created.get("ok", false)):
		_finish_failure(str(created.get("reason", "single-worker session setup")))
		return false
	main.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	field = FieldAdapter.new()
	field.configure(main, created.session)
	layer.add_child(field)
	await process_frame
	await RenderingServer.frame_post_draw
	if field.canyon_hub == null or not field.session.is_single_worker_demo():
		_finish_failure("single-worker visual field unavailable")
		return false
	# The bridge bypass is the existing demo contract; this does not make a new
	# route or modify navigation/collision authority.
	field.session.set_gate_closed(true)
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

func _observe_visible_worker() -> bool:
	if field == null or field.canyon_hub == null or field.session == null:
		return false
	var actor: Dictionary = field.session.actors.get("worker:0", {})
	if actor.is_empty():
		return false
	var hub = field.canyon_hub
	var source := Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0)))
	var foot: Vector2 = hub.presentation_point_for_actor(actor)
	var bridge = hub.get_node_or_null("Bridge")
	var occupancy = hub.get_node_or_null("Occupancy")
	if bridge == null or occupancy == null or not bridge.has_method("surface_sample"):
		return false
	var surface: Dictionary = bridge.call("surface_sample", foot, hub)
	var surface_name := str(surface.get("region", "outside"))
	var source_progress := float(hub.single_demo_bridge_progress_for_source(source))
	if source_progress >= 0.0:
		if not bridge_samples.has("entry") and surface_name == "approach_near":
			return await _capture_stage("entry", actor, source, foot, surface, occupancy)
		if bridge_samples.has("entry") and not bridge_samples.has("deck") and surface_name == "deck":
			return await _capture_stage("deck", actor, source, foot, surface, occupancy)
		if bridge_samples.has("deck") and not bridge_samples.has("exit") and surface_name == "approach_far":
			return await _capture_stage("exit", actor, source, foot, surface, occupancy)
	if not snapshots.has("dock") and str(actor.get("state", "")) == "dock_wait" and int(actor.get("carry_n", 0)) > 0:
		return await _capture_stage("dock", actor, source, foot, {"region": "service_apron", "deck_progress": -1.0}, occupancy)
	return true

func _capture_stage(key: String, actor: Dictionary, source: Vector2, foot: Vector2, surface: Dictionary, occupancy) -> bool:
	await RenderingServer.frame_post_draw
	if not _save_viewport(key):
		return false
	var hub = field.canyon_hub
	var bridge = hub.get_node("Bridge")
	var sample := {
		"actor_id": "worker:0",
		"state": str(actor.get("state", "")),
		"carry_n": int(actor.get("carry_n", 0)),
		"source": _vector_array(source),
		"foot_point": _vector_array(foot),
		"surface": str(surface.get("region", "outside")),
		"deck_progress": snappedf(float(surface.get("deck_progress", -1.0)), 0.001),
		"painted_path": bool(bridge.call("presentation_path_contains", foot, hub)),
		"bridge_collision": bool(occupancy.bridge_contains(foot)),
		"display_walkable": bool(occupancy.allows_walkable(foot)),
		"source_walkable": bool(hub.walkable_contains(source)),
	}
	if key in ["entry", "deck", "exit"]:
		bridge_samples[key] = sample
	else:
		bridge_samples["dock"] = sample
	return true

func _all_witnesses_captured() -> bool:
	return bridge_samples.has("entry") and bridge_samples.has("deck") and bridge_samples.has("exit") and snapshots.has("dock")

func _layer_snapshot() -> Dictionary:
	if field == null or field.canyon_hub == null:
		return {}
	var hub = field.canyon_hub
	return {
		"bridge": _z_index(hub.get_node_or_null("Bridge")),
		"base_rear": _z_index(hub.get_node_or_null("BaseRear")),
		"checkpoint_rear": _z_index(hub.get_node_or_null("CheckpointRear")),
		"crew": _z_index(hub.get_node_or_null("CanyonCrewViews")),
		"base_front": _z_index(hub.get_node_or_null("BaseFront")),
		"checkpoint_front": _z_index(hub.get_node_or_null("CheckpointFront")),
		"cargo_yard": _z_index(hub.get_node_or_null("CargoYard")),
	}

func _z_index(node: Node) -> int:
	return (node as CanvasItem).z_index if node is CanvasItem else -99

func _native_projected_workers_hidden() -> bool:
	if field == null or field.actor_layer == null:
		return false
	for worker in field.actor_layer.get_children():
		if worker is CanvasItem and (worker as CanvasItem).visible:
			return false
	return field.actor_layer.get_child_count() > 0

func _vector_array(value: Vector2) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001)]

func _save_viewport(key: String) -> bool:
	var uri := EVIDENCE_ROOT_URI.path_join("quarterview_%s.png" % key)
	var path := ProjectSettings.globalize_path(uri)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var image: Image = root.get_texture().get_image()
	if image == null or image.get_width() != 1280 or image.get_height() != 720:
		return false
	if image.save_png(path) != OK:
		return false
	snapshots[key] = uri
	return true

func _prepare_output() -> bool:
	var root_path := ProjectSettings.globalize_path(EVIDENCE_ROOT_URI)
	if DirAccess.make_dir_recursive_absolute(root_path) != OK:
		return false
	video_uri = EVIDENCE_ROOT_URI.path_join("quarterview_bridge_observation.mp4")
	var path := ProjectSettings.globalize_path(video_uri)
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		return false
	return true

func _start_x11_video_capture() -> bool:
	var display := OS.get_environment("DISPLAY")
	if display.is_empty():
		return false
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-n",
		"-f", "x11grab", "-framerate", str(VIDEO_FPS),
		"-video_size", "1280x720", "-draw_mouse", "0", "-i", display + "+0,0",
		"-t", "%.3f" % (float(VIDEO_DURATION_MSEC) / 1000.0),
		"-an", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18",
		"-pix_fmt", "yuv420p", "-movflags", "+faststart",
		ProjectSettings.globalize_path(video_uri),
	])
	video_pid = OS.create_process("ffmpeg", args)
	return video_pid > 0

func _finish_video() -> bool:
	var deadline := Time.get_ticks_msec() + VIDEO_GRACE_MSEC
	while video_pid > 0 and OS.is_process_running(video_pid) and Time.get_ticks_msec() < deadline:
		await process_frame
	if video_pid > 0 and OS.is_process_running(video_pid):
		_finish_failure("ffmpeg did not finish")
		return false
	var file := FileAccess.open(ProjectSettings.globalize_path(video_uri), FileAccess.READ)
	if file == null:
		_finish_failure("video output missing")
		return false
	var bytes := file.get_length()
	file.close()
	if bytes < 1024:
		_finish_failure("video output empty")
		return false
	return true

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
	_write_result({
		"schema": 1,
		"display_server": DisplayServer.get_name(),
		"actual_viewport": DisplayServer.get_name() == "X11",
		"mode": "single_worker_demo",
		"verification_mode": true,
		"failure": failure,
		"snapshots": snapshots,
		"bridge_samples": bridge_samples,
		"video": video_uri,
		"normal_user_save_touched": false,
	})
	if video_pid > 0 and OS.is_process_running(video_pid):
		OS.kill(video_pid)
	_cleanup()
	print("V13_QUARTERVIEW_OCCLUSION_ACCEPTANCE_FAILED ", reason)
	quit(1)

func _cleanup() -> void:
	if field != null and is_instance_valid(field):
		field.queue_free()
	if main != null and is_instance_valid(main):
		main.queue_free()
