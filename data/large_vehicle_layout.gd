class_name LargeVehicleLayout
extends RefCounted
## Coordinate contract for the isolated large-fortress prototype.
## These are world pixels, not source-art pixels.  Every exterior attachment,
## interior deck, wheel, and worker route uses this one contract.

const HULL_RECT := Rect2(-80.0, 106.0, 992.0, 400.0)
const DECK_Y := {1: 462.0, 2: 354.0, 3: 246.0}
const WHEEL_CENTERS := [Vector2(40, 506), Vector2(296, 506), Vector2(424, 506), Vector2(664, 506), Vector2(792, 506)]
const LOWER_LADDER_X := 484.0
const UPPER_LADDER_X := 636.0
const RAMP_TOP := Vector2(904, 462)
const RAMP_FOOT := Vector2(992, 548)
const ROOF_TURRET_MOUNT := Vector2(286, 86)

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
