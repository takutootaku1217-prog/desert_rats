extends SceneTree
## TDD coverage for the C-quarry route-engineering verification.  It uses real
## Main/WorldTrip/RecoveryRouteConnectionSession state and never writes saves.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.25

var main
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _fresh()
	var backpack = await _make_session("mine-path-backpack", {})
	_check(backpack != null, "C quarry session starts from the fixed entrance")
	if backpack != null:
		_check(backpack.has_method("is_mine_path_engineering"), "Session exposes the narrow mine-path capability")
		if backpack.has_method("is_mine_path_engineering"):
			_check(not bool(backpack.call("is_mine_path_engineering")), "Existing non-engineering sessions remain unchanged")
	_free_main()

	# A downed escort cannot advance a rubble job or a later recall. Refuse the
	# field entry before the bridge owns this otherwise unrecoverable state.
	await _fresh()
	main.workers[2].down = true
	var reached_down := await _move_leg("b_forest") and await _move_leg("c_quarry")
	var denied_down: Dictionary = RouteSession.create_from_game(main, "mine-path-downed-escort", {"mine_path_engineering": true}) if reached_down else {}
	_check(reached_down and not bool(denied_down.get("ok", false)), "A downed escort blocks mine-path entry instead of starting frozen rubble work")
	_free_main()

	await _fresh()
	main.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
	_check(main.equip_work_support(main.workers[0], GameData.Item.HANDCART), "Fixture equips the harvest worker with an existing handcart")
	var cart = await _make_session("mine-path-cart", {"mine_path_engineering": true, "cart_shortcut_cleared": false})
	_check(cart != null, "Engineering session opens at C without moving the base")
	if cart != null:
		_check(cart.has_method("is_mine_path_engineering") and bool(cart.call("is_mine_path_engineering")), "Engineering is an explicit normal-C capability")
		_check(str(Dictionary(cart.actors.get("worker:0", {})).get("route", "")) == "cart_detour", "Blocked handcart uses the wide detour rather than the step shortcut")
		_check(cart.parking_anchor() == RouteSession.BASE, "Engineering keeps the mobile base at its entrance anchor")
	_free_main()

	var detour_delivery := await _measure_first_cart_delivery(false)
	var shortcut_delivery := await _measure_first_cart_delivery(true)
	_check(bool(detour_delivery.get("ok", false)) and bool(shortcut_delivery.get("ok", false)), "Both blocked and cleared cart fixtures complete a real first depot delivery")
	if bool(detour_delivery.get("ok", false)) and bool(shortcut_delivery.get("ok", false)):
		print("MINE PATH DELIVERY COMPARISON ", JSON.stringify({"blocked": detour_delivery, "cleared": shortcut_delivery, "method": "same C fixture, actual first depot increase"}))
		_check(str(detour_delivery.get("route", "")) == "cart_detour" and str(shortcut_delivery.get("route", "")) == "cart_shortcut", "Cart delivery selects detour before clearance and shortcut after clearance")
		_check(int(detour_delivery.get("deliveries", 0)) == 1 and int(shortcut_delivery.get("deliveries", 0)) == 1 and int(detour_delivery.get("depot", 0)) == int(shortcut_delivery.get("depot", 0)), "Comparison uses one equal-size deposited delivery rather than inferred capacity")
		_check(float(detour_delivery.get("elapsed", 0.0)) - float(shortcut_delivery.get("elapsed", INF)) >= 2.0, "Cleared cart shortcut saves at least two seconds on the same first-delivery fixture")
	_free_main()

	await _fresh()
	var clearance = await _make_session("mine-path-clear", {"mine_path_engineering": true})
	_check(clearance != null, "Clearance fixture opens a normal engineering session")
	if clearance != null:
		_check(clearance.has_method("request_mine_path_clearance"), "Session exposes an explicit rubble-clear command")
		_check(clearance.has_method("cancel_mine_path_clearance"), "Session exposes a worker-specific clearance cancel command")
		if clearance.has_method("request_mine_path_clearance"):
			var ordered: Dictionary = clearance.call("request_mine_path_clearance")
			_check(bool(ordered.get("ok", false)) and str(clearance.intermediate_access) == "clearing" and str(clearance.maintenance_actor_id) == "worker:2", "Only an explicit order starts escort rubble work")
			var parallel_progress := await _advance_until(clearance, func():
				var harvest: Dictionary = clearance.actors.get("worker:0", {})
				var carry: Dictionary = clearance.actors.get("worker:1", {})
				return str(harvest.get("state", "")) in ["harvesting", "to_relay"] and str(carry.get("state", "")) == "wait_relay"
			, 4.5)
			_check(parallel_progress and str(clearance.intermediate_access) == "clearing", "Mining and carrier travel progress while another worker clears rubble")
			var snapshot: Dictionary = clearance.to_dict()
			var restored: Dictionary = RouteSession.from_dict(snapshot)
			_check(bool(restored.get("ok", false)) and bool(restored.get("session", null).call("is_mine_path_engineering")) and str(restored.get("session", null).intermediate_access) == "clearing", "An in-progress rubble job restores without becoming cleared")
			var downed_snapshot := snapshot.duplicate(true)
			downed_snapshot.actors["worker:2"]["down"] = true
			var downed_restore: Dictionary = RouteSession.from_dict(downed_snapshot)
			_check(not bool(downed_restore.get("ok", false)), "A downed maintenance snapshot is rejected instead of restoring a recall soft-lock")
			if clearance.has_method("cancel_mine_path_clearance"):
				var cancelled: Dictionary = clearance.call("cancel_mine_path_clearance")
				var escort: Dictionary = clearance.actors.get("worker:2", {})
				_check(bool(cancelled.get("ok", false)) and str(clearance.intermediate_access) == "blocked" and str(clearance.maintenance_actor_id).is_empty() and str(escort.get("state", "")) == "escort" and clearance.conservation_ok(), "Cancellation restores only the maintenance worker and leaves rubble blocked")
				var reordered: Dictionary = clearance.call("request_mine_path_clearance")
				var duplicate: Dictionary = clearance.call("request_mine_path_clearance")
				_check(bool(reordered.get("ok", false)) and not bool(duplicate.get("ok", false)) and str(clearance.maintenance_actor_id) == "worker:2", "A duplicate rubble order does not assign a second worker")
				var working := await _advance_until(clearance, func(): return str(Dictionary(clearance.actors.get("worker:2", {})).get("state", "")) == "maintenance_work", 16.0)
				clearance.request_recall()
				var recall_ready := await _advance_until(clearance, func(): return str(clearance.phase) == "ready_to_exit", 180.0)
				_check(working and str(clearance.intermediate_access) == "blocked" and str(clearance.maintenance_actor_id).is_empty() and recall_ready and clearance.conservation_ok(), "Recall cancels mid-clearance without orphaning work or cargo")
	_free_main()

	await _fresh()
	var durable = await _make_session("mine-path-durable", {"mine_path_engineering": true})
	_check(durable != null, "Durable-clearance fixture opens a normal engineering session")
	if durable != null:
		var ordered: Dictionary = durable.call("request_mine_path_clearance")
		var cleared := await _advance_until(durable, func(): return str(durable.intermediate_access) == "cleared", 30.0)
		_check(bool(ordered.get("ok", false)) and cleared, "Rubble work completes without moving the fixed base")
		durable.request_recall()
		var ready := await _advance_until(durable, func(): return str(durable.phase) == "ready_to_exit", 180.0)
		var committed: Dictionary = durable.commit_to_game(main)
		_check(ready and bool(committed.get("ok", false)), "Cleared route commits only after normal field return")
		_check(main.world.has_method("c_quarry_cart_shortcut_cleared"), "WorldTrip exposes a C-only durable cart-shortcut flag")
		if main.world.has_method("c_quarry_cart_shortcut_cleared"):
			_check(bool(main.world.call("c_quarry_cart_shortcut_cleared")), "Committed rubble clearance persists in WorldTrip")
			var source_after_commit: Dictionary = Dictionary(main.world.locations.get("region:c_quarry", {})).duplicate(true)
			var source_resource_signature: Array = _resource_ledger_signature(source_after_commit)
			var snapshot: Dictionary = SaveGame.capture(main)
			_check(not snapshot.is_empty(), "Normal SaveGame captures the cleared route state")
			var restarted = load("res://scenes/main.tscn").instantiate()
			restarted.set("first_region_a_pilot", true)
			restarted.set_meta("diagnostic_seed", 104729)
			root.add_child(restarted)
			await process_frame
			restarted.process_mode = Node.PROCESS_MODE_DISABLED
			var reloaded := SaveGame.apply(restarted, snapshot.duplicate(true))
			_check(reloaded and restarted.world.has_method("c_quarry_cart_shortcut_cleared") and bool(restarted.world.call("c_quarry_cart_shortcut_cleared")), "Normal SaveGame reload preserves the cleared C cart shortcut")
			if reloaded:
				restarted.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
				_check(restarted.equip_work_support(restarted.workers[1], GameData.Item.HANDCART), "Reload fixture equips the existing handcart carrier")
				var restored: Dictionary = RouteSession.create_from_game(restarted, "mine-path-reload", {"mine_path_engineering": true, "cart_shortcut_cleared": bool(restarted.world.call("c_quarry_cart_shortcut_cleared"))})
				var restored_carry: Dictionary = Dictionary(restored.get("session", null).actors.get("worker:1", {})) if bool(restored.get("ok", false)) else {}
				_check(bool(restored.get("ok", false)) and str(restored_carry.get("route", "")) == "cart_shortcut", "Reloaded clearance selects the cart shortcut on the next C session")
			root.remove_child(restarted)
			restarted.free()
			var leave := await _move_leg("b_forest")
			var revisit := await _move_leg("c_quarry")
			_check(leave and revisit and bool(main.world.call("c_quarry_cart_shortcut_cleared")), "Leaving and revisiting C keeps the cleared cart route")
			# Re-entry is allowed to add return_at to creatures that leave the camera.
			# Engineering must not reseed or mutate finite gather/resource ledger rows.
			_check(_resource_ledger_signature(Dictionary(main.world.locations.get("region:c_quarry", {}))) == source_resource_signature, "Route clearance preserves source identities and amounts after accounting for ordinary regeneration")
	_free_main()
	await _normal_capacity_return()
	await _zero_cargo_overweight()
	_free_main()
	print("MINE PATH CLEARANCE failures=", fails)
	quit(1 if fails else 0)

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _fresh() -> void:
	_free_main()
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	main.director.enabled = false
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.priorities[job] = 0

func _free_main() -> void:
	if main != null and is_instance_valid(main):
		root.remove_child(main)
		main.free()
	main = null

func _step_world() -> void:
	main._process(STEP)
	await process_frame

func _move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 320:
		await _step_world()
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return main.world.phase == "stopped" and main.world.region == destination

func _make_session(tag: String, options: Dictionary):
	if main.world.region == "a_start" and not await _move_leg("b_forest"):
		_check(false, tag + ": A to B travel")
		return null
	if main.world.region == "b_forest" and not await _move_leg("c_quarry"):
		_check(false, tag + ": B to C travel")
		return null
	var made: Dictionary = RouteSession.create_from_game(main, tag, options)
	_check(bool(made.get("ok", false)), tag + ": real C session creation")
	return made.get("session", null)

func _advance_until(session, predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		session.tick(STEP)
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return false
		if predicate.call():
			return true
	return predicate.call()

func _measure_first_cart_delivery(cleared: bool) -> Dictionary:
	await _fresh()
	main.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
	if not main.equip_work_support(main.workers[1], GameData.Item.HANDCART):
		return {"ok": false, "reason": "handcart equip failed"}
	if not await _move_leg("b_forest") or not await _move_leg("c_quarry"):
		return {"ok": false, "reason": "C travel failed"}
	var created: Dictionary = RouteSession.create_from_game(main, "mine-path-delivery-" + ("open" if cleared else "blocked"), {"mine_path_engineering": true, "cart_shortcut_cleared": cleared})
	if not bool(created.get("ok", false)):
		return {"ok": false, "reason": str(created.get("reason", "session failed"))}
	var session = created.session
	var prior_depot := int(session.state_summary().get("depot", 0))
	var deliveries := 0
	for unused in 800:
		session.tick(STEP)
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return {"ok": false, "reason": str(projection.get("reason", "projection failed"))}
		var depot := int(session.state_summary().get("depot", 0))
		if depot > prior_depot:
			deliveries += 1
			return {"ok": true, "elapsed": session.elapsed, "depot": depot, "deliveries": deliveries, "route": str(Dictionary(session.actors.get("worker:1", {})).get("route", ""))}
		prior_depot = depot
	return {"ok": false, "reason": "first depot delivery timed out", "elapsed": session.elapsed, "route": str(Dictionary(session.actors.get("worker:1", {})).get("route", ""))}

func _resource_ledger_signature(location: Dictionary) -> Array:
	var ids: Array = location.keys()
	ids.sort()
	var signature: Array = []
	for id in ids:
		var row: Dictionary = Dictionary(location[id])
		if str(row.get("type", "")) not in ["gather", "resource"]:
			continue
		var stable:Dictionary=row.duplicate(true)
		if stable.has("regeneration"):
			# Separate ground growth from engineering/reseed. The unchanged
			# source identity/capacity and remaining-minus-growth stay exact.
			stable.data.remaining-=int(stable.regeneration.revision)
			stable.regeneration.erase("last")
			stable.regeneration.erase("credit")
			stable.regeneration.erase("revision")
			stable.spent=false
		signature.append({"id": str(id), "row": stable})
	return signature

func _normal_capacity_return() -> void:
	await _fresh()
	_check(await _move_leg("b_forest") and await _move_leg("c_quarry"), "Capacity fixture reaches normal C")
	var room: int = main.storage.max_weight() - main.storage.current_weight() - main.storage.processing_reserve()
	main.storage.store_owned(GameData.Item.FOOD, room - 8, Inventory.SOURCE_TRANSFER)
	var made: Dictionary = RouteSession.create_from_game(main, "mine-capacity", {"mine_path_engineering": true})
	_check(made.ok, "Normal capacity session starts at352/360")
	if not made.ok: return
	var s = made.session
	_check(s.field_capacity_limit_weight == 8, "Normal C captures real eight-weight collection allowance")
	var actor: Dictionary = s.actors["worker:0"]
	actor.carry_limit = 4
	var rid: String = s._reserve_resource("worker:0")
	actor.resource_id = rid
	s._take_reserved_resource("worker:0")
	_check(actor.carry_n == 1 and actor.carry_item == GameData.Item.STONE, "Stone weighs six: eight free weight allows one unit, not four")
	s._deposit_at_relay(actor)
	var second: String = s._reserve_resource("worker:0")
	_check(second.is_empty(), "Relay cargo consumes the same collection budget")
	if not second.is_empty():
		actor.resource_id = second
		s._release_actor_reservation(actor)

	# A real in-flight reservation can lose its room before harvest completes.
	s.field_capacity_limit_weight = 12
	var shrinking: String = s._reserve_resource("worker:0")
	_check(not shrinking.is_empty(), "Shrink fixture reserves while one more stone fits")
	if not shrinking.is_empty():
		actor.resource_id = shrinking
		var ground: int = s.resources[shrinking].remaining
		s.field_capacity_limit_weight = 8
		s._take_reserved_resource("worker:0")
		_check(actor.carry_item == -1 and actor.carry_n == 0 and s.resources[shrinking].remaining == ground and s.reservations.is_empty(), "Zero-unit completion stays empty-handed and releases its reservation")
		s.apply_projection_to_workers(main)
		_check(main.workers[0].carrying == -1, "Zero acquisition never projects phantom one-unit cargo")
	_check(s.conservation_ok(), "Capacity-limited acquisition conserves every resource")
	_check(s.has_method("return_cargo_plan"), "Normal return exposes an exact load/ground preview")
	if not s.has_method("return_cargo_plan"): return
	# Explicit legacy-save fixture: previously acquired four stones with only8 room.
	var held: int = s._stock_total(s.relay_stock)
	s.relay_stock.clear()
	s.resources[rid].remaining -= 4 - held
	s.depot_stock = {GameData.Item.STONE: 4}
	for a in s.actors.values():
		a.state = "idle"; a.carry_item = -1; a.carry_n = 0; a.path = []; a.path_index = 0
	s.reservations.clear(); s.phase = "ready_to_exit"
	s.apply_projection_to_workers(main)
	var plan: Dictionary = s.call("return_cargo_plan", main)
	_check(plan.get("deposited") == {GameData.Item.STONE:1} and plan.get("left_outside") == {GameData.Item.STONE:3}, "Legacy4-stone return previews one loaded and three at C")
	var before := SaveGame.capture(main)
	_check(not s.commit_to_game(main).ok and SaveGame.capture(main) == before, "No implicit overflow return without explicit approval")
	# A changed capacity must not execute an earlier quantity promise.
	main.storage.store_owned(GameData.Item.FOOD, 3, Inventory.SOURCE_TRANSFER)
	var changed := SaveGame.capture(main)
	var stale: Dictionary = s.call("commit_to_game", main, plan)
	_check(not stale.ok and SaveGame.capture(main) == changed and not s.committed, "Stale split changes no inventory, IDs or session completion")
	main.storage.inventory.take_n(GameData.Item.FOOD, 3)
	plan = s.call("return_cargo_plan", main)
	var result: Dictionary = s.call("commit_to_game", main, plan)
	_check(result.ok and main.storage.current_weight() == 358 and main.storage.max_weight() == 360, "Explicit partial return keeps real capacity and loads only one stone")
	if not result.ok: return
	_check(result.summary.deposited == {GameData.Item.STONE:1} and result.summary.left_outside == {GameData.Item.STONE:3}, "Return accounting distinguishes loaded and remaining cargo")
	var ids: Array = []
	for id in main.world.locations[RouteSession.SOURCE_KEY]:
		var row: Dictionary = main.world.locations[RouteSession.SOURCE_KEY][id]
		if row.type == "resource" and row.data.item == GameData.Item.STONE and not row.spent:
			ids.append(id)
	_check(ids.size() == 3, "Three ordinary ground IDs are durable immediately after return")
	var complete := SaveGame.capture(main)
	_check(SaveGame.validate(complete, main), "Partial return immediately validates as a complete save")
	_check(s.call("commit_to_game", main, plan).already_committed and SaveGame.capture(main) == complete, "Repeated explicit return never duplicates cargo or ground IDs")
	_check(SaveGame.apply(main, complete), "Partial return and ground IDs survive complete reload")
	for w in main.workers:
		w.stop_work(); w.floor_i = 1
	_check(await _move_leg("b_forest") and await _move_leg("c_quarry"), "Leftover location can be left and revisited normally")
	var retained := true
	for id in ids:
		retained = retained and main.world.locations[RouteSession.SOURCE_KEY].has(id) and not main.world.locations[RouteSession.SOURCE_KEY][id].spent
	_check(retained, "Revisited C retains the same three unspent leftover IDs")

func _zero_cargo_overweight() -> void:
	await _fresh()
	_check(await _move_leg("b_forest") and await _move_leg("c_quarry"), "Overweight fixture reaches C")
	main.storage.store_owned(GameData.Item.FOOD, main.storage.max_weight() + 1, Inventory.SOURCE_TRANSFER)
	var made: Dictionary = RouteSession.create_from_game(main, "zero-cargo-overweight", {"mine_path_engineering": true})
	_check(made.ok, "Owned overweight inventory does not prevent safe C inspection")
	if not made.ok: return
	var s = made.session
	_check(s.field_capacity_limit_weight == 0 and s._reserve_resource("worker:0").is_empty(), "Overweight C takes no new resources or reservations")
	s.request_recall()
	_check(await _advance_until(s, func(): return s.phase == "ready_to_exit", 80.0), "Zero-budget crew can finish ordinary physical recall")
	var inventory: Dictionary = main.storage.inventory.counts.duplicate(true)
	_check(s.commit_to_game(main).ok and main.storage.inventory.counts == inventory, "Zero-cargo return never requires extra capacity or changes owned inventory")
