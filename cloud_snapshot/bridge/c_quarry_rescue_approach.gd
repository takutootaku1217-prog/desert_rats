class_name CQuarryRescueApproach
extends RefCounted
## Live physical rescue and entrance handoff. Dedicated complete snapshots restore
## validated ownership; legacy Session migration still refuses active ownership.
const MineRoutes = preload("res://bridge/c_quarry_mine_rescue_routes.gd")
var _mine_returns := {} # live rescue-origin release -> healthy/injured return
var _mine_bindings := {} # live exact target/carrier dictionaries
var _owned := {} # carrier -> target; complete restore also rebuilds exact actor bindings
var _treatment := {} # target -> saved rescue remainder, until normal recovery commit

func request(session, target_id: String, carrier_id: String, expected_session_id: String) -> Dictionary:
	if expected_session_id.is_empty() or expected_session_id != session.session_id or session.committed or session.phase not in ["local", "recall"]:
		return {"ok": false, "reason": "現在の現地sessionを確認できません"}
	if reserved(session, carrier_id) or not _position_valid(session, target_id) or not _position_valid(session, carrier_id):
		return {"ok": false, "reason": "担ぎ手の現在位置・作業予約を確認してください"}
	if str(session.actors[carrier_id].get("state", "")) in ["rescue_move", "rescue_hold", "rescue_return"]:
		return {"ok": false, "reason": "担ぎ手は既に救助中です"}
	if session.mine_path_engineering:
		var plan := MineRoutes.plan(session, session.actors[carrier_id], Vector2(session.actors[target_id].x, session.actors[target_id].y), carrier_id, target_id)
		if not plan.ok: return plan
	if not session.rescue_ledger.assign(target_id, carrier_id, session.actors, not session.all_routes_closed):
		return {"ok": false, "reason": "救助対象または空荷の担ぎ手を確認してください"}
	_clear_mine_return(session, carrier_id)
	_owned[carrier_id] = target_id
	if session.mine_path_engineering:
		_mine_bindings[carrier_id] = {"target": session.actors[target_id], "carrier": session.actors[carrier_id]}
	var actor: Dictionary = session.actors[carrier_id]
	actor.state = "rescue_move"
	actor.resume_state = ""
	actor.wait_reason = "戦闘不能の仲間へ接近中"
	repath(session, carrier_id)
	session._log("%s が%sへ手動救助で接近" % [carrier_id, target_id])
	return {"ok": true, "target_id": target_id, "carrier_id": carrier_id}

func cancel(session, target_id: String, expected_session_id: String) -> Dictionary:
	if expected_session_id.is_empty() or expected_session_id != session.session_id or session.committed:
		return {"ok": false, "reason": "現在の現地sessionを確認できません"}
	var row: Dictionary = session.rescue_ledger.case_for(target_id)
	if not _owned.has(row.get("carrier", "")) or _owned[row.carrier] != target_id or not session.rescue_ledger.interrupt(target_id):
		return {"ok": false, "reason": "取消できる救助担当がありません"}
	sync(session)
	return {"ok": true}

## Competing jobs must respect both movement and pending treatment ownership.
func owns(actor_id: String) -> bool:
	return _owned.has(actor_id) or _treatment.has(actor_id) or _mine_returns.has(actor_id)

func reserved(session, actor_id: String) -> bool:
	if actor_id.is_empty() or not session.actors.has(actor_id):
		return true
	if actor_id == session.maintenance_actor_id or session.dock_queue.has(actor_id) or session.dock_busy.has(actor_id) or session.reservations.values().has(actor_id):
		return true
	for resource in session.resources.values():
		if str(resource.get("reservation", "")) == actor_id:
			return true
	for enemy in session.outpost_enemies.values():
		if str(enemy.get("engager", "")) == actor_id:
			return true
	var frame: Dictionary = session.field_frame_exchange
	if frame.get("status") == "scheduled" and actor_id in [frame.get("source_id"), frame.get("target_id")]:
		return true
	return session._field_tool_swap_waiting_for(actor_id) or (session.return_handcart_exchange.get("status") == "reserved" and session.return_handcart_exchange.get("target_id") == actor_id)

func sync(session) -> void:
	for actor_id in _mine_returns.keys():
		if not session.actors.has(actor_id) or bool(session.actors[actor_id].get("down", false)) or session.actors[actor_id].get("state") not in ["to_base_empty", "injured_return", "safe_wait"]:
			_clear_mine_return(session, actor_id)
	for carrier_id in _owned.keys():
		var target_id: String = _owned[carrier_id]
		var row: Dictionary = session.rescue_ledger.case_for(target_id)
		var active: bool = row.get("carrier") == carrier_id and row.get("phase") in ["assigned", "carried"]
		if active:
			var allowed_states: Array = ["rescue_move"] if row.phase == "assigned" else ["rescue_hold", "rescue_return"]
			active = session.phase in ["local", "recall"] and not session.committed and not session.all_routes_closed and not reserved(session, carrier_id) and _position_valid(session, target_id) and _position_valid(session, carrier_id)
			active = active and session.rescue_ledger._target_down(target_id, session.actors) and session.rescue_ledger._carrier_ready(carrier_id, session.actors) and session.actors[carrier_id].get("state") in allowed_states
			if active and session.mine_path_engineering:
				active = _mine_binding_current(session, carrier_id, target_id)
				var carrier: Dictionary = session.actors[carrier_id]
				if active and carrier.state in ["rescue_move", "rescue_return"]:
					active = session.mine_rescue_traces.plan_current(carrier_id, carrier)
				if active and carrier.state == "rescue_move":
					active = session.mine_rescue_traces.approved_goal(carrier_id) == Vector2(session.actors[target_id].x, session.actors[target_id].y)
			if active and row.phase == "carried":
				active = _same_position(session.actors[carrier_id], session.actors[target_id])
		if active:
			continue
		session.rescue_ledger.interrupt(target_id)
		_owned.erase(carrier_id)
		var original_carrier: bool = not session.mine_path_engineering or (_mine_bindings.has(carrier_id) and is_same(_mine_bindings[carrier_id].carrier, session.actors.get(carrier_id)))
		_mine_bindings.erase(carrier_id)
		if original_carrier: _release_carrier(session, carrier_id)

func repath(session, carrier_id: String) -> void:
	if not _owned.has(carrier_id) or not session.actors.has(carrier_id):
		return
	var actor: Dictionary = session.actors[carrier_id]
	if actor.get("state") not in ["rescue_move", "rescue_return"] or not _position_valid(session, _owned[carrier_id]):
		return
	var target: Dictionary = {"x": session.BASE.x, "y": session.BASE.y} if actor.state == "rescue_return" else session.actors[_owned[carrier_id]]
	if session.mine_path_engineering:
		var plan := MineRoutes.plan(session, actor, Vector2(target.x, target.y), carrier_id, "" if actor.state == "rescue_return" else _owned[carrier_id])
		if plan.ok:
			_apply_mine_path(session, actor, plan)
		else:
			session.rescue_ledger.interrupt(_owned[carrier_id])
			_owned.erase(carrier_id)
			_release_carrier(session, carrier_id)
		return
	var crosses_gate: bool = (float(actor.x) > session.GATE.x) != (float(target.x) > session.GATE.x)
	var points: Array = []
	if crosses_gate:
		points.append(session._point_array(session.BYPASS if session.gate_closed else session.GATE))
	points.append([target.x, target.y])
	actor.path = points
	actor.path_index = 0
	actor.path_speed = session._local_travel_speed()
	actor.seen_route_revision = session.route_revision
	actor.route = "bypass" if crosses_gate and session.gate_closed else ("main" if crosses_gate else "local")
	session.path_requests += 1

func update_actor(session, carrier_id: String, delta: float) -> void:
	if not _owned.has(carrier_id):
		return
	var actor: Dictionary = session.actors[carrier_id]
	if actor.state == "rescue_hold":
		return
	var target_id: String = _owned[carrier_id]
	var target: Dictionary = session.actors[target_id]
	if actor.state == "rescue_return":
		_update_return(session, carrier_id, target_id, delta)
		return
	if not session._advance(actor, delta):
		return
	# Ordinary paths allow a small tolerance. Rescue cannot use it as a pickup
	# radius. Finish the physical final segment before sharing exact numbers.
	if Vector2(actor.x, actor.y) != Vector2(target.x, target.y):
		actor.path = [[target.x, target.y]]
		actor.path_index = 0
		if session.mine_path_engineering: session.mine_rescue_traces.witness_correction(session, carrier_id, actor)
		return
	actor.x = target.x
	actor.y = target.y
	if session.rescue_ledger.pickup(target_id, carrier_id, session.actors, not session.all_routes_closed):
		actor.state = "rescue_hold"
		actor.path = []
		actor.path_index = 0
		actor.wait_reason = "担ぎ上げ保持中：入口への搬送を指示できます"
		session._log("%s が%sを同位置で担ぎ上げ" % [carrier_id, target_id])

## Battle-origin boss returns use the same witnessed mine corridors as a
## released rescuer. No new path permissions or legacy trace exceptions.
func begin_boss_return(session, actor_id: String, return_state: String) -> bool:
	if not session.is_region_boss() or not session.mine_path_engineering or return_state not in ["injured_return", "to_base_empty"] or not session.actors.has(actor_id):
		return false
	var actor: Dictionary = session.actors[actor_id]
	if actor.get("role") != "escort" or actor.get("state") != return_state or bool(actor.get("down", false)) or float(actor.get("hp", 0.0)) <= 0.0 or int(actor.get("carry_n", 0)) != 0:
		return false
	if owns(actor_id) or session.expired_recovery.owns(actor_id) or reserved(session, actor_id):
		return false
	_mine_returns[actor_id] = return_state
	actor.rescue_mine_return = true
	repath_mine_return(session, actor_id)
	return true # An unavailable route remains owned safe_wait, never a shortcut.

func _release_carrier(session, carrier_id: String) -> void:
	if not session.actors.has(carrier_id):
		return
	var actor: Dictionary = session.actors[carrier_id]
	if session.mine_path_engineering and actor.get("state") in ["rescue_move", "rescue_hold", "rescue_return", "injured_return"] and not bool(actor.down):
		_mine_returns[carrier_id] = "injured_return" if float(actor.hp) <= FieldOperations.RETREAT_HP else "to_base_empty"
		actor.rescue_mine_return = true
		repath_mine_return(session, carrier_id)
		return
	if actor.get("state") not in ["rescue_move", "rescue_hold", "rescue_return"]:
		return # A newer owner, injury or down transition keeps its own state.
	actor.path = []
	actor.path_index = 0
	actor.resume_state = ""
	actor.wait_reason = "救助を中断。対象は現地に留まり残秒から再開"
	if bool(actor.down):
		actor.state = "down"
	elif float(actor.hp) > 0.0 and float(actor.hp) <= FieldOperations.RETREAT_HP:
		session._begin_injured_return(carrier_id, actor)
	else:
		actor.state = "to_base_empty"
		session._refresh_actor_path(carrier_id)

func _position_valid(session, actor_id: String) -> bool:
	if not session.actors.get(actor_id) is Dictionary:
		return false
	for axis in ["x", "y"]:
		var value: Variant = session.actors[actor_id].get(axis)
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	return true

func request_return(session, target_id: String, expected_session_id: String) -> Dictionary:
	if expected_session_id.is_empty() or expected_session_id != session.session_id or session.committed or session.phase not in ["local", "recall"] or session.all_routes_closed:
		return {"ok": false, "reason": "現在の救助搬送経路を確認できません"}
	var row: Dictionary = session.rescue_ledger.case_for(target_id)
	var carrier_id := str(row.get("carrier", ""))
	if row.get("phase") != "carried" or _owned.get(carrier_id) != target_id or reserved(session, carrier_id) or not _position_valid(session, target_id) or not _position_valid(session, carrier_id):
		return {"ok": false, "reason": "同じ場所で担ぎ上げている救助担当が必要です"}
	if session.mine_path_engineering and not _mine_binding_current(session, carrier_id, target_id):
		return {"ok": false, "reason": "救助開始時の対象・担ぎ手と一致しません"}
	var actor: Dictionary = session.actors[carrier_id]
	if actor.get("state") != "rescue_hold" or not session.rescue_ledger._carrier_ready(carrier_id, session.actors) or not session.rescue_ledger._target_down(target_id, session.actors) or not _same_position(actor, session.actors[target_id]):
		return {"ok": false, "reason": "担ぎ手と対象の現在状態を確認してください"}
	if session.mine_path_engineering:
		var plan := MineRoutes.plan(session, actor, session.BASE, carrier_id)
		if not plan.ok: return plan
	actor.state = "rescue_return"
	actor.wait_reason = "仲間を入口へ搬送中"
	repath(session, carrier_id)
	return {"ok": true, "target_id": target_id, "carrier_id": carrier_id}

func _same_position(a: Dictionary, b: Dictionary) -> bool:
	return float(a.x) == float(b.x) and float(a.y) == float(b.y)

func _update_return(session, carrier_id: String, target_id: String, delta: float) -> void:
	var actor: Dictionary = session.actors[carrier_id]
	var target: Dictionary = session.actors[target_id]
	var arrived: bool = session._advance(actor, delta)
	target.x = actor.x
	target.y = actor.y
	if not arrived:
		return
	if Vector2(actor.x, actor.y) != session.BASE:
		actor.path = [session._point_array(session.BASE)]
		actor.path_index = 0
		if session.mine_path_engineering: session.mine_rescue_traces.witness_correction(session, carrier_id, actor)
		return
	var row: Dictionary = session.rescue_ledger.finish_at_entrance(target_id, carrier_id, session.actors, session.BASE)
	if row.is_empty():
		return
	_treatment[target_id] = float(row.left)
	_owned.erase(carrier_id)
	_mine_bindings.erase(carrier_id)
	# Reuse existing normal deliver_rescue first aid, not a new heal rate.
	target.down = false
	target.hp = CrewStatusDB.HP_REVIVE_AT
	target.state = "rescue_treatment"
	target.path = []
	target.path_index = 0
	target.resume_state = ""
	target.wait_reason = "入口で応急手当済み。帰還確定後に治療・待機"
	actor.state = "idle"
	actor.path = []
	actor.path_index = 0
	actor.resume_state = ""
	actor.wait_reason = "救助搬送完了。入口で待機"
	update_treatment(session, target_id)
	session._log("%s を入口へ実搬送。帰還確定後の治療引渡し待ち" % target_id)

func treatment_pending(target_id: String) -> bool:
	return _treatment.has(target_id)

func update_treatment(session, target_id: String) -> void:
	if not treatment_pending(target_id) or not session.actors.has(target_id):
		return
	var actor: Dictionary = session.actors[target_id]
	if int(actor.get("carry_n", 0)) > 0 and (not session.vertical_slice or session._depot_room_for(int(actor.carry_item)) > 0):
		session._enqueue_dock(target_id)

func commit_preflight(session, game) -> Dictionary:
	var pending := {}
	var indexes := {}
	for actor_id in session.actors:
		var actor: Dictionary = session.actors[actor_id]
		if actor.get("state") == "rescue_treatment" and not treatment_pending(actor_id):
			return {"ok": false, "reason": "入口治療の引渡し記録がありません"}
		if not treatment_pending(actor_id):
			continue
		for field in ["worker_index", "hp", "carry_n", "carry_item"]:
			var value: Variant = actor.get(field)
			if not (value is int or value is float) or not is_finite(float(value)):
				return {"ok": false, "reason": "入口治療の数値が不正です"}
		if float(actor.worker_index) != float(int(actor.worker_index)) or str(actor_id) != "worker:%d" % int(actor.worker_index) or not actor.get("down") is bool or float(actor.hp) > CrewStatusDB.MAX_HP or float(actor.carry_n) != 0.0 or float(actor.carry_item) != -1.0:
			return {"ok": false, "reason": "入口治療の対象・体調・手持ちが不正です"}
		var index := int(actor.get("worker_index", -1))
		if index < 0 or index >= game.workers.size() or indexes.has(index) or bool(actor.get("down", true)) or float(actor.get("hp", 0.0)) < CrewStatusDB.HP_REVIVE_AT or actor.get("state") != "rescue_treatment" or not _position_valid(session, actor_id) or Vector2(actor.x, actor.y) != session.BASE or int(actor.get("carry_n", 0)) != 0:
			return {"ok": false, "reason": "入口治療の対象・位置・貨物を確認できません"}
		if game.operations == null or game.operations.rescue_cases.has(str(index)) or not game.operations.rescue_carrier_phase(game.workers[index]).is_empty():
			return {"ok": false, "reason": "本編救助記録との競合があるため治療引渡しを拒否しました"}
		indexes[index] = true
		pending[str(index)] = {"target": index, "carrier": -1, "phase": "recovering", "left": float(_treatment[actor_id]), "resume_return": true, "resume_manual_job": -1, "deferred_return": false}
	if pending.size() != _treatment.size() or not FieldOperations.rescue_cases_valid(pending, game.workers.size()):
		return {"ok": false, "reason": "治療引渡し記録を検証できません"}
	return {"ok": true, "cases": pending}

func apply_commit(_session, game, plan: Dictionary) -> void:
	for key in plan.cases:
		var row: Dictionary = plan.cases[key]
		var worker = game.workers[int(row.target)]
		game.operations.rescue_cases[key] = row.duplicate(true)
		worker.ai._release_task()
		worker.ai.return_request = true
		worker.ai.manual_job = -1
		worker.ai._set_state(CharacterAI.State.RESCUE_RECOVER)
		worker.position = game.storage.access_point() + worker.slot_offset
		worker.target = worker.position
		worker.floor_i = GameData.floor_of_y(worker.position.y)
		worker._climb_dest = null

## Preserve safe mine geometry after cancellation or injury, until exact BASE.
func has_mine_return(actor_id: String) -> bool:
	return _mine_returns.has(actor_id)

func _clear_mine_return(session, actor_id: String) -> void:
	_mine_returns.erase(actor_id)
	if session.actors.has(actor_id): session.actors[actor_id].erase("rescue_mine_return")

func _apply_mine_path(session, actor: Dictionary, plan: Dictionary) -> void:
	actor.path = plan.path
	actor.path_index = 0
	actor.path_speed = session.MOVE_SPEED
	actor.seen_route_revision = session.route_revision
	actor.route = plan.route
	for id in session.actors:
		if is_same(session.actors[id], actor): session.mine_rescue_traces.witness_plan(session, id, actor, "rescue", plan.get("witness",{}))
	session.path_requests += 1

func repath_mine_return(session, actor_id: String) -> void:
	if not _mine_returns.has(actor_id) or not session.actors.has(actor_id): return
	var actor: Dictionary = session.actors[actor_id]
	if float(actor.hp) <= FieldOperations.RETREAT_HP:
		_mine_returns[actor_id] = "injured_return"
	var plan := MineRoutes.plan(session, actor, session.BASE, actor_id)
	actor.path = []
	actor.path_index = 0
	if not plan.ok:
		actor.state = "safe_wait"
		actor.resume_state = _mine_returns[actor_id]
		actor.wait_reason = str(plan.reason)
		return
	actor.state = _mine_returns[actor_id]
	actor.resume_state = ""
	actor.wait_reason = "採石路を通って入口へ帰還"
	_apply_mine_path(session, actor, plan)

func update_mine_return(session, actor_id: String, delta: float) -> void:
	var actor: Dictionary = session.actors[actor_id]
	if actor.state == "safe_wait":
		if not session.all_routes_closed and int(actor.get("seen_route_revision", -1)) != session.route_revision:
			repath_mine_return(session, actor_id)
		return
	if session.all_routes_closed:
		repath_mine_return(session, actor_id)
		return
	if not session.mine_rescue_traces.plan_current(actor_id, actor):
		actor.state = "safe_wait"
		actor.resume_state = _mine_returns[actor_id]
		actor.wait_reason = "帰還経路の担当・装備・位置・順序が変更されたため停止しました"
		return
	if not session._advance(actor, delta): return
	if Vector2(actor.x, actor.y) != session.BASE:
		actor.path = [session._point_array(session.BASE)]
		actor.path_index = 0
		session.mine_rescue_traces.witness_correction(session, actor_id, actor)
		return
	actor.state = "injured_wait" if _mine_returns[actor_id] == "injured_return" else "idle"
	actor.path = []
	actor.path_index = 0
	actor.resume_state = ""
	actor.wait_reason = "負傷のため入口で撤退待ち" if actor.state == "injured_wait" else "救助中断後、入口で待機"
	_clear_mine_return(session, actor_id)

func _mine_binding_current(session, carrier_id: String, target_id: String) -> bool:
	return _mine_bindings.has(carrier_id) and is_same(_mine_bindings[carrier_id].carrier, session.actors.get(carrier_id)) and is_same(_mine_bindings[carrier_id].target, session.actors.get(target_id))
