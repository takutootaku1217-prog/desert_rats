class_name ExpeditionUI
extends CanvasLayer
## 遠征（遺跡の探索）の画面。Xキーまたは右のボタンで開閉する。
## 左: 調査隊のメンバーを選ぶ（CrewPicker。最大3人）。右: 遺跡の情報・進め方・持ち物・成功率の目安・出発。
## 探索中は進み具合と記録、戻ったら結果を表示する。データは data/expeditions.gd、進行は scripts/expedition.gd。

var game
var _overlay: Control
var _picker: CrewPicker
var _right: VBoxContainer
var _approach := "normal"
var _kit := false
var _timer := 0.0


func _ready() -> void:
	layer = 22
	# 右のボタンは低い層に置く（運営の方針・仲間の管理などの画面を開いたとき、その下に隠れるように）
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 12
	add_child(btn_layer)
	var btn := UIKit.button("遠征 (X)", toggle)
	btn.position = Vector2(1000, 326)
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
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UIKit.lbl("遠征（遺跡の探索）", 22, UIKit.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.button("閉じる (X / Esc)", close))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	_picker = CrewPicker.new()
	_picker.source = func(): return _available()
	_picker.selection_changed.connect(_on_selection_changed)
	cols.add_child(_picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(820, 0)
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
	_picker.refresh()
	_rebuild()


func close() -> void:
	_overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X:
			toggle()
		elif event.keycode == KEY_ESCAPE and _overlay.visible:
			close()


func _process(delta: float) -> void:
	if _overlay != null and _overlay.visible:
		_timer -= delta
		if _timer <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_timer = 0.4
			_rebuild()


## 遠征に出られる仲間（すでに出かけている仲間・倒れている仲間は除く）
func _available() -> Array:
	var l: Array = []
	for w in game.workers:
		if not w.away and not w.down:
			l.append(w)
	return l


## 選びすぎたら、後から選んだぶんを外す
func _on_selection_changed() -> void:
	var l: Array = _picker.selected_list()
	if l.size() > ExpeditionDB.MAX_PARTY:
		for w in l.slice(ExpeditionDB.MAX_PARTY):
			_picker.selected.erase(w)
		_picker.refresh()
	_rebuild()


func _rebuild() -> void:
	if game == null:
		return
	UIKit.clear(_right)
	var ex: Expedition = game.expedition
	match ex.state:
		"offered":
			_build_offer(ex)
		"running":
			_build_running(ex)
		"done":
			_build_done(ex)
		_:
			_right.add_child(UIKit.lbl("いま調べられる遺跡はありません。", 18, UIKit.C_TEXT))
			_right.add_child(_note("旅の途中で、遺跡が見つかることがあります。見つかると、画面左下に知らせが出て、しばらくのあいだ調べられます。"
					+ "調査隊を出すと、その仲間は拠点にいなくなります。人手が減るぶん、拠点の作業が回りにくくなります。"))
			_right.add_child(_note("関門ごとに必要な分野の実力が違います。探索＝回収、罠＝開発、守護者＝戦闘、危険地帯＝医務。メンバーの組み合わせが大事です。"))


func _note(text: String, size: int = 13, color: Color = UIKit.C_DIM) -> Label:
	var l := UIKit.lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(600, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _build_offer(ex: Expedition) -> void:
	var d := ex.site()
	var members: Array = _picker.selected_list()
	_right.add_child(UIKit.lbl("%s（あと %d秒 調べられる）" % [d["name"], int(ceil(ex.offer_left))], 20, UIKit.C_ACCENT))
	_right.add_child(_note("関門 %d つ　難しさ %.1f　所要時間 約%d秒（標準）　持たせる食料: 1人につき %d個"
			% [d["steps"], d["difficulty"], int(d["duration"]), ExpeditionDB.FOOD_PER_MEMBER]))
	# 進め方
	_right.add_child(UIKit.lbl("── 進め方 ──", 14, UIKit.C_DIM))
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 6)
	_right.add_child(ar)
	for a in ExpeditionDB.APPROACHES:
		var aid: String = a["id"]
		var b := UIKit.button(a["name"], func():
			_approach = aid
			_rebuild())
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(150, 34)
		UIKit.style(b, aid == _approach)
		ar.add_child(b)
	_right.add_child(_note(ExpeditionDB.approach(_approach)["note"]))
	# 持ち物
	var kit_have: int = game.storage.count_of(GameData.Item.REPAIR_KIT)
	var cb := CheckBox.new()
	cb.text = "修理資材を1個持たせる（所持 %d。罠・守護者・危険地帯の最初の失敗の被害を防ぐ）" % kit_have
	cb.add_theme_font_override("font", GameData.font())
	cb.add_theme_color_override("font_color", UIKit.C_TEXT)
	cb.button_pressed = _kit
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on):
		_kit = on)
	_right.add_child(cb)
	# 調査隊の実力と成功率の目安
	_right.add_child(UIKit.lbl("── 調査隊の実力と、関門の成功率の目安 ──", 14, UIKit.C_DIM))
	if members.is_empty():
		_right.add_child(_note("左でメンバーを選んでください（最大%d人）。" % ExpeditionDB.MAX_PARTY, 14, UIKit.C_TEXT))
	else:
		var names: Array = []
		for w in members:
			names.append(w.char_name)
		_right.add_child(UIKit.lbl("調査隊: " + "・".join(PackedStringArray(names)), 15))
		for t in ["explore", "trap", "guardian", "hazard"]:
			var def: Dictionary = ExpeditionDB.STEPS[t]
			var first := ex.step_chance(members, t, 0, _approach)
			var last := ex.step_chance(members, t, d["steps"] - 1, _approach)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			_right.add_child(row)
			row.add_child(UIKit.lbl("%s（%s）" % [def["name"], GameData.FIELD_NAMES[def["field"]]], 14, UIKit.C_TEXT, 150))
			row.add_child(UIKit.lbl("実力 %.1f" % ex.power_of(members, def["field"]), 14, UIKit.C_DIM, 90))
			var col := Color("86efac") if last >= 0.7 else (Color("fde68a") if last >= 0.45 else Color("f87171"))
			row.add_child(UIKit.lbl("成功率 %d%%（最初）→ %d%%（最後）" % [int(round(first * 100.0)), int(round(last * 100.0))], 14, col))
	# 出発
	var why := ex.block_reason(members, _approach, _kit)
	var go := UIKit.button("調査隊を出発させる", func():
		if ex.start(_picker.selected_list(), _approach, _kit):
			_picker.selected.clear()
			_picker.refresh()
			_rebuild())
	go.alignment = HORIZONTAL_ALIGNMENT_CENTER
	go.custom_minimum_size = Vector2(260, 40)
	go.disabled = why != ""
	_right.add_child(go)
	if why != "":
		_right.add_child(_note(why, 13, Color("f87171")))


func _build_running(ex: Expedition) -> void:
	var d := ex.site()
	_right.add_child(UIKit.lbl("探索中: %s" % d["name"], 20, UIKit.C_ACCENT))
	var names: Array = []
	for w in ex.party:
		names.append(w.char_name)
	_right.add_child(UIKit.lbl("調査隊: %s（%s）" % ["・".join(PackedStringArray(names)), ExpeditionDB.approach(ex.approach_id)["name"]], 15))
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = ex.progress() * 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(500, 14)
	bar.add_theme_stylebox_override("background", UIKit.box(Color("0d0f12"), Color("3a3f4a"), 2, 0))
	bar.add_theme_stylebox_override("fill", UIKit.box(Color("7be07b"), Color("7be07b"), 0, 0))
	_right.add_child(bar)
	_right.add_child(UIKit.lbl("関門 %d / %d　成功%d 失敗%d" % [mini(ex.step_i + 1, ex.steps.size()), ex.steps.size(), ex.ok_count, ex.ng_count], 14, UIKit.C_DIM))
	_right.add_child(UIKit.lbl("── 記録 ──", 14, UIKit.C_DIM))
	for line in ex.log:
		_right.add_child(_note("・" + line, 14, UIKit.C_TEXT))


func _build_done(ex: Expedition) -> void:
	_right.add_child(UIKit.lbl("調査隊が戻ってきた", 20, UIKit.C_ACCENT))
	_right.add_child(_note(ex.summary(), 16, Color("fff7dc")))
	_right.add_child(UIKit.lbl("── 記録 ──", 14, UIKit.C_DIM))
	for line in ex.log:
		_right.add_child(_note("・" + line, 14, UIKit.C_TEXT))
