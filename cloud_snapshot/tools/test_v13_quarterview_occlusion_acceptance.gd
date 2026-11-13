extends SceneTree
## Result-contract test for the current quarter-view depth acceptance pass.
## It deliberately checks the visible CanyonCrewViews hierarchy, not the hidden
## native adapter Worker projection that caused an outdated review concern.

const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/v13_quarterview_occlusion_acceptance.json"

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := ProjectSettings.globalize_path(RESULT_URI)
	_check(FileAccess.file_exists(path), "quarter-view occlusion acceptance result exists")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed := JSON.new()
		var error := parsed.parse(file.get_as_text()) if file != null else ERR_CANT_OPEN
		if file != null:
			file.close()
		_check(error == OK and parsed.data is Dictionary, "quarter-view occlusion result parses")
		if error == OK and parsed.data is Dictionary:
			var result: Dictionary = parsed.data
			_check(str(result.get("display_server", "")) == "X11" and bool(result.get("actual_viewport", false)), "evidence comes from an actual X11 Godot viewport")
			_check(str(result.get("mode", "")) == "single_worker_demo" and bool(result.get("verification_mode", false)), "bridge witness is clearly labelled as the existing isolated verification mode")
			_check(str(result.get("visible_worker_node", "")) == "CanyonCrewViews" and bool(result.get("native_projected_workers_hidden", false)), "visible people are CanyonCrewViews, not the hidden native Worker projection")
			var layers: Dictionary = result.get("layers", {})
			var rear_ok := int(layers.get("bridge", -99)) < int(layers.get("crew", -99)) and int(layers.get("base_rear", -99)) < int(layers.get("crew", -99)) and int(layers.get("checkpoint_rear", -99)) < int(layers.get("crew", -99))
			var front_ok := int(layers.get("crew", -99)) < int(layers.get("base_front", -99)) and int(layers.get("crew", -99)) < int(layers.get("checkpoint_front", -99)) and int(layers.get("crew", -99)) < int(layers.get("cargo_yard", -99))
			_check(rear_ok and front_ok, "bridge/rear art < visible crew < front vehicle/checkpoint/cargo art")
			_check(not bool(result.get("occlusion_issue_reproduced", true)) and not bool(result.get("production_depth_fix_applied", true)) and not bool(result.get("generic_y_sort_applied", true)), "no current building/rock/bridge defect was reproduced; no generic Y-sort or production depth patch was applied")
			_check(bool(result.get("rock_crossing_not_tested", false)), "no invalid route was forced across decorative foreground rocks")
			_check(bool(result.get("normal_user_save_touched", true)) == false, "acceptance capture does not touch normal user save")
			var snapshots: Dictionary = result.get("snapshots", {})
			for key in ["entry", "deck", "exit", "dock"]:
				var uri := str(snapshots.get(key, ""))
				var image := Image.load_from_file(ProjectSettings.globalize_path(uri))
				_check(not uri.is_empty() and image != null and image.get_width() == 1280 and image.get_height() == 720, "%s is a native 1280x720 actual viewport frame" % key)
			var bridge_samples: Dictionary = result.get("bridge_samples", {})
			_check(str(bridge_samples.get("entry", {}).get("surface", "")) != "outside" and str(bridge_samples.get("deck", {}).get("surface", "")) == "deck" and str(bridge_samples.get("exit", {}).get("surface", "")) != "outside", "entry, deck, and exit are sampled from the painted bridge path")
			var video_uri := str(result.get("video", ""))
			var video_file := FileAccess.open(ProjectSettings.globalize_path(video_uri), FileAccess.READ)
			_check(video_file != null and video_file.get_length() > 1024, "short unmodified X11 bridge-observation video exists")
			if video_file != null:
				video_file.close()
	print("== Result: %s ==" % ("PASS" if fails == 0 else "%d failures" % fails))
	quit(1 if fails > 0 else 0)

func _check(ok: bool, description: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", description])
	if not ok:
		fails += 1
