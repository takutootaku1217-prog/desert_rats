extends SceneTree
## Validates the X11 viewport evidence emitted by the narrow v13 GUI
## save/load acceptance capture. This intentionally rejects a claim that a
## programmatic Button signal was a physical pointer click.

const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/v13_gui_save_load_acceptance.json"

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := ProjectSettings.globalize_path(RESULT_URI)
	_check(FileAccess.file_exists(path), "GUI acceptance result JSON exists")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed := JSON.new()
		var error := parsed.parse(file.get_as_text()) if file != null else ERR_CANT_OPEN
		if file != null:
			file.close()
		_check(error == OK and parsed.data is Dictionary, "GUI acceptance result JSON parses")
		if error == OK and parsed.data is Dictionary:
			var result: Dictionary = parsed.data
			_check(str(result.get("display_server", "")) == "X11" and bool(result.get("actual_viewport", false)), "capture came from an actual X11 Godot viewport")
			_check(str(result.get("input_method", "")) == "programmatic_button_signal" and not bool(result.get("physical_pointer", true)), "programmatic Button path is explicitly not reported as a physical pointer click")
			_check(bool(result.get("missing_fixture_rejected", false)), "missing fixture load leaves the session active and displays its failure")
			_check(bool(result.get("saved", false)) and bool(result.get("mutated", false)) and bool(result.get("restored", false)) and bool(result.get("repeat_restored", false)), "save → mutation → load → repeated load is accepted through visible controls")
			_check(bool(result.get("normal_user_save_touched", true)) == false, "acceptance capture does not touch normal user save")
			var snapshots: Dictionary = result.get("snapshots", {})
			_check(snapshots.has("missing") and snapshots.has("mutated") and snapshots.has("restored"), "missing, mutated, and restored viewport screenshots are recorded")
			for key in ["missing", "mutated", "restored"]:
				var uri := str(snapshots.get(key, ""))
				var image := Image.load_from_file(ProjectSettings.globalize_path(uri))
				_check(not uri.is_empty() and image != null and image.get_width() == 1280 and image.get_height() == 720, "%s screenshot is an unmodified native 1280x720 viewport" % key)
	print("== Result: %s ==" % ("PASS" if fails == 0 else "%d failures" % fails))
	quit(1 if fails > 0 else 0)

func _check(ok: bool, description: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", description])
	if not ok:
		fails += 1
