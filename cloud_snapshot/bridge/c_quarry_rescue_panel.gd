extends PanelContainer
## View-only selection/binding. All movement and health stay in the session.
var adapter
var generation := 0
var bound_session
var bound_clock
var target_option: OptionButton
var carrier_option: OptionButton
var status_label: Label
var assign_button: Button
var return_button: Button
var cancel_button: Button
var refresh_button: Button
var close_button: Button
var _target_id := ""
var _carrier_id := ""
var _feedback := ""

func configure(owner_adapter) -> void:
	adapter = owner_adapter

func _ready() -> void:
	name = "CRescuePanel"
	position = Vector2(16, 48)
	custom_minimum_size = Vector2(470, 0)
	z_index = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "手動救助：対象と空荷の担ぎ手を指定"
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)
	target_option = OptionButton.new()
	target_option.name = "Target"
	box.add_child(target_option)
	carrier_option = OptionButton.new()
	carrier_option.name = "Carrier"
	box.add_child(carrier_option)
	target_option.item_selected.connect(_selection_changed)
	carrier_option.item_selected.connect(_selection_changed)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.custom_minimum_size = Vector2(450, 84)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	box.add_child(status_label)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	assign_button = _button(actions, "Assign", "救助へ向かう")
	return_button = _button(actions, "Transport", "入口へ搬送")
	cancel_button = _button(actions, "Interrupt", "救助を中断")
	var footer := HBoxContainer.new()
	box.add_child(footer)
	refresh_button = _button(footer, "Refresh", "一覧を更新")
	close_button = _button(footer, "Close", "閉じる")
	refresh_button.pressed.connect(rebuild)
	close_button.pressed.connect(close_panel)
	hide()

func _button(parent: Node, node_name: String, title: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = title
	button.custom_minimum_size = Vector2(116, 28)
	button.add_theme_font_size_override("font_size", 13)
	parent.add_child(button)
	return button

func open_panel() -> void:
	show()
	rebuild()

func close_panel() -> void:
	invalidate()
	hide()

func invalidate() -> void:
	generation += 1

func _exit_tree() -> void:
	invalidate()

func _process(_delta: float) -> void:
	if visible:
		refresh_status()

func rebuild() -> void:
	invalidate()
	_feedback = ""
	if not is_instance_valid(adapter) or adapter.session == null:
		return
	bound_session = adapter.session
	bound_clock = adapter.life_clock
	target_option.clear()
	carrier_option.clear()
	target_option.add_item("対象を選択")
	target_option.set_item_metadata(0, "")
	carrier_option.add_item("担ぎ手を選択（手動指定）")
	carrier_option.set_item_metadata(0, "")
	for actor_id in bound_session.actors:
		var actor: Dictionary = bound_session.actors[actor_id]
		var label := "%s [%s]" % [str(actor.get("name", actor_id)), str(actor_id)]
		if not bound_session.rescue_ledger.case_for(actor_id).is_empty() or bound_session.rescue_approach.treatment_pending(actor_id) or bound_session.expired_recovery.owns(actor_id):
			target_option.add_item(label)
			target_option.set_item_metadata(target_option.item_count - 1, str(actor_id))
			if actor_id == _target_id: target_option.select(target_option.item_count - 1)
		if not bool(actor.get("down", false)):
			carrier_option.add_item(label)
			carrier_option.set_item_metadata(carrier_option.item_count - 1, str(actor_id))
			if actor_id == _carrier_id: carrier_option.select(carrier_option.item_count - 1)
	_bind_actions()

func _selection_changed(_index: int) -> void:
	invalidate()
	_feedback = ""
	_bind_actions()

func _bind_actions() -> void:
	_target_id = str(target_option.get_selected_metadata()) if target_option.selected >= 0 else ""
	_carrier_id = str(carrier_option.get_selected_metadata()) if carrier_option.selected >= 0 else ""
	var target_id := _target_id
	var carrier_id := _carrier_id
	var captured_generation := generation
	var captured_session = bound_session
	var captured_clock = bound_clock
	for button in [assign_button, return_button, cancel_button]:
		for connection in button.get_signal_connection_list("pressed"):
			button.pressed.disconnect(connection.callable)
	assign_button.pressed.connect(func(): _command("assign", target_id, carrier_id, captured_generation, captured_session, captured_clock))
	return_button.pressed.connect(func(): _command("return", target_id, carrier_id, captured_generation, captured_session, captured_clock))
	cancel_button.pressed.connect(func(): _command("cancel", target_id, carrier_id, captured_generation, captured_session, captured_clock))
	refresh_status()

func _current() -> bool:
	return is_instance_valid(adapter) and adapter.rescue_context_current(self, bound_session, bound_clock)

func _command(action: String, target_id: String, carrier_id: String, expected_generation: int, expected_session, expected_clock) -> void:
	if generation != expected_generation or expected_session != bound_session or expected_clock != bound_clock or target_id != _target_id or carrier_id != _carrier_id or not _current():
		return
	if get_tree().paused or adapter.game.game_over or adapter.game.save_ui.is_open() or bound_session.phase not in ["local", "recall"] or not bound_session.actors.has(target_id) or (action == "assign" and not bound_session.actors.has(carrier_id)):
		return
	var result: Dictionary = {}
	match action:
		"assign": result = bound_session.request_rescue(target_id, carrier_id, bound_session.session_id)
		"return": result = bound_session.request_rescue_return(target_id, bound_session.session_id)
		"cancel": result = bound_session.cancel_rescue(target_id, bound_session.session_id)
		_: return
	# Every attempted command consumes this view binding, including failures.
	rebuild()
	if not result.get("ok", false):
		_feedback = str(result.get("reason", "現在の状態では指示できません"))
		refresh_status()

func refresh_status() -> void:
	if status_label == null:
		return
	if not _current():
		_disable_actions()
		status_label.text = "現在の現地画面ではありません。閉じて現在の画面から開き直してください。"
		return
	if _target_id.is_empty() or not bound_session.actors.has(_target_id):
		_disable_actions()
		status_label.text = "救助対象と担ぎ手を手動で選択してください。\n一覧にいなければ更新。詳細を開いても時間は止まりません。"
		return
	var actor: Dictionary = bound_session.actors[_target_id]
	var row: Dictionary = bound_session.rescue_ledger.case_for(_target_id)
	var phase := str(row.get("phase", ""))
	var carrier_id := str(row.get("carrier", ""))
	var carrier: Dictionary = bound_session.actors.get(carrier_id, {})
	var status := "救助待ち"
	match phase:
		"assigned": status = "担ぎ手が接近中（対象はまだ現地にいます）"
		"carried": status = "入口へ搬送中" if carrier.get("state") == "rescue_return" else "担ぎ上げ保持中：入口へ搬送できます"
		"incapacitated": status = "長期行動不能（暫定）。残り時間後に自力回復・入口へ帰還"
		"recovery_due": status = "自力回復の安全確認待ち（暫定）"
	if bound_session.expired_recovery.owns(_target_id):
		status = str(actor.get("wait_reason", "自力回復後の入口帰還（暫定）"))
	if bound_session.rescue_approach.treatment_pending(_target_id):
		status = "入口へ搬送済み。帰還確定後に治療・待機（HP条件は既存仮値）"
	status_label.text = "%s：%s\nHP %.0f / 手持ち %d" % [str(actor.get("name", _target_id)), status, float(actor.get("hp", 0.0)), int(actor.get("carry_n", 0))]
	if not row.is_empty(): status_label.text += " / 残り %.1f秒%s" % [float(row.left), "（担ぎ中停止）" if phase == "carried" else ""]
	if not carrier_id.is_empty(): status_label.text += "\n担当：" + str(carrier.get("name", carrier_id))
	if not _feedback.is_empty(): status_label.text += "\n" + _feedback
	if bound_session.phase == "ready_to_exit":
		_disable_actions()
		return
	if get_tree().paused or adapter.game.save_ui.is_open():
		_disable_actions()
		status_label.text += "\n一時停止中：救助指示も停止しています"
		return
	assign_button.disabled = phase != "waiting" or _carrier_id.is_empty()
	return_button.disabled = phase != "carried" or carrier.get("state") != "rescue_hold"
	cancel_button.disabled = phase not in ["assigned", "carried"]

func _disable_actions() -> void:
	assign_button.disabled = true
	return_button.disabled = true
	cancel_button.disabled = true
