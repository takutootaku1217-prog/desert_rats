extends SceneTree
## Equal-time food-balance witness for the initial survival-loop prototype.
## It uses a real first-region Main and normal worker/creature ticks.  The
## comparison starts from the normal eight-food starter stock; it never adds
## food, meat, carcasses, drops, or crafted output.

const STEP := 0.2
const WINDOW_SECONDS := 3600.0
const REHUNT_LIMIT_SECONDS := 600.0
const SEED := 311101
const FOOD_SPECIES := ["dodo", "sand_paca", "mossback"]

var main
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _fresh() -> void:
	_free_main()
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", SEED)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 0.0


func _free_main() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null


func _snapshot() -> Dictionary:
	var hungers: Array[float] = []
	for worker in main.workers:
		hungers.append(float(worker.hunger))
	var min_hunger := 0.0
	var average_hunger := 0.0
	if not hungers.is_empty():
		min_hunger = hungers.min()
		for hunger in hungers:
			average_hunger += hunger
		average_hunger /= float(hungers.size())
	var cover := ProductionPlan.finished(main, GameData.Item.FOOD) + ProductionPlan.future(main, GameData.Item.FOOD)
	return {
		"elapsed": float(main.director.elapsed),
		"workers": main.workers.size(),
		"hunted": int(main.total_hunted),
		"eaten": int(main.total_eaten),
		"food_ready": int(main.food_for_eating()),
		"food_cover": int(cover),
		"meat": int(main.storage.count_of(GameData.Item.MEAT)),
		# This is an end-of-window snapshot, not a time average.
		"end_min_hunger": min_hunger,
		"end_average_hunger": average_hunger,
	}


func _advance_equal_window() -> Dictionary:
	var initial := _snapshot()
	var frames := ceili(WINDOW_SECONDS / STEP)
	for frame in frames:
		# This is the usual per-frame order for the systems under test.  The
		# creature tick is explicit because Main processing is disabled in this
		# deterministic headless fixture.
		main._process(STEP)
		for creature in main.creatures_root.get_children():
			if is_instance_valid(creature) and not creature.is_queued_for_deletion():
				creature._process(STEP)
		for worker in main.workers:
			worker._process(STEP)
		if frame % 120 == 0:
			await process_frame
	var finish := _snapshot()
	finish["food_generated"] = int(finish.eaten) + int(finish.food_cover) - int(initial.food_cover)
	finish["start_cover"] = int(initial.food_cover)
	# Director time intentionally does not advance while the normal first town
	# is safe.  This is the fixed simulation clock used for both equal cases.
	finish["simulated_seconds"] = float(frames) * STEP
	return finish


func _step_world() -> void:
	main._process(STEP)
	for creature in main.creatures_root.get_children():
		if is_instance_valid(creature) and not creature.is_queued_for_deletion():
			creature._process(STEP)
	for worker in main.workers:
		worker._process(STEP)


func _species_respawned(species: String) -> bool:
	for row in main.world.locations.get("region:a_start", {}).values():
		if row.get("type", "") == "creature" and row.get("data", {}).get("species", "") == species:
			return not bool(row.get("spent", false))
	return false


func _species_respawn_at(species: String) -> float:
	for row in main.world.locations.get("region:a_start", {}).values():
		if row.get("type", "") == "creature" and row.get("data", {}).get("species", "") == species:
			return float(row.get("respawn_at", -1.0))
	return -1.0


func _wait_until(predicate: Callable, seconds: float) -> bool:
	for frame in ceili(seconds / STEP):
		_step_world()
		if predicate.call():
			return true
		if frame % 120 == 0:
			await process_frame
	return bool(predicate.call())


func _move_normally(destination: String) -> Dictionary:
	if main.world.region == destination and main.world.phase == "stopped":
		return {"ok": true}
	main.target_speed = 60.0
	var ready := await _wait_until(func(): return main.world.ready_reason().is_empty(), 120.0)
	if not ready:
		return {"ok": false, "reason": "crew or cargo did not become ready for %s" % destination}
	if not main.world.request(destination):
		return {"ok": false, "reason": "normal map request to %s was rejected" % destination}
	var arrived := await _wait_until(func(): return main.world.region == destination and main.world.phase == "stopped", 180.0)
	return {"ok": arrived, "reason": "did not arrive at %s" % destination if not arrived else ""}


func _rehunt_after_respawn(species: String) -> Dictionary:
	var before := _snapshot()
	var hunts_before := int(main.total_hunted)
	var due_at := _species_respawn_at(species)
	if due_at < 0.0:
		return {"ok": false, "respawned": false, "reason": "%s has no respawn deadline" % species}
	# A is a safe town, so its event clock intentionally stops.  Use only the
	# normal A->B->A map route to advance the same game clock that governs
	# wildlife respawn; do not alter elapsed time or ledger state directly.
	var outward: Dictionary = await _move_normally("b_forest")
	if not bool(outward.get("ok", false)):
		return {"ok": false, "respawned": false, "reason": str(outward.get("reason", "could not leave A"))}
	var elapsed := await _wait_until(func(): return main.director.elapsed >= due_at + STEP, 300.0)
	if not elapsed:
		return {"ok": false, "respawned": false, "reason": "respawn clock did not reach the dodo deadline"}
	var homeward: Dictionary = await _move_normally("a_start")
	if not bool(homeward.get("ok", false)):
		return {"ok": false, "respawned": false, "reason": str(homeward.get("reason", "could not return to A"))}
	_step_world()
	var respawned := _species_respawned(species)
	if not respawned:
		return {"ok": false, "respawned": false, "reason": "%s did not restore after its elapsed-time deadline" % species}
	if not main.request_hunt(species, 1):
		return {"ok": false, "respawned": true, "reason": "second %s request was rejected" % species}
	var frames := ceili(REHUNT_LIMIT_SECONDS / STEP)
	for frame in frames:
		_step_world()
		var now := _snapshot()
		var generated := int(now.eaten) - int(before.eaten) + int(now.food_cover) - int(before.food_cover)
		if int(main.total_hunted) == hunts_before + 1 and generated >= 2:
			now["ok"] = true
			now["respawned"] = true
			now["generated_after_respawn"] = generated
			now["simulated_seconds"] = float(frame + 1) * STEP
			return now
		if frame % 120 == 0:
			await process_frame
	var finish := _snapshot()
	finish["ok"] = false
	finish["respawned"] = true
	finish["generated_after_respawn"] = int(finish.eaten) - int(before.eaten) + int(finish.food_cover) - int(before.food_cover)
	finish["simulated_seconds"] = float(frames) * STEP
	return finish


func _run_case(request_food_trip: bool) -> Dictionary:
	await _fresh()
	if request_food_trip:
		# These are the same bounded player-facing entry points the Craft UI calls.
		# The first-region roster contains one of each, totalling ten cooked-food
		# units after normal meat haul and cooking.
		for species in FOOD_SPECIES:
			if not main.request_hunt(species, 1):
				return {"ok": false, "reason": "explicit %s request was rejected" % species}
	var report: Dictionary = await _advance_equal_window()
	report["requested_food_trip"] = request_food_trip
	if request_food_trip:
		report["rehunt"] = await _rehunt_after_respawn("dodo")
	report["ok"] = true
	return report


func _run() -> void:
	var baseline: Dictionary = await _run_case(false)
	var intervention: Dictionary = await _run_case(true)
	print("  baseline=%s" % JSON.stringify(baseline))
	print("  food_trip=%s" % JSON.stringify(intervention))
	_check(bool(baseline.get("ok", false)) and bool(intervention.get("ok", false)), "both cases instantiate the same normal first-region fixture")
	_check(int(baseline.get("workers", 0)) == 3 and int(intervention.get("workers", 0)) == 3, "both cases use the same three workers")
	_check(is_equal_approx(float(baseline.get("simulated_seconds", 0.0)), WINDOW_SECONDS) and is_equal_approx(float(intervention.get("simulated_seconds", 0.0)), WINDOW_SECONDS), "both cases advance the same simulated game time")
	_check(int(baseline.get("hunted", 0)) == 0, "baseline has no implicit hunt")
	_check(int(intervention.get("hunted", 0)) == FOOD_SPECIES.size(), "three explicit first-region requests create three normal hunts")
	_check(int(intervention.get("food_generated", 0)) >= 10, "three species pass through normal haul and cooking into ten food units")
	_check(int(intervention.get("eaten", 0)) > int(baseline.get("eaten", 0)), "intervention completes more meals than the equal-time baseline")
	_check(float(intervention.get("end_average_hunger", 0.0)) > float(baseline.get("end_average_hunger", 0.0)), "intervention improves end-of-window average hunger")
	var rehunt: Dictionary = intervention.get("rehunt", {})
	_check(bool(rehunt.get("respawned", false)), "the original dodo ledger row respawns before a second request")
	_check(bool(rehunt.get("ok", false)), "the respawned dodo accepts a second explicit hunt and cooks normally")
	_check(int(rehunt.get("generated_after_respawn", 0)) >= 2, "the second explicit hunt adds its normal two cooked-food units")
	_free_main()
	SaveGame.disabled = false
	print("== survival food balance: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures > 0 else 0)
