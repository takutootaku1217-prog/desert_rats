class_name CQuarryRescueLedger
extends RefCounted
## Actor-ID state contract only. The session owns positions, cargo and health.
## No Worker AI, save permission, inventory, rewards or revival cost live here.
const SCHEMA_VERSION := 1
const RESCUE_SECONDS := FieldOperations.RESCUE_SECONDS
## User chose temporary long incapacitation on 2026-10-23. The 600-second
## implementation value is deliberately shared and remains adjustable.
const INCAPACITATION_SECONDS := FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS
const PHASES := ["waiting", "assigned", "carried", "incapacitated", "recovery_due"]
const CASE_FIELDS := ["target", "carrier", "phase", "left"]
var _cases: Dictionary = {}

func case_for(target_id: String) -> Dictionary:
	return Dictionary(_cases.get(target_id, {})).duplicate(true)

func observe_down(target_id: String, actors: Dictionary) -> bool:
	if _cases.has(target_id) or not _target_down(target_id, actors):
		return false
	_cases[target_id] = {"target": target_id, "carrier": "", "phase": "waiting", "left": RESCUE_SECONDS}
	return true

func assign(target_id: String, carrier_id: String, actors: Dictionary, routes_open := true) -> bool:
	if not routes_open or not _cases.has(target_id) or _cases[target_id].phase != "waiting" or not _target_down(target_id, actors):
		return false
	if not _carrier_ready(carrier_id, actors) or not _carrier_target(carrier_id).is_empty():
		return false
	_cases[target_id].carrier = carrier_id
	_cases[target_id].phase = "assigned"
	return true

func pickup(target_id: String, carrier_id: String, actors: Dictionary, routes_open := true) -> bool:
	if not routes_open or not _cases.has(target_id):
		return false
	var row: Dictionary = _cases[target_id]
	if row.phase != "assigned" or row.carrier != carrier_id or not _target_down(target_id, actors) or not _carrier_ready(carrier_id, actors):
		return false
	var target: Dictionary = actors[target_id]
	var carrier: Dictionary = actors[carrier_id]
	# The movement owner must complete its path and establish arrival first.
	# This contract invents neither a pickup radius nor a teleport operation.
	for axis in ["x", "y"]:
		if not _finite_number(target.get(axis)) or not _finite_number(carrier.get(axis)) or float(target[axis]) != float(carrier[axis]):
			return false
	row.phase = "carried"
	return true

func interrupt(target_id: String) -> bool:
	if not _cases.has(target_id) or _cases[target_id].phase not in ["assigned", "carried"]:
		return false
	_cases[target_id].phase = "waiting"
	_cases[target_id].carrier = ""
	return true

func tick(delta: float, actors: Dictionary, explicitly_paused := false, routes_open := true) -> void:
	if explicitly_paused or not is_finite(delta) or delta <= 0.0:
		return
	for target_id in _cases:
		var row: Dictionary = _cases[target_id]
		if row.phase in ["assigned", "carried"] and (not routes_open or not _carrier_ready(row.carrier, actors)):
			interrupt(target_id)
		if row.phase in ["carried", "recovery_due"]:
			continue
		var remaining_delta := delta
		if row.phase in ["waiting", "assigned"]:
			var consumed := minf(remaining_delta, float(row.left))
			row.left = maxf(0.0, float(row.left) - consumed)
			remaining_delta -= consumed
			if row.left <= 0.0:
				row.phase = "incapacitated"
				row.carrier = ""
				row.left = INCAPACITATION_SECONDS
		if row.phase == "incapacitated":
			row.left = maxf(0.0, float(row.left) - remaining_delta)
			if row.left <= 0.0:
				# The live expiry owner consumes this intent once for physical return.
				# This intent alone does not heal fully or authorize a remote commit.
				row.phase = "recovery_due"

func to_dict() -> Dictionary:
	return {"schema": SCHEMA_VERSION, "cases": _cases.duplicate(true)}

static func from_dict(data: Variant, actors: Dictionary) -> Dictionary:
	if not data is Dictionary or data.size() != 2 or not data.has("schema") or not data.has("cases"):
		return {"ok": false, "reason": "救助台帳の必須項目が不正です"}
	if not _finite_number(data.schema) or float(data.schema) != SCHEMA_VERSION or not data.cases is Dictionary:
		return {"ok": false, "reason": "救助台帳のschemaまたはcaseが不正です"}
	var result := new()
	result._cases = data.cases.duplicate(true)
	var carriers := {}
	for target_id in result._cases:
		if not target_id is String or not result._target_down(target_id, actors):
			return {"ok": false, "reason": "救助対象のactorを確認できません"}
		var row = result._cases[target_id]
		if not row is Dictionary or row.size() != CASE_FIELDS.size():
			return {"ok": false, "reason": "救助caseの項目が不正です"}
		for field in CASE_FIELDS:
			if not row.has(field):
				return {"ok": false, "reason": "救助caseの項目が欠けています"}
		if not row.target is String or row.target != target_id or not row.carrier is String or not row.phase is String or row.phase not in PHASES:
			return {"ok": false, "reason": "救助caseの対象・担当・段階が不正です"}
		if not _finite_number(row.left):
			return {"ok": false, "reason": "救助caseの残秒が不正です"}
		var left := float(row.left)
		# Like normal FieldOperations, saved incapacitation keeps its remainder
		# when the provisional default is tuned later. Only new expiry uses it.
		if (left != 0.0 if row.phase == "recovery_due" else left <= 0.0 or (row.phase != "incapacitated" and left > RESCUE_SECONDS)):
			return {"ok": false, "reason": "救助caseの残秒範囲が不正です"}
		if row.phase in ["assigned", "carried"]:
			if not result._carrier_ready(row.carrier, actors) or carriers.has(row.carrier):
				return {"ok": false, "reason": "救助担当の重複または状態が不正です"}
			carriers[row.carrier] = target_id
		elif not row.carrier.is_empty():
			return {"ok": false, "reason": "担当のない救助段階に担当者が残っています"}
		row.left = left
	return {"ok": true, "ledger": result}

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _target_down(actor_id: String, actors: Dictionary) -> bool:
	if actor_id.is_empty() or not actors.get(actor_id) is Dictionary:
		return false
	var actor: Dictionary = actors[actor_id]
	return actor.get("down") is bool and actor.down and _finite_number(actor.get("hp")) and float(actor.hp) == 0.0

func _carrier_ready(actor_id: String, actors: Dictionary) -> bool:
	if actor_id.is_empty() or _cases.has(actor_id) or not actors.get(actor_id) is Dictionary:
		return false
	var actor: Dictionary = actors[actor_id]
	if not actor.get("down") is bool or actor.down or not _finite_number(actor.get("hp")) or float(actor.hp) <= FieldOperations.RETREAT_HP:
		return false
	if not _finite_number(actor.get("carry_n")) or float(actor.carry_n) != 0.0 or not _finite_number(actor.get("carry_item")) or float(actor.carry_item) != -1.0:
		return false
	if actor.get("resource_id") != "" or actor.get("combat_target") != "":
		return false
	return actor.get("state") in ["idle", "escort", "wait_relay", "to_resource", "to_relay", "to_base_empty", "outpost_wait", "safe_wait", "capacity_idle", "rescue_move", "rescue_hold", "rescue_return"]

func _carrier_target(carrier_id: String) -> String:
	for target_id in _cases:
		if _cases[target_id].carrier == carrier_id:
			return str(target_id)
	return ""

## Consume only a physically delivered case. Health and cargo remain session-owned.
func finish_at_entrance(target_id: String, carrier_id: String, actors: Dictionary, entrance: Vector2) -> Dictionary:
	var row := case_for(target_id)
	if row.get("phase") != "carried" or row.get("carrier") != carrier_id or not _target_down(target_id, actors) or not _carrier_ready(carrier_id, actors):
		return {}
	for actor_id in [target_id, carrier_id]:
		var actor: Dictionary = actors[actor_id]
		if not _finite_number(actor.get("x")) or not _finite_number(actor.get("y")) or Vector2(actor.x, actor.y) != entrance:
			return {}
	_cases.erase(target_id)
	return row

## Consume the completed provisional delay once. Health/positions remain session-owned.
func consume_recovery_due(target_id: String, actors: Dictionary) -> bool:
	if not _target_down(target_id, actors) or case_for(target_id).get("phase") != "recovery_due": return false
	_cases.erase(target_id)
	return true
