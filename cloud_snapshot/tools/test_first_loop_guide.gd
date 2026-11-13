extends SceneTree
## The guide must describe current state, never invent progression or supplies.

const GUIDE := "はじめの一周"
var main
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok: failures += 1

func _state() -> Dictionary:
	return SaveGame.capture(main)

func _run() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 261107)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	var nav = main.navigation
	_check(not nav.popup.visible, "the guide never forces an intro on a fresh game")
	_check(nav.groups.has(GUIDE), "the existing navigation contains the first-loop guide")
	_check(nav.has_method("guide_snapshot"), "guide exposes its authoritative current-state readback")
	if not nav.groups.has(GUIDE) or not nav.has_method("guide_snapshot"):
		await _finish()
		return
	var entry: Button = nav.groups["その他"].find_child("FirstLoopGuideEntry", true, false)
	_check(entry != null, "the guide is reachable through the existing Other menu")
	if entry == null:
		await _finish()
		return
	var before := _state()
	nav.activate("その他")
	entry.emit_signal("pressed")
	await process_frame
	nav._process(0.0)
	_check(nav.popup.visible and nav.groups[GUIDE].visible, "the menu entry opens the actual guide")
	_check(paused, "reading the guide pauses the simulation")
	var first: Dictionary = nav.guide_snapshot()
	_check(first.supported and first.mode == "current_state", "guide explicitly reports current state rather than historic completion")
	_check(first.town_ready and not first.at_quarry, "fresh A is currently a town, not a completed quarry visit")
	_check(first.hunted == 0 and first.frame_equipped == 0, "fresh game has no invented hunt or equipment achievement")
	_check(first.ore == 0 and not first.workbench, "guide reads the actual empty ore stock and unbuilt workbench")
	var rect: Rect2 = nav.popup.get_global_rect()
	_check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1280 and rect.end.y <= 720, "guide fits the 1280 by 720 game viewport")
	var scroll: ScrollContainer = nav.groups[GUIDE].find_child("FirstLoopGuideScroll", true, false)
	_check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "long instructions remain readable through scrolling")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	nav._unhandled_input(escape)
	_check(not nav.popup.visible and not paused, "Escape dismisses the guide and restores unpaused play")
	_check(before == _state(), "opening, refreshing and closing does not mutate any saved gameplay state")

	# A valid inventory fixture is not proof of quarry collection or past visits.
	main.storage.store_owned(GameData.Item.IRON_ORE, 2, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.HAUL_FRAME, 1, Inventory.SOURCE_TRANSFER)
	_check(main.equip_work_support(main.workers[0], GameData.Item.HAUL_FRAME), "fixture equips a real owned frame through the normal API")
	var changed := _state()
	nav.activate(GUIDE)
	nav._process(0.0)
	var refreshed: Dictionary = nav.guide_snapshot()
	_check(refreshed.ore == 2 and refreshed.frame_stock == 0 and refreshed.frame_equipped == 1, "reopened guide reflects exact warehouse and equipped quantities")
	_check(refreshed.hunted == 0 and not refreshed.at_quarry, "unrelated stock never implies hunting or being at C")
	_check(changed == _state(), "guide refresh does not grant, consume, equip, or change orders")
	main.storage.take_item(GameData.Item.IRON_ORE)
	nav._process(0.0)
	_check(nav.guide_snapshot().ore == 1, "an open guide refreshes when authoritative state changes")
	nav.close()

	paused = true
	nav.activate(GUIDE)
	nav.close()
	_check(paused, "closing preserves a game that was already paused")
	paused = false
	nav.activate(GUIDE)
	nav.activate("その他")
	_check(not paused and nav.selected == "その他", "switching navigation groups releases only the guide's pause")
	nav.close()
	main.world.guide_progress.completed["quarry_returned"] = true
	main.world.guide_progress.completed["returned_a"] = true
	var actions_before := _state()
	for action in ["map", "prepare", "repair", "upgrade", "crew", "save", "smelt", "armor_recipe", "armor", "town"]:
		nav.activate(GUIDE)
		await process_frame; nav._process(0.0)
		var button: Button = nav.groups[GUIDE].find_child("GuideAction_" + action, true, false)
		_check(button != null, "%s link exists" % action)
		if button == null: continue
		_check(button.is_visible_in_tree() and nav.popup.get_global_rect().encloses(button.get_global_rect()), "%s real action stays inside the visible guide" % action)
		button.emit_signal("pressed")
		_check(not nav.popup.visible, "%s closes the guide before opening its destination" % action)
		match action:
			"map": _check(main.map_ui.is_open(), "map link opens the existing route chooser without departing")
			"prepare": _check(main.craft_ui.is_open() and main.craft_ui.selected_entry().get("key") == "build:workbench", "preparation opens the real first workbench entry")
			"repair": _check(main.craft_ui.is_open() and main.craft_ui.selected_entry().get("key") == "repair_stone", "repair link opens the existing stone repair recipe")
			"upgrade": _check(main.craft_ui.is_open() and main.craft_ui.selected_entry().get("key") == "haul_frame", "upgrade link opens the existing frame recipe")
			"crew": _check(main.detail._overlay.visible, "crew link opens existing equipment management")
			"save": _check(main.save_ui.is_open() and main.save_ui._action == "", "save link only opens the confirmation-based save menu")
			"smelt": _check(main.craft_ui.is_open() and main.craft_ui.selected_entry().get("key") == "smelt", "smelt link opens existing ore-to-iron recipe without submitting it")
			"armor_recipe": _check(main.craft_ui.is_open() and main.craft_ui.selected_entry().get("key") == "armor_plate_kit", "armor recipe link opens paid kit manufacturing")
			"armor": _check(main.vehicle_ui._overlay.visible and not main.vehicle_ui._armor_dialog.visible, "armor link opens real vehicle panel without starting a comparison transaction")
			"town": _check(main.town_ui.is_open() and not main.town_ui._waiting, "town link opens existing ready-town supply screen without recall")
		main.close_other_panels(null)
		_check(not paused, "%s destination restores the pre-guide pause state on close" % action)
	_check(actions_before == _state(), "guide links do not spend, depart, save, or issue work orders")
	var town_link: Button = nav.groups[GUIDE].find_child("GuideAction_town", true, false)
	if town_link != null:
		nav.activate(GUIDE)
		main.workers[0].away = true
		var unavailable := _state()
		nav._process(0.0)
		_check(town_link.disabled, "unready town link is disabled instead of secretly recalling workers")
		town_link.emit_signal("pressed")
		_check(not main.town_ui.is_open() and not main.town_ui._waiting and unavailable == _state(), "stale town callback rechecks availability without recall or saved-state changes")
		main.workers[0].away = false
	main.map_ui.open()
	nav.activate(GUIDE)
	_check(not main.map_ui.is_open() and paused, "guide closes another modal without losing pause ownership")
	nav.close()
	_check(not paused, "closing a guide opened over another modal restores normal play")

	main.world.map_profile = WorldMapDB.DESERT
	var legacy: Dictionary = nav.guide_snapshot()
	_check(not legacy.supported, "non-first-region saves are not given an unavailable A to D route")
	await _finish()

func _finish() -> void:
	paused = false
	if is_instance_valid(main): main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("FIRST LOOP GUIDE failures=", failures)
	quit(1 if failures else 0)
