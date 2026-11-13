class_name CFieldSnapshot
extends RefCounted
## Complete-file boundary, separate from permissive legacy fixture migration.
## Ordinary C field, including manual rescue and post-expiry ownership.
## Independent boss combat is supported; optional outpost/vertical/solo remain unsupported.
const Session = preload("res://bridge/route_connection_session.gd")
const Ledger = preload("res://bridge/c_quarry_rescue_ledger.gd")
const Routes = preload("res://bridge/c_quarry_mine_rescue_routes.gd")
const Owners = preload("res://bridge/c_field_snapshot_owners.gd")
const Boss = preload("res://bridge/c_field_boss_snapshot.gd")
const SCHEMA := 2
const MAX_PATH := 16640
const MOVING := ["to_resource","to_relay","to_base","to_base_empty","injured_return","maintenance_move","rescue_move","rescue_return","outpost_move"]

static func capture(g, adapter) -> Dictionary:
	if adapter == null or not is_instance_valid(adapter) or adapter.session == null or not adapter.life_clock.is_current(): return {}
	var s = adapter.session
	var original := []
	for w in g.workers:
		var key: int = w.get_instance_id()
		if not adapter.original_positions.has(key): return {}
		original.append({"position": adapter.original_positions[key], "mode": adapter.original_process_modes[key], "visible": adapter.original_visibilities[key]})
	var traces := {}
	for id in s.mine_rescue_traces._rows:
		var row: Dictionary = s.mine_rescue_traces._rows[id]
		if not s.actors.has(id) or (str(row.reason).is_empty() and not is_same(row.actor, s.actors[id])): return {}
		var copy := row.duplicate(true)
		copy.erase("actor")
		traces[id] = copy
	var plans := {}
	for id in s.mine_rescue_traces._plans:
		var row: Dictionary = s.mine_rescue_traces._plans[id]
		if not s.actors.has(id): return {}
		if s.expired_recovery.owns(id) and s.expired_recovery._records[id].invalid: continue
		if not is_same(row.actor, s.actors[id]): return {}
		# Stale historical witnesses are not active navigation authority.
		if not s.mine_rescue_traces.plan_current(id, s.actors[id]) or (s.actors[id].state not in MOVING and s.actors[id].state != "safe_wait"): continue
		var copy := row.duplicate(true)
		copy.erase("actor")
		plans[id] = copy
	var result := {"schema": SCHEMA, "navigation_schema": 1, "gate_serial": g.mine_arrival_gate._session_serial, "entry_stance": g.mine_arrival_gate._entry_stance, "session": s.to_dict(), "workers": original,
		"traces": traces, "plans": plans,
		"owners": Owners.capture(s)}
	return _paths_codec(result,true)

static func number(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func point(v) -> bool:
	return v is Array and v.size() == 2 and number(v[0]) and number(v[1])

static func path_valid(v, limit := MAX_PATH) -> bool:
	if not v is Array or v.size() > limit: return false
	for p in v:
		if not point(p): return false
	return true

static func prepare(main: Dictionary) -> Dictionary:
	var f = _paths_codec(main.get("field_snapshot"),false)
	if not f is Dictionary or not f.get("schema") is int or f.schema != SCHEMA or not f.get("navigation_schema") is int or f.navigation_schema != 1: return {}
	if not f.get("gate_serial") is int or f.gate_serial < 1: return {}
	if not f.get("session") is Dictionary or not f.get("workers") is Array or not f.get("traces") is Dictionary or not f.get("plans") is Dictionary: return {}
	if not main.get("crew") is Array or f.workers.size() != main.crew.size(): return {}
	if not main.get("operations") is Dictionary or not main.operations.get("rescue_cases") is Dictionary: return {}
	if not f.get("entry_stance") is String or f.entry_stance not in ["", "normal", "alert", "recall"]: return {}
	if f.entry_stance != "" and main.operations.stance != "recall": return {}
	if not main.operations.rescue_cases.is_empty(): return {}
	var source_world: Dictionary = WorldTrip.normalized(main.world,float(main.director.elapsed))
	var data: Dictionary = f.session
	if not data.get("schema") is int:return {}
	var legacy_resource_wait: bool = data.schema == 9
	if data.get("schema") == 9:
		if main.world.get("resource_regeneration_version",0) != 0: return {}
		data = Session.ResourceGrowth.migrate_legacy(data,source_world.locations.get(Session.SOURCE_KEY,{}),float(main.director.elapsed))
		if data.is_empty(): return {}
	if data.schema == 10:
		if data.has("encounter_id") or data.has("encounter_entry"): return {}
		data=data.duplicate(true)
		data.schema=11
		data["encounter_id"]=""
		data["encounter_entry"]={}
	var s := Session.new()
	var template := s.to_dict()
	if data.size() != template.size(): return {}
	for key in template:
		if not data.has(key) or typeof(data[key]) != typeof(template[key]): return {}
		if key not in ["schema", "rescue"]: s.set(key, data[key].duplicate(true) if data[key] is Dictionary or data[key] is Array else data[key])
	if s.session_id != "mine-arrival-%03d" % f.gate_serial: return {}
	if data.schema != Session.SCHEMA_VERSION or s.session_id.is_empty() or s.committed or s.phase not in ["local", "recall", "ready_to_exit"]: return {}
	if not s.mine_path_engineering or s.vertical_slice or (s.outpost_enabled and not s.is_region_boss()) or s.single_worker_demo: return {}
	if s.parking_slot != Session.PARKING_ENTRY or s.intermediate_access not in ["blocked", "clearing", "cleared"]: return {}
	if not number(s.elapsed) or s.elapsed < 0.0 or s.life_clock_paid != s.elapsed or s.life_clock_token.is_empty(): return {}
	if not number(s.entry_director_elapsed) or s.entry_director_elapsed < 0.0: return {}
	if absf(float(main.director.elapsed) - s.entry_director_elapsed - s.life_clock_paid) > 0.00001: return {}
	if main.world.map_profile != WorldMapDB.FIRST_REGION_A or main.world.region != Session.SITE_ID or main.world.phase != "stopped": return {}
	if not _resources_valid(main,s): return {}
	if s.actors.is_empty() or s.actors.size() != main.crew.size(): return {}
	var seen := {}
	for id in s.actors:
		var a = s.actors[id]
		if not id is String or not a is Dictionary or not a.get("worker_index") is int: return {}
		if not _actor_shape(a): return {}
		var i: int = a.worker_index
		if i < 0 or i >= main.crew.size() or id != "worker:%d" % i or seen.has(i): return {}
		seen[i] = true
		var w: Dictionary = main.crew[i].worker
		for key in ["hp", "fatigue", "hunger", "calm", "stress", "x", "y"]:
			if not number(a.get(key)): return {}
		for key in ["hp", "fatigue", "hunger", "calm", "stress", "mental", "down"]:
			if not a.has(key) or w.get(key) != a[key]: return {}
		if not a.get("down") is bool or a.down != (a.hp == 0.0) or a.hp < 0.0 or a.hp > CrewStatusDB.MAX_HP: return {}
		if a.get("name") != w.char_name or a.get("entry_weapon") != w.weapon or a.get("entry_work_support") != w.get("work_support",-1) or a.get("entry_tools") != w.tools: return {}
		for flag in ["expired_self_return","rescue_mine_return"]:
			if a.has(flag) and (not a[flag] is bool or a[flag] != true): return {}
		if not path_valid(a.get("path")) or not a.get("path_index") is int or a.path_index < 0 or a.path_index > a.path.size(): return {}
		if not a.get("carry_n") is int or a.carry_n < 0 or a.get("carry_item") != w.carrying or maxi(1,a.carry_n) != w.carry_n: return {}
		var original = f.workers[i]
		if not original is Dictionary or not original.get("position") is Vector2 or not original.get("mode") is int or original.mode not in [0,1,2,3,4] or not original.get("visible") is bool: return {}
		if w.position != original.position: return {}
	var ledger := Ledger.from_dict(data.rescue, s.actors)
	if not ledger.get("ok", false): return {}
	s.rescue_ledger = ledger.ledger
	for id in s.actors:
		var row := s.rescue_ledger.case_for(id)
		if s.actors[id].down and row.is_empty(): return {}
	# Owner restoration reads enemy reservations, so reject malformed records
	# first. Exposure validation then sees the restored return/medical owners.
	if s.is_region_boss() and not FirstRegionCompletion.enemy_record_valid({"enemies":s.outpost_enemies,"cleared":s.outpost_cleared},s.actors.size()): return {}
	if not Owners.restore(f.get("owners"),s): return {}
	if not Boss.valid(s,source_world):return {}
	if not _owners_valid(s) or not s._single_worker_mode_valid(): return {}
	if s.phase == "ready_to_exit" and not s._local_exit_ready(): return {}
	for ledger_row in s.resource_ledger_by_item().values():
		if not ledger_row.conservation_ok: return {}
	if not s.conservation_ok() or not s._equipment_support_map_authorized() or not s._field_tool_maps_authorized(): return {}
	if not _navigation_valid(f,s): return {}
	if legacy_resource_wait:Session.ResourceGrowth.mark_legacy_waiters(s)
	for id in f.traces:
		var row: Dictionary = f.traces[id].duplicate(true)
		row["actor"] = s.actors[id]
		s.mine_rescue_traces._rows[id] = row
	for id in f.plans:
		var row: Dictionary = f.plans[id].duplicate(true)
		row["actor"] = s.actors[id]
		s.mine_rescue_traces._generation += 1
		row.generation = s.mine_rescue_traces._generation
		s.mine_rescue_traces._plans[id] = row
	return {"session": s, "workers": f.workers.duplicate(true), "gate_serial": f.gate_serial, "entry_stance": f.entry_stance}

static func _navigation_valid(f: Dictionary, s) -> bool:
	for id in f.traces:
		if not s.actors.has(id): return false
		var row = f.traces[id]
		var a: Dictionary = s.actors[id]
		if not row is Dictionary or not row.get("points") is Array or row.points.size() > 8192 or not row.get("reason") is String or not row.get("departed") is bool or not row.get("gear") is int: return false
		for p in row.points:
			if not p is Vector2 or not is_finite(p.x) or not is_finite(p.y): return false
		if row.has("transported_by") or row.has("transport_gear"):
			if not row.get("transported_by") is String or not s.actors.has(row.transported_by) or row.transported_by==id or not row.get("transport_gear") is int or (row.transport_gear!=-1 and row.transport_gear not in GameData.SUPPORT_ITEMS): return false
		if row.reason.is_empty():
			if row.points.is_empty() or row.gear != a.work_support or row.points[-1] != Vector2(a.x,a.y): return false
			var rescue_case: Dictionary = s.rescue_ledger.case_for(id)
			var transported: bool = rescue_case.get("phase") == "carried"
			var cart: bool = row.gear == GameData.Item.HANDCART
			if row.has("transported_by"):
				cart=row.transport_gear==GameData.Item.HANDCART
			if transported:
				var carrier: String = rescue_case.carrier
				if row.get("transported_by") != carrier or row.get("transport_gear") != s.actors[carrier].work_support: return false
				if not f.traces.get(carrier) is Dictionary or not f.traces[carrier].get("points") is Array or not f.traces[carrier].get("reason") is String: return false
				if f.traces[carrier].points != row.points or f.traces[carrier].reason != "": return false
				cart = s.actors[carrier].work_support == GameData.Item.HANDCART
			if Routes._members(row.points[0],Routes.edges(s,cart)).is_empty(): return false
			if cart and row.points.size() > 1: return false
	for id in s.actors:
		var a: Dictionary = s.actors[id]
		if a.state in MOVING and (a.path.is_empty() or not f.plans.has(id)): return false
	for id in f.plans:
		if not s.actors.has(id): return false
		var p = f.plans[id]
		var a: Dictionary = s.actors[id]
		if not p is Dictionary or not path_valid(p.get("path")) or not p.get("index") is int or not p.get("position") is Vector2 or not p.get("gear") is int or not p.get("source") is String: return false
		if p.path != a.path or p.get("index") != a.path_index or p.get("position") != Vector2(a.x,a.y) or p.get("gear") != a.work_support or p.get("source") not in ["ordinary","rescue"]: return false
		if p.source == "ordinary":
			if Owners.has_moving_owner(s,id) or not _ordinary_plan_valid(s,a,p): return false
		elif not Owners.plan_valid(s,id,p): return false
	return true

static func _resources_valid(main: Dictionary, s) -> bool:
	for id in s.reservations:
		if not id is String or not s.reservations[id] is String: return false
	var sources: Dictionary = WorldTrip.normalized(main.world,float(main.director.elapsed)).locations.get(Session.SOURCE_KEY,{})
	var expected := {}
	for id in sources:
		var row: Dictionary = sources[id]
		if row.type == "gather" and (int(row.data.remaining) > 0 or row.has("regeneration")): expected[id] = row.data
	if s.resources.size() != expected.size(): return false
	for id in s.resources:
		var r = s.resources[id]
		if not expected.has(id) or not r is Dictionary or r.size() != (8 if sources[id].has("regeneration") else 5): return false
		for key in ["item","initial","remaining"]:
			if not r.get(key) is int: return false
		if not r.get("kind") is String: return false
		if not Session.ResourceGrowth.valid_resource(r,s.entry_director_elapsed+s.elapsed) or not Session.ResourceGrowth.matches_entry(r,sources[id]): return false
		if r.item != expected[id].item or r.initial != expected[id].remaining or r.remaining < 0 or r.remaining > (int(r.regeneration.capacity) if r.has("regeneration") else r.initial) or r.get("kind") != expected[id].kind or not r.get("reservation") is String: return false
		if r.has("regeneration") and absf(r.regeneration.last-s.entry_director_elapsed-s.elapsed)>0.00001:return false
		if r.reservation != "" and (not s.actors.has(r.reservation) or s.reservations.get(id) != r.reservation): return false
	for id in s.reservations:
		if not s.resources.has(id) or s.resources[id].reservation != s.reservations[id] or not s.actors.has(s.reservations[id]): return false
	for stock in [s.relay_stock,s.depot_stock]:
		for item in stock:
			if not item is int or item not in GameData.Item.values() or not stock[item] is int or stock[item] < 0: return false
	return true

static func _actor_shape(a: Dictionary) -> bool:
	for key in ["worker_index","weapon","entry_weapon","work_support","entry_work_support","entry_gather_rank","carry_limit","carry_item","carry_n","path_index","seen_route_revision","mental"]:
		if not a.get(key) is int: return false
	for key in ["name","role","state","resource_id","wait_reason","resume_state","combat_target","route"]:
		if not a.get(key) is String: return false
	for key in ["entry_gather_ability","entry_hp","entry_fatigue","entry_stress","hp","fatigue","hunger","calm","stress","attack_per_second","weapon_range","x","y","work_left"]:
		if not number(a.get(key)): return false
	for key in ["tools","entry_tools","field_tool_kit","entry_field_tool_kit"]:
		if not a.get(key) is Dictionary: return false
		for slot in a[key]:
			if not slot is String or slot not in GatherDB.SLOTS or not a[key][slot] is int or not GatherDB.TOOLS.has(a[key][slot]) or GatherDB.TOOLS[a[key][slot]].slot != slot: return false
	for key in ["down","direct_depot_loop","presentation_hidden"]:
		if not a.get(key) is bool: return false
	if a.role not in ["harvest","carry","escort"] or a.weapon != a.entry_weapon or a.carry_limit < 1: return false
	var states := ["idle","escort","to_resource","harvesting","to_relay","wait_relay","to_base","to_base_empty","dock_wait","capacity_wait","capacity_idle","down","safe_wait","injured_return","injured_wait","maintenance_move","maintenance_work","rescue_move","rescue_hold","rescue_return","rescue_treatment","outpost_wait","outpost_move","combat"]
	if a.state not in states or (a.resume_state != "" and a.resume_state not in states): return false
	if a.state in ["harvesting","maintenance_work"] and a.work_left < 0.0: return false
	if a.mental < 0 or a.mental > CrewStatusDB.Mental.LIMIT or a.hunger < 0.0 or a.hunger > CrewStatusDB.MAX_HUNGER or a.fatigue < 0.0 or a.fatigue > CrewStatusDB.MAX_FATIGUE or a.calm < 0.0 or a.stress < 0.0: return false
	if (a.carry_item == -1) != (a.carry_n == 0) or (a.carry_item != -1 and a.carry_item not in GameData.Item.values()): return false
	if a.has("path_speed") and (not number(a.path_speed) or a.path_speed <= 0.0): return false
	if a.has("life_move_mult") and (not number(a.life_move_mult) or a.life_move_mult <= 0.0 or a.life_move_mult > 1.0): return false
	return true

static func _owners_valid(s) -> bool:
	if not s.field_frame_exchange.is_empty() or not s.field_tool_swap.is_empty() or not s.return_handcart_exchange.is_empty(): return false
	if s.reposition_target_slot != "" or s.reposition_seconds_left != 0.0 or s.dock_count not in [1,2] or s.route_revision < 0 or s.path_requests < 0: return false
	if s.intermediate_access == "clearing":
		if not s.actors.has(s.maintenance_actor_id): return false
		var a: Dictionary = s.actors[s.maintenance_actor_id]
		if a.role != "escort" or a.down or a.state not in ["maintenance_move","maintenance_work"]: return false
	elif s.maintenance_actor_id != "": return false
	var docked := {}
	for id in s.dock_queue + s.dock_busy.keys():
		if not id is String or not s.actors.has(id) or docked.has(id): return false
		docked[id] = true
		var a: Dictionary = s.actors[id]
		if Vector2(a.x,a.y) != s.BASE or a.down or a.carry_n <= 0 or a.state not in ["dock_wait","rescue_treatment"]: return false
		if s.dock_busy.has(id) and (not number(s.dock_busy[id]) or s.dock_busy[id] <= 0.0 or s.dock_busy[id] > s.DOCK_SECONDS): return false
	if s.dock_busy.size() > s.dock_count: return false
	for id in s.actors:
		var a: Dictionary = s.actors[id]
		if s.all_routes_closed and a.state in ["to_resource","to_relay","to_base","to_base_empty"]: return false
		if a.state.begins_with("maintenance_") and id != s.maintenance_actor_id: return false
		if a.state == "dock_wait" and not docked.has(id): return false
		if not a.field_tool_kit.is_empty() or not a.entry_field_tool_kit.is_empty(): return false
		if a.resource_id != "" and (not s.resources.has(a.resource_id) or s.resources[a.resource_id].reservation != id or s.reservations.get(a.resource_id) != id): return false
	for rid in s.reservations:
		var id = s.reservations[rid]
		if s.actors[id].resource_id != rid or s.actors[id].down: return false
	return true

static func _ordinary_plan_valid(s, a: Dictionary, p: Dictionary) -> bool:
	if not p.get("origin") is Vector2 or not p.origin.is_finite() or not p.get("revision") is int or p.revision < 0 or p.revision > s.route_revision or p.revision != a.seen_route_revision: return false
	var state: String = a.resume_state if a.state == "safe_wait" else a.state
	if not p.get("command_state") is String or state not in MOVING or p.command_state != state: return false
	var expected := []
	var corridor := [s.MINE_PATH_STEP]
	if a.work_support == GameData.Item.HANDCART:
		corridor = [s.MINE_PATH_CART_SHORTCUT] if a.route == "cart_shortcut" else [s.MINE_PATH_CART_DETOUR_ENTRY,s.MINE_PATH_CART_DETOUR]
	if state == "to_resource":
		expected.append_array(corridor)
		expected.append_array([s.GATE,s.RESOURCE])
	elif state == "to_relay":
		if a.role == "harvest":
			expected.append(s.GATE)
			corridor.reverse()
		expected.append_array(corridor)
		expected.append(s.RELAY)
	elif state in ["to_base","to_base_empty"]:
		corridor.reverse()
		expected.append_array(corridor)
		expected.append(s.BASE)
	elif state == "maintenance_move":
		if a.role != "escort": return false
		expected.append(s.MINE_PATH_RUBBLE)
	elif state == "outpost_move":
		expected=Boss.combat_plan(s,a,p)
		if expected.is_empty():return false
	elif state == "injured_return":
		if p.origin.x > s.GATE.x: expected.append(s.BYPASS if a.route == "bypass" else s.GATE)
		expected.append(s.BASE)
	if expected.size() != a.path.size(): return false
	for i in expected.size():
		if Vector2(a.path[i][0],a.path[i][1]) != expected[i]: return false
	var position := Vector2(a.x,a.y)
	if a.path_index == a.path.size(): return not expected.is_empty() and position == expected[-1]
	var previous: Vector2 = p.origin if a.path_index == 0 else expected[a.path_index-1]
	return position.distance_to(Geometry2D.get_closest_point_to_segment(position,previous,expected[a.path_index])) <= Routes.MEMBERSHIP_TOLERANCE

## Chunk only known path-shaped fields; retain the ordinary global safe-array cap.
static func _paths_codec(value, encode: bool):
	if value is Dictionary:
		var result := {}
		for raw_key in value:
			var key = str(raw_key) if raw_key is StringName else raw_key
			var item = value[raw_key]
			if key is String and key == "path" and encode and item is Array and item.size()>4096:
				var chunks := []
				for start in range(0,item.size(),4096): chunks.append(item.slice(start,mini(start+4096,item.size())))
				result[key]={"chunks":chunks,"count":item.size()}
			elif key is String and key == "path" and not encode and item is Dictionary:
				result[key]=_decode_path(item)
			else: result[key]=_paths_codec(item,encode)
		return result
	if value is Array:
		var result := []
		for item in value: result.append(_paths_codec(item,encode))
		return result
	return value

static func _decode_path(row: Dictionary):
	if row.size()!=2 or not row.get("count") is int or row.count<0 or row.count>MAX_PATH or not row.get("chunks") is Array or row.chunks.size()>5: return null
	var result := []
	for chunk in row.chunks:
		if not path_valid(chunk,4096): return null
		result.append_array(chunk)
	return result if result.size()==row.count else null
