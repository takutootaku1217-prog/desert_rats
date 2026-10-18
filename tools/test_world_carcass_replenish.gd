extends SceneTree

## Reward renewal must revive only the fixed regional creature.  A real hunt
## creates a dynamic carcass ResourceNode, then the normal gather/store path
## consumes it. Two delivery-reward cycles prove that neither historical
## carcass is materialized again or counted as another drop source.
const STEP := 0.2
var fails := 0
var main

func check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func tick(delta: float = STEP) -> void:
	main._process(delta)
	for node in main.resources_root.get_children():
		if not node.is_queued_for_deletion(): node._process(delta)
	for node in main.creatures_root.get_children():
		if not node.is_queued_for_deletion(): node._process(delta)
	for node in main.enemies_root.get_children():
		if not node.is_queued_for_deletion(): node._process(delta)
	for worker in main.workers:
		if not worker.is_queued_for_deletion(): worker._process(delta)
	await process_frame

func wait_for(done: Callable, seconds: float, step: float = STEP) -> bool:
	for unused in ceili(seconds / step):
		if done.call(): return true
		await tick(step)
	return done.call()

func recall_ready() -> bool:
	main.operations.set_stance("recall")
	var ok := await wait_for(func(): return main.operations.returned_count() == main.workers.size(), 180.0, 1.0)
	main.operations.set_stance("normal")
	return ok

func travel(to: String) -> bool:
	# Travel uses the normal scroll loop; hunting itself freezes scrolling below
	# so the nearby prey cannot be culled by the viewport while being verified.
	main.target_speed = 200.0
	var next_stance: String = main.operations.stance
	main.operations.set_stance("recall")
	if not main.world.request(to):
		if not await recall_ready(): return false
		if not main.world.request(to): return false
	var arrived := await wait_for(func(): return main.world.region == to and main.world.phase == "stopped", 240.0, 1.0)
	main.operations.set_stance(next_stance)
	return arrived

func city_ready() -> bool:
	return await wait_for(func(): return main.town.entry_reason() == "", 180.0, 1.0)

func action(name: String, item := -1, n := 1) -> bool:
	return main.town.execute(main.town.quote(name, item, n))

func south_ledger() -> Dictionary:
	return main.world.locations.get("region:south_oasis", {})

func ledger_row(id: String) -> Dictionary:
	return south_ledger().get(id, {})

func live_creature(id: String):
	for creature in main.creatures_root.get_children():
		if not creature.is_queued_for_deletion() and creature.world_id == id:
			return creature
	return null

func active_carcasses() -> Array:
	var rows: Array = []
	for node in main.resources_root.get_children():
		if not node.is_queued_for_deletion() and node is ResourceNode and node.item == GameData.Item.CARCASS:
			rows.append(node)
	return rows

func recorded_carcasses() -> Array:
	var rows: Array = []
	for id in south_ledger():
		var row: Dictionary = ledger_row(id)
		if row.type == "resource" and row.data.item == GameData.Item.CARCASS:
			rows.append({"id": id, "row": row})
	return rows

func unique_living_ids() -> bool:
	var ids := {}
	for node in main.creatures_root.get_children() + main.enemies_root.get_children():
		if node.is_queued_for_deletion() or node.dead: continue
		if ids.has(node.world_id): return false
		ids[node.world_id] = true
	return true

func drop_counts(species: String) -> Dictionary:
	var result := {}
	for item in GameData.CREATURES[species].drops:
		result[item] = main.storage.count_of(item)
	return result

func expected_drops(baseline: Dictionary, species: String, hunts: int) -> Dictionary:
	var result := baseline.duplicate(true)
	for item in GameData.CREATURES[species].drops:
		result[item] = int(result.get(item, 0)) + int(GameData.CREATURES[species].drops[item]) * hunts
	return result

func configure_single_hunter() -> void:
	for worker in main.workers:
		worker.ai._release_task()
		worker.ai._set_state(CharacterAI.State.SEARCH)
		for job in worker.priorities:
			worker.priorities[job] = 0
	for species in main.hunt_policy:
		main.hunt_policy[species] = false
	main.hunt_policy["hare"] = true
	main.workers[0].priorities[GameData.Job.HUNT] = 5
	for setting in main.refill_settings.values():
		setting.enabled = false

func hunt_and_store(expected_hunts: int) -> Dictionary:
	main.world._spawn_visible()
	var historic_ids: Array = []
	for entry in recorded_carcasses():
		historic_ids.append(entry.id)
	var candidates = main.creatures_root.get_children().filter(func(node): return not node.is_queued_for_deletion() and not node.dead and node.species == "hare")
	if candidates.is_empty():
		check(false, "a live huntable fixed creature exists in cycle %d" % expected_hunts)
		return {}
	var creature = candidates[0]
	var creature_id: String = creature.world_id
	var species: String = creature.species
	# This remains a real HUNT_ATTACK kill and normal carcass pickup.  Keeping
	# the fixture prey one hit from death makes that chain deterministic rather
	# than letting a default-speed hare flee out of the finite viewport.
	creature.hp = minf(creature.hp, 1.0)
	# Start the regular hunting state machine within attack range. This avoids a
	# map-distance race with a fleeing target while still exercising HUNT_MOVE /
	# HUNT_ATTACK, Main.on_creature_killed, and the normal carcass gather/store
	# transition; no damage, carcass, or drop is injected by the test.
	var hunter = main.workers[0]
	main.target_speed = 0.0
	# Stand on the creature's fleeing side, keeping its first flee step within
	# reach instead of opening an uncatchable gap.
	hunter.position = creature.position + Vector2(20.0, 0.0)
	hunter.floor_i = 0
	hunter._climb_dest = null
	check(hunter.ai._try_start(GameData.Job.HUNT), "normal hunt state machine starts in cycle %d" % expected_hunts)
	var butchered_before: int = main.storage.total_butchered
	var hunted_before: int = main.total_hunted
	var killed := await wait_for(func(): return main.total_hunted == hunted_before + 1, 180.0)
	check(killed, "normal hunter kills the fixed creature in cycle %d" % expected_hunts)
	var created := main.last_carcass != null and is_instance_valid(main.last_carcass)
	check(created, "hunt creates a dynamic carcass through Main.on_creature_killed")
	var stored := await wait_for(func(): return main.storage.total_butchered == butchered_before + 1, 180.0) if created else false
	check(stored, "normal gather/store path picks up the cycle %d carcass" % expected_hunts)
	# The dynamic node receives its world id when the normal gather path calls
	# WorldTrip.consume.  Discover that newly persisted record after storage;
	# inspecting last_carcass immediately would still see an unassigned id.
	var new_carcasses: Array = []
	for entry in recorded_carcasses():
		if not historic_ids.has(entry.id):
			new_carcasses.append(entry)
	check(new_carcasses.size() == 1, "normal pickup persists exactly one new dynamic carcass ledger record")
	var carcass_id: String = str(new_carcasses[0].id) if new_carcasses.size() == 1 else ""
	var carcass_row := ledger_row(carcass_id)
	check(not carcass_row.is_empty() and carcass_row.type == "resource" and carcass_row.spent, "picked carcass is a spent dynamic resource ledger record")
	return {"creature_id": creature_id, "species": species, "carcass_id": carcass_id}

func claim_delivery_reward(cycle: int) -> bool:
	return await travel("central_trade") and await city_ready() and action("accept_delivery") and await travel(TownDB.DELIVERY_TO) and main.town.delivery == "return" and await travel("central_trade") and await city_ready() and action("claim_delivery") and main.world.reward_replenish_pending

func assert_revisit(fixed_creature_id: String, carcass_ids: Array, expected: Dictionary, label: String) -> void:
	main.world._spawn_visible()
	var fixed = live_creature(fixed_creature_id)
	check(fixed != null and not fixed.dead and unique_living_ids(), label + " restores exactly one live fixed creature")
	check(active_carcasses().is_empty(), label + " does not materialize historical carcasses")
	check(recorded_carcasses().size() == carcass_ids.size() and recorded_carcasses().all(func(entry): return entry.row.spent), label + " keeps every historical carcass spent in the ledger")
	check(drop_counts("hare") == expected, label + " leaves stored hunt-drop totals unchanged before the next hunt")

func _initialize() -> void:
	SaveGame.disabled = false
	SaveGame.new_run_requested = true
	SaveGame.active_checkpoint.clear()
	SaveGame.run_selected = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set_meta("diagnostic_seed", 641)
	root.add_child(main)
	await main.ready
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.target_speed = 200.0
	for worker in main.workers: worker.set_process(false)
	configure_single_hunter()
	main.world._spawn_visible()
	var first_fixed = main.creatures_root.get_children().filter(func(node): return not node.is_queued_for_deletion())[0]
	var fixed_id: String = first_fixed.world_id
	var baseline := drop_counts(first_fixed.species)

	var first := await hunt_and_store(1)
	if first.is_empty():
		print("== RESULT: %d FAILED ==" % fails)
		quit(1)
		return
	check(first.creature_id == fixed_id, "first hunt targets the fixed south-oasis creature")
	var expected := expected_drops(baseline, first.species, 1)
	check(drop_counts(first.species) == expected and main.storage.total_butchered == 1, "first carcass contributes exactly one normal drop set")
	check(await claim_delivery_reward(1), "first normal delivery reward schedules a world renewal")
	check(await travel("south_oasis"), "first post-reward normal revisit reaches south oasis")
	assert_revisit(fixed_id, [first.carcass_id], expected, "first reward revisit")

	var second := await hunt_and_store(2)
	if second.is_empty():
		print("== RESULT: %d FAILED ==" % fails)
		quit(1)
		return
	check(second.creature_id == fixed_id and second.carcass_id != first.carcass_id, "second hunt reuses the fixed creature id but creates one new carcass id")
	expected = expected_drops(baseline, second.species, 2)
	check(drop_counts(second.species) == expected and main.storage.total_butchered == 2, "two hunts contribute exactly two drop sets")
	check(await claim_delivery_reward(2), "second normal delivery reward schedules a second world renewal")
	check(await travel("south_oasis"), "second post-reward normal revisit reaches south oasis")
	assert_revisit(fixed_id, [first.carcass_id, second.carcass_id], expected, "second reward revisit")
	check(recorded_carcasses().map(func(entry): return entry.id).has(first.carcass_id) and recorded_carcasses().map(func(entry): return entry.id).has(second.carcass_id), "both historical carcass records remain only as spent history")

	print("== RESULT: %s ==" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
