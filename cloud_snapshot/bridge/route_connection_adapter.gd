class_name RecoveryRouteConnectionAdapter
extends Control
## 固定クォータービューの表示と操作だけを担う bridge UI。
## 状態の正本は RecoveryRouteConnectionSession で、ここは既存 Worker の投影先である。

signal exit_to_horizontal(result: Dictionary)

const CanyonHubScene = preload("res://scenes/canyon/canyon_recovery_hub.tscn")
const CanyonRouteGuideScene = preload("res://scenes/canyon/components/canyon_route_guide.gd")

var game
var _discarding_for_load := false
var session
var canyon_hub: CanyonRecoveryHub
var enemy_layer: Node2D
var actor_layer: Node2D
var enemy_views := {}
var original_parents := {}
var original_positions := {}
var original_process_modes := {}
var original_visibilities := {}
var title_label: Label
var life_clock
var vehicle_status_label: Label
var crew_health_label: Label
var vehicle_pause_button: Button
var vehicle_return_button: Button
var _vehicle_return_action := ""
var _vehicle_return_session
var _vehicle_return_clock
var _owns_field_pause := false
var _return_failure := ""
var return_confirmation: ConfirmationDialog
var _return_plan := {}
var _return_session
var _return_clock
var life_status_label: Label
var status_label: Label
var detail_label: Label
var cargo_status_label: Label
var capacity_status_label: Label
var field_tool_status_label: Label
var worker_rows: VBoxContainer
var worker_status_labels: Array[Label] = []
var notice_label: Label
var gate_button: Button
var block_button: Button
var dock_button: Button
var exit_button: Button
var maintenance_button: Button
var reposition_button: Button
var reposition_cancel_button: Button
var capacity_refresh_button: Button
var field_frame_button: Button
var field_tool_button: Button
var return_handcart_button: Button
var equipment_cancel_button: Button
var controls_panel: PanelContainer
var controls_box: VBoxContainer
var controls_grid: GridContainer
var control_buttons: Array[Button] = []
var route_guide
var route_guide_button: Button
var rescue_panel
var rescue_toggle: Button

func configure(p_game, p_session) -> void:
	if rescue_panel != null: rescue_panel.invalidate()
	game = p_game
	session = p_session
	if session.is_mine_path_engineering(): session.refresh_capacity_from_game(game)
	life_clock = preload("res://bridge/field_survival_clock.gd").new()
	var life_bound: Dictionary = life_clock.setup(game, session)
	if not life_bound.ok: life_clock.reason = str(life_bound.reason)
	# A real storage inventory change is an event-driven capacity refresh, not a
	# per-frame free-space poll.  Projected worker hands are accounted for by the
	# session refresh helper, so this remains safe for the vertical slice.
	if game != null and game.storage != null and game.storage.inventory != null and not game.storage.inventory.changed.is_connected(_on_storage_inventory_changed):
		game.storage.inventory.changed.connect(_on_storage_inventory_changed)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_canyon_hub()
	_build_route_guide()
	enemy_layer = Node2D.new()
	enemy_layer.name = "ProjectedOutpostEnemies"
	enemy_layer.z_index = 3
	add_child(enemy_layer)
	actor_layer = Node2D.new()
	actor_layer.name = "ProjectedWorkers"
	actor_layer.z_index = 4
	add_child(actor_layer)
	_build_controls()
	_build_vehicle_status()
	_build_rescue_panel()
	_build_return_confirmation()
	if not life_clock.is_current():
		_notice(life_clock.reason)
		for button in control_buttons: button.disabled = true
		return
	game.set_meta("c_rescue_current_adapter", get_instance_id())
	_take_workers()
	var projection: Dictionary = _apply_worker_projection()
	if not bool(projection.get("ok", false)):
		_notice(str(projection.get("reason", "仲間の投影を開始できません")))
	_sync_outpost_enemies()
	queue_redraw()

func _build_canyon_hub() -> void:
	canyon_hub = CanyonHubScene.instantiate()
	canyon_hub.name = "CanyonRecoveryHub"
	canyon_hub.z_index = 0
	add_child(canyon_hub)
	var design_size := size if size.x > 0.0 and size.y > 0.0 else Vector2(1280, 720)
	canyon_hub.set_view_size(design_size)
	canyon_hub.configure(session)

func _build_route_guide() -> void:
	route_guide = CanyonRouteGuideScene.new()
	route_guide.name = "CanyonRouteGuide"
	route_guide.position = Vector2(16, 48)
	route_guide.size = Vector2(360, 270)
	route_guide.z_index = 20
	route_guide.configure(session)
	route_guide.hide()
	add_child(route_guide)
	route_guide_button = Button.new()
	route_guide_button.name = "RouteGuideToggle"
	route_guide_button.position = Vector2(16, 14)
	route_guide_button.size = Vector2(152, 28)
	route_guide_button.z_index = 21
	route_guide_button.text = "経路案内図"
	route_guide_button.pressed.connect(_toggle_route_guide)
	add_child(route_guide_button)

func _toggle_route_guide() -> void:
	if rescue_panel != null: rescue_panel.close_panel()
	if route_guide == null:
		return
	route_guide.visible = not route_guide.visible
	if route_guide.visible:
		route_guide.refresh_from_session()
	_update_controls()

func _exit_tree() -> void:
	if rescue_panel != null: rescue_panel.invalidate()
	if is_instance_valid(game) and int(game.get_meta("c_rescue_current_adapter", -1)) == get_instance_id():
		game.remove_meta("c_rescue_current_adapter")
	if game != null and game.storage != null and game.storage.inventory != null and game.storage.inventory.changed.is_connected(_on_storage_inventory_changed):
		game.storage.inventory.changed.disconnect(_on_storage_inventory_changed)
	if not _discarding_for_load and session != null and life_clock != null and life_clock.is_current() and not bool(session.get("committed")) and session.has_method("release_uncommitted_field_tool_kits"):
		session.call("release_uncommitted_field_tool_kits", game)
	if is_instance_valid(game) and game.world != null: game.world.release_regeneration(session,true)
	_restore_workers()

func _on_storage_inventory_changed() -> void:
	if session != null and session.is_mine_path_engineering() and not session.committed:
		session.refresh_capacity_from_game(game)
		return
	if session == null or not session.has_method("is_vertical_slice") or not bool(session.call("is_vertical_slice")):
		return
	if not bool(session.state_summary().get("capacity_paused", false)):
		return
	var refreshed: Dictionary = session.refresh_capacity_from_game(game)
	if bool(refreshed.get("ok", false)):
		_notice("容量変化を検知: 保持貨物を再判定")

func _process(delta: float) -> void:
	if session == null or get_tree().paused or game.game_over:
		return
	life_clock.tick(delta)
	if game.game_over: return
	if not life_clock.is_current():
		_notice(life_clock.reason)
		for button in control_buttons: button.disabled = true
		return
	var projected: Dictionary = _apply_worker_projection()
	if not bool(projected.get("ok", false)):
		_notice(str(projected.get("reason", "仲間の照合が一致しません")))
	_sync_outpost_enemies()
	if canyon_hub != null:
		canyon_hub.refresh(delta)
	_update_controls()
	queue_redraw()

func _take_workers() -> void:
	if game == null:
		return
	for worker in game.workers:
		if not is_instance_valid(worker) or worker.get_parent() == actor_layer:
			continue
		var key: int = worker.get_instance_id()
		original_parents[key] = worker.get_parent()
		original_positions[key] = worker.position
		original_process_modes[key] = worker.process_mode
		original_visibilities[key] = worker.visible
		worker.get_parent().remove_child(worker)
		actor_layer.add_child(worker)
		worker.process_mode = Node.PROCESS_MODE_DISABLED
		# The native side-on Worker stays alive for session projection but is
		# hidden only inside this quarter-view adapter. CanyonCrewViews mirrors
		# its session actor with a human, footpoint-aligned sprite.
		worker.visible = false

## Keep the session's source coordinates authoritative, but mirror each visual
## position instead of mirroring its whole CanvasItem hierarchy.  A negative
## parent scale also mirrors Worker/Enemy status text, which makes the real
## projected names and activity display unreadable.
func _apply_worker_projection() -> Dictionary:
	if life_clock == null or not life_clock.is_current():
		return {"ok": false, "reason": "古い現地表示から本体の生命状態を上書きしません"}
	var projection: Dictionary = session.apply_projection_to_workers(game)
	if not bool(projection.get("ok", false)) or actor_layer == null:
		return projection
	for worker in actor_layer.get_children():
		if worker is Node2D:
			var projected_worker: Node2D = worker as Node2D
			projected_worker.position = _presentation_point(projected_worker.position)
	return projection

func _presentation_point(source: Vector2) -> Vector2:
	if canyon_hub != null:
		if session != null and session.has_method("is_vertical_slice") and bool(session.call("is_vertical_slice")):
			return canyon_hub.presentation_point_for_actor({"x": source.x, "y": source.y})
		return canyon_hub.map_point(source)
	return Vector2(roundf(size.x - source.x), roundf(source.y))

func _restore_workers() -> void:
	if actor_layer == null:
		return
	for worker in actor_layer.get_children():
		var key: int = worker.get_instance_id()
		var parent: Node = original_parents.get(key, null)
		if parent == null or not is_instance_valid(parent):
			continue
		actor_layer.remove_child(worker)
		parent.add_child(worker)
		worker.process_mode = int(original_process_modes.get(key, Node.PROCESS_MODE_INHERIT))
		if life_clock != null and life_clock.is_current():
			worker.position = game.storage.access_point() + worker.slot_offset if session.committed and session.rescue_approach.treatment_pending("worker:%d" % game.workers.find(worker)) else original_positions.get(key, worker.position)
		worker.visible = bool(original_visibilities.get(key, true))
	original_parents.clear()
	original_positions.clear()
	original_process_modes.clear()
	original_visibilities.clear()

func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.name = "RouteControls"
	# Keep the live controls accessible, but reserve the upper centre for the
	# canyon instead of leaving a large translucent empty card.
	panel.position = Vector2(507, 14)
	panel.size = Vector2(266, 108)
	panel.z_index = 10
	panel.modulate = Color(1.0, 1.0, 1.0, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	controls_panel = panel
	var box := VBoxContainer.new()
	box.name = "Contents"
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	controls_box = box
	title_label = Label.new()
	title_label.name = "Title"
	title_label.add_theme_font_size_override("font_size", 12)
	box.add_child(title_label)
	status_label = Label.new()
	status_label.name = "ParkingStatus"
	status_label.add_theme_font_size_override("font_size", 10)
	box.add_child(status_label)
	detail_label = Label.new()
	detail_label.name = "DetailStatus"
	detail_label.add_theme_font_size_override("font_size", 9)
	box.add_child(detail_label)
	life_status_label = Label.new()
	life_status_label.name = "FieldSurvivalStatus"
	life_status_label.add_theme_font_size_override("font_size", 9)
	box.add_child(life_status_label)
	cargo_status_label = Label.new()
	cargo_status_label.name = "CargoStatus"
	cargo_status_label.visible = false
	box.add_child(cargo_status_label)
	capacity_status_label = Label.new()
	capacity_status_label.name = "CapacityStatus"
	capacity_status_label.visible = false
	box.add_child(capacity_status_label)
	worker_rows = VBoxContainer.new()
	worker_rows.name = "WorkerRows"
	worker_rows.add_theme_constant_override("separation", 0)
	worker_rows.visible = false
	box.add_child(worker_rows)
	for index in 3:
		var worker_label := Label.new()
		worker_label.name = "WorkerStatus_%d" % index
		worker_label.visible = false
		worker_rows.add_child(worker_label)
		worker_status_labels.append(worker_label)
	field_tool_status_label = Label.new()
	field_tool_status_label.name = "FieldToolStatus"
	field_tool_status_label.visible = false
	field_tool_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	field_tool_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	field_tool_status_label.custom_minimum_size = Vector2(0, 10)
	field_tool_status_label.add_theme_font_size_override("font_size", 8)
	box.add_child(field_tool_status_label)
	var grid := GridContainer.new()
	grid.name = "ActionGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	box.add_child(grid)
	controls_grid = grid
	var return_button := Button.new()
	return_button.text = "撤退"
	return_button.pressed.connect(func():
		session.request_recall()
		_notice("現地の手持ち・relay・入口列を解消してから横視点へ戻ります")
	)
	grid.add_child(return_button)
	gate_button = Button.new()
	gate_button.pressed.connect(_toggle_gate)
	grid.add_child(gate_button)
	block_button = Button.new()
	block_button.pressed.connect(_toggle_all_routes)
	grid.add_child(block_button)
	dock_button = Button.new()
	dock_button.pressed.connect(_toggle_dock_count)
	grid.add_child(dock_button)
	var save_button := Button.new()
	save_button.text = "検証保存"
	save_button.pressed.connect(_save_fixture)
	grid.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "検証読込"
	load_button.pressed.connect(_load_fixture)
	grid.add_child(load_button)
	exit_button = Button.new()
	exit_button.text = "帰還→横視点"
	exit_button.pressed.connect(_commit_and_exit)
	grid.add_child(exit_button)
	maintenance_button = Button.new()
	maintenance_button.text = "整備"
	maintenance_button.pressed.connect(_request_intermediate_clearance)
	grid.add_child(maintenance_button)
	reposition_button = Button.new()
	reposition_button.text = "中継停車"
	reposition_button.pressed.connect(_request_reposition)
	grid.add_child(reposition_button)
	reposition_cancel_button = Button.new()
	reposition_cancel_button.text = "停車取消"
	reposition_cancel_button.pressed.connect(_cancel_reposition)
	grid.add_child(reposition_cancel_button)
	capacity_refresh_button = Button.new()
	capacity_refresh_button.text = "容量更新"
	capacity_refresh_button.pressed.connect(_refresh_capacity)
	grid.add_child(capacity_refresh_button)
	field_frame_button = Button.new()
	field_frame_button.name = "FieldFrameExchange"
	field_frame_button.text = "現地:フレーム"
	field_frame_button.pressed.connect(_request_field_frame_to_harvest)
	grid.add_child(field_frame_button)
	field_tool_button = Button.new()
	field_tool_button.name = "FieldToolSwap"
	field_tool_button.text = "現地:採掘具"
	field_tool_button.pressed.connect(_request_field_tool_swap)
	grid.add_child(field_tool_button)
	return_handcart_button = Button.new()
	return_handcart_button.name = "ReturnHandcartExchange"
	return_handcart_button.text = "拠点:手押し車"
	return_handcart_button.tooltip_text = "手押し車は拠点専用です。現地では交換せず、帰還後の交換予約だけを出します。"
	return_handcart_button.pressed.connect(_request_return_handcart_exchange)
	grid.add_child(return_handcart_button)
	equipment_cancel_button = Button.new()
	equipment_cancel_button.name = "EquipmentExchangeCancel"
	equipment_cancel_button.text = "装備取消"
	equipment_cancel_button.pressed.connect(_cancel_equipment_exchange)
	grid.add_child(equipment_cancel_button)
	control_buttons = [return_button, gate_button, block_button, dock_button, save_button, load_button, exit_button, maintenance_button, reposition_button, reposition_cancel_button, capacity_refresh_button, field_frame_button, field_tool_button, return_handcart_button, equipment_cancel_button]
	for button in control_buttons:
		button.custom_minimum_size = Vector2(61, 18)
		button.add_theme_font_size_override("font_size", 8)
	notice_label = Label.new()
	notice_label.name = "Notice"
	# Match the inherited compact HUD until the vertical-only layout asks for a
	# wrapped notice; normal and single-worker panels must retain their v14 text
	# behaviour.
	notice_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	notice_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	notice_label.add_theme_font_size_override("font_size", 8)
	notice_label.modulate = Color("ffd38a")
	notice_label.visible = false
	box.add_child(notice_label)
	_update_controls()

func _update_controls() -> void:
	_update_vehicle_return()
	if vehicle_status_label != null:
		vehicle_status_label.text = life_clock.vehicle_status_text()
		vehicle_status_label.modulate = Color("ffd38a") if "!" in vehicle_status_label.text else Color.WHITE
	if crew_health_label != null and session != null:
		crew_health_label.text = _crew_health_text()
	if life_status_label != null and life_clock != null:
		life_status_label.text = life_clock.status_text()
	if session == null or status_label == null:
		return
	var summary: Dictionary = session.state_summary()
	var single_demo: bool = session.has_method("is_single_worker_demo") and bool(session.call("is_single_worker_demo"))
	var vertical: bool = session.has_method("is_vertical_slice") and bool(session.call("is_vertical_slice"))
	var mine_path: bool = session.has_method("is_mine_path_engineering") and bool(session.call("is_mine_path_engineering"))
	if route_guide_button != null:
		route_guide_button.visible = mine_path
		route_guide_button.disabled = not mine_path
		route_guide_button.text = "経路案内図: 閉じる" if route_guide != null and route_guide.visible else "経路案内図"
	if route_guide != null:
		if not mine_path:
			route_guide.hide()
		elif route_guide.visible:
			route_guide.refresh_from_session()
	if controls_panel != null:
		controls_panel.position = Vector2(16, 486) if vertical else Vector2(507, 14)
		controls_panel.size = Vector2(448, 218) if vertical else Vector2(266, 108)
		controls_panel.modulate = Color(1.0, 1.0, 1.0, 0.97) if vertical else Color(1.0, 1.0, 1.0, 0.92)
	if controls_box != null:
		controls_box.add_theme_constant_override("separation", 0 if vertical else 3)
	if controls_grid != null:
		controls_grid.columns = 5 if vertical else 4
		controls_grid.add_theme_constant_override("h_separation", 3)
		controls_grid.add_theme_constant_override("v_separation", 0 if vertical else 3)
	if notice_label != null:
		notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if vertical else TextServer.AUTOWRAP_OFF
		notice_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if vertical else TextServer.OVERRUN_NO_TRIMMING
	for button in control_buttons:
		button.custom_minimum_size = Vector2(85, 15) if vertical else Vector2(61, 18)
		button.add_theme_font_size_override("font_size", 8 if vertical else 8)
	if title_label != null:
		title_label.add_theme_font_size_override("font_size", 12 if vertical else 12)
		title_label.text = "峡谷回収拠点 / 単独追跡検証" if single_demo else ("峡谷回収拠点 / 入口固定停車" if vertical else "峡谷回収拠点 / C採石場")
	var outpost_text := "前哨地なし"
	if mine_path and title_label != null:
		title_label.text = "C Quarry / Route work"
	if bool(summary.get("outpost_enabled", false)):
		outpost_text = "敵 %d/%d" % [int(summary.outpost_remaining), int(summary.outpost_total)]
	if vertical:
		var parked_text := "中継" if str(summary.get("parking_slot", "entry")) == "relay" else "入口"
		var phase_text := "通常分業"
		if session.phase == "reposition_recall":
			var target_slot := str(summary.get("reposition_target_slot", "entry"))
			phase_text = ("中継" if target_slot == "relay" else "入口") + "へ回収中"
		elif session.phase == "reposition_travel":
			phase_text = "停め直し中"
		elif session.phase == "recall":
			phase_text = "帰還処理中"
		elif session.phase == "ready_to_exit":
			phase_text = "帰還確定可"
		status_label.text = "停車:%s / %s" % [parked_text, phase_text]
	else:
		status_label.text = "鉱 %d  中継 %d  拠点 %d  %s" % [int(summary.source_remaining), int(summary.relay), int(summary.depot), outpost_text]
	if mine_path and not vertical:
		var access_text: String = str({"blocked": "cart detour", "clearing": "rubble work", "cleared": "cart shortcut"}.get(str(summary.get("intermediate_access", "blocked")), "route check"))
		status_label.text = "地上資源 %d  中継 %d  拠点 %d  %s" % [int(summary.source_remaining), int(summary.relay), int(summary.depot), access_text]
		status_label.tooltip_text = "" if session.is_region_boss() else "地上資源は木材・石材・鉄鉱石の合計。中継と拠点は採取済みの荷物です。"
	if session.is_region_boss():
		title_label.text="独立挑戦 / "+FirstRegionCompletion.BOSS_NAME
		var boss:Dictionary=session.outpost_enemies[FirstRegionCompletion.BOSS_ID]
		status_label.text="撃破済み・全員帰還で確定" if session.outpost_cleared else "HP %.1f / %.0f　負傷時は撤退・手動救助" % [boss.hp,boss.max_hp]
	status_label.add_theme_font_size_override("font_size", 11 if vertical else 10)
	if cargo_status_label != null:
		cargo_status_label.visible = vertical
		cargo_status_label.add_theme_font_size_override("font_size", 11 if vertical else 9)
		if vertical:
			cargo_status_label.text = "地面:%d  中継:%d  手持ち:%d  車内:%d" % [int(summary.source_remaining), int(summary.relay), int(summary.carried), int(summary.depot)]
	if capacity_status_label != null:
		capacity_status_label.visible = vertical
		capacity_status_label.add_theme_font_size_override("font_size", 10 if vertical else 9)
		if vertical:
			var capacity_limit := int(summary.get("capacity_limit_weight", 0))
			var budget_text := "∞" if capacity_limit >= 1000000 else "%d/%d" % [int(summary.get("capacity_used_weight", 0)), capacity_limit]
			capacity_status_label.text = "現地搬入予算:%s" % budget_text
			if bool(summary.get("capacity_paused", false)):
				capacity_status_label.text += " / 容量停止: 手持貨物を保持。容量更新で再判定"
	if worker_rows != null:
		worker_rows.visible = vertical
		var actor_ids: Array[String] = []
		for raw_actor_id in session.actors:
			actor_ids.append(str(raw_actor_id))
		actor_ids.sort()
		for index in worker_status_labels.size():
			var worker_label := worker_status_labels[index]
			var has_actor := vertical and index < actor_ids.size()
			worker_label.visible = has_actor
			if not has_actor:
				continue
			var actor: Dictionary = session.actors.get(actor_ids[index], {})
			var role := str(actor.get("role", ""))
			var role_text := "採掘" if role == "harvest" else ("運搬" if role == "carry" else "護衛")
			var activity := canyon_hub.activity_label_for(actor) if canyon_hub != null else str(actor.get("state", "待機"))
			worker_label.text = "%s %s: %s / 手%d/%d" % [role_text, str(actor.get("name", actor_ids[index])), activity, int(actor.get("carry_n", 0)), int(actor.get("carry_limit", 0))]
			worker_label.add_theme_font_size_override("font_size", 10)
	if detail_label != null:
		detail_label.visible = true
		detail_label.add_theme_font_size_override("font_size", 8 if vertical else 9)
	if single_demo:
		var tracked_id := str(session.call("tracked_worker_id"))
		var actor: Dictionary = session.actors.get(tracked_id, {})
		var activity := canyon_hub.activity_label_for(actor) if canyon_hub != null else str(actor.get("state", "待機"))
		detail_label.text = "単独追跡 %s: %s / 手%d / 拠点%d" % [str(actor.get("name", tracked_id)), activity, int(actor.get("carry_n", 0)), int(summary.depot)]
	elif vertical:
		detail_label.text = _vertical_slice_detail()
	else:
		detail_label.text = _normal_decision_detail(summary)
	gate_button.text = "迂回: 固定" if single_demo else ("主路: 閉鎖→迂回" if session.gate_closed else "主路: 開放")
	gate_button.disabled = single_demo
	block_button.text = "全路: 閉鎖→安全待機" if session.all_routes_closed else "全路: 通行"
	dock_button.text = "搬入口 %d" % session.dock_count
	exit_button.disabled = session.phase != "ready_to_exit"
	if maintenance_button != null:
		if mine_path:
			var mine_access := str(summary.get("intermediate_access", "blocked"))
			maintenance_button.visible = true
			maintenance_button.text = "瓦礫撤去を取消 (Cancel)" if mine_access == "clearing" else ("瓦礫撤去 (Clear)" if mine_access == "blocked" else "手押し車近道: 開通")
			maintenance_button.disabled = session.phase != "local" or mine_access not in ["blocked", "clearing"] or (session.is_region_boss() and not session.outpost_cleared)
			maintenance_button.tooltip_text = "ボス挑戦中は護衛を整備に移せません。撃破後か通常採掘で整備できます。" if session.is_region_boss() and not session.outpost_cleared else ""
		else:
			maintenance_button.visible = vertical
			maintenance_button.disabled = not vertical or session.phase != "local" or str(summary.get("intermediate_access", "")) != "blocked" or bool(summary.get("capacity_paused", false))
	if reposition_button != null:
		reposition_button.visible = false
		reposition_button.disabled = not vertical or session.phase != "local" or str(summary.get("intermediate_access", "")) != "cleared" or bool(summary.get("capacity_paused", false)) or str(summary.get("parking_slot", "entry")) == "relay"
	if reposition_cancel_button != null:
		reposition_cancel_button.visible = false
		reposition_cancel_button.disabled = not vertical or session.phase not in ["reposition_recall", "reposition_travel"]
	if capacity_refresh_button != null:
		capacity_refresh_button.visible = vertical
		capacity_refresh_button.disabled = not vertical
	var equipment: Dictionary = session.equipment_status() if session.has_method("equipment_status") else {}
	var field_exchange: Dictionary = Dictionary(equipment.get("field_frame", {}))
	var field_tool: Dictionary = Dictionary(equipment.get("field_tool", {}))
	var return_exchange: Dictionary = Dictionary(equipment.get("return_handcart", {}))
	var field_status := str(field_exchange.get("status", "none"))
	var field_tool_status := str(field_tool.get("status", "none"))
	var return_status := str(return_exchange.get("status", "none"))
	if field_frame_button != null:
		field_frame_button.visible = vertical
		field_frame_button.disabled = not vertical or session.phase != "local" or bool(summary.get("capacity_paused", false)) or field_status in ["scheduled", "completed"]
	if field_tool_button != null:
		field_tool_button.visible = vertical
		var equipped_tool_item := int(field_tool.get("equipped_item", -1))
		field_tool_button.text = "採掘具:予約中" if field_tool_status == "scheduled" else ("採掘具:戻す" if equipped_tool_item == GameData.Item.PICKAXE else "現地:採掘具")
		field_tool_button.disabled = not vertical or session.phase != "local" or bool(summary.get("capacity_paused", false)) or field_tool_status == "scheduled" or not str(field_tool.get("reason", "")).is_empty()
	if return_handcart_button != null:
		return_handcart_button.visible = vertical
		return_handcart_button.disabled = not vertical or session.phase != "local" or bool(summary.get("capacity_paused", false)) or return_status in ["reserved", "completed"]
	if equipment_cancel_button != null:
		equipment_cancel_button.visible = vertical
		equipment_cancel_button.disabled = not vertical or (field_status != "scheduled" and field_tool_status != "scheduled" and return_status != "reserved")
	if field_tool_status_label != null:
		field_tool_status_label.visible = vertical
		if vertical:
			var field_tool_actor_id := str(field_tool.get("actor_id", ""))
			var field_tool_actor: Dictionary = session.actors.get(field_tool_actor_id, {})
			var field_tool_name := str(field_tool_actor.get("name", "採掘役"))
			var equipped_name := _item_name(int(field_tool.get("equipped_item", -1)))
			var carried_name := _item_name(int(field_tool.get("carried_item", -1)))
			field_tool_status_label.tooltip_text = ""
			field_tool_status_label.text = "採掘具:%s 装備:%s / 携行:%s" % [field_tool_name, equipped_name, carried_name]
			if field_tool_status == "scheduled":
				field_tool_status_label.text += " / 中継予約"
			elif field_tool_status == "completed":
				field_tool_status_label.text += " / 交換済" if int(field_tool.get("equipped_item", -1)) == GameData.Item.PICKAXE else " / 元に戻した"
			elif not str(field_tool.get("reason", "")).is_empty():
				field_tool_status_label.text += " / 未準備"
				field_tool_status_label.tooltip_text = str(field_tool.get("reason", ""))
	if session.phase == "ready_to_exit":
		_notice(_return_failure if not _return_failure.is_empty() else "帰還可: 搬入を一度だけ確定")

## HUD-only readback of the session entry snapshot.  The normal view must not
## ask the mutable horizontal Worker which equipment it has after deployment.
func _normal_equipped_role_detail() -> String:
	if session == null:
		return ""
	for actor_id in session.actors:
		var actor: Dictionary = session.actors[actor_id]
		if int(actor.get("work_support", -1)) != GameData.Item.HAUL_FRAME:
			continue
		var role := str(actor.get("role", ""))
		var role_name := "採掘役" if role == "harvest" else ("運搬役" if role == "carry" else "護衛役")
		return "%s %s / 背負いフレーム / 手%d 便%d" % [role_name, str(actor.get("name", actor_id)), int(actor.get("carry_n", 0)), int(actor.get("carry_limit", 0))]
	return ""

func _item_name(item: int) -> String:
	return str(GameData.ITEM_NAMES.get(item, "なし")) if item >= 0 else "なし"

func _vertical_slice_detail() -> String:
	if session == null or not session.has_method("vertical_slice_brief"):
		return ""
	var brief: Dictionary = session.call("vertical_slice_brief")
	match str(brief.get("kind", "")):
		"capacity_hold":
			return "停止:満載。容量更新→保持貨物を荷下ろし"
		"all_routes_closed":
			return "停止:全路閉鎖→安全待機。再開後に帰還"
		"reposition_recall":
			return "停め直し:現在の貨物だけ帰還。地面資源は残す"
		"reposition_travel":
			return "停め直し中:新規採取は移動完了まで停止"
		"recall":
			return "帰還:手持ち・中継・搬入口を解消中"
		"ready_to_exit":
			return "帰還可:搬入を一度だけ確定"
		"depleted":
			return "鉱床枯渇:採取済み貨物を帰還。別鉱床へは移動しない"
		"bypass":
			return "主路閉鎖→迂回中。回収は継続"
		"maintenance":
			return "通路の小障害物整備 / 拠点は入口に固定停車"
		"relay_parked":
			return "中継停車:片道14秒（入口より10秒短縮）"
		_:
			var equipment: Dictionary = session.equipment_status() if session.has_method("equipment_status") else {}
			var field_status := str(Dictionary(equipment.get("field_frame", {})).get("status", "none"))
			var return_status := str(Dictionary(equipment.get("return_handcart", {})).get("status", "none"))
			if field_status == "scheduled":
				return "装備:中継でフレームを採掘役へ引渡し予定"
			if field_status == "completed":
				return "装備:採掘役の背負いフレーム便5"
			if return_status == "reserved":
				return "装備:帰還後に運搬役を手押し車へ交換予約"
			return "通常分業:地面→中継→車内を回収"

func _normal_collection_capacity_blocked() -> bool:
	if not session.mine_path_engineering or session.phase != "local" or session.vertical_slice or session.single_worker_demo or session.outpost_enabled:
		return false
	# Match current reservation candidates, not actor.wait_reason: a failed
	# reservation can also mean every remaining source is already reserved.
	var has_candidate := false
	for resource in session.resources.values():
		if int(resource.get("remaining", 0)) <= 0 or not str(resource.get("reservation", "")).is_empty():
			continue
		has_candidate = true
		if session.normal_collection_room_for(int(resource.item)) > 0:
			return false
	return has_candidate

func _normal_decision_detail(summary: Dictionary) -> String:
	# The current stop/return reason always wins over route availability: a
	# cleared shortcut cannot be used while the whole site is safely paused.
	if session.phase == "recall":
		return "Return preparation: unloading and crew return in progress."
	if session.phase == "ready_to_exit":
		return "Return ready: confirm departure."
	if session.all_routes_closed:
		return "Stopped: all routes are closed; crew are waiting safely."
	if _normal_collection_capacity_blocked():
		return "採取停止: 積載予算不足\n帰還して街で売却し、空き容量を確保"
	if session != null and session.phase not in ["recall", "ready_to_exit"] and session.has_method("is_mine_path_engineering") and bool(session.call("is_mine_path_engineering")):
		var access := str(summary.get("intermediate_access", "blocked"))
		if access == "blocked":
			return "経路: 背負いは段差近道 / 手押し車は迂回。瓦礫撤去を指示できます"
		if access == "clearing":
			var worker: Dictionary = session.actors.get(str(summary.get("maintenance_actor_id", "")), {})
			return "瓦礫撤去中: %s。採掘と運搬は継続" % str(worker.get("name", "整備担当"))
		if access == "cleared":
			return "経路: 手押し車の近道が開通。入口の移動拠点は固定"
	if session.phase == "recall":
		return "帰還中: 荷下ろしと仲間の帰還を待機"
	if session.phase == "ready_to_exit":
		return "帰還完了: 帰還を確定"
	if session.all_routes_closed:
		return "停止:全路閉鎖→安全待機"
	if session.gate_closed:
		return "主路閉鎖→迂回中"
	var actor_ids: Array[String] = []
	for raw_actor_id in session.actors:
		actor_ids.append(str(raw_actor_id))
	actor_ids.sort()
	for actor_id in actor_ids:
		var reason := str(Dictionary(session.actors.get(actor_id, {})).get("wait_reason", ""))
		if not reason.is_empty():
			return "停止: " + reason
	var equipped_detail := _normal_equipped_role_detail()
	return equipped_detail if not equipped_detail.is_empty() else "保存 %s / 手持 %d / 入口待 %d" % ["OK" if bool(summary.conservation_ok) else "NG", int(summary.carried), int(summary.dock_queue)]

func _toggle_gate() -> void:
	session.set_gate_closed(not session.gate_closed)

func _toggle_all_routes() -> void:
	session.set_all_routes_closed(not session.all_routes_closed)

func _toggle_dock_count() -> void:
	session.set_dock_count(2 if session.dock_count == 1 else 1)

func _request_intermediate_clearance() -> void:
	var mine_path: bool = session != null and session.has_method("is_mine_path_engineering") and bool(session.call("is_mine_path_engineering"))
	if mine_path:
		var mine_result: Dictionary
		if str(session.state_summary().get("intermediate_access", "")) == "clearing":
			mine_result = session.cancel_mine_path_clearance() if session.has_method("cancel_mine_path_clearance") else {"ok": false, "reason": "Clearance cancellation is unavailable."}
			_notice("瓦礫撤去: " + ("取消" if bool(mine_result.get("ok", false)) else str(mine_result.get("reason", "取消できません"))))
		else:
			mine_result = session.request_mine_path_clearance() if session.has_method("request_mine_path_clearance") else {"ok": false, "reason": "Rubble-clearance order is unavailable."}
			_notice("瓦礫撤去: " + ("開始" if bool(mine_result.get("ok", false)) else str(mine_result.get("reason", "開始できません"))))
		_update_controls()
		return
	var result: Dictionary = session.request_intermediate_clearance()
	_notice("整備: " + ("開始" if bool(result.get("ok", false)) else str(result.get("reason", "開始できません"))))

func _request_reposition() -> void:
	var result: Dictionary = session.request_reposition("relay")
	_notice("中継停車: " + ("貨物を回収中" if bool(result.get("ok", false)) else str(result.get("reason", "開始できません"))))

func _cancel_reposition() -> void:
	var result: Dictionary = session.cancel_reposition()
	_notice("停車取消: " + ("入口停車の通常分業へ戻ります" if bool(result.get("ok", false)) else str(result.get("reason", "取消できません"))))

func _refresh_capacity() -> void:
	var result: Dictionary = session.refresh_capacity_from_game(game)
	_notice("容量更新: " + ("保持貨物を再判定" if bool(result.get("ok", false)) else str(result.get("reason", "更新できません"))))


func _request_field_frame_to_harvest() -> void:
	var result: Dictionary = session.request_field_frame_to_harvest()
	var text := "中継で採掘役へ引渡し予約" if bool(result.get("ok", false)) else str(result.get("reason", "予約できません"))
	if bool(result.get("already_scheduled", false)):
		text = "中継引渡し予約済み"
	_notice("現地装備: " + text)
	_update_controls()


func _request_field_tool_swap() -> void:
	var result: Dictionary = session.request_field_tool_swap() if session.has_method("request_field_tool_swap") else {"ok": false, "reason": "携行採掘具交換APIを確認できません"}
	var text := "次の中継・空荷時に採掘役本人が交換" if bool(result.get("ok", false)) else str(result.get("reason", "予約できません"))
	if bool(result.get("already_scheduled", false)):
		text = "採掘役の携行採掘具交換は予約済み"
	_notice("携行採掘具: " + text)
	_update_controls()


func _request_return_handcart_exchange() -> void:
	var result: Dictionary = session.request_return_handcart_exchange(game)
	var text := "拠点専用: 帰還後に手押し車へ交換予約" if bool(result.get("ok", false)) else str(result.get("reason", "予約できません"))
	if bool(result.get("already_reserved", false)):
		text = "手押し車の帰還交換予約済み"
	elif bool(result.get("already_equipped", false)):
		text = "運搬役はすでに手押し車を装備"
	_notice("帰還装備: " + text)
	_update_controls()


func _cancel_equipment_exchange() -> void:
	var cancelled: Array[String] = []
	var field_result: Dictionary = session.cancel_field_frame_exchange() if session.has_method("cancel_field_frame_exchange") else {"ok": false}
	if bool(field_result.get("ok", false)):
		cancelled.append("現地フレーム")
	var tool_result: Dictionary = session.cancel_field_tool_swap() if session.has_method("cancel_field_tool_swap") else {"ok": false}
	if bool(tool_result.get("ok", false)):
		cancelled.append("携行採掘具")
	var return_result: Dictionary = session.cancel_return_handcart_exchange() if session.has_method("cancel_return_handcart_exchange") else {"ok": false}
	if bool(return_result.get("ok", false)):
		cancelled.append("帰還手押し車")
	var fallback_reason := str(tool_result.get("reason", return_result.get("reason", field_result.get("reason", "取消できません"))))
	var text := "・".join(cancelled) + "の予約を取消" if not cancelled.is_empty() else fallback_reason
	_notice("装備取消: " + text)
	_update_controls()

func _save_fixture() -> void:
	var result: Dictionary = session.save_project_fixture()
	_notice("現地検証保存（本体保存ではなく同じ実行の最新状態専用）: " + (str(result.path) if bool(result.get("ok", false)) else str(result.get("reason", "失敗"))))

func _load_fixture() -> void:
	var result: Dictionary = RecoveryRouteConnectionSession.load_project_fixture()
	if not bool(result.get("ok", false)):
		_notice(str(result.get("reason", "読込失敗")))
		return
	var loaded: Variant = result.session
	if loaded == null or str(loaded.session_id) != str(session.session_id):
		_notice("別の検証sessionは現地在庫と混ぜず、現在のsessionと同じ保存だけを読込できます")
		return
	var new_clock = preload("res://bridge/field_survival_clock.gd").new()
	var bound: Dictionary = new_clock.setup(game, loaded)
	if not bound.ok:
		_notice(str(bound.reason))
		return
	var previous_session = session
	session = loaded
	var projected: Dictionary = _apply_worker_projection()
	if not bool(projected.get("ok", false)):
		session = previous_session
		_notice(str(projected.get("reason", "仲間照合に失敗")))
		return
	life_clock = new_clock
	if rescue_panel != null: rescue_panel.rebuild()
	if canyon_hub != null:
		canyon_hub.configure(session)
	_notice("検証セッションを復元しました。通常 user:// は使用していません。")

func _build_return_confirmation() -> void:
	return_confirmation = ConfirmationDialog.new()
	return_confirmation.name = "ReturnCargoConfirmation"
	return_confirmation.title = "積載量とCへの残置を確認"
	return_confirmation.dialog_hide_on_ok = false
	return_confirmation.ok_button_text = "この個数で帰還"
	return_confirmation.cancel_button_text = "戻る"
	return_confirmation.confirmed.connect(_confirm_partial_return)
	return_confirmation.canceled.connect(_cancel_partial_return)
	add_child(return_confirmation)

func _cancel_partial_return() -> void:
	_return_plan.clear()
	_return_session = null
	_return_clock = null

func _cargo_text(cargo: Dictionary) -> String:
	var rows: PackedStringArray = []
	for item in cargo: rows.append("%s × %d" % [_item_name(int(item)), int(cargo[item])])
	return "なし" if rows.is_empty() else "、".join(rows)

func _show_return_plan(plan: Dictionary, changed := false) -> void:
	_return_plan = plan.duplicate(true)
	_return_session = session
	_return_clock = life_clock
	return_confirmation.dialog_text = ("積載量が変わりました。内容を確認し直してください。\n\n" if changed else "積載量が足りないため、残りはCの地面に保管します。\n\n") + "車内へ搬入: " + _cargo_text(plan.deposited) + "\nCに残す: " + _cargo_text(plan.left_outside) + "\n\n残した物はCの横視点で、空きを作って後から回収できます。\n帰還は一度だけ確定します。"
	return_confirmation.popup_centered(Vector2i(580, 250))

func _return_context_current() -> bool:
	return not _discarding_for_load and is_inside_tree() and not is_queued_for_deletion() and is_visible_in_tree() and is_instance_valid(game) and not game.game_over and not game.save_ui.is_open() and session != null and not session.committed and session.phase == "ready_to_exit" and life_clock != null and life_clock.is_current()

func _confirm_partial_return() -> void:
	if not _return_context_current() or _return_session != session or _return_clock != life_clock or _return_plan.is_empty():
		_cancel_partial_return(); return
	var current: Dictionary = session.return_cargo_plan(game)
	if current.is_empty():
		_return_failure = "Cの残置先を確認できないため帰還を中止しました"
		_cancel_partial_return(); _notice(_return_failure); return
	if current != _return_plan:
		_show_return_plan(current, true); return
	var approved := _return_plan.duplicate(true)
	return_confirmation.hide()
	_cancel_partial_return()
	_execute_return(approved)

func _commit_and_exit() -> void:
	if not _return_context_current(): return
	var plan: Dictionary = session.return_cargo_plan(game)
	if not plan.is_empty() and not Dictionary(plan.left_outside).is_empty():
		_show_return_plan(plan); return
	_execute_return()

func _execute_return(approved: Dictionary = {}) -> void:
	var result: Dictionary = session.commit_to_game(game, approved)
	if not bool(result.get("ok", false)):
		_return_failure = str(result.get("reason", "搬入を確定できません"))
		_notice(_return_failure)
		return
	_return_failure = ""
	_restore_workers()
	# Only release the pause this field UI owns, never a failure/menu pause.
	if _owns_field_pause and not game.game_over and not game.save_ui.is_open():
		get_tree().paused = false
		_owns_field_pause = false
	exit_to_horizontal.emit(result)

func _sync_outpost_enemies() -> void:
	if enemy_layer == null or session == null:
		return
	var live := {}
	for enemy_id in session.outpost_enemies:
		var enemy: Dictionary = session.outpost_enemies[enemy_id]
		if bool(enemy.get("dead", false)):
			continue
		live[str(enemy_id)] = true
		var visual = enemy_views.get(str(enemy_id), null)
		if visual == null or not is_instance_valid(visual):
			visual = preload("res://bridge/quarry_boss_view.gd").new() if session.is_region_boss() else Enemy.new()
			var spec: Dictionary = EventDB.ENEMIES.get(str(enemy.get("kind", "")), {})
			visual.game = game
			visual.kind = str(enemy.get("kind", ""))
			visual.max_hp = float(enemy.get("max_hp", 0.0))
			visual.damage = float(spec.get("dmg", 0.0))
			visual.run_speed = float(spec.get("run", 0.0))
			visual.body_scale = float(spec.get("scale", 1.0))
			visual._body = Color(str(spec.get("color", "ffffff")))
			visual.ecological = true
			visual.present = true
			visual.process_mode = Node.PROCESS_MODE_DISABLED
			enemy_layer.add_child(visual)
			enemy_views[str(enemy_id)] = visual
		visual.position = _presentation_point(Vector2(float(enemy.get("x", 0.0)), float(enemy.get("y", 0.0))))
		visual.home_x = float(enemy.get("home_x", visual.position.x))
		visual.hp = float(enemy.get("hp", visual.max_hp))
		visual.queue_redraw()
	for enemy_id in enemy_views.keys().duplicate():
		if live.has(enemy_id):
			continue
		var stale = enemy_views[enemy_id]
		if is_instance_valid(stale):
			stale.queue_free()
		enemy_views.erase(enemy_id)

func _notice(text: String) -> void:
	if notice_label != null:
		notice_label.text = text
		notice_label.visible = not text.is_empty()

func _draw() -> void:
	if canyon_hub != null:
		# CanyonRecoveryHub owns the completed, layered visual presentation.
		# Keep the former schematic below as a construction fallback only.
		return
	# 画面はカメラに巻き込まれない固定クォータービュー。ワールド背景の貼り付けではなく、
	# 実際に session の移動・ゲート・人数を投影している。
	draw_rect(Rect2(Vector2.ZERO, size), Color("263742"))
	for x in range(110, 1220, 105):
		for y in range(160, 650, 76):
			_draw_diamond(Vector2(x, y), Vector2(75, 35), Color("4d675a"))
	_draw_route([RecoveryRouteConnectionSession.BASE, RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.GATE, RecoveryRouteConnectionSession.RESOURCE], Color("dfc27d"), 10.0)
	_draw_route([RecoveryRouteConnectionSession.RELAY, RecoveryRouteConnectionSession.BYPASS, RecoveryRouteConnectionSession.RESOURCE], Color("95b9c8"), 8.0)
	_draw_site(RecoveryRouteConnectionSession.BASE, "駐車基地", Color("d98b4b"))
	_draw_site(RecoveryRouteConnectionSession.RELAY, "中継／保管", Color("8fbc8f"))
	_draw_site(RecoveryRouteConnectionSession.RESOURCE, "敵施設・資源", Color("c26a58"))
	_draw_cover(RecoveryRouteConnectionSession.OUTPOST_COVER)
	var gate_color: Color = Color("c45151") if session != null and session.gate_closed else Color("7ecf8e")
	draw_rect(Rect2(RecoveryRouteConnectionSession.GATE - Vector2(18, 32), Vector2(36, 64)), gate_color)
	draw_string(ThemeDB.fallback_font, RecoveryRouteConnectionSession.GATE + Vector2(-44, -42), "ゲート", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	if session != null:
		for actor_id in session.actors:
			var actor: Dictionary = session.actors[actor_id]
			var p := Vector2(float(actor.x), float(actor.y))
			var role: String = str(actor.role)
			var color: Color = {"harvest": Color("ffe37a"), "carry": Color("82c8ff"), "escort": Color("ff9a9a")}.get(role, Color.WHITE)
			draw_circle(p + Vector2(0, 12), 13, Color(0.0, 0.0, 0.0, 0.26))
			draw_circle(p, 11, color)
			draw_string(ThemeDB.fallback_font, p + Vector2(15, -8), role, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
			if int(actor.carry_n) > 0:
				draw_rect(Rect2(p + Vector2(-7, -26), Vector2(14, 11)), Color("e9c46a"))
			if not str(actor.wait_reason).is_empty():
				draw_string(ThemeDB.fallback_font, p + Vector2(15, 16), str(actor.wait_reason), HORIZONTAL_ALIGNMENT_LEFT, 150, 12, Color("ffd38a"))

func _draw_route(points: Array, color: Color, width: float) -> void:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(point)
	draw_polyline(packed, color, width, true)

func _draw_diamond(center: Vector2, half_size: Vector2, color: Color) -> void:
	var points := PackedVector2Array([center + Vector2(0, -half_size.y), center + Vector2(half_size.x, 0), center + Vector2(0, half_size.y), center + Vector2(-half_size.x, 0)])
	draw_colored_polygon(points, color)

func _draw_site(point: Vector2, label: String, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([point + Vector2(-42, 0), point + Vector2(0, -25), point + Vector2(42, 0), point + Vector2(0, 25)]), color)
	draw_rect(Rect2(point + Vector2(-29, 0), Vector2(58, 29)), color.darkened(0.25))
	draw_string(ThemeDB.fallback_font, point + Vector2(-52, 49), label, HORIZONTAL_ALIGNMENT_LEFT, 140, 16, Color.WHITE)

func _draw_cover(point: Vector2) -> void:
	var color := Color("66727a")
	draw_rect(Rect2(point - Vector2(42, 20), Vector2(84, 40)), color)
	draw_line(point + Vector2(-35, -13), point + Vector2(35, 13), color.lightened(0.25), 4.0)
	draw_string(ThemeDB.fallback_font, point + Vector2(-51, 39), "遮蔽物", HORIZONTAL_ALIGNMENT_LEFT, 110, 14, Color("dfe8e9"))

func _crew_health_text() -> String:
	# Read the live field actors, not the suspended side-view workers.
	var members: Array[String] = []
	var injured := 0
	var down := 0
	for actor_id in session.actors:
		var actor: Dictionary = session.actors[actor_id]
		var hp := float(actor.get("hp", 0.0))
		members.append("%s %.1f" % [str(actor.get("name", actor_id)), hp])
		if bool(actor.get("down", false)) or hp <= 0.0:
			down += 1
		elif hp < CrewStatusDB.MAX_HP:
			injured += 1
	var text := "仲間HP: " + " / ".join(members)
	if down > 0:
		text += "\n戦闘不能%d人：手動救助で状態・残秒を確認" % down
	elif injured > 0:
		var next := "帰還準備で全員を呼戻し"
		if session.phase == "recall": next = "全員の帰還を待機"
		elif session.phase == "ready_to_exit": next = "帰還→横視点で確定"
		text += "\n負傷%d人：%s" % [injured, next]
	return text

func _build_vehicle_status() -> void:
	var panel := PanelContainer.new()
	panel.name = "FieldVehicleStatus"
	panel.position = Vector2(914, 14)
	panel.custom_minimum_size = Vector2(350, 0)
	panel.z_index = 20
	add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Contents"
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	vehicle_status_label = Label.new()
	vehicle_status_label.name = "Status"
	vehicle_status_label.custom_minimum_size.x = 340
	vehicle_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vehicle_status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(vehicle_status_label)
	crew_health_label = Label.new()
	crew_health_label.name = "CrewHealth"
	crew_health_label.custom_minimum_size.x = 340
	crew_health_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crew_health_label.add_theme_font_size_override("font_size", 13)
	box.add_child(crew_health_label)
	var row := HBoxContainer.new()
	row.name = "Actions"
	box.add_child(row)
	vehicle_pause_button = Button.new()
	vehicle_pause_button.name = "Pause"
	vehicle_pause_button.text = "一時停止"
	vehicle_pause_button.pressed.connect(_toggle_field_pause)
	row.add_child(vehicle_pause_button)
	var save := Button.new()
	save.name = "Save"
	save.text = "保存 / 続きから"
	save.pressed.connect(func():
		if not game.game_over: game.save_ui.open()
	)
	row.add_child(save)
	vehicle_return_button = Button.new()
	vehicle_return_button.name = "Return"
	vehicle_return_button.text = "帰還準備"
	vehicle_return_button.tooltip_text = "全員と荷物を集めて、下部の帰還→横視点で確定"
	vehicle_return_button.button_down.connect(_capture_vehicle_return)
	vehicle_return_button.pressed.connect(_dispatch_vehicle_return)
	row.add_child(vehicle_return_button)
	_update_controls()

func _optional_outpost_return() -> bool:
	return session != null and session.outpost_enabled and not session.is_region_boss()

func _vehicle_return_context_current() -> bool:
	return not _discarding_for_load and is_inside_tree() and not is_queued_for_deletion() and is_visible_in_tree() and is_instance_valid(game) and not game.game_over and not game.save_ui.is_open() and session != null and not session.committed and life_clock != null and life_clock.is_current()

func _update_vehicle_return() -> void:
	if vehicle_return_button == null or not _optional_outpost_return(): return
	var ready: bool = session.phase == "ready_to_exit"
	vehicle_return_button.text = "帰還→横視点" if ready else ("帰還準備" if session.phase == "local" else "帰還準備中")
	vehicle_return_button.tooltip_text = "全員と荷物の帰還を確定し、横視点へ戻ります" if ready else "全員と荷物を呼び戻します。準備完了後、このボタンで帰還を確定してください"
	vehicle_return_button.disabled = not _vehicle_return_context_current() or session.phase not in ["local", "ready_to_exit"]

func _capture_vehicle_return() -> void:
	_vehicle_return_action = ""
	_vehicle_return_session = null
	_vehicle_return_clock = null
	if not _optional_outpost_return() or not _vehicle_return_context_current() or vehicle_return_button.disabled: return
	# Capture the visible choice at press time, never promote recall on release.
	_vehicle_return_action = "commit" if vehicle_return_button.text == "帰還→横視点" else "recall"
	_vehicle_return_session = session
	_vehicle_return_clock = life_clock

func _dispatch_vehicle_return() -> void:
	if not _optional_outpost_return():
		if not game.game_over: session.request_recall()
		return
	var action := _vehicle_return_action
	var same_context: bool = _vehicle_return_session == session and _vehicle_return_clock == life_clock
	_vehicle_return_action = ""
	_vehicle_return_session = null
	_vehicle_return_clock = null
	if not same_context or not _vehicle_return_context_current(): return
	if action == "commit":
		_commit_and_exit()
	elif action == "recall" and session.phase == "local":
		session.request_recall()
	_update_vehicle_return()

func _toggle_field_pause() -> void:
	if game.game_over or game.save_ui.is_open(): return
	if get_tree().paused and not _owns_field_pause: return
	_owns_field_pause = not get_tree().paused
	get_tree().paused = _owns_field_pause
	vehicle_pause_button.text = "再開" if _owns_field_pause else "一時停止"

func _build_rescue_panel() -> void:
	rescue_panel = preload("res://bridge/c_quarry_rescue_panel.gd").new()
	rescue_panel.name = "CRescuePanel"
	rescue_panel.configure(self)
	add_child(rescue_panel)
	rescue_toggle = Button.new()
	rescue_toggle.name = "RescueToggle"
	rescue_toggle.text = "手動救助"
	rescue_toggle.position = Vector2(178, 14)
	rescue_toggle.custom_minimum_size = Vector2(128, 28)
	rescue_toggle.z_index = 31
	rescue_toggle.pressed.connect(_toggle_rescue_panel)
	add_child(rescue_toggle)

func _toggle_rescue_panel() -> void:
	if rescue_panel == null:
		return
	if rescue_panel.visible:
		rescue_panel.close_panel()
	else:
		if route_guide != null: route_guide.hide()
		rescue_panel.open_panel()

func rescue_context_current(panel, expected_session, expected_clock) -> bool:
	if panel != rescue_panel or not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree() or not is_instance_valid(game) or game.game_over:
		return false
	if panel == null or not panel.is_inside_tree() or not panel.is_visible_in_tree() or panel.is_queued_for_deletion() or session == null or life_clock == null:
		return false
	if expected_session != session or expected_clock != life_clock or life_clock.session != session or not life_clock.is_current() or session.committed or session.phase not in ["local", "recall", "ready_to_exit"]:
		return false
	if int(game.get_meta("c_rescue_current_adapter", -1)) != get_instance_id():
		return false
	if game.mine_arrival_gate != null and get_parent() == game.mine_arrival_gate and game.mine_arrival_gate.field != self:
		return false
	return true

## Replacing the whole saved world is not field abandonment or return.
func discard_for_load() -> void:
	_discarding_for_load = true
	_cancel_partial_return()
	if return_confirmation != null: return_confirmation.hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	if rescue_panel != null: rescue_panel.invalidate()
	_restore_workers()
	if life_clock != null: life_clock.bound = false
