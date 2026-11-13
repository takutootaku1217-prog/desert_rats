extends SceneTree
## Current fixed-parking compatibility edition; original v17 file retained.
## Focused real-session witness for the first v17 path: an existing escort-held
## Haul Frame is handed to the harvest role at the relay.  This file uses a
## temporary in-memory Main fixture and never writes normal SaveGame data.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.5

var main
var session
var fails := 0
var projection_ok := true

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	SaveGame.disabled = true
	if not await _prepare():
		_finish()
		return
	_check(session.has_method("request_field_frame_to_harvest"), "現地フレーム引渡しはsessionの通常操作APIとして存在する")
	_check(session.has_method("cancel_field_frame_exchange"), "現地フレーム引渡しは取消APIを持つ")
	_check(session.has_method("equipment_status"), "装備指示の状態はHUD用の読み取りAPIで取得できる")
	if fails > 0:
		_finish()
		return
	_run_legacy_entry_compatibility()
	_run_unauthorized_support_restore_rejection()
	_run_equipment_command_conflicts()
	_run_field_exchange_route_closure_checks()
	if fails > 0:
		_finish()
		return
	await _run_field_handoff()
	await _run_return_handcart_exchange()
	_finish()

func _prepare() -> bool:
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
	if not await _move("b_forest") or not await _move("c_quarry"):
		_check(false, "既存横視点でC採石場へ移動")
		return false
	main.storage.store_owned(GameData.Item.HAUL_FRAME, 2, Inventory.SOURCE_TRANSFER)
	_check(main.equip_work_support(main.workers[2], GameData.Item.HAUL_FRAME), "既存倉庫APIで護衛役へ背負いフレームを装備")
	_check(main.equip_work_support(main.workers[1], GameData.Item.HAUL_FRAME), "既存倉庫APIで運搬役へ帰還交換前の背負いフレームを装備")
	if int(main.workers[2].work_support) != GameData.Item.HAUL_FRAME or int(main.workers[1].work_support) != GameData.Item.HAUL_FRAME:
		return false
	var created: Dictionary = RouteSession.create_from_game(main, "equipment-switch-v17-field", {"outpost_enabled": false, "vertical_slice": true})
	_check(bool(created.get("ok", false)), "既存C資源と通常3人分業から装備切替sessionを作成")
	if not bool(created.get("ok", false)):
		return false
	session = created.session
	return true

func _run_legacy_entry_compatibility() -> void:
	print("-- v17: 旧session読込互換")
	var restored_v3: Variant = null
	var legacy_ok := true
	for schema in [2, 3]:
		var legacy_data: Dictionary = session.to_dict()
		legacy_data["schema"] = schema
		legacy_data.erase("rescue")
		legacy_data.erase("field_frame_exchange")
		legacy_data.erase("return_handcart_exchange")
		for actor_id in legacy_data.get("actors", {}):
			var actor: Dictionary = legacy_data["actors"][actor_id]
			actor.erase("entry_weapon")
			actor.erase("entry_work_support")
			actor.erase("entry_tools")
		var restored: Dictionary = RouteSession.from_dict(legacy_data)
		var entry_seeded := false
		var projection := {"ok": false}
		if bool(restored.get("ok", false)):
			var legacy_session = restored.get("session", null)
			if legacy_session != null:
				var legacy_actor: Dictionary = legacy_session.actors.get("worker:1", {})
				entry_seeded = legacy_actor.has("entry_weapon") and legacy_actor.has("entry_work_support") and legacy_actor.has("entry_tools")
				projection = legacy_session.apply_projection_to_workers(main)
				if schema == 3:
					restored_v3 = legacy_session
		legacy_ok = legacy_ok and bool(restored.get("ok", false)) and entry_seeded and bool(projection.get("ok", false))
	_check(legacy_ok and restored_v3 != null, "v2〜v3互換読込はentry装備snapshotを補完し本編投影を維持する")
	if restored_v3 != null:
		# The rest of this witness uses the restored v3 session.  Its later real
		# handoff → recall → commit proves the seeded identity remains usable.
		session = restored_v3

func _run_unauthorized_support_restore_rejection() -> void:
	print("-- v17: 不正な装備所有者変更の拒否")
	var tampered: Dictionary = session.to_dict()
	var actor_rows: Dictionary = tampered.get("actors", {})
	var harvest: Dictionary = actor_rows.get("worker:0", {})
	var escort: Dictionary = actor_rows.get("worker:2", {})
	harvest["work_support"] = GameData.Item.HAUL_FRAME
	harvest["carry_limit"] = GameData.HAUL_FRAME_LIMIT
	escort["work_support"] = -1
	escort["carry_limit"] = GatherDB.CARRY_MAX
	tampered["field_frame_exchange"] = {}
	var restored: Dictionary = RouteSession.from_dict(tampered)
	_check(not bool(restored.get("ok", false)), "記録のないactor間の補助装備移動は復元時に拒否し本編へ反映しない")

func _run_equipment_command_conflicts() -> void:
	print("-- v17: 装備・整備の競合拒否")
	var maintenance_created: Dictionary = RouteSession.create_from_game(main, "equipment-switch-v17-maintenance-first", {"outpost_enabled": false, "vertical_slice": true})
	if bool(maintenance_created.get("ok", false)):
		var maintenance_session = maintenance_created.get("session", null)
		if maintenance_session != null:
			var maintenance: Dictionary = maintenance_session.request_intermediate_clearance()
			var frame_while_maintenance: Dictionary = maintenance_session.request_field_frame_to_harvest()
			_check(bool(maintenance.get("ok", false)) and not bool(frame_while_maintenance.get("ok", false)) and str(frame_while_maintenance.get("reason", "")).contains("整備"), "整備中は現地フレーム予約を拒否し作業員stateを競合させない")
		else:
			_check(false, "整備優先の競合検証sessionを作成")
	else:
		_check(false, "整備優先の競合検証sessionを作成")
	var frame_created: Dictionary = RouteSession.create_from_game(main, "equipment-switch-v17-frame-first", {"outpost_enabled": false, "vertical_slice": true})
	if bool(frame_created.get("ok", false)):
		var frame_session = frame_created.get("session", null)
		if frame_session != null:
			var frame: Dictionary = frame_session.request_field_frame_to_harvest()
			var maintenance_while_frame: Dictionary = frame_session.request_intermediate_clearance()
			_check(bool(frame.get("ok", false)) and not bool(maintenance_while_frame.get("ok", false)) and str(maintenance_while_frame.get("reason", "")).contains("フレーム"), "現地フレーム予約中は整備を拒否し採掘役を待機固定しない")
		else:
			_check(false, "フレーム優先の競合検証sessionを作成")
	else:
		_check(false, "フレーム優先の競合検証sessionを作成")

func _run_field_exchange_route_closure_checks() -> void:
	print("-- v17: 現地引渡しの経路閉鎖")
	var closed_created: Dictionary = RouteSession.create_from_game(main, "equipment-switch-v17-closed-before", {"outpost_enabled": false, "vertical_slice": true})
	if bool(closed_created.get("ok", false)):
		var closed_session = closed_created.get("session", null)
		if closed_session != null:
			var closed_escort: Dictionary = closed_session.actors.get("worker:2", {})
			closed_escort["x"] = RecoveryRouteConnectionSession.RESOURCE.x
			closed_escort["y"] = RecoveryRouteConnectionSession.RESOURCE.y
			closed_session.set_all_routes_closed(true)
			var request_closed: Dictionary = closed_session.request_field_frame_to_harvest()
			var after_closed: Dictionary = Dictionary(closed_session.actors.get("worker:2", {})).duplicate(true)
			closed_session.set_all_routes_closed(false)
			closed_session.tick(STEP)
			var after_reopen: Dictionary = closed_session.actors.get("worker:2", {})
			_check(bool(request_closed.get("ok", false)) and str(after_closed.get("state", "")) == "safe_wait" and str(after_closed.get("resume_state", "")) == "field_exchange_move" and str(after_reopen.get("state", "")) == "field_exchange_move" and str(after_reopen.get("route", "")) == "main", "全路閉鎖中に門の向こうから引渡しへ戻る護衛は安全待機し、再開後に再経路化する")
		else:
			_check(false, "閉鎖前の現地引渡し検証sessionを作成")
	else:
		_check(false, "閉鎖前の現地引渡し検証sessionを作成")
	var moving_created: Dictionary = RouteSession.create_from_game(main, "equipment-switch-v17-closed-during", {"outpost_enabled": false, "vertical_slice": true})
	if bool(moving_created.get("ok", false)):
		var moving_session = moving_created.get("session", null)
		if moving_session != null:
			var moving_escort: Dictionary = moving_session.actors.get("worker:2", {})
			moving_escort["x"] = RecoveryRouteConnectionSession.RESOURCE.x
			moving_escort["y"] = RecoveryRouteConnectionSession.RESOURCE.y
			var request_moving: Dictionary = moving_session.request_field_frame_to_harvest()
			moving_session.set_all_routes_closed(true)
			var after_moving: Dictionary = Dictionary(moving_session.actors.get("worker:2", {})).duplicate(true)
			moving_session.set_all_routes_closed(false)
			moving_session.tick(STEP)
			var after_moving_reopen: Dictionary = moving_session.actors.get("worker:2", {})
			_check(bool(request_moving.get("ok", false)) and str(after_moving.get("state", "")) == "safe_wait" and str(after_moving.get("resume_state", "")) == "field_exchange_move" and str(after_moving_reopen.get("state", "")) == "field_exchange_move" and str(after_moving_reopen.get("route", "")) == "main", "引渡し移動中の全路閉鎖も安全待機へ切替え、再開後に続行する")
		else:
			_check(false, "移動中の現地引渡し検証sessionを作成")
	else:
		_check(false, "移動中の現地引渡し検証sessionを作成")

func _run_field_handoff() -> void:
	print("-- v17: 現地携行フレーム引渡し")
	var ledger_before: Dictionary = session.resource_ledger_by_item().duplicate(true)
	var support_before := _support_totals()
	var first: Dictionary = session.request_field_frame_to_harvest()
	var after_request: Dictionary = session.equipment_status()
	_check(bool(first.get("ok", false)) and str(Dictionary(after_request.get("field_frame", {})).get("status", "")) == "scheduled", "護衛の携行フレームを採取役へ中継引渡しとして予約する")
	_check(_support_totals() == support_before and session.resource_ledger_by_item() == ledger_before, "現地引渡し予約だけでは倉庫数・装備数・資源台帳を変えない")
	var duplicate: Dictionary = session.request_field_frame_to_harvest()
	_check(bool(duplicate.get("ok", false)) and bool(duplicate.get("already_scheduled", false)), "同じ現地引渡し指示の連打は二重予約にしない")
	var restored_result: Dictionary = RouteSession.from_dict(session.to_dict())
	var restored_status := {}
	if bool(restored_result.get("ok", false)):
		var restored = restored_result.get("session", null)
		if restored != null and restored.has_method("equipment_status"):
			restored_status = restored.equipment_status()
	_check(bool(restored_result.get("ok", false)) and str(Dictionary(restored_status.get("field_frame", {})).get("status", "")) == "scheduled", "保存復元は未実行の現地引渡し予約を保持する")
	var cancelled: Dictionary = session.cancel_field_frame_exchange()
	_check(bool(cancelled.get("ok", false)) and str(Dictionary(session.equipment_status().get("field_frame", {})).get("status", "")) == "none" and _support_totals() == support_before, "現地引渡しの取消は装備・倉庫を変えず通常行動へ戻す")
	var requested: Dictionary = session.request_field_frame_to_harvest()
	var completed := await _advance_until(func():
		var field_row: Dictionary = session.equipment_status().get("field_frame", {})
		var harvest: Dictionary = session.actors.get("worker:0", {})
		var escort: Dictionary = session.actors.get("worker:2", {})
		return str(field_row.get("status", "")) == "completed" and int(harvest.get("work_support", -1)) == GameData.Item.HAUL_FRAME and int(harvest.get("carry_limit", 0)) == GameData.HAUL_FRAME_LIMIT and int(escort.get("work_support", -1)) == -1
	, 90.0)
	_check(bool(requested.get("ok", false)) and completed and projection_ok and _support_totals() == support_before and session.conservation_ok(), "中継で空荷の護衛→採取役へ実フレームを渡し、数量保存を維持する")
	var carry_five := await _advance_until(func(): return int(Dictionary(session.actors.get("worker:0", {})).get("carry_n", 0)) == GameData.HAUL_FRAME_LIMIT, 45.0)
	_check(carry_five and session.conservation_ok(), "現地引渡し後の次の採取は既存便数5を実際に使う")

func _run_return_handcart_exchange() -> void:
	print("-- v17: 帰還時の手押し車交換予約")
	_check(session.has_method("request_return_handcart_exchange"), "手押し車の帰還交換はsessionの通常操作APIとして存在する")
	_check(session.has_method("cancel_return_handcart_exchange"), "手押し車の帰還交換は取消APIを持つ")
	_check(main.has_method("swap_work_support"), "既存基地の補助装備は原子的に入替えられる")
	if fails > 0:
		return
	var supports_before := _support_totals()
	var missing: Dictionary = session.request_return_handcart_exchange(main)
	_check(not bool(missing.get("ok", false)) and str(missing.get("reason", "")).contains("手押し車") and _support_totals() == supports_before, "基地にない大型装備は現地で生成せず理由付きで拒否する")
	main.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
	supports_before = _support_totals()
	var reserved: Dictionary = session.request_return_handcart_exchange(main)
	var return_status: Dictionary = session.equipment_status().get("return_handcart", {})
	_check(bool(reserved.get("ok", false)) and str(return_status.get("status", "")) == "reserved" and _support_totals() == supports_before, "手押し車は帰還確定まで倉庫・装備を変えない予約として保持する")
	var duplicate: Dictionary = session.request_return_handcart_exchange(main)
	_check(bool(duplicate.get("ok", false)) and bool(duplicate.get("already_reserved", false)) and _support_totals() == supports_before, "手押し車予約の連打は在庫を二重に動かさない")
	var canceled: Dictionary = session.cancel_return_handcart_exchange()
	_check(bool(canceled.get("ok", false)) and str(Dictionary(session.equipment_status().get("return_handcart", {})).get("status", "")) == "none" and _support_totals() == supports_before, "帰還交換の取消は予約だけを消して数量を維持する")
	var re_reserved: Dictionary = session.request_return_handcart_exchange(main)
	var restored: Dictionary = RouteSession.from_dict(session.to_dict())
	var restored_status := {}
	if bool(restored.get("ok", false)):
		var restored_session = restored.get("session", null)
		if restored_session != null and restored_session.has_method("equipment_status"):
			restored_status = restored_session.equipment_status()
	_check(bool(re_reserved.get("ok", false)) and bool(restored.get("ok", false)) and str(Dictionary(restored_status.get("return_handcart", {})).get("status", "")) == "reserved", "検証保存復元は帰還交換予約を保持する")
	var clearance: Dictionary = session.request_intermediate_clearance()
	var cleared := await _advance_until(func(): return str(session.state_summary().get("intermediate_access", "")) == "cleared", 30.0)
	var reposition: Dictionary = session.request_reposition("relay")
	var fixed_at_entry := str(session.phase) == "local" and str(session.state_summary().get("parking_slot", "")) == "entry"
	_check(bool(clearance.get("ok", false)) and cleared and not bool(reposition.get("ok", false)) and fixed_at_entry and str(Dictionary(session.equipment_status().get("return_handcart", {})).get("status", "")) == "reserved", "停め直しは拒否され入口固定・基地交換予約を維持する")
	var post_reposition_reservation: Dictionary = session.request_return_handcart_exchange(main)
	_check(bool(post_reposition_reservation.get("ok", false)) and str(Dictionary(session.equipment_status().get("return_handcart", {})).get("status", "")) == "reserved", "停め直し拒否後も基地保管の手押し車の帰還交換予約を維持する")
	session.request_recall()
	_check(str(session.phase) == "recall" and str(Dictionary(session.equipment_status().get("return_handcart", {})).get("status", "")) == "reserved" and _support_totals() == supports_before, "撤退は予約を即時装備へ変えず、通常帰還を優先する")
	var ready := await _advance_until(func(): return str(session.phase) == "ready_to_exit", 120.0)
	main.storage.inventory.take(GameData.Item.HANDCART)
	var missing_at_commit: Dictionary = session.commit_to_game(main)
	var preflight_preserved := not bool(missing_at_commit.get("ok", false)) and int(main.workers[0].work_support) == -1 and int(main.workers[1].work_support) == GameData.Item.HAUL_FRAME and int(main.workers[2].work_support) == GameData.Item.HAUL_FRAME
	main.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
	_check(preflight_preserved and str(missing_at_commit.get("reason", "")).contains("手押し車"), "予約済み手押し車が帰還前に無くなっても確定を拒否し本編装備を変えない")
	var observed_return := {"events": 0, "support": -1}
	var support_observer := func(item: int, amount: int, source: String):
		if item == GameData.Item.HAUL_FRAME and amount == 1 and source == Inventory.SOURCE_TRANSFER:
			observed_return["events"] = int(observed_return.get("events", 0)) + 1
			observed_return["support"] = int(main.workers[1].work_support)
	main.storage.inventory.item_added.connect(support_observer)
	var committed: Dictionary = session.commit_to_game(main)
	if main.storage.inventory.item_added.is_connected(support_observer):
		main.storage.inventory.item_added.disconnect(support_observer)
	var repeated: Dictionary = session.commit_to_game(main)
	var support_after := _support_totals()
	var save_snapshot: Dictionary = SaveGame.capture(main)
	var saved_carrier_support := -1
	var crew: Array = Array(save_snapshot.get("crew", []))
	if crew.size() > 1:
		var carrier_row := Dictionary(Dictionary(crew[1]).get("worker", {}))
		saved_carrier_support = int(carrier_row.get("work_support", -1))
	var commit_state_ok := bool(repeated.get("already_committed", false)) and int(main.workers[0].work_support) == GameData.Item.HAUL_FRAME and int(main.workers[1].work_support) == GameData.Item.HANDCART and int(main.workers[2].work_support) == -1 and support_after == supports_before and saved_carrier_support == GameData.Item.HANDCART and int(observed_return.get("events", 0)) == 1 and int(observed_return.get("support", -1)) == GameData.Item.HANDCART
	_check(ready and bool(committed.get("ok", false)) and commit_state_ok, "帰還確定だけがフレーム位置と手押し車を一度だけ原子的に反映し既存保存対象へ渡す")
	var next_created: Dictionary = RouteSession.create_from_game(main, "equipment-switch-v17-after-return", {"outpost_enabled": false, "vertical_slice": true})
	var next_carrier := {}
	if bool(next_created.get("ok", false)):
		var next_session = next_created.get("session", null)
		if next_session != null:
			next_carrier = next_session.actors.get("worker:1", {})
	_check(bool(next_created.get("ok", false)) and int(next_carrier.get("work_support", -1)) == GameData.Item.HANDCART and int(next_carrier.get("carry_limit", 0)) == GameData.HANDCART_LIMIT, "次のC採石場入場は帰還交換後の手押し車便8をsnapshotへ反映する")

func _move(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 300:
		main._process(0.2)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return false

func _tick() -> void:
	session.tick(STEP)
	var projected: Dictionary = session.apply_projection_to_workers(main)
	projection_ok = projection_ok and bool(projected.get("ok", false))
	await process_frame

func _advance_until(predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		await _tick()
		if predicate.call():
			return true
	return predicate.call()

func _support_totals() -> Dictionary:
	var result := {
		GameData.Item.HAUL_FRAME: int(main.storage.count_of(GameData.Item.HAUL_FRAME)),
		GameData.Item.HANDCART: int(main.storage.count_of(GameData.Item.HANDCART)),
	}
	for worker in main.workers:
		var support := int(worker.work_support)
		if result.has(support):
			result[support] = int(result[support]) + 1
	return result

func _finish() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
