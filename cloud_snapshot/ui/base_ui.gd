class_name BaseUI
extends CanvasLayer
## 部屋の管理。車内クリックで区画を直接開き、Rキーでは車体全体を選べる。
## 部屋の建設・解体と、B画面で行う設備の設置・梱包は別の操作。

var game
var _slot := "u1"              # 選択中の区画
var _overlay: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _timer := 0.0
var _panel: PanelContainer
var _title: Label
var _interior := false
var _pending: Dictionary = {}
var _feedback := ""
var _last_view := []

const C_TEXT := UIKit.C_TEXT
const C_DIM := UIKit.C_DIM
const C_ACCENT := UIKit.C_ACCENT
const C_OK := Color("86efac")
const C_BAD := Color("f87171")
const HULL_SCALE := 1.45                 # 断面図の拡大（論理ユニット1つを何pxで描くか）


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
	_panel = panel
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
	_title = title
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
	_open(false)


func open_interior(slot: String) -> void:
	if not Rooms.SLOTS.has(slot):
		return
	_slot = slot
	_open(true)


func _open(interior: bool) -> void:
	game.close_other_panels(self)
	_interior = interior
	_left.visible = not interior
	_title.text = "車内の部屋" if interior else "部屋の変更"
	_panel.position = Vector2(270 if interior else 60, 18)
	_panel.custom_minimum_size = Vector2(740 if interior else 1160, 672)
	_panel.size = _panel.custom_minimum_size
	_feedback = ""
	_pending.clear()
	_overlay.visible = true
	_rebuild()


func close() -> void:
	_pending.clear()
	_overlay.visible = false


func is_open() -> bool:
	return _overlay.visible


## 画面で選んでいる区画を変える（画面の操作と同じ。確認用にも使う）
func select_slot(s: String) -> void:
	if not Rooms.SLOTS.has(s):
		return
	_slot = s
	_pending.clear()
	_feedback = ""
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
		if _timer <= 0.0 and _pending.is_empty() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_timer = 0.4
			if _view_state() != _last_view:
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
	_last_view = _view_state()
	if not _interior:
		_rebuild_left()
	_rebuild_right()


func _view_state() -> Array:
	var current: String = game.room_layout[_slot]
	var state := [game.room_layout.duplicate(), _inside_text(current), _room_status(current), _pack_notes(current), _fx_text()]
	for t in Rooms.TYPE_ORDER:
		state.append(game.room_block_reason(_slot, t))
		for item in Rooms.TYPES[t]["cost"]:
			state.append(game.warehouse_stock_row(item).usable)
	return state


func _rebuild_left() -> void:
	_clear(_left)
	_left.add_child(_lbl("── 車体（区画を押して選ぶ） ──", 14, C_DIM))
	_left.add_child(_hull_view())
	var fx := _fx_text()
	_left.add_child(_note(fx if fx != "" else "部屋の効果: なし", 13))
	_left.add_child(_lbl("── 区画の一覧 ──", 14, C_DIM))
	_left.add_child(_lbl("上の階", 13, C_DIM))
	_left.add_child(_slot_row(["u3", "u1", "u2"], Rooms.FIXED[0]["name"]))
	_left.add_child(_lbl("下の階", 13, C_DIM))
	_left.add_child(_slot_row(["l3", "l1", "l2"], Rooms.FIXED[1]["name"]))
	_left.add_child(_note("操縦室・搬入口は入れ替えできません。加工室・寝室・倉庫・機関室は拠点に1つだけ。"
			+ "別の区画に建てると移設になり、中の設備も一緒に動きます（元の区画は空き部屋）。"))
	_left.add_child(_note("小型拠点は内蔵エンジン。可変6区画、初期の空きは3室。機関室なしでも搬入口で補給・整備できます。加工室・寝室・倉庫は必須です。"))
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
		parts.append("疲労度の蓄積 -%d%%" % int(round(drain * 100.0)))
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
		b.custom_minimum_size = Vector2(86, 54)
		UIKit.style(b, s == _slot)
		row.add_child(b)
	var fb := UIKit.button("\n%s\n(固定)" % fixed_name, func(): pass)
	fb.custom_minimum_size = Vector2(86, 54)
	fb.disabled = true
	row.add_child(fb)
	return row


func _rebuild_right() -> void:
	_clear(_right)
	var cur: String = game.room_layout.get(_slot, "empty")
	_right.add_child(_lbl("%s · %s" % [Rooms.SLOTS[_slot]["name"], Rooms.TYPES[cur]["name"]], 19, C_ACCENT))
	if not _feedback.is_empty():
		_right.add_child(_note(_feedback, 14, C_ACCENT))
	if not _pending.is_empty():
		_show_confirmation(cur)
		return
	if cur != "empty":
		_right.add_child(_note(_room_status(cur), 15))
		_right.add_child(_note(Rooms.effect_text(cur), 15, C_TEXT))
		var inside := _inside_text(cur)
		_right.add_child(_note(inside if not inside.is_empty() else "設置設備: なし", 14))
		for note in _pack_notes(cur):
			_right.add_child(_note(note, 13, C_BAD))
		var why: String = game.room_block_reason(_slot, "empty")
		var dismantle := UIKit.button("解体…", func(): _preview("empty"))
		dismantle.disabled = not why.is_empty()
		_right.add_child(dismantle)
		if not why.is_empty():
			_right.add_child(_note(why, 14, C_BAD))
		if _interior:
			return
	var later := []
	for t in Rooms.TYPE_ORDER:
		if t == "empty" or t == cur:
			continue
		if _interior and (not Rooms.can_place(t, _slot) or Rooms.is_relocation(game.room_layout, _slot, t)):
			later.append(t)
		else:
			_right.add_child(_type_row(t))
	for t in later:
		_right.add_child(_type_row(t))


func _pack_notes(rtype: String) -> Array[String]:
	var notes: Array[String] = []
	for id in FacilityDB.ids():
		if FacilityDB.room_of(id) != rtype:
			continue
		for index in game.base.built.get(id, []):
			var why: String = game.facility_pack_reason(id, index)
			if not why.is_empty():
				notes.append("%sの撤去: %s" % [FacilityDB.name_of(id), why])
	return notes


func _room_status(rtype: String) -> String:
	match rtype:
		"workshop":
			if not game.processor.active_recipes().is_empty():
				return "稼働状態: 加工中"
			return "稼働状態: 作業待ち"
		"bedroom":
			var occupied := 0
			for worker in game.base.beds:
				if is_instance_valid(worker):
					occupied += 1
			return "稼働状態: 使用・予約中のベッド %d" % occupied
		"engine":
			return "稼働状態: 補給・修理中" if game.base.refuel_reserved or game.base.repair_reserved.has(GameData.Part.DRIVE) else "稼働状態: 補給・整備に利用可能"
		"training":
			return "稼働状態: 訓練機能は未実装"
	return "稼働状態: 有効"


func _preview(target: String) -> void:
	if not is_open() or not game.can_build_room(_slot, target):
		return
	_pending = {"slot": _slot, "target": target, "current": game.room_layout[_slot],
		"source": Rooms.slot_of(game.room_layout, target) if Rooms.TYPES[target]["unique"] else ""}
	_feedback = ""
	_rebuild()


func _cancel_preview() -> void:
	_pending.clear()
	_rebuild()


func _confirm_preview() -> void:
	if not is_open() or _pending.is_empty():
		return
	var change := _pending
	_pending = {}
	var target: String = change.target
	var source := Rooms.slot_of(game.room_layout, target) if Rooms.TYPES[target]["unique"] else ""
	if _slot != change.slot or game.room_layout[_slot] != change.current or source != change.source:
		_feedback = "区画の状態が変わりました。選び直してください。"
	else:
		var why: String = game.room_block_reason(_slot, target)
		if why.is_empty() and game.build_room(_slot, target):
			_feedback = "解体しました" if target == "empty" else "%sを設置しました" % Rooms.TYPES[target]["name"]
		else:
			_feedback = why if not why.is_empty() else "変更できませんでした。"
	_rebuild()


func _show_confirmation(cur: String) -> void:
	var target: String = _pending.target
	if cur != "empty":
		_right.add_child(_note("失う機能・効果　" + Rooms.effect_text(cur), 15, C_TEXT))
		_right.add_child(_note("返却: なし。設備の梱包は建設・製作 (B) で行います。", 14))
	if target != "empty":
		var title := "建設" if _pending.source.is_empty() else "移設（中の設備も移動）"
		_right.add_child(_note("%s　%s" % [title, Rooms.TYPES[target]["name"]], 16, C_TEXT))
		_right.add_child(_cost_row(Rooms.TYPES[target]["cost"]))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_right.add_child(actions)
	var action := "建設を確定" if _pending.source.is_empty() else "移設を確定"
	actions.add_child(UIKit.button("解体を確定" if target == "empty" else action, _confirm_preview))
	actions.add_child(UIKit.button("取り消す", _cancel_preview))


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


func _type_row(t: String) -> Control:
	var info: Dictionary = Rooms.TYPES[t]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UIKit.box(Color("23262d"), Color("3a3f4a"), 2, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	# 部屋の見た目（この区画に置いたときの絵を2倍で）
	var tex: Texture2D = GameData.tex(Rooms.overlay_path(_slot, t)) if Rooms.can_place(t, _slot) else null
	var pv := TextureRect.new()
	pv.texture = tex
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_SCALE
	pv.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv.custom_minimum_size = Rooms.slot_size(_slot) * (1.6 if _interior else 2.0)        # この区画の大きさ（ユニット）×2。絵の細かさに依存しない
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pv)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(160, 0)
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	v.add_child(_lbl(info["name"], 17, C_TEXT))
	v.add_child(_note(info["desc"], 13, C_DIM, 160.0))
	v.add_child(_cost_row(info["cost"]))
	var why: String = game.room_block_reason(_slot, t)
	if not why.is_empty():
		v.add_child(_note(why, 13, C_BAD, 160.0))
	# 建てるボタン
	var reloc: bool = Rooms.is_relocation(game.room_layout, _slot, t)
	var label := "移設…" if reloc else "建設…"
	var b := UIKit.button(label, func(): _preview(t))
	b.name = "RoomChoice_" + t
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(120, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not why.is_empty()
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
		var have: int = game.warehouse_stock_row(it).usable
		var ok: bool = have >= int(cost[it])
		row.add_child(_lbl("%s×%d（使用可%d）" % [GameData.ITEM_NAMES[it], cost[it], have], 13, C_OK if ok else C_BAD))
	return row
