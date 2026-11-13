extends SceneTree
## Post-capture integrity check.  This is intentionally separate from the
## renderer so it can reject a stale/mislabelled PNG+JSON handoff artifact.

const MEASUREMENT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/normal_haul_frame_progression.json"
const CAPTURE_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/normal_haul_frame_render_capture_v11.json"

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _read_json(uri: String) -> Dictionary:
	if not FileAccess.file_exists(uri):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(uri)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}

func _metrics(row: Dictionary) -> Dictionary:
	return Dictionary(row.get("metrics", {})).duplicate(true)

func _run() -> void:
	var measured := _read_json(MEASUREMENT_URI)
	var captured := _read_json(CAPTURE_URI)
	_check(not measured.is_empty() and not captured.is_empty(), "計測JSONと実Viewport capture JSONが存在する")
	_check(str(captured.get("mode", "")) == "normal_roles" and str(captured.get("display_server", "")) == "X11" and bool(captured.get("normal_mode", false)) and not bool(captured.get("normal_user_save_touched", true)), "captureはX11通常分業だけを使い個人saveを変更しない")
	_check(captured.get("selection", {}) == measured.get("selection", {}) and str(captured.get("selection", {}).get("case", "")) == "harvester_frame", "captureの選択理由は計測済み採掘役候補と一致する")
	_check(captured.get("prepared_checkpoint", {}) == measured.get("prepared_checkpoint", {}), "captureは既存進行checkpointを計測結果と同じ前提で記録する")
	var comparison: Dictionary = captured.get("comparison", {})
	_check(comparison.get("baseline", {}) == _metrics(measured.get("baseline", {})) and comparison.get("harvester_frame", {}) == _metrics(measured.get("harvester_frame", {})) and comparison.get("carrier_frame", {}) == _metrics(measured.get("carrier_frame", {})), "captureはbaseline・採掘役・運搬役の全実測値を取り違えない")
	var measured_selected: Dictionary = measured.get("harvester_frame", {})
	var measured_conditions: Dictionary = measured.get("comparability", {})
	_check(captured.get("entry_resources", {}) == measured_selected.get("entry_resources", {}) and captured.get("entry_roles", {}) == measured_selected.get("entry_roles", {}) and int(captured.get("entry_dock_count", -1)) == int(measured_conditions.get("dock_count", -2)) and int(captured.get("entry_seed", -1)) == int(measured_conditions.get("seed", -2)), "capture開始時の資源・全役割・dock・seedは選択済みベンチマークの実条件と一致する")
	var actor: Dictionary = captured.get("entry_actor", {})
	_check(str(actor.get("role", "")) == "harvest" and int(actor.get("work_support", -1)) == GameData.Item.HAUL_FRAME and int(actor.get("carry_limit", 0)) == GameData.HAUL_FRAME_LIMIT, "captureに映す班員は実sessionの採掘役フレーム便5である")
	var loaded: Dictionary = captured.get("loaded_observation", {})
	var depot: Dictionary = captured.get("depot_observation", {})
	_check(int(loaded.get("carried", 0)) > 0 and int(depot.get("depot", 0)) > int(captured.get("depot_before", -1)) and bool(loaded.get("conservation_ok", false)) and bool(depot.get("conservation_ok", false)), "実画面の積載と収納増加は保存則を保つ同じ通常sessionから得る")
	var expected_cost: Dictionary = measured.get("cost", {})
	var actual_cost: Dictionary = captured.get("upgrade", {}).get("cost", {})
	_check(int(actual_cost.get("workbench_wood", -1)) == int(expected_cost.get("workbench", {}).get("wood", -2)) and int(actual_cost.get("haul_frame_wood", -1)) == int(expected_cost.get("haul_frame", {}).get("wood", -2)) and int(actual_cost.get("haul_frame_hide", -1)) == int(expected_cost.get("haul_frame", {}).get("hide", -2)) and int(actual_cost.get("haul_frame_iron", -1)) == int(expected_cost.get("haul_frame", {}).get("iron", -2)) and int(actual_cost.get("smelt_tank_fuel", -1)) == int(expected_cost.get("haul_frame", {}).get("tank_fuel_for_iron", -2)), "captureは既存製作コストを計測結果と同じ値で記録する")
	var png_count := 0
	for uri in captured.get("screenshots", {}):
		var path := ProjectSettings.globalize_path(str(uri))
		var image := Image.load_from_file(path)
		if image != null and image.get_width() == 1280 and image.get_height() == 720:
			png_count += 1
	_check(png_count == 3 and bool(captured.get("conservation_ok", false)), "HUD・積載・収納の無加工1280×720 PNG三枚と最終保存則を確認する")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
