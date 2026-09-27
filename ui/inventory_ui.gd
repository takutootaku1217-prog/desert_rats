class_name InventoryUI
extends CanvasLayer
## インベントリの画面（Tab キーまたは右の「インベントリ (Tab)」ボタン）。アイテムを、数字ではなく「物」として見せる。
##  - 左: アイテムの一覧（アイコン・名前・分類の札・数量）。倉庫 ⇄ 作業場を切り替える（別の置き場。運ぶまで材料は移らない）。
##  - 右: 選んだアイテムの詳細（入手先・使い道のアイコン・数量の選び方）と、操作（運搬の依頼・分割）。運搬は仲間が行う（運搬の依頼）。
##  - 下: [制作]（制作の画面へ）と [整理]（同じアイテムをまとめて並べ直す）。
## 一覧は「束」（scripts/item_stack.gd）で並び、同じアイテムを分割して2つ以上の束にできる（木材 ×20 → ×12 と ×8）。分割は画面上の並びで、
## 倉庫・作業場の数量そのものは変えない（選んだ束の数だけを運べる）。数量の正は倉庫（BaseStorage.inventory）と作業場（BaseProcessor.stock）。
## 文字は増やさず、アイコン・色・数量で見せる（分類は色の札）。見た目は仮で、素材（絵）を差し替えられる。

var game
var _overlay: Control
var _tab := 0                                   # 0 = 倉庫、1 = 作業場
var _tab_btns: Array = []
var _models := [InventoryModel.new(), InventoryModel.new()]
var _sel := -1                                  # 選んでいる束の番号（いまの置き場の並びの中）
var _list: VBoxContainer
var _detail: VBoxContainer
var _sig := ""
var _t := 0.0
var _qty_val := 1                               # 数量の選び方の値（束を選び直すまで保つ）
var _qty: QtyPicker
var _split_box: HBoxContainer
var _split_qty: QtyPicker
var _move_btn: Button
var _split_btn: Button
var _msg: Label
var _msg_text := ""                             # 操作の結果の一言（画面が作り直されても残す）

const TAB_NAMES := ["倉庫", "作業場"]
const C_SEL := Color("f2c14e")


func _ready() -> void:
	layer = 25
	# 右のボタンは低い層に置く（ほかの画面を開いたとき、その下に隠れるように）
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 12
	add_child(btn_layer)
	var btn := UIKit.button("インベントリ (Tab)", toggle)
	btn.position = Vector2(1000, 434)
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
	panel.position = Vector2(40, 18)
	panel.custom_minimum_size = Vector2(1200, 660)
	_overlay.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UIKit.lbl("インベントリ", 22, UIKit.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.button("閉じる (Tab / Esc)", close))
	# 置き場の切り替え
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	for i in TAB_NAMES.size():
		var idx := i
		var tb := UIKit.button(TAB_NAMES[i], func(): _set_tab(idx))
		tb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.custom_minimum_size = Vector2(150, 34)
		tabs.add_child(tb)
		_tab_btns.append(tb)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	# 左: 一覧と、下のボタン
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(600, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(600, 500)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	left.add_child(bottom)
	var b_craft := UIKit.button("制作", func(): game.craft_ui.open())
	b_craft.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_craft.custom_minimum_size = Vector2(150, 36)
	bottom.add_child(b_craft)
	var b_sort := UIKit.button("整理", _sort)
	b_sort.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_sort.custom_minimum_size = Vector2(150, 36)
	b_sort.tooltip_text = "同じアイテムを1つにまとめて、並べ直す"
	bottom.add_child(b_sort)
	# 右: 詳細
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	cols.add_child(_detail)


# ---------------------------------------------------------------- 開閉
func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		open()


func open() -> void:
	game.close_other_panels(self)
	_overlay.visible = true
	_refresh(true)


func close() -> void:
	_overlay.visible = false


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle()
		elif event.keycode == KEY_ESCAPE and _overlay.visible:
			close()


func _process(delta: float) -> void:
	if not _overlay.visible:
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		_refresh()


# ---------------------------------------------------------------- 状態
func _model() -> InventoryModel:
	return _models[_tab]


func _counts() -> Dictionary:
	return game.storage.inventory.counts if _tab == 0 else game.processor.stock.counts


func _set_tab(t: int) -> void:
	_tab = t
	_sel = -1
	_msg_clear()
	_refresh(true)


## 選んでいる束（なければ null）
func selected_stack() -> ItemStack:
	var m := _model()
	return m.stacks[_sel] if _sel >= 0 and _sel < m.stacks.size() else null


func _select(i: int) -> void:
	if i != _sel:
		_qty_val = 1
	_sel = i
	_msg_clear()
	_refresh(true)


func _msg_clear() -> void:
	_msg_text = ""
	if _msg != null:
		_msg.text = ""


func _sort() -> void:
	var keep := selected_stack()
	_model().merge_all()
	_sel = -1
	if keep != null:
		for i in _model().stacks.size():
			if _model().stacks[i].item == keep.item:
				_sel = i
				break
	_refresh(true)
	_say("整理した（同じアイテムをまとめて並べ直した）")


## 一覧・詳細を作り直す必要があるかの目印（数量・選択・置き場・運搬の依頼が変わったら変わる）
func _signature() -> String:
	var parts: Array = ["%d|%d" % [_tab, _sel]]
	for s in _model().stacks:
		parts.append("%d:%d" % [s.item, s.n])
	if _tab == 1:
		var ci: Dictionary = game.processor.committed_inputs()
		for it in ci:
			parts.append("c%d:%d" % [it, ci[it]])
	for t in game.transfer_queue:
		parts.append("t%d:%d:%s" % [t["item"], t["n"], t["dir"]])
	return ",".join(PackedStringArray(parts))


func _refresh(force := false) -> void:
	if game == null or game.storage == null:
		return
	for i in _tab_btns.size():
		UIKit.style(_tab_btns[i], i == _tab)
	var m := _model()
	m.sync(_counts())
	if _sel >= m.stacks.size():
		_sel = m.stacks.size() - 1
	if _sel < 0 and not m.stacks.is_empty():
		_sel = 0
	var sig := _signature()
	if force or sig != _sig:
		_sig = sig
		_rebuild_list()
		_rebuild_detail()
	_update_dynamic()


# ---------------------------------------------------------------- 一覧（左）
func _rebuild_list() -> void:
	UIKit.clear(_list)
	var m := _model()
	if m.stacks.is_empty():
		var empty := UIKit.lbl("何もない", 16, UIKit.C_DIM)
		_list.add_child(empty)
	for i in m.stacks.size():
		_list.add_child(_make_row(m.stacks[i], i, i == _sel))
	if _tab == 1:
		var ci: Dictionary = game.processor.committed_inputs()
		if not ci.is_empty():
			var head := UIKit.lbl("加工待ち（注文に割り当て済み）", 13, UIKit.C_DIM)
			_list.add_child(head)
			for it in ItemDB.all():
				if ci.has(it):
					_list.add_child(_make_static_row(int(it), int(ci[it])))


func _make_row(s: ItemStack, index: int, selected: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.box(Color("2a3140") if selected else Color("23272f"), C_SEL if selected else Color("3a3f4a"), 3 if selected else 2, 4))
	row.tooltip_text = "%s ×%d（%s）" % [ItemDB.name_of(s.item), s.n, ItemDB.category_of(s.item)]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	h.add_child(ItemWidgets.icon(s.item, 48.0))
	var nm := UIKit.lbl(ItemDB.name_of(s.item), 20, UIKit.C_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var chip := ItemWidgets.chip(ItemDB.category_of(s.item), ItemDB.color_of(s.item))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	var cnt := UIKit.lbl("×%d" % s.n, 22, Color("fff7dc"), 80)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cnt)
	var idx := index
	row.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(idx))
	return row


## 作業場の「加工待ち」の材料（見るだけ。選べない）
func _make_static_row(item: int, n: int) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.box(Color("1c1f25"), Color("2f343d"), 2, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var ic := ItemWidgets.icon(item, 24.0)
	ic.modulate = Color(1, 1, 1, 0.55)
	h.add_child(ic)
	var nm := UIKit.lbl(ItemDB.name_of(item), 15, UIKit.C_DIM)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	h.add_child(UIKit.lbl("×%d" % n, 16, UIKit.C_DIM))
	return row


# ---------------------------------------------------------------- 詳細（右）
func _rebuild_detail() -> void:
	UIKit.clear(_detail)
	_qty = null
	_split_box = null
	_move_btn = null
	_split_btn = null
	_msg = null
	var s := selected_stack()
	if s == null:
		_detail.add_child(UIKit.lbl("左の一覧から、アイテムを選んでください", 16, UIKit.C_DIM))
		_msg = UIKit.lbl(_msg_text, 14, UIKit.C_ACCENT)
		_detail.add_child(_msg)
		_add_queue_box()
		return
	# 見出し: 大きな絵・名前・分類の札
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_detail.add_child(head)
	head.add_child(ItemWidgets.icon_frame(s.item, 96.0))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	head.add_child(hv)
	hv.add_child(UIKit.lbl(ItemDB.name_of(s.item), 26, UIKit.C_ACCENT))
	var hc := HBoxContainer.new()
	hc.add_theme_constant_override("separation", 6)
	hv.add_child(hc)
	hc.add_child(ItemWidgets.chip(ItemDB.category_of(s.item), ItemDB.color_of(s.item), 13))
	for src in ItemDB.sources_of(s.item):
		hc.add_child(ItemWidgets.chip(String(src), Color("6f7a8c"), 12))
	# 持っている数（両方の置き場。どちらにどれだけあるかが分かる）
	var own := HBoxContainer.new()
	own.add_theme_constant_override("separation", 14)
	hv.add_child(own)
	own.add_child(UIKit.lbl("倉庫 ×%d" % game.storage.count_of(s.item), 16, UIKit.C_TEXT if _tab == 0 else UIKit.C_DIM))
	own.add_child(UIKit.lbl("作業場 ×%d" % game.workshop_count(s.item), 16, UIKit.C_TEXT if _tab == 1 else UIKit.C_DIM))
	# 使い道（作れる物のアイコン）
	var uses := ItemDB.uses_of(s.item)
	if not uses.is_empty():
		_detail.add_child(UIKit.lbl("使い道", 13, UIKit.C_DIM))
		var ur := HFlowContainer.new()
		ur.add_theme_constant_override("h_separation", 6)
		ur.add_theme_constant_override("v_separation", 6)
		_detail.add_child(ur)
		var seen := {}
		for u in uses:
			var key := "%d:%s" % [int(u["out"]), String(u["id"]) if int(u["out"]) < 0 else ""]
			if seen.has(key):
				continue
			seen[key] = true
			if int(u["out"]) >= 0:
				var f := ItemWidgets.icon_frame(int(u["out"]), 24.0)
				f.tooltip_text = String(u["name"])
				ur.add_child(f)
			else:
				var c := ItemWidgets.chip("建設", Color("8a90a0"), 12)
				c.tooltip_text = String(u["name"])
				ur.add_child(c)
	# 数量の選び方と操作
	_detail.add_child(UIKit.lbl("数量", 13, UIKit.C_DIM))
	_qty = QtyPicker.new().setup([1, 5, -1])
	_qty.set_max(s.n)
	_qty.set_value(_qty_val, false)
	_qty.changed.connect(func(v): _qty_val = v)
	_detail.add_child(_qty)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	_detail.add_child(acts)
	_move_btn = UIKit.button("作業場へ運ぶ" if _tab == 0 else "倉庫へ戻す", _move)
	_move_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_move_btn.custom_minimum_size = Vector2(190, 36)
	_move_btn.tooltip_text = "仲間が運ぶ（運搬の仕事）。選んだ数だけ"
	acts.add_child(_move_btn)
	_split_btn = UIKit.button("分割", func():
		if _split_box != null:
			_split_box.visible = not _split_box.visible
			if _split_box.visible:
				var cur := selected_stack()
				_split_qty.set_max(maxi(1, cur.n - 1))
				_split_qty.set_value(maxi(1, cur.n / 2), false))
	_split_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_split_btn.custom_minimum_size = Vector2(110, 36)
	_split_btn.tooltip_text = "束を2つに分ける"
	acts.add_child(_split_btn)
	# 分割の数量（開いたときだけ出る）
	_split_box = HBoxContainer.new()
	_split_box.add_theme_constant_override("separation", 8)
	_split_box.visible = false
	_detail.add_child(_split_box)
	_split_box.add_child(UIKit.lbl("分ける数", 13, UIKit.C_DIM))
	_split_qty = QtyPicker.new().setup([1, 5])
	_split_box.add_child(_split_qty)
	var ok := UIKit.button("決定", _do_split)
	ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ok.custom_minimum_size = Vector2(80, 30)
	_split_box.add_child(ok)
	_msg = UIKit.lbl(_msg_text, 14, UIKit.C_ACCENT)
	_msg.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_msg.custom_minimum_size = Vector2(480, 0)
	_detail.add_child(_msg)
	_add_queue_box()


## 運搬の依頼（いま待っている運搬）。アイコンと数で見せる
func _add_queue_box() -> void:
	if game.transfer_queue.is_empty():
		return
	_detail.add_child(UIKit.lbl("運搬の依頼（仲間が運ぶ）", 13, UIKit.C_DIM))
	var qb := HFlowContainer.new()
	qb.add_theme_constant_override("h_separation", 10)
	qb.add_theme_constant_override("v_separation", 6)
	_detail.add_child(qb)
	for t in game.transfer_queue:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		qb.add_child(h)
		h.add_child(ItemWidgets.icon_frame(int(t["item"]), 24.0))
		h.add_child(UIKit.lbl("×%d" % int(t["n"]), 15, UIKit.C_TEXT))
		h.add_child(UIKit.lbl("→ 作業場" if t["dir"] == "to_workshop" else "→ 倉庫", 13, UIKit.C_DIM))
	if game.transfer_worker != null:
		_detail.add_child(UIKit.lbl("%s が運んでいる" % game.transfer_worker.char_name, 13, UIKit.C_DIM))
	var cancel := UIKit.button("依頼を取り消す", func():
		game.cancel_transfers()
		_refresh(true))
	cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel.custom_minimum_size = Vector2(160, 30)
	_detail.add_child(cancel)


## 数量・ボタンの有効／無効を、毎回の更新で合わせる（押している最中に作り直さない）
func _update_dynamic() -> void:
	var s := selected_stack()
	if s == null or _qty == null:
		return
	_qty.set_max(s.n)
	if _move_btn != null:
		_move_btn.disabled = _qty.value < 1
	if _split_btn != null:
		_split_btn.disabled = s.n < 2
		if s.n < 2 and _split_box != null:
			_split_box.visible = false


func _say(text: String) -> void:
	_msg_text = text
	if _msg != null:
		_msg.text = text


# ---------------------------------------------------------------- 操作
## 選んだ数を、運搬の依頼にする（倉庫 → 作業場、または 作業場 → 倉庫）
func _move() -> void:
	var s := selected_stack()
	if s == null:
		return
	var dir := "to_workshop" if _tab == 0 else "to_storage"
	var got: int = game.request_transfer(s.item, mini(_qty.value, s.n), dir)
	var name := ItemDB.name_of(s.item)
	_refresh(true)
	if got > 0:
		_say("運搬を頼んだ: %s ×%d → %s（仲間が運ぶ）" % [name, got, "作業場" if dir == "to_workshop" else "倉庫"])
	else:
		_say("これ以上は頼めない（すでに頼んだ分・行き先の空き・元にない）")


func _do_split() -> void:
	var s := selected_stack()
	if s == null or _split_qty == null:
		return
	var n := _split_qty.value
	var before := s.n
	if _model().split(_sel, n):
		_split_box.visible = false
		_refresh(true)
		_say("%s ×%d を ×%d と ×%d に分けた" % [ItemDB.name_of(s.item), before, before - n, n])
	else:
		_say("その数では分けられない")
