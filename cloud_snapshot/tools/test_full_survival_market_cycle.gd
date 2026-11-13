extends SceneTree
## Deterministic full survival/economy witness (not normal mouse input).
## Hunting is in the stopped horizontal B region, NOT the C quarter-view.
## Save disabled; no currency, meat, carcass, or resource injection.
##
## The resource sold below originates in a real C-quarry RouteSession. This
## test does not seed currency or inventory and never writes a player save.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.2
const HARVEST_SECONDS := 240.0

var main
var failures := 0
var ledger: Array = []
var simulation_seconds := 0.0
var quarterview_seconds := 0.0
var observed_meal_hunger_gain := false
var observed_carcass_cargo := false
var observed_meat_stock := false
var observed_food_output := false

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _fresh() -> bool:
	_free_main()
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 60.0
	main.refill_settings = {} # player-controlled automatic recipe requests disabled until meat is stocked
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	for worker in main.workers:
		worker.stop_work()
		worker.set_priority(GameData.Job.GATHER, 0)
	return main.world.region == "a_start" and main.world.phase == "stopped"

func _free_main() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null

func _world_step() -> void:
	main._process(STEP)
	for creature in main.creatures_root.get_children():
		if is_instance_valid(creature) and not creature.is_queued_for_deletion():
			creature._process(STEP)
	for worker in main.workers:
		var hunger_before: float = worker.hunger
		var meals_before: int = main.total_eaten
		worker._process(STEP)
		if main.total_eaten > meals_before and worker.hunger > hunger_before:
			observed_meal_hunger_gain = true
		if worker.carrying == GameData.Item.CARCASS and int(worker.carcass_cargo.get(GameData.Item.MEAT, 0)) > 0:
			observed_carcass_cargo = true
	observed_meat_stock = observed_meat_stock or main.storage.count_of(GameData.Item.MEAT) > 0
	observed_food_output = observed_food_output or GameData.Item.FOOD in main.processor.all_output()
	simulation_seconds += STEP

func _snapshot(stage: String) -> void:
	var hunger: Array = []
	for worker in main.workers: hunger.append(snappedf(worker.hunger, 0.01))
	var row := {"stage": stage, "seconds": snappedf(simulation_seconds, 0.01), "region": main.world.region,
		"quarterview_seconds": snappedf(quarterview_seconds, 0.01),
		"phase": main.world.phase, "credits": main.town.credits, "fuel": snappedf(main.base.fuel, 0.01),
		"meat": main.storage.count_of(GameData.Item.MEAT), "food": main.storage.count_of(GameData.Item.FOOD),
		"iron_ore": main.storage.count_of(GameData.Item.IRON_ORE), "hunted": main.total_hunted,
		"eaten": main.total_eaten, "hunger": hunger, "carcass_cargo_seen": observed_carcass_cargo,
		"meat_stock_seen": observed_meat_stock, "food_output_seen": observed_food_output,
		"meal_hunger_gain_seen": observed_meal_hunger_gain}
	ledger.append(row)
	print("LEDGER " + JSON.stringify(row))

func _wait_until(predicate: Callable, seconds: float) -> bool:
	for frame in ceili(seconds / STEP):
		_world_step()
		if predicate.call(): return true
		if frame % 120 == 0: await process_frame
	return bool(predicate.call())

func _hunt_cook_eat() -> Dictionary:
	_snapshot("normal_initial_state")
	if not await _move_leg("b_forest"):
		return {"ok": false, "reason": "A -> B travel failed"}
	_snapshot("arrive_B_stopped_horizontal")
	if not main.request_hunt("dodo", 1):
		return {"ok": false, "reason": "explicit dodo request rejected"}
	if not await _wait_until(func(): return main.total_hunted == 1 and main.storage.count_of(GameData.Item.MEAT) >= 1, 600.0):
		_snapshot("hunt_failed")
		return {"ok": false, "reason": "explicit hunt did not deliver meat to base storage"}
	_snapshot("hunted_and_meat_stored")
	if not observed_carcass_cargo:
		return {"ok": false, "reason": "meat arrived without observed carcass cargo path"}
	var food_before: int = main.storage.count_of(GameData.Item.FOOD)
	var eaten_before: int = main.total_eaten
	main.refill_settings = {GameData.Item.FOOD:{"enabled":true,"target":12}}
	if not await _wait_until(func(): return main.storage.count_of(GameData.Item.MEAT) == 0 and (main.storage.count_of(GameData.Item.FOOD) + main.total_eaten - eaten_before) >= food_before + 2, 600.0):
		_snapshot("cook_failed")
		return {"ok": false, "reason": "stored meat did not become two cooked-food units"}
	_snapshot("cooked_food_stored")
	var meals_before: int = main.total_eaten
	if not await _wait_until(func(): return main.total_eaten > meals_before, 1200.0):
		return {"ok": false, "reason": "no normal hunger-driven meal completed"}
	_snapshot("normal_meal_consumed")
	main.refill_settings = {}
	return {"ok": true}

func _move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for frame in 1200:
		_world_step()
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
		if frame % 24 == 0:
			await process_frame
	return main.world.phase == "stopped" and main.world.region == destination

func _move_to_quarry() -> bool:
	if main.world.region == "a_start" and not await _move_leg("b_forest"):
		return false
	if main.world.region == "b_forest":
		return await _move_leg("c_quarry")
	return main.world.region == "c_quarry" and main.world.phase == "stopped"

func _move_to_start() -> bool:
	if main.world.region == "c_quarry" and not await _move_leg("b_forest"):
		return false
	if main.world.region == "b_forest":
		return await _move_leg("a_start")
	return main.world.region == "a_start" and main.world.phase == "stopped"

func _advance_session(session, predicate: Callable, seconds: float) -> Dictionary:
	var conservation_ok := true
	for frame in ceili(seconds / STEP):
		session.tick(STEP)
		quarterview_seconds += STEP
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return {"ok": false, "reason": str(projection.get("reason", "projection failed")), "conservation_ok": false}
		conservation_ok = conservation_ok and session.conservation_ok()
		if predicate.call():
			return {"ok": true, "conservation_ok": conservation_ok}
		if frame % 48 == 0:
			await process_frame
	return {"ok": bool(predicate.call()), "conservation_ok": conservation_ok}

func _open_market() -> bool:
	main.town_ui.request_open()
	if not main.town_ui.is_open():
		return false
	main.town_ui.show_building_intro("market")
	if main.town_ui.building_id() != "market":
		return false
	main.town_ui.enter_building()
	return main.town_ui.is_open() and main.town_ui.building_id().is_empty()

func _run_cycle() -> Dictionary:
	if not await _fresh():
		return {"ok": false, "reason": "fresh first-region state was unavailable"}
	var survival: Dictionary = await _hunt_cook_eat()
	if not bool(survival.get("ok", false)): return survival
	if not await _move_to_quarry():
		return {"ok": false, "reason": "could not travel A -> B -> C"}
	_snapshot("arrive_C_before_quarterview_session")
	var created: Dictionary = RouteSession.create_from_game(main, "recovery-town-market", {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		return {"ok": false, "reason": str(created.get("reason", "could not start quarry session"))}
	var session = created.session
	var harvested: Dictionary = await _advance_session(session, func():
		return int(session.depot_stock.get(GameData.Item.IRON_ORE, 0)) >= 2,
		HARVEST_SECONDS)
	if not bool(harvested.get("ok", false)):
		return {"ok": false, "reason": "quarry did not deliver two iron ore", "summary": session.state_summary()}
	var depot_ore := int(session.depot_stock.get(GameData.Item.IRON_ORE, 0))
	session.request_recall()
	var recalled: Dictionary = await _advance_session(session, func(): return session.phase == "ready_to_exit", 100.0)
	if not bool(recalled.get("ok", false)):
		return {"ok": false, "reason": "quarry crew did not return", "summary": session.state_summary()}
	var ore_before_commit: int = main.storage.count_of(GameData.Item.IRON_ORE)
	var committed: Dictionary = session.commit_to_game(main)
	var repeated_commit: Dictionary = session.commit_to_game(main)
	if not bool(committed.get("ok", false)) or not bool(repeated_commit.get("already_committed", false)):
		return {"ok": false, "reason": "quarry commit was not idempotent"}
	var ore_after_commit: int = main.storage.count_of(GameData.Item.IRON_ORE)
	if ore_after_commit != ore_before_commit + depot_ore:
		return {"ok": false, "reason": "quarry ore did not reach base storage exactly once"}
	_snapshot("C_ore_committed_once")
	if not await _move_to_start() or not main.town.location_ok():
		return {"ok": false, "reason": "could not return C -> B -> A town"}
	if not _open_market():
		return {"ok": false, "reason": "normal town street -> market entry failed"}
	_snapshot("A_town_market")
	var credits_before := int(main.town.credits)
	var ore_before_sale: int = main.storage.count_of(GameData.Item.IRON_ORE)
	main.town_ui.preview("sell", GameData.Item.IRON_ORE)
	main.town_ui.show_street()
	if int(main.town.credits) != credits_before or main.storage.count_of(GameData.Item.IRON_ORE) != ore_before_sale:
		return {"ok": false, "reason": "cancelled market preview changed recovered ore or credits"}
	if not _open_market():
		return {"ok": false, "reason": "could not return from cancelled market preview"}
	var ticket: Dictionary = main.town.quote("sell", GameData.Item.IRON_ORE, 1)
	if not bool(ticket.get("ok", false)):
		return {"ok": false, "reason": "valid recovered-ore ticket could not be created"}
	if not main.town.execute(ticket):
		return {"ok": false, "reason": "valid recovered-ore ticket was not executable"}
	if main.town.execute(ticket):
		return {"ok": false, "reason": "same recovered-ore ticket executed twice"}
	if int(main.town.credits) != credits_before + 3 or main.storage.count_of(GameData.Item.IRON_ORE) != ore_before_sale - 1:
		return {"ok": false, "reason": "ticket duplicate changed recovered ore or credits"}
	main.town_ui.preview("sell", GameData.Item.IRON_ORE)
	main.town_ui.confirm()
	var credits_after_sale := int(main.town.credits)
	var ore_after_sale: int = main.storage.count_of(GameData.Item.IRON_ORE)
	if credits_after_sale != credits_before + 6 or ore_after_sale != ore_before_sale - 2:
		return {"ok": false, "reason": "two market sells did not exchange exactly two recovered ore for six credits"}
	var food_before: int = main.storage.count_of(GameData.Item.FOOD)
	main.town_ui.preview("buy", GameData.Item.FOOD)
	main.town_ui.confirm()
	var credits_after_buy := int(main.town.credits)
	var food_after_buy: int = main.storage.count_of(GameData.Item.FOOD)
	if credits_after_buy != credits_after_sale - 4 or food_after_buy != food_before + 1:
		return {"ok": false, "reason": "market purchase did not debit credits and store food exactly once"}
	main.town_ui.preview("buy", GameData.Item.FUEL)
	main.town_ui.confirm()
	if int(main.town.credits) != credits_after_buy or main.storage.count_of(GameData.Item.FOOD) != food_after_buy:
		return {"ok": false, "reason": "insufficient-credit UI confirmation changed stock or credits"}
	var insufficient: Dictionary = main.town.quote("buy", GameData.Item.FUEL, 1)
	if bool(insufficient.get("ok", false)):
		return {"ok": false, "reason": "insufficient-credit purchase was incorrectly quoted"}
	_snapshot("sale_purchase_complete")
	main.town_ui.close()
	if not await _move_leg("b_forest"):
		return {"ok": false, "reason": "redeparture after purchase failed"}
	_snapshot("next_departure_arrived_B")
	if main.total_hunted != 1 or not observed_meat_stock or not observed_food_output or not observed_meal_hunger_gain:
		return {"ok": false, "reason": "hunting/cooking/meal evidence incomplete or extra unrequested hunt"}
	if main.storage.count_of(GameData.Item.FOOD) + main.total_eaten != 11:
		return {"ok": false, "reason": "food conservation failed: initial 8 + cooked 2 + purchased 1 must equal stored + eaten"}
	return {"ok": bool(harvested.get("conservation_ok", false)) and bool(recalled.get("conservation_ok", false)), "depot_ore": depot_ore, "credits": int(main.town.credits), "food": main.storage.count_of(GameData.Item.FOOD)}

func _run() -> void:
	var result: Dictionary = await _run_cycle()
	_check(bool(result.get("ok", false)), "stopped-horizontal hunt, meat haul, cooking, meal, quarry recovery, town market, and next departure complete")
	if not bool(result.get("ok", false)):
		print("  reason: %s" % str(result.get("reason", "unknown")))
	else:
		print("  recovered iron: %d / remaining credits: %d / food: %d" % [int(result.get("depot_ore", 0)), int(result.get("credits", 0)), int(result.get("food", 0))])
	print("WITNESS_SCOPE stopped horizontal B hunting; C quarter-view mineral recovery; deterministic system/API input, not GUI mouse input")
	if main != null and main.town_ui != null:
		main.town_ui.close()
	_free_main()
	SaveGame.disabled = false
	print("== full survival market cycle: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
