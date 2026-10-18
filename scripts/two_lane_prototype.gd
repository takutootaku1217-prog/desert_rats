extends Node2D
## 比較用の小規模試作。固定線・固定横断路ではなく、連続した浅い奥行き帯を描く。

const Model = preload("res://scripts/two_lane_prototype_model.gd")
var model: GroundTwoLanePrototypeModel
var selected_agent := 0
var info: Label
var _agent_buttons: Array[Button] = []
var _font: Font


func _ready() -> void:
	model = Model.new()
	model.reset()
	_font = ThemeDB.fallback_font
	_make_controls()
	queue_redraw()


func _process(delta: float) -> void:
	model.step(delta)
	_refresh_ui()
	queue_redraw()


func reset() -> void:
	model.reset()
	selected_agent = 0
	_refresh_ui()


func start_retreat_test() -> void:
	model.start_personal_retreat(selected_agent)


func _make_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_add_button(layer, "Reset", Vector2(18, 14), Vector2(110, 34), reset)
	_add_button(layer, "R: Return", Vector2(138, 14), Vector2(126, 34), start_retreat_test)
	_add_button(layer, "A: Chase", Vector2(274, 14), Vector2(126, 34), func(): model.start_chase(selected_agent))
	for i in 3:
		var b := Button.new()
		b.position = Vector2(18 + i * 160, 56)
		b.size = Vector2(152, 30)
		b.pressed.connect(func(): selected_agent = i)
		layer.add_child(b)
		_agent_buttons.append(b)
	info = Label.new()
	info.position = Vector2(18, 100)
	info.size = Vector2(660, 96)
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color("fff4d6"))
	layer.add_child(info)
	_refresh_ui()


func _add_button(layer: CanvasLayer, text: String, pos: Vector2, size: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = size
	button.pressed.connect(action)
	layer.add_child(button)


func _refresh_ui() -> void:
	if model == null:
		return
	for i in _agent_buttons.size():
		_agent_buttons[i].text = ("> " if i == selected_agent else "   ") + String(model.agents[i].name)
	var end := "完了 %.1f秒" % model.completion_time if model.completion_time >= 0.0 else "進行中"
	info.text = "連続奥行き帯（2レーン相当幅）/ 総資源%d・仲間3人\n荷卸し %d/%d・残%d・%s\n選択: %s\n近接: %s（Tab・名前・クリックで選択）" % [Model.TOTAL_RESOURCE, model.delivered, Model.TOTAL_RESOURCE, model.remaining_resource(), end, model.agent_status(selected_agent), "奥行き距離を確認" if model.depth_melee_is_blocked() else "FAIL"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2: reset()
			KEY_R: start_retreat_test()
			KEY_A: model.start_chase(selected_agent)
			KEY_TAB: selected_agent = (selected_agent + 1) % model.agents.size()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in model.agents.size():
			if Vector2(model.agents[i].position).distance_to(event.position) < 26.0:
				selected_agent = i


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color("c98a51"))
	draw_rect(Rect2(0, 260, 1280, 460), Color("dba965"))
	# Two-lane-width means a shallow continuous band, not two painted rails.
	draw_rect(Rect2(0, Model.BACK_Y - 18, 1280, Model.FRONT_Y - Model.BACK_Y + 36), Color("c99050"))
	draw_line(Vector2(0, Model.BACK_Y - 18), Vector2(1280, Model.BACK_Y - 18), Color("8d673e"), 2)
	draw_line(Vector2(0, Model.FRONT_Y + 18), Vector2(1280, Model.FRONT_Y + 18), Color("8d673e"), 2)
	_draw_base()
	for source in model.sources:
		_draw_source(source)
	if bool(model.enemy.alive):
		_draw_enemy(Vector2(model.enemy.position))
	var ordered := model.agents.duplicate()
	ordered.sort_custom(func(a, b): return Vector2(a.position).y < Vector2(b.position).y)
	for a in ordered:
		_draw_agent(a)
	draw_string(_font, Vector2(640, 690), "仮値: 奥行き帯 90 px / 移動 90 px/s / 近接 58 px / 採取 0.8 秒", HORIZONTAL_ALIGNMENT_CENTER, 0, 15, Color("fff0cf"))


func _draw_base() -> void:
	var base := Rect2(62, 214, 340, 94)
	draw_rect(base, Color("4c5560"))
	draw_rect(Rect2(68, 220, 328, 76), Color("78838a"))
	for x in [82, 142, 202, 262]:
		draw_rect(Rect2(x, 234, 42, 48), Color("38434c"))
	draw_string(_font, Vector2(84, 207), "移動拠点（奥側）", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("fff4d6"))
	draw_line(Vector2(330, 300), Model.RAMP_FOOT, Color("4a3d35"), 22)
	draw_line(Vector2(330, 300), Model.RAMP_FOOT, Color("a98258"), 14)
	draw_string(_font, Vector2(250, 330), "既存の帰還スロープ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("403127"))


func _draw_source(source: Dictionary) -> void:
	var p := Vector2(source.position)
	_draw_ellipse(p + Vector2(0, 7), Vector2(28, 7), Color(0, 0, 0, 0.24))
	draw_circle(p + Vector2(-11, -7), 13, Color("6c5d73"))
	draw_circle(p + Vector2(4, -14), 18, Color("8c7aa0"))
	draw_circle(p + Vector2(18, -6), 12, Color("5a516c"))
	draw_string(_font, p + Vector2(-30, -42), "鉄鉱石 %d" % int(source.remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff2cb"))


func _draw_enemy(p: Vector2) -> void:
	_draw_ellipse(p + Vector2(0, 8), Vector2(32, 8), Color(0, 0, 0, 0.25))
	draw_circle(p + Vector2(0, -18), 22, Color("802f34"))
	draw_circle(p + Vector2(18, -14), 10, Color("a7443c"))
	draw_string(_font, p + Vector2(-44, -54), "近接テスト敵", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffe2ce"))


func _draw_agent(a: Dictionary) -> void:
	var p := Vector2(a.position)
	var color: Color = [Color("72b4bf"), Color("e6a95f"), Color("ca79a5")][int(a.id)]
	_draw_ellipse(p + Vector2(0, 6), Vector2(18, 6), Color(0, 0, 0, 0.30))
	draw_circle(p + Vector2(0, -16), 15, color)
	draw_circle(p + Vector2(8, -20), 5, Color("f6dac5"))
	if int(a.cargo) > 0:
		draw_rect(Rect2(p + Vector2(-9, -49), Vector2(18, 13)), Color("8c673c"))
	if int(a.id) == selected_agent:
		draw_arc(p + Vector2(0, -16), 23, 0, TAU, 18, Color("fff26e"), 2)
	draw_string(_font, p + Vector2(-30, 30), String(a.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff4d6"))
	draw_string(_font, p + Vector2(-38, 45), model._state_name(String(a.state)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("5a342a"))


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 18:
		var angle := TAU * float(i) / 18.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
