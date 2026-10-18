class_name QuarryTrip
extends RefCounted
## 街道 ⇄ 1鉱床の小さな状態機械。地点の残量・採取途中の進捗は手動セーブにも保存する。
var game
var state := "road"                 # road / approach / parked / recall / returning
var left := 0.0
var near_only := true
var remaining := {}
var progress := {}
var points: Array = []
var visit_generated := {}
var visit_nearby := {}
var visit_discarded := {}
var last_report := {}
var _food_start := 0
var discarded := {}          # プレイヤーが確認して放棄した品目と累計
var loose := {}                      # 満載時の搬入口残置。出発前に必ず倉庫へ回収する
var saved_speed := 60.0
var visits := 0
## 報酬による次回補充予約。奥行き試作の保存を通常版でも安全に読めるよう保持する。
var reward_replenish_pending := false

func setup(g) -> void:
	game = g
	for d in QuarryDB.POINTS:
		remaining[d["id"]] = d["amount"]

## A completed town reward renews the mine for the next visit only.  Accepting
## or cancelling a mission never changes the current site, and live workers
## are not duplicated by an in-place respawn.
func schedule_mission_replenishment() -> void:
	reward_replenish_pending = true

func _apply_reward_replenishment() -> void:
	if not reward_replenish_pending:
		return
	for d in QuarryDB.POINTS:
		remaining[d["id"]] = d["amount"]
		progress.erase(d["id"])
	reward_replenish_pending = false

func sheltered() -> bool:
	return state in ["parked", "recall"]

func recalling() -> bool:
	return state == "recall"

func hostile() -> bool:
	if game.director._busy("attack"):
		return true
	for e in game.enemies_root.get_children():
		if not e.dead and not e.ecological:
			return true
	return false

func select() -> bool:
	if state != "road" or game.game_over or (game.world.active and (game.world.region != "old_mine" or game.world.phase != "stopped")):
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

func crew_ready_to_leave() -> bool:
	if game.game_over or not recalling(): return false
	for w in game.workers:
		if w.away or w.floor_i == 0 or w._climb_dest != null or w.carrying >= 0: return false
		if w.ai.state not in [CharacterAI.State.RETURN_BASE, CharacterAI.State.REST, CharacterAI.State.REST_HERE, CharacterAI.State.DOWN]: return false
	return true

func ready_to_leave() -> bool:
	return loose.is_empty() and crew_ready_to_leave()

## 確認画面に示した全品目・数量が変わっていない場合だけ放棄して出発。
func discard_and_leave(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or snapshot != loose or not crew_ready_to_leave(): return false
	for it in snapshot:
		discarded[it] = int(discarded.get(it, 0)) + int(snapshot[it])
		visit_discarded[it] = int(visit_discarded.get(it, 0)) + int(snapshot[it])
	game.director.note("確認して残置品を放棄: " + cargo_text())
	loose.clear()
	return leave()

func leave() -> bool:
	if not ready_to_leave():
		return false
	last_report = {"generated":visit_generated.duplicate(), "nearby":visit_nearby.duplicate(), "food":game.total_eaten-_food_start, "discarded":visit_discarded.duplicate()}
	for p in points:
		remaining[p.get_meta("quarry_id")] = p.remaining
		progress[p.get_meta("quarry_id")] = p.work
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
	_apply_reward_replenishment()
	visit_generated.clear()
	visit_nearby.clear()
	visit_discarded.clear()
	_food_start = game.total_eaten
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
		p.work = float(progress.get(d["id"], 0.0))
		p.position = d["pos"]
		p.set_meta("quarry_id", d["id"])
		p.set_meta("quarry_group", d["group"])
		game.resources_root.add_child(p)
		points.append(p)
	game.director.note("%sに停車。周囲の生物を目視し、危険なら呼戻し。食料・天候・車体消耗にも注意" % QuarryDB.NAME)

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
		"parked": return stop_reason() if stop_reason() != "" else "停車採取中（襲撃なし）"
		"recall":
			if not loose.is_empty(): return "満載：帰還取消後に消費・加工・設置で軽くするか、全員帰還後に残置品を確認して放棄できます"
			if ready_to_leave(): return "全員帰還・荷物収納済み。街道へ出発できます"
			return "新規作業を止め、仲間と荷物の帰還待ち（休憩・食事は継続）"
	return state


func record_generated(item: int, n: int, from_quarry := true) -> void:
	if not sheltered(): return
	var target := visit_generated if from_quarry else visit_nearby
	target[item] = int(target.get(item,0)) + n

func item_list(items: Dictionary) -> String:
	var names: Array[String] = []
	for it in items:
		if items[it] > 0: names.append("%s×%d" % [GameData.ITEM_NAMES[it],items[it]])
	return "、".join(names) if not names.is_empty() else "なし"

func report_text() -> String:
	var active := sheltered()
	var r := {"generated":visit_generated,"nearby":visit_nearby,"food":game.total_eaten-_food_start,"discarded":visit_discarded} if active else last_report
	if r.is_empty(): return "採取記録はまだありません。現地到着から出発決定までを記録します。"
	return ("今回の滞在（記録中）" if active else "直近の滞在（出発時確定）") + "\n集計範囲：現地到着〜出発決定\n\n対象鉱床から生成：" + item_list(r["generated"]) + "\n周辺の採取から生成：" + item_list(r.get("nearby",{})) + "\n食事に使った食料：%d個\n確認して放棄：%s\n\n生成数は、加工・消費前の数です。倉庫残量や持帰り数ではありません。精錬でできた鉄や、出発前からの所持品は生成数に含めません。" % [r["food"],item_list(r["discarded"])]

func stop_reason() -> String:
	if group_left("近場") + (0 if near_only else group_left("奥")) <= 0: return "選んだ採取範囲は枯渇しています（再訪でも補充なし）"
	if game.storage.free_for(GameData.Item.IRON_ORE) == 0:
		return "採取停止：鉄鉱石1個（重量%d）の空き不足。保有%d＋加工増量予約%d／容量%d。消費・加工・設置で空きを作れます" % [CargoDB.size_of(GameData.Item.IRON_ORE),game.storage.current_weight(),game.storage.processing_reserve(),game.storage.max_weight()]
	return ""
