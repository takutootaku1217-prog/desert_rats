extends SceneTree

var fails := 0
var main

func check(ok: bool, text: String) -> void:
	if ok: print("  ok   ", text)
	else:
		fails += 1
		print("  FAIL ", text)

func _initialize() -> void:
	await fresh()
	var injured = main.workers[0]
	var carrier = main.workers[1]
	var spare = main.workers[2]
	for w in main.workers: w.set_process(false)
	injured.position = Vector2(900, GameData.LO_Y)
	carrier.position = Vector2(700, GameData.LO_Y)
	spare.position = Vector2(620, GameData.LO_Y)
	injured.carrying = GameData.Item.WOOD
	CrewStatus.damage(injured, 999.0)
	check(injured.down and main.rescue.record_for(injured).left == RescueSystem.WAIT_SECONDS, "down starts a 90 second rescue wait")
	check(main.rescue.status_text(injured).begins_with("救助待ち：残り"), "downed worker shows the localized waiting status with remaining seconds")
	check(injured.carrying == GameData.Item.WOOD, "down retains personal cargo")
	carrier.carrying = GameData.Item.STONE
	check(main.rescue.assign(carrier, injured), "manual carrier designation succeeds even with carrier cargo")
	check(main.rescue.status_text(injured).begins_with("救助担当が移動中：残り"), "assigned carrier shows localized travel status while the timer continues")
	check(not main.rescue.assign(spare, injured), "duplicate carrier reservation is rejected")
	var waiting_before_pickup: float = float(main.rescue.record_for(injured).left)
	main.rescue.tick(5.0)
	check(float(main.rescue.record_for(injured).left) < waiting_before_pickup, "assigned-but-not-picked-up rescue timer keeps counting")
	for n in 500:
		main.rescue.carrier_tick(carrier, 0.1)
		if int(main.rescue.record_for(injured).get("carrier", -1)) >= 0 and bool(main.rescue.record_for(injured).get("carried", false)): break
	var left_before: float = float(main.rescue.record_for(injured).left)
	check(main.rescue.status_text(injured) == "搬送中／救助時間停止中", "carried rescue shows the localized paused-timer status")
	main.rescue.tick(5.0)
	check(is_equal_approx(float(main.rescue.record_for(injured).left), left_before), "pickup pauses rescue timer")
	CrewStatus.damage(carrier, 999.0)
	check(int(main.rescue.record_for(injured).get("carrier", -1)) < 0 and not bool(main.rescue.record_for(injured).get("carried", true)), "carrier down cancels transport and resumes waiting")
	check(main.rescue.assign(spare, injured), "a new explicit carrier can be assigned after cancellation")
	for n in 1200:
		main.rescue.carrier_tick(spare, 0.1)
		if not injured.down: break
	check(not injured.down and injured.hp >= RescueSystem.SIMPLE_TREAT_HP and injured.ai.post_rescue_wait, "return provides simple treatment then waits for player resume")
	main.rescue.resume(injured)
	check(not injured.ai.post_rescue_wait, "resume remains explicit and does not require HP 70")
	# A carrier who is told to withdraw on deck must leave the rescue state, then
	# follow the normal return path instead of remaining frozen in RESCUE_MOVE.
	CrewStatus.damage(injured, 999.0)
	carrier = spare
	carrier.position = Vector2(720, GameData.LO_Y)
	injured.position = Vector2(920, GameData.LO_Y)
	check(main.rescue.assign(carrier, injured), "deck-side rescue can be assigned for return interruption")
	carrier.ai.return_request = true
	carrier.ai.tick(0.1)
	check(carrier.ai.rescue_target < 0 and carrier.ai.state == CharacterAI.State.RETURN_BASE and int(main.rescue.record_for(injured).get("carrier", -1)) < 0, "individual return interruption cancels rescue and enters the normal return state")
	carrier.ai.cancel_return()
	carrier.hp = CrewStatusDB.MAX_HP
	carrier.floor_i = 0
	injured.floor_i = 0
	check(main.rescue.assign(carrier, injured), "rescue can be reassigned for the automatic HP interruption")
	carrier.hp = CrewStatusDB.MAX_HP * 0.30
	carrier.ai.return_request = false
	carrier.ai.tick(0.1)
	check(carrier.ai.return_request and carrier.ai.rescue_target < 0 and carrier.ai.state == CharacterAI.State.RETURN_BASE and int(main.rescue.record_for(injured).get("carrier", -1)) < 0, "automatic 30% HP return cancels rescue and enters the normal return state")
	CrewStatus.damage(injured, 999.0)
	var r: Dictionary = main.rescue.record_for(injured)
	r.left = 0.05
	main.rescue.incapacitated[main.rescue.worker_index(injured)] = r
	main.rescue.tick(1.0)
	check(bool(main.rescue.record_for(injured).get("expired", false)), "expired crew stay as recoverable records")
	check(main.rescue.status_text(injured) == "救助期限切れ：回収待ち", "expired worker shows the localized recovery-wait status")
	injured.carrying = GameData.Item.WOOD
	main.rescue.assign(spare, injured)
	for n in 1200:
		main.rescue.carrier_tick(spare, 0.1)
		if bool(main.rescue.record_for(injured).get("at_base", false)): break
	check(injured.carrying < 0 and bool(main.rescue.record_for(injured).get("at_base", false)), "expired rescue unloads cargo at base so city revival travel remains available")
	check(not main.rescue.revive_at_city(injured), "city revival rejects missing city/funds without charging")
	await fresh()
	injured = main.workers[0]
	carrier = main.workers[1]
	for w in main.workers: w.set_process(false)
	injured.position = Vector2(900, GameData.LO_Y)
	carrier.position = Vector2(760, GameData.LO_Y)
	injured.carrying = GameData.Item.WOOD
	injured.carry_n = 2
	injured.carry_bonus = {GameData.Item.STONE: 3}
	CrewStatus.damage(injured, 999.0)
	check(main.rescue.assign(carrier, injured), "carried-rescue snapshot assignment succeeds")
	for n in 500:
		main.rescue.carrier_tick(carrier, 0.1)
		if bool(main.rescue.record_for(injured).get("carried", false)): break
	main.rescue.tick(2.0)
	var left_at_save: float = float(main.rescue.record_for(injured).left)
	var saved := SaveGame.capture(main)
	check(SaveGame.validate(saved, main), "actual carried rescue snapshot is save-valid")
	injured.carrying = -1
	injured.carry_bonus.clear()
	carrier.ai.rescue_target = -1
	carrier.ai._set_state(CharacterAI.State.SEARCH)
	main.rescue.incapacitated.clear()
	check(SaveGame.apply(main, saved), "actual carried rescue snapshot restores")
	injured = main.workers[0]
	carrier = main.workers[1]
	var restored: Dictionary = main.rescue.record_for(injured)
	check(injured.down and bool(restored.get("carried", false)) and is_equal_approx(float(restored.left), left_at_save) and int(restored.get("carrier", -1)) == main.rescue.worker_index(carrier), "restore preserves carried timer and carrier reservation")
	check(carrier.ai.rescue_target == main.rescue.worker_index(injured) and carrier.ai.state == CharacterAI.State.RESCUE_CARRY, "restore preserves both rescue AI states")
	check(injured.carrying == GameData.Item.WOOD and injured.carry_n == 2 and int(injured.carry_bonus.get(GameData.Item.STONE, 0)) == 3, "restore preserves downed worker personal cargo")
	for w in main.workers:
		if not w.down: CrewStatus.damage(w, 999.0)
	main.rescue.tick(0.1)
	check(main.rescue.prompt != null and main.rescue.prompt.visible, "all-down checkpoint restart prompt appears immediately")
	check(main.rescue.prompt_label.text.contains("チェックポイントから再開") and main.rescue.prompt_label.text.contains("10%"), "all-down prompt is localized and explains the checkpoint loss")
	await fresh()
	for w in main.workers: w.set_process(false)
	var recalled = main.workers[0]
	var excluded = main.workers[1]
	recalled.floor_i = 0
	excluded.floor_i = 0
	recalled.position = Vector2(850, GameData.LO_Y)
	excluded.position = Vector2(900, GameData.LO_Y)
	recalled.ai._set_state(CharacterAI.State.SEARCH)
	excluded.ai._set_state(CharacterAI.State.SEARCH)
	excluded.recall_exempt = true
	var saved_exclusion := SaveGame.capture(main)
	excluded.recall_exempt = false
	check(SaveGame.apply(main, saved_exclusion) and main.workers[1].recall_exempt, "group-recall exclusion persists through a saved run")
	recalled = main.workers[0]
	excluded = main.workers[1]
	for w in [recalled, excluded]:
		w.set_process(false)
		w.floor_i = 0
		w.hp = CrewStatusDB.MAX_HP
		w.ai.return_request = false
		recalled.ai._set_state(CharacterAI.State.SEARCH)
		excluded.ai._set_state(CharacterAI.State.SEARCH)
	var ongoing = GatherPoint.new()
	ongoing.setup(main, "tree")
	ongoing.position = Vector2(1100, GameData.LO_Y)
	main.resources_root.add_child(ongoing)
	ongoing.claimed_by = excluded
	excluded.ai.res = ongoing
	excluded.ai._set_state(CharacterAI.State.MOVE_TO_RESOURCE)
	main.operations.set_stance("recall")
	recalled.ai.tick(0.1)
	excluded.ai.tick(0.1)
	check(recalled.ai.state == CharacterAI.State.RETURN_BASE and excluded.ai.state == CharacterAI.State.MOVE_TO_RESOURCE and excluded.ai.res == ongoing and ongoing.claimed_by == excluded, "group recall returns included crew while an excluded crew member keeps the assigned gathering instruction")
	check(excluded.ai.request_return(), "an excluded crew member can still receive an individual return order")
	excluded.ai.tick(0.1)
	check(excluded.ai.state == CharacterAI.State.RETURN_BASE, "individual return remains effective while group recall excludes that crew member")
	excluded.ai.cancel_return()
	excluded.ai._set_state(CharacterAI.State.SEARCH)
	CrewStatus.damage(recalled, 999.0)
	check(main.rescue.assign(excluded, recalled), "an excluded crew member can be explicitly assigned as a rescue carrier during group recall")
	excluded.ai.tick(0.1)
	check(excluded.ai.rescue_target == main.rescue.worker_index(recalled) and main.rescue.is_carrier(excluded), "group recall does not cancel an excluded carrier on the next AI tick")
	excluded.hp = CrewStatusDB.MAX_HP * 0.30
	excluded.ai.tick(0.1)
	check(excluded.ai.return_request and excluded.ai.state == CharacterAI.State.RETURN_BASE, "30 percent outdoor withdrawal overrides group-recall exclusion")
	main.operations.set_stance("normal")
	await fresh()
	for w in main.workers: w.set_process(false)
	var field_worker = main.workers[0]
	field_worker.floor_i = 0
	field_worker.position = Vector2(900, GameData.LO_Y)
	for state in [CharacterAI.State.MOVE_TO_RESOURCE, CharacterAI.State.GATHER, CharacterAI.State.HUNT_MOVE, CharacterAI.State.HUNT_ATTACK, CharacterAI.State.MISSION_RECOVERY_MOVE, CharacterAI.State.XFER_MOVE, CharacterAI.State.COMBAT_MOVE]:
		field_worker.hp = CrewStatusDB.MAX_HP * 0.30
		field_worker.ai.return_request = false
		field_worker.ai.manual_attack = state == CharacterAI.State.COMBAT_MOVE
		field_worker.ai._set_state(state)
		field_worker.ai.tick(0.1)
		check(field_worker.ai.return_request and field_worker.ai.state == CharacterAI.State.RETURN_BASE, "30 percent outdoor withdrawal interrupts %s" % CharacterAI.STATE_TEXT[state])
		field_worker.ai.cancel_return()
		field_worker.ai._set_state(CharacterAI.State.SEARCH)
	field_worker.floor_i = 1
	field_worker.hp = CrewStatusDB.MAX_HP * 0.30
	field_worker.ai.return_request = false
	field_worker.ai._set_state(CharacterAI.State.REST)
	field_worker.ai.tick(0.1)
	check(not field_worker.ai.return_request and field_worker.ai.state == CharacterAI.State.REST, "deck-side low-HP rest is not converted into an outdoor withdrawal")
	print("== RESULT: %s ==" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)

func fresh() -> void:
	if main != null:
		main.set_process(false)
		for worker in main.workers:
			worker.set_process(false)
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# This test replaces the Main scene in one SceneTree; retain the new owner
	# explicitly so a FieldOperations node cannot keep the previous fixture.
	main.operations.game = main
