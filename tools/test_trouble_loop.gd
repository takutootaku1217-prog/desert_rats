extends "res://tools/test_field_operations.gd"
## Focused regression coverage for crew status/orders, retreat, and engine fuel leaks.


func ready_worker(w) -> void:
	for other in main.workers:
		other.stop_work()
		other.floor_i = 1
		other.position = Vector2(700.0, GameData.LO_Y)
		other._climb_dest = null
		for job in GameData.job_list():
			other.priorities[job] = 0
		other.ai.retreating = false
		other.ai.danger_hold = false
		other.ai.return_request = false
		other.ai.manual_job = -1
	w.floor_i = 1
	w.position = main.storage.access_point()
	w.hp = 100.0
	w.hunger = 100.0
	w.fatigue = 0.0
	w.stress = 0.0
	w.ai._set_state(CharacterAI.State.SEARCH)


func wait_for_repair(w, before: int) -> bool:
	return await until(func(): return main.base.total_repair > before and w.ai.manual_job == -1, 18.0)


func _initialize() -> void:
	await repair_loop()
	await retreat_loop()
	await leak_loop()
	await save_loop()
	await capture_requested_screens()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)


func capture_requested_screens() -> void:
	var destination := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			destination = arg.trim_prefix("--screenshots=")
	if destination.is_empty():
		return
	print("screenshot destination: ", destination)
	main.base.parts[GameData.Part.DRIVE] = 69.0
	main.base.rear_engine_damage = GameData.REAR_ENGINE_LEAK_DAMAGE_THRESHOLD
	main.status._process(0.1)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(destination.path_join("trouble-hud.png"))
	main.detail.open_worker(main.workers[0])
	await process_frame
	main.detail._update_live()
	await process_frame
	root.get_texture().get_image().save_png(destination.path_join("trouble-crew.png"))


func repair_loop() -> void:
	print("-- manual repair, interruption, and autonomous return --")
	await fresh()
	main.target_speed = 0.0
	var w = main.workers[0]
	ready_worker(w)
	while main.storage.count_of(GameData.Item.REPAIR_KIT) > 0:
		main.storage.take_item(GameData.Item.REPAIR_KIT)
	main.base.parts[GameData.Part.DRIVE] = 69.0
	main.base.rear_engine_damage = GameData.REAR_ENGINE_LEAK_DAMAGE_THRESHOLD
	var empty: Dictionary = main.repair_order_info()
	check(int(empty["required"]) == 1 and int(empty["available"]) == 0 and int(empty["missing"]) == 1, "repair UI data reports kit requirement and shortage before assigning")
	check(not main.request_repair(w) and w.ai.manual_job == -1, "a missing kit neither assigns a worker nor consumes an order")
	main.storage.store_owned(GameData.Item.REPAIR_KIT, 1)
	var before_kits: int = main.storage.count_of(GameData.Item.REPAIR_KIT)
	check(main.request_repair(w) and w.ai.manual_job == GameData.Job.REPAIR, "explicit worker repair order is accepted with one kit")
	var order: Dictionary = main.repair_order_info()
	check(order["assigned"] == w and int(order["missing"]) == 0, "repair assignment is visible while pending")
	var repair_before: int = main.base.total_repair
	check(await wait_for_repair(w, repair_before), "repairer collects kit, repairs, and finishes without fuel")
	check(main.base.condition(GameData.Part.DRIVE) == 94.0 and is_equal_approx(main.base.rear_engine_damage, 5.0) and not main.base.engine_leaking() and main.storage.count_of(GameData.Item.REPAIR_KIT) == before_kits - 1, "one field repair spends exactly one kit, repairs DRIVE, and clears its rear-hit leak accumulation")
	check(w.ai.manual_job == -1 and not main.base.repair_reserved.has(GameData.Part.DRIVE), "completed direct repair releases assignment and reservation")
	main.storage.store_owned(GameData.Item.FUEL, 1)
	main.base.fuel = 0.0
	w.priorities[GameData.Job.HAUL] = GameData.MAX_PRIORITY
	await step()
	check(w.ai.state in [CharacterAI.State.REFUEL_TAKE, CharacterAI.State.REFUEL_MOVE, CharacterAI.State.REFUEL], "after repair, normal priority work resumes automatically")

	ready_worker(w)
	main.base.parts[GameData.Part.DRIVE] = 69.0
	main.storage.store_owned(GameData.Item.REPAIR_KIT, 1)
	check(main.request_repair(w), "a second repair request starts normally")
	check(await until(func(): return w.ai.state in [CharacterAI.State.REPAIR_MOVE, CharacterAI.State.REPAIR], 8.0), "repair reaches its active phase")
	var saved_kit_count: int = main.storage.count_of(GameData.Item.REPAIR_KIT)
	check(w.ai.cancel_manual_repair(), "active repair can be cancelled")
	check(w.ai.manual_job == -1 and not main.base.repair_reserved.has(GameData.Part.DRIVE) and w.carrying == -1 and main.storage.count_of(GameData.Item.REPAIR_KIT) == saved_kit_count + 1, "cancelling active repair returns the kit and clears reservation")

	check(main.request_repair(w), "repair can be assigned again after cancellation")
	check(await until(func(): return w.ai.state in [CharacterAI.State.REPAIR_MOVE, CharacterAI.State.REPAIR], 8.0), "reassigned repair starts")
	check(w.ai.request_return(), "repairer accepts a persistent retreat order")
	w.ai.tick(0.1)
	check(w.ai.return_request and w.ai.manual_job == GameData.Job.REPAIR and not main.base.repair_reserved.has(GameData.Part.DRIVE) and w.carrying == -1, "retreat pauses repair safely without losing its kit or reservation")
	check(w.ai.cancel_return(), "persistent retreat has an explicit cancellation path")
	w.stop_work()
	check(w.ai.manual_job == -1 and not main.base.repair_reserved.has(GameData.Part.DRIVE), "injury/stop-work cleanup cannot leave a repair assignment stuck")
	main.status._process(0.1)
	check(main.status._crew_repair != null and not main.status._crew_repair.tooltip_text.is_empty(), "HUD exposes repair material and assignment information")


func retreat_loop() -> void:
	print("-- retreat interrupts eating and combat without re-engaging --")
	await fresh()
	main.target_speed = 0.0
	var w = main.workers[0]
	ready_worker(w)
	main.storage.store_owned(GameData.Item.FOOD, 1)
	w.hunger = 0.0
	check(w.ai._try_start_eat(true), "worker can begin the existing eating state")
	w.position = main.storage.access_point()
	check(await until(func(): return w.ai.state == CharacterAI.State.EAT, 4.0), "eating state is active before retreat")
	var food_before: int = main.storage.count_of(GameData.Item.FOOD)
	check(w.ai.request_return(), "retreat command is accepted while eating")
	w.ai.tick(0.1)
	check(w.ai.return_request and w.ai.state == CharacterAI.State.RETURN_BASE and main.food_claims == 0 and main.storage.count_of(GameData.Item.FOOD) == food_before + 1, "retreat releases meal claim and returns carried food")
	check(w.ai.cancel_return(), "retreat can be cancelled after eating interruption")

	ready_worker(w)
	w.floor_i = 0
	w.position = Vector2(700.0, 680.0)
	var target = enemy_at("sand_stalker", 740.0)
	check(w.ai.order_attack(target), "manual combat order starts")
	w.ai.tick(0.1)
	check(w.ai.request_return(), "combatant accepts early retreat")
	w.ai.tick(0.1)
	check(w.ai.return_request and not w.ai.manual_attack and w.ai.enemy == null and w.ai.state == CharacterAI.State.RETURN_BASE, "retreat clears active combat target and prevents a new engagement")
	check(not w.ai.order_attack(target), "persistent retreat blocks another manual combat order")
	check(w.ai.status_text().contains("退却"), "crew status text identifies persistent retreat")
	clear_enemies()


func leak_loop() -> void:
	print("-- rear-only enemy damage, speed, and fuel leak --")
	await fresh()
	main.target_speed = 200.0
	var b = main.base
	var rear_x: float = b.rear_engine_attack_point().x
	var threshold: float = GameData.REAR_ENGINE_LEAK_DAMAGE_THRESHOLD
	# 通常走行の摩耗だけでは、DRIVEが低くなっても漏れ原因を作らない。
	b.wear_by(0.0, 20000.0)
	check(b.condition(GameData.Part.DRIVE) < 70.0 and is_equal_approx(b.rear_engine_damage, 0.0) and not b.engine_leaking(), "normal travel wear lowers DRIVE without creating a fuel leak")
	b.parts[GameData.Part.HULL] = 100.0
	b.parts[GameData.Part.DRIVE] = 100.0
	# 通常襲撃の前方命中は耐久を損傷しても、後部漏れ蓄積を増やさない。
	var front := Enemy.new()
	front.setup_kind(main, "scorpion")
	front.position = Vector2(front.hold_x - 1.0, 680.0)
	front._atk_timer = 0.0
	main.enemies_root.add_child(front)
	front._process(0.01)
	check(b.impact_zone(front.position.x) == GameData.ImpactZone.FRONT and b.condition(GameData.Part.DRIVE) < 100.0 and is_equal_approx(b.rear_engine_damage, 0.0) and not b.engine_leaking(), "front enemy hit damages ordinary DRIVE only and cannot start a leak")
	main.enemies_root.remove_child(front)
	front.free()
	b.parts[GameData.Part.HULL] = 100.0
	b.parts[GameData.Part.DRIVE] = 100.0
	b.rear_engine_damage = 0.0
	var center_x := GameData.HULL_POS.x + (GameData.BASE_IMPACT_REAR_LOCAL_X_MAX + 10.0) * ArtSpec.UNIT_PX
	b.take_damage(threshold, center_x)
	check(b.impact_zone(center_x) == GameData.ImpactZone.CENTER and is_equal_approx(b.rear_engine_damage, 0.0) and not b.engine_leaking(), "center enemy hit remains separate from rear leak accumulation")
	b.parts[GameData.Part.HULL] = 100.0
	b.parts[GameData.Part.DRIVE] = 100.0
	# 後部被弾はしきい値未満では漏れず、跨いだ時だけ発生する。
	b.take_damage(threshold - 1.0, rear_x)
	check(is_equal_approx(b.rear_engine_damage, threshold - 1.0) and not b.engine_leaking(), "rear hits below the provisional threshold do not leak")
	b.take_damage(1.0, rear_x)
	var at_threshold: float = b.engine_leak_rate(GameData.FUEL_STANDARD_SPEED)
	check(b.engine_leaking() and at_threshold > 0.0, "rear hit crossing the threshold starts a fuel leak")
	b.take_damage(10.0, rear_x)
	check(b.rear_engine_damage > threshold and b.engine_leak_rate(GameData.FUEL_STANDARD_SPEED) > at_threshold, "continued rear hits accumulate and raise the leak rate")
	# 車体の向きは画面ローカルで固定。経路を反転しても後部判定は入れ替わらない。
	var direction_before: int = main.world.direction
	main.world.direction = -1
	b.rear_engine_damage = 0.0
	b.parts[GameData.Part.DRIVE] = 100.0
	b.take_damage(threshold, rear_x)
	check(b.engine_leaking() and b.is_rear_engine_impact(rear_x) and not b.is_rear_engine_impact(GameData.RAMP_FOOT.x), "reverse travel keeps the same vehicle-local rear and excludes the front")
	main.world.direction = direction_before
	# 後部への大きな連続被弾は既存の速度上限を使う。修理後も目標速度は手動で戻す。
	b.take_damage(50.0, rear_x)
	check(main.target_speed == b.speed_limit() and main.target_speed == 40.0, "severe rear engine damage lowers target speed")
	b.fuel = 100.0
	var idle: float = b.leak_fuel(10.0, 0.0)
	var moving: float = b.leak_fuel(10.0, GameData.FUEL_STANDARD_SPEED)
	b.fuel = 0.0
	b.leak_fuel(10.0, GameData.FUEL_STANDARD_SPEED)
	check(idle > 0.0 and moving > idle and b.fuel == 0.0, "stopping reduces but does not eliminate leak cost, and empty fuel never goes negative")
	b.repair(GameData.Part.DRIVE)
	b.repair(GameData.Part.DRIVE)
	b.repair(GameData.Part.DRIVE)
	check(not b.engine_leaking() and main.target_speed == 40.0, "repairs reduce rear accumulation until the leak stops without restoring speed automatically")
	# 応急即時修理も同じ蓄積を回復する。
	await fresh()
	b = main.base
	b.parts[GameData.Part.DRIVE] = 69.0
	b.rear_engine_damage = threshold
	main.storage.store_owned(GameData.Item.REPAIR_KIT, 1)
	check(main.emergency_repair() and is_equal_approx(b.rear_engine_damage, threshold - GameData.REPAIR_AMOUNT) and not b.engine_leaking(), "emergency repair clears rear-hit accumulation together with DRIVE")
	# 故障イベントは DRIVE を直接損傷しても、敵の後部被弾としては扱わない。
	await fresh()
	b = main.base
	main.director._apply_instant("breakdown", {"kind":"trouble", "parts":{GameData.Part.DRIVE:1.0}, "damage":[40.0,40.0], "text":{GameData.Part.DRIVE:"test"}})
	check(b.condition(GameData.Part.DRIVE) == 60.0 and is_equal_approx(b.rear_engine_damage, 0.0) and not b.engine_leaking(), "breakdown DRIVE damage is separate from rear enemy leak damage")
	main.status._process(0.1)
	b.rear_engine_damage = threshold
	main.status._process(0.1)
	check(main.status._leak.visible and main.status._leak.text.contains("燃料"), "HUD shows the rear-hit leak status and reduced/stopped behavior")


func save_loop() -> void:
	print("-- save restore preserves orders without blocked reservations --")
	await fresh()
	var w = main.workers[0]
	ready_worker(w)
	main.base.parts[GameData.Part.DRIVE] = 69.0
	main.base.rear_engine_damage = GameData.REAR_ENGINE_LEAK_DAMAGE_THRESHOLD
	main.storage.store_owned(GameData.Item.REPAIR_KIT, 1)
	check(main.request_repair(w), "repair request is ready for save")
	w.ai.return_request = true
	var snapshot := SaveGame.capture(main)
	check(SaveGame.apply(main, snapshot), "save snapshot with retreat and repair assignment restores")
	w = main.workers[0]
	check(w.ai.return_request and w.ai.manual_job == GameData.Job.REPAIR and main.base.repair_reserved.is_empty() and main.base.engine_leaking() and is_equal_approx(main.base.rear_engine_damage, GameData.REAR_ENGINE_LEAK_DAMAGE_THRESHOLD), "new saves restore rear-hit leakage while paused repair has no stale reservation")
	var legacy := snapshot.duplicate(true)
	legacy.base.erase("rear_engine_damage")
	legacy.base.parts[GameData.Part.DRIVE] = 0.0
	for row in legacy.crew:
		row.ai.erase("return_request")
		row.ai.erase("manual_job")
	check(SaveGame.validate(legacy, main) and SaveGame.apply(main, legacy) and not main.base.engine_leaking() and is_equal_approx(main.base.rear_engine_damage, 0.0), "older saves with low DRIVE but no rear-hit field stay compatible and do not leak")
