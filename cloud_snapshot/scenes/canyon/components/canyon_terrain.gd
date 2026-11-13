extends Node2D
## Warm canyon floor and readable transport bands; all coordinates are snapped
## to the 1280×720 design grid so this remains crisp at native resolution.

const MAIN_ROUTE_WIDTH := 72.0
const BYPASS_ROUTE_WIDTH := 54.0
const ROAD_MARK_SPACING := 24.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var hub = get_parent()
	if hub == null:
		return
	var canvas_size: Vector2 = hub.view_size
	draw_rect(Rect2(Vector2.ZERO, canvas_size), Color("34283a"))
	draw_rect(Rect2(Vector2(8, 8), canvas_size - Vector2(16, 16)), Color("d8894b"))
	_draw_sand_tiles(canvas_size)
	_draw_transport_bands(hub)
	_draw_sand_clusters()

## The floor remains one contiguous navigable visual plane, but is built from
## small fixed grid marks so the mobile-base scene no longer reads as a single
## color polygon. Larger transparent ground modules add ruts/grass on top.
func _draw_sand_tiles(canvas_size: Vector2) -> void:
	# A fixed 16px field of low-contrast chips, heat cracks and scrub shadows
	# breaks the otherwise uninterrupted sand without using a full-screen image.
	for y in range(20, int(canvas_size.y) - 18, 16):
		for x in range(20, int(canvas_size.x) - 18, 16):
			var column := int(x / 16)
			var row := int(y / 16)
			var cell := (column * 11 + row * 7) % 13
			var p := Vector2(x + (row % 3) * 3, y + (column % 2) * 2)
			if cell < 7:
				var shade: Color = [Color("e7a65e"), Color("d37d46"), Color("bf6e43"), Color("efb66b")][cell % 4]
				draw_rect(Rect2(p, Vector2(2 + cell % 3, 1 + int(cell / 2) % 2)), shade)
			if cell == 2 or cell == 9:
				draw_line(p + Vector2(5, 4), p + Vector2(9, 2), Color("8c4b3c"), 1.0, false)
			if cell == 6:
				_poly([p + Vector2(2, 7), p + Vector2(6, 3), p + Vector2(10, 7), p + Vector2(6, 10)], Color("a45c40"))

func _draw_transport_bands(hub) -> void:
	if _is_mine_path_engineering(hub):
		_draw_mine_path_bands(hub)
		return
	# The same live session segments remain the visual centerline.  The reduced,
	# softened band leaves room for repeated low-contrast ruts instead of a
	# single bright strip that reads as a flat painted polygon.
	var vertical_slice := _is_vertical_slice(hub)
	var bypass_active := is_bypass_route_visible(hub)
	var active_path: Array = active_transport_path(hub)
	var active_width := BYPASS_ROUTE_WIDTH if vertical_slice and bypass_active else MAIN_ROUTE_WIDTH
	var active_edge := Color("8c4d38") if vertical_slice and bypass_active else Color("9c593c")
	var active_fill := Color("c97845") if vertical_slice and bypass_active else Color("d4864a")
	_road(active_path, active_width, active_edge, active_fill)
	# The bypass apron meets the bridge's own short approaches.  In the vertical
	# slice it appears only while that authoritative route is actually active;
	# otherwise it reads as an orphaned old parking slab after the base moves.
	if not vertical_slice and bypass_active:
		_road(_bypass_route_points(hub), BYPASS_ROUTE_WIDTH, Color("8c4d38"), Color("c97845"))
	_draw_route_surface_marks(route_surface_marks(hub))

## Quarry engineering is a display of the session's real waypoint families.
## It intentionally does not create navigation, collision, or a second path
## authority. The fixed mobile base stays at BASE; only crew corridors vary.
func mine_path_visual_routes(hub) -> Dictionary:
	var base: Vector2 = hub.map_point(RecoveryRouteConnectionSession.BASE)
	var step: Vector2 = hub.map_point(RecoveryRouteConnectionSession.MINE_PATH_STEP)
	var detour_entry: Vector2 = hub.map_point(RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR_ENTRY)
	var detour: Vector2 = hub.map_point(RecoveryRouteConnectionSession.MINE_PATH_CART_DETOUR)
	var shortcut: Vector2 = hub.map_point(RecoveryRouteConnectionSession.MINE_PATH_CART_SHORTCUT)
	var relay: Vector2 = hub.map_point(RecoveryRouteConnectionSession.RELAY)
	var gate: Vector2 = hub.map_point(RecoveryRouteConnectionSession.GATE)
	var resource: Vector2 = hub.map_point(RecoveryRouteConnectionSession.RESOURCE)
	var access := str(hub.session.state_summary().get("intermediate_access", "blocked")) if hub != null and "session" in hub and hub.session != null else "blocked"
	# Clearing only applies to the cart's next leg. While a cart is physically
	# traversing the old detour, keep the display highlight on that real route.
	var active_cart_route := "cart_shortcut" if access == "cleared" else "cart_detour"
	if access == "cleared" and hub != null and "session" in hub and hub.session != null:
		for actor in hub.session.actors.values():
			if int(actor.get("work_support", -1)) == GameData.Item.HANDCART and str(actor.get("route", "")) == "cart_detour":
				active_cart_route = "cart_detour"
				break
	return {
		# These split paths mirror the real session roles: carrier BASE→RELAY,
		# then harvest relay→ore.  Drawing both keeps art aligned with the actual
		# handoff rather than inventing a direct base-to-ore cart route.
		"backpack_step": [base, step, relay],
		"backpack_to_ore": [relay, step, gate, resource],
		"cart_detour": [base, detour_entry, detour, relay],
		"cart_detour_to_ore": [relay, detour_entry, detour, gate, resource],
		"cart_shortcut": [base, shortcut, relay],
		"cart_shortcut_to_ore": [relay, shortcut, gate, resource],
		"cart_active": active_cart_route,
		"rubble_visible": access != "cleared",
		"rubble": hub.map_point(RecoveryRouteConnectionSession.MINE_PATH_RUBBLE),
	}

func _draw_mine_path_bands(hub) -> void:
	var routes: Dictionary = mine_path_visual_routes(hub)
	var backpack: Array = Array(routes.get("backpack_step", []))
	var backpack_to_ore: Array = Array(routes.get("backpack_to_ore", []))
	var detour: Array = Array(routes.get("cart_detour", []))
	var detour_to_ore: Array = Array(routes.get("cart_detour_to_ore", []))
	var shortcut: Array = Array(routes.get("cart_shortcut", []))
	var shortcut_to_ore: Array = Array(routes.get("cart_shortcut_to_ore", []))
	# The wide cart route is always usable. The narrow step is visibly thinner,
	# making the support restriction legible without hiding either route.
	_road(detour, 44.0, Color("6f4537"), Color("a75f3d"))
	_road(detour_to_ore, 44.0, Color("6f4537"), Color("a75f3d"))
	_road(backpack, 22.0, Color("655a46"), Color("b58b4d"))
	_road(backpack_to_ore, 22.0, Color("655a46"), Color("b58b4d"))
	if bool(routes.get("rubble_visible", true)):
		# Keep the blocked shortcut readable behind the barricade, but darker than
		# the active detour so it cannot be mistaken for an available cart path.
		_road(shortcut, 32.0, Color("5c4b43"), Color("735a48"))
		_road(shortcut_to_ore, 32.0, Color("5c4b43"), Color("735a48"))
	else:
		_road(shortcut, 44.0, Color("4f6a51"), Color("809b5b"))
		_road(shortcut_to_ore, 44.0, Color("4f6a51"), Color("809b5b"))
	var active_path: Array = Array(routes.get(str(routes.get("cart_active", "cart_detour")), []))
	if active_path.size() >= 2:
		draw_polyline(_packed(active_path), Color("f3d784"), 4.0, false)
	_draw_route_surface_marks(route_surface_marks(hub))

## This one display path follows the same active parking anchor and selected
## main/bypass route as the session. It is not a nav path or second authority.
func active_transport_path(hub) -> Array:
	if _is_mine_path_engineering(hub):
		var routes: Dictionary = mine_path_visual_routes(hub)
		return Array(routes.get(str(routes.get("cart_active", "cart_detour")), []))
	var base: Vector2 = hub.map_point(RecoveryRouteConnectionSession.BASE)
	var relay: Vector2 = hub.map_point(RecoveryRouteConnectionSession.RELAY)
	var gate: Vector2 = hub.map_point(RecoveryRouteConnectionSession.GATE)
	var bypass: Vector2 = hub.map_point(RecoveryRouteConnectionSession.BYPASS)
	var resource: Vector2 = hub.map_point(RecoveryRouteConnectionSession.RESOURCE)
	if not _is_vertical_slice(hub):
		return [base, relay, gate, resource]
	var route_session = hub.session
	var dock: Vector2 = hub.active_unload_contact() if hub.has_method("active_unload_contact") else base
	if bool(route_session.gate_closed):
		return [dock, bypass, resource]
	if str(route_session.state_summary().get("parking_slot", "entry")) == RecoveryRouteConnectionSession.PARKING_RELAY:
		return [dock, gate, resource]
	return [dock, relay, gate, resource]

## This is display-only.  Route selection stays in the bridge session and
## closing the main route makes the same bypass visible again immediately.
func is_bypass_route_visible(hub) -> bool:
	if hub == null or not "session" in hub or hub.session == null:
		return true
	var route_session = hub.session
	if route_session.has_method("is_vertical_slice") and bool(route_session.call("is_vertical_slice")):
		return bool(route_session.gate_closed)
	return true

func _is_vertical_slice(hub) -> bool:
	return hub != null and "session" in hub and hub.session != null and hub.session.has_method("is_vertical_slice") and bool(hub.session.call("is_vertical_slice"))

func _is_mine_path_engineering(hub) -> bool:
	return hub != null and "session" in hub and hub.session != null and hub.session.has_method("is_mine_path_engineering") and bool(hub.session.call("is_mine_path_engineering"))

func route_surface_marks(hub) -> Array[Dictionary]:
	# Reusable 8px rut dashes and 2px edge specks are generated only from live
	# screen-space route segments.  Returning them also lets the scene test
	# guard against a future detached road decoration.
	var marks: Array[Dictionary] = []
	if _is_mine_path_engineering(hub):
		var routes: Dictionary = mine_path_visual_routes(hub)
		var active: Array = Array(routes.get(str(routes.get("cart_active", "cart_detour")), []))
		_append_route_surface_marks(marks, active, 44.0, 4)
		return marks
	var vertical_slice := _is_vertical_slice(hub)
	var bypass_active := is_bypass_route_visible(hub)
	_append_route_surface_marks(marks, active_transport_path(hub), BYPASS_ROUTE_WIDTH if vertical_slice and bypass_active else MAIN_ROUTE_WIDTH, 0)
	if not vertical_slice and bypass_active:
		_append_route_surface_marks(marks, _bypass_route_points(hub), BYPASS_ROUTE_WIDTH, 1)
	return marks

func _bypass_route_points(hub) -> Array:
	if hub.session != null and hub.session.has_method("is_single_worker_demo") and bool(hub.session.call("is_single_worker_demo")) and hub.has_method("single_demo_service_path"):
		return hub.call("single_demo_service_path")
	if _is_vertical_slice(hub):
		var dock: Vector2 = hub.active_unload_contact() if hub.has_method("active_unload_contact") else hub.map_point(RecoveryRouteConnectionSession.BASE)
		return [dock, hub.map_point(RecoveryRouteConnectionSession.BYPASS), hub.map_point(RecoveryRouteConnectionSession.RESOURCE)]
	return [hub.map_point(RecoveryRouteConnectionSession.BASE), hub.map_point(RecoveryRouteConnectionSession.BYPASS)]

func _append_route_surface_marks(marks: Array[Dictionary], points: Array, width: float, phase: int) -> void:
	for segment_index in range(points.size() - 1):
		var a: Vector2 = points[segment_index]
		var b: Vector2 = points[segment_index + 1]
		var offset := b - a
		var length := offset.length()
		if length <= 20.0:
			continue
		var direction := offset / length
		var normal := Vector2(-direction.y, direction.x)
		var distance := 14.0 + float((segment_index + phase) % 3) * 3.0
		var mark_index := 0
		while distance < length - 10.0:
			var center := a + direction * distance
			for side in [-1.0, 1.0]:
				marks.append({
					"position": center + normal * side * width * 0.22,
					"direction": direction,
					"length": 7.0 + float((mark_index + segment_index) % 3) * 2.0,
					"kind": "rut",
				})
				if (mark_index + segment_index + phase) % 2 == 0:
					marks.append({
						"position": center + normal * side * width * 0.50,
						"direction": direction,
						"length": 0.0,
						"kind": "edge",
					})
			distance += ROAD_MARK_SPACING
			mark_index += 1

func _road(points: Array, width: float, edge: Color, fill: Color) -> void:
	var packed := _packed(points)
	draw_polyline(packed, edge, width + 6.0, false)
	draw_polyline(packed, fill, width, false)

func _draw_route_surface_marks(marks: Array[Dictionary]) -> void:
	for mark in marks:
		var position: Vector2 = mark.get("position", Vector2.ZERO)
		if str(mark.get("kind", "")) == "edge":
			draw_circle(position, 1.5, Color(0.53, 0.28, 0.22, 0.52))
			continue
		var direction: Vector2 = mark.get("direction", Vector2.RIGHT)
		var length := float(mark.get("length", 8.0))
		var half := direction * (length * 0.5)
		draw_line(position - half, position + half, Color(0.58, 0.31, 0.22, 0.52), 2.0, false)
		draw_line(position - half, position + half, Color(0.92, 0.61, 0.32, 0.32), 1.0, false)

func _draw_sand_clusters() -> void:
	var flecks := [
		Vector2(72, 270), Vector2(126, 356), Vector2(177, 430), Vector2(330, 284),
		Vector2(380, 508), Vector2(437, 607), Vector2(536, 202), Vector2(605, 267),
		Vector2(670, 188), Vector2(741, 318), Vector2(850, 219), Vector2(922, 330),
		Vector2(1080, 310), Vector2(1165, 403), Vector2(1190, 567), Vector2(1026, 621),
		Vector2(790, 625), Vector2(630, 645), Vector2(257, 610), Vector2(93, 553),
	]
	for index in flecks.size():
		var p: Vector2 = flecks[index]
		var shade := Color("bb6137") if index % 2 == 0 else Color("f5bb6a")
		draw_rect(Rect2(p, Vector2(4 + (index % 3) * 2, 3 + (index % 2) * 2)), shade)
		if index % 3 == 0:
			draw_rect(Rect2(p + Vector2(7, 5), Vector2(3, 2)), Color("7b4338"))
		if index % 4 == 0:
			draw_line(p + Vector2(2, 1), p + Vector2(0, -5), Color("546044"), 1.0, false)

func _poly(points: Array, color: Color) -> void:
	draw_colored_polygon(_packed(points), color)

func _packed(points: Array) -> PackedVector2Array:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(point)
	return packed
