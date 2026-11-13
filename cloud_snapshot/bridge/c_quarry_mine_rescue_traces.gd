class_name CQuarryMineRescueTraces
extends RefCounted
## Live, bounded provenance. Complete snapshots validate it; never infer it from positions.
const Routes = preload("res://bridge/c_quarry_mine_rescue_routes.gd")
const MAX_POINTS := 8192
const LIMIT_REASON := "移動経路の記録上限に達したため、この位置の安全な救助経路を確認できません"
var _rows := {}
var _plans := {}
var _generation := 0

func _pos(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x), float(actor.y))

func _canonical(session, actor: Dictionary, p: Vector2) -> bool:
	return not Routes._members(p, Routes.edges(session, int(actor.get("work_support", -1)) == GameData.Item.HANDCART)).is_empty()

func anchor_actor(session, id: String) -> void:
	var actor: Dictionary = session.actors[id]
	var point := _pos(actor)
	if _canonical(session, actor, point):
		_rows[id] = {"actor": actor, "gear": int(actor.get("work_support", -1)), "points": [point], "reason": "", "departed": false}

func witness_plan(session, id: String, actor: Dictionary, source := "ordinary", creation_witness: Dictionary = {}) -> void:
	if source == "rescue" and _canonical(session, actor, _pos(actor)) and not has_trail(id, actor) and not needs_anchor(id):
		# Explicit endpoint of an approved canonical plan, not an incidental crossing.
		anchor_actor(session, id)
	_store_plan(session,id,actor,source,creation_witness)

func _store_plan(session, id: String, actor: Dictionary, source: String, creation_witness: Dictionary) -> void:
	_generation += 1
	_plans[id] = {"actor": actor, "path": actor.path.duplicate(true), "index": int(actor.path_index), "position": _pos(actor), "generation": _generation, "source": source, "origin": _pos(actor), "command_state": str(actor.get("state", "")), "revision": session.route_revision, "gear": int(actor.get("work_support", -1))}
	if session.is_region_boss() and actor.state=="outpost_move" and not actor.path.is_empty():
		_plans[id]["combat_target"]=actor.combat_target
		_plans[id]["combat_destination"]=Vector2(actor.path[-1][0],actor.path[-1][1])
	if source == "rescue":
		_plans[id]["witness"] = creation_witness.duplicate(true)
		_plans[id]["correction"] = false

## _advance has moved but end_step has not yet observed that movement. Reuse
## the immutable base witness rather than querying a temporarily stale trail.
func witness_correction(session, id: String, actor: Dictionary) -> void:
	var previous: Dictionary = _plans.get(id,{})
	var proof: Dictionary = previous.get("witness",{}).duplicate(true)
	_store_plan(session,id,actor,"rescue",proof)
	_plans[id]["correction"] = true

func begin_step(session, id: String) -> Dictionary:
	var actor: Dictionary = session.actors[id]
	var state := str(actor.get("state", ""))
	var plan: Dictionary = _plans.get(id, {})
	var trusted: bool = state == "escort" or plan_current(id, actor)
	var goal := Vector2.INF
	var index := int(actor.get("path_index", 0))
	if index >= 0 and index < actor.path.size():
		goal = Vector2(actor.path[index][0], actor.path[index][1])
	return {"actor": actor, "position": _pos(actor), "state": state, "trusted": trusted, "goal": goal, "gear": int(actor.get("work_support", -1)), "generation": int(plan.get("generation", -1)), "source": str(plan.get("source", ""))}

func end_step(session, id: String, step: Dictionary) -> void:
	var actor: Dictionary = session.actors[id]
	if not is_same(step.actor, actor):
		_rows.erase(id)
		return
	if bool(step.trusted) and _plans.has(id) and int(step.generation) == int(_plans[id].generation):
		_plans[id].position = _pos(actor)
		_plans[id].index = int(actor.path_index)
	var before: Vector2 = step.position
	var after := _pos(actor)
	if before == after:
		# Even a stationary tick observes changed equipment/identity.
		_valid(id, actor)
		return
	var allowed := str(step.state) in ["escort", "maintenance_move", "rescue_move", "rescue_return", "to_base_empty", "injured_return", "to_resource", "to_relay", "to_base"]
	allowed=allowed or (session.is_region_boss() and step.state=="outpost_move")
	if not bool(step.trusted) or not allowed or int(step.gear) != int(actor.get("work_support", -1)):
		_invalidate(id, "移動命令の連続性を確認できません")
		return
	if _explicit_anchor(session, actor, after):
		anchor_actor(session, id)
		return
	if str(step.state) not in ["escort", "maintenance_move"] and not (session.is_region_boss() and step.state=="outpost_move") and str(step.source) != "rescue":
		_invalidate(id, "この移動命令は経路外の救助証跡を作れません")
		return
	if int(actor.get("work_support", -1)) == GameData.Item.HANDCART:
		_invalidate(id, "手押し車の経路外移動は救助経路として利用できません")
		return
	if not _rows.has(id) and _explicit_anchor(session, actor, before):
		_rows[id] = {"actor": actor, "gear": int(actor.get("work_support", -1)), "points": [before], "reason": "", "departed": false}
	if not _valid(id, actor, before): return
	if not _canonical(session, actor, after): _rows[id].departed = true
	var points: Array = _rows[id].points
	# Only collapse an exact return to a witnessed vertex. Curves are never
	# simplified into a new chord. Query/path vertices retain exact coordinates.
	if points.size() > 1 and after == points[-2]:
		points.pop_back()
	elif points.size() >= MAX_POINTS:
		_invalidate(id, LIMIT_REASON)
	else:
		points.append(after)

func _invalidate(id: String, reason: String) -> void:
	if _rows.has(id): _rows[id].reason = reason

func _valid(id: String, actor: Dictionary, expected := Vector2.INF) -> bool:
	if not _rows.has(id): return false
	var row: Dictionary = _rows[id]
	if not str(row.reason).is_empty(): return false
	if not is_same(row.actor, actor) or int(row.gear) != int(actor.get("work_support", -1)):
		_invalidate(id, "担当・装備が変更されたため移動経路の記録を利用できません")
		return false
	var position := _pos(actor) if expected == Vector2.INF else expected
	if row.points.is_empty() or row.points[-1] != position:
		_invalidate(id, "現在位置と実移動の記録が一致しません")
		return false
	return true

func endpoint(session, id: String, actor: Dictionary) -> Dictionary:
	if id.is_empty() or not session.actors.has(id) or not is_same(session.actors[id], actor):
		return {"ok": false, "reason": "この位置の移動記録を確認できません"}
	if not _valid(id, actor):
		return {"ok": false, "reason": str(_rows.get(id, {}).get("reason", "この位置には現sessionの実移動記録がありません"))}
	return {"ok": true, "points": _rows[id].points.duplicate()}

func share_carried(session, carrier_id: String, target_id: String) -> void:
	var carrier: Dictionary = session.actors[carrier_id]
	var target: Dictionary = session.actors[target_id]
	if _pos(carrier) != _pos(target) or not _valid(carrier_id, carrier):
		_invalidate(target_id, "搬送経路の記録を確認できません")
		return
	_rows[target_id] = {"actor": target, "gear": int(target.get("work_support", -1)), "points": _rows[carrier_id].points.duplicate(), "reason": "", "departed": bool(_rows[carrier_id].departed), "transported_by": carrier_id, "transport_gear": int(carrier.get("work_support",-1))}

func observe_actor(id: String, actor: Dictionary) -> void:
	_valid(id, actor)

func plan_current(id: String, actor: Dictionary) -> bool:
	var plan: Dictionary = _plans.get(id, {})
	return not plan.is_empty() and is_same(plan.actor, actor) and plan.path == actor.path and int(plan.index) == int(actor.path_index) and plan.position == _pos(actor) and int(plan.gear) == int(actor.get("work_support", -1))

func approved_goal(id: String) -> Vector2:
	var plan: Dictionary = _plans.get(id, {})
	if plan.is_empty() or plan.path.is_empty(): return Vector2.INF
	var last: Array = plan.path[-1]
	return Vector2(last[0], last[1])

func _explicit_anchor(session, actor: Dictionary, point: Vector2) -> bool:
	for edge in Routes.edges(session, int(actor.get("work_support", -1)) == GameData.Item.HANDCART):
		if point == edge[0] or point == edge[1]: return true
	return false

func has_trail(id: String, actor: Dictionary) -> bool:
	return _valid(id, actor) and _rows[id].points.size() > 1

func needs_anchor(id: String) -> bool:
	return _rows.has(id) and bool(_rows[id].get("departed", false)) and not str(_rows[id].reason).is_empty()

func invalid_reason(id: String) -> String:
	return str(_rows.get(id, {}).get("reason", "実移動の記録を確認できません"))
