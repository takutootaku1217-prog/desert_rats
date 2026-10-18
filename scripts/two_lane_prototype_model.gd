class_name GroundTwoLanePrototypeModel
extends RefCounted
## 独立試作専用: 屋外の「奥/手前」固定2レーンを検証する最小モデル。
## 同じ平面の奥行き表現だけを扱い、3D座標・自由な面移動は持ち込まない。

const BACK_Y := 350.0
const FRONT_Y := 470.0
const BASE_DOOR := Vector2(188.0, 174.0)
const RAMP_FOOT := Vector2(350.0, BACK_Y)
const CROSS_X := 540.0
# 同じ平地を縦に横断する地点。斜路／橋ではない。
const CROSS_BACK := Vector2(CROSS_X, BACK_Y)
const CROSS_FRONT := Vector2(CROSS_X, FRONT_Y)
const CARRY_LIMIT := 2
const WALK_SPEED := 90.0
const GATHER_SECONDS := 0.8
const MIN_SPACING := 24.0
const MELEE_X_REACH := 58.0
const MELEE_DEPTH_REACH := 30.0
const TOTAL_RESOURCE := 6

var mode := "two" # one / two
var time := 0.0
var agents: Array[Dictionary] = []
var sources: Array[Dictionary] = []
var delivered := 0
var lane_changes := 0
var combat_hits := 0
var retreat_violations := 0
var min_worker_distance := INF
var closest_pair := ""
var max_depth_step := 0.0
var completion_time := -1.0
var attack_log := "未実行"
var enemy := {"position": Vector2(865.0, FRONT_Y), "alive": true}


func reset(next_mode := "two") -> void:
	mode = next_mode
	time = 0.0
	delivered = 0
	lane_changes = 0
	combat_hits = 0
	retreat_violations = 0
	min_worker_distance = INF
	closest_pair = ""
	max_depth_step = 0.0
	completion_time = -1.0
	attack_log = "同じ x・別レーンは近接不可"
	enemy = {"position": Vector2(865.0, FRONT_Y), "alive": true}
	agents.clear()
	sources.clear()
	var ys: Array = [BACK_Y, BACK_Y, BACK_Y] if mode == "one" else [BACK_Y, FRONT_Y, BACK_Y]
	for i in 3:
		sources.append({"id": i, "position": Vector2(710.0 + float(i) * 155.0, ys[i]), "remaining": 2, "claimed": -1})
		var p := BASE_DOOR + Vector2(float(i - 1) * 30.0, 0.0)
		agents.append({
			"id": i, "name": ["ネズ吉", "チュー太", "モモ"][i], "position": p,
			"state": "outbound", "route": [], "target": -1, "cargo": 0,
			"gather": 0.0, "retreating": false, "lane_change_count": 0,
			"unloaded": 0, "last_position": p,
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
		if bool(a["retreating"]) and String(a["state"]) in ["outbound", "gather", "chase"]:
			retreat_violations += 1
		match String(a["state"]):
			"outbound":
				if _follow_route(a, delta):
					a["state"] = "gather"
					a["gather"] = 0.0
			"gather":
				var source := _source_for(a)
				if source.is_empty() or int(source["remaining"]) <= 0:
					_assign_source(i)
				else:
					a["gather"] = float(a["gather"]) + delta
					if float(a["gather"]) >= GATHER_SECONDS:
						source["remaining"] = int(source["remaining"]) - 1
						# 同じ鉱脈は採取者が掘り切るまで予約する。帰還中に別の仲間が
						# 同じ足元へ押し寄せないため、待ち行列で通路を詰まらせない。
						if int(source["remaining"]) <= 0:
							source["claimed"] = -1
							a["target"] = -1
						sources[int(source["id"])] = source
						a["cargo"] = int(a["cargo"]) + 1
						a["gather"] = 0.0
						if int(a["cargo"]) >= CARRY_LIMIT or int(source["remaining"]) <= 0:
							_set_return_route(a)
							a["state"] = "returning"
			"returning":
				if _follow_route(a, delta):
					a["state"] = "unload"
			"unload":
				delivered += int(a["cargo"])
				if int(a["cargo"]) > 0:
					a["unloaded"] = int(a["unloaded"]) + int(a["cargo"])
				a["cargo"] = 0
				if bool(a["retreating"]):
					a["state"] = "retreated"
				else:
					_assign_source(i)
			"chase":
				if _follow_route(a, delta):
					if can_melee(Vector2(a["position"]), Vector2(enemy["position"])):
						combat_hits += 1
						enemy["alive"] = false
						attack_log = "同レーンへ移動後に近接成功"
					else:
						attack_log = "FAIL: 別レーンへ誤って命中"
					_set_return_route(a)
					a["state"] = "returning"
		agents[i] = a
	_update_spacing()
	if delivered >= TOTAL_RESOURCE and completion_time < 0.0:
		completion_time = time


func run_for(seconds: float, delta := 0.05) -> void:
	for _frame in ceili(seconds / delta):
		step(delta)


func complete() -> bool:
	return delivered >= TOTAL_RESOURCE and agents.all(func(a): return String(a["state"]) in ["idle", "retreated"])


func cross_lane_melee_is_blocked() -> bool:
	return not can_melee(Vector2(865.0, BACK_Y), Vector2(enemy["position"]))


func can_melee(attacker: Vector2, target: Vector2) -> bool:
	return absf(attacker.x - target.x) <= MELEE_X_REACH and absf(attacker.y - target.y) <= MELEE_DEPTH_REACH


func start_chase(agent_id: int) -> bool:
	if agent_id < 0 or agent_id >= agents.size() or not bool(enemy["alive"]):
		return false
	var a := agents[agent_id]
	if bool(a["retreating"]) or int(a["cargo"]) > 0:
		return false
	_release_source(a)
	a["route"] = _route_between(Vector2(a["position"]), Vector2(enemy["position"]), int(a["id"]))
	a["state"] = "chase"
	attack_log = "追跡中: レーン接続部を経由"
	agents[agent_id] = a
	return true


func start_personal_retreat(agent_id: int) -> bool:
	if agent_id < 0 or agent_id >= agents.size():
		return false
	var a := agents[agent_id]
	if String(a["state"]) in ["retreated", "returning", "unload"]:
		return false
	_release_source(a)
	a["retreating"] = true
	_set_return_route(a)
	a["state"] = "returning"
	agents[agent_id] = a
	return true


func agent_status(agent_id: int) -> String:
	var a := agents[agent_id]
	return "%s: %s / %s" % [a["name"], _state_name(String(a["state"])), lane_name(Vector2(a["position"]).y)]


func lane_name(y: float) -> String:
	return "奥レーン" if absf(y - BACK_Y) < absf(y - FRONT_Y) else "手前レーン"


func remaining_resource() -> int:
	var total := 0
	for source in sources:
		total += int(source["remaining"])
	return total


func _assign_source(agent_id: int) -> void:
	var a := agents[agent_id]
	if bool(a["retreating"]):
		a["state"] = "retreated"
		agents[agent_id] = a
		return
	var reserved_id := int(a["target"])
	if reserved_id >= 0 and reserved_id < sources.size():
		var reserved := sources[reserved_id]
		if int(reserved["remaining"]) > 0 and int(reserved["claimed"]) == agent_id:
			a["route"] = _route_to_source(Vector2(reserved["position"]), int(a["id"]))
			a["state"] = "outbound"
			agents[agent_id] = a
			return
	var best_id := -1
	var best_distance := INF
	for source in sources:
		if int(source["remaining"]) <= 0 or int(source["claimed"]) >= 0:
			continue
		var d := Vector2(a["position"]).distance_to(Vector2(source["position"]))
		if d < best_distance:
			best_distance = d
			best_id = int(source["id"])
	if best_id < 0:
		a["target"] = -1
		a["state"] = "idle"
		agents[agent_id] = a
		return
	var source := sources[best_id]
	source["claimed"] = agent_id
	sources[best_id] = source
	a["target"] = best_id
	a["route"] = _route_to_source(Vector2(source["position"]), int(a["id"]))
	a["state"] = "outbound"
	agents[agent_id] = a


func _source_for(a: Dictionary) -> Dictionary:
	var id := int(a["target"])
	return sources[id] if id >= 0 and id < sources.size() else {}


func _release_source(a: Dictionary) -> void:
	var id := int(a["target"])
	if id >= 0 and id < sources.size():
		var source := sources[id]
		if int(source["claimed"]) == int(a["id"]):
			source["claimed"] = -1
			sources[id] = source
	a["target"] = -1


func _route_to_source(target: Vector2, agent_id: int) -> Array[Vector2]:
	var offset := float(agent_id - 1) * 30.0
	var route: Array[Vector2] = [RAMP_FOOT + Vector2(offset, 0.0), CROSS_BACK + Vector2(offset, 0.0)]
	if absf(target.y - FRONT_Y) < 1.0:
		route.append(CROSS_FRONT + Vector2(offset, 0.0))
	route.append(target + Vector2(-32.0, 0.0))
	return route


func _set_return_route(a: Dictionary) -> void:
	var p := Vector2(a["position"])
	var offset := float(int(a["id"]) - 1) * 30.0
	var route: Array[Vector2] = []
	if absf(p.y - FRONT_Y) < absf(p.y - BACK_Y):
		route.append(CROSS_FRONT + Vector2(offset, 0.0))
		route.append(CROSS_BACK + Vector2(offset, 0.0))
	else:
		route.append(CROSS_BACK + Vector2(offset, 0.0))
	route.append(RAMP_FOOT + Vector2(offset, 0.0))
	route.append(BASE_DOOR + Vector2(offset, 0.0))
	a["route"] = route


func _route_between(from: Vector2, target: Vector2, agent_id: int) -> Array[Vector2]:
	var offset := float(agent_id - 1) * 30.0
	var from_front := absf(from.y - FRONT_Y) < absf(from.y - BACK_Y)
	var target_front := absf(target.y - FRONT_Y) < absf(target.y - BACK_Y)
	var route: Array[Vector2] = []
	if from_front:
		route.append(CROSS_FRONT + Vector2(offset, 0.0))
		route.append(CROSS_BACK + Vector2(offset, 0.0))
	else:
		route.append(CROSS_BACK + Vector2(offset, 0.0))
	if target_front:
		route.append(CROSS_FRONT + Vector2(offset, 0.0))
	route.append(target + Vector2(-28.0, 0.0))
	return route


func _follow_route(a: Dictionary, delta: float) -> bool:
	var route: Array = a["route"]
	if route.is_empty():
		return true
	var p := Vector2(a["position"])
	var target := Vector2(route[0])
	var step := WALK_SPEED * delta
	var before_y := p.y
	var reached := false
	if p.distance_to(target) <= step:
		p = target
		route.pop_front()
		reached = true
	else:
		p += p.direction_to(target) * step
	var depth_step := absf(p.y - before_y)
	max_depth_step = maxf(max_depth_step, depth_step)
	if reached and target.distance_to(CROSS_FRONT + Vector2(float(int(a["id"]) - 1) * 30.0, 0.0)) < 1.0:
		# 手前側の固定接続部を歩き切った時だけ数える。スロープの上下移動はレーン切替ではない。
		a["lane_change_count"] = int(a["lane_change_count"]) + 1
		lane_changes += 1
	a["position"] = p
	a["route"] = route
	return route.is_empty()


func _update_spacing() -> void:
	for i in agents.size():
		for j in range(i + 1, agents.size()):
			var pa := Vector2(agents[i]["position"])
			var pb := Vector2(agents[j]["position"])
			# 接続部を斜めに通る別レーン同士は足元が一瞬近づいても衝突対象にしない。
			# 同一レーンは鉱脈予約と30pxの経路オフセットで常に間隔を持つ。
			if absf(pa.y - pb.y) < 16.0 and pa.distance_to(pb) < MIN_SPACING:
				var middle := (pa.x + pb.x) * 0.5
				if pa.x <= pb.x:
					pa.x = middle - MIN_SPACING * 0.5
					pb.x = middle + MIN_SPACING * 0.5
				else:
					pa.x = middle + MIN_SPACING * 0.5
					pb.x = middle - MIN_SPACING * 0.5
				var a := agents[i]
				var b := agents[j]
				a["position"] = pa
				b["position"] = pb
				agents[i] = a
				agents[j] = b
			if absf(pa.y - pb.y) < 16.0:
				var d := pa.distance_to(pb)
				if d < min_worker_distance:
					min_worker_distance = d
					closest_pair = "%s/%s at %.2fs (%s,%s)" % [agents[i]["name"], agents[j]["name"], time, pa, pb]


func _state_name(state: String) -> String:
	return {
		"outbound": "採取地点へ移動", "gather": "採取", "returning": "スロープへ帰還",
		"unload": "荷卸し", "chase": "追跡", "retreated": "個人退却完了", "idle": "待機",
	}.get(state, state)
