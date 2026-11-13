extends SceneTree
## C採石場の入口→中継停車縦切り。通常SaveGameを使わず、本編の有限資源と
## BaseStorageを実際に読む。vertical_slice未指定の通常分業は変更しない。

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.5
const FIXTURE := "canyon_parking_vertical_slice_fixture.json"

var main
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _fresh()
	await _profile_and_reposition_contract()
	if fails == 0:
		await _inflight_reposition_contract()
	if fails == 0:
		await _capacity_hold_and_resume_contract()
	if fails == 0:
		await _capacity_refresh_accounting_contract()
	if fails == 0:
		await _recall_capacity_priority_contract()
	if fails == 0:
		await _cancel_and_depletion_contract()
	if fails == 0:
		await _fixture_and_priority_contract()
	_free_main()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _free_main() -> void:
	if main != null and is_instance_valid(main):
		root.remove_child(main)
		main.free()
	main = null

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

func _step_world() -> void:
	main._process(STEP)
	await process_frame

func _move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 240:
		await _step_world()
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return main.world.phase == "stopped" and main.world.region == destination

func _move_to_quarry() -> bool:
	if main.world.region == "a_start" and not await _move_leg("b_forest"):
		return false
	if main.world.region == "b_forest":
		return await _move_leg("c_quarry")
	return main.world.region == "c_quarry" and main.world.phase == "stopped"

func _make_session(tag: String, options: Dictionary):
	if not await _move_to_quarry():
		_check(false, tag + ": A→B→Cの既存横移動")
		return null
	var created: Dictionary = RouteSession.create_from_game(main, tag, options)
	_check(bool(created.get("ok", false)), tag + ": C有限資源と既存仲間からsessionを作成")
	return created.get("session", null)

func _advance_until(session, predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		session.tick(STEP)
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return false
		if predicate.call():
			return true
	return predicate.call()

func _has_state(session, wanted: String) -> bool:
	for actor_id in session.actors:
		if str(session.actors[actor_id].get("state", "")) == wanted:
			return true
	return false

func _profile_and_reposition_contract() -> void:
	print("-- 停車profile・小障害物整備・中継停車")
	var normal = await _make_session("parking-normal", {"outpost_enabled": false})
	if normal == null:
		return
	_check(normal.has_method("is_vertical_slice"), "通常sessionにも垂直slice照会APIが存在")
	if not normal.has_method("is_vertical_slice"):
		return
	_check(not bool(normal.call("is_vertical_slice")), "vertical_slice未指定では通常分業を維持")
	var session = await _make_session("parking-entry", {"outpost_enabled": false, "vertical_slice": true})
	if session == null:
		return
	var required := ["vertical_slice_profile", "parking_anchor", "request_intermediate_clearance", "request_reposition", "cancel_reposition", "is_vertical_slice"]
	for method in required:
		_check(session.has_method(method), "縦切りAPI %s が存在" % method)
	if required.any(func(method): return not session.has_method(method)):
		return
	_check(bool(session.call("is_vertical_slice")), "vertical_sliceは明示optionでのみ有効")
	var profile: Dictionary = session.call("vertical_slice_profile")
	_check(str(profile.get("parking_slot", "")) == "entry" and is_equal_approx(float(profile.get("entry_one_way_seconds", 0.0)), 24.0), "入口profileは24秒基準")
	_check(is_equal_approx(float(profile.get("relay_one_way_seconds", 0.0)), 14.0) and float(profile.get("relay_one_way_seconds", 100.0)) < float(profile.get("entry_one_way_seconds", 0.0)), "中継profileは14秒で入口より短い")
	var source_before: int = int(session.total_source_remaining())
	var early: Dictionary = session.call("request_reposition", "relay")
	_check(not bool(early.get("ok", true)), "小障害物整備前は中継停車を拒否")
	var clearance: Dictionary = session.call("request_intermediate_clearance")
	_check(bool(clearance.get("ok", false)), "既存護衛が小障害物整備を開始")
	var cleared := await _advance_until(session, func(): return str(session.state_summary().get("intermediate_access", "")) == "cleared", 20.0)
	_check(cleared and session.conservation_ok(), "整備完了まで資源保存則を維持")
	var reposition: Dictionary = session.call("request_reposition", "relay")
	_check(bool(reposition.get("ok", false)), "整備後は中継停車を開始")
	var relocated := await _advance_until(session, func(): return str(session.state_summary().get("parking_slot", "")) == "relay" and str(session.phase) == "local", 40.0)
	_check(relocated, "全員帰還後に中継停車へ移動")
	_check(session.total_source_remaining() == source_before and session.conservation_ok(), "停め直しは未採取資源を消失・重複させない")
	var relay_profile: Dictionary = session.call("vertical_slice_profile")
	_check(is_equal_approx(float(relay_profile.get("active_one_way_seconds", 0.0)), 14.0), "中継停車後は14秒profileを表示")
	session.set_all_routes_closed(true)
	var safely_waiting := await _advance_until(session, func(): return _has_state(session, "safe_wait"), 6.0)
	_check(safely_waiting and session.conservation_ok(), "停め直し後の全路閉鎖は安全待機")
	session.set_all_routes_closed(false)
	var restarted := await _advance_until(session, func(): return int(session.state_summary().get("depot", 0)) > 0, 70.0)
	_check(restarted and session.conservation_ok(), "経路再開後は中継停車から通常分業を再開")

func _inflight_reposition_contract() -> void:
	print("-- 運搬中貨物を含む停め直し")
	await _fresh()
	var session = await _make_session("parking-inflight-reposition", {"outpost_enabled": false, "vertical_slice": true})
	if session == null:
		return
	_check(bool(session.call("request_intermediate_clearance").get("ok", false)), "運搬中停め直し試験の整備開始")
	_check(await _advance_until(session, func(): return str(session.state_summary().get("intermediate_access", "")) == "cleared", 20.0), "運搬中停め直し試験の整備完了")
	var has_transit_cargo := await _advance_until(session, func():
		if int(session.state_summary().get("relay", 0)) != 0:
			return false
		for actor_id in session.actors:
			var actor: Dictionary = session.actors[actor_id]
			if str(actor.get("role", "")) == "harvest" and str(actor.get("state", "")) == "to_relay" and int(actor.get("carry_n", 0)) > 0:
				return true
		return false
	, 80.0)
	_check(has_transit_cargo, "採掘役がrelay未到着の貨物を持つ瞬間を検出")
	if not has_transit_cargo:
		return
	var reposition: Dictionary = session.call("request_reposition", "relay")
	_check(bool(reposition.get("ok", false)), "運搬中でも新規採取を止めて停め直しを開始")
	var relocated := await _advance_until(session, func(): return str(session.phase) == "local" and str(session.state_summary().get("parking_slot", "")) == "relay", 70.0)
	_check(relocated and int(session.state_summary().get("relay", -1)) == 0 and session.conservation_ok(), "運搬中貨物もrelayから回収して中継停車へ完了")

func _capacity_hold_and_resume_contract() -> void:
	print("-- 満載保持・容量回復・自動再開")
	await _fresh()
	var iron: int = int(GameData.Item.IRON_ORE)
	var original_bonus := int(main.storage.capacity_bonus)
	var room: int = int(main.storage.max_weight() - main.storage.current_weight() - main.storage.processing_reserve())
	main.storage.capacity_bonus = original_bonus - room + main.storage.item_weight(iron, 1)
	var session = await _make_session("parking-capacity", {"outpost_enabled": false, "vertical_slice": true})
	if session == null:
		return
	var held := await _advance_until(session, func():
		var summary: Dictionary = session.state_summary()
		return bool(summary.get("capacity_paused", false)) and int(summary.get("depot", 0)) > 0 and int(summary.get("carried", 0)) > 0,
		90.0)
	var paused: Dictionary = session.state_summary()
	_check(held and int(paused.get("depot", 0)) > 0 and int(paused.get("carried", 0)) > 0, "満載時は一部を収納し残りを仲間が保持")
	var remaining_before: int = int(session.total_source_remaining())
	for unused in 20:
		session.tick(STEP)
	_check(session.total_source_remaining() == remaining_before and session.conservation_ok(), "満載中は新規採取を止め保存則を維持")
	main.storage.capacity_bonus = original_bonus
	var refreshed: Dictionary = session.call("refresh_capacity_from_game", main)
	_check(bool(refreshed.get("ok", false)), "既存BaseStorageの空きを読み直す")
	var resumed := await _advance_until(session, func(): return not bool(session.state_summary().get("capacity_paused", true)) and int(session.state_summary().get("depot", 0)) > int(paused.get("depot", 0)), 20.0)
	_check(resumed and session.conservation_ok(), "容量回復後は保持荷物を一度だけ収納して自動再開")

func _capacity_refresh_accounting_contract() -> void:
	print("-- 投影済み手荷物を含む容量再読込")
	await _fresh()
	var iron: int = int(GameData.Item.IRON_ORE)
	var original_bonus: int = int(main.storage.capacity_bonus)
	var room: int = int(main.storage.max_weight() - main.storage.current_weight() - main.storage.processing_reserve())
	main.storage.capacity_bonus = original_bonus - room + main.storage.item_weight(iron, 1)
	var session = await _make_session("parking-capacity-accounting", {"outpost_enabled": false, "vertical_slice": true})
	if session == null:
		main.storage.capacity_bonus = original_bonus
		return
	var source_id := ""
	for resource_id in session.resources:
		var resource: Dictionary = session.resources[resource_id]
		if int(resource.get("item", -1)) == iron and int(resource.get("remaining", 0)) >= 4:
			source_id = str(resource_id)
			break
	var harvest_id := ""
	for actor_id in session.actors:
		if str(session.actors[actor_id].get("role", "")) == "harvest":
			harvest_id = str(actor_id)
			break
	_check(not source_id.is_empty() and not harvest_id.is_empty(), "容量再読込に実在する鉄鉱石と採掘役を使用")
	if source_id.is_empty() or harvest_id.is_empty():
		main.storage.capacity_bonus = original_bonus
		return
	var harvester: Dictionary = session.actors[harvest_id]
	harvester["carry_item"] = iron
	harvester["carry_n"] = 3
	harvester["state"] = "capacity_wait"
	session.resources[source_id]["remaining"] = int(session.resources[source_id].get("remaining", 0)) - 4
	session.depot_stock[iron] = int(session.depot_stock.get(iron, 0)) + 1
	session.capacity_paused = false
	var projection: Dictionary = session.apply_projection_to_workers(main)
	var captured_limit: int = int(session.field_capacity_limit_weight)
	var refreshed: Dictionary = session.call("refresh_capacity_from_game", main)
	_check(bool(projection.get("ok", false)) and session.conservation_ok(), "投影済み手荷物とdepotを保存則のまま構成")
	_check(int(refreshed.get("limit_weight", -1)) == captured_limit and bool(refreshed.get("capacity_paused", false)), "容量再読込は負の生空きへ手荷物を戻しても新しい収納枠を発明せず採取停止へ切り替える")
	main.storage.capacity_bonus = original_bonus

func _recall_capacity_priority_contract() -> void:
	print("-- 満載保持中の通常帰還優先")
	await _fresh()
	var iron: int = int(GameData.Item.IRON_ORE)
	var original_bonus: int = int(main.storage.capacity_bonus)
	var room: int = int(main.storage.max_weight() - main.storage.current_weight() - main.storage.processing_reserve())
	main.storage.capacity_bonus = original_bonus - room + main.storage.item_weight(iron, 1)
	var session = await _make_session("parking-recall-capacity", {"outpost_enabled": false, "vertical_slice": true})
	if session == null:
		main.storage.capacity_bonus = original_bonus
		return
	var held := await _advance_until(session, func():
		var summary: Dictionary = session.state_summary()
		return bool(summary.get("capacity_paused", false)) and int(summary.get("carried", 0)) > 0
	, 90.0)
	_check(held and session.conservation_ok(), "満載時に保持貨物を持つ仲間を実sessionで作成")
	if not held:
		main.storage.capacity_bonus = original_bonus
		return
	session.request_recall()
	_check(str(session.phase) == "recall", "通常撤退は満載保持より優先して帰還段階へ入る")
	var waiting_to_redock := await _advance_until(session, func(): return _has_state(session, "capacity_wait"), 20.0)
	_check(waiting_to_redock and session.conservation_ok(), "帰還中も入りきらない貨物は破棄せず容量待ちする")
	main.storage.capacity_bonus = original_bonus
	var refreshed: Dictionary = session.call("refresh_capacity_from_game", main)
	var ready := await _advance_until(session, func(): return str(session.phase) == "ready_to_exit", 40.0)
	_check(bool(refreshed.get("ok", false)) and ready and not bool(session.state_summary().get("capacity_paused", true)) and int(session.state_summary().get("carried", -1)) == 0 and session.conservation_ok(), "空き復帰後は保持貨物を一度だけ収納して通常帰還を完了")
	var committed: Dictionary = session.commit_to_game(main)
	_check(bool(committed.get("ok", false)), "帰還優先の収納後は本編確定を容量拒否せず一回だけ実行")

func _all_workers_waiting_at_parking(session) -> bool:
	for actor_id in session.actors:
		if str(session.actors[actor_id].get("state", "")) not in ["idle", "capacity_idle", "safe_wait"]:
			return false
	return true

func _cancel_and_depletion_contract() -> void:
	print("-- 停め直し取消・鉱床枯渇")
	await _fresh()
	var session = await _make_session("parking-cancel", {"outpost_enabled": false, "vertical_slice": true})
	if session == null:
		return
	_check(bool(session.call("request_intermediate_clearance").get("ok", false)), "取消試験の整備開始")
	_check(await _advance_until(session, func(): return str(session.state_summary().get("intermediate_access", "")) == "cleared", 20.0), "取消試験の整備完了")
	var started: Dictionary = session.call("request_reposition", "relay")
	_check(bool(started.get("ok", false)), "停め直しを開始")
	var repeated: Dictionary = session.call("request_reposition", "relay")
	_check(not bool(repeated.get("ok", true)), "移動入力連打は二重の停め直しを開始しない")
	var cancelled: Dictionary = session.call("cancel_reposition")
	_check(bool(cancelled.get("ok", false)) and str(session.phase) == "local" and str(session.state_summary().get("parking_slot", "")) == "entry" and session.conservation_ok(), "停め直し取消は入口停車と保存則を維持")

	await _fresh()
	var depleted = await _make_session("parking-depleted", {"outpost_enabled": false, "vertical_slice": true})
	if depleted == null:
		return
	var first_resource := ""
	for resource_id in depleted.resources:
		if first_resource.is_empty():
			first_resource = str(resource_id)
			depleted.resources[resource_id]["initial"] = 1
			depleted.resources[resource_id]["remaining"] = 1
		else:
			depleted.resources[resource_id]["initial"] = 0
			depleted.resources[resource_id]["remaining"] = 0
	_check(not first_resource.is_empty() and depleted.conservation_ok(), "枯渇試験を有限1資源へ縮小して保存則を維持")
	var exhausted := await _advance_until(depleted, func():
		var summary: Dictionary = depleted.state_summary()
		return int(summary.get("source_remaining", -1)) == 0 and int(summary.get("relay", -1)) == 0 and int(summary.get("carried", -1)) == 0 and int(summary.get("depot", 0)) > 0 and _all_workers_waiting_at_parking(depleted),
		100.0)
	_check(exhausted and depleted.conservation_ok(), "鉱床枯渇後は採取済み貨物だけ帰還し仲間は待機")

func _fixture_and_priority_contract() -> void:
	print("-- 保存読込・撤退優先")
	await _fresh()
	var session = await _make_session("parking-fixture", {"outpost_enabled": false, "vertical_slice": true})
	if session == null:
		return
	var clearance: Dictionary = session.call("request_intermediate_clearance")
	_check(bool(clearance.get("ok", false)), "保存前の整備開始")
	_check(await _advance_until(session, func(): return str(session.state_summary().get("intermediate_access", "")) == "cleared", 20.0), "保存前の整備完了")
	_check(bool(session.call("request_reposition", "relay").get("ok", false)), "保存前の停め直し開始")
	_check(await _advance_until(session, func(): return str(session.state_summary().get("parking_slot", "")) == "relay", 40.0), "保存前に中継停車へ到達")
	var saved: Dictionary = session.save_project_fixture(FIXTURE)
	_check(bool(saved.get("ok", false)), "通常user保存を使わず縦切りfixtureへ保存")
	var loaded: Dictionary = RouteSession.load_project_fixture(FIXTURE)
	_check(bool(loaded.get("ok", false)), "縦切りfixtureを読込")
	if bool(loaded.get("ok", false)):
		var restored = loaded.session
		_check(str(restored.state_summary().get("parking_slot", "")) == "relay" and str(restored.state_summary().get("intermediate_access", "")) == "cleared" and restored.conservation_ok(), "読込後も停車位置・整備・保存則を維持")
		restored.request_recall()
		_check(str(restored.phase) == "recall", "通常撤退は停め直しと別の優先状態")
