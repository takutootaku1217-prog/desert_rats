class_name BaseUI
extends CanvasLayer
## 部屋の変更の画面。Rキーか、右の「部屋の変更 (R)」ボタン（建設・製作の画面からも開ける）。Bキーは建設・製作の画面に譲った。
## 車体そのものの区画（上階・左右／下階・左右）を、どの部屋にするかを決める（空き → 建てる → 別の部屋へ建て替える）。
## 設備（ワークベンチ・ベッド）を部屋の中に足す「建設」（ui/build_ui.gd）とは別。見た目は検証用で、後で変える前提。
## 左: 車体の断面図（区画を押して選ぶ。変更はすぐ絵に出る）と、部屋の効果・区画の一覧。右: 選んだ区画に建てられる部屋の一覧。
## 部屋は「建てる」で入れ替わる（材料は倉庫から）。加工設備・倉庫・ワークベンチ・ベッドの位置も部屋に合わせて移る。

var game
var _slot := "u1"              # 選択中の区画
var _overlay: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _timer := 0.0

const C_TEXT := UIKit.C_TEXT
const C_DIM := UIKit.C_DIM
const C_ACCENT := UIKit.C_ACCENT
const C_OK := Color("86efac")
const C_BAD := Color("f87171")
const HULL_SCALE := 2                 # 断面図の拡大（論理ユニット1つを何pxで描くか）


func _ready() -> void:
	layer = 24
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 12
	add_child(btn_layer)
	var btn := UIKit.button("部屋の変更 (R)", toggle)
	btn.position = Vector2(1000, 398)
	btn.custom_minimum_size = Vector2(272, 32)
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
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("1b1e24", 0.98), Color("636b7a"), 4, 12))
	panel.position = Vector2(60, 18)
	panel.custom_minimum_size = Vector2(1160, 672)
	_overlay.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var title := UIKit.lbl("部屋の変更（車体の区画を、どの部屋にするか）", 22, C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.button("建設・製作へ (B)", func():
		close()
		game.build_ui.open()))
	top.add_child(UIKit.button("閉じる (R / Esc)", close))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(380, 0)
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
		open()


func open() -> void:
	game.close_other_panels(self)
	_overlay.visible = true
	_rebuild()


func close() -> void:
	_overlay.visible = false


func is_open() -> bool:
	return _overlay.visible


## 画面で選んでいる区画を変える（画面の操作と同じ。確認用にも使う）
func select_slot(s: String) -> void:
	_slot = s
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
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
	UIKit.clear(node)


func _lbl(text: String, size: int = 15, color: Color = C_TEXT, minw: float = 0.0) -> Label:
	return UIKit.lbl(text, size, color, minw)


## 幅に収まるよう折り返す説明文（長い文が画面の外へ広がらないように）
func _note(text: String, size: int = 12, color: Color = C_DIM, minw: float = 320.0) -> Label:
	var l := _lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(minw, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _select_slot(s: String) -> void:
	select_slot(s)


func _rebuild() -> void:
	if game == null:
		return
	_rebuild_left()
	_rebuild_right()


func _rebuild_left() -> void:
	_clear(_left)
	_left.add_child(_lbl("── 車体（区画を押して選ぶ） ──", 14, C_DIM))
	_left.add_child(_hull_view())
	var fx := _fx_text()
	_left.add_child(_note(fx if fx != "" else "部屋の効果: なし", 13))
	_left.add_child(_lbl("── 区画の一覧 ──", 14, C_DIM))
	_left.add_child(_lbl("上の階", 13, C_DIM))
	_left.add_child(_slot_row(["u1", "u2"], Rooms.FIXED[0]["name"]))
	_left.add_child(_lbl("下の階", 13, C_DIM))
	_left.add_child(_slot_row(["l1", "l2"], Rooms.FIXED[1]["name"]))
	_left.add_child(_note("操縦室・搬入口は入れ替えできません。加工室・寝室・倉庫・機関室は拠点に1つだけ。"
			+ "別の区画に建てると移設になり、中の設備も一緒に動きます（元の区画は空き部屋）。"))
	_left.add_child(_note("加工室・寝室・倉庫は、なくせません。機関室は壊せます（燃料は搬入口で補給）。"))
	_left.add_child(_note("ワークベンチ・ベッドは、この画面ではなく「建設・製作 (B)」で部屋の中に建てます。"))


## 車体の断面図（車体の絵に、区画ごとの部屋の絵を重ねたもの。ゲーム画面と同じ絵）。区画の上を押すと、その区画を選ぶ。
## 選んでいる区画は枠で囲む。部屋を建てると、次の更新でここの絵も変わる。
func _hull_view() -> Control:
	var hull := GameData.tex("res://assets/base/hull.png")
	var sc := float(HULL_SCALE)                                     # 論理ユニット1つを画面の何pxで描くか（絵の細かさとは関係がない）
	var hull_units := Vector2(ArtSpec.HULL)
	var view := Control.new()
	view.custom_minimum_size = hull_units * sc
	view.clip_contents = true
	view.add_child(_tex_rect(hull, Vector2.ZERO, hull_units * sc))
	for s in Rooms.SLOT_ORDER:
		var rt: String = game.room_layout.get(s, "empty")
		var r: Rect2 = Rooms.overlay_rect(s)
		var pos: Vector2 = (r.position - GameData.HULL_POS) / float(Rooms.UNIT) * sc
		var size: Vector2 = r.size / float(Rooms.UNIT) * sc
		view.add_child(_tex_rect(GameData.tex(Rooms.overlay_path(s, rt)), pos, size))
		var b := Button.new()                                       # 区画の上の透明なボタン（枠は選択中だけ）
		b.position = pos
		b.size = size
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s: %s" % [Rooms.SLOTS[s]["name"], Rooms.TYPES[rt]["name"]]
		var clear := StyleBoxEmpty.new()
		b.add_theme_stylebox_override("normal", clear)
		b.add_theme_stylebox_override("pressed", clear)
		b.add_theme_stylebox_override("disabled", clear)
		var hover := UIKit.box(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.5), 2, 0)
		b.add_theme_stylebox_override("hover", hover)
		b.pressed.connect(func(): _select_slot(s))
		view.add_child(b)
		if s == _slot:
			var frame := Panel.new()
			frame.position = pos
			frame.size = size
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0), C_ACCENT, 3, 0))
			view.add_child(frame)
	return view


func _tex_rect(tex: Texture2D, pos: Vector2, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.position = pos
	t.size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


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
		var b := UIKit.button("%s\n%s" % [Rooms.SLOTS[s]["name"], Rooms.TYPES[rt]["name"]], func(): _select_slot(s))
		b.custom_minimum_size = Vector2(112, 54)
		UIKit.style(b, s == _slot)
		row.add_child(b)
	var fb := UIKit.button("\n%s\n(固定)" % fixed_name, func(): pass)
	fb.custom_minimum_size = Vector2(112, 54)
	fb.disabled = true
	row.add_child(fb)
	return row


func _rebuild_right() -> void:
	_clear(_right)
	var cur: String = game.room_layout.get(_slot, "empty")
	_right.add_child(_lbl("%s の部屋を変える（今: %s）" % [Rooms.SLOTS[_slot]["name"], Rooms.TYPES[cur]["name"]], 17, C_ACCENT))
	var inside := _inside_text(cur)
	if inside != "":
		_right.add_child(_note(inside, 13, C_DIM, 560.0))
	for t in Rooms.TYPE_ORDER:
		if Rooms.can_place(t, _slot):
			_right.add_child(_type_row(t, cur))


## いまの部屋の中にある物（建設した設備。部屋を移すと一緒に動く）
func _inside_text(rtype: String) -> String:
	var parts: Array = []
	if rtype == "workshop":
		parts.append("加工設備")
	if rtype == "storage":
		parts.append("倉庫の棚")
	for id in FacilityDB.ids():
		if FacilityDB.room_of(id) == rtype and game.base.facility_count(id) > 0:
			parts.append("%s×%d" % [FacilityDB.name_of(id), game.base.facility_count(id)])
	return "この部屋にある物: " + "、".join(PackedStringArray(parts)) if not parts.is_empty() else ""


func _type_row(t: String, cur: String) -> Control:
	var info: Dictionary = Rooms.TYPES[t]
	var is_cur := t == cur
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UIKit.box(Color("23262d"), C_ACCENT if is_cur else Color("3a3f4a"), 3 if is_cur else 2, 8))
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
	pv.custom_minimum_size = Rooms.slot_size(_slot) * 2.0        # この区画の大きさ（ユニット）×2。絵の細かさに依存しない
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
	var label := "現在の部屋" if is_cur else ("壊して空ける" if t == "empty" else ("移設する" if reloc else "建てる"))
	var b := UIKit.button(label, func():
		game.build_room(_slot, t)
		_rebuild())
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(120, 40)
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
