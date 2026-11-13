extends SceneTree
## Final v15 evidence after the relay-corridor continuity fix. The v9 capture
## must prove the same dock owns the vehicle, formation, open route, closed
## bypass, and first storage transfer in one actual X11 run.

const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/canyon_parking_vertical_slice_capture_v9.json"
const DOCK := [865, 455]
const OFFSET := [-139, -139]
const GATE := [580, 325]
const BYPASS := [580, 535]
const RESOURCE := [250, 235]

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(RESULT_URI), FileAccess.READ)
	if file == null:
		_check(false, "v9実画面結果が存在する")
		_finish()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var result: Dictionary = parsed if parsed is Dictionary else {}
	var shots: Dictionary = result.get("screenshots", {})
	var relay: Dictionary = shots.get("relay-hud", {})
	var closed: Dictionary = shots.get("closed-bypass-hud", {})
	var delivery: Dictionary = shots.get("first-delivery-hud", {})
	var relay_visual: Dictionary = relay.get("visual", {})
	var closed_visual: Dictionary = closed.get("visual", {})
	var relay_feet: Dictionary = relay_visual.get("crew_feet", {})
	_check(int(result.get("schema", 0)) >= 6 and bool(result.get("actual_viewport", false)), "v9は実X11 viewport結果として保存する")
	_check(not relay.is_empty() and not closed.is_empty() and not delivery.is_empty(), "中継・閉鎖迂回・最初の収納の実画面を記録する")
	_check(str(relay.get("state", {}).get("parking_slot", "")) == "relay" and _point_equals(relay_visual.get("active_unload_contact", []), DOCK) and _point_equals(relay_visual.get("base_rear_offset", []), OFFSET) and _path_equals(relay_visual.get("active_transport_path", []), [DOCK, GATE, RESOURCE]) and _near(relay_feet.get("worker:1", []), DOCK, 80.0) and _near(relay_feet.get("worker:2", []), DOCK, 80.0), "中継の車体・3人編成・主経路は同じdockに一致する")
	_check(bool(closed.get("state", {}).get("gate_closed", false)) and _path_equals(closed_visual.get("active_transport_path", []), [DOCK, BYPASS, RESOURCE]), "閉鎖画面はsession状態とdock起点bypassを同じsnapshotで記録する")
	_check(int(delivery.get("state", {}).get("depot", 0)) > 0 and bool(result.get("conservation_ok", false)), "収納後は車内増加と保存則を記録する")
	_finish()

func _point_equals(raw: Variant, expected: Array) -> bool:
	if not raw is Array:
		return false
	var points: Array = raw as Array
	return points.size() == 2 and int(roundf(float(points[0]))) == int(expected[0]) and int(roundf(float(points[1]))) == int(expected[1])

func _path_equals(raw: Variant, expected: Array) -> bool:
	if not raw is Array:
		return false
	var points: Array = raw as Array
	if points.size() != expected.size():
		return false
	for index in points.size():
		if not _point_equals(points[index], expected[index]):
			return false
	return true

func _near(raw: Variant, expected: Array, maximum: float) -> bool:
	if not raw is Array:
		return false
	var point: Array = raw as Array
	return point.size() == 2 and Vector2(float(point[0]), float(point[1])).distance_to(Vector2(float(expected[0]), float(expected[1]))) <= maximum

func _finish() -> void:
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
