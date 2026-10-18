class_name CrewDetailUI
extends CanvasLayer
## 仲間の管理画面。通常HUDの仲間ボタン（またはCキー）で開閉する。
## 左: 顔つきメンバー一覧と部署フィルター / 右: 固定ヘッダー＋用途別タブ。
## 概要 / 装備・荷物 / 仕事・能力へ整理し、部署の解放情報は別タブに残す。

var game
var _worker
var _filter := -1                # -1 = 全員、それ以外は GameData.Field
var _tab := 0                    # 0 = 概要、1 = 装備・荷物、2 = 仕事・能力、3 = 部署
var _overlay: Control
var _dept_btns := {}             # 旧UI互換の予約。部署の入口はフィルターと「部署」タブへ移した。
var _filter_select: OptionButton
var _tab_btns: Array = []
var _picker: CrewPicker
var _scroll: ScrollContainer
var _body: VBoxContainer
var _live := {}                  # 毎回更新する表示
var _header := {}                # タブ切替でも残る個体ヘッダー
var _timer := 0.0


func _ready() -> void:
	# 開く入口は通常HUDに集約し、管理画面は他の管理画面より上に置く。
	layer = 27

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

	# 左: 顔つきメンバー一覧（複数選択）。部署の常設列をなくし、個人カードの幅を確保する。
	var members := VBoxContainer.new()
	members.custom_minimum_size = Vector2(220, 0)
	members.size_flags_vertical = Control.SIZE_EXPAND_FILL
	members.add_theme_constant_override("separation", 5)
	cols.add_child(members)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 5)
	members.add_child(filter_row)
	filter_row.add_child(UIKit.lbl("部署", 13, UIKit.C_DIM, 34))
	_filter_select = OptionButton.new()
	_filter_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_select.fit_to_longest_item = false
	_filter_select.add_theme_font_override("font", GameData.font())
	_filter_select.item_selected.connect(func(index): _set_filter(_filter_select.get_item_id(index)))
	filter_row.add_child(_filter_select)
	_picker = CrewPicker.new()
	_picker.set_compact(true)
	_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker.source = func(): return _members(_filter)
	_picker.number_source = func(w): return game.crew_alerts.number_of(w) if game.crew_alerts != null else 0
	_picker.focused.connect(_select)
	_picker.selection_changed.connect(_on_selection_changed)
	members.add_child(_picker)

	# 右: タブ + タブ切替でも消えない個体ヘッダー + 個体の詳細
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	right.add_child(tabs)
	var i := 0
	for name in ["概要", "装備・荷物", "仕事・能力", "部署"]:
		var idx := i
		var tb := UIKit.button(name, func(): _set_tab(idx))
		tb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.custom_minimum_size = Vector2(118, 36)
		tabs.add_child(tb)
		_tab_btns.append(tb)
		i += 1
	_build_detail_header(right)
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
		if game.workers.is_empty():
			_worker = null
			_picker.focus_worker = null
			_refresh_all()
			return
		# 管理画面内の閲覧対象と、画面側の選択は別。開くときは現在の選択を表示する。
		for w in game.workers:
			if w.selected:
				_worker = w
				break
		if not is_instance_valid(_worker) or not game.workers.has(_worker):
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
		if _tab == 3:
			_build_detail()
		return
	_filter = f
	_refresh_depts()
	_picker.refresh()
	if _tab == 3:
		_build_detail()


func _refresh_depts() -> void:
	_normalize_filter()
	if _filter_select == null:
		return
	_filter_select.clear()
	_filter_select.add_item("全員 %d人" % game.workers.size(), -1)
	for f in GameData.visible_departments():
		_filter_select.add_item("%s %d人" % [GameData.FIELD_NAMES[f], _members(f).size()], f)
	var selected := _filter_select.get_item_index(_filter)
	_filter_select.select(selected if selected >= 0 else 0)


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
	if _tab == 3:
		_build_department()
		return
	var w = _worker
	if not is_instance_valid(w) or not game.workers.has(w):
		return
	match _tab:
		0: _build_overview(w)
		1: _build_equipment_and_cargo(w)
		2: _build_work_and_ability(w)
	_update_live()


## 顔・名前・現在行動・受付中の指示・重要な不調・頻出操作は、どのタブでも見失わない。
func _build_detail_header(right: VBoxContainer) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 108)
	card.add_theme_stylebox_override("panel", UIKit.box(Color("25282e"), Color("636b7a"), 2, 7))
	right.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(82, 82)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	_header["portrait"] = portrait
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	_header["name"] = _wrapped_label("", 24, UIKit.C_ACCENT)
	text.add_child(_header["name"])
	_header["action"] = _wrapped_label("", 18)
	text.add_child(_header["action"])
	_header["instruction"] = _wrapped_label("", 12, UIKit.C_DIM)
	text.add_child(_header["instruction"])
	_header["warning"] = _wrapped_label("", 13, UIKit.C_DIM)
	text.add_child(_header["warning"])
	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(150, 0)
	actions.add_theme_constant_override("separation", 5)
	row.add_child(actions)
	var returning := UIKit.button("帰還を指示", _request_return)
	returning.custom_minimum_size = Vector2(150, 32)
	actions.add_child(returning)
	_header["return"] = returning
	var exempt := UIKit.button("全体帰還：対象", _toggle_recall_exempt)
	exempt.custom_minimum_size = Vector2(150, 28)
	actions.add_child(exempt)
	_header["recall_exempt"] = exempt
	var rescue := UIKit.button("救助操作", _request_rescue)
	rescue.custom_minimum_size = Vector2(150, 32)
	actions.add_child(rescue)
	_header["rescue"] = rescue
	var repair := UIKit.button("\u4fee\u7406\u3092\u4efb\u305b\u308b", _request_header_repair)
	repair.custom_minimum_size = Vector2(150, 32)
	actions.add_child(repair)
	_header["repair"] = repair
	var rest := UIKit.button("休憩を促す", _request_header_rest)
	rest.custom_minimum_size = Vector2(150, 32)
	actions.add_child(rest)
	_header["rest"] = rest
	var follow := UIKit.button("画面で選択・追従", _follow_worker)
	follow.custom_minimum_size = Vector2(150, 28)
	actions.add_child(follow)
	_header["follow"] = follow


func _portrait_of(w) -> Texture2D:
	var sheet := GameData.tex("res://assets/characters/mouse_%s.png" % w.palette)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = ArtSpec.frame_src(sheet, ArtSpec.WORKER, Worker.F_IDLE0)
	atlas.filter_clip = true
	return atlas


func _build_overview(w) -> void:
	var number: int = game.crew_alerts.number_of(w) if game.crew_alerts != null else 0
	_body.add_child(_wrapped_label("No.%02d　Lv%d・個体ランク %s　得意: %s" % [number, w.level, w.rank_letter(), w.best_fields_text()], 15, UIKit.C_DIM))
	var view := CrewStatusView.new().setup(Vector2i(12, 12), 11, true)
	_body.add_child(view)
	_live["view"] = view
	# 休憩は固定ヘッダーの頻出操作。食事だけを短い補助操作として概要に残す。
	_live["life_rest"] = _header["rest"]
	_build_life_controls(w, false)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	_body.add_child(cards)
	var equipment_card := _visual_card(cards, "使用中の装備", Color("bfa774"))
	_live["overview_equipment_slots"] = HBoxContainer.new()
	_live["overview_equipment_slots"].add_theme_constant_override("separation", 5)
	equipment_card.add_child(_live["overview_equipment_slots"])
	var cargo_card := _visual_card(cards, "運搬中", Color("76b7ce"))
	_live["cargo_summary"] = UIKit.lbl("", 14, UIKit.C_TEXT)
	cargo_card.add_child(_live["cargo_summary"])
	_live["carried"] = _live["cargo_summary"]       # 既存の診断・連携が読む参照を保持する。
	_live["overview_cargo_items"] = HBoxContainer.new()
	_live["overview_cargo_items"].add_theme_constant_override("separation", 5)
	cargo_card.add_child(_live["overview_cargo_items"])
	_live["cargo_detail"] = _wrapped_label("", 12, UIKit.C_DIM)
	cargo_card.add_child(_live["cargo_detail"])


func _build_equipment_and_cargo(w) -> void:
	_build_tools(w)
	_build_cargo_panel(w, true)


func _build_work_and_ability(w) -> void:
	_build_personnel(w)
	_build_training(w)


## carrying/carry_n は個人バッグではなく、既存AIが届ける途中の物資。
## 狩猟素材、加工材料、倉庫⇄作業場の移し替えなどを、届け先ごとに表示する。
func _build_cargo_panel(w, include_store := true) -> void:
	var cargo_card := _visual_card(_body, "運搬中（個人バッグではありません）", Color("76b7ce"))
	_live["cargo_summary"] = UIKit.lbl("", 15, UIKit.C_TEXT)
	cargo_card.add_child(_live["cargo_summary"])
	# 旧来の診断・他画面は carried を読んでいたため、用途を分けた見出しへ同じ参照を残す。
	# 現在の仕事は固定ヘッダーで、運搬容量はこのカードの見出しで常に確認できる。
	_live["carried"] = _live["cargo_summary"]
	_live["overview_cargo_items"] = HBoxContainer.new()
	_live["overview_cargo_items"].add_theme_constant_override("separation", 6)
	cargo_card.add_child(_live["overview_cargo_items"])
	_live["cargo_detail"] = _wrapped_label("", 13, UIKit.C_DIM)
	cargo_card.add_child(_live["cargo_detail"])
	if include_store:
		_live["store_now"] = UIKit.button("今の採取分を収納", func(): w.ai.store_now(); _update_live())
		_live["store_now"].custom_minimum_size = Vector2(0, 30)
		cargo_card.add_child(_live["store_now"])


## 画像と短い札を中心にしたカード。文章を読まなくても装備／運搬を判別できるようにする。
func _visual_card(parent: Container, title: String, edge: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("20242b"), edge.darkened(0.25), 2, 7))
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	panel.add_child(body)
	body.add_child(UIKit.lbl(title, 16, edge.lightened(0.25)))
	return body


func _empty_item_frame(label: String, px: float = 40.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("161a20"), Color("3c4655"), 2, 4))
	var empty := UIKit.lbl("—", 22, UIKit.C_DIM, px)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty.custom_minimum_size = Vector2(px, px)
	panel.add_child(empty)
	panel.tooltip_text = label + "：なし"
	return panel


func _add_item_slot(parent: Container, label: String, item: int, amount: int = 0) -> void:
	var slot := VBoxContainer.new()
	slot.custom_minimum_size = Vector2(82, 0)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_constant_override("separation", 1)
	parent.add_child(slot)
	var frame: Control = ItemWidgets.icon_frame(item, 40.0) if item >= 0 else _empty_item_frame(label)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.add_child(frame)
	var short_name := ItemDB.name_of(item) if item >= 0 else "なし"
	var caption := "%s\n%s%s" % [label, short_name, " ×%d" % amount if amount > 0 else ""]
	var name := UIKit.lbl(caption, 11, UIKit.C_TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(name)
	slot.tooltip_text = "%s：%s%s" % [label, short_name, " ×%d" % amount if amount > 0 else ""]


func _cargo_items(w) -> Array:
	var items: Dictionary = {}
	if w.carrying == GameData.Item.CARCASS:
		items = w.carcass_cargo.duplicate()
	elif w.ai.state in [CharacterAI.State.HAUL_TAKE, CharacterAI.State.HAUL_MOVE]:
		items = w.ai.haul_recipe.get("in", {}).duplicate()
	elif w.carrying >= 0:
		items[w.carrying] = w.carry_n
		for item in w.carry_bonus:
			items[item] = int(items.get(item, 0)) + int(w.carry_bonus[item])
	elif w.ai.state in [CharacterAI.State.REFUEL_TAKE, CharacterAI.State.REFUEL_MOVE, CharacterAI.State.REFUEL]:
		items[GameData.Item.FUEL] = 0
	elif w.ai.state in [CharacterAI.State.REPAIR_TAKE, CharacterAI.State.REPAIR_MOVE, CharacterAI.State.REPAIR]:
		items[GameData.Item.REPAIR_KIT] = 0
	var list: Array = []
	for item in items:
		if int(items[item]) >= 0:
			list.append({"item": int(item), "amount": int(items[item])})
	list.sort_custom(func(a, b): return ItemDB.order_of(a["item"]) < ItemDB.order_of(b["item"]))
	return list


func _refresh_visual_slots(w) -> void:
	if _live.has("overview_equipment_slots"):
		var equipment: Container = _live["overview_equipment_slots"]
		UIKit.clear(equipment)
		_add_item_slot(equipment, "武器", w.weapon)
		_add_item_slot(equipment, "補助", w.work_support)
		_add_item_slot(equipment, "採掘", int(w.tools.get("mine", -1)))
		_add_item_slot(equipment, "伐採", int(w.tools.get("chop", -1)))
	if _live.has("overview_cargo_items"):
		var cargo_box: Container = _live["overview_cargo_items"]
		UIKit.clear(cargo_box)
		var cargo_items := _cargo_items(w)
		if cargo_items.is_empty():
			_add_item_slot(cargo_box, "荷物", -1)
		else:
			for entry in cargo_items:
				_add_item_slot(cargo_box, "運搬", int(entry["item"]), int(entry["amount"]))


func _items_text(items: Dictionary) -> String:
	var parts: Array[String] = []
	for it in items:
		var n: int = int(items[it])
		if n > 0:
			parts.append("%s ×%d" % [ItemDB.name_of(int(it)), n])
	return "、".join(PackedStringArray(parts)) if not parts.is_empty() else "なし"


func _recipe_destination(recipe: Dictionary) -> String:
	if recipe.has("build"):
		return "%sの建設場所" % FacilityDB.name_of(String(recipe["build"]))
	var station := String(recipe.get("station", ""))
	return "%sへ" % FacilityDB.name_of(station) if not station.is_empty() else "加工設備へ"


func _cargo_status(w) -> Dictionary:
	var a = w.ai
	if a.state in [CharacterAI.State.MISSION_RECOVERY_MOVE, CharacterAI.State.MISSION_RECOVERY_LOAD]:
		return {"main": "依頼の遺失物を回収中", "detail": "%sの遺失地点 → 移動拠点（専用荷物・通常素材ではありません）" % game.town.recovery_target_text()}
	if a.state == CharacterAI.State.MISSION_RECOVERY_RETURN or game.town.recovery_carried_by(w):
		return {"main": "依頼の遺失物を運搬中", "detail": "遺失地点 → 移動拠点（専用荷物・重量%d）" % TownDB.RECOVERY_PARCEL_WEIGHT}
	if a.state == CharacterAI.State.HAUL_TAKE:
		return {"main": "材料を取りに行っています", "detail": "%s → %s" % [_items_text(a.haul_recipe.get("in", {})), _recipe_destination(a.haul_recipe)]}
	if a.state == CharacterAI.State.HAUL_MOVE:
		return {"main": "加工材料を運搬中", "detail": "%s → %s" % [_items_text(a.haul_recipe.get("in", {})), _recipe_destination(a.haul_recipe)]}
	if a.state == CharacterAI.State.XFER_TAKE or a.state == CharacterAI.State.XFER_MOVE:
		var destination := "作業場" if a.xfer_dir == "to_workshop" else "倉庫"
		var item_name := ItemDB.name_of(a.xfer_item) if a.xfer_item >= 0 else "素材"
		var amount: int = w.carry_n if w.carrying >= 0 else 0
		return {"main": "倉庫・作業場の移し替え", "detail": "%s%s → %s" % [item_name, " ×%d" % amount if amount > 0 else "を取りに行く", destination]}
	if a.state in [CharacterAI.State.REFUEL_TAKE, CharacterAI.State.REFUEL_MOVE, CharacterAI.State.REFUEL]:
		return {"main": "燃料を補給中", "detail": "%s → 機関室" % (ItemDB.name_of(w.carrying) if w.carrying >= 0 else "燃料を取りに行く")}
	if a.state in [CharacterAI.State.REPAIR_TAKE, CharacterAI.State.REPAIR_MOVE, CharacterAI.State.REPAIR]:
		return {"main": "修理資材を運搬中", "detail": "%s → 修理箇所" % (ItemDB.name_of(w.carrying) if w.carrying >= 0 else "応急修理板を取りに行く")}
	if w.carrying == GameData.Item.CARCASS:
		return {"main": "獲物の素材を持ち帰り中", "detail": "%s → 倉庫" % _items_text(w.carcass_cargo)}
	if w.carrying >= 0:
		var extras := _items_text(w.carry_bonus)
		var detail := "%s ×%d → 倉庫" % [ItemDB.name_of(w.carrying), w.carry_n]
		if extras != "なし":
			detail += "（副産物: %s）" % extras
		return {"main": "持ち帰り中", "detail": detail}
	return {"main": "今は運搬中の荷物なし", "detail": "持ち帰る資源・加工材料・補給物はありません"}


func _equipment_summary(w) -> String:
	var parts: Array[String] = []
	if w.weapon >= 0:
		parts.append("武器: " + ItemDB.name_of(w.weapon))
	if w.work_support >= 0:
		parts.append("仕事補助: " + ItemDB.name_of(w.work_support))
	for slot in GatherDB.SLOTS:
		var item: int = int(w.tools.get(slot, -1))
		if item >= 0:
			parts.append("%s: %s" % [GatherDB.SLOTS[slot], ItemDB.name_of(item)])
	return " ／ ".join(PackedStringArray(parts)) if not parts.is_empty() else "使用中の装備はありません"


func _important_warning(w) -> String:
	var parts: Array[String] = []
	if w.down:
		parts.append("戦闘不能")
	if w.hp < CrewStatusDB.WARN_LINE["hp"]:
		parts.append("HP低下")
	if w.hunger < CrewStatusDB.WARN_LINE["hunger"]:
		parts.append("空腹")
	if w.fatigue >= CrewStatusDB.WARN_LINE["fatigue"]:
		parts.append("疲労が高い")
	if w.mental >= CrewStatusDB.Mental.BAD:
		parts.append("精神:" + CrewStatusDB.MENTAL_NAMES[w.mental])
	return "重要な不調：" + (" / ".join(PackedStringArray(parts)) if not parts.is_empty() else "なし")


## 一覧の閲覧では追従を変えず、この操作だけで世界側の選択へ渡す。
func _follow_worker() -> void:
	if not _follow_reason(_worker).is_empty():
		_update_follow_control()
		return
	game._select(_worker)
	close()


func _follow_reason(w) -> String:
	if not is_instance_valid(w) or not game.workers.has(w):
		return "対象の仲間が見つかりません。"
	if w.away:
		return "遠征中は画面で選択・追従できません。"
	if not w.visible:
		return "現在表示されていない仲間は、画面で選択・追従できません。"
	return ""


func _update_follow_control() -> void:
	if not _header.has("follow"):
		return
	var reason := _follow_reason(_worker)
	var button: Button = _header["follow"]
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if not reason.is_empty() else "管理画面を閉じ、この仲間を画面で選択・追従します。Escキーで追従を解除できます。"


## 生活行動は自動。ここでは個体のAIへ促しを伝え、作業や予約を直接変更しない。
func _build_life_controls(w, include_rest := true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	row.add_child(ItemWidgets.chip("生活は自動", Color("526b7d"), 12))
	for action in (["rest", "eat"] if include_rest else ["eat"]):
		var kind: String = action
		var text := "休憩を促す" if kind == "rest" else "食事を促す"
		var button := UIKit.button(text, func(): _request_life_action(w, kind))
		button.custom_minimum_size = Vector2(150, 32)
		row.add_child(button)
		_live["life_%s" % kind] = button
	_live["life_pending"] = _wrapped_label("", 12, UIKit.C_DIM)
	_body.add_child(_live["life_pending"])


func _request_life_action(w, action: String) -> void:
	if is_instance_valid(w) and w == _worker:
		w.ai.request_life_action(action)
	_update_live()


func _request_header_rest() -> void:
	_request_life_action(_worker, "rest")


func _request_return() -> void:
	if is_instance_valid(_worker) and game.workers.has(_worker):
		if _worker.ai.return_request:
			_worker.ai.cancel_return()
		else:
			_worker.ai.request_return()
	_update_live()


func _toggle_recall_exempt() -> void:
	if is_instance_valid(_worker) and game.workers.has(_worker):
		_worker.recall_exempt = not _worker.recall_exempt
	_update_live()

func _request_rescue() -> void:
	if not is_instance_valid(_worker) or not game.workers.has(_worker): return
	var record: Dictionary = game.rescue.record_for(_worker)
	if _worker.down:
		if bool(record.get("expired", false)):
			game.rescue.revive_at_city(_worker)
		else:
			for carrier in game.workers:
				if game.rescue.assign(carrier, _worker): break
	elif _worker.ai.post_rescue_wait:
		game.rescue.resume(_worker)
	else:
		for target in game.workers:
			if target.down and game.rescue.assign(_worker, target): break
	_update_live()


func _request_header_repair() -> void:
	if is_instance_valid(_worker) and game.workers.has(_worker):
		if _worker.ai.manual_job == GameData.Job.REPAIR:
			_worker.ai.cancel_manual_repair()
		else:
			game.request_repair(_worker)
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


## 個人武器1枠と既存の採取道具。全員共通の自動設定と、閲覧中の1人の手動操作を分ける。
func _build_tools(w) -> void:
	_section("装備")
	var top_cards := HBoxContainer.new()
	top_cards.add_theme_constant_override("separation", 10)
	_body.add_child(top_cards)
	var weapon_card := _visual_card(top_cards, "武器", Color("c9a6f2"))
	_live["weapon"] = _wrapped_label("", 14)
	weapon_card.add_child(_live["weapon"])
	_live["weapon_visual"] = HBoxContainer.new()
	weapon_card.add_child(_live["weapon_visual"])
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 5)
	weapon_card.add_child(weapon_row)
	_live["weapon_equip"] = UIKit.button("簡易槍を装備", func():
		if is_instance_valid(w) and w == _worker: game.equip_weapon(w)
		_update_live())
	_live["weapon_off"] = UIKit.button("外して倉庫へ", func():
		if is_instance_valid(w) and w == _worker: game.unequip_weapon(w)
		_update_live())
	weapon_row.add_child(_live["weapon_equip"])
	weapon_row.add_child(_live["weapon_off"])
	_live["weapon_reason"] = _wrapped_label("", 13, UIKit.C_DIM)
	weapon_card.add_child(_live["weapon_reason"])
	_add_details_toggle(weapon_card, ItemDB.effect_text(GameData.Item.SIMPLE_SPEAR))

	var support_card := _visual_card(top_cards, "仕事補助", Color("c9b68b"))
	_live["work_support"] = _wrapped_label("", 15)
	support_card.add_child(_live["work_support"])
	_live["work_support_visual"] = HBoxContainer.new()
	support_card.add_child(_live["work_support_visual"])
	var work_support_row := HBoxContainer.new()
	work_support_row.add_theme_constant_override("separation", 5)
	support_card.add_child(work_support_row)
	_live["work_support_equip"] = UIKit.button("背負いフレームを装備", func():
		if is_instance_valid(w) and w == _worker: game.equip_work_support(w)
		_update_live())
	_live["work_support_off"] = UIKit.button("外して倉庫へ", func():
		if is_instance_valid(w) and w == _worker: game.unequip_work_support(w)
		_update_live())
	work_support_row.add_child(_live["work_support_equip"])
	work_support_row.add_child(_live["work_support_off"])
	_live["handcart"] = UIKit.button("手押し車を装備", func():
		if is_instance_valid(w) and w == _worker: game.equip_work_support(w, GameData.Item.HANDCART)
		_update_live())
	work_support_row.add_child(_live["handcart"])
	_live["work_support_reason"] = _wrapped_label("", 13, UIKit.C_DIM)
	support_card.add_child(_live["work_support_reason"])
	_add_details_toggle(support_card, ItemDB.effect_text(GameData.Item.HAUL_FRAME) + "\n" + ItemDB.effect_text(GameData.Item.HANDCART))

	_section("採取道具")
	_live["tool_auto"] = UIKit.button("", _toggle_tool_auto)
	_live["tool_auto"].custom_minimum_size = Vector2(0, 32)
	_body.add_child(_live["tool_auto"])
	var tool_cards := HBoxContainer.new()
	tool_cards.add_theme_constant_override("separation", 10)
	_body.add_child(tool_cards)
	for slot in GatherDB.SLOTS:
		var s: String = slot
		var tool_card := _visual_card(tool_cards, GatherDB.SLOTS[s] + "道具", Color("a8b5d6"))
		_live["tool_%s" % s] = _wrapped_label("", 15)
		tool_card.add_child(_live["tool_%s" % s])
		_live["tool_visual_%s" % s] = HBoxContainer.new()
		_live["tool_visual_%s" % s].add_theme_constant_override("separation", 4)
		tool_card.add_child(_live["tool_visual_%s" % s])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		tool_card.add_child(row)
		var choices := OptionButton.new()
		choices.custom_minimum_size = Vector2(174, 32)
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
		tool_card.add_child(_live["tool_reason_%s" % s])
		_live["yield_%s" % s] = _wrapped_label("", 13, UIKit.C_DIM)
		_live["yield_%s" % s].visible = false
		tool_card.add_child(_live["yield_%s" % s])
		var yield_button := UIKit.button("採取効果を表示", func(): _live["yield_%s" % s].visible = not _live["yield_%s" % s].visible)
		yield_button.custom_minimum_size = Vector2(0, 26)
		tool_card.add_child(yield_button)
	_body.add_child(_wrapped_label("採取効果の詳細は各枠で表示できます。実際の持ち帰り数は袋の上限により変わります。", 12, UIKit.C_DIM))


func _add_details_toggle(parent: Container, detail: String) -> void:
	var details := _wrapped_label(detail, 12, UIKit.C_DIM)
	details.visible = false
	var button := UIKit.button("効果・注意を表示", func(): details.visible = not details.visible)
	button.custom_minimum_size = Vector2(0, 26)
	button.tooltip_text = "短い要約だけでは足りないときに、既存の詳細説明を開きます。"
	parent.add_child(button)
	parent.add_child(details)


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
		_section("部署")
		_body.add_child(_wrapped_label("左上の部署フィルター、またはここから部署を選ぶと、Lvと解放内容を確認できます。", 14, UIKit.C_DIM))
		var choices := HBoxContainer.new()
		choices.add_theme_constant_override("separation", 6)
		_body.add_child(choices)
		for f in GameData.visible_departments():
			var button := UIKit.button("%s\nLv%d・%d人" % [GameData.FIELD_NAMES[f], GameData.field_level(game.workers, f), _members(f).size()], func(): _set_filter(f); _build_detail())
			button.custom_minimum_size = Vector2(118, 54)
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			choices.add_child(button)
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
	_update_follow_control()
	_update_header(w)
	if not is_instance_valid(w) or not game.workers.has(w):
		return
	if _live.has("cargo_summary"):
		var cargo := _cargo_status(w)
		_live["cargo_summary"].text = "%s　容量%d" % [String(cargo["main"]), w.carry_limit()]
		_live["cargo_detail"].text = String(cargo["detail"])
		_refresh_visual_slots(w)
		if _live.has("store_now"):
			var store_button: Button = _live["store_now"]
			# store_now は採取中だけ既存の移動処理へ渡す。表示更新では状態を変えず、可否を状態から復元する。
			var store_enabled: bool = w.carrying >= 0 and not w.down and not w.away and not w.ai.retreating and not w.ai.manual_attack and game.operations.stance != "recall" and w.ai.state in [CharacterAI.State.GATHER, CharacterAI.State.MOVE_TO_STORAGE, CharacterAI.State.STORE]
			store_button.disabled = not store_enabled
			store_button.tooltip_text = "採取中の荷物を先に倉庫へ届けます。" if store_enabled else "採取中または倉庫へ向かっている荷物があるときだけ使えます。"
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
		_live["life_pending"].text = "受付中：%sを促す（安全な区切りで実行）" % ("休憩" if pending == "rest" else "食事") if not pending.is_empty() else ""
	if _live.has("weapon"):
		_live["weapon"].text = "武器：%s ／ 倉庫の簡易槍 %d" % [ItemDB.name_of(w.weapon) if w.weapon >= 0 else "なし", game.storage.count_of(GameData.Item.SIMPLE_SPEAR)]
		_refresh_item_visual("weapon_visual", "武器", w.weapon)
		var equip_reason: String = game.weapon_change_reason(w, true)
		var off_reason: String = game.weapon_change_reason(w, false)
		_live["weapon_equip"].disabled = not equip_reason.is_empty()
		_live["weapon_off"].disabled = not off_reason.is_empty()
		_live["weapon_reason"].text = off_reason if w.weapon >= 0 else equip_reason
		_live["weapon_reason"].visible = not _live["weapon_reason"].text.is_empty()
	if _live.has("work_support"):
		_live["handcart"].disabled = not game.work_support_change_reason(w,true,GameData.Item.HANDCART).is_empty()
		_live["handcart"].tooltip_text = game.work_support_change_reason(w,true,GameData.Item.HANDCART)
		_live["work_support"].text = "仕事補助：%s ／ 倉庫のフレーム %d" % [ItemDB.name_of(w.work_support) if w.work_support >= 0 else "なし", game.storage.count_of(GameData.Item.HAUL_FRAME)]
		_refresh_item_visual("work_support_visual", "補助", w.work_support)
		var equip_reason: String = game.work_support_change_reason(w, true)
		var off_reason: String = game.work_support_change_reason(w, false)
		_live["work_support_equip"].disabled = not equip_reason.is_empty()
		_live["work_support_off"].disabled = not off_reason.is_empty()
		_live["work_support_reason"].text = off_reason if w.work_support >= 0 else equip_reason
		_live["work_support_reason"].visible = not _live["work_support_reason"].text.is_empty()
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
		_refresh_item_visual("tool_visual_%s" % slot, GatherDB.SLOTS[slot], cur)
		if _live.has("tool_select_%s" % slot):
			_update_tool_controls(w, slot)
		var parts: Array[String] = []
		for kind in GatherDB.POINTS:
			if GatherDB.POINTS[kind]["slot"] != slot:
				continue
			parts.append(GatherDB.result_text(kind, cur, w.ranks.get(GameData.Field.GATHERER, 0), w.field_mult(GameData.Field.GATHERER)))
		_live["yield_%s" % slot].text = " ／ ".join(PackedStringArray(parts))
	for job in GameData.job_list():
		if job != GameData.Job.REST and _live.has("eff_%d" % job):
			_live["eff_%d" % job].text = "%s ×%.2f" % [GameData.JOB_NAMES[job], w.skill_mult(job)]
		if _live.has("prio_%d" % job):
			var n: int = w.priorities.get(job, 0)
			_live["prio_%d" % job].text = ("★".repeat(n) + "☆".repeat(GameData.MAX_PRIORITY - n)) if n > 0 else "─ やらない ─"


func _refresh_item_visual(key: String, label: String, item: int) -> void:
	if not _live.has(key):
		return
	var box: Container = _live[key]
	UIKit.clear(box)
	_add_item_slot(box, label, item)


func _update_header(w) -> void:
	if not is_instance_valid(w) or not game.workers.has(w) or _header.is_empty():
		return
	_header["portrait"].texture = _portrait_of(w)
	var number: int = game.crew_alerts.number_of(w) if game.crew_alerts != null else 0
	_header["name"].text = ("No.%02d " % number if number > 0 else "") + w.char_name
	var rescue_status: String = game.rescue.status_text(w) if game.rescue != null else ""
	var action_text: String = w.ai.status_text()
	if not rescue_status.is_empty():
		action_text = rescue_status
	elif w.ai.rescue_target >= 0:
		action_text = "仲間を救助中"
	elif w.ai.post_rescue_wait:
		action_text = "手当て完了：作業再開待ち"
	_header["action"].text = "現在行動：" + action_text
	var directives: Array[String] = []
	if w.ai.return_request:
		directives.append("帰還指示：受付中")
	if w.ai.manual_job == GameData.Job.REPAIR:
		directives.append("\u4fee\u7406\u6307\u793a: \u53d7\u4ed8\u4e2d")
	if not w.ai.life_request.is_empty():
		directives.append(("休憩" if w.ai.life_request == "rest" else "食事") + "：受付中")
	var instruction_text := "自動作業中"
	if not rescue_status.is_empty() or w.ai.rescue_target >= 0:
		instruction_text = "救助対応中"
	elif w.ai.post_rescue_wait:
		instruction_text = "手当て完了：再開待ち"
	_header["instruction"].text = " / ".join(PackedStringArray(directives)) if not directives.is_empty() else instruction_text
	var warning := _important_warning(w)
	if not rescue_status.is_empty(): warning = rescue_status
	var has_warning := warning != "重要な不調：なし"
	_header["warning"].visible = has_warning
	_header["warning"].text = warning.replace("重要な不調：", "不調：") if has_warning else ""
	_header["warning"].modulate = CrewStatusDB.COLOR_DANGER if has_warning else Color.WHITE
	var return_reason: String = "" if w.ai.return_request else w.ai.return_action_reason()
	var returning: Button = _header["return"]
	returning.disabled = not return_reason.is_empty()
	returning.text = "\u9000\u5374\u3092\u89e3\u9664" if w.ai.return_request else "\u9000\u5374\u547d\u4ee4"
	returning.tooltip_text = return_reason if not return_reason.is_empty() else "この仲間だけに帰還を指示します。全員撤退は行いません。"
	if w.ai.return_request:
		returning.tooltip_text = "\u9000\u5374\u3092\u89e3\u9664\u3057\u3001\u5e30\u9084\u5f8c\u306e\u6b21\u306e\u5b89\u5168\u306a\u6642\u70b9\u304b\u3089\u81ea\u5f8b\u884c\u52d5\u306b\u623b\u3057\u307e\u3059\u3002"
	var exempt: Button = _header["recall_exempt"]
	exempt.text = "全体帰還：対象外" if w.recall_exempt else "全体帰還：対象"
	exempt.tooltip_text = "この仲間は全体帰還の対象外です。個別帰還と屋外でのHP30%以下の安全帰還は優先されます。"
	var rescue: Button = _header["rescue"]
	if w.down:
		var rec: Dictionary = game.rescue.record_for(w)
		if bool(rec.get("expired", false)):
			rescue.text = "都市で回復（%d Cr）" % TownDB.REVIVAL_COST
			rescue.disabled = not game.town.location_ok() or game.town.credits < TownDB.REVIVAL_COST
			rescue.tooltip_text = "期限切れの仲間は拠点へ回収後、都市で回復できます。"
		else:
			rescue.text = "救助担当を指定"
			rescue.disabled = int(rec.get("carrier", -1)) >= 0
			rescue.tooltip_text = "救助担当は自動で割り当てません。救助する仲間を指定します。"
	elif w.ai.post_rescue_wait:
		rescue.text = "作業を再開"
		rescue.disabled = false
		rescue.tooltip_text = "手当て完了後の再開は、プレイヤーが決めます。"
	else:
		var has_target := false
		for target in game.workers:
			if target.down: has_target = true
		rescue.text = "救助へ向かう"
		rescue.disabled = not has_target or game.rescue.is_carrier(w)
		rescue.tooltip_text = "戦闘不能の仲間を選び、救助担当にします。"
	var repair: Button = _header["repair"]
	var info: Dictionary = game.repair_order_info()
	var repair_reason: String = ""
	if w.ai.manual_job != GameData.Job.REPAIR:
		if info["assigned"] != null:
			repair_reason = "\u4ed6\u306e\u4ef2\u9593\u304c\u4fee\u7406\u6307\u793a\u3092\u5f15\u304d\u53d7\u3051\u3066\u3044\u307e\u3059"
		elif int(info["missing"]) > 0:
			repair_reason = "\u4fee\u7406\u30ad\u30c3\u30c8%d\u500b\u304c\u4e0d\u8db3\u3067\u3059" % int(info["missing"])
		else:
			repair_reason = w.ai.manual_repair_reason()
	repair.text = "\u4fee\u7406\u4f9d\u983c\u3092\u53d6\u6d88" if w.ai.manual_job == GameData.Job.REPAIR else "\u4fee\u7406\u3092\u4efb\u305b\u308b"
	repair.disabled = w.ai.manual_job != GameData.Job.REPAIR and not repair_reason.is_empty()
	repair.tooltip_text = "\u4fee\u7406\u4f9d\u983c\u3092\u53d6\u6d88\u3057\u3066\u512a\u5148\u5ea6\u306b\u623b\u3057\u307e\u3059\u3002" if w.ai.manual_job == GameData.Job.REPAIR else (repair_reason if not repair_reason.is_empty() else "\u73fe\u5730\u4fee\u7406: \u4fee\u7406\u30ad\u30c31\u500b\u30fb1.2\u79d2\u3002\u4fee\u7406\u5f8c\u306f\u512a\u5148\u5ea6\u884c\u52d5\u306b\u623b\u308a\u307e\u3059\u3002")
	var rest_reason: String = w.ai.life_action_reason("rest")
	var rest: Button = _header["rest"]
	rest.disabled = not rest_reason.is_empty()
	rest.tooltip_text = rest_reason if not rest_reason.is_empty() else "この仲間だけに休憩を促します。受付後は安全な区切りでAIが実行します。"


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
