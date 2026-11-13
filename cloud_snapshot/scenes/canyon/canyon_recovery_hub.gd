class_name CanyonRecoveryHub
extends Node2D
## C 古い採石場 bridge の表示専用クォータービュー。
## 経路、資源、cargo、保存、Worker の正本は RecoveryRouteConnectionSession 側に残す。

const DESIGN_SIZE := Vector2(1280, 720)
const WALKABLE_HALF_WIDTH := 48.0
## Normal-role formation offsets are authored by the existing session around
## its route centres. Preserve them inside this display-only corridor instead
## of falling back to the old raw mirror just because they are not centreline
## points (for example immediately after relay parking settles).
const VERTICAL_ROUTE_PROJECTION_HALF_WIDTH := 64.0
## v15 presentation-only unload contacts.  These are authored against the
## existing same-facing truck stairs; they do not become route/session data.
const ENTRY_UNLOAD_CONTACT := Vector2(1004, 594)
## Set right of the bridge's near foot so the unchanged same-facing art never
## reads as parked on the deck.  This is a visual dock contact only; the
## authoritative relay source anchor remains in RecoveryRouteConnectionSession.
const RELAY_UNLOAD_CONTACT := Vector2(865, 455)
## The focused demo uses a small, painted service apron left of the vehicle
## instead of drawing its route through the opaque base/cargo artwork.  This
## only projects the real BASE→BYPASS segment; it never changes session paths.
const SINGLE_DEMO_SERVICE_DOCK := Vector2(712, 630)
## This turn keeps the screen-space BASE→BYPASS path within one pixel of the
## source segment's 550px length.  The visual worker therefore does not speed
## up at the bridge merely because the safe apron starts beside the vehicle.
const SINGLE_DEMO_SERVICE_TURN := Vector2(903, 654)
const SINGLE_DEMO_BRIDGE_JOIN := Vector2(580, 500)

var session
var view_size := DESIGN_SIZE
var _base_art_cached := false
var _base_rear_origin := Vector2.ZERO
var _base_front_origin := Vector2.ZERO
var _dock_crate_origin := Vector2.ZERO

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	refresh()

func configure(p_session) -> void:
	session = p_session
	refresh()

func set_view_size(p_view_size: Vector2) -> void:
	if p_view_size.x <= 0.0 or p_view_size.y <= 0.0:
		return
	view_size = Vector2(roundf(p_view_size.x), roundf(p_view_size.y))
	refresh()

func refresh(delta := 0.0) -> void:
	_sync_parking_art()
	queue_redraw()
	for child in get_children():
		if child.has_method("advance"):
			child.call("advance", delta)
		if child.has_method("refresh"):
			child.call("refresh")

## Session is authored left-to-right for the old schematic.  Mirror only its
## presentation so the requested quarry is left/back and the mobile base is
## right/front, without touching any route or cargo coordinate in the session.
func map_point(source: Vector2) -> Vector2:
	return Vector2(roundf(view_size.x - source.x), roundf(source.y))

## The session keeps source-space parking anchors authoritative.  This helper
## is a replaceable visual contract for the stationary entry and relay poses.
func active_unload_contact() -> Vector2:
	return ENTRY_UNLOAD_CONTACT

func mobile_base_visual_offset() -> Vector2:
	return Vector2.ZERO

func _is_vertical_slice() -> bool:
	return session != null and session.has_method("is_vertical_slice") and bool(session.call("is_vertical_slice"))

func _sync_parking_art() -> void:
	var rear := get_node_or_null("BaseRear") as Node2D
	var front := get_node_or_null("BaseFront") as Node2D
	var crate := get_node_or_null("Props/DockCrate") as Node2D
	if rear == null or front == null:
		return
	if not _base_art_cached:
		_base_rear_origin = rear.position
		_base_front_origin = front.position
		_dock_crate_origin = crate.position if crate != null else Vector2.ZERO
		_base_art_cached = true
	var offset := mobile_base_visual_offset()
	rear.position = _base_rear_origin + offset
	front.position = _base_front_origin + offset
	if crate != null:
		crate.position = _dock_crate_origin + offset

func presentation_point_for_actor(actor: Dictionary) -> Vector2:
	var source := Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0)))
	if _is_vertical_slice():
		return _vertical_presentation_point(source, actor)
	var raw := map_point(source)
	if not bool(actor.get("direct_depot_loop", false)):
		return raw
	# The session traverses this exact source-space segment when the gate is
	# closed.  Projecting it to the adjacent service apron keeps one visible
	# worker on painted ground and retains a continuous join at the bridge.
	if _distance_to_segment(source, RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.BYPASS) <= 0.5:
		var service_segment := RecoveryRouteConnectionSession.BYPASS - RecoveryRouteConnectionSession.BASE
		var service_t := clampf((source - RecoveryRouteConnectionSession.BASE).dot(service_segment) / service_segment.length_squared(), 0.0, 1.0)
		return _point_on_polyline(single_demo_service_path(), service_t).round()
	if _distance_to_segment(source, RecoveryRouteConnectionSession.BYPASS, RecoveryRouteConnectionSession.RESOURCE) <= 0.5:
		var bridge_segment := RecoveryRouteConnectionSession.RESOURCE - RecoveryRouteConnectionSession.BYPASS
		var bridge_t := clampf((source - RecoveryRouteConnectionSession.BYPASS).dot(bridge_segment) / bridge_segment.length_squared(), 0.0, 1.0)
		return _point_on_polyline(single_demo_bridge_path(), bridge_t).round()
	return raw

## Regular crew use the original source-space segments, remapped only at the
## active parked dock.  This preserves the session path/cargo authority while
## making the screen endpoint agree with the visible vehicle stairs.
func _vertical_presentation_point(source: Vector2, actor: Dictionary = {}) -> Vector2:
	var relay_parked := str(session.state_summary().get("parking_slot", "entry")) == RecoveryRouteConnectionSession.PARKING_RELAY
	# Carriers and escorts are intentionally parked as a small formation around
	# RELAY after the reposition completes.  Keep those non-moving roles at the
	# authored dock-relative offsets instead of allowing an adjacent departure
	# segment to pull a waiting worker forward.
	if relay_parked and str(actor.get("state", "")) in ["wait_relay", "escort", "capacity_idle", "idle"] and source.distance_to(RecoveryRouteConnectionSession.RELAY) <= VERTICAL_ROUTE_PROJECTION_HALF_WIDTH:
		return (active_unload_contact() + map_point(source) - map_point(RecoveryRouteConnectionSession.RELAY)).round()
	var segments := [
		[RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.RELAY],
		[RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.GATE],
		[RecoveryRouteConnectionSession.GATE, RecoveryRouteConnectionSession.RESOURCE],
		[RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.BYPASS],
		[RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.BYPASS],
		[RecoveryRouteConnectionSession.BYPASS, RecoveryRouteConnectionSession.RESOURCE],
	]
	var closest_distance := INF
	var closest_start := Vector2.ZERO
	var closest_end := Vector2.ZERO
	var closest_t := 0.0
	for segment in segments:
		var source_start: Vector2 = segment[0]
		var source_end: Vector2 = segment[1]
		var length_squared := (source_end - source_start).length_squared()
		if length_squared <= 0.001:
			continue
		var t := clampf((source - source_start).dot(source_end - source_start) / length_squared, 0.0, 1.0)
		var source_centre := source_start.lerp(source_end, t)
		var formation_offset := source - source_centre
		var formation_distance := formation_offset.length()
		if formation_distance > VERTICAL_ROUTE_PROJECTION_HALF_WIDTH:
			continue
		# Before relay parking, retain the established v14-compatible first
		# projection.  Once parked at relay, however, several 64px formation
		# corridors meet at RELAY.  Choosing the geometrically nearest centreline
		# prevents a moving worker from remaining on BASE→RELAY until an arbitrary
		# corridor edge, then snapping to RELAY→GATE or RELAY→BYPASS.
		if relay_parked:
			if formation_distance >= closest_distance:
				continue
			closest_distance = formation_distance
			closest_start = source_start
			closest_end = source_end
			closest_t = t
			continue
		# map_point mirrors source X but the authorship of the dock anchors is
		# independent. Mirror only the actor's local formation offset around
		# that authored centreline so feet stay continuous at a parked dock.
		var mapped_offset := map_point(source) - map_point(source_centre)
		return (_vertical_anchor_point(source_start).lerp(_vertical_anchor_point(source_end), t) + mapped_offset).round()
	if closest_distance < INF:
		var closest_centre := closest_start.lerp(closest_end, closest_t)
		var closest_mapped_offset := map_point(source) - map_point(closest_centre)
		return (_vertical_anchor_point(closest_start).lerp(_vertical_anchor_point(closest_end), closest_t) + closest_mapped_offset).round()
	return map_point(source)

func _vertical_anchor_point(source_anchor: Vector2) -> Vector2:
	if source_anchor.is_equal_approx(RecoveryRouteConnectionSession.BASE):
		return ENTRY_UNLOAD_CONTACT
	if source_anchor.is_equal_approx(RecoveryRouteConnectionSession.RELAY):
		return active_unload_contact() if str(session.state_summary().get("parking_slot", "entry")) == RecoveryRouteConnectionSession.PARKING_RELAY else map_point(source_anchor)
	return map_point(source_anchor)

## Shared by Terrain and capture tests.  It is presentation-only and never
## becomes a session route, collision path, or second movement authority.
func single_demo_service_path() -> Array:
	return [SINGLE_DEMO_SERVICE_DOCK, SINGLE_DEMO_SERVICE_TURN, single_demo_bridge_join()]

func single_demo_bridge_join() -> Vector2:
	return SINGLE_DEMO_BRIDGE_JOIN

func single_demo_bridge_path() -> Array:
	var bridge = get_node_or_null("Bridge")
	if bridge != null and bridge.has_method("presentation_path"):
		return bridge.call("presentation_path", self)
	return [single_demo_bridge_join(), map_point(RecoveryRouteConnectionSession.RESOURCE)]

## Source-space bridge progress is only meaningful on the actual
## BYPASS→RESOURCE segment.  Keeping service-apron movement at -1 prevents a
## capture witness from treating the dock approach as a bridge entrance.
func single_demo_bridge_progress_for_source(source: Vector2) -> float:
	var start := RecoveryRouteConnectionSession.BYPASS
	var end := RecoveryRouteConnectionSession.RESOURCE
	if _distance_to_segment(source, start, end) > 0.5:
		return -1.0
	var segment := end - start
	if segment.length_squared() <= 0.001:
		return -1.0
	return clampf((source - start).dot(segment) / segment.length_squared(), 0.0, 1.0)

func activity_label_for(actor: Dictionary) -> String:
	var state := str(actor.get("state", ""))
	if state == "rescue_move": return "救助へ接近"
	if state == "rescue_hold": return "救助保持"
	if state == "rescue_return": return "救助搬送"
	if state == "rescue_treatment": return "治療待ち"
	if state == "down": return "戦闘不能"
	if state == "harvesting":
		return "採取"
	if state in ["maintenance_move", "maintenance_work"]:
		return "整備"
	if state in ["capacity_idle", "capacity_wait"]:
		return "容量待ち"
	if state in ["to_relay", "to_base", "dock_wait"] and int(actor.get("carry_n", 0)) > 0:
		return "運搬"
	if state in ["safe_wait", "outpost_wait", "injured_wait", "idle", "down"]:
		return "待機"
	if state in ["combat", "outpost_move", "escort"]:
		return "護衛"
	if state in ["to_resource", "to_relay", "to_base", "to_base_empty", "injured_return"]:
		return "歩行"
	return "待機"

## This is an art/navigation declaration only.  It mirrors the existing
## session waypoints and never performs physics or reroutes a Worker.
func walkable_contains(source: Vector2) -> bool:
	var corridor_contains := false
	if session != null and session.has_method("is_mine_path_engineering") and bool(session.call("is_mine_path_engineering")):
		var mine_corridors := [
			[RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.MINE_PATH_STEP],
			[RecoveryRouteConnectionSession.MINE_PATH_STEP, RecoveryRouteConnectionSession.RELAY],
			[RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.MINE_PATH_STEP],
			[RecoveryRouteConnectionSession.MINE_PATH_STEP, RecoveryRouteConnectionSession.GATE],
			[RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR_ENTRY],
			[RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR_ENTRY, RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR],
			[RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR, RecoveryRouteConnectionSession.RELAY],
			[RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR_ENTRY],
			[RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR, RecoveryRouteConnectionSession.GATE],
			[RecoveryRouteConnectionSession.GATE, RecoveryRouteConnectionSession.RESOURCE],
		]
		var shortcut_open := str(session.state_summary().get("intermediate_access", "blocked")) == "cleared"
		if shortcut_open:
			mine_corridors.append([RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.MINE_PATH_CART_SHORTCUT])
			mine_corridors.append([RecoveryRouteConnectionSession.MINE_PATH_CART_SHORTCUT, RecoveryRouteConnectionSession.GATE])
		for corridor in mine_corridors:
			if _distance_to_segment(source, corridor[0], corridor[1]) <= WALKABLE_HALF_WIDTH:
				corridor_contains = true
				break
		var mine_anchors := [RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.MINE_PATH_STEP, RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR_ENTRY, RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR, RecoveryRouteConnectionSession.GATE, RecoveryRouteConnectionSession.RESOURCE]
		if shortcut_open:
			mine_anchors.append(RecoveryRouteConnectionSession.MINE_PATH_CART_SHORTCUT)
		for anchor in mine_anchors:
			if source.distance_to(anchor) <= 58.0:
				corridor_contains = true
				break
		if not corridor_contains:
			return false
		var mine_occupancy = get_node_or_null("Occupancy")
		if mine_occupancy != null and mine_occupancy.has_method("allows_walkable"):
			return bool(mine_occupancy.call("allows_walkable", map_point(source)))
		return true
	var corridors := [
		[RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.RELAY],
		[RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.GATE],
		[RecoveryRouteConnectionSession.GATE, RecoveryRouteConnectionSession.RESOURCE],
		# The unchanged session's closed-gate path moves BASE→BYPASS directly,
		# then crosses the diagonal deck toward RESOURCE.
		[RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.BYPASS],
		[RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.BYPASS],
		[RecoveryRouteConnectionSession.BYPASS, RecoveryRouteConnectionSession.RESOURCE],
	]
	for corridor in corridors:
		if _distance_to_segment(source, corridor[0], corridor[1]) <= WALKABLE_HALF_WIDTH:
			corridor_contains = true
			break
	for anchor in [RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.GATE, RecoveryRouteConnectionSession.BYPASS, RecoveryRouteConnectionSession.RESOURCE]:
		if source.distance_to(anchor) <= 58.0:
			corridor_contains = true
			break
	if not corridor_contains:
		return false
	var occupancy = get_node_or_null("Occupancy")
	if occupancy != null and occupancy.has_method("allows_walkable"):
		return bool(occupancy.call("allows_walkable", map_point(source)))
	return true

func is_integer_render_layout() -> bool:
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back() as Node
		if node is Node2D:
			var n2d: Node2D = node
			if not _is_integer(n2d.position.x) or not _is_integer(n2d.position.y):
				return false
			if not _is_integer(absf(n2d.scale.x)) or not _is_integer(absf(n2d.scale.y)):
				return false
		if node is CanvasItem and not _inherits_nearest(node):
			return false
		for child in node.get_children():
			pending.append(child)
	return true

func _inherits_nearest(item: CanvasItem) -> bool:
	var cursor: Node = item
	while cursor != null:
		if cursor is CanvasItem:
			var canvas_item: CanvasItem = cursor
			if canvas_item.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST:
				return true
			if canvas_item.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
				return false
		cursor = cursor.get_parent()
	return false

func _is_integer(value: float) -> bool:
	return absf(value - roundf(value)) < 0.001

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)

func _point_on_polyline(points: Array, t: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0] as Vector2
	var total := 0.0
	for index in range(points.size() - 1):
		total += (points[index + 1] as Vector2).distance_to(points[index] as Vector2)
	if total <= 0.001:
		return points[0] as Vector2
	var remaining := clampf(t, 0.0, 1.0) * total
	for index in range(points.size() - 1):
		var start: Vector2 = points[index] as Vector2
		var end: Vector2 = points[index + 1] as Vector2
		var length := start.distance_to(end)
		if remaining <= length or index == points.size() - 2:
			return start.lerp(end, 0.0 if length <= 0.001 else remaining / length)
		remaining -= length
	return points.back() as Vector2
