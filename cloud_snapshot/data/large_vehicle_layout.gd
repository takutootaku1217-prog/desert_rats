class_name LargeVehicleLayout
extends RefCounted
## Coordinate contract for the isolated large-fortress prototype.
## These are world pixels, not source-art pixels.  Every exterior attachment,
## interior deck, wheel, and worker route uses this one contract.

const HULL_RECT := Rect2(-80.0, 106.0, 992.0, 400.0)
const DECK_Y := {1: 462.0, 2: 354.0, 3: 246.0}
## Keep the exterior source aspect ratio, centered inside the interior contract.
const EXTERIOR_HULL_RECT := Rect2(-56.30392, 106.0, 944.60784, 400.0)
## Larger running gear reaches into the supplied fender recesses; five axles
## remain independent, and their tire bottoms share the ordinary ground line.
const WHEEL_RADIUS := 86.0
const WHEEL_CENTERS := [Vector2(60, 476), Vector2(250, 476), Vector2(440, 476), Vector2(610, 476), Vector2(786, 476)]
const LOWER_LADDER_X := 550.0
const UPPER_LADDER_X := LOWER_LADDER_X
const RAMP_TOP := Vector2(904, 462)
const RAMP_FOOT := Vector2(992, 548)
const ROOF_TURRET_MOUNT := Vector2(390, 150)
const SUB_TURRET_MOUNTS := [Vector2(144, 182), Vector2(640, 160), Vector2(824, 170)]
const MAIN_GUN_SIZE := Vector2(560, 187)
const MAIN_GUN_PIVOT := Vector2(432, 161)
const MAIN_GUN_MUZZLE := Vector2(6, 77)
const SUB_TURRET_SIZE := Vector2(166, 95)
const SUB_TURRET_PIVOT := Vector2(112, 76)
const RASTER_HULL := "res://assets/fortress_source/fortress-hull.png"
const RASTER_INTERIOR := "res://assets/fortress_source/fortress-interior.png"
const RASTER_MAIN_GUN := "res://assets/fortress_source/fortress-main-gun.png"
const RASTER_SUB_TURRET := "res://assets/fortress_source/fortress-sub-turret.png"
const RASTER_WHEEL := "res://assets/fortress_source/fortress-wheel.png"

## User-approved industrial pixel-art exterior (2026-10-21).
## Rendering regions remove generator padding without editing the source PNGs.
const PIXEL_HULL := "res://assets/fortress_pixel/armored-body.png"
const PIXEL_WHEEL := "res://assets/fortress_pixel/wheel.png"
const PIXEL_GUN := "res://assets/fortress_pixel/roof-gun.png"
const PIXEL_HULL_REGION := Rect2(32, 4, 1610, 920)
const PIXEL_HULL_RECT := Rect2(8, 4, 880, 502.857143)
const PIXEL_WHEEL_REGION := Rect2(92, 97, 1072, 1072)
const PIXEL_WHEEL_RADIUS := 56.0
const PIXEL_WHEEL_CENTERS := [Vector2(116, 506), Vector2(220, 506), Vector2(416, 506), Vector2(520, 506), Vector2(628, 506), Vector2(744, 506)]
const PIXEL_GUN_REGION := Rect2(216, 272, 1360, 400)
const PIXEL_GUN_SIZE := Vector2(172, 50.588235)
const PIXEL_GUN_PIVOT := Vector2(60, 49.3)
const PIXEL_GUN_MOUNT := Vector2(438, 119)
const PIXEL_SECONDARY_MOUNT := Vector2(748, 119)

## Six supplied RGBA moving parts.  The manifest remains beside these sources;
## regions/pivots below intentionally match it rather than altering the PNGs.
const MOVING_BODY := "res://assets/fortress_moving/body-fixed.png"
## Approved cutaway counterpart of MOVING_BODY. It shares the source canvas;
## only this art contract changes, never the logical vehicle coordinates.
const MOVING_INTERIOR := "res://assets/fortress_moving/interior.png"
const MOVING_WHEEL := "res://assets/fortress_moving/wheel.png"
const MOVING_GUN := "res://assets/fortress_moving/roof-gun.png"
const MOVING_CRANE := "res://assets/fortress_moving/crane.png"
const MOVING_FLAG := "res://assets/fortress_moving/flag.png"
const MOVING_SHUTTER := "res://assets/fortress_moving/garage-shutter.png"
const MOVING_BODY_REGION := Rect2(32, 4, 1610, 920)
const MOVING_WHEEL_REGION := Rect2(92, 97, 1072, 1072)
const MOVING_GUN_REGION := Rect2(216, 272, 1360, 400)
const MOVING_CRANE_REGION := Rect2(80, 75, 1904, 635)
const MOVING_FLAG_REGION := Rect2(152, 92, 1234, 836)
const MOVING_SHUTTER_REGION := Rect2(140, 120, 1588, 608)
const MOVING_BODY_RECT := Rect2(8, 4, 880, 502.857143)
const MOVING_INTERIOR_REGION := MOVING_BODY_REGION
const MOVING_INTERIOR_RECT := MOVING_BODY_RECT
## The normal room/save grid predates the approved cutaway art.  These are
## presentation-only bays measured in MOVING_INTERIOR_RECT world pixels.  Keep
## the logical room slots, worker paths, facility targets, and save data in
## their original coordinate system; rendering projects them through this map.
##
## The default live rooms deliberately follow the baked cutaway: workshop is
## middle-centre, bedroom middle-right, and storage lower-left.  The remaining
## logical slots occupy the other usable bays instead of the exterior/cab.
const MOVING_INTERIOR_SLOT_RECTS := {
	"u3": Rect2(127, 248, 161, 106),
	"u1": Rect2(327, 248, 194, 106),
	"u2": Rect2(567, 248, 235, 106),
	"l3": Rect2(567, 356, 235, 106),
	"l1": Rect2(327, 356, 194, 106),
	"l2": Rect2(127, 356, 161, 106),
}
const MOVING_WHEEL_RADIUS := 56.0
const MOVING_WHEEL_CENTERS := [Vector2(116, 506), Vector2(220, 506), Vector2(416, 506), Vector2(520, 506), Vector2(628, 506), Vector2(744, 506)]
const MOVING_GUN_SIZE := Vector2(172, 50.588235)
const MOVING_GUN_PIVOT := Vector2(60, 49.3)
const MOVING_GUN_MOUNT := Vector2(438, 119)
const MOVING_SECONDARY_MOUNT := Vector2(748, 119)
const MOVING_CRANE_SIZE := Vector2(206, 68.7)
const MOVING_CRANE_PIVOT := Vector2(39, 68)
const MOVING_CRANE_MOUNT := Vector2(644, 119)
const MOVING_FLAG_RECT := Rect2(163, 28, 62, 42)
const MOVING_SHUTTER_RECT := Rect2(600, 364, 170, 81)


static func pixel_exterior_available() -> bool:
	return FileAccess.file_exists(PIXEL_HULL) and FileAccess.file_exists(PIXEL_WHEEL) and FileAccess.file_exists(PIXEL_GUN)


static func moving_parts_available() -> bool:
	return FileAccess.file_exists(MOVING_BODY) and FileAccess.file_exists(MOVING_WHEEL) \
		and FileAccess.file_exists(MOVING_GUN) and FileAccess.file_exists(MOVING_CRANE) \
		and FileAccess.file_exists(MOVING_FLAG) and FileAccess.file_exists(MOVING_SHUTTER)


static func moving_interior_available() -> bool:
	return FileAccess.file_exists(MOVING_INTERIOR)


## Returns the usable cutaway bay for a logical room slot.  This API is visual
## only; callers must never substitute it for Rooms.local_to_world or routes.
static func moving_interior_slot_rect(slot: String) -> Rect2:
	return MOVING_INTERIOR_SLOT_RECTS.get(slot, Rect2())


## Aspect-fit an old logical room representation into its approved cutaway bay,
## centred horizontally and aligned to the floor.  This prevents changed rooms
## and live facilities from covering the cab, outer hull, or ladder corridors.
static func moving_interior_slot_fit_rect(slot: String, logical_rect: Rect2) -> Rect2:
	var target := moving_interior_slot_rect(slot)
	if target.size.x <= 0.0 or target.size.y <= 0.0 or logical_rect.size.x <= 0.0 or logical_rect.size.y <= 0.0:
		return logical_rect
	var scale := minf(target.size.x / logical_rect.size.x, target.size.y / logical_rect.size.y)
	var size := logical_rect.size * scale
	return Rect2(Vector2(target.position.x + (target.size.x - size.x) * 0.5, target.end.y - size.y), size)


static func moving_interior_slot_scale(slot: String, logical_rect: Rect2) -> float:
	if logical_rect.size.x <= 0.0:
		return 1.0
	return moving_interior_slot_fit_rect(slot, logical_rect).size.x / logical_rect.size.x


## Convert a world-display rectangle back to its corresponding source pixels
## in the approved interior PNG. This is presentation-only and is used to
## restore the original deck strip after a bay-local background replacement.
static func moving_interior_source_region_for_display(display_rect: Rect2) -> Rect2:
	if display_rect.size.x <= 0.0 or display_rect.size.y <= 0.0:
		return Rect2()
	var source_per_display := Vector2(
		MOVING_INTERIOR_REGION.size.x / MOVING_INTERIOR_RECT.size.x,
		MOVING_INTERIOR_REGION.size.y / MOVING_INTERIOR_RECT.size.y
	)
	var offset := display_rect.position - MOVING_INTERIOR_RECT.position
	return Rect2(MOVING_INTERIOR_REGION.position + offset * source_per_display, display_rect.size * source_per_display)


## Project a point owned by a logical room into its display-only bay.
static func moving_interior_project_point(slot: String, logical_rect: Rect2, point: Vector2) -> Vector2:
	var fit := moving_interior_slot_fit_rect(slot, logical_rect)
	var scale := moving_interior_slot_scale(slot, logical_rect)
	return fit.position + (point - logical_rect.position) * scale


## Bounds of the supplied, unmodified roof sprites in world display space.
## They are intentionally separate from MOVING_BODY so the cutaway can retain
## its rooms while still reading as the same vehicle as the exterior view.
static func moving_roof_attachment_rects() -> Dictionary:
	return {
		"flag": MOVING_FLAG_RECT,
		"crane": Rect2(MOVING_CRANE_MOUNT - MOVING_CRANE_PIVOT, MOVING_CRANE_SIZE),
		"primary": Rect2(MOVING_GUN_MOUNT - MOVING_GUN_PIVOT, MOVING_GUN_SIZE),
		"secondary": Rect2(MOVING_SECONDARY_MOUNT - MOVING_GUN_PIVOT * 0.535, MOVING_GUN_SIZE * 0.535),
	}

## The lower and middle decks retain the live room/facility slots.  The top
## deck is a real walkable prototype deck with its own targets; it deliberately
## does not alter the player's normal two-deck room save schema.
const TOP_DECK_ROOMS := [
	{"id": "command", "rect": Rect2(72, 164, 214, 72), "anchor": Vector2(184, 246)},
	{"id": "quarters", "rect": Rect2(300, 164, 214, 72), "anchor": Vector2(408, 246)},
	{"id": "service", "rect": Rect2(528, 164, 250, 72), "anchor": Vector2(654, 246)},
]

static func deck_y(floor_i: int) -> float:
	return float(DECK_Y.get(floor_i, DECK_Y[2]))


static func top_room_anchor(index: int) -> Vector2:
	return TOP_DECK_ROOMS[clampi(index, 0, TOP_DECK_ROOMS.size() - 1)]["anchor"]


static func raster_assets_available() -> bool:
	return FileAccess.file_exists(RASTER_HULL) and FileAccess.file_exists(RASTER_INTERIOR) \
		and FileAccess.file_exists(RASTER_MAIN_GUN) and FileAccess.file_exists(RASTER_SUB_TURRET) \
		and FileAccess.file_exists(RASTER_WHEEL)
