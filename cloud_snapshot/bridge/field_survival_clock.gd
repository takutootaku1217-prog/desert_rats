class_name FieldSurvivalClock
extends RefCounted
## Narrow field authority. Never runs Main/Worker/AI ticks or unattended production.
const TOKEN_META := "field_life_generation"
const LEDGER_META := "field_life_paid"
const COMMITTED_META := "field_life_committed"
var game
var session
var reason := ""
var bound := false

static func reset_runtime(g) -> void:
	if g.world != null: g.world.release_regeneration(g.world.regeneration_owner,true)
	if g.has_meta(TOKEN_META): g.remove_meta(TOKEN_META)
	if g.has_meta(LEDGER_META): g.remove_meta(LEDGER_META)
	if g.has_meta(COMMITTED_META): g.remove_meta(COMMITTED_META)
	if g.has_meta("field_life_save_layer"):
		if g.save_ui != null: g.save_ui.layer = int(g.get_meta("field_life_save_layer"))
		g.remove_meta("field_life_save_layer")

func setup(g, s) -> Dictionary:
	game = g
	session = s
	bound = false
	if game == null or session == null:
		return {"ok": false, "reason": "現地時計の対象がありません"}
	if game.world.regeneration_owner != null and game.world.regeneration_owner != session and not game.world.regeneration_owner.committed and game.world.regeneration_owner.session_id != session.session_id:
		return {"ok":false,"reason":"C source already belongs to another live session"}
	var identity: Dictionary = session._workers_match(game)
	if not identity.ok: return identity
	if not game.has_meta(TOKEN_META):
		game.set_meta(TOKEN_META, "%d:%d:%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), game.get_instance_id()])
	var token := str(game.get_meta(TOKEN_META))
	if not session.life_clock_token.is_empty() and session.life_clock_token != token:
		return {"ok": false, "reason": "現地保存だけでは別実行の時間・在庫を復元できません。通常の本体保存を使用してください"}
	var completed: Dictionary = game.get_meta(COMMITTED_META, {})
	if completed.has(session.session_id):
		return {"ok": false, "reason": "生命時計: この現地sessionは確定済みです"}
	var ledger: Dictionary = game.get_meta(LEDGER_META, {})
	if session.life_clock_paid + 0.00001 < float(ledger.get(session.session_id, 0.0)):
		return {"ok": false, "reason": "古い現地保存では時間・空腹・在庫を巻き戻せません。現在の状態を維持しました"}
	session.life_clock_token = token
	for actor in session.actors.values():
		var w = game.workers[int(actor.worker_index)]
		if not actor.has("hunger"): actor.hunger = float(w.hunger)
		if not actor.has("calm"): actor.calm = float(w.calm)
		if not actor.has("mental"): actor.mental = int(w.mental)
	ledger[session.session_id] = session.life_clock_paid
	game.set_meta(LEDGER_META, ledger)
	game.world.regeneration_owner = session
	bound = true
	return {"ok": true}

func is_current() -> bool:
	if not bound or not is_instance_valid(game) or not is_instance_valid(session): return false
	if not game.is_inside_tree() or game.is_queued_for_deletion(): return false
	if game.world.regeneration_owner != session and not session.committed:return false
	var completed: Dictionary = game.get_meta(COMMITTED_META, {})
	if completed.has(session.session_id) and not session.committed: return false
	var ledger: Dictionary = game.get_meta(LEDGER_META, {})
	return str(game.get_meta(TOKEN_META, "")) == session.life_clock_token and session.life_clock_paid + 0.00001 >= float(ledger.get(session.session_id, 0.0))

func tick(delta: float) -> void:
	# A retained RefCounted clock can outlive its Main Node. Invalidate before
	# reading any owner property; never attach it to a recreated runtime.
	if not is_instance_valid(game) or not is_instance_valid(session):
		bound = false
		reason = "元の現地実行が終了したため古い時計を停止"
		return
	if not game.is_inside_tree() or game.is_queued_for_deletion():
		bound = false
		reason = "元の現地画面が終了したため古い時計を停止"
		return
	if not bound or delta <= 0.0 or game.game_over or game.get_tree().paused or session.committed:
		return
	if not is_current():
		bound = false
		reason = "別の現地状態または通常読込で時計が更新されました。古い表示の進行を停止"
		return
	session.tick(delta)
	var unpaid: float = maxf(0.0, session.elapsed - session.life_clock_paid)
	if unpaid <= 0.0: return
	# Session damage and cargo always win over old side-view worker snapshots.
	var projected: Dictionary = session.apply_projection_to_workers(game)
	if not projected.ok:
		reason = str(projected.reason)
		return
	game.director.tick(unpaid, 0.0)
	# Other locations settle lazily against this game time at next normal sync.
	# Main source rows remain unchanged until the field return boundary.
	game.base.leak_fuel(unpaid, 0.0)
	game.base.wear_by(unpaid, 0.0)
	for actor in session.actors.values():
		var w = game.workers[int(actor.worker_index)]
		# The field has no sleeping/resting action. Do not heal an old sleeping pose.
		var old_ai: int = w.ai.state
		var old_sleep: bool = w.sleeping
		var old_rest: bool = w.resting
		w.sleeping = false
		w.resting = false
		var state := str(actor.get("state", "idle"))
		w.ai.state = CharacterAI.State.IDLE if state in ["idle", "safe_wait", "capacity_idle", "injured_wait", "wait_relay", "dock_wait", "down"] else CharacterAI.State.SEARCH
		CrewStatus._tick_hunger(w, unpaid)
		# Outpost combat already accounts for combat fatigue in the session.
		if state != "combat": CrewStatus._tick_fatigue(w, unpaid)
		CrewStatus._tick_mental(w, unpaid)
		w.ai.state = old_ai
		w.sleeping = old_sleep
		w.resting = old_rest
		actor["life_move_mult"] = CrewStatus.move_mult(w)
		for key in ["hp", "fatigue", "stress", "hunger", "calm", "mental", "down"]:
			actor[key] = w.get(key)
	session.life_clock_paid = session.elapsed
	var ledger: Dictionary = game.get_meta(LEDGER_META, {})
	ledger[session.session_id] = session.life_clock_paid
	game.set_meta(LEDGER_META, ledger)
	if (GameData.ENABLE_COMBAT and game.base.hp <= 0.0) or (GameData.ENABLE_RAIDS and game.base.parts[GameData.Part.HULL] <= 0.0):
		if game.mine_arrival_gate != null and game.mine_arrival_gate.has_method("fail_field_to_menu"):
			if bool(game.mine_arrival_gate.call("fail_field_to_menu", "現地活動中に車体が停止しました")): return
		game._game_over()
		if game._over_layer != null: game._over_layer.layer = 100
		if game.save_ui != null:
			game.set_meta("field_life_save_layer", game.save_ui.layer)
			game.save_ui.layer = 120

func status_text() -> String:
	if not reason.is_empty(): return reason
	if session.phase == "ready_to_exit": return "帰還完了：確定待ち（一時停止）・帰還を確定してください"
	var deployed: int = session.actors.size()
	var aboard := 0
	for index in game.workers.size():
		var assigned := false
		for actor in session.actors.values():
			if int(actor.worker_index) == index: assigned = true
		if not assigned and not game.workers[index].away: aboard += 1
	var text := "現地%d人 / 車内%d人 ・時間/空腹/天候進行・入口固定" % [deployed, aboard]
	text += "\n全員現地：調理・食事は帰還後（自動給食なし）" if aboard == 0 else "\n残留者あり：この検証画面では作業AI停止、調理・食事は帰還後"
	for actor in session.actors.values():
		if float(actor.get("hunger", 100.0)) < CrewStatusDB.EAT_BELOW:
			text += " / 空腹：帰還ボタンで食事へ"
			break
	return text

## Display only: existing authoritative values, no simulation or balancing.
func vehicle_status_text() -> String:
	var hull := float(game.base.parts[GameData.Part.HULL])
	var drive := float(game.base.parts[GameData.Part.DRIVE])
	var text := "車体 %.1f /100　走行 %.1f /100\n燃料 %.1f /%.0f" % [hull, drive, game.base.fuel, GameData.FUEL_CAP]
	if hull < GameData.PART_BAD or drive < GameData.PART_BAD:
		text += "　! 要修理：帰還を検討"
	if game.base.fuel <= GameData.FUEL_CAP * 0.2: text += "\n! 燃料少：帰還後に補給"
	if game.base.engine_leaking(): text += "\n! 燃料漏れ：修理が必要"
	var weather: Array[String] = []
	for event in game.director.active:
		var definition: Dictionary = EventDB.EVENTS.get(str(event.id), {})
		if definition.get("kind", "") == "weather": weather.append(str(definition.get("name", event.id)))
	text += "\n天候：" + (" / ".join(weather) if not weather.is_empty() else "発生中なし")
	# Display active effects, not obsolete passive vehicle wear. Travel-only
	# modifiers are labelled explicitly: this field's base stays stationary.
	var travel: Array[String] = []
	var crew: Array[String] = []
	if not is_equal_approx(game.director.speed_mult(), 1.0): travel.append("速度×%.2f" % game.director.speed_mult())
	if not is_equal_approx(game.director.burn_mult(), 1.0): travel.append("燃料×%.2f" % game.director.burn_mult())
	if not is_equal_approx(game.director.energy_mult(), 1.0): crew.append("疲労×%.2f" % game.director.energy_mult())
	if not is_equal_approx(game.director.food_mult(), 1.0): crew.append("空腹進行×%.2f" % game.director.food_mult())
	if not travel.is_empty(): text += "\n移動時：" + " / ".join(travel)
	if not crew.is_empty(): text += "\n現在補正：" + " / ".join(crew)
	return text

func failure_status_text() -> String:
	var tests: Array[String] = []
	if game.base.parts[GameData.Part.HULL] <= 0.0: tests.append("HULL 0")
	if game.base.hp <= 0.0: tests.append("拠点HP 0")
	for actor in session.actors.values():
		if bool(actor.get("down", false)): tests.append("仲間戦闘不能"); break
	var text := "停止判定：" + (" / ".join(tests) if not tests.is_empty() else "現地終了")
	text += "\n" + vehicle_status_text()
	text += "\n直近の記録（原因を断定するものではありません）："
	if game.director.log.is_empty(): text += "記録なし"
	for entry in game.director.log.slice(maxi(0, game.director.log.size() - 2)):
		text += "\n%.1f秒 %s" % [float(entry.get("at", 0.0)), str(entry.get("text", ""))]
	return text
