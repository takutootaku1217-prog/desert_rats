class_name PolicyUI
extends CanvasLayer
## 運営の方針（Pキー）。仲間は自動で動くので、プレイヤーは「何を優先するか」だけを決める。
##  - 加工の優先: レシピごとの★（0 = 作らない）
##  - 回収の優先: 木材・石・鉄鉱石ごとの★（0 = 拾わない。獲物は常に拾う）
##  - 狩る生物: 生物ごとに 狩る / 見逃す
##  - テスト用の購入（ショップは第1段階では作らない）

var game
var _overlay: Control
var _body: VBoxContainer
var _page := 0                   # 0 = 方針（回収・加工・狩猟） / 1 = 積載の割り当て（data/cargo.gd）


func _ready() -> void:
	layer = 21
	var btn := UIKit.button("運営の方針 (P)", toggle)
	btn.position = Vector2(1000, 290)
	btn.custom_minimum_size = Vector2(272, 32)
	add_child(btn)
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
	var title := UIKit.lbl("運営の方針", 22, UIKit.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.button("閉じる (P / Esc)", close))
	root.add_child(UIKit.lbl("仲間は自動で動きます。ここでは「何を優先するか」を決めます。★0 はやらない。", 13, UIKit.C_DIM))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	root.add_child(_body)


func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		_overlay.visible = true
		_rebuild()


func close() -> void:
	_overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			toggle()
		elif event.keycode == KEY_ESCAPE and _overlay.visible:
			close()


func _rebuild() -> void:
	UIKit.clear(_body)
	_body.add_child(_tabs())
	if _page == 1:
		_build_cargo_page()
		return
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	_body.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 3)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	cols.add_child(right)

	# 加工の優先
	left.add_child(UIKit.lbl("── 加工の優先（材料が揃い、作り置きが足りない物を作る） ──", 14, UIKit.C_DIM))
	for r in GameData.RECIPES:
		var id: String = r["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		left.add_child(row)
		row.add_child(UIKit.lbl(r["name"], 15, UIKit.C_TEXT, 200))
		row.add_child(_stepper(func(): return game.recipe_priority.get(id, 0),
				func(v): game.recipe_priority[id] = v))
		var extra := "（炉で燃料%d使用）" % int(r["tank_fuel"]) if r["tank_fuel"] > 0.0 else ""
		row.add_child(UIKit.lbl(GameData.recipe_text(r) + extra, 13, UIKit.C_DIM))
	var tgt: Array = []
	for it in GameData.STOCK_TARGET:
		tgt.append("%s %d" % [GameData.ITEM_NAMES[it], GameData.STOCK_TARGET[it]])
	left.add_child(UIKit.lbl("作り置きの上限: " + "、".join(PackedStringArray(tgt)), 12, UIKit.C_DIM))

	# 回収の優先
	right.add_child(UIKit.lbl("── 回収の優先（獲物は常に拾う） ──", 14, UIKit.C_DIM))
	for it in GameData.GROUND_ITEMS:
		var item: int = it
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		right.add_child(row)
		row.add_child(UIKit.lbl(GameData.ITEM_NAMES[item], 15, UIKit.C_TEXT, 90))
		row.add_child(_stepper(func(): return game.gather_policy.get(item, 0),
				func(v): game.gather_policy[item] = v))

	# 狩る生物
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	right.add_child(sp)
	right.add_child(UIKit.lbl("── 狩る生物（すべて無害。追うと逃げる） ──", 14, UIKit.C_DIM))
	for s in GameData.CREATURES:
		var species: String = s
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		right.add_child(row)
		row.add_child(UIKit.lbl(GameData.CREATURES[species]["name"], 15, UIKit.C_TEXT, 90))
		var on: bool = game.hunt_allowed(species)
		var b := UIKit.button("狩る" if on else "見逃す", func():
			game.hunt_policy[species] = not game.hunt_policy.get(species, false)
			_rebuild())
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(84, 28)
		UIKit.style(b, on)
		row.add_child(b)
		row.add_child(UIKit.lbl(GameData.drops_text(species), 13, UIKit.C_DIM))

	# テスト用の購入
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 8)
	right.add_child(sp2)
	right.add_child(UIKit.lbl("── テスト用: 生物を購入（ショップは今後） ──", 14, UIKit.C_DIM))
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 6)
	right.add_child(br)
	for s in GameData.CREATURES:
		var species: String = s
		var b := UIKit.button(GameData.CREATURES[species]["name"], func(): game.test_purchase(species))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(96, 28)
		br.add_child(b)
	right.add_child(UIKit.lbl("押すと、その生物を解体した素材が倉庫に入ります", 12, UIKit.C_DIM))


## 上のページ切り替え（方針 / 積載の割り当て）
func _tabs() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for spec in [[0, "方針（加工・回収・狩猟）"], [1, "積載の割り当て"]]:
		var p: int = spec[0]
		var b := UIKit.button(spec[1], func():
			_page = p
			_rebuild())
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(240, 30)
		UIKit.style(b, _page == p)
		h.add_child(b)
	return h


## 積載の割り当て: 区画ごとの積載量を、素材ごとの枠に振り分ける。枠がいっぱいの素材は回収・狩猟・加工をしない。
func _build_cargo_page() -> void:
	var st = game.storage
	_body.add_child(UIKit.lbl("倉庫の積載量は限られています。素材ごとに「いくつまで置くか」（枠）を決めます。枠の合計は積載量まで。"
			+ "\n増やしたい素材があれば、別の素材の枠を減らしてください。枠がいっぱいの素材は集めず、入りきらない分は捨てます。", 13, UIKit.C_DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	_body.add_child(cols)
	for bay in [CargoDB.Bay.RAW, CargoDB.Bay.PRODUCT]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.custom_minimum_size = Vector2(560, 0)
		cols.add_child(col)
		var cap: int = st.capacity_of(bay)
		var left: int = st.unallocated_in(bay)
		col.add_child(UIKit.lbl("── %s（積載量 %d） ──" % [CargoDB.BAY_NAMES[bay], cap], 15, UIKit.C_ACCENT))
		var budget := "割り当て %d / %d　" % [st.allocated_in(bay), cap]
		budget += "あと %d 増やせる" % left if left > 0 else "余りなし（増やすなら他を減らす）"
		col.add_child(UIKit.lbl(budget, 13, Color("cfe6ff") if left > 0 else UIKit.C_DIM))
		for it in CargoDB.items_of(bay):
			col.add_child(_quota_row(it))
	var used_txt := ""
	for bay in [CargoDB.Bay.RAW, CargoDB.Bay.PRODUCT]:
		used_txt += "%s %d/%d　" % [CargoDB.BAY_NAMES[bay], st.used_in(bay), st.capacity_of(bay)]
	_body.add_child(UIKit.lbl("いま置いてある量: " + used_txt + "　捨てた累計: %d 個" % game.total_wasted, 13, UIKit.C_DIM))
	var tgt: Array = []
	for it in GameData.STOCK_TARGET:
		tgt.append("%s%d" % [GameData.ITEM_NAMES[it], GameData.STOCK_TARGET[it]])
	_body.add_child(UIKit.lbl("加工品の「作り置きの上限」（%s）は、枠がそれより小さければ枠に合わせます。" % "・".join(PackedStringArray(tgt)), 12, UIKit.C_DIM))


## 素材ひとつぶんの行: 名前 [－] 枠 [＋]  置いてある量のバー
func _quota_row(item: int) -> Control:
	var st = game.storage
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UIKit.lbl(GameData.ITEM_NAMES[item], 15, UIKit.C_TEXT, 84))
	var minus := UIKit.button("－", func():
		st.set_quota(item, st.quota_of(item) - CargoDB.QUOTA_STEP)
		_rebuild())
	var plus := UIKit.button("＋", func():
		st.set_quota(item, st.quota_of(item) + CargoDB.QUOTA_STEP)
		_rebuild())
	for b in [minus, plus]:
		b.custom_minimum_size = Vector2(30, 26)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(minus)
	var q := UIKit.lbl("枠 %d" % st.quota_of(item), 15, Color("ffd24a"), 64)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(q)
	h.add_child(plus)
	# 置いてある量のバー（枠に対する割合。8割で橙、いっぱいで赤）
	var n: int = st.count_of(item)
	var quota: int = st.quota_of(item)
	var bar := ProgressBar.new()
	bar.max_value = float(maxi(1, quota))
	bar.value = minf(float(n), bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 9)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := Color("7be07b")
	if n >= quota:
		col = Color("e0533d")
	elif float(n) >= float(quota) * CargoDB.WARN_RATIO:
		col = Color("f0c040")
	bar.add_theme_stylebox_override("background", UIKit.box(Color("0d0f12"), Color("0d0f12"), 0, 0))
	bar.add_theme_stylebox_override("fill", UIKit.box(col, col, 0, 0))
	h.add_child(bar)
	var note := "いま %d" % n
	if quota <= 0:
		note += "（集めない）"
	elif n >= quota:
		note += "（いっぱい）"
	h.add_child(UIKit.lbl(note, 13, UIKit.C_DIM))
	return h


## ★0〜5 を －／＋ で変える部品。
func _stepper(getter: Callable, setter: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var stars := UIKit.lbl("", 15, Color("ffd24a"), 92)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var refresh := func():
		var n: int = getter.call()
		stars.text = ("★".repeat(n) + "☆".repeat(GameData.MAX_PRIORITY - n)) if n > 0 else "─ しない ─"
	var minus := UIKit.button("－", func():
		setter.call(clampi(getter.call() - 1, 0, GameData.MAX_PRIORITY))
		refresh.call())
	var plus := UIKit.button("＋", func():
		setter.call(clampi(getter.call() + 1, 0, GameData.MAX_PRIORITY))
		refresh.call())
	for b in [minus, plus]:
		b.custom_minimum_size = Vector2(30, 26)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(minus)
	h.add_child(stars)
	h.add_child(plus)
	refresh.call()
	return h
