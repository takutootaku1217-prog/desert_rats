class_name WorkPriorityUI
extends CanvasLayer
## 画面上部に並ぶ、仲間ごとの「状態＋ステータス（HP・満腹度・疲労度・精神状態）＋作業優先度」パネル。
## ボタンは大きめ（タップ想定）。操作はすべて Worker.set_priority() を呼ぶだけなので、
## 将来スマホ用UIに差し替えてもゲームロジックには影響しない。

signal worker_selected(worker)

var workers: Array = []
var _cards := {}   # Worker -> {status, stars, view（CrewStatusView）, style}

const C_BG := Color("1b1e24")
const C_EDGE := Color("636b7a")
const C_EDGE_SEL := Color("f2c14e")
const C_TEXT := Color("ffe9b0")


func build(p_workers: Array) -> void:
	workers = p_workers
	layer = 10
	var root := HBoxContainer.new()
	root.position = Vector2(10, 8)
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	for w in workers:
		root.add_child(_make_card(w))
	set_selected(workers[0])


func _box(bg: Color, edge: Color, border: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border)
	sb.border_color = edge
	sb.set_corner_radius_all(0)         # ドット絵に合わせて角丸にしない
	sb.anti_aliasing = false
	return sb


func _make_card(w) -> Control:
	var panel := PanelContainer.new()
	var sb := _box(Color(C_BG, 0.92), C_EDGE)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(300, 0)
	panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			worker_selected.emit(w))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(GameData.make_label("%s Lv%d [%s]" % [w.char_name, w.level, w.rank_letter()], 18, C_TEXT))
	var status := GameData.make_label("", 14, Color("fde68a"))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(status)
	# ステータス: HP・満腹度・疲労度の「アイコン自体がゲージ」と、精神状態の顔（ui/crew_status_view.gd。値は Worker から読むだけ）
	var view := CrewStatusView.new().setup(Vector2i(12, 12), 12)
	v.add_child(view)
	# 通常仕事の優先度。休憩・食事は生活の自動行動なので、星で制限しない。
	var stars := {}
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	v.add_child(grid)
	for job in GameData.job_list():
		if job == GameData.Job.REST:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		grid.add_child(row)
		var jl := GameData.make_label(GameData.JOB_NAMES[job], 14)
		jl.custom_minimum_size = Vector2(38, 0)
		row.add_child(jl)
		row.add_child(_make_button("－", func(): _change(w, job, -1)))
		var star := GameData.make_label("", 14, Color("ffd24a"))
		star.custom_minimum_size = Vector2(38, 0)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(star)
		row.add_child(_make_button("＋", func(): _change(w, job, 1)))
		stars[job] = star
	v.add_child(GameData.make_label("休憩・食事は自動", 12, Color("9aa3b2")))
	_cards[w] = {"status": status, "stars": stars, "view": view, "style": sb}
	return panel


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(30, 24)
	b.add_theme_font_override("font", GameData.font())
	b.add_theme_stylebox_override("normal", _box(Color("3a3f4a"), Color("636b7a"), 2))
	b.add_theme_stylebox_override("hover", _box(Color("4b5262"), Color("f2c14e"), 2))
	b.add_theme_stylebox_override("pressed", _box(Color("22252b"), Color("f2c14e"), 2))
	b.add_theme_color_override("font_color", Color("ffe9b0"))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _change(w, job: int, d: int) -> void:
	w.set_priority(job, w.priorities.get(job, 0) + d)
	worker_selected.emit(w)


func set_selected(sel) -> void:
	for w in _cards:
		_cards[w]["style"].border_color = C_EDGE_SEL if w == sel else C_EDGE


func _process(_delta: float) -> void:
	for w in _cards:
		var c: Dictionary = _cards[w]
		c["status"].text = w.ai.status_text()
		c["view"].update_from(w)
		for job in GameData.job_list():
			if job == GameData.Job.REST:
				continue
			var n: int = w.priorities.get(job, 0)
			c["stars"][job].text = "★%d" % n if n > 0 else "─"
