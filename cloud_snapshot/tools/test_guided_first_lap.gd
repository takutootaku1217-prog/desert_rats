extends SceneTree
## Witness: one lap from a normal new game, choosing every action from the
## in-game guide's own "next step" (FirstLoopGuide.recommendation).
## Real Main, default worker priorities, normal director, fixed seed.
## No item, currency, tool, clock or state injection.  Input is the product API
## that each screen calls, not OS mouse/touch; the world is stepped directly.

const FirstLoopGuide = preload("res://ui/first_loop_guide.gd")
const STEP := 0.2
const MAX_SECONDS := 6000.0

var main
var failures := 0
var seconds := 0.0
var trail: Array = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _step() -> void:
	main._process(STEP)
	for creature in main.creatures_root.get_children():
		if is_instance_valid(creature) and not creature.is_queued_for_deletion():
			creature._process(STEP)
	for worker in main.workers:
		worker._process(STEP)
	seconds += STEP


func _guide_id() -> String:
	return str(FirstLoopGuide.snapshot(main).next_step.get("id", ""))


func _status() -> String:
	return "t=%d %s/%s wood=%d stone=%d ore=%d food=%d fuel=%.0f cr=%d orders=%s builds=%s" % [
		int(seconds), main.world.region, main.world.phase,
		main.storage.count_of(GameData.Item.WOOD), main.storage.count_of(GameData.Item.STONE),
		main.storage.count_of(GameData.Item.IRON_ORE), main.storage.count_of(GameData.Item.FOOD),
		main.base.fuel, int(main.town.credits), str(main.production_orders), str(main.build_queue)]


func _note(id: String) -> void:
	if trail.is_empty() or trail[-1] != id:
		trail.append(id)
		print("GUIDE %s | %s" % [id, _status()])


func _wait(predicate: Callable, limit: float) -> bool:
	var frames := ceili(limit / STEP)
	for frame in frames:
		if predicate.call(): return true
		if main.game_over or seconds >= MAX_SECONDS: return false
		_step()
		if frame % 120 == 0: await process_frame
	return bool(predicate.call())


func _travel(dest: String) -> bool:
	# Leave only when the game itself says departure is ready.
	if not await _wait(func(): return main.world.ready_reason().is_empty(), 900.0):
		print("  departure never ready: %s" % main.world.ready_reason())
		return false
	if not main.world.request(dest):
		print("  request(%s) refused: %s" % [dest, main.world.departure_error])
		return false
	return await _wait(func(): return main.world.phase == "stopped" and main.world.region == dest, 900.0)


func _mine_lap(want_item := -1, want_n := 1, limit := 400.0) -> bool:
	var gate = main.mine_arrival_gate
	if not await _wait(func(): return gate.visible_state() == "arrival_choice", 120.0):
		print("  no arrival choice: %s" % gate.visible_state()); return false
	# false with "entry_wait" is the product's own recall-then-enter path.
	if not gate.enter_mine() and gate.visible_state() != "entry_wait":
		print("  enter_mine refused: %s" % gate.visible_state()); return false
	for unused in 3000:
		if gate.field != null or gate.visible_state() != "entry_wait": break
		_step()
		await process_frame
	if gate.field == null:
		print("  mine entry never completed: %s / %s" % [gate.visible_state(), main.world.ready_reason()]); return false
	var adapter = gate.field
	adapter.set_process(false)
	for unused in 5: await process_frame
	var session = adapter.session
	print("MINE entry free=%d" % session.field_capacity_limit_weight)
	var advance := func(predicate: Callable, limit: float) -> bool:
		for unused in ceili(limit / STEP):
			if predicate.call(): return true
			session.tick(STEP); session.apply_projection_to_workers(main); seconds += STEP
		return bool(predicate.call())
	var enough := func() -> bool:
		if want_item < 0: return not session.depot_stock.is_empty()
		return int(session.depot_stock.get(want_item, 0)) >= want_n
	if not advance.call(enough, limit):
		print("  mine did not deliver the wanted cargo: depot=%s summary=%s" % [str(session.depot_stock), str(session.state_summary())]); return false
	var cargo: Dictionary = session.depot_stock.duplicate(true)
	var before: Dictionary = main.storage.inventory.counts.duplicate(true)
	session.request_recall()
	if not advance.call(func(): return session.phase == "ready_to_exit", 300.0):
		print("  crew never returned: %s" % str(session.state_summary())); return false
	adapter._commit_and_exit()
	if not session.committed and adapter.return_confirmation != null and adapter.return_confirmation.visible:
		print("  return asked for capacity consent (cargo would be left outside)"); return false
	for unused in 5: await process_frame
	_check(session.committed and gate.field == null, "mine return is committed and the side view is restored")
	var exact := true
	for item in cargo:
		exact = exact and main.storage.count_of(item) == int(before.get(item, 0)) + int(cargo[item])
	_check(exact and not cargo.is_empty(), "mine cargo reached the warehouse exactly once (%s)" % str(cargo))
	return session.committed


## Second lap: choices the guide text describes but does not sequence
## (iron ore -> smelt -> storage box -> install -> depart).
## Still no injection: every input was gathered or crafted in this run.
func _second_lap() -> void:
	var guide: Dictionary = FirstLoopGuide.snapshot(main)
	var free_before: int = guide.cargo.free
	var reserve := ceili(main.storage.max_weight() * CargoDB.AUTO_GATHER_RESERVE_RATIO)
	var bag_weight := 0
	for worker in main.workers:
		bag_weight = maxi(bag_weight, worker.carry_limit() * CargoDB.size_of(GameData.Item.STONE))
	print("LAP2 cargo before departure: free=%d of %d" % [free_before, main.storage.max_weight()])
	_check(free_before >= reserve - bag_weight, "automatic gathering keeps room for the second trip")
	_check(not bool(guide.cargo.near_full) and not str(guide.next_step.body).contains("積載の残りが少ない"), "no near-full warning before the second trip")
	var ok := await _travel("b_forest") and await _travel("c_quarry")
	_check(ok, "second trip A -> B -> C (%s)" % _status())
	if not ok: return
	_check(await _mine_lap(GameData.Item.IRON_ORE, 3, 900.0), "mine delivers 3 iron ore with the stone pickaxe (%s)" % _status())
	ok = await _travel("b_forest") and await _travel("a_start")
	_check(ok, "second return C -> B -> A (%s)" % _status())
	if not ok: return
	var iron := GameData.Item.IRON
	var ore_before: int = main.storage.count_of(GameData.Item.IRON_ORE)
	_check(ore_before >= 3, "iron ore is in the warehouse after the return (%d)" % ore_before)
	var racks_before: int = main.base.facility_count("cargo_rack")
	var cap_before: int = main.storage.max_weight()
	_check(main.request_order("smelt", 3) == 3, "smelting order accepted (%s)" % _status())
	_check(await _wait(func(): return main.storage.count_of(iron) >= 3, 900.0), "three iron are smelted and stored (%s)" % _status())
	_check(main.request_build("cargo_rack"), "storage box installation accepted: %s" % main.build_blocked_reason("cargo_rack"))
	_check(await _wait(func(): return main.base.facility_count("cargo_rack") == racks_before + 1, 900.0), "storage box is crafted and installed (%s)" % _status())
	_check(main.storage.max_weight() == cap_before + 60, "base upgrade took effect: capacity %d -> %d" % [cap_before, main.storage.max_weight()])
	_check(await _travel("b_forest"), "next expedition departs and arrives after the upgrade (%s)" % _status())
	_check(not main.game_over, "still alive after two laps")
	print("LAP2 end %s eaten=%d hunted=%d" % [_status(), main.total_eaten, main.total_hunted])


func _run() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	_check(main.director.enabled and main.world.region == "a_start" and main.world.phase == "stopped", "normal new game: director on, stopped at A")
	var start_food: int = main.storage.count_of(GameData.Item.FOOD)
	var done := false
	var stuck := ""
	var same_id := ""
	var same_since := 0.0
	while not done and stuck.is_empty():
		var id := _guide_id()
		_note(id)
		if id != same_id: same_id = id; same_since = seconds
		if main.game_over: stuck = "game over"; break
		if seconds >= MAX_SECONDS or seconds - same_since > 1800.0: stuck = "no progress at guide step '%s'" % id; break
		match id:
			"workbench":
				if not main.request_build("workbench"):
					stuck = "workbench request refused: " + main.build_blocked_reason("workbench")
			"workbench_wait":
				await _wait(func(): return main.has_facility("workbench"), 60.0)
			"mining_tool", "ore_tool":
				var ore_tool := id == "ore_tool"
				var pick := GameData.Item.HAMMER if ore_tool else GameData.Item.WOOD_PICK
				var recipe := "tool_hammer" if ore_tool else "tool_wood_pick"
				if main.storage.count_of(pick) > 0:
					var holder = null
					for w in main.workers:
						if main.tool_equip_reason(w, pick).is_empty(): holder = w; break
					if holder == null: await _wait(func(): return false, 10.0)
					elif not main.equip_tool(holder, pick): stuck = "equip refused"
				else:
					var pending := false
					for q in main.production_orders: pending = pending or q.id == recipe
					for q in main.craft_queue: pending = pending or q.id == recipe
					pending = pending or main.packed_in_transit(pick) > 0
					if not pending and main.request_order(recipe, 1) <= 0:
						stuck = "%s order refused" % recipe
					else:
						await _wait(func(): return main.storage.count_of(pick) > 0, 60.0)
			"visit_c":
				var next := "b_forest" if main.world.region == "a_start" else "c_quarry"
				if not await _travel(next): stuck = "travel to %s failed (%s)" % [next, _status()]
			"enter_c":
				var ore_before: int = main.storage.count_of(GameData.Item.IRON_ORE)
				if not await _mine_lap(GameData.Item.IRON_ORE): stuck = "mine lap failed"
				var ore_delivered: int = main.storage.count_of(GameData.Item.IRON_ORE) - ore_before
				print("LAP1 first trip iron ore delivered=%d" % ore_delivered)
				_check(ore_delivered > 0, "first mine commit delivered iron ore")
			"return_a":
				var back := "b_forest" if main.world.region == "c_quarry" else "a_start"
				if not await _travel(back): stuck = "travel to %s failed (%s)" % [back, _status()]
				elif main.world.region == "a_start":
					if not await _wait(func(): return main.town.entry_reason().is_empty(), 600.0):
						stuck = "town never usable: " + main.town.entry_reason()
					else:
						main.town_ui.request_open()
						_check(main.town_ui.is_open(), "town opens after the return to A")
						main.town_ui.close()
						await _wait(func(): return _guide_id() != "return_a", 30.0)
			"food":
				stuck = "food ran out during the first lap"
			_:
				done = true
	_note(_guide_id())
	_check(trail.has("ore_tool") and trail.has("visit_c") and trail.find("ore_tool") < trail.find("visit_c"), "ore tool preparation precedes travel to C")
	_check(stuck.is_empty(), "guide-following lap is never stuck (%s)" % (stuck if not stuck.is_empty() else "ok"))
	var completed: Dictionary = main.world.guide_progress.get("completed", {})
	_check(bool(completed.get("quarry_returned", false)) and bool(completed.get("returned_a", false)), "the game recorded the quarry return and the return to A (%s)" % str(completed))
	_check(main.has_facility("workbench"), "workbench was built from gathered wood")
	var equipped := 0
	for w in main.workers:
		if int(w.tools.get("mine", -1)) >= 0: equipped += 1
	_check(equipped > 0, "a crafted mining tool is equipped")
	_check(not main.game_over and main.world.region == "a_start" and main.world.phase == "stopped", "first lap ends alive and stopped at A")
	_check(done and _guide_id() in ["town_upgrade", "route_materials", "route_open", "route_travel", "boss_prepare", "boss_enter"], "guide moves on to upgrade / regional goals (%s)" % _guide_id())
	print("LAP1 end %s" % _status())
	if failures == 0:
		await _second_lap()
	print("LAP trail=%s" % str(trail))
	print("LAP food_start=%d eaten=%d hunted=%d" % [start_food, main.total_eaten, main.total_hunted])
	print("WITNESS_SCOPE guide-chosen product API calls, directly stepped world, one seed; not OS input, not a balance guarantee")
	if main.town_ui != null: main.town_ui.close()
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	SaveGame.disabled = false
	quit(1 if failures > 0 else 0)
