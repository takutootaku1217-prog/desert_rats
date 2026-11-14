extends "res://tools/survival_save_common.gd"
## Phase A (process 1): one ordinary lap with the normal director (hunt during travel, wait at the unsafe site, return, market),
## then a real save at the safe town stop. The ledger is written next to it for the restart phase (a separate Godot process).
## Fixture/API input: seed, speed, food refill target; no supply, currency, kill or clock injection. Limited, not a survival guarantee.
func _init() -> void: call_deferred("_run")
func _run() -> void:
	if OS.get_environment("FLUID_TEST_HOME") == "": quit(2); return
	await _fresh()
	_setup_fixture()
	_check(main.director.enabled,"normal director enabled")
	var t0: float = main.director.elapsed
	var ok := await _leg("b_forest")
	_check(ok,"outbound leg to the forest with a natural hunt request")
	await _wait(200.0,true)
	_check(not main.game_over,"no game over during the forest stay (natural outcome)")
	for dest in ["c_quarry","d_yard","a_start"]:
		if not ok or main.game_over: break
		ok = await _leg(dest)
	_check(ok and main.world.region == "a_start" and main.world.phase == "stopped","returned to the town and stopped safely")
	_market()
	_check(main.director.elapsed > t0 + 100.0,"the normal director world clock advanced outside the safe town (%.1f s)"%(main.director.elapsed - t0))
	_check(main.total_hunted >= 1 and hunt_meat >= 1,"a natural hunt gave hunt-source meat (hunted %d, meat %d)"%[main.total_hunted,hunt_meat])
	var ledger := _ledger()
	SaveGame.disabled = false
	var saved: bool = SaveGame.write(main,SAVE_PATH,true)
	SaveGame.disabled = true
	_check(saved,"real save written at the town stop (%s)"%SaveGame.last_error)
	var f := FileAccess.open(LEDGER_PATH,FileAccess.WRITE)
	f.store_string(var_to_str(ledger))
	f.close()
	print("LEDGER_A " + JSON.stringify(ledger))
	print("INFO seconds=%.1f meals=%d earned=%d spent=%d" % [seconds,meals,earned,spent])
	main.free()
	print("RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
