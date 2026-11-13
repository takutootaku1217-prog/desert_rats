extends SceneTree
## Real Godot/X11 evidence for the normal-role recovery → upgrade → recovery
## checkpoint.  It never replaces the regular crew with single_worker_demo,
## and it only records post-draw pixels from the live viewport.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

const STEP := 0.2
const FIRST_SORTIE_SECONDS := 180.0
const HOME_WORK_SECONDS := 120.0
const CAPTURE_TIMEOUT_TICKS := 900
const MEASUREMENT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/normal_haul_frame_progression.json"
const ROOT_URI := "res://prototypes/recovery_map_lab/evidence/normal_haul_frame_runtime_v11"
const HUD_URI := "res://prototypes/recovery_map_lab/evidence/normal_haul_frame_runtime_v11/normal_haul_frame_hud_departure.png"
const LOADED_URI := "res://prototypes/recovery_map_lab/evidence/normal_haul_frame_runtime_v11/normal_haul_frame_harvester_loaded.png"
const DEPOT_URI := "res://prototypes/recovery_map_lab/evidence/normal_haul_frame_runtime_v11/normal_haul_frame_depot_after_unload.png"
const RESULT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime/normal_haul_frame_render_capture_v11.json"

var main
var field
var screenshots := {}
var first_sortie := {}
var upgrade := {}
var failure := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	SaveGame.disabled = true
	if DisplayServer.get_name() != "X11":
		_finish_failure("real normal evidence requires an X11 viewport")
		return
	var measured := _read_measurement()
	var selection: Dictionary = measured.get("selection", {})
	if not bool(selection.get("ok", false)) or str(selection.get("case", "")) != "harvester_frame":
		_finish_failure("measured harvester selection unavailable")
		return
	if not await _fresh():
		_finish_failure("deterministic normal main could not start")
		return
	# This is an explicit pre-existing-progress checkpoint, not quarry loot.
	# The hide is still needed by the existing recipe; wood is consumed by the
	# existing workbench/frame flow below.
	main.storage.store_owned(GameData.Item.HIDE, 1, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.WOOD, 5, Inventory.SOURCE_TRANSFER)
	first_sortie = await _first_sortie()
	if not bool(first_sortie.get("ok", false)):
		_finish_failure(str(first_sortie.get("reason", "first normal sortie")))
		return
	upgrade = await _build_and_equip(0)
	if not bool(upgrade.get("ok", false)):
		_finish_failure(str(upgrade.get("reason", "existing upgrade craft")))
		return
	if not await _move_to_quarry():
		_finish_failure("upgraded A→B→C travel")
		return
	var created: Dictionary = RouteSession.create_from_game(main, "normal-haul-frame-render-v11", {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		_finish_failure(str(created.get("reason", "normal session")))
		return
	var session = created.session
	if session.is_single_worker_demo():
		_finish_failure("single_worker_demo must not replace normal roles")
		return
	var harvester: Dictionary = session.actors.get("worker:0", {})
	if str(harvester.get("role", "")) != "harvest" or int(harvester.get("work_support", -1)) != GameData.Item.HAUL_FRAME or int(harvester.get("carry_limit", 0)) != GameData.HAUL_FRAME_LIMIT:
		_finish_failure("selected harvester snapshot was not preserved")
		return
	var entry_resources := _resource_snapshot(session)
	var entry_roles := _normal_role_snapshot(session)
	var measured_selected: Dictionary = measured.get("harvester_frame", {})
	var measured_conditions: Dictionary = measured.get("comparability", {})
	if not _json_equivalent(entry_resources, measured_selected.get("entry_resources", {})) or not _json_equivalent(entry_roles, measured_selected.get("entry_roles", {})) or session.dock_count != int(measured_conditions.get("dock_count", -1)) or int(main.get_meta("diagnostic_seed", -1)) != int(measured_conditions.get("seed", -1)):
		_finish_failure("live capture entry does not match measured normal benchmark", {
			"actual_entry_resources": entry_resources,
			"expected_entry_resources": measured_selected.get("entry_resources", {}),
			"actual_entry_roles": entry_roles,
			"expected_entry_roles": measured_selected.get("entry_roles", {}),
			"actual_entry_dock_count": session.dock_count,
			"expected_entry_dock_count": int(measured_conditions.get("dock_count", -1)),
			"actual_entry_seed": int(main.get_meta("diagnostic_seed", -1)),
			"expected_entry_seed": int(measured_conditions.get("seed", -1)),
		})
		return
	main.visible = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	field = FieldAdapter.new()
	field.configure(main, session)
	layer.add_child(field)
	# The capture advances this real adapter by deterministic simulation ticks.
	# It records still images only, so it makes no claim about real-time video.
	field.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	await RenderingServer.frame_post_draw
	if field.detail_label == null or not field.detail_label.text.contains("採掘役") or not field.detail_label.text.contains("背負いフレーム") or not field.detail_label.text.contains("便5"):
		_finish_failure("normal HUD does not reflect session support snapshot")
		return
	if not _save_viewport(HUD_URI):
		_finish_failure("normal HUD screenshot")
		return
	var depot_before := int(session.state_summary().get("depot", 0))
	var loaded_observation := {}
	var depot_observation := {}
	var conservation_ok := true
	for unused in CAPTURE_TIMEOUT_TICKS:
		field._process(STEP)
		await RenderingServer.frame_post_draw
		var summary: Dictionary = session.state_summary()
		conservation_ok = conservation_ok and bool(summary.get("conservation_ok", false))
		if not conservation_ok:
			_finish_failure("normal capture session violated conservation")
			return
		harvester = session.actors.get("worker:0", {})
		if loaded_observation.is_empty() and int(harvester.get("carry_n", 0)) > 0:
			if not _save_viewport(LOADED_URI):
				_finish_failure("harvester loaded screenshot")
				return
			loaded_observation = _observation(harvester, summary)
		if depot_observation.is_empty() and int(summary.get("depot", 0)) > depot_before:
			if not _save_viewport(DEPOT_URI):
				_finish_failure("post-unload depot screenshot")
				return
			depot_observation = _observation(harvester, summary)
		if not loaded_observation.is_empty() and not depot_observation.is_empty():
			var result := {
				"schema": 1,
				"display_server": DisplayServer.get_name(),
				"mode": "normal_roles",
				"normal_mode": not session.is_single_worker_demo(),
				"normal_user_save_touched": false,
				"capture_method": "real X11 Godot viewport; deterministic 0.2-second session ticks; still PNGs only, no generated/interpolated frames",
				"prepared_checkpoint": measured.get("prepared_checkpoint", {}),
				"first_sortie": first_sortie,
				"upgrade": upgrade,
				"selection": selection,
				"comparison": {
					"baseline": measured.get("baseline", {}).get("metrics", {}),
					"harvester_frame": measured.get("harvester_frame", {}).get("metrics", {}),
					"carrier_frame": measured.get("carrier_frame", {}).get("metrics", {}),
				},
				"entry_resources": entry_resources,
				"entry_roles": entry_roles,
				"entry_dock_count": session.dock_count,
				"entry_seed": int(main.get_meta("diagnostic_seed", -1)),
				"entry_actor": _actor_summary(session.actors.get("worker:0", {})),
				"screenshots": screenshots,
				"loaded_observation": loaded_observation,
				"depot_observation": depot_observation,
				"depot_before": depot_before,
				"session": summary,
				"conservation_ok": conservation_ok,
				"screenshot_error": 0,
			}
			if not _write_result(result):
				_finish_failure("render result write")
				return
			print("NORMAL_HAUL_FRAME_CAPTURE_COMPLETE ", DEPOT_URI)
			quit()
			return
	_finish_failure("normal HUD did not reach both loaded and depot-increased states")

func _read_measurement() -> Dictionary:
	if not FileAccess.file_exists(MEASUREMENT_URI):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(MEASUREMENT_URI)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}

func _fresh() -> bool:
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
	return main.world.region == "a_start" and main.world.phase == "stopped" and main.workers.size() == 3

func _world_step() -> void:
	main._process(STEP)

func _home_step() -> void:
	main._process(STEP)
	for worker in main.workers:
		worker._process(STEP)

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
			return {"ok": false, "reason": str(projection.get("reason", "worker projection")), "conservation_ok": false}
		conservation_ok = conservation_ok and session.conservation_ok()
		if predicate.call():
			return {"ok": true, "conservation_ok": conservation_ok, "elapsed": float(session.elapsed)}
		if frame % 48 == 0:
			await process_frame
	return {"ok": bool(predicate.call()), "conservation_ok": conservation_ok, "elapsed": float(session.elapsed)}

func _resource_snapshot(session) -> Dictionary:
	var result := {}
	for raw_resource_id in session.resources:
		var resource_id := str(raw_resource_id)
		var row: Dictionary = session.resources[raw_resource_id]
		result[resource_id] = {"item": int(row.get("item", -1)), "initial": int(row.get("initial", 0)), "remaining": int(row.get("remaining", 0))}
	return result

func _normal_role_snapshot(session) -> Dictionary:
	var result := {}
	for raw_actor_id in session.actors:
		var actor_id := str(raw_actor_id)
		var actor: Dictionary = session.actors[raw_actor_id]
		result[actor_id] = {
			"role": str(actor.get("role", "")),
			"support": int(actor.get("work_support", -1)),
			"carry_limit": int(actor.get("carry_limit", 0)),
			"direct_depot_loop": bool(actor.get("direct_depot_loop", false)),
			"presentation_hidden": bool(actor.get("presentation_hidden", false)),
		}
	return result

## JSON parses integral result values as floats while the live session keeps
## them as ints. Compare every shape/key exactly, normalizing only numeric
## representation so a real value mismatch still rejects the capture.
func _json_equivalent(actual: Variant, expected: Variant) -> bool:
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size():
			return false
		for key in actual:
			if not expected.has(key) or not _json_equivalent(actual[key], expected[key]):
				return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			return false
		for index in actual.size():
			if not _json_equivalent(actual[index], expected[index]):
				return false
		return true
	if (actual is int or actual is float) and (expected is int or expected is float):
		return is_equal_approx(float(actual), float(expected))
	return actual == expected

func _stock_for_session(session) -> int:
	var total := 0
	var seen := {}
	for resource_id in session.resources:
		var item := int(session.resources[resource_id].get("item", -1))
		if item >= 0 and not seen.has(item):
			seen[item] = true
			total += main.storage.count_of(item)
	return total

func _first_sortie() -> Dictionary:
	if not await _move_to_quarry():
		return {"ok": false, "reason": "A→B→C移動失敗"}
	var created: Dictionary = RouteSession.create_from_game(main, "normal-haul-frame-render-first", {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		return {"ok": false, "reason": str(created.get("reason", "session作成失敗"))}
	var session = created.session
	var before := _resource_snapshot(session)
	var ready: Dictionary = await _advance_session(session, func(): return int(session.depot_stock.get(GameData.Item.IRON_ORE, 0)) >= 1, FIRST_SORTIE_SECONDS)
	if not bool(ready.get("ok", false)):
		return {"ok": false, "reason": "C初回回収で鉄鉱石1へ到達できない"}
	var depot: Dictionary = session.depot_stock.duplicate(true)
	session.request_recall()
	var recalled: Dictionary = await _advance_session(session, func(): return session.phase == "ready_to_exit", 100.0)
	if not bool(recalled.get("ok", false)):
		return {"ok": false, "reason": "初回sessionが安全帰還できない"}
	var storage_before := _stock_for_session(session)
	var committed: Dictionary = session.commit_to_game(main)
	var repeated: Dictionary = session.commit_to_game(main)
	var storage_after := _stock_for_session(session)
	if not bool(committed.get("ok", false)) or not bool(repeated.get("already_committed", false)) or storage_after != storage_before + int(session.state_summary().depot):
		return {"ok": false, "reason": "初回commitの保存則失敗"}
	if not await _move_to_start():
		return {"ok": false, "reason": "初回C→B→A帰還失敗"}
	return {
		"ok": true,
		"mode": "normal_roles",
		"source_before": before,
		"source_after": _resource_snapshot(session),
		"depot": depot,
		"elapsed": float(session.elapsed),
		"conservation_ok": bool(recalled.get("conservation_ok", false)) and session.conservation_ok(),
		"storage_delta": storage_after - storage_before,
	}

func _configure_home_workers() -> void:
	main.refill_settings = {}
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.set_priority(job, 0)
	main.workers[0].set_priority(GameData.Job.HAUL, 5)
	main.workers[1].set_priority(GameData.Job.PROCESS, 5)

func _advance_home_until(predicate: Callable, seconds: float) -> bool:
	for frame in ceili(seconds / STEP):
		_home_step()
		if predicate.call():
			return true
		if frame % 48 == 0:
			await process_frame
	return bool(predicate.call())

func _move_material_to_workshop(item: int, amount: int) -> bool:
	if main.request_transfer(item, amount, "to_workshop") != amount:
		return false
	return await _advance_home_until(func(): return main.workshop_count(item) >= amount, HOME_WORK_SECONDS)

func _craft_one(id: String, output_item: int) -> bool:
	if main.request_craft(id, 1) != 1:
		return false
	return await _advance_home_until(func(): return main.storage.count_of(output_item) >= 1, HOME_WORK_SECONDS)

func _build_and_equip(target_index: int) -> Dictionary:
	_configure_home_workers()
	if not main.has_facility("workbench"):
		if not main.request_build("workbench"):
			return {"ok": false, "reason": main.build_blocked_reason("workbench")}
		if not await _advance_home_until(func(): return main.has_facility("workbench"), HOME_WORK_SECONDS):
			return {"ok": false, "reason": "既存ワークベンチ建設が完了しない"}
	if not await _move_material_to_workshop(GameData.Item.IRON_ORE, 1) or not await _craft_one("smelt", GameData.Item.IRON):
		return {"ok": false, "reason": "C由来鉄鉱石を既存精錬へ通せない"}
	for row in [{"item": GameData.Item.WOOD, "n": 2}, {"item": GameData.Item.HIDE, "n": 1}, {"item": GameData.Item.IRON, "n": 1}]:
		if not await _move_material_to_workshop(int(row.item), int(row.n)):
			return {"ok": false, "reason": "既存作業場へ材料を運べない"}
	if not await _craft_one("haul_frame", GameData.Item.HAUL_FRAME):
		return {"ok": false, "reason": "既存背負いフレーム製作が完了しない"}
	var worker = main.workers[target_index]
	if not main.equip_work_support(worker, GameData.Item.HAUL_FRAME):
		return {"ok": false, "reason": main.work_support_change_reason(worker, true, GameData.Item.HAUL_FRAME)}
	return {
		"ok": true,
		"equipped_worker": target_index,
		"equipped_name": str(worker.char_name),
		"equipped_limit": int(worker.carry_limit()),
		"cost": {"workbench_wood": 3, "haul_frame_wood": 2, "haul_frame_hide": 1, "haul_frame_iron": 1, "smelt_tank_fuel": 3},
	}

func _actor_summary(actor: Dictionary) -> Dictionary:
	return {
		"id": str(actor.get("id", "worker:0")),
		"name": str(actor.get("name", "")),
		"role": str(actor.get("role", "")),
		"work_support": int(actor.get("work_support", -1)),
		"carry_limit": int(actor.get("carry_limit", 0)),
	}

func _observation(actor: Dictionary, summary: Dictionary) -> Dictionary:
	return {
		"elapsed": float(field.session.elapsed),
		"actor": _actor_summary(actor),
		"state": str(actor.get("state", "")),
		"carried": int(actor.get("carry_n", 0)),
		"source_remaining": int(summary.get("source_remaining", 0)),
		"relay": int(summary.get("relay", 0)),
		"depot": int(summary.get("depot", 0)),
		"conservation_ok": bool(summary.get("conservation_ok", false)),
	}

func _save_viewport(uri: String) -> bool:
	var path := ProjectSettings.globalize_path(uri)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var image: Image = root.get_texture().get_image()
	if not _has_canyon_render_signature(image):
		screenshots[uri] = {"error": "render signature missing"}
		return false
	var error := image.save_png(path)
	screenshots[uri] = {"error": error, "render_signature": "canyon-ore-and-amber-base", "world_phase": main.world.phase, "world_region": main.world.region}
	return error == OK

func _has_canyon_render_signature(image: Image) -> bool:
	if image == null or image.get_width() != 1280 or image.get_height() != 720:
		return false
	var samples := [Vector2i(8, 8), Vector2i(180, 210), Vector2i(250, 300), Vector2i(580, 500), Vector2i(900, 500), Vector2i(1180, 170), Vector2i(1100, 620)]
	var distinct := {}
	for point in samples:
		distinct[image.get_pixel(point.x, point.y).to_rgba32()] = true
	return distinct.size() >= 5 and _contains_cyan_ore(image) and _contains_amber_base(image)

func _contains_cyan_ore(image: Image) -> bool:
	for y in range(110, 410, 12):
		for x in range(60, 470, 12):
			var color := image.get_pixel(x, y)
			if color.a > 0.8 and color.b > color.r * 1.20 and color.g > color.r * 1.08:
				return true
	return false

func _contains_amber_base(image: Image) -> bool:
	for y in range(390, 650, 12):
		for x in range(740, 1180, 12):
			var color := image.get_pixel(x, y)
			if color.a > 0.8 and color.r > 0.62 and color.g > 0.28 and color.g < color.r and color.b < color.g * 0.92:
				return true
	return false

func _write_result(result: Dictionary) -> bool:
	var path := ProjectSettings.globalize_path(RESULT_URI)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	return true

func _finish_failure(reason: String, details := {}) -> void:
	failure = reason
	var result := {"display_server": DisplayServer.get_name(), "mode": "normal_roles", "screenshots": screenshots, "failure": failure, "normal_user_save_touched": false}
	for key in details:
		result[key] = details[key]
	_write_result(result)
	print("NORMAL_HAUL_FRAME_CAPTURE_FAILED ", reason)
	quit(1)
