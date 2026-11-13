class_name CQuarryMineRescueRoutes
extends RefCounted
## Read-only geometry from existing mine corridors. No position snapping,
## implicit crossing junctions, Worker authority or direct-line fallback.
const MEMBERSHIP_TOLERANCE := 0.11

static func edges(session, cart: bool) -> Array:
	var result: Array = [[session.GATE, session.RESOURCE]]
	if cart:
		result.append_array([[session.BASE, session.MINE_PATH_CART_DETOUR_ENTRY], [session.MINE_PATH_CART_DETOUR_ENTRY, session.MINE_PATH_CART_DETOUR], [session.MINE_PATH_CART_DETOUR, session.RELAY], [session.RELAY, session.MINE_PATH_CART_DETOUR_ENTRY], [session.MINE_PATH_CART_DETOUR, session.GATE]])
		if session.intermediate_access == "cleared":
			result.append_array([[session.BASE, session.MINE_PATH_CART_SHORTCUT], [session.MINE_PATH_CART_SHORTCUT, session.RELAY], [session.MINE_PATH_CART_SHORTCUT, session.GATE]])
	else:
		result.append_array([[session.BASE, session.MINE_PATH_STEP], [session.MINE_PATH_STEP, session.RELAY], [session.MINE_PATH_STEP, session.GATE]])
	# Existing entry formation and its first normal leg are finite known edges,
	# not permission to connect an arbitrary current position to a nearby node.
	for id in session.actors:
		var actor: Dictionary = session.actors[id]
		var index := int(actor.get("worker_index", -1))
		if index < 0 or str(id) != "worker:%d" % index:
			continue
		var origin: Vector2 = session.BASE + Vector2(index * 28.0, (index % 2) * 20.0)
		if origin == session.BASE:
			continue
		result.append([session.BASE, origin])
		var entry_cart := int(actor.get("entry_work_support", actor.get("work_support", -1))) == GameData.Item.HANDCART
		if entry_cart != cart or str(actor.get("role", "")) not in ["harvest", "carry"]:
			continue
		var first: Vector2 = session.MINE_PATH_CART_DETOUR_ENTRY if cart else session.MINE_PATH_STEP
		result.append([origin, first])
		if cart and session.intermediate_access == "cleared":
			result.append([origin, session.MINE_PATH_CART_SHORTCUT])
	return result

static func plan(session, actor: Dictionary, destination: Vector2, actor_id := "", target_id := "") -> Dictionary:
	var answer := plan_geometry(session,actor,destination,actor_id,target_id)
	if answer.get("ok",false):
		answer["witness"] = {"schema":1,"session_id":session.session_id,"actor_id":actor_id,"target_id":target_id,
			"origin":Vector2(actor.x,actor.y),"goal":destination,"gear":int(actor.work_support),
			"revision":session.route_revision,"gate_closed":session.gate_closed,"all_routes_closed":session.all_routes_closed,
			"intermediate_access":session.intermediate_access,"source_trace":_trace_copy(session,actor_id),"target_trace":_trace_copy(session,target_id)}
	return answer

static func _trace_copy(session, id: String) -> Dictionary:
	if not session.mine_rescue_traces._rows.has(id): return {"status":"absent"}
	var row: Dictionary = session.mine_rescue_traces._rows[id]
	var result := {"status":"present","gear":row.gear,"points":row.points.duplicate(),"reason":row.reason,"departed":row.departed}
	if row.has("transported_by"):
		result["transported_by"]=row.transported_by
		result["transport_gear"]=row.transport_gear
	return result

## Also used on a private complete-save validation context; never publishes a path.
static func plan_geometry(session, actor: Dictionary, destination: Vector2, actor_id := "", target_id := "") -> Dictionary:
	if not actor_id.is_empty(): session.mine_rescue_traces.observe_actor(actor_id, actor)
	var direct := _canonical_plan(session, actor, destination)
	var start_trail: bool = session.mine_rescue_traces.has_trail(actor_id, actor)
	var target_trail: bool = session.actors.has(target_id) and session.mine_rescue_traces.has_trail(target_id, session.actors[target_id])
	for id in [actor_id, target_id]:
		if session.mine_rescue_traces.needs_anchor(id):
			return {"ok": false, "reason": session.mine_rescue_traces.invalid_reason(id)}
	if session.all_routes_closed or (direct.ok and not start_trail and not target_trail): return direct
	if int(actor.get("work_support", -1)) == GameData.Item.HANDCART:
		return {"ok": false, "reason": "手押し車は徒歩の実移動記録を救助経路に利用できません"}
	var start := Vector2(actor.x, actor.y)
	var start_points: Array = [start]
	var target_points: Array = [destination]
	var segments := edges(session, false)
	if start_trail or _members(start, segments).is_empty():
		var trace: Dictionary = session.mine_rescue_traces.endpoint(session, actor_id, actor)
		if not trace.ok: return trace
		start_points = trace.points
	if target_trail or _members(destination, segments).is_empty():
		if not session.actors.has(target_id): return direct
		var trace: Dictionary = session.mine_rescue_traces.endpoint(session, target_id, session.actors[target_id])
		if not trace.ok: return trace
		target_points = trace.points
	# No trace intersections become junctions. Go via each explicit anchor.
	var proxy := actor.duplicate(true)
	proxy.x = start_points[0].x; proxy.y = start_points[0].y
	var middle := _canonical_plan(session, proxy, target_points[0])
	if not middle.ok: return middle
	var path: Array = []
	for i in range(start_points.size() - 2, -1, -1): path.append([start_points[i].x, start_points[i].y])
	path.append_array(middle.path)
	for i in range(1, target_points.size()): path.append([target_points[i].x, target_points[i].y])
	return {"ok": true, "path": path, "route": "mine_rescue_witnessed_foot"}

static func _canonical_plan(session, actor: Dictionary, destination: Vector2) -> Dictionary:
	if session.all_routes_closed:
		return {"ok": false, "reason": "採石路が閉鎖中です"}
	var start := Vector2(float(actor.x), float(actor.y))
	if not start.is_finite() or not destination.is_finite():
		return {"ok": false, "reason": "救助の現在位置が不正です"}
	var cart := int(actor.get("work_support", -1)) == GameData.Item.HANDCART
	var segments := edges(session, cart)
	var starts := _members(start, segments)
	var ends := _members(destination, segments)
	if starts.is_empty() or ends.is_empty():
		return {"ok": false, "reason": "現在の装備で使える採石路上にいません。段差・瓦礫・経路外を直線で迂回できません"}
	var points: Array[Vector2] = []
	var links: Array = []
	var endpoint_ids: Array = []
	for segment in segments:
		var a := _node(points, links, segment[0])
		var b := _node(points, links, segment[1])
		_join(points, links, a, b)
		endpoint_ids.append([a, b])
	# Start/goal are distinct query vertices, not graph junctions. Projected
	# vertices only join their own segment. The actual coordinates are retained.
	var start_id := points.size()
	points.append(start); links.append({})
	var end_id := points.size()
	points.append(destination); links.append({})
	var start_projections := _attach(points, links, start_id, starts, segments, endpoint_ids)
	var end_projections := _attach(points, links, end_id, ends, segments, endpoint_ids)
	for edge_index in start_projections:
		if end_projections.has(edge_index):
			_join(points, links, start_projections[edge_index], end_projections[edge_index])
	var distance := {start_id: 0.0}
	var previous := {}
	var visited := {}
	while true:
		var current := -1
		var best := INF
		for candidate in distance:
			if not visited.has(candidate) and float(distance[candidate]) < best:
				current = int(candidate); best = float(distance[candidate])
		if current == -1:
			return {"ok": false, "reason": "現在の装備では救助対象まで経路がつながりません"}
		if current == end_id:
			break
		visited[current] = true
		for neighbor in links[current]:
			var next_distance := best + float(links[current][neighbor])
			if next_distance < float(distance.get(neighbor, INF)):
				distance[neighbor] = next_distance
				previous[neighbor] = current
	var reversed: Array = []
	var cursor := end_id
	while cursor != start_id:
		reversed.append([points[cursor].x, points[cursor].y])
		cursor = int(previous[cursor])
	reversed.reverse()
	var path: Array = []
	var last := start
	for point in reversed:
		var next := Vector2(point[0], point[1])
		if next != last:
			path.append(point)
		last = next
	if path.is_empty(): path.append([destination.x, destination.y])
	return {"ok": true, "path": path, "route": "mine_rescue_cart" if cart else "mine_rescue_step"}

static func _members(point: Vector2, segments: Array) -> Array:
	var found: Array = []
	for i in segments.size():
		var segment: Array = segments[i]
		var projected := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		if point.distance_to(projected) <= MEMBERSHIP_TOLERANCE:
			found.append(i)
	# At a visual crossing, the physical lane cannot be inferred from a point.
	# Refuse rather than create a junction. Shared explicit anchors are valid.
	for a in found:
		for b in found:
			if a >= b: continue
			var shared := false
			for endpoint in segments[a]:
				if segments[b].has(endpoint) and point.distance_to(endpoint) <= MEMBERSHIP_TOLERANCE:
					shared = true
			# Collinear overlapping entry staging edges are one physical lane.
			var u: Vector2 = segments[a][1] - segments[a][0]
			var v: Vector2 = segments[b][1] - segments[b][0]
			if not shared and absf(u.normalized().cross(v.normalized())) > 0.0001:
				return []
	return found

static func _node(points: Array[Vector2], links: Array, point: Vector2) -> int:
	var id := points.find(point)
	if id >= 0: return id
	points.append(point); links.append({})
	return points.size() - 1

static func _join(points: Array[Vector2], links: Array, a: int, b: int) -> void:
	links[a][b] = points[a].distance_to(points[b])
	links[b][a] = points[a].distance_to(points[b])

static func _attach(points: Array[Vector2], links: Array, query: int, members: Array, segments: Array, endpoint_ids: Array) -> Dictionary:
	var result := {}
	for i in members:
		var projection := Geometry2D.get_closest_point_to_segment(points[query], segments[i][0], segments[i][1])
		var id := points.size()
		points.append(projection); links.append({})
		_join(points, links, query, id)
		_join(points, links, id, endpoint_ids[i][0])
		_join(points, links, id, endpoint_ids[i][1])
		result[i] = id
	return result
