extends Node2D
## 専用比較シーン。既存の拠点断面・通常マップ・採石所のAIを変更しない。

const Model = preload("res://scripts/two_lane_prototype_model.gd")
var model: GroundTwoLanePrototypeModel
var selected_agent := 0
var info: Label
var _agent_buttons: Array[Button] = []
var _font: Font


func _ready() -> void:
	model = Model.new()
	model.reset("two")
	_font = ThemeDB.fallback_font
	_make_controls()
	queue_redraw()


func _process(delta: float) -> void:
	model.step(delta)
	_refresh_ui()
	queue_redraw()


func reset(mode: String) -> void:
	model.reset(mode)
	selected_agent = 0
	_refresh_ui()


func start_retreat_test() -> void:
	model.start_personal_retreat(selected_agent)


func _make_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_add_button(layer, "1: 一列比較", Vector2(18, 14), Vector2(132, 34), func(): reset("one"))
	_add_button(layer, "2: 二レーン比較", Vector2(158, 14), Vector2(150, 34), func(): reset("two"))
	_add_button(layer, "R: 個人退却", Vector2(316, 14), Vector2(126, 34), start_retreat_test)
	_add_button(layer, "A: 追跡試験", Vector2(450, 14), Vector2(126, 34), func(): model.start_chase(selected_agent))
	for i in 3:
		var b := Button.new()
		b.position = Vector2(18 + i * 142, 56)
		b.size = Vector2(134, 30)
		b.pressed.connect(func(): selected_agent = i)
		layer.add_child(b)
		_agent_buttons.append(b)
	info = Label.new()
	info.position = Vector2(18, 94)
	info.size = Vector2(525, 135)
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
		_agent_buttons[i].text = ("▶ " if i == selected_agent else "   ") + model.agent_status(i)
	var one_or_two := "一列" if model.mode == "one" else "固定2レーン"
	var end := "完了 %.1f秒" % model.completion_time if model.completion_time >= 0.0 else "進行中"
	info.text = "%s比較 / 同じ鉄鉱石 %d 個・仲間3人\n荷卸し %d/%d  残り %d  %s\n%s\n近接: %s\nTab/上の名前で奥側の仲間も直接選択。クリックは選択だけで、移動・近接判定とは分離。" % [one_or_two, Model.TOTAL_RESOURCE, model.delivered, Model.TOTAL_RESOURCE, model.remaining_resource(), end, model.attack_log, "別レーン命中なし" if model.cross_lane_melee_is_blocked() else "FAIL"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: reset("one")
			KEY_2: reset("two")
			KEY_R: start_retreat_test()
			KEY_A: model.start_chase(selected_agent)
			KEY_TAB: selected_agent = (selected_agent + 1) % model.agents.size()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in model.agents.size():
			if Vector2(model.agents[i]["position"]).distance_to(event.position) < 26.0:
				selected_agent = i


func _draw() -> void:
	# 空間の上下は高さではなく固定奥行き。背後に置いた拠点へ仲間を隠さない。
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color("c98a51"))
	draw_rect(Rect2(0, 260, 1280, 460), Color("dba965"))
	draw_rect(Rect2(0, Model.BACK_Y - 18, 1280, 38), Color("c99050"))
	draw_rect(Rect2(0, Model.FRONT_Y - 18, 1280, 38), Color("b8783e"))
	_draw_base()
	_draw_lane(Model.BACK_Y, "奥レーン  (拠点に近い)", Color("80603d"))
	_draw_lane(Model.FRONT_Y, "手前レーン", Color("5d432f"))
	_draw_ramp_and_crossing()
	for source in model.sources:
		_draw_source(source)
	if bool(model.enemy["alive"]):
		_draw_enemy(Vector2(model.enemy["position"]))
	var ordered := model.agents.duplicate()
	ordered.sort_custom(func(a, b): return Vector2(a["position"]).y < Vector2(b["position"]).y)
	for a in ordered:
		_draw_agent(a)
	draw_string(_font, Vector2(640, 690), "試作値: レーン間隔 120 px / 接続部 110 px / 歩行 90 px/s / 採取 0.8 s", HORIZONTAL_ALIGNMENT_CENTER, 0, 15, Color("fff0cf"))


func _draw_base() -> void:
	var base := Rect2(62, 214, 340, 94)
	draw_rect(base, Color("4c5560"))
	draw_rect(Rect2(68, 220, 328, 76), Color("78838a"))
	draw_rect(Rect2(82, 234, 42, 48), Color("38434c"))
	draw_rect(Rect2(142, 234, 42, 48), Color("38434c"))
	draw_rect(Rect2(202, 234, 42, 48), Color("38434c"))
	draw_rect(Rect2(262, 234, 42, 48), Color("38434c"))
	draw_string(_font, Vector2(84, 207), "移動拠点（奥側）", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("fff4d6"))
	draw_line(Vector2(330, 300), Model.RAMP_FOOT, Color("4a3d35"), 22)
	draw_line(Vector2(330, 300), Model.RAMP_FOOT, Color("a98258"), 14)
	draw_string(_font, Vector2(250, 330), "帰還スロープ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("403127"))


func _draw_lane(y: float, name: String, color: Color) -> void:
	for x in range(430, 1240, 42):
		draw_rect(Rect2(x, y - 2, 22, 3), color)
	draw_string(_font, Vector2(1010, y - 22), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("4a3423"))


func _draw_ramp_and_crossing() -> void:
	draw_line(Model.CROSS_BACK, Model.CROSS_FRONT, Color("6b4932"), 16)
	draw_line(Model.CROSS_BACK, Model.CROSS_FRONT, Color("d6bd78"), 8)
	draw_string(_font, Vector2(454, 428), "レーン接続", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("4a3423"))


func _draw_source(source: Dictionary) -> void:
	var p := Vector2(source["position"])
	_draw_ellipse(p + Vector2(0, 7), Vector2(28, 7), Color(0, 0, 0, 0.24))
	draw_circle(p + Vector2(-11, -7), 13, Color("6c5d73"))
	draw_circle(p + Vector2(4, -14), 18, Color("8c7aa0"))
	draw_circle(p + Vector2(18, -6), 12, Color("5a516c"))
	draw_string(_font, p + Vector2(-30, -42), "鉄鉱脈 %d" % int(source["remaining"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff2cb"))


func _draw_enemy(p: Vector2) -> void:
	_draw_ellipse(p + Vector2(0, 8), Vector2(32, 8), Color(0, 0, 0, 0.25))
	draw_circle(p + Vector2(0, -18), 22, Color("802f34"))
	draw_circle(p + Vector2(18, -14), 10, Color("a7443c"))
	draw_string(_font, p + Vector2(-44, -54), "近接試験敵", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffe2ce"))


func _draw_agent(a: Dictionary) -> void:
	var p := Vector2(a["position"])
	var color: Color = [Color("72b4bf"), Color("e6a95f"), Color("ca79a5")][int(a["id"])]
	_draw_ellipse(p + Vector2(0, 6), Vector2(18, 6), Color(0, 0, 0, 0.30))
	draw_circle(p + Vector2(0, -16), 15, color)
	draw_circle(p + Vector2(8, -20), 5, Color("f6dac5"))
	if int(a["cargo"]) > 0:
		draw_rect(Rect2(p + Vector2(-9, -49), Vector2(18, 13)), Color("8c673c"))
	if int(a["id"]) == selected_agent:
		draw_arc(p + Vector2(0, -16), 23, 0, TAU, 18, Color("fff26e"), 2)
	draw_string(_font, p + Vector2(-30, 30), String(a["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff4d6"))
	draw_string(_font, p + Vector2(-38, 45), model._state_name(String(a["state"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("5a342a"))


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 18:
		var angle := TAU * float(i) / 18.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
