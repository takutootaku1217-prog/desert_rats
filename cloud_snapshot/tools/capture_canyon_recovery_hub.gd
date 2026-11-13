extends SceneTree
## 峡谷回収拠点の実 Godot 描画を保存する。概念画像や headless 出力は証跡にしない。

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const DEPARTURE_URI := "res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_departure_runtime.png"
const HARVEST_URI := "res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_harvest_runtime.png"
const CARRY_URI := "res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_carry_runtime.png"
const CARGO_URI := "res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_cargo_runtime.png"
const HUD_URI := "res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_hud_runtime.png"
const HUD_INTERACTION_URI := "res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_hud_interaction_runtime.png"
const RESOLUTION_URI := "res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_resolution_640x360_x2.png"
const BRIDGE_FRAME_URIS := [
	"res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_bridge_walk_01.png",
	"res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_bridge_walk_02.png",
	"res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_bridge_walk_03.png",
	"res://prototypes/recovery_map_lab/evidence/canyon_hub_runtime/canyon_bridge_walk_04.png",
]
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/canyon_hub_render_capture.json"

var main
var field
var screenshots := {}
var bridge_walk: Array[Dictionary] = []
var hud_interaction := {}
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
		_write_result({"display_server": "headless", "screenshots": ["N/A"], "screenshot_error": "not_captured_headless", "normal_user_save_touched": false})
		print("CANYON_HUB_CAPTURE_SKIPPED_HEADLESS")
		quit()
		return
	if not await _move("b_forest") or not await _move("c_quarry"):
		_finish_failure("horizontal route to C")
		return
	var created: Dictionary = RouteSession.create_from_game(main, "canyon-hub-render", {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		_finish_failure(str(created.get("reason", "session")))
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
	var route_controls := field.get_node_or_null("RouteControls") as CanvasItem
	if route_controls == null:
		_finish_failure("RouteControls unavailable")
		return
	# This is the actual playable HUD, recorded before the art-only views hide
	# it.  The UI itself is never removed from the running adapter.
	if not _save_viewport(HUD_URI):
		_finish_failure("HUD screenshot")
		return
	# The presentation captures below intentionally hide the control card only
	# so it cannot cover the canyon ridge.  Their purpose is art inspection.
	if route_controls != null:
		route_controls.visible = false
	# Force the existing alternate path: its visual bridge must stay clear while
	# the unchanged session uses its bypass waypoint.
	field.session.set_gate_closed(true)
	if not await _capture_bridge_walk():
		_finish_failure("continuous bridge walk was not captured")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(DEPARTURE_URI):
		_finish_failure("departure screenshot")
		return
	if not await _wait_for_harvest():
		_finish_failure("harvest did not begin")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(HARVEST_URI):
		_finish_failure("harvest screenshot")
		return
	if not await _wait_for_carrying():
		_finish_failure("carry did not begin")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(CARRY_URI):
		_finish_failure("carry screenshot")
		return
	if not await _wait_for_cargo():
		_finish_failure("cargo did not reach dock")
		return
	await RenderingServer.frame_post_draw
	if not _save_viewport(CARGO_URI):
		_finish_failure("cargo screenshot")
		return
	if not _save_resolution_comparison():
		_finish_failure("640x360 x2 comparison")
		return
	route_controls.visible = true
	hud_interaction = await _exercise_hud_buttons()
	await RenderingServer.frame_post_draw
	if not _save_viewport(HUD_INTERACTION_URI):
		_finish_failure("HUD interaction screenshot")
		return
	_write_result({
		"display_server": DisplayServer.get_name(),
		"screenshots": screenshots,
		"bridge_walk": bridge_walk,
		"hud_capture": {
			"playable_hud_visible": true,
			"art_only_captures_hide_hud": true,
			"interaction": hud_interaction,
		},
		"resolution_comparison": "same native 1280x720 Godot frame -> nearest 640x360 -> nearest 1280x720 (postprocess; not a separate window run)",
		"screenshot_error": 0,
		"session": field.session.state_summary(),
		"gate_closed": field.session.gate_closed,
		"normal_user_save_touched": false,
	})
	print("CANYON_HUB_CAPTURE_COMPLETE ", CARGO_URI)
	quit()

func _exercise_hud_buttons() -> Dictionary:
	# The sandbox offers X11 rendering but no installed, supported OS input
	# injector.  This
	# invokes the same Button.pressed signals wired in the playable control,
	# records each result, and leaves normal user:// saves disabled.
	var result := {
		"method": "programmatic Button.pressed signals; no installed, supported OS-level X11 click injector",
		"bypass": false,
		"save": false,
		"load": false,
		"retreat": false,
		"fixture_path": "",
	}
	var bypass_before: bool = bool(field.session.gate_closed)
	field.gate_button.emit_signal("pressed")
	result["bypass"] = field.session.gate_closed != bypass_before
	# Restore the closed-gate bypass visual used by the bridge capture.
	field.gate_button.emit_signal("pressed")
	var save_button := _button_with_text(field, "検証保存")
	var load_button := _button_with_text(field, "検証読込")
	var retreat_button := _button_with_text(field, "撤退")
	if save_button != null:
		save_button.emit_signal("pressed")
		await process_frame
		result["save"] = field.notice_label != null and field.notice_label.text.begins_with("検証保存:")
		result["fixture_path"] = RouteSession.project_fixture_path(RouteSession.GUI_STATE_FILE)
	if load_button != null:
		load_button.emit_signal("pressed")
		await process_frame
		result["load"] = field.notice_label != null and field.notice_label.text.begins_with("検証セッションを復元")
	if retreat_button != null:
		retreat_button.emit_signal("pressed")
		await process_frame
		result["retreat"] = field.session.phase == "recall"
	result["notice"] = field.notice_label.text if field.notice_label != null else ""
	return result

func _button_with_text(root_node: Node, title: String) -> Button:
	for node in root_node.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == title:
			return button
	return null

func _move(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 300:
		main._process(0.2)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return false

func _wait_for_harvest() -> bool:
	for unused in 900:
		await process_frame
		for actor_id in field.session.actors:
			if str(field.session.actors[actor_id].get("state", "")) == "harvesting":
				return true
	return false

func _capture_bridge_walk() -> bool:
	var tracked_actor_id := ""
	var last_capture_source := Vector2.INF
	var occupancy: CanyonRecoveryOccupancy = field.canyon_hub.get_node_or_null("Occupancy") as CanyonRecoveryOccupancy
	for unused in 1500:
		await process_frame
		if occupancy == null:
			return false
		for raw_actor_id in field.session.actors:
			var actor_id := str(raw_actor_id)
			var actor: Dictionary = field.session.actors[raw_actor_id]
			if str(actor.get("route", "")) != "bypass":
				continue
			var source: Vector2 = Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0)))
			var screen: Vector2 = field.canyon_hub.map_point(source)
			if not occupancy.bridge_contains(screen):
				continue
			if tracked_actor_id.is_empty():
				tracked_actor_id = actor_id
			if actor_id != tracked_actor_id:
				continue
			if last_capture_source != Vector2.INF and last_capture_source.distance_to(source) < 1.0:
				continue
			if not _bridge_capture_stage_reached(bridge_walk.size(), screen):
				continue
			await RenderingServer.frame_post_draw
			var uri: String = BRIDGE_FRAME_URIS[bridge_walk.size()]
			if not _save_viewport(uri):
				return false
			bridge_walk.append({
				"actor_id": actor_id,
				"source": {"x": source.x, "y": source.y},
				"screen": {"x": screen.x, "y": screen.y},
				"state": str(actor.get("state", "")),
				"walkable": field.canyon_hub.walkable_contains(source),
				"bridge_deck": occupancy.bridge_contains(screen),
				"stage": ["entry", "middle", "upper_deck", "exit"][bridge_walk.size()],
			})
			last_capture_source = source
			if bridge_walk.size() == BRIDGE_FRAME_URIS.size():
				return true
	return false

func _bridge_capture_stage_reached(stage: int, screen: Vector2) -> bool:
	match stage:
		0:
			return true
		1:
			return screen.x <= 465.0 and screen.y <= 440.0
		2:
			return screen.x <= 405.0 and screen.y <= 390.0
		3:
			return screen.x <= 360.0 and screen.y <= 340.0
		_:
			return false

func _wait_for_cargo() -> bool:
	for unused in 1800:
		await process_frame
		if int(field.session.state_summary().get("depot", 0)) > 0:
			return true
	return false

func _wait_for_carrying() -> bool:
	for unused in 1800:
		await process_frame
		for actor_id in field.session.actors:
			var actor: Dictionary = field.session.actors[actor_id]
			if int(actor.get("carry_n", 0)) > 0 and field.canyon_hub.activity_label_for(actor) == "運搬":
				return true
	return false

func _save_viewport(uri: String) -> bool:
	var path := ProjectSettings.globalize_path(uri)
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK:
		failure = "directory %s" % directory_error
		return false
	var image: Image = root.get_texture().get_image()
	if not _has_canyon_render_signature(image):
		failure = "render signature missing"
		screenshots[uri] = {"error": failure, "world_phase": main.world.phase, "world_region": main.world.region}
		return false
	var error := image.save_png(path)
	screenshots[uri] = {"error": error, "render_signature": "canyon-ore-and-amber-base", "world_phase": main.world.phase, "world_region": main.world.region}
	return error == OK

func _save_resolution_comparison() -> bool:
	var path := ProjectSettings.globalize_path(RESOLUTION_URI)
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK:
		failure = "resolution directory %s" % directory_error
		return false
	var image: Image = root.get_texture().get_image()
	if not _has_canyon_render_signature(image):
		failure = "resolution source signature missing"
		return false
	var comparison: Image = image.duplicate()
	comparison.resize(640, 360, Image.INTERPOLATE_NEAREST)
	comparison.resize(1280, 720, Image.INTERPOLATE_NEAREST)
	var error: Error = comparison.save_png(path)
	screenshots[RESOLUTION_URI] = {"error": error, "comparison": "nearest downsample 640x360 then nearest x2", "source": CARGO_URI}
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

func _write_result(result: Dictionary) -> void:
	var result_path := ProjectSettings.globalize_path(RESULT_URI)
	DirAccess.make_dir_recursive_absolute(result_path.get_base_dir())
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()

func _finish_failure(reason: String) -> void:
	failure = reason
	_write_result({"display_server": DisplayServer.get_name(), "screenshots": screenshots, "failure": failure, "normal_user_save_touched": false})
	print("CANYON_HUB_CAPTURE_FAILED ", reason)
	quit(1)
