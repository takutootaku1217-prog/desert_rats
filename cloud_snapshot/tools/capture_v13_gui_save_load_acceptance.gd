extends SceneTree
## Narrow v13 acceptance evidence for the existing verification-only Save/Load
## buttons. It uses the button signal wiring, not a claim of a physical pointer
## click: this cloud image has no supported X11 click injector.
##
## The only state file touched is RouteSession.GUI_STATE_FILE inside this
## isolated acceptance copy. Its prior bytes (or absence) are restored before
## the script exits; normal user:// saving remains disabled throughout.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const EVIDENCE_ROOT_URI := "res://prototypes/recovery_map_lab/evidence/v13_gui_save_load_acceptance"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/v13_gui_save_load_acceptance.json"

var main
var field
var fixture_path := ""
var fixture_existed := false
var fixture_bytes := PackedByteArray()
var fixture_restored := false
var snapshots := {}
var failure := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	SaveGame.disabled = true
	if DisplayServer.get_name() != "X11":
		_finish_failure("X11 viewport unavailable")
		return
	fixture_path = RouteSession.project_fixture_path(RouteSession.GUI_STATE_FILE)
	if fixture_path.is_empty():
		_finish_failure("verification fixture path invalid")
		return
	if not _backup_and_clear_fixture():
		_finish_failure("could not prepare isolated verification fixture")
		return
	if not await _prepare_field():
		return
	var load_button := _button_with_text(field, "検証読込")
	var save_button := _button_with_text(field, "検証保存")
	if load_button == null or save_button == null or field.block_button == null or field.dock_button == null:
		_finish_failure("verification controls unavailable")
		return

	# No cancel dialog is implemented by this narrow verification UI. The safe
	# negative path is missing fixture: it must retain the live session and show
	# the failure through the visible notice label.
	var original_session = field.session
	load_button.emit_signal("pressed")
	await process_frame
	await RenderingServer.frame_post_draw
	var missing_fixture_rejected: bool = field.session == original_session and field.notice_label != null and field.notice_label.text.begins_with("検証用保存がありません")
	if not _save_viewport("missing"):
		_finish_failure("missing-fixture screenshot")
		return

	var saved_signature := _session_signature(field.session)
	save_button.emit_signal("pressed")
	await process_frame
	await RenderingServer.frame_post_draw
	var saved: bool = FileAccess.file_exists(fixture_path) and field.notice_label != null and field.notice_label.text.begins_with("検証保存:")

	# Change state through the two visible controls, then use the visible Load
	# control. The session stays frozen between events so this compares fixture
	# serialization/restoration, not a race with worker simulation.
	field.block_button.emit_signal("pressed")
	field.dock_button.emit_signal("pressed")
	field._update_controls()
	await process_frame
	await RenderingServer.frame_post_draw
	var mutated: bool = bool(field.session.all_routes_closed) and int(field.session.dock_count) == 2 and _session_signature(field.session) != saved_signature
	if not _save_viewport("mutated"):
		_finish_failure("mutated screenshot")
		return

	load_button = _button_with_text(field, "検証読込")
	load_button.emit_signal("pressed")
	await process_frame
	await RenderingServer.frame_post_draw
	var restored: bool = field.notice_label != null and field.notice_label.text.begins_with("検証セッションを復元") and _session_signature(field.session) == saved_signature
	if not _save_viewport("restored"):
		_finish_failure("restored screenshot")
		return

	# The same on-screen control is deliberately safe to invoke repeatedly.
	load_button = _button_with_text(field, "検証読込")
	load_button.emit_signal("pressed")
	await process_frame
	var repeat_restored: bool = field.notice_label != null and field.notice_label.text.begins_with("検証セッションを復元") and _session_signature(field.session) == saved_signature

	fixture_restored = _restore_prior_fixture()
	var result := {
		"schema": 1,
		"display_server": DisplayServer.get_name(),
		"actual_viewport": true,
		"input_method": "programmatic_button_signal",
		"physical_pointer": false,
		"input_note": "No installed, supported OS-level X11 click injector in this cloud environment; Button.pressed signals exercise the wired GUI route but are not physical clicks.",
		"cancel_ui_present": false,
		"cancel_verification": "not_applicable_no_cancel_control; missing-fixture rejection is the available negative path",
		"missing_fixture_rejected": missing_fixture_rejected,
		"saved": saved,
		"mutated": mutated,
		"restored": restored,
		"repeat_restored": repeat_restored,
		"fixture_path": fixture_path,
		"fixture_restored_to_prior_state": fixture_restored,
		"normal_user_save_touched": false,
		"snapshots": snapshots,
		"saved_signature": saved_signature,
	}
	if not _write_result(result):
		_finish_failure("result write")
		return
	_cleanup()
	print("V13_GUI_SAVE_LOAD_ACCEPTANCE_COMPLETE ", RESULT_URI)
	quit(0 if missing_fixture_rejected and saved and mutated and restored and repeat_restored and fixture_restored else 1)

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
	var created: Dictionary = RouteSession.create_from_game(main, "v13-gui-save-load-acceptance", {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		_finish_failure(str(created.get("reason", "session setup")))
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
	# Freeze normal simulation only after the adapter has built its actual HUD.
	# Signals below still call the production button handlers.
	field.process_mode = Node.PROCESS_MODE_DISABLED
	return field.get_node_or_null("RouteControls") != null

func _move(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 300:
		main._process(0.2)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return false

func _button_with_text(root_node: Node, title: String) -> Button:
	for node in root_node.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == title:
			return button
	return null

func _session_signature(session) -> Dictionary:
	if session == null:
		return {}
	# `to_dict` is JSON-safe and is the same body saved by the production
	# verification fixture API. Normalize it through JSON because the live
	# in-memory path vectors become JSON arrays after the real save/load round
	# trip. Exclude session_id: runtime identity can differ.
	var state: Dictionary = session.to_dict().duplicate(true)
	state.erase("session_id")
	var parser := JSON.new()
	if parser.parse(JSON.stringify(state)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data as Dictionary

func _backup_and_clear_fixture() -> bool:
	fixture_existed = FileAccess.file_exists(fixture_path)
	if fixture_existed:
		var file := FileAccess.open(fixture_path, FileAccess.READ)
		if file == null:
			return false
		fixture_bytes = file.get_buffer(file.get_length())
		file.close()
	else:
		fixture_bytes = PackedByteArray()
	if FileAccess.file_exists(fixture_path):
		return DirAccess.remove_absolute(fixture_path) == OK
	return true

func _restore_prior_fixture() -> bool:
	if fixture_path.is_empty():
		return false
	if fixture_existed:
		if DirAccess.make_dir_recursive_absolute(fixture_path.get_base_dir()) != OK:
			return false
		var file := FileAccess.open(fixture_path, FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(fixture_bytes)
		file.close()
		return true
	if FileAccess.file_exists(fixture_path):
		return DirAccess.remove_absolute(fixture_path) == OK
	return true

func _save_viewport(key: String) -> bool:
	var uri := EVIDENCE_ROOT_URI.path_join("gui_%s.png" % key)
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
	if not fixture_path.is_empty():
		fixture_restored = _restore_prior_fixture()
	_write_result({
		"schema": 1,
		"display_server": DisplayServer.get_name(),
		"actual_viewport": DisplayServer.get_name() == "X11",
		"input_method": "programmatic_button_signal",
		"physical_pointer": false,
		"failure": failure,
		"fixture_restored_to_prior_state": fixture_restored,
		"normal_user_save_touched": false,
		"snapshots": snapshots,
	})
	_cleanup()
	print("V13_GUI_SAVE_LOAD_ACCEPTANCE_FAILED ", reason)
	quit(1)

func _cleanup() -> void:
	if field != null and is_instance_valid(field):
		field.queue_free()
	if main != null and is_instance_valid(main):
		main.queue_free()
