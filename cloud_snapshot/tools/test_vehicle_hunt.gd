extends SceneTree
## Boundary fixtures only: creatures, travel state and capacity are deliberately arranged.
## This is not evidence of the natural survival loop or GUI/Windows play.
var main
var fails := 0
var disk_evidence_paths: Array[String] = []
func _origin() -> Vector2:
	return Vector2(GameData.RAMP_FOOT.x, TravelLanePresentation.travel_ground_y())
func _init():
	call_deferred("_run")
func _check(ok: bool, label: String):
	print("%s %s" % ["ok" if ok else "FAIL", label])
	if not ok: fails += 1
func _fresh():
	if is_instance_valid(main): main.free()
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	main.director.enabled = false
	main.refill_settings = {}
	for w in main.workers:
		w.stop_work()
		for job in GameData.job_list(): w.priorities[job] = 0
	for n in main.creatures_root.get_children(): n.free()
	for n in main.resources_root.get_children(): n.free()
	main.world.request("b_forest")
	main.world.start_leg()
	main.scroll_speed = 60.0
	main.base.vehicle_loadout["prototype_unlimited"] = false
	main.storage.enforce = true
func _creature(distance: float = 100.0):
	var c = Creature.new()
	c.setup(main, "dodo")
	c.position = _origin() + Vector2(distance, 0)
	main.creatures_root.add_child(c)
	return c
func _tick(seconds: float):
	for i in ceili(seconds / 0.1): main.vehicle_hunt.tick(0.1)
func _kill_to_cargo(c) -> bool:
	main.request_hunt("dodo", 1)
	for i in 100:
		main.vehicle_hunt.tick(0.1)
		if not main.vehicle_hunt.cargo.is_empty(): return true
	return false
func _disk_roundtrip(label: String) -> Dictionary:
	var path := "user://vehicle-hunt-boundary-%s-%d.json" % [label, Time.get_ticks_usec()]
	disk_evidence_paths.append(path)
	SaveGame.disabled = false
	var wrote: bool = SaveGame.write(main, path, false)
	SaveGame.disabled = true
	_check(wrote, "Real isolated SaveGame.write: " + label)
	var data := SaveGame.read(path)
	_check(not data.is_empty() and SaveGame.validate(data, main), "Real isolated SaveGame.read + validate: " + label)
	print("SAVE_EVIDENCE ", ProjectSettings.globalize_path(path))
	return data

func _assert_disk_evidence_removed() -> void:
	for path in disk_evidence_paths:
		_check(not FileAccess.file_exists(path), "Isolated SaveGame evidence is removed before test exit")

func _clear_disk_evidence() -> void:
	for path in disk_evidence_paths:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Isolated SaveGame evidence cleanup succeeds")
func _run():
	await _fresh()
	_check(main.get("vehicle_hunt") != null, "VehicleHunt controller installed")
	if main.get("vehicle_hunt") == null:
		main.free()
		quit(1)
		return
	var c = _creature()
	var hp: float = c.hp
	_tick(3)
	_check(c.hp == hp and main.total_hunted == 0, "No explicit order: neutral creature untouched")
	main.request_hunt("dodo", 1)
	_tick(0.8)
	_check(c.hp < hp and hp - c.hp <= 8.0, "Explicit moving shot applies at most 8 HP per 0.8 sec")
	var shot_hp: float = c.hp
	var shot_cd: float = main.vehicle_hunt.cooldown
	var shooting_save := _disk_roundtrip("shooting")
	_check(SaveGame.apply(main, shooting_save), "Restore real file during shooting")
	c = main.creatures_root.get_child(0)
	_check(c.hp == shot_hp and is_equal_approx(main.vehicle_hunt.cooldown, shot_cd), "Shooting save preserves damaged prey HP and shot cooldown")
	main.cancel_hunt("dodo")
	hp = c.hp
	_tick(2)
	_check(c.hp == hp, "Cancellation immediately prevents further shots")
	await _fresh()
	c = _creature(461)
	main.request_hunt("dodo", 1)
	hp = c.hp
	_tick(3)
	_check(c.hp == hp, "461px is outside 460px shot range")
	c.position = _origin() + Vector2(460, 0)
	_tick(0.8)
	_check(c.hp < hp, "460px inclusive range boundary")
	await _fresh()
	c = _creature()
	main.request_hunt("dodo", 1)
	main.operations.stance = "recall"
	hp = c.hp
	_tick(2)
	_check(c.hp == hp, "Group recall prevents vehicle shooting")
	main.operations.stance = "normal"
	main.base.hp = 0
	_tick(2)
	_check(c.hp == hp, "Destroyed vehicle does not shoot")
	await _fresh()
	c = _creature()
	main.request_hunt("dodo", 1)
	main.world.phase = "stopped"
	hp = c.hp
	_tick(2)
	_check(c.hp == hp, "Stopped screen does not run moving vehicle weapon")
	main.world.phase = "travel"
	main.scroll_speed = 0
	_tick(2)
	_check(c.hp == hp, "Zero scrolling speed does not run moving weapon")
	await _fresh()
	c = _creature()
	var mass_before: int = main.storage.current_weight()
	var meat_before: int = main.storage.count_of(GameData.Item.MEAT)
	_check(_kill_to_cargo(c), "Death produces one recoverable cargo")
	_check(c.dead and c.hp <= 0 and main.total_hunted == 1, "Death/HP/hunt ledger agree")
	_check(main.vehicle_hunt.cargo_species == "dodo" and main.vehicle_hunt.cargo.get(GameData.Item.MEAT, 0) == GameData.CREATURES.dodo.drops[GameData.Item.MEAT], "Cargo derives from killed species drops")
	_check(main.storage.count_of(GameData.Item.MEAT) == meat_before, "Kill does not instantly credit storage")
	_check(main.storage.current_weight() == mass_before + main.storage.set_weight(main.vehicle_hunt.cargo), "Owned recovery cargo counts toward total mass immediately")
	var c2 = _creature(110)
	main.request_hunt("dodo", 1)
	var second_hp: float = c2.hp
	_tick(0.5)
	_check(c2.hp == second_hp and main.total_hunted == 1, "One-carcass cargo blocks second shot")
	main.cancel_hunt("dodo")
	_tick(2.0)
	_check(main.storage.count_of(GameData.Item.MEAT) == meat_before, "Recovery takes at least 3 seconds, not immediate on kill")
	var carried = main.vehicle_hunt.cargo.duplicate(true)
	var progress: float = main.vehicle_hunt.cargo_progress
	var snapshot = SaveGame.capture(main)
	_check(SaveGame.validate(snapshot, main), "Mid-recovery snapshot validates")
	var corrupt = snapshot.duplicate(true)
	corrupt.vehicle_hunt.cargo[GameData.Item.MEAT] += 1
	_check(not SaveGame.validate(corrupt, main), "Inflated saved carcass payload rejected")
	_check(not SaveGame.apply(main, corrupt) and main.vehicle_hunt.cargo == carried, "Rejected corrupt save leaves current cargo untouched")
	var bad_progress = snapshot.duplicate(true)
	bad_progress.vehicle_hunt.progress = 3.1
	_check(not SaveGame.validate(bad_progress, main) and not SaveGame.apply(main, bad_progress) and main.vehicle_hunt.cargo == carried and is_equal_approx(main.vehicle_hunt.cargo_progress, progress), "Invalid recovery progress rejected without state mutation")
	_check(SaveGame.saved_weight(snapshot) == main.storage.current_weight(), "Saved weight includes pending vehicle cargo exactly once")
	var disk_snapshot := _disk_roundtrip("recovering")
	_check(SaveGame.saved_weight(disk_snapshot) == main.storage.current_weight(), "On-disk payload retains exact cargo-inclusive weight")
	_check(SaveGame.apply(main, disk_snapshot), "Mid-recovery actual file restores")
	_check(main.vehicle_hunt.cargo == carried and is_equal_approx(main.vehicle_hunt.cargo_progress, progress), "Save/load preserves pending cargo and recovery progress")
	_tick(5)
	_check(main.vehicle_hunt.cargo.is_empty() and main.storage.count_of(GameData.Item.MEAT) == meat_before + carried.get(GameData.Item.MEAT, 0), "Recovery deposits actual meat once after delay")
	_check(main.storage.current_weight() == mass_before + main.storage.set_weight(carried), "Delivery transfers owned mass without double counting")
	var stored: int = main.storage.count_of(GameData.Item.MEAT)
	_tick(10)
	_check(main.storage.count_of(GameData.Item.MEAT) == stored and main.total_hunted == 1, "No second delivery or unrequested kill after completion")
	await _fresh()
	c = _creature()
	main.storage.capacity_bonus = main.storage.current_weight() - main.storage.max_weight()
	main.request_hunt("dodo", 1)
	hp = c.hp
	_tick(5)
	_check(c.hp == hp and main.vehicle_hunt.cargo.is_empty(), "Full storage prevents new lethal acquisition")
	await _fresh()
	c = _creature()
	_check(_kill_to_cargo(c), "Acquire cargo for capacity-change boundary fixture")
	var held = main.vehicle_hunt.cargo.duplicate(true)
	var stock_before: int = main.storage.count_of(GameData.Item.MEAT)
	main.storage.capacity_bonus = 1 - main.storage.max_weight()
	_tick(5)
	_check(main.vehicle_hunt.cargo == held and main.storage.count_of(GameData.Item.MEAT) == stock_before, "Capacity shrinks mid-recovery: retain cargo without loss or overflow")
	main.storage.capacity_bonus = 1000
	_tick(5)
	_check(main.vehicle_hunt.cargo.is_empty() and main.storage.count_of(GameData.Item.MEAT) == stock_before + held.get(GameData.Item.MEAT, 0), "Restored capacity deposits retained cargo once")
	await _fresh()
	c = _creature()
	main.request_hunt("dodo", 1)
	for w in main.workers:
		w.priorities[GameData.Job.HUNT] = 3
		w.priorities[GameData.Job.GATHER] = 3
		w.ai.tick(0.5)
		_check(w.ai.state not in [CharacterAI.State.HUNT_MOVE, CharacterAI.State.HUNT_ATTACK, CharacterAI.State.MOVE_TO_RESOURCE, CharacterAI.State.GATHER], "Travel does not send worker outside to hunt/gather")
	_check(main.vehicle_hunt.status() is Dictionary, "Controller supplies read-only UI status")
	_clear_disk_evidence()
	_assert_disk_evidence_removed()
	main.free()
	print("VEHICLE HUNT boundary failures=", fails)
	quit(1 if fails else 0)
