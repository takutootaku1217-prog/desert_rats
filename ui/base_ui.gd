class_name BaseUI
extends CanvasLayer
## 拠点画面。Bキーまたは右上のボタンで開閉する。
## 左: 拠点レベル・収容人数・部屋の効果と、区画（部屋の場所）の一覧。右: 選んだ区画に建てられる部屋の一覧。
## 部屋は「建てる」で入れ替わる（費用は加工品）。加工設備・倉庫・ベッドの位置も部屋に合わせて移る。

var game
var _slot := "u1"              # 選択中の区画
var _overlay: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _timer := 0.0

const C_TEXT := Color("ffe9b0")
const C_DIM := Color("9aa3b2")
const C_ACCENT := Color("f2c14e")
const C_OK := Color("86efac")
const C_BAD := Color("f87171")


func _ready() -> void:
	layer = 22
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 12
	add_child(btn_layer)
	var btn := GameData.make_button("拠点 (B)", toggle)
	btn.position = Vector2(1000, 210)
	btn.custom_minimum_size = Vector2(272, 34)
	btn_layer.add_child(btn)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close())
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameData.panel_box(Color("1b1e24", 0.98), Color("636b7a"), 4, 12))
	panel.position = Vector2(80, 24)
	panel.custom_minimum_size = Vector2(1120, 672)
	_overlay.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := GameData.make_label("拠点（部屋を建て替える）", 22, C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(GameData.make_button("閉じる (B / Esc)", close))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(340, 0)
	_left.add_theme_constant_override("separation", 6)
	cols.add_child(_left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(620, 0)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 6)
	scroll.add_child(_right)


func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		game.close_other_panels(self)
		_overlay.visible = true
		_rebuild()


func close() -> void:
	_overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			toggle()
		elif event.keycode == KEY_ESCAPE and _overlay.visible:
			close()


func _process(delta: float) -> void:
	if _overlay != null and _overlay.visible:
		_timer -= delta
		if _timer <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_timer = 0.4
			_rebuild()


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _lbl(text: String, size: int = 15, color: Color = C_TEXT, minw: float = 0.0) -> Label:
	var l := GameData.make_label(text, size, color)
	if minw > 0.0:
		l.custom_minimum_size = Vector2(minw, 0)
	return l


## 幅に収まるよう折り返す説明文（長い文が画面の外へ広がらないように）
func _note(text: String, size: int = 12, color: Color = C_DIM, minw: float = 320.0) -> Label:
	var l := _lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(minw, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _select_slot(s: String) -> void:
	_slot = s
	_rebuild()


func _rebuild() -> void:
	if game == null:
		return
	_rebuild_left()
	_rebuild_right()


func _rebuild_left() -> void:
	_clear(_left)
	var lv: int = game.base_level()
	var nxt: int = game.base_level_next_points()
	_left.add_child(_lbl("拠点レベル Lv%d" % lv, 22, C_ACCENT))
	var prog := "MAX" if nxt < 0 else "部署の育ち %d / %d 点（次のLvまで）" % [game.base_level_points(), nxt]
	_left.add_child(_note(prog, 13))
	_left.add_child(_lbl("収容人数 %d / %d匹" % [game.workers.size(), game.max_crew()], 15))
	var beds: int = game.base.bed_capacity()
	_left.add_child(_lbl("ベッド %d（寝室 %d室）" % [beds, Rooms.count(game.room_layout, "bedroom")], 15))
	var fx := _fx_text()
	_left.add_child(_note(fx if fx != "" else "部屋の効果: なし", 13))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	_left.add_child(sp)
	_left.add_child(_lbl("── 区画（押して選ぶ） ──", 14, C_DIM))
	_left.add_child(_lbl("上の階", 13, C_DIM))
	_left.add_child(_slot_row(["u1", "u2"], Rooms.FIXED[0]["name"]))
	_left.add_child(_lbl("下の階", 13, C_DIM))
	_left.add_child(_slot_row(["l1", "l2"], Rooms.FIXED[1]["name"]))
	_left.add_child(_note("操縦室・搬入口は入れ替えできません。"))
	_left.add_child(_note("加工室と倉庫は1つだけ。別の区画に建てると移設になり、元の区画は空き部屋になります。"))
	_left.add_child(_note("寝室・加工室・倉庫は、最後の1つを壊せません。"))


func _fx_text() -> String:
	var parts: Array = []
	var rest: float = game.room_effect("rest_rate")
	if rest > 0.0:
		parts.append("休憩の回復 +%d%%" % int(round(rest * 100.0)))
	var drain: float = game.room_effect("drain_cut")
	if drain > 0.0:
		parts.append("元気の消耗 -%d%%" % int(round(drain * 100.0)))
	var tr: float = game.room_effect("train_xp")
	if tr > 0.0:
		parts.append("訓練の経験値 +%d%%" % int(round(tr * 100.0)))
	return "部屋の効果: " + " / ".join(PackedStringArray(parts)) if not parts.is_empty() else ""


func _slot_row(slots: Array, fixed_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for s in slots:
		var rt: String = game.room_layout.get(s, "empty")
		var b := GameData.make_button("%s\n%s" % [Rooms.SLOTS[s]["name"], Rooms.TYPES[rt]["name"]], func(): _select_slot(s), 13)
		b.custom_minimum_size = Vector2(102, 54)
		if s == _slot:
			b.add_theme_stylebox_override("normal", GameData.panel_box(Color("4b5262"), C_ACCENT, 3))
		row.add_child(b)
	var fb := GameData.make_button("\n%s\n(固定)" % fixed_name, func(): pass, 12)
	fb.custom_minimum_size = Vector2(102, 54)
	fb.disabled = true
	row.add_child(fb)
	return row


func _rebuild_right() -> void:
	_clear(_right)
	var cur: String = game.room_layout.get(_slot, "empty")
	_right.add_child(_lbl("%s の部屋を建て替える（今: %s）" % [Rooms.SLOTS[_slot]["name"], Rooms.TYPES[cur]["name"]], 17, C_ACCENT))
	for t in Rooms.TYPE_ORDER:
		if Rooms.can_place(t, _slot):
			_right.add_child(_type_row(t, cur))


func _type_row(t: String, cur: String) -> Control:
	var info: Dictionary = Rooms.TYPES[t]
	var is_cur := t == cur
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			GameData.panel_box(Color("23262d"), C_ACCENT if is_cur else Color("3a3f4a"), 3 if is_cur else 2, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	# 部屋の見た目（この区画に置いたときの絵を2倍で）
	var tex := GameData.tex(Rooms.overlay_path(_slot, t))
	var pv := TextureRect.new()
	pv.texture = tex
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_SCALE
	pv.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv.custom_minimum_size = Vector2(tex.get_size()) * 2.0
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pv)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(160, 0)
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	v.add_child(_lbl("%s%s" % [info["name"], "（今の部屋）" if is_cur else ""], 17, C_ACCENT if is_cur else C_TEXT))
	v.add_child(_note(info["desc"], 13, C_DIM, 160.0))
	v.add_child(_cost_row(info["cost"]))
	var why: String = game.room_block_reason(_slot, t)
	if why != "" and not is_cur:
		v.add_child(_lbl(why, 13, C_BAD))
	# 建てるボタン
	var reloc: bool = Rooms.is_relocation(game.room_layout, _slot, t)
	var label := "現在の部屋" if is_cur else ("移設する" if reloc else "建てる")
	var b := GameData.make_button(label, func(): game.build_room(_slot, t), 15)
	b.custom_minimum_size = Vector2(110, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = is_cur or not game.can_build_room(_slot, t)
	h.add_child(b)
	return panel


func _cost_row(cost: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_lbl("費用:", 13, C_DIM))
	if cost.is_empty():
		row.add_child(_lbl("なし", 13, C_OK))
		return row
	for it in cost:
		var have: int = game.storage.count_of(it)
		var ok: bool = have >= int(cost[it])
		row.add_child(_lbl("%s×%d（所持%d）" % [GameData.ITEM_NAMES[it], cost[it], have], 13, C_OK if ok else C_BAD))
	return row
