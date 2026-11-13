class_name CFieldSnapshotOwners
extends RefCounted
const Session = preload("res://bridge/route_connection_session.gd")
const Routes = preload("res://bridge/c_quarry_mine_rescue_routes.gd")

static func capture(s) -> Dictionary:
	for carrier in s.rescue_approach._owned:
		var target = s.rescue_approach._owned[carrier]
		if not s.rescue_approach._mine_binding_current(s,carrier,target): return {}
	var expired := {}
	for id in s.expired_recovery._records:
		var record: Dictionary = s.expired_recovery._records[id]
		if not s.actors.has(id) or (not record.invalid and not is_same(record.actor,s.actors[id])): return {}
		var row := record.duplicate(true)
		row.erase("actor")
		expired[id] = row
	return {"owned":s.rescue_approach._owned.duplicate(true),"treatment":s.rescue_approach._treatment.duplicate(true),"returns":s.rescue_approach._mine_returns.duplicate(true),"expired":expired}

static func number(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func position(a: Dictionary) -> Vector2:
	return Vector2(a.x,a.y)

static func restore(data, s) -> bool:
	if not data is Dictionary or data.size()!=4: return false
	for key in ["owned","treatment","returns","expired"]:
		if not data.get(key) is Dictionary: return false
	if not s.field_frame_exchange.is_empty() or not s.field_tool_swap.is_empty() or not s.return_handcart_exchange.is_empty() or (not s.outpost_enemies.is_empty() and not s.is_region_boss()): return false
	var occupied := {}
	for carrier in data.owned:
		var target = data.owned[carrier]
		if not carrier is String or not target is String or not s.actors.has(carrier) or not s.actors.has(target) or occupied.has(carrier) or occupied.has(target) or carrier==target: return false
		occupied[carrier]=true; occupied[target]=true
		var row: Dictionary = s.rescue_ledger.case_for(target)
		var a: Dictionary = s.actors[carrier]
		if s.all_routes_closed or s.phase not in ["local","recall"] or row.get("carrier")!=carrier or row.get("phase") not in ["assigned","carried"]: return false
		if s.rescue_approach.reserved(s,carrier): return false
		if row.phase=="assigned" and a.state!="rescue_move": return false
		if row.phase=="carried" and (a.state not in ["rescue_hold","rescue_return"] or position(a)!=position(s.actors[target])): return false
		if a.state=="rescue_hold" and (not a.path.is_empty() or a.path_index!=0): return false
		s.rescue_approach._owned[carrier]=target
		s.rescue_approach._mine_bindings[carrier]={"carrier":a,"target":s.actors[target]}
	for id in data.treatment:
		if not id is String or not s.actors.has(id) or occupied.has(id) or not number(data.treatment[id]) or data.treatment[id]<=0.0 or data.treatment[id]>FieldOperations.RESCUE_SECONDS: return false
		occupied[id]=true
		var a: Dictionary = s.actors[id]
		if a.down or a.state!="rescue_treatment" or a.hp<CrewStatusDB.HP_REVIVE_AT or position(a)!=s.BASE or not s.rescue_ledger.case_for(id).is_empty() or not a.path.is_empty(): return false
		s.rescue_approach._treatment[id]=data.treatment[id]
	for id in data.returns:
		if not id is String or not s.actors.has(id) or occupied.has(id) or data.returns[id] not in ["to_base_empty","injured_return"]: return false
		occupied[id]=true
		var a: Dictionary = s.actors[id]
		if a.get("rescue_mine_return")!=true or a.down or a.carry_n!=0 or (a.state!=data.returns[id] and not (a.state=="safe_wait" and a.resume_state==data.returns[id])): return false
		s.rescue_approach._mine_returns[id]=data.returns[id]
	for id in data.expired:
		if not id is String or not s.actors.has(id) or occupied.has(id): return false
		occupied[id]=true
		var a: Dictionary = s.actors[id]
		var row = data.expired[id]
		if not row is Dictionary or not row.get("gear") is int or not row.get("invalid") is bool or row.get("stage") not in ["return","dock","wait"]: return false
		if a.get("expired_self_return")!=true or a.down or not s.rescue_ledger.case_for(id).is_empty(): return false
		if not row.get("revision") is int or row.revision<0 or row.revision>s.route_revision or not row.get("position") is Vector2 or not row.position.is_finite() or not _path(row.get("path")) or not row.get("index") is int or row.index<0 or row.index>row.path.size(): return false
		if row.invalid:
			if a.state!="safe_wait" or a.resume_state!="injured_return": return false
		elif row.gear!=a.work_support: return false
		elif row.stage=="return":
			if a.state not in ["injured_return","safe_wait"] or (a.state=="safe_wait" and a.resume_state!="injured_return") or row.path!=a.path or row.index!=a.path_index or row.position!=position(a): return false
			if a.state=="safe_wait" and (not a.path.is_empty() or a.path_index!=0): return false
		elif row.stage=="dock":
			if position(a)!=s.BASE or a.state not in ["injured_return","dock_wait","capacity_wait"] or a.carry_n<=0 or not a.path.is_empty() or a.path_index!=0: return false
		elif position(a)!=s.BASE or a.state!="injured_wait" or a.carry_n!=0 or not a.path.is_empty() or a.path_index!=0: return false
		var copy: Dictionary = row.duplicate(true)
		copy["actor"]=a
		s.expired_recovery._records[id]=copy
	for id in occupied:
		if s.maintenance_actor_id==id or s.reservations.values().has(id) or s.actors[id].resource_id!="": return false
	for id in s.actors:
		var a: Dictionary=s.actors[id]
		var row: Dictionary=s.rescue_ledger.case_for(id)
		if row.get("phase") in ["assigned","carried"] and data.owned.get(row.carrier)!=id: return false
		if a.state in ["rescue_move","rescue_hold","rescue_return"] and not data.owned.has(id): return false
		if (a.state=="rescue_treatment") != data.treatment.has(id): return false
		if a.has("rescue_mine_return") != data.returns.has(id) or a.has("expired_self_return") != data.expired.has(id): return false
	return true

static func _path(v) -> bool:
	if not v is Array or v.size()>16640: return false
	for point in v:
		if not point is Array or point.size()!=2 or not number(point[0]) or not number(point[1]): return false
	return true

static func has_moving_owner(s,id: String) -> bool:
	return s.rescue_approach._owned.has(id) or s.rescue_approach._mine_returns.has(id) or s.expired_recovery._records.has(id)

static func plan_valid(s,id: String,p: Dictionary) -> bool:
	var a: Dictionary=s.actors[id]
	var goal: Vector2 = s.BASE
	var target_id := ""
	if s.rescue_approach._owned.has(id):
		if a.state not in ["rescue_move","rescue_return"]: return false
		if a.state=="rescue_move":
			target_id=s.rescue_approach._owned[id]
			goal=position(s.actors[target_id])
	elif s.rescue_approach._mine_returns.has(id):
		if a.state not in ["to_base_empty","injured_return","safe_wait"]: return false
	elif s.expired_recovery._records.has(id):
		if s.expired_recovery._records[id].stage!="return" or s.expired_recovery._records[id].invalid: return false
	else: return false
	var witness=p.get("witness")
	if not witness is Dictionary: return false
	for key in ["session_id","actor_id","target_id","intermediate_access"]:
		if not witness.get(key) is String: return false
	if not witness.get("schema") is int or not witness.get("gear") is int or not witness.get("goal") is Vector2 or not witness.goal.is_finite(): return false
	if witness.schema!=1 or witness.get("session_id")!=s.session_id or witness.get("actor_id")!=id or witness.get("target_id")!=target_id or witness.get("goal")!=goal or witness.get("gear")!=a.work_support: return false
	if not witness.get("origin") is Vector2 or not witness.origin.is_finite() or not witness.get("revision") is int or witness.revision<0 or witness.revision>s.route_revision or not witness.get("gate_closed") is bool or not witness.get("all_routes_closed") is bool or witness.all_routes_closed or witness.get("intermediate_access") not in ["blocked","clearing","cleared"]: return false
	if not p.get("origin") is Vector2 or not p.origin.is_finite() or not p.get("correction") is bool or not p.get("revision") is int or p.revision<0 or p.revision>s.route_revision: return false
	var scratch:=Session.new()
	scratch.session_id=s.session_id
	scratch.mine_path_engineering=true
	scratch.actors=s.actors.duplicate(true)
	scratch.gate_closed=witness.gate_closed
	scratch.all_routes_closed=false
	scratch.intermediate_access=witness.intermediate_access
	scratch.route_revision=witness.revision
	var actor: Dictionary=scratch.actors[id]
	actor.x=witness.origin.x;actor.y=witness.origin.y
	if not _restore_witness_trace(scratch,id,witness.get("source_trace")): return false
	if not target_id.is_empty():
		if not _restore_witness_trace(scratch,target_id,witness.get("target_trace")): return false
	elif not witness.get("target_trace") is Dictionary or witness.target_trace!={"status":"absent"}: return false
	var approved: Dictionary=Routes.plan_geometry(scratch,actor,goal,id,target_id)
	if not approved.get("ok",false) or approved.route!=a.route: return false
	if not p.correction:
		if approved.path!=a.path or p.origin!=witness.origin: return false
	else:
		if a.path!=[[goal.x,goal.y]] or p.origin.distance_to(goal)>0.100001: return false
		var prior_start: Vector2=witness.origin if approved.path.size()<2 else Vector2(approved.path[-2][0],approved.path[-2][1])
		if p.origin.distance_to(Geometry2D.get_closest_point_to_segment(p.origin,prior_start,goal))>0.100001: return false
	if a.path.is_empty(): return false
	if a.path_index==a.path.size(): return position(a).distance_to(goal)<=0.100001
	var start: Vector2=p.origin if a.path_index==0 else Vector2(a.path[a.path_index-1][0],a.path[a.path_index-1][1])
	var end:=Vector2(a.path[a.path_index][0],a.path[a.path_index][1])
	return position(a).distance_to(Geometry2D.get_closest_point_to_segment(position(a),start,end))<=0.100001

static func _restore_witness_trace(s,id: String,row) -> bool:
	if not row is Dictionary or not row.get("status") is String: return false
	if row=={"status":"absent"}: return true
	if row.get("status")!="present" or not row.get("gear") is int or not row.get("departed") is bool or not row.get("reason") is String or not row.get("points") is Array or row.points.size()>8192: return false
	for point in row.points:
		if not point is Vector2 or not point.is_finite(): return false
	var a: Dictionary=s.actors[id]
	var cart: bool=row.gear==GameData.Item.HANDCART
	if row.has("transported_by"):
		if not row.transported_by is String or not s.actors.has(row.transported_by) or row.transported_by==id or not row.get("transport_gear") is int or (row.transport_gear!=-1 and row.transport_gear not in GameData.SUPPORT_ITEMS): return false
		cart=row.transport_gear==GameData.Item.HANDCART
	if row.reason.is_empty():
		if row.points.is_empty() or row.gear!=a.work_support or row.points[-1]!=position(a) or Routes._members(row.points[0],Routes.edges(s,cart)).is_empty(): return false
		if cart and row.points.size()>1: return false
	var copy: Dictionary=row.duplicate(true)
	copy.erase("status");copy["actor"]=a
	s.mine_rescue_traces._rows[id]=copy
	return true
