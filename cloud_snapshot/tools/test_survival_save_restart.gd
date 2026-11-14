extends "res://tools/survival_save_common.gd"
## Phase B (a NEW Godot process): read/apply the save of test_survival_save_cycle, check the restored ledger exactly,
## then continue with the ordinary stepping: next departure, natural hunt, stay, return, market. Check the ledger balance:
## food/meat/currency/fuel/director time/total_eaten change only through natural hunting, cooking, eating, trading and travel.
## Fixture/API input: same fixture as phase A; no supply, currency, kill or clock injection. Limited, not a survival guarantee.
func _init() -> void: call_deferred("_run")
func _run() -> void:
	if OS.get_environment("FLUID_TEST_HOME") == "": quit(2); return
	var saved_ledger = str_to_var(FileAccess.get_file_as_string(LEDGER_PATH))
	_check(saved_ledger is Dictionary,"ledger of process 1 is readable")
	if not saved_ledger is Dictionary: quit(1); return
	await _fresh()
	_setup_fixture()
	var before := FileAccess.get_sha256(SAVE_PATH)
	_check(SaveGame.apply(main,SaveGame.read(SAVE_PATH)),"new process reads and applies the real save")
	_check(FileAccess.get_sha256(SAVE_PATH) == before,"loading does not rewrite the save file")
	var restored := _ledger()
	_check(restored == saved_ledger,"restored ledger equals the saved one exactly (food, meat, hide, bone, fuel, credits, parts, eaten, hunted, director time, hunger, reservations, world, away flags)")
	if restored != saved_ledger:
		for k in saved_ledger:
			if restored.get(k) != saved_ledger[k]: print("DIFF %s saved=%s restored=%s" % [k,saved_ledger[k],restored.get(k)])
	var start := _ledger()
	var food0: int = start.food
	var meat0: int = start.meat
	var fuel0: float = start.fuel
	var credits0: int = start.credits
	var eaten0: int = start.eaten
	var hunted0: int = start.hunted
	var t0: float = main.director.elapsed
	_check(main.director.enabled and main.world.region == "a_start" and main.world.phase == "stopped","normal director on, base stopped at the town after restart")
	# next departure and the ordinary stepping
	var ok := await _leg("b_forest")
	_check(ok,"the next departure after restart works (real world request and travel)")
	var fuel_after_leg: float = main.base.fuel
	_check(fuel_after_leg < fuel0,"travel consumed fuel after restart (%.1f -> %.1f)"%[fuel0,fuel_after_leg])
	await _wait(200.0,true)
	for dest in ["c_quarry","d_yard","a_start"]:
		if not ok or main.game_over: break
		ok = await _leg(dest)
	var survived: bool = not main.game_over
	_check(survived,"no game over in this continuation (a natural game over would be reported as a strategy/seed result, not a code defect)")
	_check(ok and main.world.region == "a_start" and main.world.phase == "stopped","returned to the town and stopped safely after restart")
	var credits_before_market: int = main.town.credits
	_market()
	_check(main.director.elapsed > t0 + 100.0,"the director world clock advanced in the ordinary process (%.1f s), not stopped"%(main.director.elapsed - t0))
	# Wait in the safe town (hunger keeps running; the director clock pauses there) until a natural meal happens. No food is injected.
	var waited := 0.0
	while meals == 0 and waited < 1500.0 and not main.game_over:
		await _wait(100.0)
		waited += 100.0
	_check(meals > 0,"a natural meal happened after restart (hunger restored, one food eaten) after %.0f s in town"%waited)
	var end := _ledger()
	_check(int(end.credits) == credits0 + earned - spent,"currency ledger balances: only natural sales/purchases changed credits (earned %d, spent %d)"%[earned,spent])
	var unprocessed: int = _owned(GameData.Item.MEAT) + int(main.processor.committed_inputs().get(GameData.Item.MEAT,0))
	var cooked: int = meat0 + hunt_meat - unprocessed - sold_meat
	_check(int(end.food) + int(end.eaten) == food0 + eaten0 + 2 * cooked + purchases,"food balance: owned + eaten = start + 2 x cooked + purchased (cooked %d, eaten %d, purchased %d)"%[cooked,int(end.eaten)-eaten0,purchases])
	_check(witness_kills > 0 and hunt_meat > 0 and cooked > 0,"after restart real hunting and cooking happened (independently witnessed deaths %d, hunt meat %d, cooked %d); nothing injected"%[witness_kills,hunt_meat,cooked])
	_check(int(end.hunted) - hunted0 == witness_kills,"total_hunted grew by %d and equals the independently witnessed creature deaths (%d): each kill counted once"%[int(end.hunted)-hunted0,witness_kills])
	_check(int(end.eaten) - eaten0 == meals,"total_eaten grew exactly by the observed natural meals (%d)"%meals)
	_check(int(end.fuel_item) >= 0 and int(end.kit) >= 0 and int(end.hide) >= 0 and int(end.bone) >= 0,"no stock went negative")
	_check(not main.base.parts.values().any(func(v): return float(v) > 100.0 or float(v) < 0.0),"damage values stay within 0..100")
	_check(_reservation_issue() == "","reservations have real owners in matching states, none left dangling (%s)"%_reservation_issue())
	print("LEDGER_B " + JSON.stringify(end))
	print("INFO seconds=%.1f meals=%d witness_kills=%d ids=%s hunt_meat=%d cooked=%d sold_meat=%d purchases=%d earned=%d spent=%d survived=%s" % [seconds,meals,witness_kills,witness_ids,hunt_meat,cooked,sold_meat,purchases,earned,spent,survived])
	main.free()
	print("RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
