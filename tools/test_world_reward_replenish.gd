extends SceneTree

## Normal-world reward regression.  It travels via the public map and claims a
## real town delivery; setup only marks existing ledger entities as depleted so
## this test can isolate renewal rather than manufacture extra materials.
const STEP := 0.2
var fails := 0
var main

func check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func tick() -> void:
	main._process(STEP)
	for node in main.resources_root.get_children():
		if not node.is_queued_for_deletion(): node._process(STEP)
	for node in main.creatures_root.get_children():
		if not node.is_queued_for_deletion(): node._process(STEP)
	for node in main.enemies_root.get_children():
		if not node.is_queued_for_deletion(): node._process(STEP)
	for worker in main.workers:
		if not worker.is_queued_for_deletion(): worker._process(STEP)
	await process_frame

func wait_for(done: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		if done.call(): return true
		await tick()
	return done.call()

func recall_ready() -> bool:
	main.operations.set_stance("recall")
	var ok := await wait_for(func(): return main.operations.returned_count() == main.workers.size(), 180.0)
	main.operations.set_stance("normal")
	return ok

func travel(to: String) -> bool:
	var next_stance: String = main.operations.stance
	main.operations.set_stance("recall")
	if not main.world.request(to):
		if not await recall_ready(): return false
		if not main.world.request(to): return false
	var arrived := await wait_for(func(): return main.world.region == to and main.world.phase == "stopped", 240.0)
	main.operations.set_stance(next_stance)
	return arrived

func city_ready() -> bool:
	return await wait_for(func(): return main.town.entry_reason() == "", 180.0)

func action(name: String, item := -1, n := 1) -> bool:
	return main.town.execute(main.town.quote(name, item, n))

func unique_living_ids() -> bool:
	var ids := {}
	for node in main.creatures_root.get_children() + main.enemies_root.get_children():
		if node.is_queued_for_deletion() or node.dead: continue
		if ids.has(node.world_id): return false
		ids[node.world_id] = true
	return true

func exhaust_here() -> Dictionary:
	main.world._spawn_visible()
	var point = main.resources_root.get_children().filter(func(n): return n is GatherPoint)[0]
	var creature = main.creatures_root.get_child(0)
	var point_id: String = point.world_id
	var creature_id: String = creature.world_id
	point.remaining = 0
	main.world.consume(point)
	point.queue_free()
	creature.take_damage(999.0)
	await process_frame
	return {"resource": point_id, "creature": creature_id}

func row(id: String) -> Dictionary:
	return main.world.locations[main.world.key()][id]

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

	var south_ids := await exhaust_here()
	check(row(south_ids.resource).spent and row(south_ids.creature).spent, "depleted resource and dead creature are recorded in the normal-world ledger")
	check(await travel("central_trade") and await city_ready(), "normal map travel reaches town")
	var city_ids := await exhaust_here()
	check(action("accept_delivery"), "normal delivery mission is accepted")
	check(await travel(TownDB.DELIVERY_TO) and await recall_ready() and await travel("central_trade") and await city_ready(), "delivery travels and returns through normal map states")
	check(action("claim_delivery"), "normal delivery reward is claimed")
	check(main.world.reward_replenish_pending and main.quarry.reward_replenish_pending, "claimed reward schedules both normal-world and mine renewal")
	check(row(city_ids.resource).spent and row(city_ids.creature).spent, "claiming a reward never respawns the current town immediately")
	check(SaveGame.write_progress(main, true) and SaveGame.continue_progress(main, SaveGame.read_progress()), "pending normal-world renewal survives save and explicit Continue")
	check(main.world.reward_replenish_pending, "restored progress retains the pending renewal exactly once")
	# A turnback reaches the city where the reward was received, not a new normal
	# region.  It must leave its spent ledger rows untouched and keep the pending
	# renewal for the next distinct region arrival.
	main.operations.set_stance("recall")
	check(main.world.request("south_oasis") and await wait_for(func(): return main.world.phase == "travel", 60.0), "post-reward departure begins before the turnback check")
	check(main.world.cancel_or_return() and await wait_for(func(): return main.world.region == "central_trade" and main.world.phase == "stopped", 240.0), "turning back reaches the reward city normally")
	main.operations.set_stance("normal")
	check(main.world.reward_replenish_pending and row(city_ids.resource).spent and row(city_ids.creature).spent, "turnback to the reward city neither renews resources nor consumes the pending renewal")

	check(await travel("south_oasis"), "next normal-world visit reaches the depleted region")
	main.world._spawn_visible()
	check(not main.world.reward_replenish_pending and not row(south_ids.resource).spent and row(south_ids.resource).data.remaining == row(south_ids.resource).data.max_amount, "next visit refills the recorded resource once")
	check(not row(south_ids.creature).spent and not row(south_ids.creature).data.dead and row(south_ids.creature).data.hp == row(south_ids.creature).data.max_hp, "next visit restores the existing fauna id")
	check(main.creatures_root.get_children().any(func(c): return c.world_id == south_ids.creature) and unique_living_ids(), "restored fauna has one live instance with no duplicate ids")

	# With the reservation consumed, another depletion persists through a round
	# trip. This distinguishes one-shot renewal from a location-entry respawner.
	south_ids = await exhaust_here()
	check(await travel("central_trade") and await city_ready() and await travel("south_oasis"), "second ordinary round trip completes without another reward")
	check(not main.world.reward_replenish_pending and row(south_ids.resource).spent and row(south_ids.creature).spent, "following visit does not replenish again without a new claim")

	# Cancelling a town offer schedules neither renewal and keeps the same depleted
	# world state on the next visit.
	check(await travel("central_trade") and await city_ready(), "town is reached for cancellation")
	var world_pending_before_cancel: bool = main.world.reward_replenish_pending
	var quarry_pending_before_cancel: bool = main.quarry.reward_replenish_pending
	check(action("accept_supply", GameData.Item.WOOD) and action("cancel_supply"), "supply offer is cancelled through the normal town API")
	check(main.world.reward_replenish_pending == world_pending_before_cancel and main.quarry.reward_replenish_pending == quarry_pending_before_cancel, "cancelled offer adds no normal-world or mine renewal reservation")
	check(await travel("south_oasis"), "normal visit after cancellation completes")
	check(row(south_ids.resource).spent and row(south_ids.creature).spent and unique_living_ids(), "cancellation leaves depleted resource/fauna unchanged and non-duplicated")

	print("== RESULT: %s ==" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
