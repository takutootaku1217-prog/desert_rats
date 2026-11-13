extends SceneTree
## One deterministic C-quarry witness.  It uses the real bridge session and
## temporary XDG-backed fixture state only; it never enables normal SaveGame.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const STEP := 0.5

var main
var session
var original_capacity_bonus := 0
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	SaveGame.disabled = true
	if not await _prepare_session():
		_finish()
		return
	_check(session.has_method("vertical_slice_brief"), "一地点縦切りは読み取り専用の次判断briefを持つ")
	_check(session.has_method("resource_ledger_by_item"), "一地点縦切りは地面・手持ち・中継・車内を項目別に照合できる")
	if not session.has_method("vertical_slice_brief") or not session.has_method("resource_ledger_by_item"):
		_finish()
		return
	await _run_playable_loop()
	_finish()

func _prepare_session() -> bool:
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
	if not await _move_to_quarry():
		_check(false, "既存の横2D A→B→C移動で採石場に到達")
		return false
	var iron := int(GameData.Item.IRON_ORE)
	original_capacity_bonus = int(main.storage.capacity_bonus)
	var room := int(main.storage.max_weight() - main.storage.current_weight() - main.storage.processing_reserve())
	main.storage.capacity_bonus = original_capacity_bonus - room + main.storage.item_weight(iron, 1)
	var created: Dictionary = RouteSession.create_from_game(main, "one-site-playable-loop-v16", {"outpost_enabled": false, "vertical_slice": true})
	_check(bool(created.get("ok", false)), "C採石場の既存有限資源・通常3人分業から縦切りsessionを作成")
	if not bool(created.get("ok", false)):
		return false
	session = created.session
	return true

func _run_playable_loop() -> void:
	print("-- 一地点: 回収・迂回・満杯保持・中継・帰還")
	var initial_brief: Dictionary = session.call("vertical_slice_brief")
	var frame: Dictionary = initial_brief.get("haul_frame", {})
	var requirements: Dictionary = frame.get("requirements", {})
	_check(str(initial_brief.get("kind", "")) == "maintenance" and is_equal_approx(float(initial_brief.get("saved_one_way_seconds", 0.0)), 10.0), "入口では整備→中継の24→14秒判断を正本profileから読む")
	_check(int(frame.get("base_limit", 0)) == 3 and int(frame.get("limit", 0)) == 5 and int(requirements.get(GameData.Item.WOOD, 0)) == 2 and int(requirements.get(GameData.Item.HIDE, 0)) == 1 and int(requirements.get(GameData.Item.IRON, 0)) == 1, "既存背負いフレーム候補は便3→5と実レシピだけを示す")
	_check(_readbacks_are_pure(), "briefと項目別台帳の読出しはsession・倉庫・検証保存設定を変更しない")
	_check(_ledger_matches_session(), "開始時の項目別台帳は実sessionの資源所在地と一致")

	session.set_gate_closed(true)
	var bypass_brief: Dictionary = session.call("vertical_slice_brief")
	var bypass_seen := await _advance_until(func(): return _has_route("bypass"), 45.0)
	var depot_before_bypass := int(session.state_summary().get("depot", 0))
	var bypass_delivery := await _advance_until(func(): return int(session.state_summary().get("depot", 0)) > depot_before_bypass, 90.0)
	_check(bypass_seen and bypass_delivery and str(bypass_brief.get("kind", "")) == "bypass" and session.conservation_ok() and _ledger_matches_session(), "主路閉鎖時は実actorが迂回し、収納と項目別保存則を維持")

	var held := await _advance_until(func():
		var summary: Dictionary = session.state_summary()
		return bool(summary.get("capacity_paused", false)) and int(summary.get("depot", 0)) > 0 and int(summary.get("carried", 0)) > 0
	, 90.0)
	var held_summary: Dictionary = session.state_summary()
	var source_at_hold := int(held_summary.get("source_remaining", 0))
	_check(held and str(session.call("vertical_slice_brief").get("kind", "")) == "capacity_hold" and _ledger_matches_session(), "満載時は新規採取を停止し、入りきらない貨物を仲間が保持")
	for unused in 20:
		await _tick()
	_check(session.total_source_remaining() == source_at_hold and session.conservation_ok() and _ledger_matches_session(), "満載保持中は新規採取を増やさず資源の所在を保つ")

	main.storage.capacity_bonus = original_capacity_bonus
	var refreshed: Dictionary = session.refresh_capacity_from_game(main)
	var depot_before_retained_unload := int(held_summary.get("depot", 0))
	var retained_unloaded := await _advance_until(func():
		var summary: Dictionary = session.state_summary()
		return not bool(summary.get("capacity_paused", true)) and int(summary.get("depot", 0)) > depot_before_retained_unload
	, 30.0)
	var source_after_retained_unload: int = int(session.total_source_remaining())
	var depot_after_retained_unload := int(session.state_summary().get("depot", 0))
	var renewed_delivery := await _advance_until(func(): return session.total_source_remaining() < source_after_retained_unload and int(session.state_summary().get("depot", 0)) > depot_after_retained_unload, 90.0)
	_check(bool(refreshed.get("ok", false)) and retained_unloaded and renewed_delivery and session.conservation_ok() and _ledger_matches_session(), "容量回復後は保持荷物だけで終わらず、新しい採取→収納を再開")

	session.set_gate_closed(false)
	var clearance: Dictionary = session.request_intermediate_clearance()
	var cleared := await _advance_until(func(): return str(session.state_summary().get("intermediate_access", "")) == "cleared", 20.0)
	var source_before_reposition: int = int(session.total_source_remaining())
	var reposition: Dictionary = session.request_reposition("relay")
	var relocated := await _advance_until(func(): return str(session.phase) == "local" and str(session.state_summary().get("parking_slot", "")) == "relay", 80.0)
	var relay_profile: Dictionary = session.vertical_slice_profile()
	var relay_brief: Dictionary = session.call("vertical_slice_brief")
	_check(bool(clearance.get("ok", false)) and cleared and bool(reposition.get("ok", false)) and relocated and is_equal_approx(float(relay_profile.get("active_one_way_seconds", 0.0)), 14.0) and is_equal_approx(float(relay_brief.get("saved_one_way_seconds", 0.0)), 10.0) and session.total_source_remaining() == source_before_reposition and session.conservation_ok() and _ledger_matches_session(), "整備→全員帰還→中継停車は地面資源を残し、片道24→14秒の効果を有効化")

	session.request_recall()
	var recall_brief: Dictionary = session.call("vertical_slice_brief")
	var ready := await _advance_until(func(): return str(session.phase) == "ready_to_exit", 100.0)
	var before_commit_ledger: Dictionary = session.call("resource_ledger_by_item")
	var storage_before := _storage_counts(before_commit_ledger)
	var committed: Dictionary = session.commit_to_game(main)
	var committed_once := bool(committed.get("ok", false)) and _storage_received(before_commit_ledger, storage_before)
	var repeated: Dictionary = session.commit_to_game(main)
	_check(str(recall_brief.get("kind", "")) == "recall" and ready and _ledger_matches_session() and committed_once and bool(repeated.get("already_committed", false)), "帰還は貨物を一度だけ本編倉庫へ確定し、二重加算を拒否")

func _move_to_quarry() -> bool:
	for destination in ["b_forest", "c_quarry"]:
		if not main.world.request(destination):
			return false
		for unused in 240:
			main._process(STEP)
			await process_frame
			if main.world.phase == "stopped" and main.world.region == destination:
				break
		if main.world.phase != "stopped" or main.world.region != destination:
			return false
	return true

func _tick() -> void:
	session.tick(STEP)
	var projection: Dictionary = session.apply_projection_to_workers(main)
	if not bool(projection.get("ok", false)):
		_check(false, "実sessionのworker投影を維持")
	await process_frame

func _advance_until(predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		await _tick()
		if predicate.call():
			return true
	return predicate.call()

func _has_route(route_name: String) -> bool:
	for actor_id in session.actors:
		if str(session.actors[actor_id].get("route", "")) == route_name:
			return true
	return false

func _manual_ledger() -> Dictionary:
	var ledger := {}
	for resource_id in session.resources:
		var resource: Dictionary = session.resources[resource_id]
		var item := int(resource.get("item", -1))
		_add_ledger(ledger, item, "initial", int(resource.get("initial", 0)))
		_add_ledger(ledger, item, "ground", int(resource.get("remaining", 0)))
	for actor_id in session.actors:
		var actor: Dictionary = session.actors[actor_id]
		_add_ledger(ledger, int(actor.get("carry_item", -1)), "carried", int(actor.get("carry_n", 0)))
	for item in session.relay_stock:
		_add_ledger(ledger, int(item), "relay", int(session.relay_stock[item]))
	for item in session.depot_stock:
		_add_ledger(ledger, int(item), "depot", int(session.depot_stock[item]))
	for item in ledger:
		var row: Dictionary = ledger[item]
		row["accounted"] = int(row.ground) + int(row.carried) + int(row.relay) + int(row.depot)
		row["conservation_ok"] = int(row.initial) == int(row.accounted)
	return ledger

func _add_ledger(ledger: Dictionary, item: int, key: String, amount: int) -> void:
	if item < 0 or amount <= 0:
		return
	if not ledger.has(item):
		ledger[item] = {"initial": 0, "ground": 0, "carried": 0, "relay": 0, "depot": 0, "accounted": 0, "conservation_ok": false}
	var row: Dictionary = ledger[item]
	row[key] = int(row.get(key, 0)) + amount

func _ledger_matches_session() -> bool:
	var actual: Dictionary = session.call("resource_ledger_by_item")
	var expected := _manual_ledger()
	if actual.size() != expected.size():
		return false
	for item in expected:
		if not actual.has(item):
			return false
		var want: Dictionary = expected[item]
		var got: Dictionary = actual[item]
		for key in ["initial", "ground", "carried", "relay", "depot", "accounted"]:
			if int(got.get(key, -1)) != int(want.get(key, -2)):
				return false
		if bool(got.get("conservation_ok", false)) != bool(want.get("conservation_ok", false)):
			return false
	return true

func _readbacks_are_pure() -> bool:
	var session_before: Dictionary = session.to_dict().duplicate(true)
	var inventory_before: Dictionary = main.storage.inventory.counts.duplicate(true)
	var wasted_before: Dictionary = main.storage.wasted.duplicate(true)
	var capacity_before := int(main.storage.capacity_bonus)
	var saves_disabled_before := bool(SaveGame.disabled)
	session.call("vertical_slice_brief")
	session.call("resource_ledger_by_item")
	return session.to_dict() == session_before and main.storage.inventory.counts == inventory_before and main.storage.wasted == wasted_before and int(main.storage.capacity_bonus) == capacity_before and bool(SaveGame.disabled) == saves_disabled_before

func _storage_counts(ledger: Dictionary) -> Dictionary:
	var counts := {}
	for item in ledger:
		counts[int(item)] = main.storage.inventory.count(int(item))
	return counts

func _storage_received(ledger: Dictionary, before: Dictionary) -> bool:
	for item in ledger:
		var item_id := int(item)
		var row: Dictionary = ledger[item]
		if main.storage.inventory.count(item_id) != int(before.get(item_id, 0)) + int(row.get("depot", 0)):
			return false
	return true

func _finish() -> void:
	if main != null and is_instance_valid(main):
		main.storage.capacity_bonus = original_capacity_bonus
		main.queue_free()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
