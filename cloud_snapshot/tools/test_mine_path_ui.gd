extends SceneTree
## UI and presentation contract for the normal C-quarry route-engineering
## prototype.  Signals exercise production handlers; this is not a physical
## pointer claim.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")
const STEP := 0.2

var main
var field
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	SaveGame.disabled = true
	await _fresh()
	if main == null:
		_finish()
		return
	main.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
	_check(main.equip_work_support(main.workers[1], GameData.Item.HANDCART), "Fixture equips the existing cart carrier")
	var created: Dictionary = RouteSession.create_from_game(main, "mine-path-ui", {"mine_path_engineering": true})
	_check(bool(created.get("ok", false)), "Normal C creates the mine-path session for UI wiring")
	if not bool(created.get("ok", false)):
		_finish()
		return
	main.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	field = FieldAdapter.new()
	field.configure(main, created.session)
	layer.add_child(field)
	await process_frame
	field.process_mode = Node.PROCESS_MODE_DISABLED
	field._update_controls()
	_check(field.status_label.text.begins_with("地上資源 %d" % field.session.total_source_remaining()), "Normal mixed resource total is not labelled ore")
	_check(field.status_label.tooltip_text.contains("木材") and field.status_label.tooltip_text.contains("石材") and field.status_label.tooltip_text.contains("鉄鉱石"), "Resource aggregate tooltip names the three kinds")
	_check_capacity_feedback()
	print("MINE PATH VEHICLE RECTS ", field.vehicle_pause_button.get_global_rect())
	_check(field.maintenance_button != null and field.maintenance_button.visible, "Normal C exposes an explicit rubble-clear action without vertical parking")
	var terrain = field.canyon_hub.get_node_or_null("Terrain")
	var shortcut_probe: Vector2 = RouteSession.BASE.lerp(RouteSession.MINE_PATH_CART_SHORTCUT, 0.5)
	_check(terrain != null and terrain.has_method("mine_path_visual_routes"), "Quarry terrain exposes display-only backpack, cart-detour, and cart-shortcut routes")
	if terrain != null and terrain.has_method("mine_path_visual_routes"):
		var blocked: Dictionary = terrain.call("mine_path_visual_routes", field.canyon_hub)
		_check(str(blocked.get("cart_active", "")) == "cart_detour" and bool(blocked.get("rubble_visible", false)), "Blocked C displays the cart detour and rubble")
		_check(not field.canyon_hub.walkable_contains(shortcut_probe), "Blocked rubble shortcut is not presented as walkable")
	field.session.set_all_routes_closed(true)
	_check(field._normal_decision_detail(field.session.state_summary()).begins_with("Stopped:"), "Normal C shows the safe-wait reason before route availability")
	field.session.set_all_routes_closed(false)
	field.maintenance_button.emit_signal("pressed")
	await process_frame
	field._update_controls()
	_check(str(field.session.intermediate_access) == "clearing" and field.maintenance_button.visible and field.maintenance_button.text.contains("Cancel"), "The same normal-C action visibly changes to clearance cancellation while a worker is assigned")
	field.maintenance_button.emit_signal("pressed")
	await process_frame
	field._update_controls()
	_check(str(field.session.intermediate_access) == "blocked", "The visible cancellation action restores the blocked cart route")
	field.maintenance_button.emit_signal("pressed")
	var cleared := await _advance_until(func(): return str(field.session.intermediate_access) == "cleared", 30.0)
	field._update_controls()
	_check(cleared, "The explicit C rubble order completes through the live session")
	if terrain != null and terrain.has_method("mine_path_visual_routes"):
		var open: Dictionary = terrain.call("mine_path_visual_routes", field.canyon_hub)
		var carry: Dictionary = field.session.actors.get("worker:1", {})
		_check(str(open.get("cart_active", "")) == str(carry.get("route", "")) and not bool(open.get("rubble_visible", true)), "Cleared C keeps the live cart route highlighted until its next leg and removes the rubble")
		_check(field.canyon_hub.walkable_contains(shortcut_probe), "Cleared shortcut becomes walkable in the matching presentation model")

	_check(await _advance_until(func(): return field.session._stock_total(field.session.depot_stock) > 0, 120.0), "UI fixture has real deposited cargo before capacity check")
	field.session.request_recall()
	_check(await _advance_until(func(): return field.session.phase == "ready_to_exit", 120.0), "UI fixture reaches ready return")
	# Force a real preflight rejection without mutating inventory or bypassing source checks.
	var source: String = field.session.resources.keys()[0]
	field.session.resources[source].initial += 1
	field._commit_and_exit()
	var rejected: String = field.notice_label.text
	field._update_controls()
	_check(rejected != "帰還可: 搬入を一度だけ確定" and field.notice_label.text == rejected, "Return rejection stays visible across control refresh")
	field.session.resources[source].initial -= 1
	_check(field.get("return_confirmation") is ConfirmationDialog, "Normal return has a standard explicit leftover confirmation")
	if field.get("return_confirmation") is ConfirmationDialog:
		_check(not field.return_confirmation.dialog_hide_on_ok, "Changed preview remains visible instead of auto-hiding after confirm")
		var room: int = main.storage.max_weight() - main.storage.current_weight() - main.storage.processing_reserve()
		main.storage.store_owned(GameData.Item.FOOD, maxi(0, room - 1), Inventory.SOURCE_TRANSFER)
		var before := SaveGame.capture(main)
		var field_before: Dictionary = field.session.to_dict()
		field._commit_and_exit()
		_check(field.return_confirmation.visible and field.return_confirmation.dialog_text.contains("車内へ搬入") and field.return_confirmation.dialog_text.contains("Cに残す"), "Overflow click presents both promised quantities")
		field.return_confirmation.canceled.emit(); field.return_confirmation.hide()
		_check(SaveGame.capture(main) == before and field.session.to_dict() == field_before, "Cancel preserves people, cargo, source IDs, goal and session exactly")
		field._commit_and_exit()
		main.storage.inventory.take_n(GameData.Item.FOOD, 6)
		var changed := SaveGame.capture(main)
		field.return_confirmation.confirmed.emit()
		_check(field.return_confirmation.visible and field.return_confirmation.dialog_text.contains("変わりました") and SaveGame.capture(main) == changed and not field.session.committed, "Changed capacity refreshes the visible promise without executing")
		field.return_confirmation.canceled.emit(); field.return_confirmation.hide()

	_finish()

func _check_capacity_feedback() -> void:
	# Display fixtures only: use a separate session; never project these edge
	# cases onto live workers or save them as an ordinary-input playthrough.
	var original = field.session
	var restored: Dictionary = RouteSession.from_dict(original.to_dict())
	_check(bool(restored.get("ok", false)), "Capacity display fixture clones the valid live session")
	if not bool(restored.get("ok", false)):
		return
	field.session = restored.session
	field.session.field_capacity_limit_weight = 8
	field.session.relay_stock = {GameData.Item.STONE: 1}
	for resource in field.session.resources.values():
		resource.remaining = 0
		resource.reservation = ""
	var candidate: Dictionary = field.session.resources.values()[0]
	candidate.item = GameData.Item.STONE
	candidate.remaining = 2
	var actor: Dictionary = field.session.actors.values()[0]
	actor.wait_reason = RouteSession.NORMAL_CAPACITY_WAIT
	for access in ["blocked", "clearing", "cleared"]:
		field.session.intermediate_access = access
		var before: Dictionary = field.session.to_dict()
		var save_before: Dictionary = SaveGame.capture(main)
		field._update_controls()
		_check(field.detail_label.visible and field.detail_label.text.contains("採取停止") and field.detail_label.text.contains("積載") and field.detail_label.text.contains("売却"), "Positive but insufficient room explains collection stop before %s route guidance" % access)
		_check(field.session.to_dict() == before and SaveGame.capture(main) == save_before, "Capacity explanation is display-only for %s" % access)
	field.session.field_capacity_limit_weight = 6
	field._update_controls()
	_check(field.detail_label.text.contains("採取停止"), "Zero remaining allowance also explains the full-load stop")
	candidate.reservation = "worker:0"
	field._update_controls()
	_check(not field.detail_label.text.contains("採取停止"), "Wholly reserved ground is not falsely labelled capacity-stopped")
	candidate.reservation = ""
	candidate.remaining = 0
	field._update_controls()
	_check(not field.detail_label.text.contains("採取停止"), "Depleted ground is not falsely labelled capacity-stopped")
	candidate.remaining = 2
	field.session.field_capacity_limit_weight = 10
	var light: Dictionary = field.session.resources.values()[1]
	light.item = GameData.Item.WOOD
	light.remaining = 1
	field._update_controls()
	_check(not field.detail_label.text.contains("採取停止"), "A fitting unreserved lighter candidate prevents a false global stop")
	light.remaining = 0
	field.session.field_capacity_limit_weight = 12
	field._update_controls()
	_check(not field.detail_label.text.contains("採取停止") and actor.wait_reason == RouteSession.NORMAL_CAPACITY_WAIT, "Recovered room removes warning despite stale actor wait text")
	field.session.field_capacity_limit_weight = 6
	for phase in ["recall", "ready_to_exit"]:
		field.session.phase = phase
		field._update_controls()
		_check(field.detail_label.text.begins_with("Return"), "%s instruction wins over capacity" % phase)
	field.session.phase = "local"
	field.session.all_routes_closed = true
	field._update_controls()
	_check(field.detail_label.text.begins_with("Stopped:"), "All-routes closure wins over capacity")
	field.session.all_routes_closed = false
	for flag in ["outpost_enabled", "vertical_slice", "single_worker_demo"]:
		field.session.set(flag, true)
		_check(not field._normal_decision_detail(field.session.state_summary()).contains("採取停止"), "%s is outside ordinary C capacity guidance" % flag)
		field.session.set(flag, false)
	field.session = original
	field._update_controls()

func _fresh() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
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
	if not await _move_leg("b_forest") or not await _move_leg("c_quarry"):
		_check(false, "Fixture reaches the normal stopped C quarry")
		main.free()
		main = null

func _move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 320:
		main._process(STEP)
		await process_frame
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return main.world.phase == "stopped" and main.world.region == destination

func _advance_until(predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		field.session.tick(STEP)
		var projected: Dictionary = field.session.apply_projection_to_workers(main)
		if not bool(projected.get("ok", false)):
			return false
		if predicate.call():
			return true
	return predicate.call()

func _finish() -> void:
	if field != null and is_instance_valid(field):
		var layer: Node = field.get_parent()
		field.queue_free()
		if layer != null:
			layer.queue_free()
	if main != null and is_instance_valid(main):
		main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("MINE PATH UI failures=", fails)
	quit(1 if fails else 0)
