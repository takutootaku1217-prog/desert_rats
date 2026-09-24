class_name DepartmentUI
extends CanvasLayer
## 部署画面。Dキーまたは右上のボタンで開閉する。
## 左で仲間を選び、右の各部署の「選択中を配置」で配置する（部署の中の名前を押すと外れる）。
## 部署レベル・効率は、所属人数と所属個体の能力値・ランク・スキルから決まる。
## 部署レベルが上がると Unlocks（data/unlocks.gd）の機能が解放される。

var game
var _worker
var _overlay: Control
var _list: VBoxContainer
var _body: VBoxContainer
var _timer := 0.0

const C_TEXT := Color("ffe9b0")
const C_DIM := Color("9aa3b2")
const C_ACCENT := Color("f2c14e")
const C_LOCKED := Color("6b7280")
const C_UNLOCKED := Color("86efac")


func _ready() -> void:
	layer = 21
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 12
	add_child(btn_layer)
	var btn := GameData.make_button("部署 (D)", toggle)
	btn.position = Vector2(1000, 134)
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
	var title := GameData.make_label("部署（仲間を選んで配置）", 22, C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(GameData.make_button("閉じる (D / Esc)", close))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(210, 0)
	_list.add_theme_constant_override("separation", 6)
	cols.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(880, 0)
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)


func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		game.close_other_panels(self)
		_overlay.visible = true
		_rebuild()


func close() -> void:
	_overlay.visible = false


func show_worker(w) -> void:
	_worker = w
	if _overlay != null and _overlay.visible:
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_D:
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


func _rebuild() -> void:
	if game == null:
		return
	if _worker == null:
		_worker = game.workers[0]
	# 左: 仲間の一覧（選択中の仲間を配置する）
	_clear(_list)
	_list.add_child(_lbl("仲間（選んで右の部署へ）", 14, C_DIM))
	for w in game.workers:
		var dname: String = GameData.dept_name(w.dept) if w.dept >= 0 else "無所属"
		var b := GameData.make_button("%s  Lv%d [%s]\n%s" % [w.char_name, w.level, w.rank_letter(), dname],
				func(): game.select_worker(w), 14)
		b.custom_minimum_size = Vector2(210, 50)
		if w == _worker:
			b.add_theme_stylebox_override("normal", GameData.panel_box(Color("4b5262"), C_ACCENT, 3))
		_list.add_child(b)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	_list.add_child(sp)
	var rb := GameData.make_button("仲間を募集\n%s" % _cost_text(Balance.RECRUIT_COST), func(): game.recruit(), 14)
	rb.custom_minimum_size = Vector2(210, 50)
	rb.disabled = not game.can_recruit()
	_list.add_child(rb)
	_list.add_child(_lbl("仲間 %d / %d匹" % [game.workers.size(), game.max_crew()], 13, C_DIM))
	# 右: 部署
	_clear(_body)
	var w = _worker
	_body.add_child(_lbl("選択中: %s（%s ランク%s）   所属: %s" % [w.char_name, _best_text(w), w.rank_letter(),
			GameData.dept_name(w.dept) if w.dept >= 0 else "無所属"], 17, C_ACCENT))
	for f in GameData.Field.values():
		_body.add_child(_dept_panel(f, w))
	_body.add_child(_lbl("部署レベルは 人数・能力値・高ランク・同じスキルの相乗 で上がる。自分の分野の部署に置くと仕事が ×%.2f 速くなる。" % Balance.ASSIGN_BONUS,
			13, C_DIM))


func _best_text(w) -> String:
	var names: Array = []
	for f in w.best_fields():
		names.append(GameData.FIELD_NAMES[f])
	return "・".join(PackedStringArray(names))


func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	var have: Array = []
	for it in cost:
		parts.append("%s×%d" % [GameData.ITEM_NAMES[it], cost[it]])
		have.append(str(game.storage.count_of(it)))
	return "（%s / 所持 %s）" % [" ".join(PackedStringArray(parts)), " ".join(PackedStringArray(have))]


func _dept_panel(f: int, sel) -> Control:
	var info: Dictionary = game.dept_info(f)
	var members: Array = info["members"]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameData.panel_box(Color("23262d"), Color("3a3f4a"), 2, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(_lbl(GameData.dept_name(f), 20, C_ACCENT, 90))
	head.add_child(_lbl("Lv %d" % info["level"], 18, C_TEXT, 60))
	head.add_child(_lbl("効率 ×%.2f" % info["eff"], 16, C_TEXT, 110))
	head.add_child(_lbl("%d / %d人" % [members.size(), Balance.DEPT_CAPACITY], 15, C_DIM, 70))
	var next_text := "MAX" if info["next_points"] < 0.0 else "次Lvまで %.1f" % (info["next_points"] - info["points"])
	head.add_child(_lbl("ポイント %.1f（%s）" % [info["points"], next_text], 14, C_DIM, 230))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var full: bool = members.size() >= Balance.DEPT_CAPACITY and sel.dept != f
	var ab := GameData.make_button("選択中を配置", func(): game.assign(sel, f), 14)
	ab.disabled = sel.dept == f or full
	head.add_child(ab)
	var eff_text: String = "効果: " + GameData.FIELD_EFFECT_TEXT[f]
	if info["synergy"] > 0.0:
		eff_text += "    スキルの相乗 +%.1fポイント" % info["synergy"]
	if info["top_rank"] > Balance.DEPT_TOP_RANK_BASE:
		eff_text += "    高ランクボーナス +%d%%" % int(round(Balance.DEPT_TOP_RANK_EFF * (info["top_rank"] - Balance.DEPT_TOP_RANK_BASE) * 100.0))
	v.add_child(_lbl(eff_text, 13, C_DIM))
	v.add_child(_unlock_row(f, info["level"]))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	v.add_child(mrow)
	if members.is_empty():
		mrow.add_child(_lbl("（誰もいない）", 14, C_DIM))
	for m in members:
		var mb := GameData.make_button("%s  %s %s ✕" % [m.char_name, m.rank_text(f), "%.0f" % m.ability(f)],
				func(): game.assign(m, -1), 14)
		mrow.add_child(mb)
	return panel


## 部署レベルによる解放（Unlocks）の一覧。解放済みは緑、未解放は灰色で並べ、
## 次の解放だけは何が要るか（Lv◯）を添える。幅からはみ出さないよう折り返す。
func _unlock_row(f: int, level: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var all_tiers: Array = Unlocks.TIERS.get(f, [])
	if all_tiers.is_empty():
		col.add_child(_lbl("解放要素なし", 12, C_DIM))
		return col
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 2)
	col.add_child(flow)
	for t in all_tiers:
		var open: bool = level >= t["level"]
		var text: String = "✓ %s" % t["title"] if open else "・%s (Lv%d)" % [t["title"], t["level"]]
		flow.add_child(_lbl(text, 13, C_UNLOCKED if open else C_LOCKED))
	var nxt = Unlocks.next_tier(f, level)
	if nxt != null:
		col.add_child(_lbl("次の解放: %s" % nxt["desc"], 12, C_DIM))
	return col
