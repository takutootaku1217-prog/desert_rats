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
	check(injured.carrying == GameData.Item.WOOD, "down retains personal cargo")
	carrier.carrying = GameData.Item.STONE
	check(main.rescue.assign(carrier, injured), "manual carrier designation succeeds even with carrier cargo")
	check(not main.rescue.assign(spare, injured), "duplicate carrier reservation is rejected")
	var waiting_before_pickup: float = float(main.rescue.record_for(injured).left)
	main.rescue.tick(5.0)
	check(float(main.rescue.record_for(injured).left) < waiting_before_pickup, "assigned-but-not-picked-up rescue timer keeps counting")
	for n in 500:
		main.rescue.carrier_tick(carrier, 0.1)
		if int(main.rescue.record_for(injured).get("carrier", -1)) >= 0 and bool(main.rescue.record_for(injured).get("carried", false)): break
	var left_before: float = float(main.rescue.record_for(injured).left)
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
	print("== RESULT: %s ==" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)

func fresh() -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
