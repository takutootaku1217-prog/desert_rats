class_name StatusPanel
extends CanvasLayer
## 右上の拠点の状態（第1段階の最低限の表示）。
## 移動状態・燃料タンク・3つの耐久度・食料と在庫・加工の様子・累計を出す。

var game
var _head: Label
var _stock: Label
var _cargo: Label
var _proc: Label
var _totals: Label
var _bars := {}        # key -> ProgressBar
var _nums := {}        # key -> Label

const W := 272.0


func _ready() -> void:
	layer = 11
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("1b1e24", 0.92), Color("636b7a"), 4, 8))
	panel.position = Vector2(1000, 8)
	panel.custom_minimum_size = Vector2(W, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	panel.add_child(v)
	_head = UIKit.lbl("", 14, Color("fff7dc"))
	v.add_child(_head)
	for spec in [["fuel", "燃料"], ["hull", "車体"], ["drive", "走行装置"], ["machine", "加工設備"]]:
		v.add_child(_bar_row(spec[0], spec[1]))
	_stock = UIKit.lbl("", 13, Color("fff7dc"))
	v.add_child(_stock)
	_cargo = UIKit.lbl("", 12, Color("cfe6ff"))       # 積載量（素材棚・加工品置き場）
	v.add_child(_cargo)
	_proc = UIKit.lbl("", 13, Color("fde68a"))
	v.add_child(_proc)
	_totals = UIKit.lbl("", 12, UIKit.C_DIM)
	v.add_child(_totals)


func _bar_row(key: String, name: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(UIKit.lbl(name, 12, Color("cfe6ff"), 64))
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 9)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UIKit.box(Color("0d0f12"), Color("0d0f12"), 0, 0))
	bar.add_theme_stylebox_override("fill", UIKit.box(Color("7be07b"), Color("7be07b"), 0, 0))
	h.add_child(bar)
	var n := UIKit.lbl("", 12, Color("fff7dc"), 34)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(n)
	_bars[key] = bar
	_nums[key] = n
	return h


## 個数の表示。枠がいっぱいの素材には「満」を付ける（積載量）。
func _n(st, item: int) -> String:
	return "%d%s" % [st.count_of(item), "満" if st.is_full(item) else ""]


func _set_bar(key: String, value: float) -> void:
	var bar: ProgressBar = _bars[key]
	bar.value = value
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	fill.bg_color = Color("7be07b") if value > 50.0 else (Color("f0c040") if value > GameData.PART_BAD else Color("e0533d"))
	_nums[key].text = "%d" % int(value)


func _process(_d: float) -> void:
	if game == null or game.base == null:
		return
	var b = game.base
	var move := "拠点: 停止中"
	if game.scroll_speed > 0.0:
		if not b.has_fuel():
			move = "拠点: 燃料切れ・低速走行"
		elif b.condition(GameData.Part.DRIVE) < GameData.PART_BAD:
			move = "拠点: 走行装置が不調"
		else:
			move = "拠点: 進行中"
	_head.text = "%s\n速度 %d / 目標 %d  (↑↓キー)" % [move, int(game.scroll_speed), int(game.target_speed)]
	_set_bar("fuel", b.fuel / GameData.FUEL_CAP * 100.0)
	_set_bar("hull", b.condition(GameData.Part.HULL))
	_set_bar("drive", b.condition(GameData.Part.DRIVE))
	_set_bar("machine", b.condition(GameData.Part.MACHINE))
	var st = game.storage
	_stock.text = "食料 %s%s ／ 燃料 %s ／ 修理資材 %s\n肉%s 皮%s 骨%s 脂%s 木%s 石%s 鉱%s 鉄%s" % [
			_n(st, GameData.Item.FOOD), "（空腹!）" if game.hungry else "",
			_n(st, GameData.Item.FUEL), _n(st, GameData.Item.REPAIR_KIT),
			_n(st, GameData.Item.MEAT), _n(st, GameData.Item.HIDE), _n(st, GameData.Item.BONE),
			_n(st, GameData.Item.FAT), _n(st, GameData.Item.WOOD), _n(st, GameData.Item.STONE),
			_n(st, GameData.Item.IRON_ORE), _n(st, GameData.Item.IRON)]
	_stock.add_theme_color_override("font_color", Color("ff9a86") if game.hungry else Color("fff7dc"))
	# 積載量: 区画ごとの「置いてある量／積載量」。8割を超えると橙、枠がすべて埋まると赤。捨てた数も出す
	var raw_used: int = st.used_in(CargoDB.Bay.RAW)
	var prod_used: int = st.used_in(CargoDB.Bay.PRODUCT)
	var raw_cap: int = st.capacity_of(CargoDB.Bay.RAW)
	var prod_cap: int = st.capacity_of(CargoDB.Bay.PRODUCT)
	_cargo.text = "積載 素材棚 %d/%d ・ 加工品 %d/%d%s" % [raw_used, raw_cap, prod_used, prod_cap,
			(" ・ 捨てた%d" % game.total_wasted) if game.total_wasted > 0 else ""]
	var worst := maxf(float(raw_used) / float(maxi(1, raw_cap)), float(prod_used) / float(maxi(1, prod_cap)))
	_cargo.add_theme_color_override("font_color", Color("ff8a70") if worst >= 0.999 else (Color("ffc266") if worst >= CargoDB.WARN_RATIO else Color("cfe6ff")))
	var p = game.processor
	var ptxt := "待機中"
	if not p.current.is_empty():
		ptxt = p.current["name"]
	elif p.waiting_fuel and not p.orders.is_empty():
		ptxt = "燃料待ち"
	_proc.text = "加工: %s（待ち %d）" % [ptxt, p.orders.size()]
	_totals.text = "狩猟%d 回収%d 加工%d 補給%d 修理%d 食事%d" % [game.total_hunted, game.total_gathered,
			p.total_done, b.total_refuel, b.total_repair, game.total_eaten]
