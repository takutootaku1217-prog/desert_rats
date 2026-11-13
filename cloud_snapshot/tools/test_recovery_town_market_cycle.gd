extends SceneTree
## End-to-end recovery -> first town -> market contract.
##
## The resource sold below originates in a real C-quarry RouteSession. This
## test does not seed currency or inventory and never writes a player save.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.2
const HARVEST_SECONDS := 240.0

var main
var failures := 0

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
	main.refill_settings = {}
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.set_priority(job, 0)
	return main.world.region == "a_start" and main.world.phase == "stopped"

func _free_main() -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null

func _world_step() -> void:
	main._process(STEP)

func _move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for frame in 240:
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
	if not await _move_to_quarry():
		return {"ok": false, "reason": "could not travel A -> B -> C"}
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
	if not await _move_to_start() or not main.town.location_ok():
		return {"ok": false, "reason": "could not return C -> B -> A town"}
	if not _open_market():
		return {"ok": false, "reason": "normal town street -> market entry failed"}
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
	return {"ok": bool(harvested.get("conservation_ok", false)) and bool(recalled.get("conservation_ok", false)), "depot_ore": depot_ore, "credits": int(main.town.credits), "food": main.storage.count_of(GameData.Item.FOOD)}

func _run() -> void:
	var result: Dictionary = await _run_cycle()
	_check(bool(result.get("ok", false)), "real quarry recovery, return, town market sale, food purchase, and ticket guards complete")
	if not bool(result.get("ok", false)):
		print("  reason: %s" % str(result.get("reason", "unknown")))
	else:
		print("  recovered iron: %d / remaining credits: %d / food: %d" % [int(result.get("depot_ore", 0)), int(result.get("credits", 0)), int(result.get("food", 0))])
	if main != null and main.town_ui != null:
		main.town_ui.close()
	_free_main()
	SaveGame.disabled = false
	print("== recovery town market cycle: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
