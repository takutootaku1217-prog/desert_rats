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


func find_first(node: Node, kind) -> Control:
	for child in node.get_children():
		if is_instance_of(child, kind):
			return child
		var found := find_first(child, kind)
		if found != null:
			return found
	return null


func find_button_text(node: Node, text_: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text_:
			return child
		var found := find_button_text(child, text_)
		if found != null:
			return found
	return null


func press_key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.director.enabled = false
	main.target_speed = 0.0
	var base = main.base
	var storage = main.storage
	check(is_equal_approx(base.speed_limit(), 200.0), "normal start keeps the existing maximum speed")
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
	# The vehicle panel must remain usable on a narrow window: fixed close action,
	# vertical scroll, wrapping action flow, and Esc all use real input paths.
	var old_window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(640, 360))
	await frames()
	var vehicle_ui = main.vehicle_ui
	vehicle_ui.open()
	await frames()
	var panel: PanelContainer = find_first(vehicle_ui._overlay, PanelContainer)
	var scroll: ScrollContainer = find_first(vehicle_ui._overlay, ScrollContainer)
	var viewport: Rect2 = root.get_visible_rect()
	check(vehicle_ui.is_open() and panel != null and panel.get_global_rect().position.x >= 0.0 and panel.get_global_rect().end.x <= viewport.end.x + 1.0 and panel.get_global_rect().end.y <= viewport.end.y + 1.0, "vehicle panel stays inside the current viewport")
	check(scroll != null and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and scroll.get_child(0).size.x <= scroll.size.x + 1.0, "vehicle rows fit the vertical scroll width")
	check(find_button_text(vehicle_ui._overlay, "戦闘フルスペック試作") != null, "combat preset uses the readable Japanese label")
	main.apply_vehicle_combat_preset()
	check(str(base.vehicle_loadout.chassis) == "reinforced_large" and vehicle_ui.is_open(), "combat preset applies while the panel is open")
	vehicle_ui.close()
	check(not vehicle_ui.is_open(), "vehicle panel closes")
	vehicle_ui.open()
	await press_key(KEY_ESCAPE)
	check(not vehicle_ui.is_open(), "Escape closes the reopened vehicle panel")
	DisplayServer.window_set_size(old_window_size)
	await frames()
	# The walkthrough itself was exercised by the preset.  Cancel it before the
	# independent crew-combat regression below so its target selection is tested.
	for worker in main.workers:
		worker.prototype_walk_target = null
	await press_key(KEY_O)
	await frames(20) # The view cross-fades before applying the exterior renderer.
	check(base.view_exterior, "O switches the raster fortress to the exterior view")
	# The six supplied wheels use travel distance/radius, not an animation frame
	# number. A stopped base must therefore keep its last rotation exactly.
	main.scroll_speed = LargeVehicleLayout.MOVING_WHEEL_RADIUS
	var wheel_before: float = base._wheel_angle
	base._process(1.0)
	var wheel_after_move: float = base._wheel_angle
	main.scroll_speed = 0.0
	base._process(1.0)
	check(not is_equal_approx(wheel_before, wheel_after_move) and is_equal_approx(wheel_after_move, base._wheel_angle), "six moving-part wheels rotate by travel distance and stop at zero speed")
	await press_key(KEY_I)
	await frames(20)
	check(not base.view_exterior, "I returns the raster fortress to the interior cutaway")
	main.spawn_vehicle_test_enemy()
	await frames()
	var enemy = main.enemies_root.get_child(0)
	var hp_before: float = enemy.hp
	var ammo_before: int = base.vehicle_loadout.ammo
	main.fire_vehicle_weapon("primary")
	check(is_equal_approx(enemy.hp, hp_before - 30.0) and base.vehicle_loadout.ammo == ammo_before - 2 \
		and base.vehicle_weapon_recoil("primary") > 0.0 and base.vehicle_weapon_flash("primary") > 0.0, "primary weapon damages, consumes ammunition, and triggers fortress fire feedback")
	var secondary_hp: float = enemy.hp
	var secondary_ammo: int = base.vehicle_loadout.ammo
	main.fire_vehicle_weapon("secondary")
	check(is_equal_approx(enemy.hp, secondary_hp - 11.0) and base.vehicle_loadout.ammo == secondary_ammo - 1, "secondary keeps its existing single-hit damage and ammunition cost")
	# Presentation timers are seconds, so this must not depend on an uncapped
	# headless renderer producing a particular number of frames.
	await create_timer(0.25).timeout
	check(is_zero_approx(base.vehicle_weapon_recoil("primary")) and is_zero_approx(base.vehicle_weapon_flash("primary")), "fortress fire feedback ends after its short presentation window")
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
