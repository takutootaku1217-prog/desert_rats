extends SceneTree
## GUI wiring contract for the opt-in C-quarry parking vertical slice.
## Button signals exercise the production handlers; this is explicitly not a
## physical-pointer claim.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")
const STEP := 0.5

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
	if not await _prepare_field():
		_finish()
		return
	var overlay = field.canyon_hub.get_node_or_null("ParkingOverlay")
	_check(overlay != null and overlay.has_method("refresh"), "中継停車の仮マーカーは独立した表示部品")
	var terrain = field.canyon_hub.get_node_or_null("Terrain")
	var bypass_is_conditional: bool = terrain != null and terrain.has_method("is_bypass_route_visible")
	if bypass_is_conditional:
		_check(not bool(terrain.call("is_bypass_route_visible", field.canyon_hub)), "縦切りで主経路が通る間は未使用の入口→橋迂回帯を描かない")
		field.session.gate_closed = true
		_check(bool(terrain.call("is_bypass_route_visible", field.canyon_hub)), "主経路閉鎖時だけ実際に使う入口→橋迂回帯を再表示する")
		field.session.gate_closed = false
	else:
		_check(false, "縦切りの未使用迂回帯を判定する表示契約がある")
	var entry_contact := Vector2(1004, 594)
	var relay_contact := Vector2(865, 455)
	var entry_anchor_actor := {"x": RecoveryRouteConnectionSession.BASE.x, "y": RecoveryRouteConnectionSession.BASE.y, "state": "idle"}
	var entry_contact_matches := false
	if field.canyon_hub.has_method("active_unload_contact") and field.canyon_hub.has_method("presentation_point_for_actor"):
		entry_contact_matches = field.canyon_hub.active_unload_contact() == entry_contact and field.canyon_hub.presentation_point_for_actor(entry_anchor_actor) == entry_contact
	_check(entry_contact_matches, "入口停車では車体の荷下ろし接点とBASE表示投影が同じ作者定義anchorになる")
	var vertical_panel_rect: Rect2 = field.controls_panel.get_global_rect() if field.controls_panel != null else Rect2()
	_check(field.controls_panel != null and field.controls_panel.position == Vector2(16, 486) and field.controls_panel.size == Vector2(448, 218) and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(vertical_panel_rect), "縦切りHUDは作業路を隠さない左下の読みやすい範囲へ移す")
	var parking_status := field.controls_panel.get_node_or_null("Contents/ParkingStatus") as Label
	var detail_status := field.controls_panel.get_node_or_null("Contents/DetailStatus") as Label
	var cargo_status := field.controls_panel.get_node_or_null("Contents/CargoStatus") as Label
	var capacity_status := field.controls_panel.get_node_or_null("Contents/CapacityStatus") as Label
	var field_tool_status := field.controls_panel.get_node_or_null("Contents/FieldToolStatus") as Label
	var worker_rows := field.controls_panel.get_node_or_null("Contents/WorkerRows") as VBoxContainer
	_check(parking_status != null and detail_status != null and cargo_status != null and capacity_status != null and field_tool_status != null and worker_rows != null and worker_rows.get_child_count() == 3, "縦切りHUDは停車・判断・貨物・容量・携行採掘具と既存3人の作業行を分けて表示する")
	_check(parking_status != null and parking_status.text.contains("入口") and cargo_status != null and cargo_status.text.contains("手持ち") and cargo_status.text.contains("車内"), "縦切りHUDは現在地と手持ち／収納を同じ画面で読める")
	_check(detail_status != null and detail_status.visible and detail_status.text.contains("整備") and detail_status.text.contains("24→14秒") and detail_status.text.contains("背負いフレーム") and detail_status.text.contains("3→5") and detail_status.text.contains("木2") and detail_status.text.contains("皮1") and detail_status.text.contains("鉄1"), "入口停車では整備→中継の短縮効果と既存フレーム強化候補をHUDで読む")
	_check(field.maintenance_button.visible and field.reposition_button.visible and field.reposition_cancel_button.visible and field.capacity_refresh_button.visible, "縦切りHUDは整備・停車・取消・容量再読込を表示")
	# Production button signals are checked here; this remains a wiring test,
	# not a claim that a physical pointer was available in headless CI.
	var action_grid := field.controls_panel.get_node_or_null("Contents/ActionGrid") as GridContainer
	var field_frame_button := action_grid.get_node_or_null("FieldFrameExchange") as Button if action_grid != null else null
	var return_handcart_button := action_grid.get_node_or_null("ReturnHandcartExchange") as Button if action_grid != null else null
	var field_tool_button := action_grid.get_node_or_null("FieldToolSwap") as Button if action_grid != null else null
	var equipment_cancel_button := action_grid.get_node_or_null("EquipmentExchangeCancel") as Button if action_grid != null else null
	_check(field_frame_button != null and return_handcart_button != null and field_tool_button != null and equipment_cancel_button != null and field_frame_button.visible and return_handcart_button.visible and field_tool_button.visible and equipment_cancel_button.visible and return_handcart_button.text.contains("拠点") and field_tool_status != null and field_tool_status.text.contains("装備") and field_tool_status.text.contains("携行"), "縦切りHUDは同一採掘役の装備／携行表示と現地交換操作、手押し車が拠点専用である理由を通常ボタンとして表示")
	if field_frame_button != null and return_handcart_button != null and field_tool_button != null and equipment_cancel_button != null:
		field_frame_button.emit_signal("pressed")
		await process_frame
		_check(str(Dictionary(field.session.equipment_status().get("field_frame", {})).get("status", "")) == "scheduled" and field.notice_label.text.begins_with("現地装備:"), "現地フレーム操作はproduction handlerからsession予約と非モーダル理由表示へ接続")
		return_handcart_button.emit_signal("pressed")
		await process_frame
		_check(str(Dictionary(field.session.equipment_status().get("return_handcart", {})).get("status", "")) == "reserved" and field.notice_label.text.begins_with("帰還装備:"), "帰還手押し車操作は在庫を動かさず予約と非モーダル表示へ接続")
		field_tool_button.emit_signal("pressed")
		await process_frame
		_check(str(Dictionary(field.session.equipment_status().get("field_tool", {})).get("status", "")) == "scheduled" and field.notice_label.text.begins_with("携行採掘具:"), "現地採掘具操作は同一採掘役の安全境界予約と非モーダル表示へ接続")
		equipment_cancel_button.emit_signal("pressed")
		await process_frame
		var equipment_status: Dictionary = field.session.equipment_status()
		_check(str(Dictionary(equipment_status.get("field_frame", {})).get("status", "")) == "none" and str(Dictionary(equipment_status.get("return_handcart", {})).get("status", "")) == "none" and str(Dictionary(equipment_status.get("field_tool", {})).get("status", "")) == "none" and field.notice_label.text.begins_with("装備取消:"), "装備取消は現地採掘具を含む予約だけを消し在庫・現地貨物を変更しない")
		field_tool_button.emit_signal("pressed")
		var field_tool_completed := await _advance_until(func(): return str(Dictionary(field.session.equipment_status().get("field_tool", {})).get("status", "")) == "completed", 70.0)
		field._update_controls()
		_check(field_tool_completed and not field_tool_button.disabled and field_tool_button.text.contains("戻す"), "採掘役本人が交換済みでもHUDの同じ操作から携行採掘具を戻す予約を出せる")
		field_tool_button.emit_signal("pressed")
		await process_frame
		_check(str(Dictionary(field.session.equipment_status().get("field_tool", {})).get("status", "")) == "scheduled" and field.notice_label.text.begins_with("携行採掘具:"), "交換後のHUD操作も同一採掘役の逆切替予約と非モーダル表示へ接続")
		equipment_cancel_button.emit_signal("pressed")
		await process_frame
		_check(str(Dictionary(field.session.equipment_status().get("field_tool", {})).get("status", "")) == "completed" and not field_tool_button.disabled, "逆切替の取消は既存の交換済み所有権を保ち、再予約を妨げない")
	field.session.field_capacity_limit_weight = 0
	field.session.capacity_paused = true
	field._update_controls()
	_check(capacity_status != null and capacity_status.text.contains("容量停止") and capacity_status.text.contains("容量更新"), "満杯停止の理由と再開操作をHUDへ明示する")
	_check(detail_status != null and detail_status.text.contains("停止") and detail_status.text.contains("満載") and detail_status.text.contains("容量更新"), "満杯時の判断行は新規採取停止と容量更新を優先して示す")
	main.storage.inventory.add(GameData.Item.WOOD, 1, Inventory.SOURCE_TRANSFER)
	await process_frame
	_check(not field.session.capacity_paused and field.notice_label.text.begins_with("容量変化を検知:"), "既存倉庫の在庫変更は毎frame pollなしで保持貨物を再判定")
	main.storage.inventory.take(GameData.Item.WOOD)
	var base_rear_position := (field.canyon_hub.get_node("BaseRear") as Node2D).position
	var base_front_position := (field.canyon_hub.get_node("BaseFront") as Node2D).position
	field.maintenance_button.emit_signal("pressed")
	await process_frame
	_check(str(field.session.state_summary().get("intermediate_access", "")) == "clearing" and field.notice_label.text.begins_with("整備:"), "整備ボタンは正本sessionの整備状態だけを開始")
	_check(await _advance_until(func(): return str(field.session.state_summary().get("intermediate_access", "")) == "cleared", 20.0), "実sessionの整備完了がHUDへ反映")
	field._update_controls()
	_check(not field.reposition_button.disabled, "整備済み後に中継停車ボタンを有効化")
	field.reposition_button.emit_signal("pressed")
	await process_frame
	_check(str(field.session.phase) == "reposition_recall", "停車ボタンは通常撤退でなく停め直しphaseを開始")
	field.canyon_hub.refresh()
	_check((field.canyon_hub.get_node("BaseRear") as Node2D).position == base_rear_position and (field.canyon_hub.get_node("BaseFront") as Node2D).position == base_front_position, "停め直しの回収中は入口車体と荷下ろし接点を維持する")
	field.reposition_cancel_button.emit_signal("pressed")
	await process_frame
	_check(str(field.session.phase) == "local" and str(field.session.state_summary().get("parking_slot", "")) == "entry" and field.session.conservation_ok(), "停車取消は入口位置と資源保存則を維持")
	field.reposition_button.emit_signal("pressed")
	_check(await _advance_until(func(): return str(field.session.phase) == "local" and str(field.session.state_summary().get("parking_slot", "")) == "relay", 40.0), "HUDの停車操作で中継位置へ到達")
	field._update_controls()
	_check(field.reposition_button.disabled and not field.capacity_refresh_button.disabled, "中継停車後は二重移動を防ぎ容量再読込を残す")
	var relay_offset := relay_contact - entry_contact
	var base_rear := field.canyon_hub.get_node("BaseRear") as Node2D
	var base_front := field.canyon_hub.get_node("BaseFront") as Node2D
	_check(base_rear.position == base_rear_position + relay_offset and base_front.position == base_front_position + relay_offset and base_front.position - base_rear.position == base_front_position - base_rear_position, "中継停車完了後は車体前後レイヤーが同じ整数offsetで移動する")
	var bridge = field.canyon_hub.get_node_or_null("Bridge")
	var rear_sprite = field.canyon_hub.get_node_or_null("BaseRear/MobileBaseRear") as Sprite2D
	var front_sprite = field.canyon_hub.get_node_or_null("BaseFront/MobileBaseFrontOccluder") as Sprite2D
	var bridge_path: Array = bridge.call("presentation_path", field.canyon_hub) if bridge != null and bridge.has_method("presentation_path") else []
	var bridge_entry_clear := false
	if rear_sprite != null and front_sprite != null and rear_sprite.texture != null and front_sprite.texture != null and bridge_path.size() > 1:
		var rear_bounds := Rect2(rear_sprite.global_position - rear_sprite.texture.get_size() * 0.5, rear_sprite.texture.get_size()).grow(8.0)
		var front_bounds := Rect2(front_sprite.global_position - front_sprite.texture.get_size() * 0.5, front_sprite.texture.get_size()).grow(8.0)
		var bridge_near_foot: Vector2 = bridge_path[1]
		bridge_entry_clear = not rear_bounds.has_point(bridge_near_foot) and not front_bounds.has_point(bridge_near_foot)
	_check(bridge_entry_clear, "中継停車の同向き車体は短橋の手前接地点を覆わない")
	var relay_anchor_actor := {"x": RecoveryRouteConnectionSession.RELAY.x, "y": RecoveryRouteConnectionSession.RELAY.y, "state": "idle"}
	var relay_contact_matches: bool = field.canyon_hub.has_method("active_unload_contact") and field.canyon_hub.active_unload_contact() == relay_contact and field.canyon_hub.presentation_point_for_actor(relay_anchor_actor) == relay_contact
	_check(relay_contact_matches, "中継停車では車体荷下ろし接点とRELAY表示投影が同じanchorになる")
	var relay_worker_one: Dictionary = field.session.actors.get("worker:1", {})
	var relay_worker_two: Dictionary = field.session.actors.get("worker:2", {})
	var relay_formation_maps: bool = not relay_worker_one.is_empty() and not relay_worker_two.is_empty() and field.canyon_hub.presentation_point_for_actor(relay_worker_one) == relay_contact + Vector2(-28, 20) and field.canyon_hub.presentation_point_for_actor(relay_worker_two) == relay_contact + Vector2(-56, 0)
	_check(relay_formation_maps, "中継到着直後の既存3人編成もdock基準で連続投影し、raw mapへ落とさない")
	# A formation corridor may overlap the preceding BASE→RELAY endpoint.  The
	# moving RELAY→GATE centreline must still choose its own segment, otherwise
	# it stays at the old endpoint until the corridor edge and visibly jumps.
	var relay_to_gate := RecoveryRouteConnectionSession.GATE - RecoveryRouteConnectionSession.RELAY
	var relay_to_gate_length := relay_to_gate.length()
	var corridor_before_t := (64.0 - 0.01) / relay_to_gate_length
	var corridor_after_t := (64.0 + 0.01) / relay_to_gate_length
	var corridor_before_source := RecoveryRouteConnectionSession.RELAY.lerp(RecoveryRouteConnectionSession.GATE, corridor_before_t)
	var corridor_after_source := RecoveryRouteConnectionSession.RELAY.lerp(RecoveryRouteConnectionSession.GATE, corridor_after_t)
	var corridor_before: Vector2 = field.canyon_hub.presentation_point_for_actor({"x": corridor_before_source.x, "y": corridor_before_source.y, "state": "to_resource"})
	var corridor_after: Vector2 = field.canyon_hub.presentation_point_for_actor({"x": corridor_after_source.x, "y": corridor_after_source.y, "state": "to_resource"})
	var expected_before := relay_contact.lerp(field.canyon_hub.map_point(RecoveryRouteConnectionSession.GATE), corridor_before_t).round()
	var expected_after := relay_contact.lerp(field.canyon_hub.map_point(RecoveryRouteConnectionSession.GATE), corridor_after_t).round()
	_check(corridor_before == expected_before and corridor_after == expected_after and corridor_before.distance_to(corridor_after) <= 2.0, "relay→gateの編成許容幅境界でも前後の実移動表示は連続し、旧segmentへ張り付かない")
	var relay_open_path: Array = Array(terrain.call("active_transport_path", field.canyon_hub)) if terrain != null and terrain.has_method("active_transport_path") else []
	_check(relay_open_path.size() == 3 and relay_open_path[0] == relay_contact and relay_open_path[1] == field.canyon_hub.map_point(RecoveryRouteConnectionSession.GATE) and relay_open_path[2] == field.canyon_hub.map_point(RecoveryRouteConnectionSession.RESOURCE), "中継で主経路が開いている間はdock→gate→資源地の実表示経路を使う")
	field.session.gate_closed = true
	var relay_closed_path: Array = Array(terrain.call("active_transport_path", field.canyon_hub)) if terrain != null and terrain.has_method("active_transport_path") else []
	_check(relay_closed_path.size() == 3 and relay_closed_path[0] == relay_contact and relay_closed_path[1] == field.canyon_hub.map_point(RecoveryRouteConnectionSession.BYPASS) and relay_closed_path[2] == field.canyon_hub.map_point(RecoveryRouteConnectionSession.RESOURCE), "中継で主経路を閉鎖した時もdockから始まる実bypassを描く")
	field._update_controls()
	_check(detail_status != null and detail_status.text.contains("主路閉鎖") and detail_status.text.contains("迂回") and field.gate_button.text == "主路: 閉鎖→迂回", "主路閉鎖ではHUDの判断行と操作名が実bypassと同じ意味を示す")
	field.session.gate_closed = false
	field.session.field_capacity_limit_weight = 0
	field.session.capacity_paused = true
	var held_move: Dictionary = field.session.request_reposition("entry")
	field.canyon_hub.refresh()
	_check(not bool(held_move.get("ok", false)) and str(field.session.phase) == "local" and base_rear.position == base_rear_position + relay_offset, "満杯保持中は停め直しも車体表示も開始しない")
	field.session.field_capacity_limit_weight = RouteSession.UNLIMITED_FIELD_WEIGHT
	field.session.capacity_paused = false
	var return_reposition: Dictionary = field.session.request_reposition("entry")
	field.canyon_hub.refresh()
	_check(bool(return_reposition.get("ok", false)) and base_rear.position == base_rear_position + relay_offset, "中継から入口への停め直し中も確定済み中継車体を保持する")
	field._update_controls()
	_check(parking_status != null and parking_status.text.contains("入口へ回収中") and not parking_status.text.contains("中継へ回収中"), "入口へ戻す停め直しはHUDでも入口を目的地として示す")
	var cancelled: Dictionary = field.session.cancel_reposition()
	field.canyon_hub.refresh()
	_check(bool(cancelled.get("ok", false)) and str(field.session.state_summary().get("parking_slot", "")) == "relay" and base_rear.position == base_rear_position + relay_offset, "停め直し取消後はsessionと中継車体表示が一致する")
	var fixture_saved: Dictionary = field.session.save_project_fixture()
	field.session.parking_slot = "entry"
	field.canyon_hub.configure(field.session)
	_check(base_rear.position == base_rear_position, "fixture読込前に別session状態を投影すると入口車体へ戻る")
	field._load_fixture()
	await process_frame
	_check(bool(fixture_saved.get("ok", false)) and str(field.session.state_summary().get("parking_slot", "")) == "relay" and base_rear.position == base_rear_position + relay_offset, "検証fixture読込は保存した中継車体と荷下ろし接点を復元する")
	field.session.set_all_routes_closed(true)
	field._update_controls()
	_check(detail_status != null and detail_status.text.contains("再開後に帰還") and not detail_status.text.contains("再開または帰還"), "全路閉鎖中は帰還も再開後であることをHUDに正しく示す")
	field.session.set_all_routes_closed(false)
	field.session.request_recall()
	var ready_to_exit := await _advance_until(func(): return str(field.session.phase) == "ready_to_exit", 80.0)
	field._update_controls()
	_check(ready_to_exit and parking_status != null and parking_status.text.contains("帰還確定可") and detail_status != null and detail_status.text.contains("帰還可"), "帰還確定可能時は回収中でなく確定操作をHUDに示す")
	_check(field.canyon_hub.is_integer_render_layout(), "仮マーカーを含めNearest・整数描画契約を維持")
	_check(_all_vertical_controls_inside_panel(field.controls_panel), "縦切りHUDの文字と主要ボタンは1280x720 panel内に収まる")
	_finish()

func _prepare_field() -> bool:
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 104729)
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
	main.storage.store_owned(GameData.Item.HAUL_FRAME, 2, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.HAMMER, 1, Inventory.SOURCE_TRANSFER)
	main.storage.store_owned(GameData.Item.PICKAXE, 1, Inventory.SOURCE_TRANSFER)
	if not main.equip_tool(main.workers[0], GameData.Item.HAMMER):
		_check(false, "縦切りHUDの携行採掘具操作に必要な既存採掘具を用意")
		return false
	if not main.equip_work_support(main.workers[1], GameData.Item.HAUL_FRAME) or not main.equip_work_support(main.workers[2], GameData.Item.HAUL_FRAME):
		_check(false, "縦切りHUDの通常装備操作に必要な既存補助を用意")
		return false
	var created: Dictionary = RouteSession.create_from_game(main, "parking-ui", {"outpost_enabled": false, "vertical_slice": true})
	_check(bool(created.get("ok", false)), "縦切りsessionを既存C資源と仲間から作成")
	if not bool(created.get("ok", false)):
		return false
	main.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	field = FieldAdapter.new()
	field.configure(main, created.session)
	layer.add_child(field)
	await process_frame
	field.process_mode = Node.PROCESS_MODE_DISABLED
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

func _advance_until(predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		field.session.tick(STEP)
		var projection: Dictionary = field.session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return false
		field.canyon_hub.refresh(STEP)
		field._update_controls()
		await process_frame
		if predicate.call():
			return true
	return predicate.call()

func _all_vertical_controls_inside_panel(panel: PanelContainer) -> bool:
	if panel == null:
		return false
	var panel_rect := panel.get_global_rect()
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var node: Node = pending.pop_back() as Node
		for child in node.get_children():
			pending.append(child)
			if child is Label or child is Button:
				var control := child as Control
				if control.visible and not panel_rect.encloses(control.get_global_rect()):
					return false
	return true

func _finish() -> void:
	if field != null and is_instance_valid(field):
		field.queue_free()
	if main != null and is_instance_valid(main):
		main.queue_free()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
