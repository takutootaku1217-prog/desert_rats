class_name TravelLanePresentation
extends RefCounted
## Derived, draw-only description of the normal between-region view.
## This owns no route, speed, save, or gameplay state.

const ROAD_PHASES := ["departing", "travel", "arriving", "turning"]

# The travel view has one shared, flat route.  These are presentation
# coordinates only; world-map routing, collision, fuel and saves do not use
# them.  Keeping the fauna feet and vehicle-hunt mount on this same ground line
# prevents the former foreground row from reading as a second lane.
const SINGLE_LANE_TOP := 492.0
const SINGLE_LANE_HEIGHT := 96.0
const TRAVEL_GROUND_Y := 548.0

static func active(game) -> bool:
	return game != null and game.world != null and game.world.active and str(game.world.phase) in ROAD_PHASES


static func travel_ground_y() -> float:
	return TRAVEL_GROUND_Y


## A derived renderer contract for the single between-region route.  It owns
## no simulation state and deliberately exposes neither a foreground shoulder
## nor a centre divider as a second lane.
static func road_layout(game) -> Dictionary:
	if not active(game):
		return {}
	# WorldTrip enters `departing` before the returning crew has been archived.
	# Keep its safety/recall state active, but leave the stopped-site picture in
	# place until the actual horizontal leg starts.  Rendering the route beneath
	# that still-visible site row made preparation look like a second lane.
	if str(game.world.phase) == "departing":
		return {}
	return {
		"strip_count": 1,
		"top": SINGLE_LANE_TOP,
		"height": SINGLE_LANE_HEIGHT,
		"ground_y": TRAVEL_GROUND_Y,
		"has_center_divider": false,
		"has_near_shoulder": false,
	}

## Road presentation owns no route or worker state, but it is the shared answer
## to whether a new field job may be dispatched while the base is in motion.
## Existing workers are recalled by WorldTrip before departure; this only
## prevents a new outside assignment from racing that safety gate.
static func blocks_outdoor_work(game) -> bool:
	return active(game)


## A threat already present in the live simulation selects the wider road
## composition.  It neither creates nor moves an enemy, so it remains safe for
## deterministic presentation tests and normal raids.
static func danger_active(game) -> bool:
	if not active(game):
		return false
	if game.director != null and game.director.has_method("raid_pressing") and game.director.raid_pressing():
		return true
	if game.enemies_root == null:
		return false
	for enemy in game.enemies_root.get_children():
		if is_instance_valid(enemy) and not bool(enemy.get("dead")):
			return true
	return false


## Keep this a small, draw-only vocabulary.  It intentionally does not become
## a combat state machine or a second route topology.
static func composition(game) -> String:
	if not active(game):
		return "stopped"
	return "danger" if danger_active(game) else "normal"

static func phase_label(game) -> String:
	if not active(game):
		return "停車中"
	match str(game.world.phase):
		"departing": return "乗車確認中"
		"travel": return "一本道を走行中"
		"arriving": return "到着確認中"
		"turning": return "帰路へ転回中"
	return "移動中"
