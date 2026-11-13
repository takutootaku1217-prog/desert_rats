extends SceneTree
## Contract for the live road presentation. This uses the real Main scene but
## invokes only draw-selection methods; no route, save, fuel, or crew state is
## advanced by this test.

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
	main.set_meta("diagnostic_seed", 240731)
	root.add_child(main)
	await process_frame

func _rider_state() -> Array:
	var out: Array = []
	for worker in main.workers:
		out.append({
			"position": worker.position,
			"floor_i": worker.floor_i,
			"away": worker.away,
			"carrying": worker.carrying,
			"carry_bonus": worker.carry_bonus.duplicate(true),
			"ai_state": worker.ai.state,
			"hp": worker.hp,
			"hunger": worker.hunger,
			"fatigue": worker.fatigue,
			"stress": worker.stress,
			"calm": worker.calm,
			"mental": worker.mental,
			"down": worker.down,
			"sleeping": worker.sleeping,
			"resting": worker.resting,
		})
	return out

func _simulation_state() -> Dictionary:
	return {
		"world": SaveGame.fields(main.world, WorldTrip.FIELDS),
		"journey": main.journey.snapshot(),
		"fuel": main.base.fuel,
		"parts": main.base.parts.duplicate(true),
		"distance": main.director.distance,
		"scroll_speed": main.scroll_speed,
		"target_speed": main.target_speed,
		"inventory": main.storage.inventory.counts.duplicate(true),
		"riders": _rider_state(),
	}

func _all_riders_visible() -> bool:
	return main.workers.all(func(worker): return worker.away or worker.visible)

func _all_riders_hidden() -> bool:
	return main.workers.all(func(worker): return not worker.visible)

func _run() -> void:
	await _fresh()
	var user_dir_name := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var actual_user_dir := OS.get_user_data_dir().replace("\\", "/").trim_suffix("/")
	_check(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) and not user_dir_name.is_empty(), "prototype explicitly selects a custom user-data directory")
	_check(actual_user_dir.to_lower().ends_with("/" + user_dir_name.replace("\\", "/").to_lower()), "runtime save location matches the selected prototype/QA directory")
	var isolated_home := OS.get_environment("FLUID_TEST_HOME").replace("\\", "/").trim_suffix("/")
	if not isolated_home.is_empty():
		_check(actual_user_dir.to_lower().begins_with(isolated_home.to_lower() + "/"), "runner keeps actual saves below its isolated temporary root, never the player's save directory")
	var lane_path := "res://scripts/travel_lane_presentation.gd"
	_check(ResourceLoader.exists(lane_path), "road presentation exposes a derived phase readback")
	if ResourceLoader.exists(lane_path):
		var lane = load(lane_path)
		for phase in ["departing", "travel", "arriving", "turning"]:
			main.world.phase = phase
			_check(bool(lane.active(main)), "%s is a road-presentation phase" % phase)
			_check("\n" not in str(lane.phase_label(main)), "%s label stays on one line" % phase)
		var has_outdoor_gate: bool = bool(lane.get_script_method_list().any(func(method): return String(method.get("name", "")) == "blocks_outdoor_work"))
		var has_composition: bool = bool(lane.get_script_method_list().any(func(method): return String(method.get("name", "")) == "composition"))
		var has_road_layout: bool = bool(lane.get_script_method_list().any(func(method): return String(method.get("name", "")) == "road_layout"))
		_check(has_outdoor_gate, "road presentation exposes an outdoor-work gate")
		_check(has_composition, "road presentation exposes normal and danger compositions")
		_check(has_road_layout, "road presentation exposes one draw-only travel-strip layout")
		if has_road_layout:
			var normal_layout: Dictionary = {}
			for phase in ["departing", "travel", "arriving", "turning"]:
				main.world.phase = phase
				var layout: Dictionary = lane.road_layout(main)
				# Departure can still be waiting for workers to return from the
				# stopped site.  Do not draw a road beneath those site actors: that
				# would make the old site row and the travel row read as two lanes.
				# It remains an active/safety phase, just not a moving-road picture.
				if phase == "departing":
					_check(layout.is_empty(), "departing keeps the stopped-site picture until the one-lane journey actually begins")
					_check(bool(lane.blocks_outdoor_work(main)), "departing still blocks new outdoor work while riders return")
					continue
				_check(int(layout.get("strip_count", -1)) == 1, "%s exposes exactly one visual route strip" % phase)
				_check(not bool(layout.get("has_center_divider", true)) and not bool(layout.get("has_near_shoulder", true)), "%s exposes no divider or foreground shoulder as a second lane" % phase)
				var top := float(layout.get("top", INF))
				var height := float(layout.get("height", -1.0))
				var ground_y := float(layout.get("ground_y", -INF))
				_check(height > 0.0 and ground_y >= top and ground_y <= top + height, "%s keeps travel actors on its only visual route" % phase)
				_check(is_equal_approx(main.vehicle_hunt.mount().y, ground_y), "%s keeps the explicit vehicle-hunt mount on the only route" % phase)
				if phase == "travel":
					normal_layout = layout.duplicate(true)
			main.world.phase = "travel"
			var layout_read_before := _simulation_state()
			lane.road_layout(main)
			_check(layout_read_before == _simulation_state(), "reading the one-lane layout never mutates travel, fuel, durability, inventory, or crew")
			main.spawn_vehicle_test_enemy()
			var danger_layout: Dictionary = lane.road_layout(main)
			_check(normal_layout.get("top") == danger_layout.get("top") and normal_layout.get("height") == danger_layout.get("height") and normal_layout.get("ground_y") == danger_layout.get("ground_y"), "danger framing keeps the same one-lane geometry")
			for enemy in main.enemies_root.get_children():
				# The fixture threat only selects presentation danger. Mark it inactive
				# synchronously so later normal-composition assertions stay deterministic.
				enemy.dead = true
			main.world.phase = "stopped"
			_check(lane.road_layout(main).is_empty(), "stopped region exposes no travel route strip")
		main.world.phase = "travel"
		if has_outdoor_gate:
			_check(bool(lane.blocks_outdoor_work(main)), "road travel blocks new outdoor work")
			_check(not main.operations.can_depart(main.workers[0], main.workers[0].position), "road travel does not dispatch a rider to field work")
		if has_composition:
			_check(str(lane.composition(main)) == "normal", "road travel starts in the normal exterior composition")
			main.spawn_vehicle_test_enemy()
			_check(str(lane.composition(main)) == "danger", "an existing threat selects the danger composition without a new combat system")
		main.world.phase = "stopped"
		if has_outdoor_gate:
			_check(not bool(lane.blocks_outdoor_work(main)), "a stopped region permits normal outdoor-work eligibility")
		main.world.phase = "stopped"
		_check(not bool(lane.active(main)), "stopped region is not road presentation")
	var hud_path := "res://ui/travel_hud.gd"
	_check(ResourceLoader.exists(hud_path), "travel presentation has a compact HUD with an explicit details control")
	if ResourceLoader.exists(hud_path):
		var travel_hud = load(hud_path).new()
		travel_hud.game = main
		root.add_child(travel_hud)
		await process_frame
		main.world.phase = "travel"
		var hud_before := _simulation_state()
		_check(travel_hud.is_compact(), "road HUD starts compact")
		travel_hud.set_details_open(true)
		_check(travel_hud.details_open(), "road HUD opens details only on request")
		travel_hud.set_details_open(false)
		_check(not travel_hud.details_open(), "road HUD closes details on request")
		_check(hud_before == _simulation_state(), "road HUD detail changes do not mutate travel, fuel, durability, inventory, or crew state")
		main.world.phase = "stopped"
		travel_hud.queue_free()
	var has_sync: bool = main.base_view.has_method("sync_travel_presentation")
	var has_shown_mode: bool = main.base_view.has_method("shown_mode")
	_check(has_sync and has_shown_mode, "BaseView exposes presentation sync and shown mode")
	if has_sync and has_shown_mode:
		main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
		var shown_events: Array[int] = []
		main.base_view.changed.connect(func(new_mode: int): shown_events.append(new_mode))
		main.world.phase = "travel"
		var before := _simulation_state()
		main.base_view.sync_travel_presentation()
		var after := _simulation_state()
		_check(main.base_view.shown_mode() == BaseView.Mode.EXTERIOR, "road travel forces the displayed exterior")
		_check(shown_events == [BaseView.Mode.EXTERIOR], "view UI is notified of the road-forced exterior")
		_check(_all_riders_hidden(), "road travel presents all riders as aboard")
		_check(before == after, "presentation sync does not mutate travel, fuel, durability, inventory, or crew state")

		main.world.phase = "stopped"
		main.base_view.sync_travel_presentation()
		_check(main.base_view.shown_mode() == BaseView.Mode.INTERIOR, "stopped region restores selected interior")
		_check(shown_events == [BaseView.Mode.EXTERIOR, BaseView.Mode.INTERIOR], "view UI is notified when selected interior is restored")
		_check(_all_riders_visible(), "stopped interior restores rider visibility")

		main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
		main.world.phase = "turning"
		main.base_view.sync_travel_presentation()
		main.world.phase = "stopped"
		main.base_view.sync_travel_presentation()
		_check(main.base_view.shown_mode() == BaseView.Mode.EXTERIOR, "selected exterior persists after return travel")
	# The live road fixture must place generated fauna on the same route as the
	# mounted hunt origin; this is visual alignment only and changes no range or
	# hunt authorisation rule.
	var began_road: bool = main.world.request("b_forest")
	_check(began_road, "first-region map can still request the existing A-to-B road")
	if began_road:
		# This presentation fixture is not validating crew departure readiness;
		# archive the stopped-site rows as the normal departing state machine does,
		# then begin the accepted leg deterministically before inspecting road fauna.
		main.world._archive()
		main.world.start_leg()
		main.world._ensure_location()
		await process_frame
		var live_layout: Dictionary = TravelLanePresentation.road_layout(main)
		var road_rows: Dictionary = main.world.locations.get(main.world.key(), {})
		var route_fauna: Array = road_rows.values().filter(func(row): return str(row.get("type", "")) == "creature")
		_check(int(live_layout.get("strip_count", 0)) == 1 and not route_fauna.is_empty(), "moving A-to-B keeps one visual route with its generated normal fauna")
		for row in route_fauna:
			var lane_ground_y := float(live_layout.get("ground_y", -1.0))
			var data: Dictionary = row.get("data", {})
			var position: Vector2 = data.get("position", Vector2(-1.0, -1.0))
			_check(is_equal_approx(position.y, lane_ground_y), "generated road fauna y %.1f shares the single mounted-hunt route y %.1f" % [position.y, lane_ground_y])
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("== travel lane presentation: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
