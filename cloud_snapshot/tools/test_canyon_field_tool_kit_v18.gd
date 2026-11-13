extends SceneTree
## Focused real-session witness for v18: a single harvest worker carries one
## real small mine tool from BaseStorage and swaps it at an empty relay.
## It never writes normal SaveGame data or touches the protected v17 copy.

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
	if not await _prepare("field-tool-kit-v18-primary"):
		_finish()
		return
	_check(session.has_method("request_field_tool_swap"), "同一採掘役の携行採掘具切替はsession通常操作APIとして存在する")
	_check(session.has_method("cancel_field_tool_swap"), "未完の携行採掘具切替は取消APIを持つ")
	_check(session.has_method("equipment_status"), "携行採掘具の状態はHUD用読み取りAPIで取得できる")
	if fails > 0:
		_finish()
		return
	await _run_same_worker_swap_and_commit()
	if fails == 0:
		await _run_recall_priority_and_missing_kit()
	_finish()

func _prepare(id: String) -> bool:
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 260129)
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	main.director.enabled = false
	main.tool_auto = false
	main.workers[0].ranks[GameData.Field.GATHERER] = 2
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
	main.storage.store_owned(GameData.Item.HAMMER, 1, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.PICKAXE, 1, Inventory.SOURCE_TRANSFER)
	_check(main.equip_tool(main.workers[0], GameData.Item.HAMMER), "既存倉庫APIで採掘役へ石のハンマーを装備")
	var created: Dictionary = RouteSession.create_from_game(main, id, {"outpost_enabled": false, "vertical_slice": true})
	_check(bool(created.get("ok", false)), "既存C資源と通常3人分業からfield-tool-kit sessionを作成")
	if not bool(created.get("ok", false)):
		return false
	session = created.session
	return true

func _run_same_worker_swap_and_commit() -> void:
	print("-- v18: 同一採掘役の実在携行採掘具")
	var harvest: Dictionary = session.actors.get("worker:0", {})
	var before_tools := _field_tool_totals(session)
	var pickaxe_storage_before := int(main.storage.count_of(GameData.Item.PICKAXE))
	var kit: Dictionary = Dictionary(harvest.get("field_tool_kit", {}))
	_check(int(main.workers[0].tools.get("mine", -1)) == GameData.Item.HAMMER and int(harvest.get("tools", {}).get("mine", -1)) == GameData.Item.HAMMER and int(kit.get("mine", -1)) == GameData.Item.PICKAXE and pickaxe_storage_before == 0, "出発時に実在ピッケル1本だけを採掘役の携行枠へ移し、本編Workerはentry採掘具のまま")
	_check(before_tools == _field_tool_totals(session) and _all_actor_tool_kits_valid(session), "現地kitは同一actor・mine枠の所有だけを持ち、工具総数を保存する")
	var missing_handcart: Dictionary = session.to_dict()
	var handcart_rows: Dictionary = Dictionary(missing_handcart.get("actors", {})).duplicate(true)
	var handcart_actor: Dictionary = Dictionary(handcart_rows.get("worker:0", {})).duplicate(true)
	handcart_actor["field_tool_kit"] = {"mine": GameData.Item.HANDCART}
	handcart_rows["worker:0"] = handcart_actor
	missing_handcart["actors"] = handcart_rows
	var handcart_restored: Dictionary = RouteSession.from_dict(missing_handcart)
	_check(not bool(handcart_restored.get("ok", false)), "手押し車を採掘具携行枠へ改竄したsessionは復元時に拒否する")
	var wrong_slot: Dictionary = session.to_dict()
	var wrong_slot_rows: Dictionary = Dictionary(wrong_slot.get("actors", {})).duplicate(true)
	var wrong_slot_actor: Dictionary = Dictionary(wrong_slot_rows.get("worker:0", {})).duplicate(true)
	wrong_slot_actor["field_tool_kit"] = {"chop": GameData.Item.PICKAXE}
	wrong_slot_rows["worker:0"] = wrong_slot_actor
	wrong_slot["actors"] = wrong_slot_rows
	_check(not bool(RouteSession.from_dict(wrong_slot).get("ok", false)), "採掘具を別slotへ入れたsessionは復元時に拒否する")
	var duplicate_tool: Dictionary = session.to_dict()
	var duplicate_rows: Dictionary = Dictionary(duplicate_tool.get("actors", {})).duplicate(true)
	var duplicate_actor: Dictionary = Dictionary(duplicate_rows.get("worker:0", {})).duplicate(true)
	duplicate_actor["tools"] = {"mine": GameData.Item.PICKAXE}
	duplicate_rows["worker:0"] = duplicate_actor
	duplicate_tool["actors"] = duplicate_rows
	_check(not bool(RouteSession.from_dict(duplicate_tool).get("ok", false)), "同じ採掘具を装備と携行へ複製したsessionは復元時に拒否する")
	var moved_owner: Dictionary = session.to_dict()
	var moved_rows: Dictionary = Dictionary(moved_owner.get("actors", {})).duplicate(true)
	var moved_harvest: Dictionary = Dictionary(moved_rows.get("worker:0", {})).duplicate(true)
	var moved_carry: Dictionary = Dictionary(moved_rows.get("worker:1", {})).duplicate(true)
	moved_harvest["field_tool_kit"] = {}
	moved_carry["field_tool_kit"] = {"mine": GameData.Item.PICKAXE}
	moved_rows["worker:0"] = moved_harvest
	moved_rows["worker:1"] = moved_carry
	moved_owner["actors"] = moved_rows
	var moved_restored: Dictionary = RouteSession.from_dict(moved_owner)
	_check(not bool(moved_restored.get("ok", false)), "別仲間へ移した携行採掘具の改竄は復元時に拒否する")
	var reached_first_work := await _advance_until(func(): return str(Dictionary(session.actors.get("worker:0", {})).get("state", "")) == "harvesting", 35.0)
	var entry_work_left := float(Dictionary(session.actors.get("worker:0", {})).get("work_left", 0.0))
	var first: Dictionary = session.request_field_tool_swap()
	var equipment: Dictionary = session.equipment_status()
	var tool_status: Dictionary = Dictionary(equipment.get("field_tool", {}))
	_check(reached_first_work and entry_work_left > 0.0 and bool(first.get("ok", false)) and str(tool_status.get("status", "")) == "scheduled", "採掘中の切替は同一採掘役の中継・空荷予約となる")
	var restored: Dictionary = RouteSession.from_dict(session.to_dict())
	var restored_status := {}
	if bool(restored.get("ok", false)):
		var restored_session = restored.get("session", null)
		if restored_session != null:
			restored_status = Dictionary(restored_session.equipment_status().get("field_tool", {}))
	_check(bool(restored.get("ok", false)) and str(restored_status.get("status", "")) == "scheduled", "project-local session保存復元は未完の同一仲間切替予約を保持する")
	var canceled: Dictionary = session.cancel_field_tool_swap()
	_check(bool(canceled.get("ok", false)) and str(Dictionary(session.equipment_status().get("field_tool", {})).get("status", "")) == "none" and _field_tool_totals(session) == before_tools, "取消は予約だけを消し、現地kit・在庫・資源を変えない")
	var requested: Dictionary = session.request_field_tool_swap()
	var swapped := await _advance_until(func():
		var row: Dictionary = Dictionary(session.equipment_status().get("field_tool", {}))
		var actor: Dictionary = session.actors.get("worker:0", {})
		return str(row.get("status", "")) == "completed" and int(actor.get("tools", {}).get("mine", -1)) == GameData.Item.PICKAXE and int(Dictionary(actor.get("field_tool_kit", {})).get("mine", -1)) == GameData.Item.HAMMER
	, 70.0)
	_check(bool(requested.get("ok", false)) and swapped and projection_ok and int(main.workers[0].tools.get("mine", -1)) == GameData.Item.HAMMER and _field_tool_totals(session) == before_tools, "中継の空荷境界で採掘役本人だけが交換し、本編Workerと工具総数を現地中に変えない")
	var reached_next_work := await _advance_until(func(): return str(Dictionary(session.actors.get("worker:0", {})).get("state", "")) == "harvesting", 45.0)
	var switched_work_left := float(Dictionary(session.actors.get("worker:0", {})).get("work_left", 0.0))
	_check(reached_next_work and switched_work_left > 0.0 and switched_work_left < entry_work_left, "交換後の次回採掘は既存GatherDB効率比による短い作業時間を使う")
	var reverse_requested: Dictionary = session.request_field_tool_swap()
	var reversed := await _advance_until(func():
		var row: Dictionary = Dictionary(session.equipment_status().get("field_tool", {}))
		var actor: Dictionary = session.actors.get("worker:0", {})
		return str(row.get("status", "")) == "completed" and int(Dictionary(actor.get("tools", {})).get("mine", -1)) == GameData.Item.HAMMER and int(Dictionary(actor.get("field_tool_kit", {})).get("mine", -1)) == GameData.Item.PICKAXE
	, 70.0)
	_check(bool(reverse_requested.get("ok", false)) and reversed and projection_ok and int(main.workers[0].tools.get("mine", -1)) == GameData.Item.HAMMER and _field_tool_totals(session) == before_tools, "同一採掘役は空荷の中継境界で装備中と携行中の採掘具を元へ戻せる")
	var final_requested: Dictionary = session.request_field_tool_swap()
	var final_swapped := await _advance_until(func():
		var row: Dictionary = Dictionary(session.equipment_status().get("field_tool", {}))
		var actor: Dictionary = session.actors.get("worker:0", {})
		return str(row.get("status", "")) == "completed" and int(Dictionary(actor.get("tools", {})).get("mine", -1)) == GameData.Item.PICKAXE and int(Dictionary(actor.get("field_tool_kit", {})).get("mine", -1)) == GameData.Item.HAMMER
	, 70.0)
	_check(bool(final_requested.get("ok", false)) and final_swapped and _field_tool_totals(session) == before_tools, "戻した後も同じ本人の実在携行ピッケルへ再切替できる")
	var before_recall_tools := _field_tool_totals(session)
	session.request_recall()
	var ready := await _advance_until(func(): return str(session.phase) == "ready_to_exit", 150.0)
	var live_before_commit := int(main.workers[0].tools.get("mine", -1)) == GameData.Item.HAMMER
	var committed: Dictionary = session.commit_to_game(main)
	var repeated: Dictionary = session.commit_to_game(main)
	var save_snapshot: Dictionary = SaveGame.capture(main)
	var saved_tool := -1
	var crew: Array = Array(save_snapshot.get("crew", []))
	if not crew.is_empty():
		saved_tool = int(Dictionary(Dictionary(crew[0]).get("worker", {})).get("tools", {}).get("mine", -1))
	main.workers[0].tools["mine"] = GameData.Item.HAMMER
	var save_roundtrip := SaveGame.apply(main, save_snapshot)
	_check(ready and live_before_commit and bool(committed.get("ok", false)) and bool(repeated.get("already_committed", false)) and int(main.workers[0].tools.get("mine", -1)) == GameData.Item.PICKAXE and int(main.storage.count_of(GameData.Item.HAMMER)) == 1 and saved_tool == GameData.Item.PICKAXE and save_roundtrip and _main_tool_total() == 2, "帰還確定だけが同一Workerへ新toolを反映し、旧toolを倉庫へ一度だけ戻し、既存SaveGameの実読込後も保持する")

func _run_recall_priority_and_missing_kit() -> void:
	print("-- v18: 予約優先と非所持理由")
	_check(main.equip_tool(main.workers[0], GameData.Item.HAMMER), "既存倉庫APIで次回検証用に採掘役をハンマーへ戻す")
	var created: Dictionary = RouteSession.create_from_game(main, "field-tool-kit-v18-recall", {"outpost_enabled": false, "vertical_slice": true})
	_check(bool(created.get("ok", false)), "帰還優先検証の次回sessionを作成")
	if not bool(created.get("ok", false)):
		return
	session = created.session
	var requested: Dictionary = session.request_field_tool_swap()
	session.request_recall()
	var status_after_recall: Dictionary = Dictionary(session.equipment_status().get("field_tool", {}))
	var ready := await _advance_until(func(): return str(session.phase) == "ready_to_exit", 150.0)
	var committed: Dictionary = session.commit_to_game(main)
	_check(bool(requested.get("ok", false)) and str(status_after_recall.get("status", "")) == "none" and ready and bool(committed.get("ok", false)) and int(main.workers[0].tools.get("mine", -1)) == GameData.Item.HAMMER and int(main.storage.count_of(GameData.Item.PICKAXE)) == 1 and _main_tool_total() == 2, "撤退は未完の携行採掘具予約を取消し、貨物帰還と数量保存を優先する")
	_check(main.storage.take_item(GameData.Item.PICKAXE), "非所持理由の検証用に基地ピッケルを一時的に取り除く")
	var no_kit_created: Dictionary = RouteSession.create_from_game(main, "field-tool-kit-v18-no-kit", {"outpost_enabled": false, "vertical_slice": true})
	if not bool(no_kit_created.get("ok", false)):
		_check(false, "携行候補なしのsessionを作成")
	else:
		var no_kit_session = no_kit_created.session
		var rejected: Dictionary = no_kit_session.request_field_tool_swap()
		_check(not bool(rejected.get("ok", false)) and str(rejected.get("reason", "")).contains("携行"), "基地に携行可能な小型採掘具が無いときは遠隔生成せず理由付きで拒否する")
	main.storage.store_owned(GameData.Item.PICKAXE, 1, Inventory.SOURCE_TRANSFER)
	var cleanup_created: Dictionary = RouteSession.create_from_game(main, "field-tool-kit-v18-cleanup", {"outpost_enabled": false, "vertical_slice": true})
	var cleanup_ok := false
	if bool(cleanup_created.get("ok", false)):
		var cleanup_session = cleanup_created.get("session", null)
		if cleanup_session != null and cleanup_session.has_method("release_uncommitted_field_tool_kits"):
			var cleanup_swap: Dictionary = cleanup_session.request_field_tool_swap()
			var cleanup_swapped := await _advance_session_until(cleanup_session, func():
				var row: Dictionary = Dictionary(cleanup_session.equipment_status().get("field_tool", {}))
				return str(row.get("status", "")) == "completed"
			, 70.0)
			var cleanup_result: Dictionary = cleanup_session.release_uncommitted_field_tool_kits(main)
			cleanup_ok = bool(cleanup_swap.get("ok", false)) and cleanup_swapped and bool(cleanup_result.get("ok", false)) and int(main.storage.count_of(GameData.Item.PICKAXE)) == 1 and int(main.storage.count_of(GameData.Item.HAMMER)) == 0 and int(main.workers[0].tools.get("mine", -1)) == GameData.Item.HAMMER and _main_tool_total() == 2
	_check(cleanup_ok, "交換済みでも未確定field viewの終了は元の携行ピッケルだけを倉庫へ戻し、本編Workerと工具総数を変えない")

func _field_tool_totals(target_session) -> Dictionary:
	var result := {
		GameData.Item.HAMMER: int(main.storage.count_of(GameData.Item.HAMMER)),
		GameData.Item.PICKAXE: int(main.storage.count_of(GameData.Item.PICKAXE)),
	}
	for actor_id in target_session.actors:
		var actor: Dictionary = target_session.actors[actor_id]
		for item in [int(Dictionary(actor.get("tools", {})).get("mine", -1)), int(Dictionary(actor.get("field_tool_kit", {})).get("mine", -1))]:
			if result.has(item):
				result[item] = int(result[item]) + 1
	return result

func _main_tool_total() -> int:
	var total := int(main.storage.count_of(GameData.Item.HAMMER)) + int(main.storage.count_of(GameData.Item.PICKAXE))
	for worker in main.workers:
		for slot in worker.tools:
			var item := int(worker.tools[slot])
			if item in [GameData.Item.HAMMER, GameData.Item.PICKAXE]:
				total += 1
	return total

func _all_actor_tool_kits_valid(target_session) -> bool:
	for actor_id in target_session.actors:
		var actor: Dictionary = target_session.actors[actor_id]
		var kit: Dictionary = Dictionary(actor.get("field_tool_kit", {}))
		if kit.size() > 1:
			return false
		for slot in kit:
			if slot != "mine" or not GatherDB.is_tool_item(int(kit[slot])):
				return false
	return true

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

func _advance_session_until(target_session, predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		target_session.tick(STEP)
		var projected: Dictionary = target_session.apply_projection_to_workers(main)
		projection_ok = projection_ok and bool(projected.get("ok", false))
		await process_frame
		if predicate.call():
			return true
	return predicate.call()

func _finish() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
