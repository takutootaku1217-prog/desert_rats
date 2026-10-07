class_name CrewAlertUI
extends CanvasLayer
## 注意のある仲間だけを小さく表示する。数値・生活の判断・予約は既存モデルが担当する。
## 通常HUDは最大3人と残り人数、タップすると1人の情報と生活の促しを開く。

const MAX_CARDS := 3
const REFRESH_SECONDS := 0.3
const WARNING_WORDS := {"hp": "HP低下", "hunger": "空腹", "fatigue": "疲労", "mental": "精神"}

var game
var workers: Array = []
var _root: Control
var _cards: Array[Button] = []
var _overflow: Button
var _entries: Array = []
var _numbers := {}                  # Worker -> このセッションで初回登録した番号（再利用しない）
var _next_number := 1
var _portraits := {}                # Worker -> 既存待機コマのAtlasTexture
var _signature := ""
var _render_pending := false
var _list_refresh_pending := false
var _timer := 0.0

var _popup_layer: CanvasLayer
var _overlay: Control
var _panel: PanelContainer
var _content: VBoxContainer
var _mode := ""
var _brief_worker = null
var _view: CrewStatusView
var _status: Label
var _warnings: Label
var _rest: Button
var _eat: Button
var _rest_hint: Label
var _eat_hint: Label
var _pending: Label
var _details: Button
var _list_scroll: ScrollContainer
var _list_rows := {}                # Worker -> Button
var _list_box: VBoxContainer
var _list_revision := 0


func build(p_workers: Array) -> void:
	workers = p_workers
	layer = 10
	_register_workers()
	_root = Control.new()
	_root.position = Vector2(166, 8)
	_root.size = Vector2(392, 44)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for i in MAX_CARDS:
		var button := _make_card()
		button.position = Vector2(i * 116, 0)
		_root.add_child(button)
		_cards.append(button)
	_overflow = UIKit.button("", open_list)
	_overflow.position = Vector2(348, 0)
	_overflow.custom_minimum_size = Vector2(44, 44)
	_overflow.size = Vector2(44, 44)
	_overflow.clip_text = true
	_overflow.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overflow.add_theme_font_size_override("font_size", 14)
	_overflow.hide()
	_root.add_child(_overflow)
	_build_overlay()
	_refresh()


func _register_workers() -> void:
	for w in workers:
		if is_instance_valid(w) and not _numbers.has(w):
			_numbers[w] = _next_number
			_next_number += 1


func number_of(w) -> int:
	if not is_instance_valid(w) or not workers.has(w):
		return 0
	_register_workers()
	return int(_numbers[w])


## 全件を既存の警告基準で判定する。精神状態は既存カテゴリ「不調」「限界」を表示する。
func warnings_for(w) -> Array:
	var result: Array = []
	if not is_instance_valid(w):
		return result
	for stat in CrewStatusDB.WARN_ORDER:
		if stat == "mental":
			if w.mental == CrewStatusDB.Mental.BAD or w.mental == CrewStatusDB.Mental.LIMIT:
				result.append({"stat": stat, "strong": w.mental == CrewStatusDB.Mental.LIMIT})
			continue
		var value: float = float(w.get(stat))
		var high_bad: bool = CrewStatusDB.is_high_bad(stat)
		var line: float = float(CrewStatusDB.WARN_LINE[stat])
		var strong_line: float = float(CrewStatusDB.WARN_STRONG[stat])
		if (high_bad and value >= line) or (not high_bad and value < line):
			result.append({"stat": stat, "strong": value >= strong_line if high_bad else value < strong_line})
	return result


func _process(delta: float) -> void:
	if _root == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_SECONDS
	_refresh()


func _refresh() -> void:
	_register_workers()
	var next: Array = []
	for w in workers:
		if not is_instance_valid(w):
			continue
		var warnings := warnings_for(w)
		if warnings.is_empty():
			continue
		var urgent: bool = w.down
		var priority := CrewStatusDB.WARN_ORDER.size()
		for warning in warnings:
			if warning["strong"]:
				urgent = true
				priority = mini(priority, CrewStatusDB.WARN_ORDER.find(warning["stat"]))
		if priority == CrewStatusDB.WARN_ORDER.size():
			priority = CrewStatusDB.WARN_ORDER.find(warnings[0]["stat"])
		next.append({"worker": w, "number": int(_numbers[w]), "warnings": warnings, "urgent": urgent, "priority": priority})
	next.sort_custom(func(a, b):
		if a["urgent"] != b["urgent"]:
			return a["urgent"]
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["number"] < b["number"])
	_entries = next
	var signature := ""
	for entry in _entries:
		var w = entry["worker"]
		signature += "%d:%s:%s:%s:%s|" % [w.get_instance_id(), w.char_name, w.palette, str(entry["urgent"]), str(entry["warnings"])]
	var changed: bool = signature != _signature
	_signature = signature
	if changed or _render_pending:
		_render_cards()
	if _overlay.visible:
		if _mode == "brief":
			_update_brief()
		elif _mode == "list" and (changed or _list_refresh_pending):
			_rebuild_list()


func _make_card() -> Button:
	var button := UIKit.button("", func(): pass)
	button.custom_minimum_size = Vector2(112, 44)
	button.size = Vector2(112, 44)
	button.clip_text = true
	button.hide()
	button.pressed.connect(_on_card_pressed.bind(button))
	var portrait := _texture_rect(Vector2(32, 32))
	portrait.position = Vector2(6, 6)
	button.add_child(portrait)
	var name_label := _fixed_label("", 11, 18)
	name_label.position = Vector2(42, 2)
	name_label.size = Vector2(64, 18)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(name_label)
	var icons: Array = []
	for i in CrewStatusDB.WARN_ORDER.size():
		var icon := _texture_rect(Vector2(14, 14))
		icon.position = Vector2(42 + i * 16, 24)
		icon.hide()
		button.add_child(icon)
		icons.append(icon)
	button.set_meta("portrait", portrait)
	button.set_meta("identity", name_label)
	button.set_meta("icons", icons)
	return button


func _render_cards() -> void:
	_render_pending = false
	for i in _cards.size():
		var button: Button = _cards[i]
		# 押下した個体は指を離すまで保持する。警告の並べ替えで、別個体へのタップにしない。
		if button.is_pressed():
			_render_pending = true
			continue
		if i >= _entries.size():
			button.hide()
			button.set_meta("worker", null)
			button.set_meta("number", 0)
			continue
		_bind_card(button, _entries[i])
	var extra := maxi(0, _entries.size() - MAX_CARDS)
	_overflow.visible = extra > 0
	_overflow.text = "+%d" % extra
	_overflow.tooltip_text = "ほかに注意のある仲間 %d人。タップして確認します。" % extra


func _bind_card(button: Button, entry: Dictionary) -> void:
	var w = entry["worker"]
	button.set_meta("worker", w)
	button.set_meta("number", entry["number"])
	button.show()
	var portrait: TextureRect = button.get_meta("portrait")
	portrait.texture = _portrait_of(w)
	var name_label: Label = button.get_meta("identity")
	name_label.text = "No.%d %s" % [entry["number"], w.char_name]
	button.tooltip_text = "No.%d %s\n%s\nタップして状態と対処を確認します。" % [entry["number"], w.char_name, _warning_text(w, entry["warnings"])]
	var icons: Array = button.get_meta("icons")
	for i in icons.size():
		var icon: TextureRect = icons[i]
		icon.visible = i < entry["warnings"].size()
		if icon.visible:
			var warning: Dictionary = entry["warnings"][i]
			icon.texture = _warning_texture(warning)
			icon.modulate = CrewStatusDB.COLOR_DANGER if warning["strong"] else CrewStatusDB.COLOR_WARN
	var edge: Color = CrewStatusDB.COLOR_DANGER if entry["urgent"] else CrewStatusDB.COLOR_WARN
	button.add_theme_stylebox_override("normal", UIKit.box(Color("25282e", 0.96), edge, 2, 4))


func _portrait_of(w) -> Texture2D:
	var sheet := GameData.tex("res://assets/characters/mouse_%s.png" % w.palette)
	if not _portraits.has(w) or _portraits[w].atlas != sheet:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = ArtSpec.frame_src(sheet, ArtSpec.WORKER, Worker.F_IDLE0)
		atlas.filter_clip = true
		_portraits[w] = atlas
	return _portraits[w]


func _warning_texture(warning: Dictionary) -> Texture2D:
	var file: String = "mental_limit" if warning["strong"] else "mental_bad"
	if warning["stat"] != "mental":
		file = String(CrewStatusDB.ICON_FILES[warning["stat"]])
	return GameData.tex("res://assets/ui/%s.png" % file)


func _warning_text(w, warnings: Array) -> String:
	if warnings.is_empty():
		return "注意は解消しました。"
	var parts: Array[String] = []
	for warning in warnings:
		var stat: String = warning["stat"]
		parts.append("精神：%s" % CrewStatusDB.MENTAL_NAMES[w.mental] if stat == "mental" else String(WARNING_WORDS[stat]))
	return "注意：" + " / ".join(PackedStringArray(parts))


func _on_card_pressed(button: Button) -> void:
	open_worker(button.get_meta("worker", null))


func _build_overlay() -> void:
	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = 26
	add_child(_popup_layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.hide()
	_popup_layer.add_child(_overlay)
	var outside := ColorRect.new()
	outside.color = Color(0, 0, 0, 0)
	outside.set_anchors_preset(Control.PRESET_FULL_RECT)
	outside.mouse_filter = Control.MOUSE_FILTER_STOP
	outside.gui_input.connect(_on_outside_input.bind(outside))
	_overlay.add_child(outside)
	_panel = PanelContainer.new()
	_panel.position = Vector2(10, 74)
	_panel.custom_minimum_size = Vector2(360, 330)
	_panel.size = Vector2(360, 330)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UIKit.box(Color("1b1e24", 0.98), UIKit.C_ACCENT, 2, 8))
	_overlay.add_child(_panel)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 3)
	_panel.add_child(_content)


func _on_outside_input(event: InputEvent, outside: Control) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		outside.accept_event()
		close()


func _input(event: InputEvent) -> void:
	if _overlay == null or not _overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func open_worker(w) -> void:
	if not _valid_worker(w):
		return
	game.close_other_panels(self)
	_mode = "brief"
	_brief_worker = w
	_overlay.show()
	_clear_content()
	_add_header("No.%d %s" % [number_of(w), w.char_name])
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	scroll.add_child(body)
	_status = _wrapped_label("", 12)
	body.add_child(_status)
	_warnings = _wrapped_label("", 12)
	body.add_child(_warnings)
	_view = CrewStatusView.new().setup(Vector2i(8, 8), 10, true)
	body.add_child(_view)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_content.add_child(actions)
	_rest = UIKit.button("休憩を促す", _request_life_action.bind(w, "rest"))
	_eat = UIKit.button("食事を促す", _request_life_action.bind(w, "eat"))
	for button in [_rest, _eat]:
		button.custom_minimum_size = Vector2(150, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		actions.add_child(button)
	_rest_hint = _fixed_label("", 11, 16)
	_eat_hint = _fixed_label("", 11, 16)
	_rest_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_eat_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(_rest_hint)
	_content.add_child(_eat_hint)
	_pending = _fixed_label("", 11, 16)
	_pending.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(_pending)
	var help := _fixed_label("促しは安全な区切りで実行。予約は開始時。", 11, 16)
	_content.add_child(help)
	_details = UIKit.button("詳細を開く", _open_details.bind(w))
	_details.custom_minimum_size = Vector2(0, 32)
	_details.add_theme_font_size_override("font_size", 14)
	_content.add_child(_details)
	_update_brief()


func _update_brief() -> void:
	var w = _brief_worker
	if not _valid_worker(w):
		close()
		return
	_status.text = "遠征中" if w.away else ("戦闘不能" if w.down else w.ai.status_text())
	_warnings.text = _warning_text(w, warnings_for(w))
	_view.update_from(w)
	var rest_reason: String = w.ai.life_action_reason("rest")
	var eat_reason: String = w.ai.life_action_reason("eat")
	_rest.disabled = not rest_reason.is_empty()
	_eat.disabled = not eat_reason.is_empty()
	_rest.tooltip_text = rest_reason
	_eat.tooltip_text = eat_reason
	_rest_hint.text = "休憩：" + (_short_reason(rest_reason) if not rest_reason.is_empty() else "早めに促せます")
	_eat_hint.text = "食事：" + (_short_reason(eat_reason) if not eat_reason.is_empty() else "早めに促せます")
	_rest_hint.tooltip_text = rest_reason
	_eat_hint.tooltip_text = eat_reason
	var request: String = w.ai.life_request
	_pending.visible = not request.is_empty()
	_pending.text = "%sを促しています。安全な区切りを待っています。" % ("休憩" if request == "rest" else "食事") if not request.is_empty() else ""
	_pending.tooltip_text = _pending.text


func _request_life_action(w, action: String) -> void:
	if _mode != "brief" or not _overlay.visible or not _valid_worker(w) or w != _brief_worker:
		return
	w.ai.request_life_action(action)
	_update_brief()


func _open_details(w) -> void:
	if _mode != "brief" or not _overlay.visible or not _valid_worker(w) or w != _brief_worker:
		return
	close()
	game.detail.open_worker(w)


func open_list() -> void:
	game.close_other_panels(self)
	_mode = "list"
	_brief_worker = null
	_overlay.show()
	_clear_content()
	_rebuild_list()


func _rebuild_list() -> void:
	for button in _list_rows.values():
		if is_instance_valid(button) and button.is_pressed():
			_list_refresh_pending = true
			return
	_list_refresh_pending = false
	var previous_scroll: int = _list_scroll.scroll_vertical if is_instance_valid(_list_scroll) else 0
	_clear_content()
	_list_revision += 1
	var remaining: Array = _entries.slice(MAX_CARDS)
	_add_header("ほかに注意のある仲間 %d人" % remaining.size())
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	_list_scroll.add_child(_list_box)
	if remaining.is_empty():
		_list_box.add_child(_wrapped_label("残りの注意はありません。", 14))
	for entry in remaining:
		var w = entry["worker"]
		var button := UIKit.button("", func(): pass)
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.set_meta("worker", w)
		button.set_meta("number", entry["number"])
		button.pressed.connect(_on_list_row_pressed.bind(button))
		var portrait := _texture_rect(Vector2(32, 32))
		portrait.position = Vector2(6, 8)
		portrait.texture = _portrait_of(w)
		button.add_child(portrait)
		var name_label := _fixed_label("No.%d %s" % [entry["number"], w.char_name], 13, 20)
		name_label.position = Vector2(44, 3)
		name_label.size = Vector2(260, 20)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(name_label)
		var warning_label := _fixed_label(_warning_text(w, entry["warnings"]), 11, 18)
		warning_label.position = Vector2(44, 25)
		warning_label.size = Vector2(260, 18)
		warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(warning_label)
		button.tooltip_text = "%s\n%s" % [name_label.text, warning_label.text]
		_list_box.add_child(button)
		_list_rows[w] = button
	if previous_scroll > 0:
		call_deferred("_restore_list_scroll", _list_revision, previous_scroll, 2)


func _restore_list_scroll(revision: int, offset: int, remaining_frames: int) -> void:
	if revision != _list_revision or not is_inside_tree() or _mode != "list" or not _overlay.visible:
		return
	if remaining_frames > 0:
		get_tree().process_frame.connect(_restore_list_scroll.bind(revision, offset, remaining_frames - 1), CONNECT_ONE_SHOT)
		return
	_list_scroll.scroll_vertical = offset


func _on_list_row_pressed(button: Button) -> void:
	open_worker(button.get_meta("worker", null))


func close() -> void:
	if _overlay != null:
		_overlay.hide()
	_mode = ""
	_brief_worker = null


func _valid_worker(w) -> bool:
	return is_instance_valid(w) and workers.has(w)


func _clear_content() -> void:
	UIKit.clear(_content)
	_list_rows.clear()
	_view = null
	_status = null
	_warnings = null
	_rest = null
	_eat = null
	_rest_hint = null
	_eat_hint = null
	_pending = null
	_details = null
	_list_scroll = null
	_list_box = null


func _add_header(text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_content.add_child(row)
	var label := _fixed_label(text, 16, 28)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	var dismiss := UIKit.button("×", close)
	dismiss.custom_minimum_size = Vector2(30, 28)
	dismiss.add_theme_font_size_override("font_size", 14)
	dismiss.alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(dismiss)


func _texture_rect(dimensions: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = dimensions
	rect.size = dimensions
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _fixed_label(text: String, font_size: int, height: float) -> Label:
	var label := UIKit.lbl(text, font_size)
	label.clip_text = true
	label.custom_minimum_size = Vector2(0, height)
	return label


func _wrapped_label(text: String, font_size: int) -> Label:
	var label := UIKit.lbl(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _short_reason(reason: String) -> String:
	var index := reason.find("（")
	return reason.substr(0, index) if index >= 0 else reason
