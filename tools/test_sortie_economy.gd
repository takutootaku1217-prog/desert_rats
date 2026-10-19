extends SceneTree

## Approved stage-three economy comparison. A run is three claimed town
## missions (delivery, supply, recovery). Every map request, including the
## one preparation leg needed to reach town, is recorded. No mine visits,
## resource grants, checkpoint loss, or rescue component fixtures are mixed
## into the economic result.
const STEP := 0.2
const DEFAULT_SEED_VALUE := 641
const FOOD_TARGET := 8
const REPAIR_KIT_TARGET := 2
const FUEL_TARGET := 100.0

var main
var fails := 0
var legs: Array = []
var sales: Array = []
var maintenance_reference := {}
var case_started_elapsed := 0.0
var seed_value := DEFAULT_SEED_VALUE
var observation_seconds := 0.0
var repeat_delivery_count := 0
var eventual_maintenance_probe := false
var trace_phase := ""
var state_seconds_by_phase := {}

func check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok: fails += 1

func boot(crew_count: int) -> void:
	SaveGame.disabled = false
	SaveGame.new_run_requested = true
	SaveGame.active_checkpoint.clear()
	SaveGame.run_selected = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set_meta("diagnostic_seed", seed_value)
	main.set_meta("diagnostic_crew_count", crew_count)
	root.add_child(main)
	await main.ready
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.target_speed = 200.0
	check(main.workers.size() == crew_count, "configured cohort size is used")
	check(main.storage.count_of(GameData.Item.FOOD) == 8 and main.storage.count_of(GameData.Item.FUEL) == 2 and main.storage.count_of(GameData.Item.REPAIR_KIT) == 2 and main.town.credits == 0, "both cohorts start with normal stock and funds")
	check(main.tool_auto, "automatic tool use is enabled")
	check(main.refill_settings.get(GameData.Item.FOOD, {}).get("target", -1) == 12 and main.refill_settings.get(GameData.Item.FUEL, {}).get("target", -1) == 8 and main.refill_settings.get(GameData.Item.REPAIR_KIT, {}).get("target", -1) == 6, "automatic minimum retention remains food 12, fuel 8, repair kits 6")

func tick() -> void:
	if not trace_phase.is_empty():
		var trace: Dictionary = state_seconds_by_phase.get(trace_phase, {})
		for worker in main.workers:
			var state_name: String = CharacterAI.State.keys()[worker.ai.state]
			trace[state_name] = snappedf(float(trace.get(state_name, 0.0)) + STEP, 0.01)
		state_seconds_by_phase[trace_phase] = trace
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

func part_snapshot() -> Dictionary:
	return {"hull": snappedf(main.base.parts[GameData.Part.HULL], 0.01), "drive": snappedf(main.base.parts[GameData.Part.DRIVE], 0.01), "machine": snappedf(main.base.parts[GameData.Part.MACHINE], 0.01)}

func crew_snapshot() -> Array:
	var rows: Array = []
	for worker in main.workers:
		rows.append({"name": worker.char_name, "state": CharacterAI.State.keys()[worker.ai.state], "hp": snappedf(worker.hp, 0.01), "hunger": snappedf(worker.hunger, 0.01), "fatigue": snappedf(worker.fatigue, 0.01), "down": worker.down, "away": worker.away})
	return rows

func market_value(items: Dictionary) -> int:
	var value := 0
	for item in items:
		if TownDB.SELL.has(item): value += int(items[item]) * int(TownDB.SELL[item])
	return value

func upgrades() -> Dictionary:
	return {"workbench": main.has_facility("workbench"), "storage_upgrade": main.has_facility("storage_upgrade"), "haul_frame": main.workers.any(func(w): return w.work_support == GameData.Item.HAUL_FRAME), "work_support": main.workers.map(func(w): return w.work_support)}

func visible_gather_points() -> Array:
	var rows: Array = []
	for node in main.resources_root.get_children():
		if node is GatherPoint:
			rows.append({"kind": node.kind, "item": node.item, "remaining": node.remaining, "max_amount": node.max_amount, "claimed": node.claimed_by != null})
	return rows

func snapshot() -> Dictionary:
	var inventory: Dictionary = main.storage.inventory.counts.duplicate(true)
	var stock: Dictionary = main.processor.stock.counts.duplicate(true)
	return {"elapsed_seconds": snappedf(main.director.elapsed, 0.01), "credits": main.town.credits, "inventory": inventory, "stock": stock, "tradable_asset_value": market_value(inventory) + market_value(stock), "fuel": snappedf(main.base.fuel, 0.01), "food": main.storage.count_of(GameData.Item.FOOD), "repair_kits": main.storage.count_of(GameData.Item.REPAIR_KIT), "eaten": main.total_eaten, "refuel_actions": main.base.total_refuel, "repair_actions": main.base.total_repair, "parts": part_snapshot(), "gathered": main.total_gathered, "upgrades": upgrades(), "orders": main.production_orders.duplicate(true), "craft_queue": main.craft_queue.duplicate(true), "processor_orders": main.processor.orders.duplicate(true), "transfer_queue": main.transfer_queue.duplicate(true), "procurement_goals": main.procurement_goals.duplicate(true), "visible_gather_points": visible_gather_points(), "crew": crew_snapshot(), "world": {"region": main.world.region, "phase": main.world.phase}}

func entity_ids_unique() -> bool:
	var ids := {}
	for node in main.creatures_root.get_children() + main.enemies_root.get_children():
		if not is_instance_valid(node) or node.is_queued_for_deletion() or node.dead: continue
		if ids.has(node.world_id): return false
		ids[node.world_id] = true
	return true

func travel(to: String, label: String) -> bool:
	var before := snapshot()
	var from: String = main.world.region
	var next_stance: String = main.operations.stance
	main.operations.set_stance("recall")
	if not main.world.request(to):
		if not await wait_for(func(): return main.operations.returned_count() == main.workers.size(), 180.0): return false
		if not main.world.request(to): return false
	var arrived := await wait_for(func(): return main.world.region == to and main.world.phase == "stopped", 300.0)
	main.operations.set_stance(next_stance)
	var after := snapshot()
	legs.append({"label": label, "from": from, "to": to, "arrived": arrived, "credits_delta": int(after.credits) - int(before.credits), "fuel_consumed_net": snappedf(float(before.fuel) - float(after.fuel), 0.01), "food_consumed": int(after.eaten) - int(before.eaten), "repair_actions": int(after.repair_actions) - int(before.repair_actions), "start": before, "end": after})
	return arrived

func city_ready() -> bool:
	return await wait_for(func(): return main.town.entry_reason() == "", 180.0)

func city_action(action: String, item := -1, n := 1) -> bool:
	return main.town.execute(main.town.quote(action, item, n))

func worker_has_tool(item: int) -> bool:
	return main.workers.any(func(w): return w.tools.values().has(item))

func has_order(id: String) -> bool:
	return main.production_orders.any(func(order): return str(order.get("id", "")) == id)

func first_improvement() -> bool:
	return main.has_facility("storage_upgrade") or main.workers.any(func(w): return w.work_support == GameData.Item.HAUL_FRAME)

## Record the production-system explanation during the approved first-upgrade
## wait.  The result distinguishes material/transfer/lane constraints from
## workers merely being in IDLE/REST states; it does not alter scheduling.
func wait_for_first_improvement(seconds: float) -> Dictionary:
	var before := snapshot()
	var reasons := {}
	for unused in ceili(seconds / STEP):
		if main.storage.count_of(GameData.Item.HAUL_FRAME) > 0 or main.has_facility("storage_upgrade"):
			return {"done": true, "elapsed_seconds": snappedf(main.director.elapsed - float(before.elapsed_seconds), 0.01), "reasons": reasons, "before": before, "after": snapshot()}
		var reason: String = ProductionPlan.order_reason(main, GameData.recipe_by_id("haul_frame"))
		reasons[reason] = snappedf(float(reasons.get(reason, 0.0)) + STEP, 0.01)
		await tick()
	return {"done": main.storage.count_of(GameData.Item.HAUL_FRAME) > 0 or main.has_facility("storage_upgrade"), "elapsed_seconds": snappedf(main.director.elapsed - float(before.elapsed_seconds), 0.01), "reasons": reasons, "before": before, "after": snapshot()}

func queue_progression() -> void:
	if not main.has_facility("workbench") and not main.build_queue.has("workbench"):
		check(main.request_build("workbench"), "workbench request uses normal build queue")
	if not worker_has_tool(GameData.Item.WOOD_PICK) and not has_order("tool_wood_pick"):
		check(main.request_order("tool_wood_pick", 1) == 1, "wood-pick order uses player queue")
	if not worker_has_tool(GameData.Item.HAMMER) and not has_order("tool_hammer"):
		check(main.request_order("tool_hammer", 1) == 1, "hammer order uses player queue")
	if main.storage.count_of(GameData.Item.IRON) < 1 and not has_order("smelt"):
		check(main.request_order("smelt", 4) == 4, "smelting order uses player queue")
	if main.has_facility("workbench") and not main.workers.any(func(w): return w.work_support >= 0) and main.storage.count_of(GameData.Item.HAUL_FRAME) == 0 and not has_order("haul_frame"):
		check(main.request_order("haul_frame", 1) == 1, "haul-frame order uses player queue")
	for item in [GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE]: main.set_procurement(item, 8)
	if main.storage.count_of(GameData.Item.HAUL_FRAME) > 0:
		for worker in main.workers:
			if worker.work_support < 0 and main.equip_work_support(worker):
				check(true, "haul frame equips through normal crew action")
				break

func maintain_same_level() -> Dictionary:
	var before := snapshot()
	var target: Dictionary = maintenance_reference if not maintenance_reference.is_empty() else before
	var purchases := {"fuel": 0, "food": 0, "repair_kits": 0, "part_repairs": 0}
	while main.base.fuel < float(target.fuel) - 0.01 and city_action("fuel_cash"): purchases.fuel += 1
	while main.storage.count_of(GameData.Item.FOOD) < int(target.food) and city_action("buy", GameData.Item.FOOD, 1): purchases.food += 1
	while main.storage.count_of(GameData.Item.REPAIR_KIT) < int(target.repair_kits) and city_action("buy", GameData.Item.REPAIR_KIT, 1): purchases.repair_kits += 1
	for part in GameData.Part.values():
		var part_name: String = {GameData.Part.HULL: "hull", GameData.Part.DRIVE: "drive", GameData.Part.MACHINE: "machine"}[part]
		while main.base.parts[part] < float(target.parts[part_name]) - 0.01 and city_action("repair_cash", part): purchases.part_repairs += 1
	var after := snapshot()
	var reached: bool = after.fuel >= float(target.fuel) - 0.01 and after.food >= int(target.food) and after.repair_kits >= int(target.repair_kits) and after.parts.hull >= float(target.parts.hull) - 0.01 and after.parts.drive >= float(target.parts.drive) - 0.01 and after.parts.machine >= float(target.parts.machine) - 0.01
	return {"target": {"fuel": target.fuel, "food": target.food, "repair_kits": target.repair_kits, "parts": target.parts}, "reached": reached, "purchases": purchases, "cash_cost": int(before.credits) - int(after.credits), "before": before, "after": after}

func assert_maintenance_state(label: String, state: Dictionary) -> void:
	var target: Dictionary = maintenance_reference
	check(state.fuel >= float(target.fuel) - 0.01, label + " retains the common fuel level")
	check(state.food >= int(target.food), label + " retains the common food level")
	check(state.repair_kits >= int(target.repair_kits), label + " retains the common repair-kit level")
	check(state.parts.hull >= float(target.parts.hull) - 0.01 and state.parts.drive >= float(target.parts.drive) - 0.01 and state.parts.machine >= float(target.parts.machine) - 0.01, label + " restores every base part to the common durability level")
	check(state.crew.all(func(worker): return not worker.down and not worker.away), label + " has no down or absent crew")


func maintenance_parts_reached(state: Dictionary) -> bool:
	var target: Dictionary = maintenance_reference
	return state.parts.hull >= float(target.parts.hull) - 0.01 and state.parts.drive >= float(target.parts.drive) - 0.01 and state.parts.machine >= float(target.parts.machine) - 0.01

func make_cargo_room(weight: int, label: String) -> bool:
	for item in [GameData.Item.MEAT, GameData.Item.BONE, GameData.Item.FAT, GameData.Item.STONE, GameData.Item.IRON_ORE, GameData.Item.WOOD]:
		while not main.town.cargo_room(weight) and main.town.available(item) > 0:
			var before: int = main.town.credits
			if not city_action("sell", item, 1): break
			sales.append({"label": label, "item": item, "count": 1, "credits": main.town.credits - before})
	return main.town.cargo_room(weight)

## The market only buys physical, unreserved surplus.  A long paid loop must
## make enough room for its ordinary food refill before claiming that a city
## maintenance failure is an income failure.
func make_maintenance_food_room(label: String) -> bool:
	var required := maxi(0, int(maintenance_reference.food) - main.storage.count_of(GameData.Item.FOOD))
	for item in [GameData.Item.MEAT, GameData.Item.BONE, GameData.Item.FAT, GameData.Item.STONE, GameData.Item.IRON_ORE, GameData.Item.WOOD]:
		while main.storage.free_for(GameData.Item.FOOD) < required and main.town.available(item) > 0:
			var before: int = main.town.credits
			if not city_action("sell", item, 1): break
			sales.append({"label": label, "item": item, "count": 1, "credits": main.town.credits - before})
	return main.storage.free_for(GameData.Item.FOOD) >= required

func record_sortie(rows: Array, name: String, before: Dictionary, maintenance: Dictionary) -> void:
	var after: Dictionary = maintenance.after
	rows.append({"name": name, "elapsed_start_seconds": snappedf(float(before.elapsed_seconds) - case_started_elapsed, 0.01), "elapsed_end_seconds": snappedf(float(after.elapsed_seconds) - case_started_elapsed, 0.01), "credits_delta_before_maintenance": int(maintenance.before.credits) - int(before.credits), "maintenance_cash_cost": maintenance.cash_cost, "credits_delta_after_maintenance": int(after.credits) - int(before.credits), "fuel_consumed_net": snappedf(float(before.fuel) - float(after.fuel), 0.01), "food_consumed": int(after.eaten) - int(before.eaten), "repair_actions": int(after.repair_actions) - int(before.repair_actions), "asset_value_delta": int(after.tradable_asset_value) - int(before.tradable_asset_value), "maintenance": maintenance, "start": before, "end": after})

func checkpoint_fixture(economic_snapshot: Dictionary) -> Dictionary:
	const COPY_PATH := "user://economy-checkpoint-copy.json"
	var written := SaveGame.write(main, COPY_PATH, true, SaveGame.SLOT_CHECKPOINT)
	var credits: int = main.town.credits
	var bought := city_action("buy", GameData.Item.FOOD, 1) if credits >= TownDB.BUY[GameData.Item.FOOD] else false
	var restarted := SaveGame.restart_from_checkpoint(main, SaveGame.DEFAULT_RESTART_LOSS, COPY_PATH)
	var expected: int = credits - SaveGame.restart_loss(credits)
	check(written and restarted and main.town.credits == expected, "separate checkpoint copy applies its one restart loss")
	check(SaveGame.apply(main, economic_snapshot), "economic state is restored after separate checkpoint fixture")
	return {"copy_written": written, "purchased_after_copy": bought, "restart_credits": expected}

## Optional long normal-world observation used for balance investigation.  It
## changes no settings and records worker-state time rather than treating an
## idle/bed state as an unexplained aggregate wait.
func observe_normal_play(seconds: float) -> Dictionary:
	var start := snapshot()
	var state_seconds := {}
	var bed_busy_seconds := 0.0
	var rest_here_seconds := 0.0
	var hunger_below_eat_seconds := 0.0
	var hunger_below_urgent_seconds := 0.0
	var until: float = main.director.elapsed + seconds
	while main.director.elapsed < until and not main.game_over:
		for worker in main.workers:
			var state_name: String = CharacterAI.State.keys()[worker.ai.state]
			state_seconds[state_name] = snappedf(float(state_seconds.get(state_name, 0.0)) + STEP, 0.01)
			if worker.sleeping: bed_busy_seconds += STEP
			if worker.resting: rest_here_seconds += STEP
			if worker.hunger < CrewStatusDB.EAT_BELOW: hunger_below_eat_seconds += STEP
			if worker.hunger < CrewStatusDB.EAT_URGENT_BELOW: hunger_below_urgent_seconds += STEP
		await tick()
	var finish := snapshot()
	return {"requested_seconds": seconds, "elapsed_seconds": snappedf(float(finish.elapsed_seconds) - float(start.elapsed_seconds), 0.01), "start": start, "end": finish, "food_consumed": int(finish.eaten) - int(start.eaten), "food_inventory_delta": int(finish.food) - int(start.food), "state_seconds_by_worker": state_seconds, "bed_busy_worker_seconds": snappedf(bed_busy_seconds, 0.01), "rest_here_worker_seconds": snappedf(rest_here_seconds, 0.01), "hunger_below_eat_worker_seconds": snappedf(hunger_below_eat_seconds, 0.01), "hunger_below_urgent_worker_seconds": snappedf(hunger_below_urgent_seconds, 0.01), "built_beds": main.base.built.get("bed", []).size(), "game_over": main.game_over}

## City cash service cannot repair a part while a worker has already reserved
## that part for a normal repair-kit trip.  This is not an income wait: let the
## existing AI finish that owned trip, record it, then assess the same baseline.
func settle_maintenance_work(seconds := 60.0) -> Dictionary:
	var before := snapshot()
	var initial_repairs: Array = main.base.repair_reserved.keys().duplicate()
	var initial_refuel: bool = main.base.refuel_reserved
	var settled := await wait_for(func(): return main.base.repair_reserved.is_empty() and not main.base.refuel_reserved, seconds)
	return {"before": before, "after": snapshot(), "initial_repair_reservations": initial_repairs, "initial_refuel_reservation": initial_refuel, "settled": settled}


## Keep the fixed-leg assertion immediate, but prove separately that a repair
## already owned by a worker completes without an unbounded wait or duplicate
## automatic consumption before city service fills any remaining gap.
func eventual_reserved_maintenance(label: String) -> Dictionary:
	var reserved_parts: Array = main.base.repair_reserved.keys().duplicate()
	var before := snapshot()
	if reserved_parts.is_empty():
		return {"applicable": false, "label": label, "before": before}
	var wait_start: float = main.director.elapsed
	var settled: bool = await wait_for(func(): return main.base.repair_reserved.is_empty(), 60.0)
	var after_wait: Dictionary = snapshot()
	var automatic_repairs: int = int(after_wait.repair_actions) - int(before.repair_actions)
	var kit_delta: int = int(after_wait.repair_kits) - int(before.repair_kits)
	check(settled, label + " reserved repair completes within 60 seconds")
	check(automatic_repairs == reserved_parts.size(), label + " completes each initially reserved repair exactly once before further city service")
	check(kit_delta >= -automatic_repairs, label + " does not consume more repair kits than completed automatic repairs")
	# A long wait lets idle crew begin ordinary deck/field work. Reassemble before
	# asking the existing city service to top up any gap the 75%-threshold repair
	# correctly leaves; this does not interrupt the completed reservation.
	var prior_stance: String = main.operations.stance
	main.operations.set_stance("recall")
	var city_ready_after_wait := await city_ready()
	var completion := maintain_same_level()
	main.operations.set_stance(prior_stance)
	check(city_ready_after_wait, label + " can return to normal city service after the reserved repair")
	check(bool(completion.reached), label + " returns to the unchanged maintenance baseline after the reserved repair")
	assert_maintenance_state(label + " eventual return", completion.after)
	return {"applicable": true, "label": label, "reserved_parts": reserved_parts, "before": before, "wait_seconds": snappedf(main.director.elapsed - wait_start, 0.01), "settled": settled, "expected_automatic_repair_actions": reserved_parts.size(), "automatic_repair_actions": automatic_repairs, "repair_kit_delta_during_wait": kit_delta, "after_wait": after_wait, "city_ready_after_wait": city_ready_after_wait, "material_before": {"wood": int(before.inventory.get(GameData.Item.WOOD, 0)), "stone": int(before.inventory.get(GameData.Item.STONE, 0)), "iron": int(before.inventory.get(GameData.Item.IRON, 0))}, "material_after_wait": {"wood": int(after_wait.inventory.get(GameData.Item.WOOD, 0)), "stone": int(after_wait.inventory.get(GameData.Item.STONE, 0)), "iron": int(after_wait.inventory.get(GameData.Item.IRON, 0))}, "completion": completion}


## Repeats ordinary paid delivery work after the fixed three-sortie comparison.
## Unlike observe_normal_play, this keeps providing map/resource/reward income
## opportunities and records each maintenance purchase separately.
func run_repeat_deliveries(count: int) -> Array:
	var rows: Array = []
	for i in count:
		trace_phase = "repeat_delivery_%02d" % (i + 1)
		var entry := {"index": i + 1, "start": snapshot()}
		entry.maintenance_food_room = make_maintenance_food_room("repeat-maintenance-%d" % (i + 1))
		entry.pre_maintenance_settle = await settle_maintenance_work()
		var departure_maintenance := maintain_same_level()
		entry.departure_maintenance = departure_maintenance
		if not bool(departure_maintenance.reached):
			entry.blocker = "maintenance_before_departure"
			rows.append(entry)
			break
		check(make_cargo_room(TownDB.DELIVERY_PARCEL_WEIGHT, "repeat-delivery-%d" % (i + 1)), "repeat delivery %d makes normal parcel room" % (i + 1))
		if not city_action("accept_delivery"):
			entry.blocker = "accept_delivery"
			rows.append(entry)
			break
		var gathered_before: int = main.total_gathered
		if not await travel(TownDB.DELIVERY_TO, "repeat-delivery-%d-outbound" % (i + 1)):
			entry.blocker = "outbound_travel"
			rows.append(entry)
			break
		if not await wait_for(func(): return main.total_gathered > gathered_before, 180.0):
			entry.blocker = "normal_gather"
			rows.append(entry)
			break
		if not await travel("central_trade", "repeat-delivery-%d-return" % (i + 1)) or not await city_ready() or not city_action("claim_delivery"):
			entry.blocker = "return_or_claim"
			rows.append(entry)
			break
		queue_progression()
		var arrival_maintenance := maintain_same_level()
		entry.arrival_maintenance = arrival_maintenance
		entry.end = snapshot()
		entry.credits_delta_after_maintenance = int(entry.end.credits) - int(entry.start.credits)
		entry.food_consumed = int(entry.end.eaten) - int(entry.start.eaten)
		entry.repair_actions = int(entry.end.repair_actions) - int(entry.start.repair_actions)
		rows.append(entry)
	return rows

func run_case(crew_count: int) -> Dictionary:
	await boot(crew_count)
	legs.clear(); sales.clear(); maintenance_reference = {}; state_seconds_by_phase.clear(); trace_phase = "preparation"
	case_started_elapsed = main.director.elapsed
	var initial := snapshot()
	queue_progression()
	check(await wait_for(func(): return worker_has_tool(GameData.Item.HAMMER), 420.0), "normal starting-region AI completes the required hammer without a resource grant")
	queue_progression()
	check(await travel("central_trade", "preparation-access-town") and await city_ready(), "recorded preparation leg reaches town normally")
	maintenance_reference = snapshot()
	var first_maintenance := maintain_same_level()
	check(first_maintenance.reached, "initial town visit can establish the maintenance reference level")
	assert_maintenance_state("preparation return", first_maintenance.after)
	var prelude := {"start": initial, "town_reference": first_maintenance.after, "credits_delta": int(first_maintenance.after.credits) - int(initial.credits), "food_consumed": int(first_maintenance.after.eaten) - int(initial.eaten), "elapsed_seconds": snappedf(float(first_maintenance.after.elapsed_seconds) - case_started_elapsed, 0.01), "legs": legs.duplicate(true)}
	var sorties: Array = []
	var eventual_maintenance: Array = []

	trace_phase = "sortie_1_delivery"
	var before := snapshot()
	assert_maintenance_state("sortie 1 departure", before)
	check(make_cargo_room(TownDB.DELIVERY_PARCEL_WEIGHT, "delivery"), "normal town inventory makes room for delivery parcel")
	check(city_action("accept_delivery"), "sortie 1 accepts normal delivery")
	check(await travel(TownDB.DELIVERY_TO, "sortie-1-delivery-outbound"), "sortie 1 reaches its delivery destination")
	var gathered_before: int = main.total_gathered
	check(await wait_for(func(): return main.total_gathered > gathered_before, 180.0), "sortie 1 uses normal gathering AI")
	check(await travel("central_trade", "sortie-1-delivery-return") and await city_ready() and city_action("claim_delivery"), "sortie 1 returns and claims reward")
	queue_progression()
	var maintenance := maintain_same_level()
	check(maintenance.reached, "sortie 1 returns to the common maintenance level")
	assert_maintenance_state("sortie 1 return", maintenance.after)
	record_sortie(sorties, "delivery", before, maintenance)
	if eventual_maintenance_probe and not bool(maintenance.reached): eventual_maintenance.append(await eventual_reserved_maintenance("sortie 1 return"))

	trace_phase = "sortie_2_supply"
	before = snapshot()
	assert_maintenance_state("sortie 2 departure", before)
	check(city_action("accept_supply", GameData.Item.WOOD), "sortie 2 accepts normal supply")
	gathered_before = main.total_gathered
	check(await travel("south_oasis", "sortie-2-supply-outbound"), "sortie 2 reaches normal supply region")
	check(await wait_for(func(): return main.total_gathered > gathered_before and main.storage.count_of(GameData.Item.WOOD) >= TownDB.SUPPLY_OFFERS[GameData.Item.WOOD].count and main.storage.count_of(GameData.Item.IRON_ORE) >= 1, 240.0), "sortie 2 gathers its requested material and early-upgrade ore without a grant")
	check(await travel("central_trade", "sortie-2-supply-return") and await city_ready() and city_action("claim_supply"), "sortie 2 returns and claims reward")
	queue_progression()
	var first_improvement_wait := await wait_for_first_improvement(240.0)
	check(bool(first_improvement_wait.done), "first hauling or storage improvement is crafted by two claimed sorties")
	queue_progression()
	check(first_improvement(), "first hauling or storage improvement is equipped or installed through normal crew action")
	var first_improvement_elapsed := snappedf(main.director.elapsed - case_started_elapsed, 0.01)
	check(await city_ready(), "early-upgrade work returns the crew to normal city actions")
	maintenance = maintain_same_level()
	check(maintenance.reached, "sortie 2 returns to the common maintenance level")
	assert_maintenance_state("sortie 2 return", maintenance.after)
	record_sortie(sorties, "supply", before, maintenance)
	if eventual_maintenance_probe and not bool(maintenance.reached): eventual_maintenance.append(await eventual_reserved_maintenance("sortie 2 return"))

	trace_phase = "sortie_3_recovery"
	before = snapshot()
	assert_maintenance_state("sortie 3 departure", before)
	check(make_cargo_room(TownDB.RECOVERY_PARCEL_WEIGHT, "recovery"), "normal town inventory makes room for recovery parcel")
	check(city_action("accept_recovery"), "sortie 3 accepts normal recovery")
	var old_gather: Dictionary = main.gather_policy.duplicate(true)
	var old_hunt: Dictionary = main.hunt_policy.duplicate(true)
	for item in [GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE]: main.gather_policy[item] = 0
	for species in main.hunt_policy: main.hunt_policy[species] = false
	main.operations.set_stance("alert")
	check(await travel(TownDB.RECOVERY_TO, "sortie-3-recovery-outbound"), "sortie 3 reaches recovery destination")
	main.operations.set_stance("normal")
	check(main.town.recovery in ["site", "loading", "carried", "return", "ready"], "recovery enters normal field state")
	check(SaveGame.write_progress(main, true) and SaveGame.continue_progress(main, SaveGame.read_progress()), "mid-sortie progress save and Continue restore")
	check(await wait_for(func(): return main.town.recovery == "return", 420.0), "sortie 3 uses normal AI recovery handling")
	main.gather_policy = old_gather
	main.hunt_policy = old_hunt
	check(await travel("central_trade", "sortie-3-recovery-return") and await city_ready() and city_action("claim_recovery"), "sortie 3 returns and claims reward")
	maintenance = maintain_same_level()
	check(maintenance.reached, "sortie 3 returns to the common maintenance level")
	assert_maintenance_state("sortie 3 return", maintenance.after)
	record_sortie(sorties, "recovery", before, maintenance)
	if eventual_maintenance_probe and not bool(maintenance.reached): eventual_maintenance.append(await eventual_reserved_maintenance("sortie 3 return"))

	var economic_final := snapshot()
	var repeated: Array = []
	if repeat_delivery_count > 0:
		repeated = await run_repeat_deliveries(repeat_delivery_count)
		check(main.total_eaten - int(economic_final.eaten) >= 2, "repeated paid deliveries include multiple real meals")
	var checkpoint := checkpoint_fixture(SaveGame.capture(main))
	var observation := {}
	if observation_seconds > 0.0:
		trace_phase = "post_sortie_no_income_observation"
		observation = await observe_normal_play(observation_seconds)
	if observation_seconds > 0.0:
		check(int(observation.food_consumed) >= 2, "extended normal observation includes multiple real meals")
	var result := {"seed": seed_value, "crew_count": crew_count, "preparation": prelude, "elapsed_seconds_to_first_improvement": first_improvement_elapsed, "first_improvement_wait": first_improvement_wait, "elapsed_seconds_total": snappedf(main.director.elapsed - case_started_elapsed, 0.01), "travel_legs": legs, "sorties": sorties, "eventual_reserved_maintenance": eventual_maintenance, "repeat_deliveries": repeated, "city_sales": sales, "initial": initial, "economic_final": economic_final, "first_improvement": economic_final.upgrades, "checkpoint_fixture_separate": checkpoint, "post_sortie_observation": observation, "state_seconds_by_phase": state_seconds_by_phase}
	print("SORTIE_ECONOMY_JSON " + JSON.stringify(result))
	var completed_repeats := 0
	for row in repeated:
		if row.has("end"):
			completed_repeats += 1
	check(legs.size() == 7 + completed_repeats * 2, "all preparation, fixed sorties, and every completed repeated paid-delivery map leg are recorded with no hidden trips")
	check(sorties.size() == 3 and sorties.all(func(row): return row.maintenance.reached), "all three sorties include complete return-to-target maintenance accounting")
	check(not main.game_over and economic_final.credits > int(first_maintenance.after.credits) and entity_ids_unique(), "three claimed sorties retain positive cash above the common maintenance reference without duplicate living entities")
	return result

func _initialize() -> void:
	var crew_count := 4
	var args := OS.get_cmdline_user_args()
	var index := args.find("--crew-count")
	if index >= 0 and index + 1 < args.size(): crew_count = int(args[index + 1])
	index = args.find("--seed")
	if index >= 0 and index + 1 < args.size(): seed_value = int(args[index + 1])
	index = args.find("--observe-seconds")
	if index >= 0 and index + 1 < args.size(): observation_seconds = maxf(0.0, float(args[index + 1]))
	index = args.find("--repeat-deliveries")
	if index >= 0 and index + 1 < args.size(): repeat_delivery_count = maxi(0, int(args[index + 1]))
	eventual_maintenance_probe = args.has("--eventual-maintenance-probe")
	check(crew_count in [4, 5], "selected crew count is supported")
	if crew_count not in [4, 5]:
		print("== RESULT: %d FAILED ==" % fails)
		quit(1)
		return
	await run_case(crew_count)
	print("== RESULT: %s ==" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
