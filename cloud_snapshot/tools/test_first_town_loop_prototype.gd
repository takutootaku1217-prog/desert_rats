extends SceneTree
## Verification-level first-town flow contract.
##
## This exercises the actual Main / WorldTrip / TownEconomy objects. It does
## not invent inventory or mission state, and keeps SaveGame disabled so the
## prototype test never touches a player's save.

var main
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _fresh() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	await process_frame

func _run() -> void:
	await _fresh()
	_check(main.world.map_profile == WorldMapDB.FIRST_REGION_A and main.world.region == "a_start", "first-region Main starts at A")
	_check(main.town.location_ok(), "A start can enter TownEconomy as the first town")
	var has_town_display_name: bool = main.town.has_method("town_display_name")
	_check(has_town_display_name, "TownEconomy exposes a profile-aware town display name")
	if has_town_display_name:
		_check(main.town.town_display_name() == "開始街", "first-region town UI is named as the first town, not Central Trade")
	var has_safe_town: bool = main.world.has_method("is_safe_town")
	_check(has_safe_town, "WorldTrip exposes a derived safe-town check")
	_check(has_safe_town and bool(main.world.call("is_safe_town")), "stopped A start is recognized as a safe town")
	main.world.region = "b_forest"
	main.world.phase = "stopped"
	main.journey.remaining = ["a_start"]
	main.operations.set_stance("recall")
	_check(main.world.ready_reason().is_empty(), "returned crew can leave a confirmed intermediate stop")
	_check(main.journey.resume(), "a cleared recall stance can resume the remaining route without re-dispatching crew")
	main.world.region = "a_start"
	main.world.phase = "stopped"
	main.journey.clear()
	main.operations.set_stance("normal")
	var has_mission_policy: bool = main.town.has_method("mission_enabled")
	_check(has_mission_policy, "TownEconomy exposes profile-aware mission availability")
	if has_mission_policy:
		_check(main.town.mission_enabled("supply"), "supply subquest is available in the first region")
		_check(not main.town.mission_enabled("delivery") and not main.town.mission_enabled("recovery"), "unreachable delivery and recovery contracts are unavailable")
	var has_growth_entry: bool = main.town_ui.has_method("open_prototype_growth")
	_check(has_growth_entry, "town UI exposes a prototype entry for existing craft and crew screens")
	main.town_ui.request_open()
	_check(main.town_ui.is_open(), "normal town entry opens at stopped A start")
	var has_building_map: bool = main.town_ui.has_method("show_building_intro") and main.town_ui.has_method("enter_building") and main.town_ui.has_method("building_id")
	_check(has_building_map, "town area map exposes tappable building previews and a returnable interior transition")
	if has_building_map:
		main.town_ui.show_building_intro("service")
		for frame in range(4):
			await process_frame
		var viewport: Rect2 = root.get_visible_rect()
		var panel: PanelContainer = main.town_ui._panel
		_check(viewport.encloses(panel.get_global_rect()), "yard explanation panel remains inside the viewport")
		var header: HBoxContainer = main.town_ui._body.get_child(0)
		var back: Button = header.get_child(1)
		var enter: Button = main.town_ui._body.get_child(main.town_ui._body.get_child_count() - 1)
		_check(viewport.encloses(back.get_global_rect()) and viewport.encloses(enter.get_global_rect()), "yard return and service entry buttons remain fully visible")
		enter.pressed.emit()
		_check(main.town_ui._selection == "service", "visible yard entry opens the real service screen")
		main.town_ui.show_street()
		main.town_ui.show_building_intro("market")
		_check(main.town_ui.building_id() == "market", "market tap opens the temporary shopkeeper interior")
		main.town_ui.enter_building()
		_check(main.town_ui.is_open() and main.town_ui.building_id() == "", "entering the shop transitions to the existing market and clears the building selection")
		main.town_ui.show_street()
	if has_growth_entry:
		main.town_ui.open_prototype_growth()
		_check(main.town_ui.is_open(), "prototype growth entry renders inside the town UI")
	main.town_ui.close()
	main.base.parts[GameData.Part.HULL] = 0.0
	await process_frame
	_check(not main.game_over, "stopped safe town permits Hull repair before game over")
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("== first town loop prototype: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
