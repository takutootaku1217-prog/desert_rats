class_name StatusPanel
extends CanvasLayer
## 右上の拠点の状態。文字を読まなくても、ひと目で状態が分かるように、アイコン中心に並べる（情報は減らしていない）。
##  1段目: 移動の状態（短い1行）と、速度 / 目標（↑↓キー）。
##  2段目: アイコンゲージ（アイコンそのものが残量。数字はアイコンの中）
##         車体・走行装置・加工設備の耐久 = 盾（個体のHP=ハートと同じ作り。目印で部位を見分ける）／燃料 = ジェリカン／積載重量 = 重り（ARK方式）。
##  3段目: 倉庫の中身（アイテムのアイコン＋個数。ui/stock_grid.gd）。
##  4段目: 累計（小さく）。
## 絵は assets/ui/*.png（枠と充填範囲の2枚。tools/art_ui.py が作る仮素材）。差し替えるだけで形を変えられる。表示だけで、ゲームのデータは読むだけ。

var game
var _state: Label
var _speed: Label
var _gauges := {}            # key -> IconGauge
var _weight: IconGauge       # 積載重量（= _gauges["weight"]。診断ツールが読む）
var _stock: StockGrid
var _totals: Label

const W := 272.0
const ICON_UNITS := Vector2i(12, 12)     # アイコン1つの基準の大きさ（ユニット）= 48px（絵のドットが3pxの整数倍）
## 2段目のアイコンゲージ（左から）。icon = assets/ui/<icon>.png と <icon>_mask.png
const GAUGES := [
	{"key": "hull", "icon": "shield_hull", "name": "車体"},
	{"key": "drive", "icon": "shield_drive", "name": "走行装置"},
	{"key": "machine", "icon": "shield_machine", "name": "加工設備"},
	{"key": "fuel", "icon": "fuel", "name": "燃料"},
	{"key": "weight", "icon": "weight", "name": "積載"},
]
## 3段目: 倉庫の中身（行ごと）。1行目 = 加工品・維持に使う物、2行目 = 素材
const STOCK_ROWS := [
	[GameData.Item.FOOD, GameData.Item.FUEL, GameData.Item.REPAIR_KIT, GameData.Item.IRON],
	[GameData.Item.MEAT, GameData.Item.HIDE, GameData.Item.BONE, GameData.Item.FAT, GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE],
]


func _ready() -> void:
	layer = 11
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("1b1e24", 0.92), Color("636b7a"), 4, 8))
	panel.position = Vector2(1000, 8)
	panel.custom_minimum_size = Vector2(W, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	# 1段目: 移動の状態と速度
	var head := HBoxContainer.new()
	v.add_child(head)
	_state = UIKit.lbl("", 14, Color("fff7dc"))
	_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_state)
	_speed = UIKit.lbl("", 13, Color("cfe6ff"))
	_speed.mouse_filter = Control.MOUSE_FILTER_STOP
	head.add_child(_speed)
	# 2段目: アイコンゲージ
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 4)
	v.add_child(gh)
	for spec in GAUGES:
		var g := IconGauge.new()
		g.setup(String(spec["icon"]), ICON_UNITS)        # 基準の大きさはユニット（絵を高精細にしても画面上の大きさは同じ）
		if spec["key"] != "weight":
			g.color_stages = UIKit.GAUGE_STAGES_BASE
			g.dark_empty = true
		gh.add_child(g)
		_gauges[spec["key"]] = g
	_weight = _gauges["weight"]
	# 3段目: 倉庫の中身
	_stock = StockGrid.new().setup(STOCK_ROWS)
	v.add_child(_stock)
	# 4段目: 累計（小さく）
	_totals = UIKit.lbl("", 12, UIKit.C_DIM)
	v.add_child(_totals)


func _set_gauge(key: String, value: float, maximum: float, label: String, tip: String) -> void:
	var g: IconGauge = _gauges[key]
	g.set_value(value, maximum, label if UIKit.show_icon_numbers else "")
	g.tooltip_text = tip
	if key != "weight":
		g.set_blink(g.ratio < UIKit.GAUGE_BLINK_BELOW)            # 危険域では、そのアイコンだけが赤く点滅する


## 表示している倉庫の中身の文字（診断ツール用。画面には出さない）
func stock_summary() -> String:
	return _stock.summary()


func _process(_d: float) -> void:
	if game == null or game.base == null:
		return
	var b = game.base
	# 1段目
	var move := "停止中"
	var col := Color("fff7dc")
	if game.scroll_speed > 0.0:
		if not b.has_fuel():
			move = "燃料切れ・低速走行"
			col = Color("ff8a70")
		elif b.condition(GameData.Part.DRIVE) < GameData.PART_BAD:
			move = "走行装置が不調"
			col = Color("ffb347")
		else:
			move = "進行中"
			col = Color("b9f3b9")
	_state.text = "拠点: " + move
	_state.add_theme_color_override("font_color", col)
	_speed.text = "速度 %d / %d ↑↓" % [int(game.scroll_speed), int(game.target_speed)]
	_speed.tooltip_text = "速度 / 目標（↑↓キーで目標の速度を変える）"
	# 2段目: 耐久（盾）・燃料（ジェリカン）
	for spec in [["hull", GameData.Part.HULL], ["drive", GameData.Part.DRIVE], ["machine", GameData.Part.MACHINE]]:
		var cond: float = b.condition(spec[1])
		var nm: String = GameData.PART_NAMES[spec[1]]
		_set_gauge(spec[0], cond, 100.0, str(int(cond)), "%s の耐久 %d / 100%s" % [nm, int(cond), "（不調）" if cond < GameData.PART_BAD else ""])
	_set_gauge("fuel", b.fuel, GameData.FUEL_CAP, str(int(b.fuel / GameData.FUEL_CAP * 100.0)), "燃料 %d / %d" % [int(b.fuel), int(GameData.FUEL_CAP)])
	# 積載重量: 重りのアイコンが下から埋まり、増えるほど色が濃くなる。数字は正確な重量（アイコンの中）。
	# 区画ごとの内訳（素材棚・加工品置き場）と捨てた数は、アイコンにマウスを載せると出る。
	var st = game.storage
	var tip := "積載重量 %d / %d" % [st.current_weight(), st.max_weight()]
	for bay in CargoDB.BAY_NAMES:
		tip += "\n　%s %d / %d" % [CargoDB.BAY_NAMES[bay], st.used_in(bay), st.capacity_of(bay)]
	if game.total_wasted > 0:
		tip += "\n　捨てた %d 個" % game.total_wasted
	_set_gauge("weight", float(st.current_weight()), float(st.max_weight()), str(st.current_weight()), tip)
	# 3段目
	_stock.update_from(st, game.hungry)
	# 4段目
	var p = game.processor
	_totals.text = "狩猟%d 回収%d 加工%d 補給%d 修理%d 食事%d" % [game.total_hunted, game.total_gathered,
			p.total_done, b.total_refuel, b.total_repair, game.total_eaten]
