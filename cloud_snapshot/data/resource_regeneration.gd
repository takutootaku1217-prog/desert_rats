class_name ResourceRegeneration
extends RefCounted
## Provisional balance, not a final design decision: one unit / 120 game seconds.
## Ground only. No wall clock, inventory, mission, animal or actor side effects.
const SECONDS_PER_UNIT := 120.0
const VERSION := 1
const KINDS := ["tree", "rock", "vein"]

static func eligible(row: Dictionary) -> bool:
	return row.get("type") == "gather" and row.get("data") is Dictionary and row.data.get("kind") in KINDS and row.data.get("item") == GatherDB.POINTS[row.data.kind].item

static func create(capacity: int, now: float) -> Dictionary:
	return {"version": VERSION, "capacity": capacity, "last": now, "credit": 0.0, "revision": 0}

static func number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func valid(state: Variant, remaining: int, now: float) -> bool:
	if not state is Dictionary or state.size() != 5: return false
	if not state.get("version") is int or state.version != VERSION or not state.get("capacity") is int or state.capacity <= 0: return false
	if not state.get("revision") is int or state.revision < 0: return false
	if not number(state.get("last")) or state.last < 0.0 or state.last > now + 0.00001: return false
	if not number(state.get("credit")) or state.credit < 0.0 or state.credit >= SECONDS_PER_UNIT: return false
	return remaining >= 0 and remaining <= state.capacity and (remaining < state.capacity or state.credit == 0.0)

static func settle(state: Dictionary, remaining: int, now: float, blocked: bool) -> int:
	if not number(now) or now < float(state.last): return remaining
	var delta := now - float(state.last)
	state.last = now
	if remaining >= int(state.capacity):
		state.credit = 0.0
		return remaining
	if blocked: return remaining
	var credit := float(state.credit) + delta
	var restored := mini(int(state.capacity) - remaining, floori((credit + 0.00000001) / SECONDS_PER_UNIT))
	remaining += restored
	state.revision += restored
	state.credit = 0.0 if remaining == int(state.capacity) else maxf(0.0, credit - float(restored) * SECONDS_PER_UNIT)
	return remaining

static func within_footprint(row: Dictionary, footprint: Rect2) -> bool:
	return footprint.has_point(Vector2(float(row.anchor), float(row.data.position.y)))
