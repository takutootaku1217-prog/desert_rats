extends CanvasLayer
## Presentation only; existing saved goal is the authority. No save migration.
var game
var _overlay: ColorRect
var _panel: PanelContainer
var _text: Label
var _confirm: Button
var _seen := false
var _closing := false
var _owns_pause := false
var _was_paused := false
var _held_keys := {}
var _held_buttons := {}

func _ready() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.color = Color(0,0,0,0.84)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",UIKit.box(Color("1b1e24"),UIKit.C_ACCENT,3,20))
	_overlay.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",18)
	_panel.add_child(box)
	box.add_child(UIKit.lbl("第1地域突破",28,UIKit.C_ACCENT))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_text = UIKit.lbl("",20)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_text)
	_confirm = UIKit.button("確認して旅を続ける",acknowledge)
	_confirm.focus_mode = Control.FOCUS_ALL
	_confirm.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.custom_minimum_size.y = 48
	box.add_child(_confirm)
	_overlay.hide()
	get_window().focus_exited.connect(_on_focus_exited)

func is_open() -> bool:
	return _overlay != null and _overlay.visible

func _process(_delta: float) -> void:
	if is_open():
		var available := get_viewport().get_visible_rect().size
		_panel.size = Vector2(minf(720,available.x-32),minf(390,available.y-32))
		_panel.position = (available-_panel.size)/2.0
		if _closing and _held_keys.is_empty() and _held_buttons.is_empty(): close()
		return
	if _seen or game.game_over or not game.world.region_goal_snapshot().get("completed",false): return
	var gate = game.mine_arrival_gate
	if gate != null and (gate.field != null or gate.visible_state() == "entry_wait"): return
	if not game.visible or game.has_open_management_panel(): return
	# Deferred frame, never reentrant payment/return observer or another menu.
	game.close_other_panels(self)
	_was_paused = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	var goal: Dictionary = game.world.region_goal_snapshot()
	_text.text = str(goal.text) + "\n\n" + str(goal.detail) + "\n\nここでは自動保存しません。進行を残すには「保存 / 続きから」で手動保存してください。"
	_closing = false
	_overlay.show()
	_confirm.grab_focus()

func acknowledge() -> void:
	if not is_open() or _closing: return
	_seen = true
	_closing = true
	# Keep shield/pause through the confirming event and all held releases.

func close() -> void:
	if _overlay != null: _overlay.hide()
	if _confirm != null and _confirm.has_focus(): _confirm.release_focus()
	_closing = false
	if _owns_pause:
		get_tree().paused = _was_paused
		_owns_pause = false
	# Administrative dismissal is not acknowledgement; it can reappear later.

func reset_for_loaded_game() -> void:
	# Successful apply only, BEFORE installing a new field's pause ownership.
	close()
	_seen = false

func _on_focus_exited() -> void:
	# OS focus loss can swallow releases; avoid a confirmed modal getting stuck.
	_held_keys.clear()
	_held_buttons.clear()

func _input(event: InputEvent) -> void:
	# Track actual held input even before presentation/load/menu handoff. Only
	# consume while visible. Administrative close must not erase a held key.
	if event is InputEventKey:
		var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if event.pressed: _held_keys[key] = true
		else: _held_keys.erase(key)
		if not is_open(): return
		get_viewport().set_input_as_handled()
		if _closing or not event.pressed or event.echo: return
		if key == KEY_TAB: _confirm.grab_focus()
		elif key in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE] and _confirm.has_focus(): acknowledge()
		return
	if event is InputEventMouseButton:
		# Scroll pulses are not durable holds; synthetic/accessibility sources
		# need not pair them with releases.
		if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]:
			if event.pressed: _held_buttons[event.button_index] = true
			else: _held_buttons.erase(event.button_index)
		if is_open() and _closing: get_viewport().set_input_as_handled()
		return
	if is_open() and not event is InputEventMouseMotion: get_viewport().set_input_as_handled()
