class_name GroundTwoLanePrototypeModel
extends RefCounted
## 2レーン相当の浅い幅を持つ、連続奥行き帯の比較用モデル。
## 固定線・横断路・3D面移動は使わず、帯の範囲内だけを直接移動する。

const BACK_Y := 350.0
const FRONT_Y := 440.0
const BASE_DOOR := Vector2(188.0, 174.0)
const RAMP_FOOT := Vector2(350.0, BACK_Y)
const CARRY_LIMIT := 2
const WALK_SPEED := 90.0
const GATHER_SECONDS := 0.8
const MIN_SPACING := 24.0
const MELEE_REACH := 58.0
const TOTAL_RESOURCE := 6

var mode := "depth_strip"
var time := 0.0
var agents: Array[Dictionary] = []
var sources: Array[Dictionary] = []
var delivered := 0
var combat_hits := 0
var retreat_violations := 0
var min_worker_distance := INF
var closest_pair := ""
var max_depth_step := 0.0
var depth_motion_xs: Array[float] = []
var completion_time := -1.0
var attack_log := "待機"
var enemy := {"position": Vector2(865.0, FRONT_Y - 8.0), "alive": true}


func reset(_unused_mode := "depth_strip") -> void:
	mode = "depth_strip"
	time = 0.0
	delivered = 0
	combat_hits = 0
	retreat_violations = 0
	min_worker_distance = INF
	closest_pair = ""
	max_depth_step = 0.0
	depth_motion_xs.clear()
	completion_time = -1.0
	attack_log = "待機: 奥行き差だけでは近接命中しない"
	enemy = {"position": Vector2(865.0, FRONT_Y - 8.0), "alive": true}
	agents.clear()
	sources.clear()
	var ys: Array[float] = [BACK_Y + 8.0, FRONT_Y - 12.0, lerpf(BACK_Y, FRONT_Y, 0.58)]
	for i in 3:
		sources.append({"id": i, "position": Vector2(710.0 + float(i) * 155.0, ys[i]), "remaining": 2, "claimed": -1})
		var p := BASE_DOOR + Vector2(float(i - 1) * 30.0, 0.0)
		agents.append({
			"id": i, "name": ["ネズト", "チュー助", "砂吉"][i], "position": p,
			"state": "outbound", "route": [], "target": -1, "cargo": 0,
			"gather": 0.0, "retreating": false, "unloaded": 0,
		})
	for i in agents.size():
		_assign_source(i)
	_update_spacing()


func step(delta: float) -> void:
	if delta <= 0.0:
		return
	time += delta
	for i in agents.size():
		var a := agents[i]
		if bool(a.retreating) and String(a.state) in ["outbound", "gather", "chase"]:
			retreat_violations += 1
		match String(a.state):
			"outbound":
				if _follow_route(a, delta):
					a.state = "gather"
					a.gather = 0.0
			"gather":
				var source := _source_for(a)
				if source.is_empty() or int(source.remaining) <= 0:
					_assign_source(i)
				else:
					a.gather = float(a.gather) + delta
					if float(a.gather) >= GATHER_SECONDS:
						source.remaining = int(source.remaining) - 1
						if int(source.remaining) <= 0:
							source.claimed = -1
							a.target = -1
						sources[int(source.id)] = source
						a.cargo = int(a.cargo) + 1
						a.gather = 0.0
						if int(a.cargo) >= CARRY_LIMIT or int(source.remaining) <= 0:
							_set_return_route(a)
							a.state = "returning"
			"returning":
				if _follow_route(a, delta):
					a.state = "unload"
			"unload":
				delivered += int(a.cargo)
				a.unloaded = int(a.unloaded) + int(a.cargo)
				a.cargo = 0
				if bool(a.retreating):
					a.state = "retreated"
				else:
					_assign_source(i)
			"chase":
				if _follow_route(a, delta):
					if can_melee(Vector2(a.position), Vector2(enemy.position)):
						combat_hits += 1
						enemy.alive = false
						attack_log = "連続帯を近づいてから近接命中"
					else:
						attack_log = "FAIL: 奥行き距離を無視した命中"
					_set_return_route(a)
					a.state = "returning"
		agents[i] = a
	_update_spacing()
	if delivered >= TOTAL_RESOURCE and completion_time < 0.0:
		completion_time = time


func run_for(seconds: float, delta := 0.05) -> void:
	for _frame in ceili(seconds / delta):
		step(delta)


func complete() -> bool:
	return delivered >= TOTAL_RESOURCE and agents.all(func(a): return String(a.state) in ["idle", "retreated"])


func depth_melee_is_blocked() -> bool:
	return not can_melee(Vector2(865.0, BACK_Y + 4.0), Vector2(enemy.position))


func can_melee(attacker: Vector2, target: Vector2) -> bool:
	return attacker.distance_to(target) <= MELEE_REACH


func start_chase(agent_id: int) -> bool:
	if agent_id < 0 or agent_id >= agents.size() or not bool(enemy.alive):
		return false
	var a := agents[agent_id]
	if bool(a.retreating) or int(a.cargo) > 0:
		return false
	_release_source(a)
	a.route = _route_between(Vector2(a.position), Vector2(enemy.position))
	a.state = "chase"
	attack_log = "追跡: 帯の中を直接移動"
	agents[agent_id] = a
	return true


func start_personal_retreat(agent_id: int) -> bool:
	if agent_id < 0 or agent_id >= agents.size():
		return false
	var a := agents[agent_id]
	if String(a.state) in ["retreated", "returning", "unload"]:
		return false
	_release_source(a)
	a.retreating = true
	_set_return_route(a)
	a.state = "returning"
	agents[agent_id] = a
	return true


func agent_status(agent_id: int) -> String:
	var a := agents[agent_id]
	return "%s: %s / 奥行き %.0f" % [a.name, _state_name(String(a.state)), Vector2(a.position).y]


func remaining_resource() -> int:
	var total := 0
	for source in sources:
		total += int(source.remaining)
	return total


func _assign_source(agent_id: int) -> void:
	var a := agents[agent_id]
	if bool(a.retreating):
		a.state = "retreated"
		agents[agent_id] = a
		return
	var best_id := -1
	var best_distance := INF
	for source in sources:
		if int(source.remaining) <= 0 or int(source.claimed) >= 0:
			continue
		var d := Vector2(a.position).distance_to(Vector2(source.position))
		if d < best_distance:
			best_distance = d
			best_id = int(source.id)
	if best_id < 0:
		a.target = -1
		a.state = "idle"
		agents[agent_id] = a
		return
	var source := sources[best_id]
	source.claimed = agent_id
	sources[best_id] = source
	a.target = best_id
	a.route = _route_to_source(Vector2(source.position), int(a.id))
	a.state = "outbound"
	agents[agent_id] = a


func _source_for(a: Dictionary) -> Dictionary:
	var id := int(a.target)
	return sources[id] if id >= 0 and id < sources.size() else {}


func _release_source(a: Dictionary) -> void:
	var id := int(a.target)
	if id >= 0 and id < sources.size():
		var source := sources[id]
		if int(source.claimed) == int(a.id):
			source.claimed = -1
			sources[id] = source
	a.target = -1


func _route_to_source(target: Vector2, agent_id: int) -> Array[Vector2]:
	var offset := float(agent_id - 1) * 30.0
	return [RAMP_FOOT + Vector2(offset, 0.0), target + Vector2(-32.0, 0.0)]


func _set_return_route(a: Dictionary) -> void:
	var offset := float(int(a.id) - 1) * 30.0
	a.route = [RAMP_FOOT + Vector2(offset, 0.0), BASE_DOOR + Vector2(offset, 0.0)]


func _route_between(_from: Vector2, target: Vector2) -> Array[Vector2]:
	return [target + Vector2(-28.0, 0.0)]


func _follow_route(a: Dictionary, delta: float) -> bool:
	var route: Array = a.route
	if route.is_empty():
		return true
	var p := Vector2(a.position)
	var target := Vector2(route[0])
	var step := WALK_SPEED * delta
	var before_y := p.y
	if p.distance_to(target) <= step:
		p = target
		route.pop_front()
	else:
		p += p.direction_to(target) * step
	var depth_step := absf(p.y - before_y)
	max_depth_step = maxf(max_depth_step, depth_step)
	if p.y > BACK_Y + 4.0 and p.y < FRONT_Y - 4.0:
		depth_motion_xs.append(p.x)
	a.position = p
	a.route = route
	return route.is_empty()


func _update_spacing() -> void:
	for i in agents.size():
		for j in range(i + 1, agents.size()):
			var pa := Vector2(agents[i].position)
			var pb := Vector2(agents[j].position)
			if pa.distance_to(pb) < MIN_SPACING:
				var push := (pa - pb).normalized()
				if push.length_squared() < 0.01:
					push = Vector2(1.0, 0.0)
				pa += push * 0.5 * (MIN_SPACING - pa.distance_to(pb))
				pb -= push * 0.5 * (MIN_SPACING - pa.distance_to(pb))
				pa.y = clampf(pa.y, BACK_Y, FRONT_Y)
				pb.y = clampf(pb.y, BACK_Y, FRONT_Y)
				var a := agents[i]
				var b := agents[j]
				a.position = pa
				b.position = pb
				agents[i] = a
				agents[j] = b
			var d := pa.distance_to(pb)
			if d < min_worker_distance:
				min_worker_distance = d
				closest_pair = "%s/%s at %.2fs (%s,%s)" % [agents[i].name, agents[j].name, time, pa, pb]


func _state_name(state: String) -> String:
	return {
		"outbound": "採取地点へ移動", "gather": "採取", "returning": "スロープへ帰還",
		"unload": "荷卸し", "chase": "追跡", "retreated": "個人退却完了", "idle": "待機",
	}.get(state, state)
