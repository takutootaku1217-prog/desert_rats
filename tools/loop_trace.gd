extends RefCounted
## test_loop の任意トレース。読み取りだけで、乱数・仕事・優先度・状態には触れない。
var wait_start := -1.0
var last_workers := ""
var last_output := ""
var last_event := ""
var last_hull := 100.0
var max_wait := 0.0

func snapshot(game) -> Dictionary:
	var workers := []
	for w in game.workers:
		workers.append({"name": w.char_name, "state": w.ai.status_text(), "job": w.ai.current_job,
			"carry": GameData.ITEM_NAMES.get(w.carrying, "none"), "fatigue": snappedf(w.fatigue, 0.1),
			"hunger": snappedf(w.hunger, 0.1), "hp": snappedf(w.hp, 0.1),
			"stress": snappedf(w.stress, 0.1), "mental": w.mental, "pos": str(w.position),
			"life_needs": CrewStatus.life_needs(w), "rest_done": CrewStatus.rest_done(w),
			"process_priority": w.priorities[GameData.Job.PROCESS], "repair_part": w.ai.repair_part})
	var enemies := []
	for e in game.enemies_root.get_children():
		enemies.append({"kind": e.kind, "hp": e.hp, "dead": e.dead, "attacking": e.is_attacking(), "damage": e.damage})
	var p: BaseProcessor = game.processor
	var repair_claims := {}
	for part in game.base.repair_reserved:
		repair_claims[GameData.PART_NAMES[part]] = game.base.repair_reserved[part].char_name
	return {"workers": workers, "processor_worker": p.worker.char_name if is_instance_valid(p.worker) else "none",
		"work_available": p.has_work_for_worker(), "output": p.output.duplicate(), "current": p.current.get("id", ""),
		"orders": p.orders.map(func(r): return r.get("id", "")), "incoming": p.incoming.map(func(r): return r.get("id", "")),
		"parts": game.base.parts.duplicate(), "fuel": game.base.fuel, "stock": game.storage.inventory.counts.duplicate(),
		"repair_claims": repair_claims, "food_claims": game.food_claims, "total_eaten": game.total_eaten,
		"total_repair": game.base.total_repair, "total_done": p.total_done, "enemies": enemies,
		"events": game.director.active.duplicate(true)}

func emit_record(game, kind: String, data: Dictionary) -> void:
	print("TRACE ", JSON.stringify({"game_seconds": snappedf(game.director.elapsed, 0.01), "kind": kind, "data": data}))

func tick(game) -> void:
	var t: float = game.director.elapsed
	var p: BaseProcessor = game.processor
	var waiting := not p.output.is_empty() and p.worker == null
	if waiting and wait_start < 0.0:
		wait_start = t
		emit_record(game, "output_wait_start", snapshot(game))
	elif not waiting and wait_start >= 0.0:
		max_wait = maxf(max_wait, t - wait_start)
		var record := snapshot(game)
		record["wait_seconds"] = snappedf(t - wait_start, 0.01)
		emit_record(game, "output_wait_end", record)
		wait_start = -1.0
	var worker_states: String = str(game.workers.map(func(w): return [w.ai.state, w.carrying]))
	var output: String = str(p.output)
	# 既知の待ちを含む区間と、ゲームオーバー直前を状態遷移ごとに残す。
	if (t >= 640.0 and t <= 860.0) or t >= 1450.0:
		if worker_states != last_workers or output != last_output:
			emit_record(game, "transition", snapshot(game))
		if game.base.condition(GameData.Part.HULL) < last_hull - 0.5:
			var damage_record := snapshot(game)
			damage_record["hull_loss_in_frame"] = last_hull - game.base.condition(GameData.Part.HULL)
			emit_record(game, "hull_damage", damage_record)
	var event: String = str(game.director.log)
	if event != last_event:
		emit_record(game, "event_log", {"log": game.director.log.duplicate(true)})
	last_workers = worker_states
	last_output = output
	last_event = event
	last_hull = game.base.condition(GameData.Part.HULL)

func finish(game) -> void:
	var record := snapshot(game)
	record["max_output_wait_seconds"] = max_wait
	record["game_over"] = game.game_over
	emit_record(game, "finish", record)
