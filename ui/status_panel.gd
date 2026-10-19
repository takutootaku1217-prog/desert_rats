class_name StatusPanel
extends CanvasLayer
## 右上の拠点の状態。文字を読まなくても、ひと目で状態が分かるように、アイコン中心に並べる。
##  1段目: 移動の状態（短い1行）と、速度 / 目標（↑↓キー）。
##  2段目: アイコンゲージ（アイコンそのものが残量。数字はアイコンの中）
##         拠点HP = 現在の拠点シルエット（中に「拠点」と数値）／燃料 = ジェリカン／積載重量 = 重り（ARK方式）。
## 倉庫の中身と累計は下部「物資」へ移す（NavigationBar）。

## 絵は assets/ui/*.png（枠と充填範囲の2枚。tools/art_ui.py が作る仮素材）。差し替えるだけで形を変えられる。表示だけで、ゲームのデータは読むだけ。

var game
var _state: Label
var _speed: Label
var _mission: Label
var _gauges := {}            # key -> IconGauge
var _weight: IconGauge       # 積載重量（= _gauges["weight"]。診断ツールが読む）
var _stock: StockGrid
var _repair: Button
var _crew_repair: Button
var _leak: Label
var _boost: Label
var _boost_bar: ProgressBar
var _boost_toggle: Button
var _boost_sustained: Button
var _boost_burst: Button
var _totals: Label
var _capacity: Label

const W := 272.0
const ICON_UNITS := Vector2i(12, 12)     # アイコン1つの基準の大きさ（ユニット）= 48px（絵のドットが3pxの整数倍）
## 2段目のアイコンゲージ（左から）。拠点HPは外装から合成、それ以外はassets/uiの素材。
const GAUGES := [
	{"key": "hull", "name": "拠点HP"},
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
	_mission = UIKit.lbl("", 12, Color("ffe2a5"))
	_mission.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission.custom_minimum_size.x = W - 18
	v.add_child(_mission)
	# 2段目: アイコンゲージ
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 4)
	v.add_child(gh)
	for spec in GAUGES:
		var g: IconGauge
		if spec["key"] == "hull":
			g = BaseHPGauge.new()
			(g as BaseHPGauge).update_appearance(game)
		else:
			g = IconGauge.new()
			g.setup(String(spec["icon"]), ICON_UNITS)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if spec["key"] != "weight":
			g.color_stages = UIKit.GAUGE_STAGES_BASE
			g.dark_empty = true
		gh.add_child(g)
		_gauges[spec["key"]] = g
	_weight = _gauges["weight"]
	_capacity = UIKit.lbl("", 13, UIKit.C_DIM)
	v.add_child(_capacity)
	_leak = UIKit.lbl("", 12, Color("ffb347"))
	_leak.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_leak)
	_boost = UIKit.lbl("", 12, Color("9ddcff"))
	_boost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_boost)
	_boost_bar = ProgressBar.new()
	_boost_bar.custom_minimum_size = Vector2(W - 16, 14)
	_boost_bar.max_value = BoostCores.MAX_LOAD
	_boost_bar.show_percentage = false
	v.add_child(_boost_bar)
	var boost_buttons := HBoxContainer.new()
	boost_buttons.add_theme_constant_override("separation", 3)
	v.add_child(boost_buttons)
	_boost_toggle = UIKit.button("ブースト開始 (V)", func(): game.request_boost_toggle())
	_boost_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boost_buttons.add_child(_boost_toggle)
	_boost_sustained = UIKit.button("持続 8/24", func(): game.select_boost_core(BoostCores.SUSTAINED))
	boost_buttons.add_child(_boost_sustained)
	_boost_burst = UIKit.button("短時間 2/6", func(): game.select_boost_core(BoostCores.BURST))
	boost_buttons.add_child(_boost_burst)
	# 3段目: 倉庫の中身
	_stock = StockGrid.new().setup(STOCK_ROWS)
	v.add_child(_stock)
	# 4段目: 累計（小さく）
	_totals = UIKit.lbl("", 12, UIKit.C_DIM)
	v.add_child(_totals)
	_repair = UIKit.button("応急修理", func(): game.emergency_repair())
	_repair.tooltip_text = "最も傷んだ未予約の部位を%d回復（上限100）。燃料・仲間HPは回復しません" % GameData.REPAIR_AMOUNT
	v.add_child(_repair)
	_crew_repair = UIKit.button("\u9069\u4efb\u306b\u4fee\u7406\u3092\u4f9d\u983c", func(): game.request_repair())
	v.add_child(_crew_repair)


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
	_repair.disabled = game.emergency_repair_target() < 0 or game.storage.count_of(GameData.Item.REPAIR_KIT) <= 0
	var repair_info: Dictionary = game.repair_order_info()
	var assigned = repair_info["assigned"]
	_crew_repair.disabled = int(repair_info["part"]) < 0 or int(repair_info["missing"]) > 0 or assigned != null
	_crew_repair.text = "\u4fee\u7406\u4e2d: %s" % assigned.char_name if assigned != null else "\u9069\u4efb\u306b\u4fee\u7406\u3092\u4f9d\u983c"
	_crew_repair.tooltip_text = "\u73fe\u5730\u4fee\u7406\u306f\u4fee\u7406\u30ad\u30c3\u30c8%d\u500b\u304c\u5fc5\u8981(\u6240\u6301%d / \u4e0d\u8db3%d)\u3002\u90fd\u5e02\u306e\u5373\u6642\u4fee\u7406\u3068\u306f\u5225\u306e\u884c\u52d5\u3067\u3059\u3002" % [int(repair_info["required"]), int(repair_info["available"]), int(repair_info["missing"])]
	_repair.text = "応急修理（%d）" % game.storage.count_of(GameData.Item.REPAIR_KIT)
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
	_mission.text = game.town.field_status_text()
	_mission.visible = game.town.delivery != "idle" or game.town.recovery != "idle"
	_speed.text = "速度 %d / %d ↑↓" % [int(game.scroll_speed), int(game.target_speed)]
	_speed.tooltip_text = "速度 / 目標（↑↓キーで目標の速度を変える）"
	# 2段目: 拠点HP（外装の耐久）。走行装置・加工設備の耐久はHUDに出さない。
	(_gauges["hull"] as BaseHPGauge).update_appearance(game)
	_speed.tooltip_text = "\u901f\u5ea6 / \u76ee\u6a19(\u4e0a\u4e0b\u30ad\u30fc\u3067\u5909\u66f4)\u3002\u30a8\u30f3\u30b8\u30f3\u4fee\u7406\u5f8c\u3082\u901f\u5ea6\u306f\u624b\u52d5\u3067\u623b\u3057\u307e\u3059\u3002"
	var leak_rate: float = b.engine_leak_rate(game.scroll_speed)
	_leak.visible = b.engine_leaking()
	if _leak.visible:
		_leak.text = "\u30a8\u30f3\u30b8\u30f3\u71c3\u6599\u6f0f\u308c: %.3f/\u79d2 (\u6e1b\u901f\u3067\u6e1b\u5c11\u30fb\u505c\u6b62\u4e2d\u3082\u7d99\u7d9a)" % leak_rate
		_leak.tooltip_text = "\u5f8c\u90e8\u88ab\u5f3e\u84c4\u7a4d %.1f / 100\nDRIVE %d / 100\n\u73fe\u5730\u4fee\u7406\u304c\u5b8c\u4e86\u3059\u308b\u307e\u3067\u6f0f\u308c\u307e\u3059\u3002" % [b.rear_engine_damage, int(b.condition(GameData.Part.DRIVE))]
	var core: Dictionary = game.boost_profile()
	var remaining: float = game.boost_remaining_seconds()
	var recover: float = game.boost_recovery_seconds()
	_boost.text = "ブースト負荷 %d%%　%s　残り %.1f秒%s" % [int(round(game.boost_load)), String(core["name"]), remaining, "　休止で %.1f秒" % recover if not game.boost_active and game.boost_load > 0.0 else ""]
	_boost.tooltip_text = "燃料とは別の負荷ゲージ。使用中に増え、休止中に下がります。\n%s / 速度 %.1f倍。満杯で解除され、再開はVキーまたは開始ボタンで明示操作します。" % [String(core["summary"]), BoostCores.SPEED_MULTIPLIER]
	_boost_bar.value = game.boost_load
	_boost_bar.tooltip_text = _boost.tooltip_text
	_boost_toggle.text = "ブースト解除 (V)" if game.boost_active else "ブースト開始 (V)"
	_boost_toggle.disabled = not game.boost_active and not game.can_start_boost()
	_boost_sustained.disabled = game.boost_active or game.boost_core_id == BoostCores.SUSTAINED
	_boost_burst.disabled = game.boost_active or game.boost_core_id == BoostCores.BURST
	var cond: float = b.condition(GameData.Part.HULL)
	_set_gauge("hull", cond, 100.0, str(int(cond)), "拠点HP %d / 100%s" % [int(cond), "（不調）" if cond < GameData.PART_BAD else ""])
	_set_gauge("fuel", b.fuel, GameData.FUEL_CAP, str(int(b.fuel / GameData.FUEL_CAP * 100.0)), "燃料 %d / %d" % [int(b.fuel), int(GameData.FUEL_CAP)])
	# 積載重量: 重りのアイコンが下から埋まり、増えるほど色が濃くなる。数字は正確な重量（アイコンの中）。
	# 区画ごとの内訳（素材棚・加工品置き場）と捨てた数は、アイコンにマウスを載せると出る。
	var st = game.storage
	_capacity.text = "燃料 %d/%d　積載 %d/%d" % [b.fuel, GameData.FUEL_CAP, st.current_weight(), st.max_weight()]
	if st.processing_reserve() > 0: _capacity.text += "\n加工増量の予約 %d" % st.processing_reserve()
	var tip := "積載重量 %d / %d" % [st.current_weight(), st.max_weight()]
	for bay in CargoDB.BAY_NAMES:
		tip += "\n　%s %d" % [CargoDB.BAY_NAMES[bay], st.used_in(bay)]
	tip += "\n　作業場・加工 %d / 運搬中 %d" % [st.workshop_weight(), st.carried_weight()]
	tip += "\n　装備中の武器 %d / 遠征携行 %d" % [st.equipped_weapon_weight(), st.expedition_weight()]
	tip += "\n　装備中の仕事補助 %d" % st.equipped_support_weight()
	tip += "\n　加工増量の予約 %d" % st.processing_reserve()
	if game.total_wasted > 0:
		tip += "\n　捨てた %d 個" % game.total_wasted
	_set_gauge("weight", float(st.current_weight()), float(st.max_weight()), str(st.current_weight()), tip)
	# 3段目
	_stock.update_from(st, game.hungry)
	# 4段目
	var p = game.processor
	_totals.text = "狩猟%d 回収%d 加工%d 補給%d 修理%d 食事%d" % [game.total_hunted, game.total_gathered,
			p.total_done, b.total_refuel, b.total_repair, game.total_eaten]
