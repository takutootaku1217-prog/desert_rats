extends SceneTree
## Contract for the first-region route-study cards.  These cards describe
## existing route/engineering state only; they must not become a second
## WorldTrip authority or mutate the save-shape input.

const WorldMapDB = preload("res://data/world_map.gd")

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _card(cards: Array, id: String) -> Dictionary:
	for card in cards:
		if str(Dictionary(card).get("id", "")) == id:
			return Dictionary(card)
	return {}

func _state(graded: bool, cleared: bool) -> Dictionary:
	return {
		"roads": {"ab": {"graded": graded}, "bd": {"cleared": cleared}},
		"lots": {"b_forest": "wild", "d_yard": "wild"},
		"mines": {"c_quarry": {"cart_shortcut_cleared": false}},
	}

func _run() -> void:
	var blocked := _state(false, false)
	var blocked_before := blocked.duplicate(true)
	var blocked_cards: Array = WorldMapDB.first_region_route_study(blocked)
	_check(blocked == blocked_before, "Route study reads road state without mutating the save-shaped input")
	var safe: Dictionary = _card(blocked_cards, "safe_detour")
	var grade: Dictionary = _card(blocked_cards, "grade_ab")
	var trees: Dictionary = _card(blocked_cards, "clear_bd")
	var risk: Dictionary = _card(blocked_cards, "risk_candidate")
	_check(not safe.is_empty() and bool(safe.get("available", false)) and not bool(safe.get("preview_only", true)), "Stable existing routes are presented as usable comparison choices")
	_check(not grade.is_empty() and str(grade.get("state", "")) == "available" and not Dictionary(grade.get("cost", {})).is_empty(), "Unimproved A-B is shown as an existing paid improvement")
	_check(not trees.is_empty() and str(trees.get("state", "")) == "blocked" and not bool(trees.get("available", true)), "Fallen-tree B-D remains a blocked improvement before clearance")
	_check(not risk.is_empty() and bool(risk.get("preview_only", false)) and not bool(risk.get("available", true)), "Forced/risky travel is visibly future-only and cannot execute in this spike")

	var improved_cards: Array = WorldMapDB.first_region_route_study(_state(true, true))
	var improved_grade: Dictionary = _card(improved_cards, "grade_ab")
	var improved_trees: Dictionary = _card(improved_cards, "clear_bd")
	_check(str(improved_grade.get("state", "")) == "complete" and not bool(improved_grade.get("available", true)), "Graded A-B is read back as completed rather than charging twice")
	_check(str(improved_trees.get("state", "")) == "complete" and bool(improved_trees.get("available", false)), "Cleared B-D is read back as an available direct route")
	print("WORLD MAP ROUTE STUDY failures=", failures)
	quit(1 if failures else 0)
