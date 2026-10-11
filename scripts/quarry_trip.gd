class_name QuarryTrip
extends RefCounted
## 街道 ⇄ 1鉱床の小さな状態機械。地点の残量はこのゲーム実行中だけ保持する。
var game
var state := "road"                 # road / approach / parked / recall / returning
var left := 0.0
var near_only := true
var remaining := {}
var points: Array = []
var loose := {}                      # 満載時の搬入口残置。出発前に必ず倉庫へ回収する
var saved_speed := 60.0
var visits := 0

func setup(g) -> void:
	game = g
	for d in QuarryDB.POINTS:
		remaining[d["id"]] = d["amount"]

func sheltered() -> bool:
	return state in ["parked", "recall"]

func recalling() -> bool:
	return state == "recall"

func hostile() -> bool:
	if game.director._busy("attack"):
		return true
	for e in game.enemies_root.get_children():
		if not e.dead:
			return true
	return false

func select() -> bool:
	if state != "road" or game.game_over:
		return false
	saved_speed = game.target_speed if game.target_speed > 0.0 else 60.0
	game.target_speed = saved_speed
	left = QuarryDB.TRAVEL_DISTANCE
	state = "approach"
	game.director.note("%sへ向かう" % QuarryDB.NAME)
	return true

func cancel() -> bool:
	if game.game_over:
		return false
	if state == "approach":
		state = "road"
		return true
	if state == "recall":
		state = "parked"
		for w in game.workers:
			if w.ai.state == CharacterAI.State.RETURN_BASE:
				w.ai._set_state(CharacterAI.State.SEARCH)
		return true
	return false

func request_departure() -> bool:
	if state != "parked" or game.game_over:
		return false
	state = "recall"
	return true

func ready_to_leave() -> bool:
	if game.game_over or not recalling() or not loose.is_empty():
		return false
	for w in game.workers:
		if w.away or w.floor_i == 0 or w._climb_dest != null or w.carrying >= 0:
			return false
		# 帰還処理が実際に仕事を解放したことも確認（室内の新規作業を残さない）。
		if w.ai.state not in [CharacterAI.State.RETURN_BASE, CharacterAI.State.REST, CharacterAI.State.REST_HERE, CharacterAI.State.DOWN]:
			return false
	return true

func leave() -> bool:
	if not ready_to_leave():
		return false
	for p in points:
		remaining[p.get_meta("quarry_id")] = p.remaining
		game.resources_root.remove_child(p)
		p.queue_free()
	points.clear()
	state = "returning"
	left = QuarryDB.TRAVEL_DISTANCE
	game.target_speed = saved_speed
	for w in game.workers:
		if w.ai.state == CharacterAI.State.RETURN_BASE:
			w.ai._set_state(CharacterAI.State.SEARCH)
	game.director.note("全員と荷物を回収し、街道へ戻る。未採取の鉱床は残る")
	return true

func speed_limit(speed: float, delta: float) -> float:
	if sheltered():
		return 0.0
	if state in ["approach", "returning"]:
		return minf(speed, left / maxf(delta, 0.00001))
	return speed

func tick(dist: float) -> void:
	if state in ["approach", "returning"]:
		left = maxf(0.0, left - dist)
		if left <= 0.001:
			if state == "returning":
				state = "road"
			elif not hostile():
				_arrive()
	if sheltered():
		# 倉庫に空きができたら残置を回収。入りきる個数だけ入れるので廃棄しない。
		for it in loose.keys():
			var n := mini(int(loose[it]), game.storage.free_for(it))
			if n > 0:
				game.storage.inventory.add(it, n)
				loose[it] -= n
			if loose[it] <= 0:
				loose.erase(it)

func _arrive() -> void:
	state = "parked"
	game.scroll_speed = 0.0
	visits += 1
	for d in QuarryDB.POINTS:
		var p := GatherPoint.new()
		# 固定地点を訪れるたびに残量を抽選し直さない。
		p.game = game
		p.kind = "vein"
		p.item = GameData.Item.IRON_ORE
		p.max_amount = d["amount"]
		p.remaining = remaining[d["id"]]
		p.position = d["pos"]
		p.set_meta("quarry_id", d["id"])
		p.set_meta("quarry_group", d["group"])
		game.resources_root.add_child(p)
		points.append(p)
	game.director.note("%sに停車。襲撃なし、食料・天候・車体消耗には注意" % QuarryDB.NAME)

func allowed_resource(r) -> bool:
	return not r.has_meta("quarry_id") or not near_only or r.get_meta("quarry_group") == "近場"

func keep_overflow(item: int, n: int) -> void:
	loose[item] = int(loose.get(item, 0)) + n

func group_left(group: String) -> int:
	var total := 0
	if sheltered():
		for p in points:
			if p.get_meta("quarry_group") == group:
				total += p.remaining
	else:
		for d in QuarryDB.POINTS:
			if d["group"] == group:
				total += int(remaining[d["id"]])
	return total

func cargo_text() -> String:
	var parts: Array[String] = []
	for it in loose:
		parts.append("%s×%d" % [GameData.ITEM_NAMES[it], loose[it]])
	return "、".join(parts) if not parts.is_empty() else "なし"

func status_text() -> String:
	match state:
		"road": return "街道を移動中"
		"approach": return "入場待ち：街道の襲撃が終わるまで待機" if left <= 0.001 else "鉱床へ移動中：残り %.2f km" % (left / 2500.0)
		"returning": return "街道へ復帰中：残り %.2f km" % (left / 2500.0)
		"parked": return "停車採取中（襲撃なし）"
		"recall":
			if not loose.is_empty(): return "満載：帰還を取り消し、制作・運搬で倉庫に空きを作ってください"
			if ready_to_leave(): return "全員帰還・荷物収納済み。街道へ出発できます"
			return "新規作業を止め、仲間と荷物の帰還待ち（休憩・食事は継続）"
	return state
