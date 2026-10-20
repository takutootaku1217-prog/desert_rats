extends SceneTree
## Headless regression for the large vehicle prototype and shared combat path.
var main
var fails := 0

func check(ok: bool, message: String) -> void:
	print(("OK " if ok else "FAIL ") + message)
	if not ok:
		fails += 1

func frames(n := 8) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.director.enabled = false
	main.target_speed = 0.0
	var base = main.base
	var storage = main.storage
	check(base.vehicle_capacity() == CargoDB.CAPACITY and storage.limits_active(), "normal start keeps the existing cargo limit")
	main.equip_vehicle_part("chassis", "large")
	check(base.vehicle_capacity() == 520 and storage.max_weight() == 520, "large chassis expands shared cargo capacity")
	check(LargeVehicleLayout.raster_assets_available() and GameData.tex(LargeVehicleLayout.RASTER_HULL).get_width() == 1927 \
		and GameData.tex(LargeVehicleLayout.RASTER_INTERIOR).get_height() == 797, "large chassis raster sources are readable at their supplied dimensions")
	main.equip_vehicle_part("chassis", "reinforced_large")
	check(base.vehicle_capacity() == 620 and storage.max_weight() == 620 and base.vehicle_equipment_weight() > 0, "chassis swap changes capacity and equipment weight")
	main.equip_vehicle_part("drive", "tracks")
	main.equip_vehicle_part("power", "turbo")
	check(is_equal_approx(base.speed_limit(), 95.0) and base.vehicle_fuel_mult() > 1.0, "drive and power change speed cap and fuel use")
	main.equip_vehicle_part("armor", "none")
	base.parts[GameData.Part.HULL] = 100.0
	base.take_damage(8.0)
	var unarmored: float = 100.0 - float(base.parts[GameData.Part.HULL])
	main.equip_vehicle_part("armor", "composite")
	base.parts[GameData.Part.HULL] = 100.0
	base.take_damage(8.0)
	var armored: float = 100.0 - float(base.parts[GameData.Part.HULL])
	check(unarmored > armored and is_equal_approx(armored, 0.0), "armor reduces actual incoming hull damage")
	main.equip_vehicle_part("primary", "cannon")
	base.set_view_exterior(true)
	await frames()
	check(base.view_exterior, "raster fortress switches to the exterior view")
	base.set_view_exterior(false)
	await frames()
	check(not base.view_exterior, "raster fortress returns to the interior cutaway")
	main.spawn_vehicle_test_enemy()
	await frames()
	var enemy = main.enemies_root.get_child(0)
	var hp_before: float = enemy.hp
	var ammo_before: int = base.vehicle_loadout.ammo
	main.fire_vehicle_weapon("primary")
	check(is_equal_approx(enemy.hp, hp_before - 30.0) and base.vehicle_loadout.ammo == ammo_before - 2, "primary weapon damages existing enemy and consumes ammunition")
	# Existing crew AI should use the same non-ecological enemy after it reaches
	# the base. Keep it alive after vehicle fire and let auto-combat acquire it.
	enemy.hp = 100.0
	enemy.position = Vector2(enemy.hold_x, GameData.GROUND_Y_MAX - 12.0)
	for worker in main.workers:
		worker.stop_work()
		worker.position = Vector2(enemy.hold_x - 25.0, GameData.GROUND_Y_MAX - 12.0)
		for job in GameData.job_list():
			worker.priorities[job] = 0
		worker.priorities[GameData.Job.COMBAT] = 5
	var crew_hp_before: float = main.workers[0].hp
	await create_timer(4.0).timeout
	check(not is_instance_valid(enemy) or enemy.hp < 100.0, "crew auto-acquires and damages the same enemy")
	check(main.workers[0].hp < crew_hp_before or main.workers[0].fatigue > 0.0, "enemy retaliation reaches crew combat path")
	main.apply_vehicle_combat_preset()
	check(not storage.limits_active() and base.vehicle_loadout.get("prototype_unlimited", false), "combat prototype ignores cargo limits while keeping weight visible")
	var snapshot := SaveGame.capture(main)
	check(SaveGame.validate(snapshot, main), "prototype loadout is included in a valid save snapshot")
	print("== vehicle prototype: %s ==" % ("passed" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)
