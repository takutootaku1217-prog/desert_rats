class_name MobileBaseMotionModel
extends RefCounted
## Pure presentation state for the isolated sideview motion proof.
## This class deliberately owns no Main, session, route, room, inventory, or save data.

const Layout = preload("res://data/large_vehicle_layout.gd")

const PARK_BEFORE_ROLL_SECONDS := 1.5
const ROLL_SECONDS := 3.0
const PARK_AFTER_ROLL_SECONDS := 1.5
const CYCLE_SECONDS := PARK_BEFORE_ROLL_SECONDS + ROLL_SECONDS + PARK_AFTER_ROLL_SECONDS
const SPEED_PX_PER_SECOND := 42.0
const WHEEL_RADIUS := 56.0
const ROLL_DISTANCE := SPEED_PX_PER_SECOND * ROLL_SECONDS
const MAX_SUSPENSION_PX := 2.0
const EXHAUST_INTERVAL_SECONDS := 0.55

var elapsed_seconds := 0.0


func reset() -> void:
	elapsed_seconds = 0.0


func advance(delta: float) -> void:
	# The phase is evaluated analytically in snapshot(), rather than accumulating
	# a frame-dependent wheel delta.  This is equivalent to splitting at each
	# boundary, but produces the same result at 30 Hz and 60 Hz.
	if delta > 0.0:
		elapsed_seconds += delta


func room_slot_ids() -> PackedStringArray:
	# Copy keys only.  The logical six-room contract stays entirely external and
	# is never written by this display proof.
	var ids := PackedStringArray()
	for raw_slot in Layout.MOVING_INTERIOR_SLOT_RECTS.keys():
		ids.append(str(raw_slot))
	return ids


func phase_at(seconds: float = elapsed_seconds) -> String:
	var local := _cycle_time(seconds)
	if local >= PARK_BEFORE_ROLL_SECONDS and local < PARK_BEFORE_ROLL_SECONDS + ROLL_SECONDS:
		return "rolling"
	return "parked"


func travel_distance_at(seconds: float = elapsed_seconds) -> float:
	var safe_seconds := maxf(0.0, seconds)
	var whole_cycles := floorf(safe_seconds / CYCLE_SECONDS)
	var local := safe_seconds - whole_cycles * CYCLE_SECONDS
	var rolling_seconds := clampf(local - PARK_BEFORE_ROLL_SECONDS, 0.0, ROLL_SECONDS)
	return whole_cycles * ROLL_DISTANCE + rolling_seconds * SPEED_PX_PER_SECOND


func wheel_angle_at(seconds: float = elapsed_seconds) -> float:
	return fposmod(travel_distance_at(seconds) / WHEEL_RADIUS, TAU)


func suspension_at(seconds: float = elapsed_seconds) -> float:
	if phase_at(seconds) != "rolling":
		return 0.0
	var roll_time := _rolling_time(seconds)
	# This moves only the sprung body/roof assembly. Wheels remain on the ground.
	return float(roundi(sin(roll_time * 15.0) * MAX_SUSPENSION_PX))


func snapshot() -> Dictionary:
	var local := _cycle_time(elapsed_seconds)
	var rolling := phase_at(elapsed_seconds) == "rolling"
	var distance := travel_distance_at(elapsed_seconds)
	return {
		"elapsed_seconds": elapsed_seconds,
		"cycle_seconds": local,
		"phase": "rolling" if rolling else "parked",
		"speed_px_per_second": SPEED_PX_PER_SECOND if rolling else 0.0,
		"distance": distance,
		"road_scroll_x": -distance,
		"wheel_angle": wheel_angle_at(elapsed_seconds),
		"suspension_y": suspension_at(elapsed_seconds),
		"flag_phase": elapsed_seconds * 5.0,
		"lamp_strength": 0.72 + 0.18 * sin(elapsed_seconds * 3.0),
		"exhaust_birth_index": floori(elapsed_seconds / EXHAUST_INTERVAL_SECONDS),
		"side_direction": "verified_single_sideview",
		"room_slots": room_slot_ids(),
	}


func _cycle_time(seconds: float) -> float:
	return fposmod(maxf(0.0, seconds), CYCLE_SECONDS)


func _rolling_time(seconds: float) -> float:
	return clampf(_cycle_time(seconds) - PARK_BEFORE_ROLL_SECONDS, 0.0, ROLL_SECONDS)
