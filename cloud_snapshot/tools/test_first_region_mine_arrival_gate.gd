extends SceneTree
## Normal first-region mine-arrival integration contract.
##
## Uses an actual Main / WorldTrip / JourneyPlan / recovery session. It does
## not write user saves or inject resources, and verifies the adapter's real
## commit boundary rather than the diagnostic harness shortcut.

const STEP := 0.2

var main
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _fresh() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
		await process_frame
	SaveGame.disabled = true
	# Each independent fixture starts unpaused; field pause behavior is tested separately.
	paused = false
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
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
	if main.world.region == "b_forest" and not await _move_leg("c_quarry"):
		return false
	return main.world.region == "c_quarry" and main.world.phase == "stopped"

func _gate():
	return main.get("mine_arrival_gate")

func _advance_until(predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		var gate = _gate()
		if gate == null or gate.field == null:
			return false
		gate.field.session.tick(STEP)
		var projection: Dictionary = gate.field.session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return false
		if predicate.call():
			return true
	return predicate.call()

func _stock_for_session(session) -> int:
	var total := 0
	var seen := {}
	for resource_id in session.resources:
		var item := int(session.resources[resource_id].item)
		if not seen.has(item):
			seen[item] = true
			total += main.storage.count_of(item)
	return total

func _run() -> void:
	await _direct_destination_has_one_entry_decision()
	if failures == 0:
		await _outpost_confirmation_contract()
	if failures == 0:
		await _map_reopen_contract()
	if failures == 0:
		await _failed_entry_notice_closes_with_choice()
	if failures == 0:
		await _pass_through_and_visit_reservation()
	if failures == 0:
		await _field_commit_restores_normal_c_state()
	if failures == 0:
		await _live_mine_path_clearance_can_return_through_visible_controls()
	if failures == 0:
		await _cleared_quarry_revisit_enters_from_the_visible_choice()
	if failures == 0:
		await _cleared_quarry_with_depleted_resources_still_enters_for_route_inspection()
	if failures == 0:
		await _live_field_adapter_keeps_processing_after_main_is_hidden()
	_return_receipt_contract()
	if main != null and is_instance_valid(main):
		main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("== first-region mine-arrival gate: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)

func _outpost_confirmation_contract() -> void:
	print("-- optional outpost informed confirmation --")
	await _fresh()
	_check(await _move_to_quarry(), "outpost confirmation uses real stopped C")
	var gate = _gate()
	var before := SaveGame.capture(main)
	var serial: int = gate._session_serial
	var stance: String = main.operations.stance
	gate._outpost_button.pressed.emit()
	var dialog = gate.get("_outpost_dialog")
	_check(dialog is ConfirmationDialog and gate.field == null and gate._session_serial == serial, "danger button requests consent before any session is created")
	if not dialog is ConfirmationDialog or gate.field != null: return
	_check(dialog.visible and paused and main.has_open_management_panel(), "confirmation owns a pause and participates in menu arbitration")
	_check(SaveGame.capture(main) == before and gate._entry_options.is_empty() and main.operations.stance == stance, "opening danger confirmation changes no durable state or orders")
	dialog.canceled.emit()
	_check(not dialog.visible and not paused and SaveGame.capture(main) == before, "cancel preserves state and restores previously running game")
	for was_paused in [true,false]:
		paused = was_paused
		gate.request_outpost_entry()
		dialog.close_requested.emit()
		_check(not dialog.visible and paused == was_paused, "window close preserves prior pause " + str(was_paused))
	paused = false
	gate.request_outpost_entry()
	main.map_ui.open()
	_check(not dialog.visible and main.map_ui.is_open() and paused, "new map cancels confirmation before acquiring its own pause")
	dialog.confirmed.emit()
	_check(gate.field == null and gate._session_serial == serial and main.map_ui.is_open() and paused, "stale confirm cannot close a later map or enter")
	main.map_ui.close()
	await process_frame
	_check(not paused and gate.request_outpost_entry(), "returning from map requires and accepts fresh consent")
	_check(SaveGame.apply(main,before), "valid ordinary load is allowed during confirmation")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	_check(not dialog.visible and not paused, "successful load invalidates confirmation and releases only its pause")
	dialog.confirmed.emit()
	_check(gate.field == null and gate._session_serial == serial, "pre-load confirmation cannot create a field")
	await process_frame
	for phase in ["departing","travel","arriving"]:
		gate.request_outpost_entry()
		main.world.phase = phase
		gate._process(0.0)
		dialog.confirmed.emit()
		_check(not dialog.visible and not paused and gate.field == null, "changed trip invalidates danger confirmation " + phase)
		main.world.phase = "stopped"
		gate._show_choice(); gate.show()
	gate.request_outpost_entry()
	main._game_over()
	gate._process(0.0)
	dialog.confirmed.emit()
	_check(not dialog.visible and paused and gate.field == null, "real game-over keeps its pause while invalidating consent")
	main.game_over = false
	paused = false
	gate._show_choice(); gate.show()
	main.workers[0].carrying = GameData.Item.WOOD
	main.workers[0].carry_n = 1
	before = SaveGame.capture(main)
	gate.request_outpost_entry()
	_check(main.operations.stance == stance and SaveGame.capture(main) == before, "even carrying workers receive no recall before confirmation")
	dialog.confirmed.emit()
	_check(gate.field == null and gate.visible_state() == "entry_wait" and main.operations.stance == "recall", "confirmed optional entry delegates to existing readiness and recall")
	_check(bool(gate._entry_options.get("outpost_enabled")) and not paused, "pending entry retains optional mode and restores prior running state")
	dialog.confirmed.emit()
	_check(gate._session_serial == serial and gate.visible_state() == "entry_wait", "double confirm does not duplicate pending entry")
	main.workers[0].carrying = -1; main.workers[0].carry_n = 0
	gate._process(0.0)
	_check(gate.field != null and gate._session_serial == serial + 1, "existing ready path creates one confirmed outpost session")
	if gate.field != null:
		gate.field.process_mode = Node.PROCESS_MODE_DISABLED
		_check(gate.field.session.outpost_enabled and not gate.field.session.mine_path_engineering, "confirmed field is optional outpost not ordinary mining")
		dialog.confirmed.emit()
		_check(gate._session_serial == serial + 1, "stale confirmation after field creation is inert")
		_check(SaveGame.apply(main,before), "normal saved state still restores after confirmed field")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	gate.request_outpost_entry()
	main.queue_free()
	await process_frame
	main = null
	_check(not paused, "freeing the game cannot leak confirmation pause")

func _direct_destination_has_one_entry_decision() -> void:
	print("-- direct C destination entry decision --")
	await _fresh()
	_check(await _move_to_quarry(), "real WorldTrip reaches stopped C")
	var gate = _gate()
	_check(gate != null, "Main owns a normal mine-arrival gate")
	if gate == null:
		return
	_check(gate.visible_state() == "arrival_choice", "stopped C exposes the mine entry decision")
	_check(gate.decline_entry(), "declining mine entry is accepted once")
	_check(main.map_ui.is_open(), "declining delegates the next destination to the existing world map")
	main.map_ui.close()
	_check(main.world.region == "c_quarry" and main.world.phase == "stopped", "declining neither teleports nor starts a new leg")
	_check(gate.field == null and gate.visible_state() == "idle", "declining creates no recovery session")
	_check(not gate.decline_entry(), "a stale decline cannot repeat after its choice is closed")


func _map_reopen_contract() -> void:
	# Breaks caught: no local map action; premature session/recall; stale action
	# stealing another modal/pause or entering while travelling/failed/active.
	await _fresh()
	_check(await _move_to_quarry(), "map reopening fixture reaches real stopped C")
	var gate = _gate()
	_check(gate.decline_entry(), "reopen fixture first declines normal C")
	main.map_ui.close()
	await process_frame
	_check(gate.visible_state() == "idle", "dismissal stays dismissed until explicit input")
	main.map_ui.open()
	var button = main.map_ui.find_child("CReopenChoice", true, false)
	_check(button is Button and button.is_visible_in_tree() and not button.disabled, "stopped C map exposes an enabled local arrival-choice action")
	if not button is Button: return
	_check(gate.has_method("reopen_from_map"), "local map action has a revalidated gate boundary")
	if not gate.has_method("reopen_from_map"): return
	var before: Dictionary = SaveGame.capture(main)
	var serial: int = gate._session_serial
	button.pressed.emit()
	_check(not main.map_ui.is_open() and gate._panel.is_visible_in_tree() and gate.visible_state() == "arrival_choice", "map action closes map and immediately reveals existing C choice")
	_check(not paused and gate.field == null and gate._session_serial == serial and before == SaveGame.capture(main), "reopen restores running state and changes no game/session/save state")
	_check(not gate.reopen_from_map(), "repeated callback with closed map is inert")
	# Map is allowed, every other management panel remains authoritative.
	main.map_ui.open()
	main.inventory_ui._overlay.show()
	_check(not gate.can_reopen_from_map() and not gate.reopen_from_map() and main.map_ui.is_open(), "overlapping other modal is rejected without closing map")
	main.inventory_ui._overlay.hide()
	main.region_clear_ui._overlay.show()
	_check(not gate.reopen_from_map() and main.map_ui.is_open() and paused and main.region_clear_ui._overlay.visible, "completion modal priority and map pause survive rejected reopen")
	main.region_clear_ui._overlay.hide()
	for state in ["entry_wait", "failed", "field"]:
		gate._state = state
		_check(not gate.reopen_from_map() and main.map_ui.is_open(), "stale callback rejects gate state " + state)
	gate._state = "idle"
	for phase in ["departing", "travel", "arriving", "turning"]:
		main.world.phase = phase
		_check(not gate.reopen_from_map() and main.map_ui.is_open(), "stale callback rejects moving phase " + phase)
	main.world.phase = "stopped"
	for site in ["a_start", "b_forest", "d_yard"]:
		main.world.region = site
		main.map_ui._refresh()
		_check(not button.visible and not gate.reopen_from_map(), "other actual site hides/rejects local C entry " + site)
	main.world.region = "c_quarry"
	main.world.active = false
	_check(not gate.reopen_from_map(), "inactive map cannot reopen C")
	main.world.active = true
	main.world.map_profile = WorldMapDB.DESERT
	_check(not gate.reopen_from_map(), "other map profile cannot reopen C")
	main.world.map_profile = WorldMapDB.FIRST_REGION_A
	main.quarry.state = "parked"
	_check(not gate.reopen_from_map(), "legacy quarry mode cannot reopen C")
	main.quarry.state = "road"
	main.game_over = true
	_check(not gate.reopen_from_map(), "game-over cannot reopen C")
	main.game_over = false
	main.map_ui.close()
	paused = true
	main.map_ui.open()
	main.map_ui.select_region("b_forest")
	main.journey.remaining = ["d_yard"]
	before = SaveGame.capture(main)
	_check(gate.reopen_from_map() and paused and before == SaveGame.capture(main), "explicit paused player and reserved onward route survive reopen despite selected other destination")
	main.journey.remaining.clear()
	paused = false
	gate.decline_entry()
	main.workers[0].carrying = GameData.Item.WOOD
	main.workers[0].carry_n = 1
	before = SaveGame.capture(main)
	_check(gate.reopen_from_map() and before == SaveGame.capture(main), "carried cargo does not block choice access or silently recall")
	_check(not gate.enter_mine() and gate.visible_state() == "entry_wait", "ordinary reopened entry still requests existing recall when necessary")
	main.map_ui.open()
	_check(not gate.reopen_from_map() and gate.visible_state() == "entry_wait", "map callback cannot reset an actual pending recall")
	main.map_ui.close()
	gate.cancel_pending_entry()
	main.workers[0].carrying = -1
	main.workers[0].carry_n = 0
	_check(gate.enter_mine(), "reopened choice enters one normal session after existing readiness clears")
	main.map_ui.open()
	_check(not gate.reopen_from_map() and gate.field != null, "active field rejects local map entry")
	main.map_ui.close()
	gate.discard_field_for_load()

func _failed_entry_notice_closes_with_choice() -> void:
	print("-- failed mine entry notice cleanup --")
	await _fresh()
	_check(await _move_to_quarry(), "real WorldTrip reaches C for a failed entry")
	var gate = _gate()
	_check(gate != null and gate.visible_state() == "arrival_choice", "C entry choice is ready for the failed-entry fixture")
	if gate == null or main.workers.is_empty():
		return
	main.workers[0].carrying = GameData.Item.WOOD
	_check(not gate.enter_mine(), "a worker carrying cargo blocks mine entry")
	_check(gate._notice.visible, "the blocked entry keeps its reason visible while the choice is open")
	_check(gate.decline_entry(), "declining after a blocked entry closes the same choice")
	_check(not gate._notice.visible, "declining clears the stale blocked-entry reason")
	_check(main.map_ui.is_open(), "declining a blocked entry still delegates to the existing map")

func _pass_through_and_visit_reservation() -> void:
	print("-- B to C to D pass-through and visit --")
	await _fresh()
	_check(main.journey.plan(["b_forest", "c_quarry", "d_yard"]), "normal JourneyPlan accepts the B-C-D route")
	var offered := false
	var reached_d := false
	for unused in 800:
		await _step_world()
		if main.journey.notice == "c_quarry":
			offered = true
		if main.world.region == "d_yard" and main.world.phase == "stopped":
			reached_d = true
			break
	_check(offered, "C is offered as a nonmodal intermediate mine visit")
	_check(reached_d, "no visit input passes C without forced stop")
	_check(not main.journey.set_stop("c_quarry", true), "a stale C visit action is inert after C has passed")

	await _fresh()
	_check(main.journey.plan(["b_forest", "c_quarry", "d_yard"]), "second normal B-C-D route starts")
	var reserved := false
	for unused in 800:
		await _step_world()
		if main.journey.notice == "c_quarry":
			reserved = main.journey.set_stop("c_quarry", true)
			break
	_check(reserved, "the existing notice reserves C only after explicit visit input")
	var stopped_at_c := false
	for unused in 800:
		await _step_world()
		if main.world.region == "c_quarry" and main.world.phase == "stopped":
			stopped_at_c = true
			break
	_check(stopped_at_c, "reserved C stops before the next leg")
	var gate = _gate()
	_check(gate != null and gate.visible_state() == "arrival_choice", "reserved intermediate C uses the same entry decision")

func _field_commit_restores_normal_c_state() -> void:
	print("-- field entry, one commit, and normal C restore --")
	await _fresh()
	_check(await _move_to_quarry(), "real WorldTrip reaches C for field entry")
	var gate = _gate()
	_check(gate != null and gate.visible_state() == "arrival_choice", "entry gate is ready")
	if gate == null:
		return
	SaveGame.disabled = false
	_check(gate.enter_mine(), "enter mine creates the fixed-quarter recovery field")
	await process_frame
	_check(gate.field != null and gate.field.session != null, "one live recovery adapter owns the session")
	_check(not gate.enter_mine(), "double enter input cannot create a second session")
	_check(SaveGame.disabled, "normal SaveGame is disabled while the field owns uncommitted state")
	if gate.field == null:
		return
	var session = gate.field.session
	_check(session.has_method("is_mine_path_engineering") and bool(session.call("is_mine_path_engineering")), "Normal C entry enables the fixed-base mine-path engineering capability")
	_check(gate.field.maintenance_button != null and gate.field.maintenance_button.visible, "Normal C entry exposes the explicit rubble-clear action")
	var collected := await _advance_until(func(): return int(session.state_summary().depot) > 0, 80.0)
	_check(collected, "fixed-quarter workers gather and haul to the field depot")
	var stock_before := _stock_for_session(session)
	var deposited := int(session.state_summary().depot)
	session.request_recall()
	var recall_detail := str(gate.field.call("_normal_decision_detail", session.state_summary()))
	_check(recall_detail.begins_with("Return preparation:"), "normal field HUD explains that return is draining cargo and workers")
	var ready := await _advance_until(func(): return session.phase == "ready_to_exit", 80.0)
	_check(ready, "return waits for field cargo and workers")
	gate.field.call("_commit_and_exit")
	await process_frame
	await process_frame
	_check(gate.field == null, "adapter exit releases the live field exactly once")
	_check(main.visible and main.process_mode == Node.PROCESS_MODE_INHERIT, "normal vehicle screen is restored")
	_check(main.world.region == "c_quarry" and main.world.phase == "stopped", "field exit returns to the original stopped C state")
	_check(_stock_for_session(session) == stock_before + deposited, "field depot commits to base storage exactly once")
	_check(main.workers.all(func(worker): return worker.carrying < 0 and not worker.away), "all normal workers are restored before departure")
	_check(not SaveGame.disabled, "normal SaveGame state is restored after committed exit")
	_check(gate.visible_state() == "idle", "returned C does not reopen a duplicate entry decision")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var returned_before: Dictionary = SaveGame.capture(main)
	main.map_ui.open()
	_check(gate.has_method("reopen_from_map") and gate.call("reopen_from_map"), "committed return can reopen C without a road detour")
	_check(gate.field == null and returned_before == SaveGame.capture(main), "post-return choice does not re-deposit cargo or reset depleted resources")
	gate.decline_entry(); main.map_ui.close()
	var receipt := str(main.director.log.back().text)
	_check(receipt.contains("車内へ搬入: ") and receipt.contains("Cに残す: なし"), "committed return explains loaded cargo separately from cargo left at C")
	for item in session.commit_summary.deposited:
		_check(receipt.contains("%s×%d" % [GameData.ITEM_NAMES[item], session.commit_summary.deposited[item]]), "real receipt contains each committed canonical item name and exact count")
	_check(not receipt.contains("deposited") and not receipt.contains("equipment") and not receipt.contains("outpost") and not receipt.contains("{"), "normal return note contains no raw diagnostics or implied combat achievement")
	var log_before: Array = main.director.log.duplicate(true)
	gate._on_field_exit({"ok": true, "summary": session.commit_summary.duplicate(true)})
	_check(main.director.log == log_before, "stale duplicate exit does not publish another receipt")
	main.map_ui.open()
	_check(gate.reopen_from_map() and gate.enter_mine(), "returned C creates a second normal session through map without leaving C")
	if gate.field != null:
		gate.field.process_mode = Node.PROCESS_MODE_DISABLED
		var again = gate.field.session
		_check(again != session and gate._session_serial == 2, "local reentry creates exactly one new session")
		_check(again.resources.keys() == session.resources.keys() and again.resources.keys().all(func(id): return again.resources[id].remaining == session.resources[id].remaining), "local reentry retains exact depleted resource counts without a travel reset")
		_check(_stock_for_session(again) == stock_before + deposited, "second entry does not duplicate first committed cargo")
		again.request_recall()
		_check(await _advance_until(func(): return again.phase == "ready_to_exit", 80.0), "second local session safely recalls")
		var again_depot := int(again.state_summary().depot)
		gate.field.call("_commit_and_exit")
		await process_frame
		main.process_mode = Node.PROCESS_MODE_DISABLED
		_check(_stock_for_session(again) == stock_before + deposited + again_depot, "second return adds only its own depot once")
	_check(main.world.request("d_yard"), "normal WorldTrip can choose the next destination after return")

func _return_receipt_contract() -> void:
	print("-- truthful compact cargo receipt --")
	var gate = load("res://bridge/first_region_mine_arrival_gate.gd").new()
	_check(gate.has_method("return_receipt"), "gate provides the actual player-facing return receipt formatter")
	if not gate.has_method("return_receipt"):
		gate.free()
		return
	var result := {"ok": true, "summary": {"deposited": {5: 3, 4: 2}, "left_outside": {6: 1}, "conservation_ok": true, "equipment": {"diagnostic": 99}, "outpost_cleared": true}}
	var unchanged := result.duplicate(true)
	_check(gate.return_receipt(result) == "採掘地から車体へ帰還。車内へ搬入: 木材×2、石×3。Cに残す: 鉄鉱石×1。", "receipt sorts existing item names, separates partial cargo and omits debug/combat claims")
	_check(result == unchanged, "formatting neither reorders nor changes the original result and nested quantities")
	_check(gate.return_receipt({"ok": true, "summary": {"deposited": {}, "left_outside": {5: 0}}}) == "採掘地から車体へ帰還。車内へ搬入: なし。Cに残す: なし。", "valid empty and zero-only cargo report none without inventing a delivery")
	_check(gate.return_receipt({"ok": false, "reason": "拠点が満載", "summary": result.summary}) == "帰還を確認できません: 拠点が満載", "failure reason wins over a misleading success-shaped summary")
	for invalid in [null, [], {}, {"ok": 1, "summary": result.summary}, {"ok": true}, {"ok": true, "summary": []}, {"ok": true, "summary": {}}]:
		var text: String = gate.return_receipt(invalid)
		_check(text.contains("未確認") and not text.contains("帰還。") and not text.contains("なし"), "missing or malformed return data is unconfirmed, not fabricated empty success")
	for bad_cargo in [null, [], {999: 2}, {"5": 2}, {5: -1}, {5: 1.5}, {5: INF}, {5: NAN}, {5: true}, {5: "2"}]:
		var text: String = gate.return_receipt({"ok": true, "summary": {"deposited": bad_cargo, "left_outside": {}}})
		_check(text.contains("車内へ搬入: 未確認") and not text.contains("帰還。"), "unknown item or invalid quantity is visible as unconfirmed instead of coerced or dropped")
	_check(gate.return_receipt({"ok": true, "summary": {"deposited": {5: 2.0}, "left_outside": {}}}).contains("石×2"), "finite whole quantity from compatible decoded data retains its exact count")
	var unbalanced := result.duplicate(true)
	unbalanced.summary.conservation_ok = false
	var warning: String = gate.return_receipt(unbalanced)
	_check(warning.contains("数量の整合") and warning.contains("未確認") and not warning.contains("帰還。"), "explicit conservation failure cannot become an ordinary successful receipt")
	gate.free()

func _live_field_adapter_keeps_processing_after_main_is_hidden() -> void:
	print("-- live field process ownership --")
	await _fresh()
	_check(await _move_to_quarry(), "real WorldTrip reaches C for live field processing")
	var gate = _gate()
	_check(gate != null and gate.enter_mine(), "field enters through the normal arrival decision")
	if gate == null or gate.field == null:
		return
	var session = gate.field.session
	var elapsed_before := float(session.elapsed)
	await create_timer(0.35).timeout
	_check(float(session.elapsed) > elapsed_before, "field session keeps ticking while Main is hidden")
	session.request_recall()
	var ready := false
	for unused in 80:
		await create_timer(0.1).timeout
		if session.phase == "ready_to_exit":
			ready = true
			break
	_check(ready, "normal field adapter reaches a return-ready state without manual session ticks")
	if ready:
		gate.field._update_controls()
		_check(not gate.field.exit_button.disabled, "return-ready state enables the visible exit control")
		gate.field.exit_button.emit_signal("pressed")
		await process_frame
		_check(gate.field == null and main.visible, "visible exit control restores the normal travel screen")


## Regression for the normal player path: the visible clearance command must not
## leave a live C field unable to gather cargo, recall, and expose its visible
## return control. This intentionally uses the adapter's own processing rather
## than direct session.tick() calls.
func _live_mine_path_clearance_can_return_through_visible_controls() -> void:
	print("-- live mine-path clearance and return controls --")
	await _fresh()
	_check(await _move_to_quarry(), "real WorldTrip reaches C for live rubble-clearance processing")
	var gate = _gate()
	_check(gate != null and gate.enter_mine(), "normal C entry opens the live route-engineering field")
	if gate == null or gate.field == null:
		return
	var session = gate.field.session
	gate.field.maintenance_button.emit_signal("pressed")
	await process_frame
	_check(str(session.intermediate_access) == "clearing", "visible rubble-clear command starts the escort task")
	var cleared := false
	for unused in 400:
		await create_timer(0.1).timeout
		if str(session.intermediate_access) == "cleared":
			cleared = true
			break
	_check(cleared, "live escort completes rubble clearance while gather and carry continue")
	session.request_recall()
	var ready := false
	for unused in 800:
		await create_timer(0.1).timeout
		if session.phase == "ready_to_exit":
			ready = true
			break
	_check(ready, "cleared live mine session drains workers and cargo for return")
	if ready:
		gate.field._update_controls()
		_check(not gate.field.exit_button.disabled, "cleared live mine exposes the visible return control")
		gate.field.exit_button.emit_signal("pressed")
		await process_frame
		_check(gate.field == null and main.visible and main.world.region == "c_quarry" and main.world.phase == "stopped", "visible return control commits cleared C and restores stopped road state")


## Regression for the ordinary revisit: after the player commits a cleared C
## session, leaves C, and comes back, the actual visible entry button must
## start exactly one new field session.  This uses a viewport pointer event,
## rather than calling enter_mine(), to cover the same UI boundary as a mouse.
func _cleared_quarry_revisit_enters_from_the_visible_choice() -> void:
	print("-- cleared C revisit visible entry --")
	await _fresh()
	_check(await _move_to_quarry(), "real WorldTrip reaches C before the cleared-revisit fixture")
	var gate = _gate()
	_check(gate != null and gate.enter_mine(), "fixture opens the first C field")
	if gate == null or gate.field == null:
		return
	var session = gate.field.session
	var clearance: Dictionary = session.request_intermediate_clearance()
	_check(bool(clearance.get("ok", false)), "fixture explicitly starts rubble clearance")
	_check(await _advance_until(func(): return str(session.intermediate_access) == "cleared", 48.0), "fixture clears the cart shortcut before returning")
	session.request_recall()
	_check(await _advance_until(func(): return session.phase == "ready_to_exit", 80.0), "fixture reaches return-ready before committing C")
	gate.field._update_controls()
	_check(not gate.field.exit_button.disabled, "fixture exposes the enabled visible return confirmation")
	gate.field.exit_button.emit_signal("pressed")
	await process_frame
	_check(gate.field == null and main.world.region == "c_quarry" and main.world.phase == "stopped", "fixture commits the cleared C field")
	_check(await _move_leg("b_forest"), "normal road travel leaves C after the committed field")
	_check(await _move_leg("c_quarry"), "normal road travel returns to stopped C")
	_check(gate.visible_state() == "arrival_choice", "revisited C exposes one fresh entry choice")
	var enter_button: Button = gate.get("_enter_button")
	_check(enter_button != null and enter_button.visible and not enter_button.disabled, "revisit keeps the visible mine-entry button enabled")
	if enter_button == null or enter_button.disabled:
		return
	var point := enter_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
		await process_frame
	_check(gate.visible_state() in ["entry_wait", "field"], "revisit pointer click starts exactly one new C field entry")
	for unused in 800:
		if gate.visible_state() == "field":
			break
		await process_frame
	_check(gate.visible_state() == "field" and gate.field != null, "revisit pointer entry completes without a second click")
	if gate.field != null:
		_check(str(gate.field.session.intermediate_access) == "cleared", "revisited field receives the committed cart-shortcut state")


## The route flag is deliberately independent of ordinary finite resources.  A
## player who cleared rubble, later exhausted the last C deposit, left, and
## came back must still be able to enter the fixed field and see the cleared
## route.  This fixture changes only the persisted C gather ledger after a
## normal committed return; it does not seed, respawn, or inject an item.
func _cleared_quarry_with_depleted_resources_still_enters_for_route_inspection() -> void:
	print("-- cleared C depleted-resource revisit --")
	await _fresh()
	_check(await _move_to_quarry(), "real WorldTrip reaches C before the depleted-revisit fixture")
	var gate = _gate()
	_check(gate != null and gate.enter_mine(), "depleted-revisit fixture opens the first C field")
	if gate == null or gate.field == null:
		return
	var session = gate.field.session
	var clearance: Dictionary = session.request_intermediate_clearance()
	_check(bool(clearance.get("ok", false)), "depleted-revisit fixture starts rubble clearance")
	_check(await _advance_until(func(): return str(session.intermediate_access) == "cleared", 48.0), "depleted-revisit fixture clears the cart shortcut")
	session.request_recall()
	_check(await _advance_until(func(): return session.phase == "ready_to_exit", 80.0), "depleted-revisit fixture reaches return-ready")
	gate.field._update_controls()
	_check(not gate.field.exit_button.disabled, "depleted-revisit fixture exposes the visible return confirmation")
	gate.field.exit_button.emit_signal("pressed")
	await process_frame
	_check(gate.field == null and main.world.region == "c_quarry" and main.world.phase == "stopped", "depleted-revisit fixture commits cleared C")
	_exhaust_c_quarry_gather_ledger()
	_check(_c_quarry_gather_ledger_is_empty(), "fixture represents a normally exhausted C finite gather ledger")
	_check(await _move_leg("b_forest"), "normal road travel leaves cleared, exhausted C")
	_check(await _move_leg("c_quarry"), "normal road travel returns to cleared, exhausted C")
	_check(gate.visible_state() == "arrival_choice", "exhausted revisit exposes a fresh C entry choice")
	var enter_button: Button = gate.get("_enter_button")
	_check(enter_button != null and enter_button.visible and not enter_button.disabled, "exhausted revisit keeps the visible mine-entry button enabled")
	if enter_button == null or enter_button.disabled:
		return
	var point := enter_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
		await process_frame
	_check(gate.visible_state() in ["entry_wait", "field"], "cleared C with no remaining deposits still begins one inspectable field entry")
	for unused in 120:
		if gate.visible_state() == "field":
			break
		await process_frame
	_check(gate.visible_state() == "field" and gate.field != null, "depleted revisit completes field entry without a second click")
	if gate.field != null:
		_check(gate.field.session.total_source_remaining()==0 and gate.field.session.initial_total()==0 and gate.field.session.ResourceGrowth.total(gate.field.session)==0, "depleted revisit retains empty source IDs without immediate resources")
		_check(str(gate.field.session.intermediate_access) == "cleared", "depleted revisit still displays the committed cart shortcut")


func _exhaust_c_quarry_gather_ledger() -> void:
	var location_key := "region:c_quarry"
	# WorldTrip serializes the still-visible road gather points on every normal
	# tick.  Deplete those authoritative live nodes first, then sync the ledger;
	# changing a detached Dictionary alone would be overwritten on departure.
	for node in main.resources_root.get_children():
		if node is GatherPoint and not node.has_meta("quarry_id"):
			node.remaining = 0
	main.world.sync()
	var rows: Dictionary = Dictionary(main.world.locations.get(location_key, {})).duplicate(true)
	for entity_id in rows:
		var row: Dictionary = Dictionary(rows[entity_id])
		if str(row.get("type", "")) != "gather":
			continue
		var data: Dictionary = Dictionary(row.get("data", {}))
		data["remaining"] = 0
		row["data"] = data
		rows[entity_id] = row
	main.world.locations[location_key] = rows


func _c_quarry_gather_ledger_is_empty() -> bool:
	for entity_id in Dictionary(main.world.locations.get("region:c_quarry", {})):
		var row: Dictionary = Dictionary(main.world.locations["region:c_quarry"][entity_id])
		if str(row.get("type", "")) == "gather" and int(Dictionary(row.get("data", {})).get("remaining", 0)) > 0:
			return false
	return true
