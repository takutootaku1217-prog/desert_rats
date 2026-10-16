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
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(620, 540)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(detail_scroll)
	detail_scroll.add_child(_detail)


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
	var focus:=get_viewport().gui_get_focus_owner()
	if not force and focus is LineEdit and _detail.is_ancestor_of(focus):return
	if game == null or game.storage == null:
		return
	if _cat == "" or not CraftDB.categories_in_use().has(_cat):
		var cats := CraftDB.categories_in_use()
		_cat = cats[0] if not cats.is_empty() else ""
	var es := _entries()
	if selected_entry().is_empty() or selected_entry()["cat"] != _cat:
		_key = es[0]["key"] if not es.is_empty() else ""
	# 目印: 分類・選択・各エントリの状態・選んだ物の材料の数・待ち行列
	var parts: Array = [_cat, _key, str(_qty_val),str(game.production_orders),str(game.refill_settings),str(game.procurement_goals),str(game.gather_room()),str(game.workers.map(func(w):return [w.carrying,w.carry_n]))]
	if not selected_entry().is_empty(): parts.append(str(game.processor.manual_status(selected_entry()["id"])))
	for e in es:
		var ev: Dictionary = CraftDB.evaluate(e, game, 1, true)
		parts.append("%s:%s" % [e["key"], ev["state"]])
	var sel := selected_entry()
	if not sel.is_empty():
		parts.append(CraftDB.detail_text(sel, game))
		var evs: Dictionary = CraftDB.evaluate(sel, game, _qty_val, true)
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
	if e["kind"] == "build":
		return int(FacilityDB.def(e["id"]).get("packed_item", GameData.Item.HAMMER))
	return int(e["out"])


func _rebuild_list() -> void:
	UIKit.clear(_list)
	for e in _entries():
		var ev: Dictionary = CraftDB.evaluate(e, game, 1, true)
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
	var ev: Dictionary = CraftDB.evaluate(e, game, qty, true)
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
	if not is_build:
		var summary := UIKit.lbl("%d回の注文 / 成果%d個 / 基準加工時間 %.1f秒（1回%.1f秒×%d、能力補正前）\n複数回だけまとめ回収：通常3個／フレーム5個。単発・自動は1個ずつ。割引なし。" % [qty,int(e["n"])*qty,float(e["time"])*qty,float(e["time"]),qty],13,UIKit.C_DIM)
		summary.name = "BatchSummary"
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.custom_minimum_size = Vector2(540,0)
		_detail.add_child(summary)
	var explanation := CraftDB.detail_text(e, game)
	if explanation != "":
		var effect := UIKit.lbl(explanation, 13, UIKit.C_TEXT)
		effect.name = "EffectDetail"
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.custom_minimum_size = Vector2(540, 0)
		_detail.add_child(effect)
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
		var top_n: int = maxi(99, maxi(int(ev["material_qty"]), int(ev["material_with_storage"])))                          # 材料が足りなくても、必要な数を見るために、倉庫の分まで選べる
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
		var label := "建設を依頼する"
		var d := FacilityDB.def(e["id"])
		if d.has("packed_item"):
			label = "製作物の設置を依頼する" if game.storage.count_of(d["packed_item"]) > 0 else "製作して設置を依頼する"
		_craft_btn = UIKit.button(label, _do_build)
		_craft_btn.disabled = not (state in ["ok", "short"])
	else:
		_craft_btn = UIKit.button("1回制作" if qty == 1 else "%d回まとめて制作" % qty, _do_craft)
		_craft_btn.disabled = state == "locked"
	_craft_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_btn.custom_minimum_size = Vector2(190, 38)
	acts.add_child(_craft_btn)
	if not is_build and state != "locked":
		_carry_btn = UIKit.button("素材を運ぶ", _do_carry)
		_carry_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_carry_btn.custom_minimum_size = Vector2(150, 38)
		_carry_btn.disabled = not CraftDB.evaluate(e,game,qty).can_transfer
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
	if not is_build:
		var s: Dictionary = game.processor.manual_status(e["id"])
		var status_text := "加工枠 %d（作業者一人につき1枠）\n" % (2 if game.has_facility("parallel_bench") else 1) + "未投入 %d回 / 投入済・未着手 %d回 / 加工中 %d回（%.1f / %.1f秒）\n完成品未回収 %d個（同じ品目の共有トレイ）。加工中の各枠は取消せず完了させます。" % [s.queued,s.loaded,s.active,s.progress,s.time,s.output]
		var batch_status := UIKit.lbl(status_text,13,UIKit.C_DIM)
		batch_status.name = "BatchStatus"
		batch_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		batch_status.custom_minimum_size = Vector2(540,0)
		_detail.add_child(batch_status)
		var rid: String = e["id"]
		var cancel := UIKit.button("この品目の未着手分を取消",func():
			var count: int = game.cancel_manual_craft(rid)
			_say("未着手%d回を取消。投入済の未着手材料は元の保管先へ返却。加工中・完成品・運搬中は保持。" % count)
			_refresh(true))
		cancel.name = "CancelUnstarted"
		cancel.disabled = s.queued+s.loaded == 0 and not game.production_orders.any(func(q):return q.id==rid) and not game.processor.incoming.any(func(r):return r.id==rid and r.get("player_order",false))
		_detail.add_child(cancel)
	_add_production(e,qty)
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
		_detail.add_child(UIKit.lbl("未投入の制作予約（材料は作業場）", 13, UIKit.C_DIM))
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
	var got: int = game.request_order(e["id"], _qty_val)
	_refresh(true)
	if got > 0:
		_say("制作を頼んだ: %s ×%d回（材料一式がそろった分から仲間が搬入・加工）" % [e["name"], got])
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
		total += game.request_transfer(int(it), maxi(0,int(ev["missing"][it])-game.workshop_incoming(int(it))), "to_workshop")
	_refresh(true)
	if total > 0:
		_say("足りない材料 %d 個の運搬を頼んだ（仲間が運ぶ）" % total)
	else:
		_say("運べる材料がない（倉庫にない・すでに頼んだ）")


func _add_production(e:Dictionary,qty:int) -> void:
	_detail.add_child(UIKit.lbl("注文・調達（倉庫在庫と個体の所持品は別）",16,UIKit.C_ACCENT))
	var costs:Dictionary=game.build_cost(e.id) if e.kind=="build" else e["in"]
	for it in costs:
		var need:int=int(costs[it])*(1 if e.kind=="build" else qty)
		var have:int=game.storage.count_of(it)
		var transit:int=game.procurement_transit(it)
		var available:int=AutoCraftGuard.available(game,it,null,true)
		var missing:int=maxi(0,need-available-transit)
		_detail.add_child(UIKit.lbl("%s 必要%d / 箱%d（利用可%d）/ 運搬中%d / 不足%d"%[ItemDB.name_of(it),need,have,available,transit,missing],13))
		var item:int=it
		var goal:=SpinBox.new();goal.name="GoalQuantity%d"%item;goal.min_value=0;goal.max_value=999;goal.value=game.procurement_goals.get(it,need)
		var row:=HBoxContainer.new();_detail.add_child(row);row.add_child(UIKit.lbl("箱の目標",12));row.add_child(goal)
		var collect:=UIKit.button("不足分を集める / 目標更新",func():game.set_procurement(item,int(goal.value));_refresh(true));collect.name="CollectGoal%d"%item;row.add_child(collect)
		var cancel:=UIKit.button("取消",func():game.set_procurement(item,0);_refresh(true));cancel.name="CancelGoal%d"%item;row.add_child(cancel)
		if game.procurement_goals.has(it):
			var reason:="採取目標 %d"%game.procurement_goals[it]
			if not game.resources_root.get_children().any(func(r):return r.item==item and (not r is GatherPoint or r.available())): reason+=" / ここに採取対象なし（加工品は製作注文が必要）"
			elif game.storage.free_for(item)<=0:reason+=" / 積載満杯"
			elif not game.resources_root.get_children().any(func(r):return r.item==item and (not r is GatherPoint or game.workers.any(func(w):return float(w.gather_eval(r.kind).eff)>=GatherDB.MIN_EFF))):reason+=" / 今の道具では採取できない"
			_detail.add_child(UIKit.lbl(reason,13,UIKit.C_DIM))
	if e.kind=="recipe" and game.refill_settings.has(e.out):
		var setting:Dictionary=game.refill_settings[e.out]
		var row:=HBoxContainer.new();_detail.add_child(row)
		var enabled:=CheckBox.new();enabled.name="RefillEnabled";enabled.text="自動補充";enabled.button_pressed=setting.enabled;row.add_child(enabled)
		enabled.toggled.connect(func(v):setting.enabled=v;_refresh(true))
		var target:=SpinBox.new();target.name="RefillTarget";target.min_value=0;target.max_value=999;target.value=setting.target;row.add_child(target)
		target.value_changed.connect(func(v):setting.target=int(v))
		var pending:int=ProductionPlan.future(game,e.out)
		var status:="補充中" if pending>0 else ("目標達成" if ProductionPlan.finished(game,e.out)>=int(setting.target) else "素材不足・搬入待ち")
		if not setting.enabled:status="補充OFF"
		_detail.add_child(UIKit.lbl("%s / 完成%d＋加工・予約%d / 目標%d"%[status,ProductionPlan.finished(game,e.out),pending,setting.target],13,UIKit.C_DIM))
	for q in game.production_orders:
		var r:=GameData.recipe_by_id(q.id)
		var reason:=ProductionPlan.order_reason(game,r)
		_detail.add_child(UIKit.lbl("%s ×%d / %s"%[r.name,q.n,reason],13))
