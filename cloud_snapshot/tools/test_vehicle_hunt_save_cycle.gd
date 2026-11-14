extends "res://tools/survival_save_common.gd"
## Phase A (process 1): a creature is killed naturally by the vehicle hunt during travel (normal request API, ordinary stepping).
## While the rope recovery is in progress (cargo present, progress between 0 and the full time) the regular save is written.
## Fixture/API: same fixture as the survival tests (seed, speed, refill target), world.request and request_hunt. Nothing is injected;
## the recovery progress is never written by the test and no save restriction is lifted (only the test-mode flag used by all save tests).
const HUNT_SAVE := "user://vehicle-hunt-save-test.json"
const HUNT_LEDGER := "user://vehicle-hunt-save-ledger.json"
func _init() -> void: call_deferred("_run")
func _run() -> void:
	if OS.get_environment("FLUID_TEST_HOME") == "": quit(2); return
	await _fresh()
	_setup_fixture()
	_check(main.world.request("b_forest"),"departure request accepted")
	var requested := false
	for frame in 3000:
		if not requested and main.world.phase == "travel": requested = main.request_hunt("dodo",1)
		_step()
		if not main.vehicle_hunt.cargo.is_empty() and main.vehicle_hunt.cargo_progress > 0.0: break
		if frame % 100 == 0: await process_frame
	var vh = main.vehicle_hunt
	_check(requested and not vh.cargo.is_empty(),"a requested creature was killed naturally and its carcass is on the rope")
	if vh.cargo.is_empty():
		print("RESULT checks=%d failures=%d" % [checks,failures]); quit(1); return
	_check(vh.cargo_progress > 0.0 and vh.cargo_progress < VehicleHunt.RECOVERY_SECONDS,"recovery is in progress (%.1f of %.1f s), not finished"%[vh.cargo_progress,VehicleHunt.RECOVERY_SECONDS])
	_check(witness_kills == 1 and witness_ids == [vh.cargo_source] and main.total_hunted == 1,"exactly one independently witnessed death, and it is the cargo source (%s)"%vh.cargo_source)
	_check(main.world.phase == "travel","the base is still travelling")
	var key: String = str(main.world.key())
	var row: Dictionary = main.world.locations.get(main.world.key(),{}).get(vh.cargo_source,{})
	_check(bool(row.get("spent",false)),"the world ledger marks the killed entity as spent")
	var respawn_at: float = float(row.get("respawn_at",-1.0))
	_check(is_finite(respawn_at) and respawn_at > main.director.elapsed,"the respawn time is finite and in the future (%.1f s > now %.1f s)"%[respawn_at,main.director.elapsed])
	var crows: Array = _carcass_rows()
	_check(_carcass_nodes() == 0 and int(crows[0]) == 0,"the carcass was taken onto the rope: no live carcass node and no unspent carcass row remain (nodes %d, rows unspent %d / spent %d)"%[_carcass_nodes(),int(crows[0]),int(crows[1])])
	var ledger := {"cargo":vh.cargo.duplicate(true),"species":vh.cargo_species,"progress":vh.cargo_progress,"source":vh.cargo_source,"key":key,
		"hunted":main.total_hunted,"butchered":main.storage.total_butchered,"weight":main.storage.current_weight(),
		"meat":_owned(GameData.Item.MEAT),"hide":_owned(GameData.Item.HIDE),"bone":_owned(GameData.Item.BONE),"elapsed":main.director.elapsed,
		"respawn_at":float(row.get("respawn_at",-1.0)),"carcass_rows_spent":int(crows[1]),"region":main.world.region,"phase":main.world.phase}
	SaveGame.disabled = false
	var saved: bool = SaveGame.write(main,HUNT_SAVE,true)
	SaveGame.disabled = true
	_check(saved,"regular save written during the rope recovery (%s)"%SaveGame.last_error)
	var f := FileAccess.open(HUNT_LEDGER,FileAccess.WRITE)
	f.store_string(var_to_str(ledger))
	f.close()
	print("INFO " + JSON.stringify({"species":ledger.species,"progress":ledger.progress,"source":ledger.source,"key":key,"elapsed":ledger.elapsed,"respawn_at":ledger.respawn_at,"cargo":str(ledger.cargo)}))
	main.free()
	print("RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
