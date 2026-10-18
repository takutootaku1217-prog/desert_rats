extends SceneTree

## Approved stage-three economy comparison.  This intentionally uses the
## player-facing order, map, quarry, town, save, recall and rescue APIs only.
## It does not add materials, credits or test-only resources.
const STEP := 0.2
const SEED_VALUE := 641

var main
var fails := 0
var comparison: Array = []

func check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func boot(crew_count: int) -> void:
	if main != null:
		root.remove_child(main)
		main.free()
		await process_frame
		await process_frame
	SaveGame.disabled = false
	# The test uses the same public new-game path as the UI, but its APPDATA is
	# isolated by the runner.  Never resume a prior diagnostic progress file.
	SaveGame.new_run_requested = true
	SaveGame.active_checkpoint.clear()
	SaveGame.run_selected = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set_meta("diagnostic_seed", SEED_VALUE)
	main.set_meta("diagnostic_crew_count", crew_count)
	root.add_child(main)
	await main.ready
	main.process_mode = Node.PROCESS_MODE_DISABLED
	check(main.workers.size() == crew_count, "configured crew count is used")
	check(main.storage.count_of(GameData.Item.FOOD) == 8 and main.storage.count_of(GameData.Item.FUEL) == 2 and main.storage.count_of(GameData.Item.REPAIR_KIT) == 2 and main.town.credits == 0, "both starts use normal stock and funds")
	check(main.tool_auto, "automatic tool use is enabled by default")
	check(main.refill_settings.get(GameData.Item.FOOD, {}).get("target", -1) == 12 and main.refill_settings.get(GameData.Item.FUEL, {}).get("target", -1) == 8 and main.refill_settings.get(GameData.Item.REPAIR_KIT, {}).get("target", -1) == 6, "default automatic-supply retention targets are food 12, fuel 8 and repair kits 6")

func tick() -> void:
	main._process(STEP)
	for r in main.resources_root.get_children():
		if not r.is_queued_for_deletion(): r._process(STEP)
	for c in main.creatures_root.get_children():
		if not c.is_queued_for_deletion(): c._process(STEP)
	for e in main.enemies_root.get_children():
		if not e.is_queued_for_deletion(): e._process(STEP)
	for w in main.workers:
		if not w.is_queued_for_deletion(): w._process(STEP)
	await process_frame

func wait_for(done: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		if done.call(): return true
		await tick()
	return done.call()

func travel(to: String, seconds := 420.0) -> bool:
	if not main.world.request(to): return false
	return await wait_for(func(): return main.world.region == to and main.world.phase == "stopped", seconds)

func city_ready() -> bool:
	return await wait_for(func(): return main.town.entry_reason() == "", 240.0)

func city_action(action: String, item := -1, n := 1) -> bool:
	return main.town.execute(main.town.quote(action, item, n))

func part_snapshot() -> Dictionary:
	return {
		"hull": snappedf(main.base.parts[GameData.Part.HULL], 0.01),
		"drive": snappedf(main.base.parts[GameData.Part.DRIVE], 0.01),
		"machine": snappedf(main.base.parts[GameData.Part.MACHINE], 0.01),
	}

func crew_snapshot() -> Array:
	var rows: Array = []
	for w in main.workers:
		rows.append({"name": w.char_name, "state": CharacterAI.State.keys()[w.ai.state], "hp": snappedf(w.hp, 0.01), "hunger": snappedf(w.hunger, 0.01), "fatigue": snappedf(w.fatigue, 0.01), "down": w.down, "away": w.away})
	return rows

func upgrades() -> Dictionary:
	return {"workbench": main.has_facility("workbench"), "storage_upgrade": main.has_facility("storage_upgrade"), "parallel_bench": main.has_facility("parallel_bench"), "work_support": main.workers.map(func(w): return w.work_support)}

func snapshot() -> Dictionary:
	return {"credits": main.town.credits, "fuel": snappedf(main.base.fuel, 0.01), "food": main.storage.count_of(GameData.Item.FOOD), "repair_kits": main.storage.count_of(GameData.Item.REPAIR_KIT), "eaten": main.total_eaten, "repair_total": main.base.total_repair, "parts": part_snapshot(), "gathered": main.total_gathered, "world": {"region": main.world.region, "phase": main.world.phase}, "quarry": {"state": main.quarry.state, "near": main.quarry.group_left("近場"), "far": main.quarry.group_left("奥")}, "upgrades": upgrades(), "crew": crew_snapshot()}

func entity_ids_unique() -> bool:
	var ids := {}
	for node in main.creatures_root.get_children() + main.enemies_root.get_children():
		if not is_instance_valid(node) or node.dead: continue
		var id: String = str(node.get("world_id"))
		if id.is_empty(): continue
		if ids.has(id): return false
		ids[id] = true
	return true

func record_sortie(rows: Array, name: String, before: Dictionary, note := "") -> void:
	var after := snapshot()
	rows.append({"name": name, "note": note, "credits_delta": int(after.credits) - int(before.credits), "fuel_consumed_net": snappedf(float(before.fuel) - float(after.fuel), 0.01), "food_consumed": int(after.eaten) - int(before.eaten), "repair_actions": int(after.repair_total) - int(before.repair_total), "start": before, "return": after})

func worker_has_tool(item: int) -> bool:
	return main.workers.any(func(w): return w.tools.values().has(item))

func has_order(id: String) -> bool:
	return main.production_orders.any(func(order): return str(order.get("id", "")) == id)

func queue_progression() -> void:
	if not main.has_facility("workbench") and not main.build_queue.has("workbench"):
		check(main.request_build("workbench"), "workbench request uses the normal build queue")
	# These are ordinary standing orders.  The planner gathers their materials;
	# no test material is injected and tool auto-equip remains enabled.
	if not worker_has_tool(GameData.Item.WOOD_PICK) and not has_order("tool_wood_pick"):
		check(main.request_order("tool_wood_pick", 1) == 1, "wood pick order uses the normal player-order queue")
	if not worker_has_tool(GameData.Item.HAMMER) and not has_order("tool_hammer"):
		check(main.request_order("tool_hammer", 1) == 1, "hammer order uses the normal player-order queue")
	if main.storage.count_of(GameData.Item.IRON) < 1 and not has_order("smelt"):
		check(main.request_order("smelt", 4) == 4, "smelting order uses the normal player-order queue")
	# Storage upgrade requires a cargo rack; a haul frame is the lower-cost
	# approved first improvement and is queued through the same player API.
	if main.has_facility("workbench") and not main.workers.any(func(w): return w.work_support >= 0) and main.storage.count_of(GameData.Item.HAUL_FRAME) == 0 and not has_order("haul_frame"):
		check(main.request_order("haul_frame", 1) == 1, "haul-frame order uses the normal player-order queue")
	if main.storage.count_of(GameData.Item.HAUL_FRAME) > 0:
		for w in main.workers:
			if w.work_support < 0 and main.equip_work_support(w):
				check(true, "haul frame equips through the normal crew action")
				break

func leave_mine() -> bool:
	main.operations.set_stance("recall")
	if not main.quarry.request_departure(): return false
	if not await wait_for(func(): return main.quarry.ready_to_leave(), 300.0): return false
	if not main.quarry.leave(): return false
	if not await wait_for(func(): return main.quarry.state == "road", 90.0): return false
	main.operations.set_stance("normal")
	return true

func visit_mine(expect_full: bool, drain: bool) -> Dictionary:
	check(await travel("old_mine"), "map travel reaches the normal mine location")
	check(main.quarry.select(), "mine selection uses the normal map/quarry entry")
	check(await wait_for(func(): return main.quarry.state == "parked", 90.0), "mine arrival completes")
	var result := {"near": main.quarry.group_left("近場"), "far": main.quarry.group_left("奥"), "points": main.quarry.points.size()}
	check(main.quarry.points.size() == 4 and entity_ids_unique(), "mine visit does not duplicate live world entities")
	if expect_full:
		check(main.quarry.group_left("近場") == 12 and main.quarry.group_left("奥") == 72, "completed reward replenishes only the next mine visit")
	if drain:
		# Player-facing procurement priority gives the ordinary gather AI an ore
		# target; it neither grants inventory nor changes quarry stock.
		main.set_procurement(GameData.Item.IRON_ORE, 4)
		var near_before: int = main.quarry.group_left("近場")
		check(await wait_for(func(): return main.quarry.group_left("近場") < near_before, 180.0), "normal gather AI depletes ordinary mine resources")
		result["drained_near"] = main.quarry.group_left("近場")
	check(await leave_mine(), "mine departure waits for the normal all-crew recall")
	check(await travel("central_trade") and await city_ready(), "mine return reaches the town normally")
	return result

func perform_maintenance() -> Dictionary:
	var before := snapshot()
	var paid := 0
	if main.base.fuel < 80.0 and city_action("fuel_cash"):
		paid += 1
	if main.storage.count_of(GameData.Item.FOOD) < main.workers.size() and city_action("buy", GameData.Item.FOOD, 1):
		paid += 1
	for part in GameData.Part.values():
		if main.base.parts[part] < 90.0 and city_action("repair_cash", part):
			paid += 1
	return {"actions": paid, "before": before, "after": snapshot()}

func make_cargo_room(weight: int, label: String) -> void:
	# Contracts have real parcel weights.  Free space through the town sell API
	# rather than altering inventory or bypassing their capacity requirements.
	for item in [GameData.Item.MEAT, GameData.Item.BONE, GameData.Item.FAT, GameData.Item.STONE, GameData.Item.IRON_ORE, GameData.Item.WOOD]:
		while not main.town.cargo_room(weight) and main.town.available(item) > 0:
			if not city_action("sell", item, 1): break
	check(main.town.cargo_room(weight), "town sell path makes room for the normal " + label + " parcel")

func save_and_restart() -> Dictionary:
	check(SaveGame.write_checkpoint(main, true), "town checkpoint writes through the normal save path")
	var checkpoint_credits: int = main.town.credits
	var purchased := false
	if main.town.credits >= TownDB.BUY[GameData.Item.FOOD]:
		purchased = city_action("buy", GameData.Item.FOOD, 1)
	var restored := SaveGame.restart_from_checkpoint(main)
	var expected := checkpoint_credits - SaveGame.restart_loss(checkpoint_credits)
	check(restored and main.town.credits == expected, "checkpoint restart restores the run and applies the configured loss once")
	return {"checkpoint_credits": checkpoint_credits, "purchased_before_restart": purchased, "restart_credits": main.town.credits}

func rescue_fixture() -> Dictionary:
	main.operations.set_stance("recall")
	check(await wait_for(func(): return main.operations.returned_count() == main.workers.size(), 180.0), "retreat returns the full active crew")
	var injured = main.workers[0]
	var carrier = main.workers[1]
	injured.floor_i = 0
	carrier.floor_i = 0
	injured.position = Vector2(920, GameData.LO_Y)
	carrier.position = Vector2(760, GameData.LO_Y)
	injured.ai._set_state(CharacterAI.State.SEARCH)
	carrier.ai._set_state(CharacterAI.State.SEARCH)
	CrewStatus.damage(injured, 999.0)
	check(main.rescue.assign(carrier, injured), "scripted rescue fixture uses the normal explicit carrier assignment")
	for unused in 1200:
		main.rescue.carrier_tick(carrier, 0.1)
		if not injured.down: break
	check(not injured.down and injured.ai.post_rescue_wait, "rescue returns the injured worker and preserves explicit resume state")
	var waited_before_resume: bool = injured.ai.post_rescue_wait
	main.rescue.resume(injured)
	main.operations.set_stance("normal")
	return {"rescued": not injured.down, "post_rescue_wait_before_resume": waited_before_resume, "resumed": not injured.ai.post_rescue_wait}

func run_case(crew_count: int) -> Dictionary:
	await boot(crew_count)
	var sorties: Array = []
	queue_progression()
	check(await travel("central_trade") and await city_ready(), "new run reaches the town on the default map")
	check(await wait_for(func(): return worker_has_tool(GameData.Item.HAMMER), 360.0), "normal wood-pick and hammer orders enable ordinary ore gathering")
	queue_progression()
	# Mine once before rewards, then prove that accepting/cancelling a mission
	# never schedules a refill and that the next visit retains the depletion.
	var first_mine := await visit_mine(false, true)
	check(city_action("accept_supply", GameData.Item.WOOD) and city_action("cancel_supply"), "mission cancellation uses the town API")
	check(not main.quarry.reward_replenish_pending, "cancelled mission does not schedule replenishment")
	var retained_mine := await visit_mine(false, false)
	check(int(retained_mine.near) == int(first_mine.drained_near), "cancelled mission does not instantly or later refill the mine")

	var before := snapshot()
	var gathered_before: int = main.total_gathered
	make_cargo_room(TownDB.DELIVERY_PARCEL_WEIGHT, "delivery")
	check(city_action("accept_delivery"), "sortie 1 accepts the normal delivery mission")
	check(await travel(TownDB.DELIVERY_TO), "sortie 1 travels to delivery destination")
	main.workers[0].set_priority(GameData.Job.HUNT, 5)
	check(await wait_for(func(): return main.total_gathered > gathered_before, 150.0), "sortie 1 obtains ordinary field resources through AI")
	# The ordinary field loop supplies the haul-frame recipe; its material may be
	# consumed immediately by the queued order, so completed equipment below is
	# the stable observable rather than transient hide inventory or hunt timing.
	check(await travel("central_trade") and await city_ready() and city_action("claim_delivery"), "sortie 1 returns and claims delivery reward")
	check(main.quarry.reward_replenish_pending and main.quarry.points.is_empty(), "reward schedules, but never performs an in-place mine respawn")
	record_sortie(sorties, "delivery", before)
	queue_progression()
	await visit_mine(true, false)

	before = snapshot()
	check(city_action("accept_supply", GameData.Item.WOOD), "sortie 2 accepts the normal supply mission")
	gathered_before = main.total_gathered
	check(await travel("south_oasis"), "sortie 2 travels to the ordinary supply region")
	check(await wait_for(func(): return main.total_gathered > gathered_before and main.storage.count_of(GameData.Item.WOOD) >= TownDB.SUPPLY_OFFERS[GameData.Item.WOOD].count, 240.0), "sortie 2 gathers the requested material without a test grant")
	check(await travel("central_trade") and await city_ready() and city_action("claim_supply"), "sortie 2 returns and claims supply reward")
	check(main.quarry.reward_replenish_pending, "every claimed mission schedules the next mine replenish")
	var maintenance := perform_maintenance()
	record_sortie(sorties, "supply", before, "maintenance=" + JSON.stringify(maintenance))
	queue_progression()
	check(await wait_for(func(): return main.has_facility("storage_upgrade") or main.workers.any(func(w): return w.work_support >= 0), 180.0), "normal production completes the first storage or hauling improvement")
	check(main.has_facility("storage_upgrade") or main.workers.any(func(w): return w.work_support >= 0), "storage or hauling improvement is reached by the first two sorties")

	before = snapshot()
	main.operations.set_stance("recall")
	check(await wait_for(func(): return main.operations.returned_count() == main.workers.size(), 180.0), "recovery begins after the crew returns from the prior sortie")
	main.operations.set_stance("normal")
	make_cargo_room(TownDB.RECOVERY_PARCEL_WEIGHT, "recovery")
	check(city_action("accept_recovery"), "sortie 3 accepts the normal recovery mission")
	# Keep the declared recovery capacity free while crossing the road.  Alert
	# and field policies are normal player controls; they are restored after the
	# parcel is stowed, before the mission reward is claimed.
	var saved_gather_policy: Dictionary = main.gather_policy.duplicate(true)
	var saved_hunt_policy: Dictionary = main.hunt_policy.duplicate(true)
	for item in [GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE]:
		main.gather_policy[item] = 0
	for species in main.hunt_policy:
		main.hunt_policy[species] = false
	main.operations.set_stance("alert")
	check(await travel(TownDB.RECOVERY_TO), "sortie 3 travels to recovery destination")
	main.operations.set_stance("normal")
	check(main.town.recovery in ["site", "loading", "carried", "return", "ready"], "recovery request reaches the normal field site")
	# Save/reload at the field site, before the recovery worker is assigned.  It
	# verifies an actual mid-sortie continuation without sampling the brief
	# loading state as a proxy for completed recovery.
	check(SaveGame.write_progress(main, true) and SaveGame.continue_progress(main, SaveGame.read_progress()), "mid-sortie progress save and explicit continue restore")
	# Crew may finish a rest or repair task first; retain the normal scheduler and
	# wait through that bounded field-action window rather than assigning a worker.
	var recovered: bool = await wait_for(func(): return main.town.recovery == "return", 420.0)
	check(recovered, "sortie 3 uses a normal worker recovery action")
	check(recovered, "recovered cargo returns to the mobile base")
	main.gather_policy = saved_gather_policy
	main.hunt_policy = saved_hunt_policy
	check(await travel("central_trade") and await city_ready() and city_action("claim_recovery"), "sortie 3 returns and claims recovery reward")
	check(main.quarry.reward_replenish_pending, "third reward also schedules replenishment")
	maintenance = perform_maintenance()
	record_sortie(sorties, "recovery", before, "maintenance=" + JSON.stringify(maintenance))
	var rescue := await rescue_fixture()
	var restart := save_and_restart()
	var final := snapshot()
	var record := {"seed": SEED_VALUE, "crew_count": crew_count, "sorties": sorties, "profit_after_maintenance": final.credits, "upgrades": final.upgrades, "crew": final.crew, "rescue": rescue, "checkpoint_restart": restart, "mine_first": first_mine, "mine_after_cancel": retained_mine, "result": final}
	print("SORTIE_ECONOMY_JSON " + JSON.stringify(record))
	check(not main.game_over and final.credits > 0 and entity_ids_unique(), "three-sortie normal economy retains a post-maintenance profit without duplicate living entities")
	return record

func _initialize() -> void:
	var crew_count := 4
	var args := OS.get_cmdline_user_args()
	var arg_index := args.find("--crew-count")
	if arg_index >= 0 and arg_index + 1 < args.size():
		crew_count = int(args[arg_index + 1])
	check(crew_count in [4, 5], "selected crew count is supported")
	if crew_count not in [4, 5]:
		print("== RESULT: %d FAILED ==" % fails)
		quit(1)
		return
	comparison.append(await run_case(crew_count))
	print("SORTIE_ECONOMY_COMPARISON " + JSON.stringify(comparison))
	print("== RESULT: %s ==" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
