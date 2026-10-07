class_name CrewDetailUI
extends CanvasLayer
## 仲間の管理画面。右上のボタン（またはCキー）で開閉する。
## 左: 部署（Lv・人数） / 中: メンバー一覧（複数選択できる CrewPicker） / 右: スクロールできる個体情報。
## 個体情報へプロフィール・状態・能力・採取道具・優先度・配属をまとめる。部署の解放情報は別タブ。

var game
var _worker
var _filter := -1                # -1 = 全員、それ以外は GameData.Field
var _tab := 0                    # 0 = 個体情報、1 = 部署
var _button_layer: CanvasLayer
var _overlay: Control
var _dept_btns := {}             # -1 / Field -> Button
var _tab_btns: Array = []
var _picker: CrewPicker
var _scroll: ScrollContainer
var _body: VBoxContainer
var _live := {}                  # 毎回更新する表示
var _timer := 0.0


func _ready() -> void:
	# 開くボタンは通常HUDに、開いた管理画面は他の管理画面より上に置く。
	layer = 27
	_button_layer = CanvasLayer.new()
	_button_layer.layer = 12
	add_child(_button_layer)
	var btn := UIKit.button("仲間の管理 (C)", toggle)
	btn.position = Vector2(1000, 252)
	btn.custom_minimum_size = Vector2(272, 32)
	_button_layer.add_child(btn)

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
	var title := UIKit.lbl("仲間の管理", 22, UIKit.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.button("閉じる (C / Esc)", close))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# 左: 部署
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(190, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(UIKit.lbl("部署", 15, UIKit.C_DIM))
	_dept_btns[-1] = UIKit.button("", func(): _set_filter(-1))
	left.add_child(_dept_btns[-1])
	for f in GameData.visible_departments():
		var b := UIKit.button("", func(): _set_filter(f))
		_dept_btns[f] = b
		left.add_child(b)
	for k in _dept_btns:
		_dept_btns[k].custom_minimum_size = Vector2(190, 46)

	# 中: メンバー一覧（複数選択）
	_picker = CrewPicker.new()
	_picker.source = func(): return _members(_filter)
	_picker.focused.connect(_select)
	_picker.selection_changed.connect(_on_selection_changed)
	cols.add_child(_picker)

	# 右: タブ + 個体の詳細
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	right.add_child(tabs)
	var i := 0
	for name in ["個体情報", "部署"]:
		var idx := i
		var tb := UIKit.button(name, func(): _set_tab(idx))
		tb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.custom_minimum_size = Vector2(150, 36)
		tabs.add_child(tb)
		_tab_btns.append(tb)
		i += 1
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 3)
	_scroll.add_child(_body)


# ---------------------------------------------------------------- 開閉
func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		# 管理画面内の閲覧対象と、画面側の選択は別。開くときは現在の選択を表示する。
		for w in game.workers:
			if w.selected:
				_worker = w
				break
		if not is_instance_valid(_worker):
			_worker = game.workers[0]
		open_worker(_worker)


## 方針画面等から個体情報を開く。世界側の選択・追従先・一括チェックは変更しない。
func open_worker(w) -> void:
	if not is_instance_valid(w) or not game.workers.has(w):
		return
	game.close_other_panels(self)
	_overlay.visible = true
	_worker = w
	_tab = 0
	_normalize_filter()
	if _filter >= 0 and w.dept != _filter:
		_filter = -1
	_picker.focus_worker = w
	_refresh_all()


func close() -> void:
	_overlay.visible = false


func show_worker(w) -> void:
	_worker = w
	if _overlay != null and _overlay.visible:
		_tab = 0
		if _filter >= 0 and w.dept != _filter:
			_filter = -1
		_picker.focus_worker = w
		_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			toggle()
		elif event.keycode == KEY_ESCAPE and _overlay.visible:
			close()


func _process(delta: float) -> void:
	if _overlay == null or not _overlay.visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.3
		_update_live()


# ---------------------------------------------------------------- 一覧・部署
func _members(field: int) -> Array:
	if field >= 0 and not GameData.department_visible(field):
		field = -1
	var l: Array = []
	for w in game.workers:
		if field < 0 or w.dept == field:
			l.append(w)
	l.sort_custom(func(a, b):
		if a.best_rank() != b.best_rank():
			return a.best_rank() > b.best_rank()
		return a.level > b.level)
	return l


func _refresh_all() -> void:
	_normalize_filter()
	_refresh_depts()
	_picker.refresh()
	_refresh_tabs()
	_build_detail()


func _set_filter(f: int) -> void:
	_normalize_filter()
	if f >= 0 and not GameData.department_visible(f):
		_refresh_depts()
		_picker.refresh()
		if _tab == 1:
			_build_detail()
		return
	_filter = f
	_refresh_depts()
	_picker.refresh()
	if _tab == 1:
		_build_detail()


func _refresh_depts() -> void:
	_normalize_filter()
	for k in _dept_btns:
		var b: Button = _dept_btns[k]
		if k < 0:
			b.text = "全員   %d人" % game.workers.size()
		else:
			b.visible = GameData.department_visible(k)
			b.text = "Lv%d %s   %d人" % [GameData.field_level(game.workers, k), GameData.FIELD_NAMES[k], _members(k).size()]
		UIKit.style(b, k == _filter)


func _select(w) -> void:
	_worker = w
	_tab = 0
	_refresh_tabs()
	_build_detail()


func _on_selection_changed() -> void:
	if _tab == 0:
		_update_live()


func _set_tab(t: int) -> void:
	_tab = t
	_refresh_tabs()
	_build_detail()


func _refresh_tabs() -> void:
	for i in _tab_btns.size():
		UIKit.style(_tab_btns[i], i == _tab)


# ---------------------------------------------------------------- 右: 個体の詳細
func _build_detail() -> void:
	UIKit.clear(_body)
	_live.clear()
	_scroll.scroll_vertical = 0
	if _tab == 1:
		_build_department()
		return
	var w = _worker
	if w == null:
		return
	_section("プロフィール")
	_body.add_child(_wrapped_label(w.char_name, 26, UIKit.C_ACCENT))
	_body.add_child(_wrapped_label("Lv %d   %s   個体ランク %s   得意分野: %s" % [w.level, GameData.GENDER_NAMES[w.gender],
			w.rank_letter(), w.best_fields_text()], 16))
	_section("状態・生活")
	_live["status"] = _wrapped_label("", 15)
	_body.add_child(_live["status"])
	var view := CrewStatusView.new().setup(Vector2i(16, 16), 13, true)
	_body.add_child(view)
	_live["view"] = view
	_build_life_controls(w)
	_build_tools(w)
	_build_personnel(w)
	_build_training(w)
	_update_live()


## 生活行動は自動。ここでは個体のAIへ促しを伝え、作業や予約を直接変更しない。
func _build_life_controls(w) -> void:
	_body.add_child(_wrapped_label("休憩・食事は自動で行います。必要なら早めに促せます。", 13, UIKit.C_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	for action in ["rest", "eat"]:
		var kind: String = action
		var text := "休憩を促す" if kind == "rest" else "食事を促す"
		var button := UIKit.button(text, func(): _request_life_action(w, kind))
		button.custom_minimum_size = Vector2(150, 32)
		row.add_child(button)
		_live["life_%s" % kind] = button
	_live["life_pending"] = _wrapped_label("", 13, UIKit.C_DIM)
	_body.add_child(_live["life_pending"])


func _request_life_action(w, action: String) -> void:
	if is_instance_valid(w) and w == _worker:
		w.ai.request_life_action(action)
	_update_live()


## 個体情報内の配属・優先度。まとめて移動する対象は、詳細を見る1人とは別に保つ。
func _build_personnel(w) -> void:
	_section("配属と仕事")
	_section("配属（この仲間を、押した部署へ移動）")
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 6)
	_body.add_child(dr)
	for f in GameData.visible_departments():
		var b := UIKit.button(GameData.FIELD_NAMES[f], func(): _move([w], f))
		b.custom_minimum_size = Vector2(100, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		UIKit.style(b, w.dept == f)
		dr.add_child(b)

	var sel := _picker.selected_list()
	_live["batch_title"] = _section("まとめて移動（チェックした %d人 を、押した部署へ）" % sel.size())
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 6)
	_body.add_child(mr)
	_live["batch_move"] = []
	for f in GameData.visible_departments():
		var b := UIKit.button(GameData.FIELD_NAMES[f], func(): _move(_picker.selected_list(), f))
		b.custom_minimum_size = Vector2(100, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.disabled = sel.is_empty()
		mr.add_child(b)
		_live["batch_move"].append(b)
	_live["batch_hint"] = _wrapped_label("左の一覧でチェックを付けるか、「全選択」「S以上」で選べます", 13, UIKit.C_DIM)
	_body.add_child(_live["batch_hint"])

	_section("仕事の効率")
	var eff := GridContainer.new()
	eff.columns = 2
	eff.add_theme_constant_override("h_separation", 22)
	_body.add_child(eff)
	for job in GameData.job_list():
		if job == GameData.Job.REST:
			continue
		var l := UIKit.lbl("", 15)
		eff.add_child(l)
		_live["eff_%d" % job] = l

	_section("仕事の優先度")
	for job in GameData.job_list():
		if job == GameData.Job.REST:
			continue
		var row := HBoxContainer.new()
		_body.add_child(row)
		row.add_child(UIKit.lbl(GameData.JOB_NAMES[job], 15, UIKit.C_TEXT, 60))
		var minus := UIKit.button("－", func(): _prio(w, job, -1))
		minus.custom_minimum_size = Vector2(36, 28)
		minus.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(minus)
		var stars := UIKit.lbl("", 16, Color("ffd24a"), 130)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(stars)
		_live["prio_%d" % job] = stars
		var plus := UIKit.button("＋", func(): _prio(w, job, 1))
		plus.custom_minimum_size = Vector2(36, 28)
		plus.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(plus)

## 既存の分野ランクとスキル。育成の新しい操作は追加しない。
func _build_training(w) -> void:
	_section("能力・スキル")
	_section("分野ランク")
	for f in GameData.Field.values():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_body.add_child(row)
		var star := "★" if f in w.best_fields() else "  "
		row.add_child(UIKit.lbl("%s %s" % [star, GameData.FIELD_NAMES[f]], 15, UIKit.C_ACCENT if f in w.best_fields() else UIKit.C_TEXT, 100))
		row.add_child(_rank_bar(w.ranks.get(f, 0)))
		row.add_child(UIKit.lbl(w.rank_text(f), 16, UIKit.C_ACCENT, 44))
		if GameData.department_visible(f):
			row.add_child(UIKit.lbl("部署 Lv%d" % GameData.field_level(game.workers, f), 14, UIKit.C_DIM, 90))
	_section("スキル")
	_body.add_child(_wrapped_label("   ".join(PackedStringArray(w.skills)) if not w.skills.is_empty() else "なし", 15,
			UIKit.C_TEXT if not w.skills.is_empty() else UIKit.C_DIM))


## 装備の実データは既存の採取道具だけ。全員共通の自動設定と、閲覧中の1人の手動操作を分ける。
func _build_tools(w) -> void:
	_section("装備・防具")
	_body.add_child(_wrapped_label("武器・防具：未実装", 13, UIKit.C_DIM))
	_section("採取道具")
	_live["tool_auto"] = UIKit.button("", _toggle_tool_auto)
	_live["tool_auto"].custom_minimum_size = Vector2(0, 32)
	_body.add_child(_live["tool_auto"])
	for slot in GatherDB.SLOTS:
		var s: String = slot
		_live["tool_%s" % s] = _wrapped_label("", 15)
		_body.add_child(_live["tool_%s" % s])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_body.add_child(row)
		var choices := OptionButton.new()
		choices.custom_minimum_size = Vector2(240, 32)
		choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.fit_to_longest_item = false
		choices.clip_text = true
		choices.add_theme_font_override("font", GameData.font())
		for it in GameData.TOOL_ITEMS:
			var item: int = it
			if GatherDB.slot_of_tool(item) == s:
				choices.add_item(GameData.ITEM_NAMES[item], item)
		var equipped: int = int(w.tools.get(s, -1))
		var index: int = choices.get_item_index(equipped)
		if index >= 0:
			choices.select(index)
		choices.item_selected.connect(func(_index): _update_live())
		row.add_child(choices)
		_live["tool_select_%s" % s] = choices
		var equip := UIKit.button("装備", func(): _equip_selected_tool(w, s))
		equip.custom_minimum_size = Vector2(64, 32)
		row.add_child(equip)
		_live["tool_equip_%s" % s] = equip
		var off := UIKit.button("外す", func(): _unequip_tool(w, s))
		off.custom_minimum_size = Vector2(64, 32)
		row.add_child(off)
		_live["tool_unequip_%s" % s] = off
		_live["tool_reason_%s" % s] = _wrapped_label("", 13, UIKit.C_DIM)
		_body.add_child(_live["tool_reason_%s" % s])
		_live["yield_%s" % s] = _wrapped_label("", 13, UIKit.C_DIM)
		_body.add_child(_live["yield_%s" % s])
	_body.add_child(_wrapped_label("回収率は既存の採取効率です。端数や袋の上限により、実際に持ち帰る個数は変わります。", 13, UIKit.C_DIM))


func _toggle_tool_auto() -> void:
	game.tool_auto = not game.tool_auto
	_update_live()


func _manual_tool_reason(w) -> String:
	if game.tool_auto:
		return "自動割り当てをOFFにしてから変更してください。"
	if w.away:
		return "遠征中は道具を変更できません。"
	if w.down:
		return "戦闘不能の間は道具を変更できません。"
	return ""


func _equip_selected_tool(w, slot: String) -> void:
	if is_instance_valid(w) and w == _worker and _manual_tool_reason(w).is_empty():
		var choices: OptionButton = _live["tool_select_%s" % slot]
		game.equip_tool(w, choices.get_selected_id())
	_update_live()


func _unequip_tool(w, slot: String) -> void:
	if is_instance_valid(w) and w == _worker and _manual_tool_reason(w).is_empty():
		game.unequip_tool(w, slot)
	_update_live()


## 在庫・自動設定・装備の変化は部品の値だけ更新し、選んだ候補やスクロール位置を保つ。
func _update_tool_controls(w, slot: String) -> void:
	var choices: OptionButton = _live["tool_select_%s" % slot]
	var current: int = int(w.tools.get(slot, -1))
	var manual_reason := _manual_tool_reason(w)
	for i in choices.item_count:
		var item: int = choices.get_item_id(i)
		var stock: int = game.storage.count_of(item)
		var text := "%s（在庫%d%s）" % [GameData.ITEM_NAMES[item], stock, "・装備中" if item == current else ""]
		if choices.get_item_text(i) != text:
			choices.set_item_text(i, text)
		var reason: String = game.tool_equip_reason(w, item)
		if item == current:
			reason = "すでに装備しています。"
		choices.set_item_tooltip(i, reason)
	choices.disabled = not manual_reason.is_empty()
	choices.tooltip_text = manual_reason
	var selected: int = choices.get_selected_id()
	var equip_reason: String = game.tool_equip_reason(w, selected)
	if selected == current:
		equip_reason = "すでに装備しています。"
	var off_reason: String = game.tool_unequip_reason(w, slot)
	if current < 0:
		off_reason = "外せる道具がありません。"
	if not manual_reason.is_empty():
		equip_reason = manual_reason
		off_reason = manual_reason
	var equip: Button = _live["tool_equip_%s" % slot]
	var off: Button = _live["tool_unequip_%s" % slot]
	equip.disabled = not equip_reason.is_empty()
	off.disabled = not off_reason.is_empty()
	equip.tooltip_text = equip_reason
	off.tooltip_text = off_reason
	var reasons: Array[String] = []
	if not manual_reason.is_empty():
		reasons.append(manual_reason)
	else:
		if not equip_reason.is_empty():
			reasons.append("装備：" + equip_reason)
		if current >= 0 and not off_reason.is_empty():
			reasons.append("外す：" + off_reason)
	var feedback: Label = _live["tool_reason_%s" % slot]
	feedback.text = " ／ ".join(PackedStringArray(reasons))
	feedback.visible = not reasons.is_empty()


## タブ「部署」: 選んだ部署のLvと、解放の一覧（Lvが足りない間も「こういうものがある」と見せる）
func _build_department() -> void:
	_normalize_filter()
	if _filter < 0:
		_body.add_child(UIKit.lbl("左で部署を選ぶと、その部署のLvと解放内容が見られます", 15, UIKit.C_DIM))
		return
	var f := _filter
	var lv := GameData.field_level(game.workers, f)
	var head := HBoxContainer.new()
	_body.add_child(head)
	head.add_child(UIKit.lbl(GameData.FIELD_NAMES[f], 26, UIKit.C_ACCENT, 150))
	head.add_child(UIKit.lbl("部署Lv %d   配属 %d人" % [lv, _members(f).size()], 16))
	_section("解放")
	var list := GameData.unlocks_of(f)
	if list.is_empty():
		_body.add_child(UIKit.lbl("この部署の解放内容は検討中です", 14, UIKit.C_DIM))
		return
	for u in list:
		var st := GameData.unlock_state(game.workers, game.blueprints, u)
		var card := PanelContainer.new()
		var edge := UIKit.C_ACCENT if st == GameData.UNLOCK_OPEN else Color("636b7a")
		card.add_theme_stylebox_override("panel", UIKit.box(Color("22252b"), edge, 2, 8))
		_body.add_child(card)
		var v := VBoxContainer.new()
		card.add_child(v)
		match st:
			GameData.UNLOCK_OPEN:
				v.add_child(UIKit.lbl("解放済み   %s" % u["name"], 16, UIKit.C_ACCENT))
				v.add_child(_wrapped_label(u["detail"], 14))
			GameData.UNLOCK_NEED_BLUEPRINT:
				v.add_child(UIKit.lbl("設計図が必要   %s" % u["name"], 16, Color("e0a34d")))
				v.add_child(UIKit.lbl("詳細: ？？？（設計図を入手すると見えます）", 14, UIKit.C_DIM))
			_:
				v.add_child(UIKit.lbl("Lv%d で解放（いまLv%d）   %s" % [u["need_level"], lv, u["name"]], 16, UIKit.C_DIM))
				v.add_child(_wrapped_label(u["teaser"], 14, UIKit.C_DIM))
	_body.add_child(UIKit.lbl("※ 解放で何が良くなるか（恩恵）は検討中です", 13, UIKit.C_DIM))


func _update_live() -> void:
	var w = _worker
	if not is_instance_valid(w) or not _live.has("status"):
		return
	_live["status"].text = w.ai.status_text()
	if GameData.department_visible(w.dept):
		_live["status"].text += "     配属: %s" % GameData.FIELD_NAMES[w.dept]
	if _live.has("batch_title"):
		var count: int = _picker.selected_list().size()
		_live["batch_title"].text = "── まとめて移動（チェックした %d人 を、押した部署へ） ──" % count
		for button in _live["batch_move"]:
			button.disabled = count == 0
		_live["batch_hint"].visible = count == 0
	if _live.has("view"):
		_live["view"].update_from(w)
	for action in ["rest", "eat"]:
		if _live.has("life_%s" % action):
			var reason: String = w.ai.life_action_reason(action)
			var button: Button = _live["life_%s" % action]
			button.disabled = not reason.is_empty()
			button.tooltip_text = reason
	if _live.has("life_pending"):
		var pending: String = w.ai.life_request
		_live["life_pending"].visible = not pending.is_empty()
		_live["life_pending"].text = "%sを促しています。今の作業を安全に区切るのを待っています。" % ("休憩" if pending == "rest" else "食事") if not pending.is_empty() else ""
	if _live.has("tool_auto"):
		var auto: Button = _live["tool_auto"]
		var text := "道具の自動割り当て（全員共通）：%s" % ("ON" if game.tool_auto else "OFF")
		if auto.text != text:
			auto.text = text
			UIKit.style(auto, game.tool_auto)
		auto.tooltip_text = "全員共通の設定です。手動で付け替えるときはOFFにしてください。"
	for slot in GatherDB.SLOTS:
		if not _live.has("tool_%s" % slot):
			continue
		var cur: int = int(w.tools.get(slot, -1))
		_live["tool_%s" % slot].text = "%s：%s" % [GatherDB.SLOTS[slot], GatherDB.tool_def(cur)["name"]]
		if _live.has("tool_select_%s" % slot):
			_update_tool_controls(w, slot)
		var parts: Array[String] = []
		for kind in GatherDB.POINTS:
			if GatherDB.POINTS[kind]["slot"] != slot:
				continue
			var ev: Dictionary = w.gather_eval(kind)
			if float(ev["eff"]) < GatherDB.MIN_EFF:
				parts.append("%s：採取対象外" % GatherDB.POINTS[kind]["name"])
			else:
				parts.append("%s：回収率 %.1f%%" % [GatherDB.POINTS[kind]["name"], float(ev["eff"]) * 100.0])
		_live["yield_%s" % slot].text = " ／ ".join(PackedStringArray(parts))
	for job in GameData.job_list():
		if job != GameData.Job.REST and _live.has("eff_%d" % job):
			_live["eff_%d" % job].text = "%s ×%.2f" % [GameData.JOB_NAMES[job], w.skill_mult(job)]
		if _live.has("prio_%d" % job):
			var n: int = w.priorities.get(job, 0)
			_live["prio_%d" % job].text = ("★".repeat(n) + "☆".repeat(GameData.MAX_PRIORITY - n)) if n > 0 else "─ やらない ─"


## 仲間（1人でも複数でも）を部署 f へ移す。移動先の部署の一覧に切り替えて追う。
func _move(list: Array, f: int) -> void:
	if list.is_empty() or not GameData.department_visible(f):
		return
	for w in list:
		w.dept = f
	_filter = f
	_refresh_depts()
	_picker.refresh()
	_build_detail()


func _prio(w, job: int, d: int) -> void:
	if not is_instance_valid(w) or w != _worker or job == GameData.Job.REST:
		return
	w.set_priority(job, w.priorities.get(job, 0) + d)
	_update_live()


func _section(text: String) -> Label:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	_body.add_child(sp)
	var title := _wrapped_label("── " + text + " ──", 14, UIKit.C_DIM)
	_body.add_child(title)
	return title


## 過去の表示設定に非表示部署が残っていても、配属データを変更せず全員一覧へ戻す。
func _normalize_filter() -> void:
	if _filter >= 0 and not GameData.department_visible(_filter):
		_filter = -1


## 長い名前・得意分野・説明でも、右側の表示幅を押し広げない。
func _wrapped_label(text: String, font_size: int = 15, color: Color = UIKit.C_TEXT) -> Label:
	var l := UIKit.lbl(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## ランクを8マスのバーで表す（E=1マス … SSS=8マス）。
func _rank_bar(rank: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.custom_minimum_size = Vector2(260, 18)
	for i in 8:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(28, 14)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.color = Color("f2c14e") if i <= rank else Color("2a2e36")
		h.add_child(c)
	return h
