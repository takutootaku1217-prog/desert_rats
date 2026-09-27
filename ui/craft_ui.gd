class_name CraftUI
extends CanvasLayer
## 制作の画面（F キーまたは右の「制作 (F)」ボタン。インベントリの［制作］からも開く）。ARK のエングラムのように、
## 「いま作れる物」だけでなく「まだ作れない物」も一覧で見られる。作れる／作れないは、文字ではなく、色・印（✓ × 鍵）・アイコンの明暗で一瞬で分かる。
##  - 上: 分類の切り替え（道具・建設・料理・加工…。エントリのある分類だけ。data/crafting.gd）。
##  - 左: その分類の制作の一覧（作る物のアイコン・名前・状態の札）。
##  - 右: 選んだ物の詳細。必要な材料を「いまある数 / 必要な数」と印で見せる（足りない材料は赤く、アイコンが暗くなる）。
##       数量（1回・5回・全部）を選んで［制作］。足りないときは、倉庫にあるか（［素材を運ぶ］で作業場へ）・倉庫にも足りないかを示す。
##       まだ作れない物は、何をすれば解放されるか（必要な設備の建設）を示す。
## 加工の材料は「作業場」にある分だけを使う（倉庫から運ぶまで使えない）。建設は、これまでの建設の依頼（材料は仲間が倉庫から自動で運ぶ）。
## 表の中身は data/crafting.gd（CraftDB）。レシピそのものは GameData.RECIPES と FacilityDB のまま。見た目は仮で、素材（絵）を差し替えられる。

var game
var _overlay: Control
var _cat := ""                                  # 選んでいる分類
var _key := ""                                  # 選んでいる制作（CraftDB のエントリの key）
var _cat_row: HBoxContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _sig := ""
var _t := 0.0
var _qty: QtyPicker
var _qty_val := 1
var _craft_btn: Button
var _carry_btn: Button
var _msg: Label
var _msg_text := ""

const C_SEL := Color("f2c14e")


func _ready() -> void:
	layer = 26
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 12
	add_child(btn_layer)
	var btn := UIKit.button("制作 (F)", toggle)
	btn.position = Vector2(1000, 470)
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
	var title := UIKit.lbl("制作", 22, UIKit.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.button("インベントリへ (Tab)", func(): game.inventory_ui.open()))
	top.add_child(UIKit.button("閉じる (F / Esc)", close))
	_cat_row = HBoxContainer.new()
	_cat_row.add_theme_constant_override("separation", 6)
	root.add_child(_cat_row)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 540)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(sc)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
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
	if _cat == "":
		var cats := CraftDB.categories_in_use()
		_cat = cats[0] if not cats.is_empty() else ""
	_refresh(true)


## 特定の制作を選んで開く（インベントリの「使い道」などから）
func open_entry(key: String) -> void:
	var e := CraftDB.entry_of(key)
	if not e.is_empty():
		_cat = e["cat"]
		_key = key
	open()


func close() -> void:
	_overlay.visible = false


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
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
func _entries() -> Array:
	return CraftDB.entries_of(_cat)


func selected_entry() -> Dictionary:
	if _key == "":
		return {}
	return CraftDB.entry_of(_key)


func _select_cat(c: String) -> void:
	_cat = c
	_key = ""
	_msg_text = ""
	_refresh(true)


func _select_entry(k: String) -> void:
	if k != _key:
		_qty_val = 1
	_key = k
	_msg_text = ""
	_refresh(true)


func _say(text: String) -> void:
	_msg_text = text
	if _msg != null:
		_msg.text = text


func _refresh(force := false) -> void:
	if game == null or game.storage == null:
		return
	if _cat == "" or not CraftDB.categories_in_use().has(_cat):
		var cats := CraftDB.categories_in_use()
		_cat = cats[0] if not cats.is_empty() else ""
	var es := _entries()
	if selected_entry().is_empty() or selected_entry()["cat"] != _cat:
		_key = es[0]["key"] if not es.is_empty() else ""
	# 目印: 分類・選択・各エントリの状態・選んだ物の材料の数・待ち行列
	var parts: Array = [_cat, _key, str(_qty_val)]
	for e in es:
		var ev: Dictionary = CraftDB.evaluate(e, game, 1)
		parts.append("%s:%s" % [e["key"], ev["state"]])
	var sel := selected_entry()
	if not sel.is_empty():
		var evs: Dictionary = CraftDB.evaluate(sel, game, _qty_val)
		for r in evs["rows"]:
			parts.append("%d/%d/%d" % [r["item"], r["have"], r["in_storage"]])
		parts.append("%d:%d" % [evs["max_qty"], int(evs["state"] == "ok")])
	for q in game.craft_queue:
		parts.append("q%s:%d" % [q["id"], q["n"]])
	for t in game.transfer_queue:
		parts.append("t%d:%d" % [t["item"], t["n"]])
	var sig := ",".join(PackedStringArray(parts))
	if force or sig != _sig:
		_sig = sig
		_rebuild_cats()
		_rebuild_list()
		_rebuild_detail()


func _rebuild_cats() -> void:
	UIKit.clear(_cat_row)
	for c in CraftDB.categories_in_use():
		var cc: String = c
		var b := UIKit.button(cc, func(): _select_cat(cc))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(120, 34)
		UIKit.style(b, cc == _cat)
		_cat_row.add_child(b)


# ---------------------------------------------------------------- 一覧（左）
## エントリの絵（作る物のアイコン。建設は道具の絵で代用する仮）
func _entry_item(e: Dictionary) -> int:
	return int(e["out"]) if int(e["out"]) >= 0 else GameData.Item.HAMMER


func _rebuild_list() -> void:
	UIKit.clear(_list)
	for e in _entries():
		var ev: Dictionary = CraftDB.evaluate(e, game, 1)
		var selected: bool = e["key"] == _key
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIKit.box(Color("2a3140") if selected else Color("23272f"), C_SEL if selected else Color("3a3f4a"), 3 if selected else 2, 4))
		row.tooltip_text = "%s（%s）" % [e["name"], ItemWidgets.state_text(ev["state"])]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var ic := ItemWidgets.icon(_entry_item(e), 48.0)
		if ev["state"] == "locked":
			ic.modulate = Color(1, 1, 1, 0.4)                            # 解放待ちは暗く
		h.add_child(ic)
		var nm := UIKit.lbl(e["name"], 18, UIKit.C_DIM if ev["state"] == "locked" else UIKit.C_TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nm)
		var plate := ItemWidgets.state_plate(ev["state"], 20.0)
		plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(plate)
		var k: String = e["key"]
		row.gui_input.connect(func(evt):
			if evt is InputEventMouseButton and evt.pressed and evt.button_index == MOUSE_BUTTON_LEFT:
				_select_entry(k))
		_list.add_child(row)


# ---------------------------------------------------------------- 詳細（右）
func _rebuild_detail() -> void:
	UIKit.clear(_detail)
	_qty = null
	_craft_btn = null
	_carry_btn = null
	_msg = null
	var e := selected_entry()
	if e.is_empty():
		_detail.add_child(UIKit.lbl("制作できる物がありません", 16, UIKit.C_DIM))
		return
	var is_build: bool = e["kind"] == "build"
	var qty: int = 1 if is_build else _qty_val
	var ev: Dictionary = CraftDB.evaluate(e, game, qty)
	var state: String = ev["state"]
	# 見出し: 作る物の大きな絵・名前・状態の札
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_detail.add_child(head)
	var big := ItemWidgets.icon_frame(_entry_item(e), 96.0)
	if state == "locked":
		big.modulate = Color(1, 1, 1, 0.5)
	head.add_child(big)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	head.add_child(hv)
	hv.add_child(UIKit.lbl(e["name"], 26, UIKit.C_ACCENT))
	var hs := HBoxContainer.new()
	hs.add_theme_constant_override("separation", 8)
	hv.add_child(hs)
	hs.add_child(ItemWidgets.state_plate(state, 24.0))
	var sc: Color = ItemWidgets.STATE_COLORS.get(state, Color.WHITE)
	hs.add_child(UIKit.lbl(ItemWidgets.state_text(state), 16, sc))
	# 作るもの（数）と、作業をする場所
	if not is_build:
		var out := HBoxContainer.new()
		out.add_theme_constant_override("separation", 6)
		hv.add_child(out)
		out.add_child(UIKit.lbl("→", 16, UIKit.C_DIM))
		out.add_child(ItemWidgets.icon_frame(int(e["out"]), 24.0))
		out.add_child(UIKit.lbl("×%d" % (int(e["n"]) * qty), 18, UIKit.C_TEXT))
		out.add_child(ItemWidgets.chip(FacilityDB.name_of(String(e["station"])) if e["station"] != "" else "手作業", Color("6f7a8c"), 12))
	# 解放待ち・不可の理由と、何をすれば解放されるか
	if ev["reason"] != "" and state != "done":
		var rr := HBoxContainer.new()
		rr.add_theme_constant_override("separation", 6)
		_detail.add_child(rr)
		rr.add_child(ItemWidgets.mark("lock" if state == "locked" else "ng", 20.0))
		rr.add_child(UIKit.lbl(String(ev["reason"]), 16, sc))
	if ev["hint"] != "" and state != "ok":
		var hl := UIKit.lbl(String(ev["hint"]), 13, UIKit.C_DIM)
		hl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		hl.custom_minimum_size = Vector2(500, 0)
		_detail.add_child(hl)
	# 必要な材料: いまある数 / 必要な数 と印
	_detail.add_child(UIKit.lbl("必要な材料（%s にある分）" % ev["source"], 13, UIKit.C_DIM))
	for r in ev["rows"]:
		_detail.add_child(_make_req_row(r, state == "locked"))
	# 数量（加工・道具・料理）と操作
	if not is_build and state != "locked":
		_detail.add_child(UIKit.lbl("回数", 13, UIKit.C_DIM))
		_qty = QtyPicker.new().setup([1, 5, -1])
		var top_n: int = maxi(int(ev["max_qty"]), int(ev["max_with_storage"]))                          # 材料が足りなくても、必要な数を見るために、倉庫の分まで選べる
		_qty.set_max(top_n, int(ev["max_qty"]) if int(ev["max_qty"]) > 0 else int(ev["max_with_storage"]))
		_qty.set_value(_qty_val, false)
		_qty_val = _qty.value
		_qty.changed.connect(func(v):
			_qty_val = v
			_refresh(true))
		_detail.add_child(_qty)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	_detail.add_child(acts)
	if is_build:
		_craft_btn = UIKit.button("建設を依頼する", _do_build)
		_craft_btn.disabled = not (state in ["ok", "short"])
	else:
		_craft_btn = UIKit.button("制作", _do_craft)
		_craft_btn.disabled = state != "ok"
	_craft_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_btn.custom_minimum_size = Vector2(190, 38)
	acts.add_child(_craft_btn)
	if not is_build and state != "locked":
		_carry_btn = UIKit.button("素材を運ぶ", _do_carry)
		_carry_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_carry_btn.custom_minimum_size = Vector2(150, 38)
		_carry_btn.disabled = not (state == "short" and ev["can_transfer"])
		_carry_btn.tooltip_text = "足りない材料を、倉庫から作業場へ運ぶ（仲間が運ぶ）"
		acts.add_child(_carry_btn)
	if state == "locked" and String(e["station"]) != "":
		var to_build := UIKit.button("建設の画面へ (B)", func(): game.build_ui.open())
		to_build.alignment = HORIZONTAL_ALIGNMENT_CENTER
		to_build.custom_minimum_size = Vector2(160, 38)
		acts.add_child(to_build)
	_msg = UIKit.lbl(_msg_text, 14, UIKit.C_ACCENT)
	_msg.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_msg.custom_minimum_size = Vector2(500, 0)
	_detail.add_child(_msg)
	_add_queue()


## 材料の1行: アイコン（足りないと暗く）・名前・いまある数 / 必要な数・印（✓ ×）。足りない行は赤く染まる
func _make_req_row(r: Dictionary, locked: bool) -> PanelContainer:
	var ok: bool = r["ok"]
	var row := PanelContainer.new()
	var bg := Color("1f2a22") if ok else Color("32201e")
	var edge := Color("3f6a45") if ok else Color("7a3a34")
	if locked:
		bg = Color("1f2229")
		edge = Color("3a3f4a")
	row.add_theme_stylebox_override("panel", UIKit.box(bg, edge, 2, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var ic := ItemWidgets.icon(int(r["item"]), 48.0)
	if not ok:
		ic.modulate = Color(0.55, 0.55, 0.6, 1.0)                           # 足りない材料のアイコンは暗い
	h.add_child(ic)
	var nm := UIKit.lbl(ItemDB.name_of(int(r["item"])), 18, UIKit.C_TEXT if ok else UIKit.C_DIM)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var have_l := UIKit.lbl("%d / %d" % [r["have"], r["need"]], 20, ItemWidgets.C_OK if ok else ItemWidgets.C_NG, 90)
	have_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	have_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(have_l)
	var mk := ItemWidgets.mark("ok" if ok else "ng", 24.0)
	mk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mk)
	if not ok and int(r["in_storage"]) > 0 and not locked:
		var st := UIKit.lbl("倉庫 %d" % int(r["in_storage"]), 12, UIKit.C_DIM)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(st)
	return row


## 制作の待ちと、運搬の依頼（アイコンと数）
func _add_queue() -> void:
	if not game.craft_queue.is_empty():
		_detail.add_child(UIKit.lbl("制作の待ち", 13, UIKit.C_DIM))
		var qb := HFlowContainer.new()
		qb.add_theme_constant_override("h_separation", 10)
		_detail.add_child(qb)
		for i in game.craft_queue.size():
			var q: Dictionary = game.craft_queue[i]
			var r: Dictionary = GameData.recipe_by_id(q["id"])
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			qb.add_child(h)
			h.add_child(ItemWidgets.icon_frame(int(r["out"]), 24.0))
			h.add_child(UIKit.lbl("×%d回" % int(q["n"]), 14, UIKit.C_TEXT))
			var idx: int = i
			var x := UIKit.button("×", func():
				game.cancel_craft(idx)
				_refresh(true))
			x.alignment = HORIZONTAL_ALIGNMENT_CENTER
			x.custom_minimum_size = Vector2(28, 26)
			x.tooltip_text = "この制作の待ちを取り消す（材料は作業場に残る）"
			h.add_child(x)
	if not game.transfer_queue.is_empty():
		_detail.add_child(UIKit.lbl("運搬の依頼（仲間が運ぶ）", 13, UIKit.C_DIM))
		var tb := HFlowContainer.new()
		tb.add_theme_constant_override("h_separation", 10)
		_detail.add_child(tb)
		for t in game.transfer_queue:
			var th := HBoxContainer.new()
			th.add_theme_constant_override("separation", 4)
			tb.add_child(th)
			th.add_child(ItemWidgets.icon_frame(int(t["item"]), 24.0))
			th.add_child(UIKit.lbl("×%d" % int(t["n"]), 14, UIKit.C_TEXT))


# ---------------------------------------------------------------- 操作
func _do_craft() -> void:
	var e := selected_entry()
	if e.is_empty():
		return
	var got: int = game.request_craft(e["id"], _qty_val)
	_refresh(true)
	if got > 0:
		_say("制作を頼んだ: %s ×%d回（作業場の材料で、加工設備が作る）" % [e["name"], got])
	else:
		_say("頼めない（材料・置き場・必要設備を確認）")


func _do_build() -> void:
	var e := selected_entry()
	if e.is_empty():
		return
	var ok: bool = game.request_build(e["id"])
	_refresh(true)
	_say("建設を依頼した（仲間が材料を運んで作る）" if ok else "いまは依頼できない")


## 足りない材料を、倉庫から作業場へ運ぶ依頼にする
func _do_carry() -> void:
	var e := selected_entry()
	if e.is_empty():
		return
	var ev: Dictionary = CraftDB.evaluate(e, game, _qty_val)
	var total := 0
	for it in ev["missing"]:
		total += game.request_transfer(int(it), int(ev["missing"][it]), "to_workshop")
	_refresh(true)
	if total > 0:
		_say("足りない材料 %d 個の運搬を頼んだ（仲間が運ぶ）" % total)
	else:
		_say("運べる材料がない（倉庫にない・すでに頼んだ）")
