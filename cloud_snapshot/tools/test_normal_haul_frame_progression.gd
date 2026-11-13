extends SceneTree
## Deterministic normal-role progression witness.
##
## The implementation uses existing Main build/craft/equip APIs and normal
## bridge sessions; it may never simulate the effect by editing session cargo,
## depot, source, or work_support directly.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.2
const FIRST_SORTIE_SECONDS := 180.0
const HOME_WORK_SECONDS := 120.0
## Keep the old 20-second sample as evidence. Regenerated one-unit stone
## heads now precede ore, so an upgraded load can still be at relay/carried
## there. End at a physical boundary, never when a positive delta appears:
## finish the in-flight baseline carrier leg, then one full pickup/dock/return
## cycle starting after that sample. All cases run the identical tick count.
const SAMPLE_SECONDS := 20.0
const MAX_POST_SAMPLE_SECONDS := 20.0
var benchmark_ticks := roundi(SAMPLE_SECONDS / STEP)
const OUTPUT_FILE := "normal_haul_frame_progression.json"

const CASES := {
	"baseline": -1,
	"harvester_frame": 0,
	"carrier_frame": 1,
}

var fails := 0
var main

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	var result: Dictionary = await _run_progression_cases()
	_check(bool(result.get("ok", false)), "進行済みcheckpointから通常分業の回収→強化→次回回収を実行")
	_check(result.has("prepared_checkpoint"), "皮・木材の既存進行前提とC由来の鉄鉱石を結果へ明記")
	_check(bool(result.get("comparability", {}).get("ok", false)), "baselineと二つの合法装備位置の比較条件が一致")
	_check(bool(result.get("selection", {}).get("ok", false)), "非飽和の同一時間でdepot増を実測した装備位置だけを選択")
	_check(bool(result.get("boundaries", {}).get("ok", false)), "保存則・撤退・閉鎖再開・満杯・保存復元・二重確定を維持")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)

func _run_progression_cases() -> Dictionary:
	var cases := {}
	for case_name in CASES:
		cases[case_name] = await _run_case(str(case_name), int(CASES[case_name]))
	var comparability := _compare_cases(cases)
	var selection := _select_case(cases, comparability)
	var boundary_case := str(selection.get("case", "harvester_frame"))
	var boundaries := await _run_boundary_probe(boundary_case, int(CASES.get(boundary_case, 0)))
	var result := {
		"ok": bool(comparability.get("ok", false)) and bool(selection.get("recorded", false)) and bool(boundaries.get("ok", false)),
		"schema": 1,
		"mode": "normal_roles",
		"prepared_checkpoint": {
			"source": "既存進行の狩猟由来の皮と、ワークベンチ＋フレーム用に残した木材を持つ開始状態",
			"seeded_before_first_sortie": {"hide": 1, "wood": 5},
			"not_quarry_loot": ["hide", "iron"],
			"workbench": "最初の帰還後に既存request_buildで建設",
			"fuel": "初期の既存車体タンクをC由来鉄鉱石の精錬で3消費",
		},
		"first_sortie": {
			"baseline": cases.get("baseline", {}).get("first_sortie", {}),
			"harvester_frame": cases.get("harvester_frame", {}).get("first_sortie", {}),
			"carrier_frame": cases.get("carrier_frame", {}).get("first_sortie", {}),
		},
		"baseline": cases.get("baseline", {}),
		"harvester_frame": cases.get("harvester_frame", {}),
		"carrier_frame": cases.get("carrier_frame", {}),
		"cost": {
			"workbench": {"wood": 3},
			"haul_frame": {"wood": 2, "hide": 1, "iron": 1, "tank_fuel_for_iron": 3},
		},
		"comparability": comparability,
		"selection": selection,
		"boundaries": boundaries,
	}
	_write_result(result)
	_free_main()
	return result

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
	return main.world.region == "a_start" and main.world.phase == "stopped" and main.workers.size() == 3

func _free_main() -> void:
	if main == null:
		return
	if is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null

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

func _advance_session(session, predicate: Callable, seconds: float, metrics := {}) -> Dictionary:
	var prior := {}
	var prior_depot := 0
	var conservation_ok := true
	for actor_id in session.actors:
		prior[str(actor_id)] = Dictionary(session.actors[actor_id]).duplicate(true)
	for frame in ceili(seconds / STEP):
		session.tick(STEP)
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return {"ok": false, "reason": str(projection.get("reason", "仲間投影失敗")), "conservation_ok": false}
		conservation_ok = conservation_ok and session.conservation_ok()
		if not metrics.is_empty():
			_collect_metrics(metrics, session, prior, prior_depot)
			prior_depot = int(session.state_summary().depot)
			for actor_id in session.actors:
				prior[str(actor_id)] = Dictionary(session.actors[actor_id]).duplicate(true)
		if predicate.call():
			return {"ok": true, "conservation_ok": conservation_ok, "elapsed": float(session.elapsed)}
		if frame % 48 == 0:
			await process_frame
	return {"ok": bool(predicate.call()), "conservation_ok": conservation_ok, "elapsed": float(session.elapsed)}

func _advance_session_ticks(session, tick_count: int, metrics := {}, finish_sample_cycle := false) -> Dictionary:
	var prior := {}
	var prior_depot := 0
	var conservation_ok := true
	for actor_id in session.actors:
		prior[str(actor_id)] = Dictionary(session.actors[actor_id]).duplicate(true)
	for frame in maxi(0, tick_count):
		session.tick(STEP)
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return {"ok": false, "reason": str(projection.get("reason", "仲間投影失敗")), "conservation_ok": false, "elapsed": float(session.elapsed)}
		conservation_ok = conservation_ok and session.conservation_ok()
		if not metrics.is_empty():
			_collect_metrics(metrics, session, prior, prior_depot)
			prior_depot = int(session.state_summary().depot)
			for actor_id in session.actors:
				prior[str(actor_id)] = Dictionary(session.actors[actor_id]).duplicate(true)
		if frame + 1 == roundi(SAMPLE_SECONDS / STEP):
			metrics["sample20"] = {"summary":session.state_summary(),"dock_unloads":int(metrics.get("dock_unloads",0)),"carrier_returns":int(metrics.get("transitions",{}).get("carry:to_relay→wait_relay",0)),"carrier_state":str(session.actors["worker:1"].state)}
		if metrics.has("sample20"):
			# Two completed unloads/returns: the already loaded leg plus one
			# whole subsequent round trip, independent of the measured benefit.
			metrics["post_sample_round_trip_complete"] = int(metrics.get("dock_unloads",0)) >= int(metrics.sample20.dock_unloads)+2 and int(metrics.get("transitions",{}).get("carry:to_relay→wait_relay",0)) >= int(metrics.sample20.carrier_returns)+2
			if finish_sample_cycle and metrics.post_sample_round_trip_complete: break
		if frame % 48 == 0:
			await process_frame
	return {"ok": true, "conservation_ok": conservation_ok, "elapsed": float(session.elapsed)}

func _collect_metrics(metrics: Dictionary, session, prior: Dictionary, prior_depot: int) -> void:
	var summary: Dictionary = session.state_summary()
	metrics["ticks"] = int(metrics.get("ticks", 0)) + 1
	metrics["conservation_ok"] = bool(metrics.get("conservation_ok", true)) and bool(summary.get("conservation_ok", false))
	metrics["peak_relay"] = maxi(int(metrics.get("peak_relay", 0)), int(summary.get("relay", 0)))
	metrics["peak_dock_queue"] = maxi(int(metrics.get("peak_dock_queue", 0)), int(summary.get("dock_queue", 0)))
	for raw_actor_id in session.actors:
		var actor_id := str(raw_actor_id)
		var actor: Dictionary = session.actors[raw_actor_id]
		var state := str(actor.get("state", ""))
		var role := str(actor.get("role", ""))
		var state_seconds: Dictionary = metrics.get("state_seconds", {})
		state_seconds["%s:%s" % [role, state]] = float(state_seconds.get("%s:%s" % [role, state], 0.0)) + STEP
		metrics["state_seconds"] = state_seconds
		if role == "carry" and state == "wait_relay":
			metrics["carrier_wait_relay_seconds"] = float(metrics.get("carrier_wait_relay_seconds", 0.0)) + STEP
		var before: Dictionary = prior.get(actor_id, {})
		if str(before.get("state", "")) != state:
			var transitions: Dictionary = metrics.get("transitions", {})
			var key := "%s:%s→%s" % [role, str(before.get("state", "")), state]
			transitions[key] = int(transitions.get(key, 0)) + 1
			metrics["transitions"] = transitions
			if role == "carry" and state == "to_base" and int(actor.get("carry_n", 0)) > 0:
				metrics["carrier_loaded_departures"] = int(metrics.get("carrier_loaded_departures", 0)) + 1
			if role == "harvest" and state == "to_relay" and int(actor.get("carry_n", 0)) > 0:
				metrics["harvester_loaded_departures"] = int(metrics.get("harvester_loaded_departures", 0)) + 1
	var depot := int(summary.get("depot", 0))
	if depot > prior_depot:
		metrics["dock_unloads"] = int(metrics.get("dock_unloads", 0)) + 1
		metrics["depot_gain_events"] = int(metrics.get("depot_gain_events", 0)) + depot - prior_depot

func _resource_snapshot(session) -> Dictionary:
	var result := {}
	for raw_resource_id in session.resources:
		var resource_id := str(raw_resource_id)
		var row: Dictionary = session.resources[raw_resource_id]
		result[resource_id] = {
			"item": int(row.get("item", -1)),
			"initial": int(row.get("initial", 0)),
			"remaining": int(row.get("remaining", 0)),
		}
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

func _first_sortie() -> Dictionary:
	if not await _move_to_quarry():
		return {"ok": false, "reason": "A→B→C移動失敗"}
	var created: Dictionary = RouteSession.create_from_game(main, "normal-haul-frame-first", {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		return {"ok": false, "reason": str(created.get("reason", "session作成失敗"))}
	var session = created.session
	var before := _resource_snapshot(session)
	var ready: Dictionary = await _advance_session(session, func():
		return int(session.depot_stock.get(GameData.Item.IRON_ORE, 0)) >= 1,
		FIRST_SORTIE_SECONDS)
	if not bool(ready.get("ok", false)):
		return {"ok": false, "reason": "C初回回収で鉄鉱石1へ到達できない", "source_before": before, "summary": session.state_summary()}
	var depot: Dictionary = session.depot_stock.duplicate(true)
	session.request_recall()
	var recalled: Dictionary = await _advance_session(session, func(): return session.phase == "ready_to_exit", 100.0)
	if not bool(recalled.get("ok", false)):
		return {"ok": false, "reason": "初回sessionが安全帰還できない"}
	var storage_before := _stock_for_session(session)
	var committed: Dictionary = session.commit_to_game(main)
	var repeated: Dictionary = session.commit_to_game(main)
	if not bool(committed.get("ok", false)) or not bool(repeated.get("already_committed", false)):
		return {"ok": false, "reason": str(committed.get("reason", "初回commit失敗"))}
	var storage_after := _stock_for_session(session)
	if storage_after != storage_before + int(session.state_summary().depot):
		return {"ok": false, "reason": "初回commitの在庫保存則失敗"}
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

func _stock_for_session(session) -> int:
	var total := 0
	var seen := {}
	for resource_id in session.resources:
		var item := int(session.resources[resource_id].get("item", -1))
		if item >= 0 and not seen.has(item):
			seen[item] = true
			total += main.storage.count_of(item)
	return total

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
	if not await _move_material_to_workshop(GameData.Item.IRON_ORE, 1):
		return {"ok": false, "reason": "鉄鉱石を既存作業場へ運べない"}
	if not await _craft_one("smelt", GameData.Item.IRON):
		return {"ok": false, "reason": "既存精錬が完了しない"}
	for row in [
		{"item": GameData.Item.WOOD, "n": 2},
		{"item": GameData.Item.HIDE, "n": 1},
		{"item": GameData.Item.IRON, "n": 1},
	]:
		if not await _move_material_to_workshop(int(row.item), int(row.n)):
			return {"ok": false, "reason": "%sを既存作業場へ運べない" % ItemDB.name_of(int(row.item))}
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
		"workbench": main.has_facility("workbench"),
		"cost": {"workbench_wood": 3, "haul_frame_wood": 2, "haul_frame_hide": 1, "haul_frame_iron": 1, "smelt_tank_fuel": 3},
	}

func _second_sortie(case_name: String) -> Dictionary:
	if not await _move_to_quarry():
		return {"ok": false, "reason": "強化後A→B→C移動失敗"}
	var created: Dictionary = RouteSession.create_from_game(main, "normal-haul-frame-%s" % case_name, {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		return {"ok": false, "reason": str(created.get("reason", "比較session作成失敗"))}
	var session = created.session
	if bool(session.is_single_worker_demo()) or not str(session.tracked_worker_id()).is_empty():
		return {"ok": false, "reason": "単独追跡modeが通常比較へ混入"}
	var entry_resources := _resource_snapshot(session)
	var entry_roles := _normal_role_snapshot(session)
	var metrics := {
		"conservation_ok": true,
		"state_seconds": {},
		"transitions": {},
		"carrier_wait_relay_seconds": 0.0,
		"carrier_loaded_departures": 0,
		"harvester_loaded_departures": 0,
		"dock_unloads": 0,
		"depot_gain_events": 0,
		"peak_relay": 0,
		"peak_dock_queue": 0,
	}
	var baseline_case := case_name == "baseline"
	var limit := roundi((SAMPLE_SECONDS+MAX_POST_SAMPLE_SECONDS)/STEP) if baseline_case else benchmark_ticks
	var benchmark: Dictionary = await _advance_session_ticks(session, limit, metrics, baseline_case)
	if baseline_case:benchmark_ticks=int(metrics.get("ticks",0))
	var summary: Dictionary = session.state_summary()
	metrics["depot"] = int(summary.get("depot", 0))
	metrics["source_remaining"] = int(summary.get("source_remaining", 0))
	metrics["relay"] = int(summary.get("relay", 0))
	metrics["carried"] = int(summary.get("carried", 0))
	metrics["dock_queue"] = int(summary.get("dock_queue", 0))
	metrics["path_requests"] = int(summary.get("path_requests", 0))
	metrics["elapsed"] = float(session.elapsed)
	return {
		"ok": bool(benchmark.get("ok", false)) and bool(benchmark.get("conservation_ok", false)) and bool(metrics.get("conservation_ok", false)),
		"session": session,
		"entry_resources": entry_resources,
		"entry_roles": entry_roles,
		"metrics": metrics,
	}

func _run_case(case_name: String, target_index: int) -> Dictionary:
	if not await _fresh():
		return {"ok": false, "reason": "A地域のdeterministic mainを作成できない"}
	# C-site resources are the measured fixture. Reset the documented seed at
	# this boundary because earlier presentation/setup work may consume the
	# engine-wide RNG between independent cases.
	seed(int(main.get_meta("diagnostic_seed", 104729)))
	main.storage.store_owned(GameData.Item.HIDE, 1, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.WOOD, 5, Inventory.SOURCE_TRANSFER)
	var first_sortie: Dictionary = await _first_sortie()
	if not bool(first_sortie.get("ok", false)):
		return {"ok": false, "reason": str(first_sortie.get("reason", "初回回収失敗")), "first_sortie": first_sortie}
	var upgrade := {"ok": true, "mode": "baseline"}
	if target_index >= 0:
		upgrade = await _build_and_equip(target_index)
		if not bool(upgrade.get("ok", false)):
			return {"ok": false, "reason": str(upgrade.get("reason", "強化失敗")), "first_sortie": first_sortie, "upgrade": upgrade}
	var second: Dictionary = await _second_sortie(case_name)
	if not bool(second.get("ok", false)):
		return {"ok": false, "reason": str(second.get("reason", "次回C回収失敗")), "first_sortie": first_sortie, "upgrade": upgrade, "second": second}
	var response := {
		"ok": true,
		"case": case_name,
		"equipped_worker": target_index,
		"first_sortie": first_sortie,
		"upgrade": upgrade,
		"entry_resources": second.entry_resources,
		"entry_roles": second.entry_roles,
		"metrics": second.metrics,
	}
	_free_main()
	return response

func _compare_cases(cases: Dictionary) -> Dictionary:
	var baseline: Dictionary = cases.get("baseline", {})
	var harvester: Dictionary = cases.get("harvester_frame", {})
	var carrier: Dictionary = cases.get("carrier_frame", {})
	var baseline_first: Dictionary = baseline.get("first_sortie", {})
	var harvester_first: Dictionary = harvester.get("first_sortie", {})
	var carrier_first: Dictionary = carrier.get("first_sortie", {})
	var baseline_metrics: Dictionary = baseline.get("metrics", {})
	var harvester_metrics: Dictionary = harvester.get("metrics", {})
	var carrier_metrics: Dictionary = carrier.get("metrics", {})
	var all_ok: bool = bool(baseline.get("ok", false)) and bool(harvester.get("ok", false)) and bool(carrier.get("ok", false))
	var first_equal: bool = all_ok and baseline_first.get("source_after", {}) == harvester_first.get("source_after", {}) and baseline_first.get("source_after", {}) == carrier_first.get("source_after", {})
	var source_equal: bool = all_ok and baseline.get("entry_resources", {}) == harvester.get("entry_resources", {}) and baseline.get("entry_resources", {}) == carrier.get("entry_resources", {})
	var roles_equal: bool = all_ok and _roles_match_for_comparison(baseline.get("entry_roles", {}), harvester.get("entry_roles", {}), 0) and _roles_match_for_comparison(baseline.get("entry_roles", {}), carrier.get("entry_roles", {}), 1)
	var timing_equal: bool = all_ok and is_equal_approx(float(baseline_metrics.get("elapsed", 0.0)), (float(benchmark_ticks)*STEP)) and is_equal_approx(float(harvester_metrics.get("elapsed", 0.0)), (float(benchmark_ticks)*STEP)) and is_equal_approx(float(carrier_metrics.get("elapsed", 0.0)), (float(benchmark_ticks)*STEP))
	var baseline_non_saturated: bool = int(baseline_metrics.get("source_remaining", 0)) > 0
	var complete_round_trips: bool = bool(baseline_metrics.get("post_sample_round_trip_complete",false)) and bool(harvester_metrics.get("post_sample_round_trip_complete",false)) and bool(carrier_metrics.get("post_sample_round_trip_complete",false))
	return {
		"ok": all_ok and first_equal and source_equal and roles_equal and timing_equal and baseline_non_saturated and complete_round_trips,
		"seed": 104729,
		"fixed_tick": STEP,
		"benchmark_seconds": (float(benchmark_ticks)*STEP),
		"outpost_enabled": false,
		"dock_count": 1,
		"first_sortie_source_equal": first_equal,
		"second_sortie_source_equal": source_equal,
		"normal_role_contract_equal": roles_equal,
		"timing_equal": timing_equal,
		"baseline_non_saturated": baseline_non_saturated,
		"post_sample_round_trips_complete":complete_round_trips,
		"boundary":"Finish the in-flight 20-second baseline carrier leg, then one full pickup/dock/return. No positive-delta stopping rule.",
	}

func _roles_match_for_comparison(baseline: Dictionary, upgraded: Dictionary, expected_worker: int) -> bool:
	for actor_id in baseline:
		if not upgraded.has(actor_id):
			return false
		var a: Dictionary = baseline[actor_id]
		var b: Dictionary = upgraded[actor_id]
		if str(a.get("role", "")) != str(b.get("role", "")) or bool(a.get("direct_depot_loop", false)) or bool(b.get("direct_depot_loop", false)) or bool(a.get("presentation_hidden", false)) or bool(b.get("presentation_hidden", false)):
			return false
		var index := int(str(actor_id).trim_prefix("worker:"))
		if index == expected_worker:
			if int(a.get("support", -1)) != -1 or int(a.get("carry_limit", 0)) != GatherDB.CARRY_MAX or int(b.get("support", -1)) != GameData.Item.HAUL_FRAME or int(b.get("carry_limit", 0)) != GameData.HAUL_FRAME_LIMIT:
				return false
		elif int(a.get("support", -1)) != int(b.get("support", -1)) or int(a.get("carry_limit", 0)) != int(b.get("carry_limit", 0)):
			return false
	return true

func _select_case(cases: Dictionary, comparable: Dictionary) -> Dictionary:
	var baseline_depot := int(cases.get("baseline", {}).get("metrics", {}).get("depot", 0))
	var candidates := []
	for case_name in ["harvester_frame", "carrier_frame"]:
		var row: Dictionary = cases.get(case_name, {})
		var metrics: Dictionary = row.get("metrics", {})
		candidates.append({
			"case": case_name,
			"depot": int(metrics.get("depot", 0)),
			"depot_delta": int(metrics.get("depot", 0)) - baseline_depot,
			"source_remaining_delta": int(cases.get("baseline", {}).get("metrics", {}).get("source_remaining", 0)) - int(metrics.get("source_remaining", 0)),
			"carrier_wait_relay_delta": float(cases.get("baseline", {}).get("metrics", {}).get("carrier_wait_relay_seconds", 0.0)) - float(metrics.get("carrier_wait_relay_seconds", 0.0)),
		})
	candidates.sort_custom(func(a, b): return int(a.depot_delta) > int(b.depot_delta))
	var best: Dictionary = candidates[0] if not candidates.is_empty() else {}
	var positive := bool(comparable.get("ok", false)) and int(best.get("depot_delta", 0)) > 0
	return {
		"recorded": bool(comparable.get("ok", false)),
		"ok": positive,
		"case": str(best.get("case", "")) if positive else "",
		"criterion": "同一%.1f秒で本編へ確定可能なdepot量がbaselineを上回ること" % (float(benchmark_ticks)*STEP),
		"baseline_depot": baseline_depot,
		"candidates": candidates,
		"no_improvement_reason": "同一条件ではdepot差が正でない。数値を変えず、装備位置の効果なしとして扱う。" if bool(comparable.get("ok", false)) and not positive else "",
	}

func _run_boundary_probe(case_name: String, target_index: int) -> Dictionary:
	if not await _fresh():
		return {"ok": false, "reason": "境界用main作成失敗"}
	main.storage.store_owned(GameData.Item.HIDE, 1, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.WOOD, 5, Inventory.SOURCE_TRANSFER)
	var first: Dictionary = await _first_sortie()
	if not bool(first.get("ok", false)):
		return {"ok": false, "reason": str(first.get("reason", "境界用初回回収失敗"))}
	var upgrade: Dictionary = await _build_and_equip(target_index)
	if not bool(upgrade.get("ok", false)):
		return {"ok": false, "reason": str(upgrade.get("reason", "境界用強化失敗"))}
	if not await _move_to_quarry():
		return {"ok": false, "reason": "境界用C再入場失敗"}
	var created: Dictionary = RouteSession.create_from_game(main, "normal-haul-frame-boundary-%s" % case_name, {"outpost_enabled": false})
	if not bool(created.get("ok", false)):
		return {"ok": false, "reason": str(created.get("reason", "境界session作成失敗"))}
	var session = created.session
	var equipped_actor_id := "worker:%d" % target_index
	var equipment_snapshot_ok := int(session.actors[equipped_actor_id].get("work_support", -1)) == GameData.Item.HAUL_FRAME and int(session.actors[equipped_actor_id].get("carry_limit", 0)) == GameData.HAUL_FRAME_LIMIT
	session.set_all_routes_closed(true)
	var closed: Dictionary = await _advance_session(session, func(): return str(session.actors["worker:0"].get("state", "")) == "safe_wait", 8.0)
	var requests_before := int(session.path_requests)
	for unused in 20:
		session.tick(STEP)
	var no_path_thrash := int(session.path_requests) == requests_before
	session.set_all_routes_closed(false)
	var reopened: Dictionary = await _advance_session(session, func(): return int(session.state_summary().depot) > 0, 100.0)
	var saved: Dictionary = session.save_project_fixture("normal_haul_frame_boundary.json")
	var loaded: Dictionary = RouteSession.load_project_fixture("normal_haul_frame_boundary.json")
	var loaded_ok: bool = bool(loaded.get("ok", false)) and bool(loaded.session.conservation_ok()) if bool(loaded.get("ok", false)) else false
	session.request_recall()
	var recalled: Dictionary = await _advance_session(session, func(): return session.phase == "ready_to_exit", 100.0)
	var original_bonus := int(main.storage.capacity_bonus)
	main.storage.capacity_bonus = -CargoDB.CAPACITY
	var before_reject := _stock_for_session(session)
	var rejected: Dictionary = session.commit_to_game(main)
	var safe_reject: bool = not bool(rejected.get("ok", false)) and _stock_for_session(session) == before_reject and session.phase == "ready_to_exit"
	main.storage.capacity_bonus = original_bonus
	var committed: Dictionary = session.commit_to_game(main)
	var repeated: Dictionary = session.commit_to_game(main)
	var committed_ok: bool = bool(committed.get("ok", false)) and bool(repeated.get("already_committed", false))
	var ok: bool = equipment_snapshot_ok and bool(closed.get("ok", false)) and no_path_thrash and bool(reopened.get("ok", false)) and bool(reopened.get("conservation_ok", false)) and bool(saved.get("ok", false)) and loaded_ok and bool(recalled.get("ok", false)) and safe_reject and committed_ok
	_free_main()
	return {
		"ok": ok,
		"equipment_snapshot": equipment_snapshot_ok,
		"route_closure_safe_wait": bool(closed.get("ok", false)) and no_path_thrash,
		"route_reopen": bool(reopened.get("ok", false)) and bool(reopened.get("conservation_ok", false)),
		"project_local_save_restore": bool(saved.get("ok", false)) and loaded_ok,
		"full_storage_reject": safe_reject,
		"recall_and_single_commit": bool(recalled.get("ok", false)) and committed_ok,
		"fresh_process_restore": "既存test_a_recovery_bridge.gdを別途実行して確認する",
	}

func _write_result(result: Dictionary) -> void:
	var path := RouteSession.project_fixture_path(OUTPUT_FILE)
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
