extends "res://tools/survival_save_common.gd"
## Phase B (a NEW Godot process): read/apply the save written during the rope recovery. Check cargo, source id, progress,
## weight and hunt count, let the recovery finish naturally (stored and butchered exactly once, witnessed through the
## warehouse item_added signal with the hunt source), then travel on, come back over the same road without any hunt request
## and check that the entity, a carcass or the cargo did not come back early and nothing was gained twice.
## A natural respawn after the documented delay is allowed and reported separately.
const HUNT_SAVE := "user://vehicle-hunt-save-test.json"
const HUNT_LEDGER := "user://vehicle-hunt-save-ledger.json"
var hunt_events: Array = []
func _init() -> void: call_deferred("_run")
func _hunt_added(item: int, amount: int, source: String) -> void:
	if source == Inventory.SOURCE_HUNT: hunt_events.append([item,amount])
func _alive_source(source: String) -> bool:
	for c in main.creatures_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion() and str(c.get("world_id")) == source and not c.dead: return true
	return false
func _run() -> void:
	if OS.get_environment("FLUID_TEST_HOME") == "": quit(2); return
	var saved = str_to_var(FileAccess.get_file_as_string(HUNT_LEDGER))
	_check(saved is Dictionary,"ledger of process 1 is readable")
	if not saved is Dictionary: quit(1); return
	await _fresh()
	_setup_fixture()
	main.storage.inventory.item_added.connect(_hunt_added)
	var before := FileAccess.get_sha256(HUNT_SAVE)
	_check(SaveGame.apply(main,SaveGame.read(HUNT_SAVE)),"new process reads and applies the save")
	_check(FileAccess.get_sha256(HUNT_SAVE) == before,"loading does not rewrite the save file")
	var vh = main.vehicle_hunt
	_check(vh.cargo == saved.cargo and vh.cargo_species == saved.species and vh.cargo_source == saved.source,"restored: same cargo, species and source entity id (%s)"%vh.cargo_source)
	_check(is_equal_approx(vh.cargo_progress,float(saved.progress)) and vh.cargo_progress < VehicleHunt.RECOVERY_SECONDS,"restored: same recovery progress (%.1f s), still unfinished"%vh.cargo_progress)
	_check(main.storage.current_weight() == int(saved.weight) and main.total_hunted == int(saved.hunted) and main.storage.total_butchered == int(saved.butchered),"restored: same weight (cargo counted once), hunt count and butcher count")
	_check(_owned(GameData.Item.MEAT) == int(saved.meat) and hunt_events.is_empty(),"restored: nothing stored by loading")
	var key = main.world.key()
	_check(str(key) == str(saved.key) and bool(main.world.locations.get(key,{}).get(saved.source,{}).get("spent",false)),"restored: the killed entity is still spent on the same road")
	_check(not _alive_source(saved.source),"restored: the killed entity is not alive")
	# natural completion of the recovery
	var weight_before: int = main.storage.current_weight()
	var meat_before: int = _owned(GameData.Item.MEAT) + int(main.processor.committed_inputs().get(GameData.Item.MEAT,0))
	var steps := 0
	while not vh.cargo.is_empty() and steps < 100:
		_step()
		steps += 1
	_check(vh.cargo.is_empty() and steps > 0,"the recovery finishes naturally after %d ordinary steps"%steps)
	var expected: Array = []
	for item in saved.cargo: expected.append([item,int(saved.cargo[item])])
	var got := hunt_events.duplicate()
	got.sort(); expected.sort()
	_check(got == expected and not expected.is_empty(),"the cargo was stored exactly once (witnessed hunt-source additions %s)"%str(hunt_events))
	_check(main.storage.total_butchered == int(saved.butchered) + 1 and main.total_hunted == int(saved.hunted),"butchered once; the hunt count did not grow")
	var meat_now: int = _owned(GameData.Item.MEAT) + int(main.processor.committed_inputs().get(GameData.Item.MEAT,0))
	_check(meat_now == meat_before + int(saved.cargo.get(GameData.Item.MEAT,0)) and main.storage.current_weight() == weight_before,"owned meat (incl. meat committed to cooking) grew by exactly the cargo (%d -> %d) and the total weight is unchanged (%d): a location change, not new mass"%[meat_before,meat_now,weight_before])
	# go on to the forest, then come back over the same road without any hunt request
	var arrived := false
	for frame in 3000:
		_step()
		if main.world.phase == "stopped" and main.world.region == "b_forest": arrived = true; break
		if frame % 100 == 0: await process_frame
	_check(arrived,"the base arrives at the forest by ordinary travel")
	_check(main.world.request("a_start"),"the return request over the same road is accepted")
	var revisited := false
	var early_revival := false
	var back := false
	for frame in 3000:
		_step()
		if str(main.world.key()) == str(saved.key): revisited = true
		if _alive_source(saved.source) and main.director.elapsed < float(saved.respawn_at): early_revival = true
		if main.world.phase == "stopped" and main.world.region == "a_start": back = true; break
		if frame % 100 == 0: await process_frame
	_check(back and revisited,"the base came back over the road of the kill")
	_check(not early_revival,"the killed entity did not come back before its natural respawn time (%.0f s; now %.0f s)"%[float(saved.respawn_at),main.director.elapsed])
	var row: Dictionary = main.world.locations.get(key,{}).get(saved.source,{})
	var natural: bool = main.director.elapsed >= float(saved.respawn_at) and float(saved.respawn_at) >= 0.0
	_check(bool(row.get("spent",false)) or natural,"entity state is spent, or alive again only through the documented natural respawn (spent=%s, natural respawn due=%s)"%[row.get("spent",false),natural])
	_check(vh.cargo.is_empty() and main.total_hunted == int(saved.hunted) and witness_kills == 0,"no cargo came back and no new kill without a request (witnessed deaths after restart: %d)"%witness_kills)
	got = hunt_events.duplicate(); got.sort()
	_check(got == expected,"still exactly one stored cargo after the revisit (no second gain)")
	# natural regeneration: keep travelling without hunt requests until the documented respawn time has passed
	var legs := 0
	var seen_alive_after := false
	while main.director.elapsed < float(saved.respawn_at) + 5.0 and legs < 14 and not main.game_over:
		var dest := "b_forest" if main.world.region == "a_start" else "a_start"
		if not main.world.request(dest): break
		for frame in 3000:
			_step()
			if _alive_source(saved.source):
				if main.director.elapsed < float(saved.respawn_at): early_revival = true
				else: seen_alive_after = true
			if main.world.phase == "stopped" and main.world.region == dest: break
			if frame % 100 == 0: await process_frame
		legs += 1
	if main.director.elapsed >= float(saved.respawn_at) and not seen_alive_after:
		# one more pass over the kill road so the regenerated entity can be observed
		for extra in 2:
			var dest2 := "b_forest" if main.world.region == "a_start" else "a_start"
			if not main.world.request(dest2): break
			for frame in 3000:
				_step()
				if _alive_source(saved.source): seen_alive_after = true
				if main.world.phase == "stopped" and main.world.region == dest2: break
				if frame % 100 == 0: await process_frame
	_check(main.director.elapsed >= float(saved.respawn_at),"ordinary travel reached the natural respawn time (%.0f s >= %.0f s) after %d more legs"%[main.director.elapsed,float(saved.respawn_at),legs])
	_check(not early_revival and seen_alive_after,"the entity came back only after its natural respawn time (regeneration), never before")
	got = hunt_events.duplicate(); got.sort()
	_check(got == expected and main.total_hunted == int(saved.hunted) and vh.cargo.is_empty() and witness_kills == 0,"the regenerated entity gave nothing without a hunt request: still one stored cargo, same hunt count, no cargo")
	print("INFO " + JSON.stringify({"seconds":seconds,"elapsed":main.director.elapsed,"respawn_at":saved.respawn_at,"natural_respawn_due":natural,"spent":row.get("spent",false),"events":str(hunt_events)}))
	main.free()
	print("RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
