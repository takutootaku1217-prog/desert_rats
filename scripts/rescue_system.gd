class_name RescueSystem
extends Node

const WAIT_SECONDS := 90.0
const SIMPLE_TREAT_HP := 35.0
const CARRY_SPEED := 0.70
const FRAME_SPEED := 0.90

var game
var incapacitated := {}
var all_down_elapsed := 0.0
var prompt: PanelContainer
var prompt_label: Label

func setup(g) -> void:
	game = g
	call_deferred("_build_prompt")

func _build_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	prompt = PanelContainer.new()
	prompt.position = Vector2(420, 250)
	prompt.custom_minimum_size = Vector2(440, 170)
	prompt.visible = false
	layer.add_child(prompt)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	prompt.add_child(box)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(prompt_label)
	var restart := Button.new()
	restart.text = "チェックポイントから再開"
	restart.pressed.connect(func(): SaveGame.restart_from_checkpoint(game))
	box.add_child(restart)

func worker_index(w) -> int:
	return game.workers.find(w)

func record_for(w) -> Dictionary:
	return incapacitated.get(worker_index(w), {})

func is_carrier(w) -> bool:
	for i in incapacitated:
		if int(incapacitated[i].get("carrier", -1)) == worker_index(w): return true
	return false

func status_text(w) -> String:
	var r := record_for(w)
	if r.is_empty(): return ""
	if bool(r.get("expired", false)): return "救助期限切れ：回収待ち"
	var left := ceili(float(r.get("left", WAIT_SECONDS)))
	if int(r.get("carrier", -1)) >= 0:
		return "搬送中／救助時間停止中" if bool(r.get("carried", false)) else "救助担当が移動中：残り%d秒" % left
	return "救助待ち：残り%d秒" % left

func on_down(w) -> void:
	cancel_carrier(w)
	var i := worker_index(w)
	if i >= 0 and not incapacitated.has(i):
		incapacitated[i] = {"left": WAIT_SECONDS, "carried": false, "carrier": -1, "expired": false, "at_base": false}

func assign(carrier, target) -> bool:
	if carrier == target or carrier.away or carrier.down or target.away or not target.down: return false
	var ti := worker_index(target)
	var ci := worker_index(carrier)
	if ti < 0 or ci < 0 or not incapacitated.has(ti) or is_carrier(carrier): return false
	var r: Dictionary = incapacitated[ti]
	if int(r.get("carrier", -1)) >= 0: return false
	# Rescue is an explicit override: release ordinary reservations first, but
	# preserve any personal cargo/equipment before taking the dedicated carry slot.
	carrier.stop_work_for_rescue()
	r.carrier = ci
	r.carried = false
	incapacitated[ti] = r
	carrier.ai.rescue_target = ti
	carrier.ai._set_state(CharacterAI.State.RESCUE_MOVE)
	return true

func cancel_carrier(carrier) -> void:
	var ci := worker_index(carrier)
	if ci < 0: return
	for i in incapacitated:
		var r: Dictionary = incapacitated[i]
		if int(r.get("carrier", -1)) == ci:
			r.carrier = -1
			r.carried = false
			incapacitated[i] = r
	if carrier != null and carrier.ai != null:
		carrier.ai.rescue_target = -1
		# A cancelled deck-side rescue must leave the dedicated rescue states.
		# Otherwise a return/recall has no ordinary state case to take over and
		# the carrier can remain inert at the interruption point.
		if not carrier.down and carrier.ai.state in [CharacterAI.State.RESCUE_MOVE, CharacterAI.State.RESCUE_CARRY]:
			carrier.ai._set_state(CharacterAI.State.RETURN_BASE)
			carrier.target = game.storage.access_point() + carrier.slot_offset

func carrier_tick(carrier, delta: float) -> bool:
	var ti: int = carrier.ai.rescue_target
	if ti < 0: return false
	if ti >= game.workers.size() or not incapacitated.has(ti):
		cancel_carrier(carrier); return false
	var target = game.workers[ti]
	var r: Dictionary = incapacitated[ti]
	if target == null or not target.down or int(r.get("carrier", -1)) != worker_index(carrier):
		cancel_carrier(carrier); return false
	if not bool(r.get("carried", false)):
		carrier.target = target.position
		carrier.ai._set_state(CharacterAI.State.RESCUE_MOVE)
		if carrier.move_to_target(delta):
			r.carried = true
			incapacitated[ti] = r
			carrier.ai._set_state(CharacterAI.State.RESCUE_CARRY)
		return true
	target.position = carrier.position + Vector2(-12.0 * carrier.facing, 3.0)
	target.floor_i = carrier.floor_i
	carrier.target = game.storage.access_point() + carrier.slot_offset
	carrier.ai._set_state(CharacterAI.State.RESCUE_CARRY)
	if carrier.move_to_target(delta):
		target.position = carrier.position + Vector2(-12.0 * carrier.facing, 3.0)
		_finish_delivery(carrier, target, r)
	return true

func _finish_delivery(carrier, target, r: Dictionary) -> void:
	var ti := worker_index(target)
	var expired := bool(r.get("expired", false))
	incapacitated.erase(ti)
	carrier.ai.rescue_target = -1
	carrier.ai.post_rescue_wait = true
	carrier.ai._set_state(CharacterAI.State.IDLE)
	target.ai.post_rescue_wait = true
	target.ai.return_request = false
	target.unload_owned()
	if expired:
		incapacitated[ti] = {"left": 0.0, "carried": false, "carrier": -1, "expired": true, "at_base": true}
		target.ai._set_state(CharacterAI.State.DOWN)
	else:
		target.down = false
		target.hp = maxf(target.hp, SIMPLE_TREAT_HP)
		target.unload_owned()
		target.ai._set_state(CharacterAI.State.SEARCH)

func revive_at_city(w) -> bool:
	var i := worker_index(w)
	var r: Dictionary = incapacitated.get(i, {})
	if r.is_empty() or not bool(r.get("expired", false)) or not bool(r.get("at_base", false)): return false
	if not game.town.location_ok() or game.town.credits < TownDB.REVIVAL_COST: return false
	game.town.credits -= TownDB.REVIVAL_COST
	incapacitated.erase(i)
	w.down = false
	w.hp = SIMPLE_TREAT_HP
	w.ai.post_rescue_wait = true
	w.ai._set_state(CharacterAI.State.SEARCH)
	return true

func resume(w) -> void:
	w.ai.post_rescue_wait = false
	if not w.down: w.ai._set_state(CharacterAI.State.SEARCH)

func tick(delta: float) -> void:
	var active := 0
	var down_count := 0
	for w in game.workers:
		if w.away: continue
		active += 1
		if w.down: down_count += 1
	for i in incapacitated.keys():
		var r: Dictionary = incapacitated[i]
		# The wait ends only once the carrier has actually picked the target up.
		if bool(r.get("expired", false)) or bool(r.get("carried", false)): continue
		r.left = maxf(0.0, float(r.get("left", WAIT_SECONDS)) - delta)
		if r.left <= 0.0: r.expired = true
		incapacitated[i] = r
	all_down_elapsed = all_down_elapsed + delta if active > 0 and down_count == active else 0.0
	if prompt != null:
		prompt.visible = active > 0 and down_count == active
		if prompt.visible: prompt_label.text = "全員が戦闘不能です。チェックポイントから再開すると、クレジットの10%を失います。"

func snapshot() -> Dictionary:
	return {"version": 1, "incapacitated": incapacitated.duplicate(true), "all_down_elapsed": all_down_elapsed}

func restore(data: Dictionary) -> void:
	incapacitated = data.get("incapacitated", {}).duplicate(true)
	all_down_elapsed = float(data.get("all_down_elapsed", 0.0))
	# Older save payloads had no rescue records. A downed worker must never be
	# left permanently unrecoverable merely because natural revival was removed.
	for w in game.workers:
		var wi := worker_index(w)
		if w.down and not incapacitated.has(wi):
			incapacitated[wi] = {"left": WAIT_SECONDS, "carried": false, "carrier": -1, "expired": false, "at_base": false}
	for i in incapacitated:
		var r: Dictionary = incapacitated[i]
		var ci := int(r.get("carrier", -1))
		if ci >= 0 and ci < game.workers.size(): game.workers[ci].ai.rescue_target = int(i)
