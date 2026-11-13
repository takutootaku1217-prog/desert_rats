class_name MobileBaseMotionProof
extends Node2D
## Independent sideview proof. It reuses only the supplied fortress_moving art
## and its static layout contract; no game/session/save node is constructed.

const MotionModel = preload("res://prototypes/recovery_map_lab/sideview_mobile_base_motion/mobile_base_motion_model.gd")
const Layout = preload("res://data/large_vehicle_layout.gd")

const VIEW_SIZE := Vector2(1280, 720)
const ART_ORIGIN := Vector2(196, 80)
const ROAD_TOP_Y := 585.0
const GROUND_Y := 644.0
const FLAG_STRIPS := 24
const EXHAUST_ANCHOR := Vector2(258, 58) # Body-relative roof stack; procedural proof effect only.

var model = MotionModel.new()
var _body: Texture2D
var _wheel: Texture2D
var _gun: Texture2D
var _crane: Texture2D
var _flag: Texture2D
var _shutter: Texture2D


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_body = load(Layout.MOVING_BODY) as Texture2D
	_wheel = load(Layout.MOVING_WHEEL) as Texture2D
	_gun = load(Layout.MOVING_GUN) as Texture2D
	_crane = load(Layout.MOVING_CRANE) as Texture2D
	_flag = load(Layout.MOVING_FLAG) as Texture2D
	_shutter = load(Layout.MOVING_SHUTTER) as Texture2D
	queue_redraw()


func _process(delta: float) -> void:
	model.advance(delta)
	queue_redraw()


func debug_snapshot() -> Dictionary:
	var result := model.snapshot()
	result["body_screen_anchor"] = ART_ORIGIN
	result["road_screen_y"] = GROUND_Y
	result["draw_order"] = ["road", "shadow", "wheels", "body", "shutter", "crane", "gun", "flag", "procedural_exhaust", "lamp_overlay"]
	result["uses_quarter_view"] = false
	result["uses_gameplay_state"] = false
	return result


func debug_part_anchors() -> Dictionary:
	# Read-only test hook for the nearest-filtered anchor contract.  The supplied
	# gun source preserves fractional *size* aspect, but its draw origin must not
	# introduce a sub-pixel sample offset.
	return {
		"gun_origins": [
			_gun_draw_origin(Layout.MOVING_GUN_MOUNT, 1.0, Vector2.ZERO),
			_gun_draw_origin(Layout.MOVING_SECONDARY_MOUNT, 0.535, Vector2.ZERO),
		],
	}


func _draw() -> void:
	if _body == null or _wheel == null or _gun == null or _crane == null or _flag == null or _shutter == null:
		return
	var state := model.snapshot()
	_draw_backdrop(state)
	_draw_road(state)
	_draw_ground_shadow()
	_draw_wheels(state)
	_draw_body_and_fixed_parts(state)
	_draw_flag(state)
	_draw_exhaust(state)
	_draw_lamp_overlay(state)
	_draw_status(state)


func _draw_backdrop(state: Dictionary) -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("13202b"))
	draw_rect(Rect2(Vector2(0, 100), Vector2(VIEW_SIZE.x, 190)), Color("1d3540"))
	draw_rect(Rect2(Vector2(0, 290), Vector2(VIEW_SIZE.x, ROAD_TOP_Y - 290.0)), Color("344452"))
	# Parallax industrial horizon. This is proof-local geometry, not a new asset.
	var distance := float(state.get("distance", 0.0))
	var far_scroll := fposmod(distance * 0.18, 96.0)
	for i in 16:
		var x := -96.0 + float(i) * 96.0 - far_scroll
		var h := 24.0 + float((i * 19) % 5) * 11.0
		draw_rect(Rect2(Vector2(roundi(x), 290.0 - h), Vector2(22, h)), Color("283843"))
		draw_rect(Rect2(Vector2(roundi(x + 4.0), 286.0 - h), Vector2(6, 8)), Color("d58d3e", 0.35))
	draw_line(Vector2(0, ROAD_TOP_Y), Vector2(VIEW_SIZE.x, ROAD_TOP_Y), Color("687179"), 2.0)


func _draw_road(state: Dictionary) -> void:
	draw_rect(Rect2(Vector2(0, ROAD_TOP_Y), Vector2(VIEW_SIZE.x, VIEW_SIZE.y - ROAD_TOP_Y)), Color("7a5532"))
	draw_rect(Rect2(Vector2(0, ROAD_TOP_Y + 24.0), Vector2(VIEW_SIZE.x, VIEW_SIZE.y - ROAD_TOP_Y - 24.0)), Color("5d432d"))
	var scroll := fposmod(float(state.get("distance", 0.0)), 96.0)
	# Road markers and ballast move with the same distance used to turn wheels.
	for lane in 2:
		var y := 612.0 + float(lane) * 22.0
		for i in 16:
			var x := -96.0 + float(i) * 96.0 - scroll
			draw_rect(Rect2(Vector2(roundi(x), y), Vector2(54, 3)), Color("bf8750", 0.82))
	for i in 28:
		var x2 := -48.0 + float(i) * 48.0 - fposmod(float(state.get("distance", 0.0)) * 1.35, 48.0)
		var y2 := 652.0 + float((i * 23) % 5) * 9.0
		draw_rect(Rect2(Vector2(roundi(x2), roundi(y2)), Vector2(5, 3)), Color("ab7844", 0.75))


func _draw_ground_shadow() -> void:
	draw_set_transform(Vector2(640, GROUND_Y), 0.0, Vector2(1.0, 0.13))
	draw_circle(Vector2.ZERO, 430.0, Color(0.01, 0.015, 0.02, 0.52))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wheels(state: Dictionary) -> void:
	var angle := float(state.get("wheel_angle", 0.0))
	var radius := Layout.MOVING_WHEEL_RADIUS
	for raw_center in Layout.MOVING_WHEEL_CENTERS:
		var center: Vector2 = ART_ORIGIN + raw_center
		draw_set_transform(center, angle, Vector2.ONE)
		draw_texture_rect_region(_wheel, Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0)), Layout.MOVING_WHEEL_REGION)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_body_and_fixed_parts(state: Dictionary) -> void:
	# Only sprung body/roof pieces move vertically. Wheel centers stay grounded.
	var sprung := Vector2(0.0, float(state.get("suspension_y", 0.0)))
	draw_texture_rect_region(_body, Rect2(ART_ORIGIN + Layout.MOVING_BODY_RECT.position + sprung, Layout.MOVING_BODY_RECT.size), Layout.MOVING_BODY_REGION)
	draw_texture_rect_region(_shutter, Rect2(ART_ORIGIN + Layout.MOVING_SHUTTER_RECT.position + sprung, Layout.MOVING_SHUTTER_RECT.size), Layout.MOVING_SHUTTER_REGION)
	# Crane, guns, and shutter are intentionally static whole parts. Their source
	# data establishes no safe articulated behavior or garage interaction.
	var crane_rect := Rect2(ART_ORIGIN + Layout.MOVING_CRANE_MOUNT - Layout.MOVING_CRANE_PIVOT + sprung, Layout.MOVING_CRANE_SIZE)
	draw_texture_rect_region(_crane, crane_rect, Layout.MOVING_CRANE_REGION)
	_draw_gun(Layout.MOVING_GUN_MOUNT, 1.0, sprung)
	_draw_gun(Layout.MOVING_SECONDARY_MOUNT, 0.535, sprung)


func _draw_gun(mount: Vector2, scale_: float, sprung: Vector2) -> void:
	var size := Layout.MOVING_GUN_SIZE * scale_
	var at := _gun_draw_origin(mount, scale_, sprung)
	draw_texture_rect_region(_gun, Rect2(at, size), Layout.MOVING_GUN_REGION)


func _gun_draw_origin(mount: Vector2, scale_: float, sprung: Vector2) -> Vector2:
	return (ART_ORIGIN + mount - Layout.MOVING_GUN_PIVOT * scale_ + sprung).round()


func _draw_flag(state: Dictionary) -> void:
	var sprung := Vector2(0.0, float(state.get("suspension_y", 0.0)))
	var source := Layout.MOVING_FLAG_REGION
	var display := Layout.MOVING_FLAG_RECT
	var phase := float(state.get("flag_phase", 0.0))
	# Integer source/destination boundaries prevent fractional-strip shimmer. The
	# right/pole edge receives zero displacement and stays body-anchored.
	for i in FLAG_STRIPS:
		var u := float(i) / float(FLAG_STRIPS)
		var source_x0 := roundi(source.position.x + source.size.x * float(i) / float(FLAG_STRIPS))
		var source_x1 := roundi(source.position.x + source.size.x * float(i + 1) / float(FLAG_STRIPS))
		var dest_x0 := roundi(display.position.x + display.size.x * float(i) / float(FLAG_STRIPS))
		var dest_x1 := roundi(display.position.x + display.size.x * float(i + 1) / float(FLAG_STRIPS))
		var wave := float(roundi(sin(phase + u * 7.0) * 2.0 * (1.0 - u)))
		var src_rect := Rect2(Vector2(source_x0, source.position.y), Vector2(source_x1 - source_x0, source.size.y))
		var dest_rect := Rect2(ART_ORIGIN + Vector2(dest_x0, roundi(display.position.y + wave)) + sprung, Vector2(dest_x1 - dest_x0, display.size.y))
		draw_texture_rect_region(_flag, dest_rect, src_rect)


func _draw_exhaust(state: Dictionary) -> void:
	# No smoke asset exists. These are explicitly procedural puffs derived from
	# model time, so their count/age is independent of render update frequency.
	var elapsed := float(state.get("elapsed_seconds", 0.0))
	var newest := floori(elapsed / MotionModel.EXHAUST_INTERVAL_SECONDS)
	var sprung := Vector2(0.0, float(state.get("suspension_y", 0.0)))
	for i in 3:
		var birth := newest - i
		if birth < 0:
			continue
		var age := elapsed - float(birth) * MotionModel.EXHAUST_INTERVAL_SECONDS
		if age < 0.0 or age > 1.45:
			continue
		var p := ART_ORIGIN + EXHAUST_ANCHOR + sprung + Vector2(-age * 18.0, -age * 34.0)
		var size := float(4 + roundi(age * 10.0))
		draw_rect(Rect2(p.round() - Vector2(size, size) * 0.5, Vector2(size, size)), Color(0.38, 0.42, 0.43, 0.46 * (1.0 - age / 1.45)))
	if str(state.get("phase", "")) == "rolling":
		for wheel_index in [0, 3, 5]:
			var raw_center: Vector2 = Layout.MOVING_WHEEL_CENTERS[wheel_index]
			var dust_x := ART_ORIGIN.x + raw_center.x - 30.0 - fposmod(float(state.get("distance", 0.0)) * 1.7 + float(wheel_index) * 19.0, 38.0)
			draw_rect(Rect2(Vector2(roundi(dust_x), GROUND_Y - 8.0), Vector2(8, 4)), Color(0.76, 0.56, 0.32, 0.36))


func _draw_lamp_overlay(state: Dictionary) -> void:
	# Lamps are baked into body-fixed.png. This low-alpha overlay is a proof-only
	# idle readability cue, not a claimed separable lamp animation asset.
	var alpha := 0.06 + 0.07 * float(state.get("lamp_strength", 0.72))
	var sprung := Vector2(0.0, float(state.get("suspension_y", 0.0)))
	for lamp in [Vector2(159, 143), Vector2(505, 145), Vector2(675, 145), Vector2(505, 344)]:
		draw_circle(ART_ORIGIN + lamp + sprung, 15.0, Color(1.0, 0.58, 0.15, alpha))


func _draw_status(state: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var phase := "ROLLING" if str(state.get("phase", "")) == "rolling" else "PARKED"
	var speed := float(state.get("speed_px_per_second", 0.0))
	draw_string(font, Vector2(42, 48), "SIDEVIEW MOTION PROOF  |  EXISTING PARTS ONLY  |  %s  %.0f px/s" % [phase, speed], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color("f6d58e"))
	draw_string(font, Vector2(42, 76), "single verified side • road scroll + wheels share travel distance • isolated / no gameplay state", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("c9d5d7"))
