class_name CQuarryExpiredRecovery
extends RefCounted
## Live post-expiry self-return. Shares existing time/HP values, never medical fees.
## This owner is separate from manual treatment; only complete snapshots restore it.
const Routes = preload("res://bridge/c_quarry_mine_rescue_routes.gd")
var _records := {}

func owns(id: String) -> bool:
	return _records.has(id)

func _pos(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x), float(actor.y))

func consume_due(session) -> void:
	for id in session.actors:
		if owns(id) or session.rescue_ledger.case_for(id).get("phase") != "recovery_due": continue
		var actor: Dictionary = session.actors[id]
		if not session.rescue_approach._position_valid(session, id): continue
		if not session.rescue_ledger.consume_recovery_due(id, session.actors): continue
		actor.down = false
		actor.hp = CrewStatusDB.HP_REVIVE_AT
		actor.expired_self_return = true
		_records[id] = {"actor": actor, "gear": int(actor.get("work_support", -1)), "stage": "return", "invalid": false}
		repath(session, id)
		session._log("%s は暫定の長期行動不能から回復。入口へ自力帰還" % id)

func _current(session, id: String) -> bool:
	if not owns(id): return false
	var row: Dictionary = _records[id]
	return session.actors.has(id) and is_same(row.actor, session.actors[id]) and int(row.gear) == int(session.actors[id].get("work_support", -1)) and not row.invalid

func _stop(session, id: String, reason: String, invalid := false) -> void:
	var row: Dictionary = _records[id]
	row.invalid = bool(row.invalid) or invalid
	if not session.actors.has(id): return
	var actor: Dictionary = session.actors[id]
	actor.state = "safe_wait"
	actor.resume_state = "injured_return"
	actor.wait_reason = reason

func _bind(actor: Dictionary, row: Dictionary) -> void:
	row.path = actor.path.duplicate(true)
	row.index = int(actor.path_index)
	row.position = _pos(actor)

func repath(session, id: String) -> void:
	if not _current(session, id):
		_stop(session, id, "回復後の担当・装備が変更されたため帰還を停止しました", true)
		return
	var actor: Dictionary = session.actors[id]
	var row: Dictionary = _records[id]
	if row.stage != "return": return
	if row.has("position") and (row.position != _pos(actor) or row.get("path") != actor.path or int(row.get("index", -1)) != int(actor.path_index)):
		_stop(session, id, "回復後の位置・経路が変更されたため再計画を拒否しました", true)
		return
	row.revision = session.route_revision
	actor.path = []; actor.path_index = 0
	_bind(actor, row)
	if session.all_routes_closed:
		_stop(session, id, "経路閉鎖中。回復後の自力帰還を待機しています")
		return
	var path: Array = []
	var creation_witness := {}
	if session.mine_path_engineering:
		var plan: Dictionary = Routes.plan(session, actor, session.BASE, id)
		if not plan.ok:
			_stop(session, id, str(plan.reason))
			return
		path = plan.path
		creation_witness = plan.get("witness",{})
		actor.route = plan.route
	else:
		if float(actor.x) > session.GATE.x:
			path.append(session._point_array(session.BYPASS if session.gate_closed else session.GATE))
		path.append(session._point_array(session.BASE))
	actor.state = "injured_return"; actor.resume_state = ""
	actor.wait_reason = "長期行動不能から回復。入口へ自力帰還中（暫定）"
	actor.path = path; actor.path_index = 0
	actor.path_speed = session.MOVE_SPEED if session.mine_path_engineering else session._local_travel_speed()
	actor.seen_route_revision = session.route_revision
	if session.mine_path_engineering: session.mine_rescue_traces.witness_plan(session, id, actor, "rescue", creation_witness)
	_bind(actor, row)
	session.path_requests += 1

func update_actor(session, id: String, delta: float) -> void:
	if not _current(session, id):
		_stop(session, id, "回復後の担当・装備が変更されたため帰還を停止しました", true)
		return
	var actor: Dictionary = session.actors[id]
	var row: Dictionary = _records[id]
	if row.stage == "wait": return
	if row.stage == "dock":
		if not dock_ready(session, id): return
		if int(actor.carry_n) > 0 and (not session.vertical_slice or session._depot_room_for(int(actor.carry_item)) > 0): session._enqueue_dock(id)
		return
	if actor.state == "safe_wait":
		if not session.all_routes_closed and int(row.get("revision", -1)) != session.route_revision: repath(session, id)
		return
	if actor.state != "injured_return" or row.get("path") != actor.path or int(row.get("index", -1)) != int(actor.path_index) or row.get("position") != _pos(actor):
		_stop(session, id, "回復後の位置・経路順序が変更されたため帰還を停止しました", true)
		return
	if session.all_routes_closed:
		repath(session, id)
		return
	var arrived: bool = session._advance(actor, delta)
	_bind(actor, row)
	if not arrived: return
	if _pos(actor) != session.BASE:
		actor.path = [session._point_array(session.BASE)]; actor.path_index = 0
		if session.mine_path_engineering: session.mine_rescue_traces.witness_correction(session, id, actor)
		_bind(actor, row)
		return
	actor.path = []; actor.path_index = 0; actor.resume_state = ""
	if int(actor.carry_n) > 0:
		row.stage = "dock"
		session._enqueue_dock(id)
	else:
		finish_dock(session, id)

func finish_dock(session, id: String) -> void:
	if not _current(session, id): return
	var actor: Dictionary = session.actors[id]
	if _pos(actor) != session.BASE or int(actor.carry_n) != 0: return
	_records[id].stage = "wait"
	actor.state = "injured_wait"
	actor.wait_reason = "回復後に入口へ帰還。低HPのため撤退・休息待ち（暫定）"

func observe_down(id: String, actor: Dictionary) -> void:
	if owns(id) and is_same(_records[id].actor, actor):
		_records.erase(id)
		actor.erase("expired_self_return")

func exit_ready(session) -> bool:
	for id in _records:
		if not _current(session, id): return false
		var actor: Dictionary = session.actors[id]
		if _records[id].stage != "wait" or _pos(actor) != session.BASE or bool(actor.down) or int(actor.carry_n) != 0 or actor.state != "injured_wait": return false
	return true

func dock_ready(session, id: String) -> bool:
	if not _current(session, id):
		_stop(session, id, "回復後の荷物搬入の担当・装備を確認できません", true)
		return false
	var actor: Dictionary = session.actors[id]
	if _records[id].stage != "dock" or _pos(actor) != session.BASE or actor.state not in ["injured_return", "dock_wait", "capacity_wait"]:
		_stop(session, id, "回復後の荷物搬入は入口でのみ行えます", true)
		return false
	return true
