extends SceneTree
## C 前哨地の実行中 viewport を段階ごとに保存する証跡用スクリプト。
## 画像生成物ではなく、横視点と bridge adapter が描画した Godot の実画面を保存する。

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const HORIZONTAL_URI := "res://prototypes/recovery_map_lab/evidence/route_outpost/horizontal_travel_runtime.png"
const COMBAT_URI := "res://prototypes/recovery_map_lab/evidence/route_outpost/outpost_combat_runtime.png"
const CARGO_URI := "res://prototypes/recovery_map_lab/evidence/route_outpost/outpost_cargo_runtime.png"
const RETURN_URI := "res://prototypes/recovery_map_lab/evidence/route_outpost/outpost_return_runtime.png"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/outpost_render_capture.json"

var main
var field
var screenshots := {}
var failure := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Normal SaveGame / user:// is never part of this evidence path.
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
		# This checks construction only. Headless must never be called visual evidence.
		if not await _move("b_forest") or not await _move("c_quarry"):
			_finish_failure("headless horizontal route")
			return
		var headless_created: Dictionary = RouteSession.create_from_game(main, "outpost-render-headless", {"outpost_enabled": true})
		if not bool(headless_created.get("ok", false)):
			_finish_failure(str(headless_created.get("reason", "headless session")))
			return
		var headless_layer := CanvasLayer.new()
		root.add_child(headless_layer)
		var headless_field = FieldAdapter.new()
		headless_field.configure(main, headless_created.session)
		headless_layer.add_child(headless_field)
		for unused in 2:
			await process_frame
		_write_result({"display_server": "headless", "screenshots": ["N/A"], "screenshot_error": "not_captured_headless", "session": headless_field.session.state_summary(), "normal_user_save_touched": false})
		print("ROUTE_OUTPOST_CAPTURE_SKIPPED_HEADLESS")
		quit()
		return
	if not _begin_move("b_forest"):
		_finish_failure("A to B could not start")
		return
	# Actual horizontal WorldTrip state before advancing it to B.
	main._process(0.2)
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save_viewport(HORIZONTAL_URI):
		_finish_failure("horizontal screenshot")
		return
	if not await _wait_for_region("b_forest") or not await _move("c_quarry"):
		_finish_failure("horizontal route to C")
		return
	var created: Dictionary = RouteSession.create_from_game(main, "outpost-render", {"outpost_enabled": true})
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
	# The closed main gate makes the bypass and cover part of the real run.
	field.session.set_gate_closed(true)
	if not await _wait_for_combat_frame():
		_finish_failure("outpost combat did not begin")
		return
	if not _save_viewport(COMBAT_URI):
		_finish_failure("combat screenshot")
		return
	if not await _wait_for_cargo_frame():
		_finish_failure("outpost cargo did not arrive")
		return
	if not _save_viewport(CARGO_URI):
		_finish_failure("cargo screenshot")
		return
	field.session.request_recall()
	if not await _wait_for_ready_to_exit():
		_finish_failure("outpost recall did not settle")
		return
	var session_before_commit: Dictionary = field.session.state_summary().duplicate(true)
	var committed: Dictionary = field.session.commit_to_game(main)
	if not bool(committed.get("ok", false)):
		_finish_failure(str(committed.get("reason", "commit")))
		return
	field.queue_free()
	field = null
	main.visible = true
	main.process_mode = Node.PROCESS_MODE_INHERIT
	if not _begin_move("b_forest"):
		_finish_failure("C to B could not start")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save_viewport(RETURN_URI):
		_finish_failure("return screenshot")
		return
	_write_result({"display_server": DisplayServer.get_name(), "screenshots": screenshots, "screenshot_error": 0, "session_before_commit": session_before_commit, "commit": committed, "return_world_phase": main.world.phase, "return_world_region": main.world.region, "normal_user_save_touched": false})
	print("ROUTE_OUTPOST_CAPTURE_COMPLETE ", RETURN_URI)
	quit()

func _begin_move(destination: String) -> bool:
	return main.world.request(destination)

func _move(destination: String) -> bool:
	if not _begin_move(destination):
		return false
	return await _wait_for_region(destination)

func _wait_for_region(destination: String) -> bool:
	for unused in 300:
		main._process(0.2)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return false

func _wait_for_combat_frame() -> bool:
	for unused in 1800:
		await process_frame
		for enemy_id in field.session.outpost_enemies:
			var enemy: Dictionary = field.session.outpost_enemies[enemy_id]
			if not bool(enemy.get("dead", false)) and float(enemy.get("hp", 0.0)) < float(enemy.get("max_hp", 0.0)):
				return true
	return false

func _wait_for_cargo_frame() -> bool:
	for unused in 2400:
		await process_frame
		if field.session.outpost_cleared and int(field.session.state_summary().get("depot", 0)) > 0:
			return true
	return false

func _wait_for_ready_to_exit() -> bool:
	for unused in 1800:
		await process_frame
		if field.session.phase == "ready_to_exit":
			return true
	return false

func _save_viewport(uri: String) -> bool:
	var path := ProjectSettings.globalize_path(uri)
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		failure = "directory %s" % dir_error
		return false
	var error := root.get_texture().get_image().save_png(path)
	screenshots[uri] = {"error": error, "world_phase": main.world.phase, "world_region": main.world.region}
	return error == OK

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
	print("ROUTE_OUTPOST_CAPTURE_FAILED ", reason)
	quit(1)
