extends SceneTree
## Pure contract for the isolated sideview mobile-base motion proof.
## It intentionally does not construct Main, a route session, or a save.

const Layout = preload("res://data/large_vehicle_layout.gd")
const MODEL_URI := "res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_model.gd"
const SCENE_URI := "res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.tscn"
const RENDERER_URI := "res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_proof.gd"
const CAPTURE_URI := "res://tools/capture_mobile_base_motion_proof.gd"
const REPORT_URI := "res://docs/cloud_handoff/SIDEVIEW_MOBILE_BASE_MOTION_PROOF_V2_VERIFICATION.md"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


func _run() -> void:
	_check(Layout.moving_parts_available(), "motion proof: all verified sideview moving parts exist")
	_check(Layout.MOVING_WHEEL_CENTERS.size() == 6 and _approx(Layout.MOVING_WHEEL_RADIUS, 56.0), "motion proof: six supplied wheel anchors and 56px radius remain authoritative")
	var expected_slots := PackedStringArray(["l1", "l2", "l3", "u1", "u2", "u3"])
	var actual_slots := PackedStringArray()
	for raw_slot in Layout.MOVING_INTERIOR_SLOT_RECTS.keys():
		actual_slots.append(str(raw_slot))
	actual_slots.sort()
	_check(actual_slots == expected_slots, "motion proof: six logical room slots are read-only input, not vehicle state")
	_check(ResourceLoader.exists(MODEL_URI), "motion proof: pure delta-time model exists")
	_check(ResourceLoader.exists(SCENE_URI) and ResourceLoader.exists(RENDERER_URI), "motion proof: isolated Node2D scene and renderer exist")
	_check(ResourceLoader.exists(CAPTURE_URI), "motion proof: bounded direct-viewport capture entry exists")
	if not ResourceLoader.exists(MODEL_URI):
		_finish()
		return
	var model_script = load(MODEL_URI)
	var model = model_script.new()
	_check(model.has_method("advance") and model.has_method("snapshot") and model.has_method("room_slot_ids"), "motion proof: model exposes only proof timing and read-only contracts")
	if not model.has_method("advance") or not model.has_method("snapshot"):
		_finish()
		return
	var initial: Dictionary = model.snapshot()
	_check(str(initial.get("phase", "")) == "parked" and _approx(float(initial.get("distance", -1.0)), 0.0) and _approx(float(initial.get("wheel_angle", -1.0)), 0.0), "motion proof: begins parked with non-rotating wheels")
	model.advance(1.4)
	var parked: Dictionary = model.snapshot()
	var parked_angle := float(parked.get("wheel_angle", -99.0))
	model.advance(0.09)
	var still_parked: Dictionary = model.snapshot()
	_check(_approx(float(still_parked.get("wheel_angle", -98.0)), parked_angle) and _approx(float(still_parked.get("distance", -1.0)), 0.0) and _approx(float(still_parked.get("suspension_y", 99.0)), 0.0), "motion proof: wheels and suspension remain still before travel")
	model.advance(0.02)
	var rolling_start: Dictionary = model.snapshot()
	model.advance(0.25)
	var rolling: Dictionary = model.snapshot()
	_check(str(rolling_start.get("phase", "")) == "rolling" and float(rolling.get("distance", 0.0)) > 0.0 and not _approx(float(rolling.get("wheel_angle", 0.0)), parked_angle), "motion proof: only signed travel advances wheel rotation")
	_check(absf(float(rolling.get("suspension_y", 99.0))) <= 2.0 and not _approx(float(rolling.get("suspension_y", 0.0)), 0.0), "motion proof: running suspension remains visibly small and bounded")
	while float(model.snapshot().get("elapsed_seconds", 0.0)) < 5.0:
		model.advance(1.0 / 60.0)
	var stopped: Dictionary = model.snapshot()
	var stopped_angle := float(stopped.get("wheel_angle", -99.0))
	model.advance(0.30)
	var stopped_later: Dictionary = model.snapshot()
	_check(str(stopped.get("phase", "")) == "parked" and _approx(float(stopped.get("suspension_y", 99.0)), 0.0) and _approx(float(stopped_later.get("wheel_angle", -98.0)), stopped_angle), "motion proof: post-roll stop does not spin wheels or bounce the body")
	var at_30 = model_script.new()
	var at_60 = model_script.new()
	for unused in 180:
		at_30.advance(1.0 / 30.0)
	for unused in 360:
		at_60.advance(1.0 / 60.0)
	var snapshot_30: Dictionary = at_30.snapshot()
	var snapshot_60: Dictionary = at_60.snapshot()
	_check(_approx(float(snapshot_30.get("distance", -1.0)), float(snapshot_60.get("distance", -2.0)), 0.0001) and _approx(float(snapshot_30.get("wheel_angle", -1.0)), float(snapshot_60.get("wheel_angle", -2.0)), 0.0001), "motion proof: 30Hz and 60Hz delta integration end at the same travel and wheel phase")
	var ten_30 = model_script.new()
	var ten_60 = model_script.new()
	for unused in 300:
		ten_30.advance(1.0 / 30.0)
	for unused in 600:
		ten_60.advance(1.0 / 60.0)
	var ten_30_snapshot: Dictionary = ten_30.snapshot()
	var ten_60_snapshot: Dictionary = ten_60.snapshot()
	_check(_approx(float(ten_30_snapshot.get("lamp_strength", -1.0)), float(ten_60_snapshot.get("lamp_strength", -2.0)), 0.0001) and int(ten_30_snapshot.get("exhaust_birth_index", -1)) == int(ten_60_snapshot.get("exhaust_birth_index", -2)) and _approx(float(ten_30_snapshot.get("suspension_y", -9.0)), float(ten_60_snapshot.get("suspension_y", -8.0))), "motion proof: 30Hz and 60Hz also preserve flag/light/exhaust timing and snapped suspension")
	var model_slots: PackedStringArray = model.room_slot_ids()
	model_slots.sort()
	_check(model_slots == expected_slots, "motion proof: renderer/model can report six slots without editing room data")
	if ResourceLoader.exists(SCENE_URI):
		var proof_scene: Node = load(SCENE_URI).instantiate()
		_check(proof_scene is Node2D and proof_scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and proof_scene.get_child_count() == 0, "motion proof: standalone renderer is a nearest-filtered Node2D with no transitive scene children")
		_check(proof_scene.has_method("debug_part_anchors"), "motion proof: renderer exposes integer attachment-anchor diagnostics")
		if proof_scene.has_method("debug_part_anchors"):
			var anchors: Dictionary = proof_scene.call("debug_part_anchors")
			var guns: Array = anchors.get("gun_origins", [])
			var gun_positions_integer := guns.size() == 2
			for raw_position in guns:
				var position: Vector2 = raw_position as Vector2 if raw_position is Vector2 else Vector2.INF
				gun_positions_integer = gun_positions_integer and position == position.round()
			_check(gun_positions_integer, "motion proof: whole gun sprites start at integer nearest-filtered positions")
		proof_scene.free()
	if ResourceLoader.exists(RENDERER_URI):
		var renderer_source := FileAccess.get_file_as_string(RENDERER_URI)
		_check(not renderer_source.contains("scenes/main.tscn") and not renderer_source.contains("RouteSession") and not renderer_source.contains("SaveGame") and not renderer_source.contains("mobile_base.png") and not renderer_source.contains("mobile_base_front.png"), "motion proof: renderer does not couple to gameplay, saves, or fixed quarter-view art")
	if ResourceLoader.exists(CAPTURE_URI):
		var capture_source := FileAccess.get_file_as_string(CAPTURE_URI)
		_check(not capture_source.contains("scenes/main.tscn") and not capture_source.contains("RouteSession") and not capture_source.contains("SaveGame") and capture_source.contains("x11grab"), "motion proof: capture records only the isolated scene through direct X11 input")
	var report_source := FileAccess.get_file_as_string(REPORT_URI)
	_check(report_source.contains("Windows/Godot 4.7.2") and report_source.contains("verified sideview orientation") and report_source.contains("pre-baked rotation") and report_source.contains("atlas."), "motion proof: handoff report preserves Windows, direction-art, and raw-wheel limitations")
	_finish()


func _finish() -> void:
	print("== Result: %s ==" % ("PASS" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
