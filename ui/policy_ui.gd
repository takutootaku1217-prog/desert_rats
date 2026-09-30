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
	if _page == 2:
		_build_tools_page()
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
		var stn: String = GameData.recipe_station(r)
		if stn != "":                                 # 必要設備。まだ建てていなければ作られない（建設の画面 B）
			extra += "　【%s%s】" % [FacilityDB.name_of(stn), "" if game.has_facility(stn) else "が必要・まだない"]
		row.add_child(UIKit.lbl(GameData.recipe_text(r) + extra, 13, UIKit.C_DIM if game.has_facility(stn) else Color("ff8a70")))
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


## 上のページ切り替え（方針 / 積載重量）
func _tabs() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for spec in [[0, "方針（加工・回収・狩猟）"], [1, "積載重量"], [2, "採取の道具"]]:
		var p: int = spec[0]
		var b := UIKit.button(spec[1], func():
			_page = p
			_rebuild())
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(220, 30)
		UIKit.style(b, _page == p)
		h.add_child(b)
	return h


## 積載重量（見るだけ。実装指示書「運営の方針→積載の割り当て」は廃止し、読み取り専用の積載重量ページへ）。
## 個別の枠は無く、拠点全体の「現在重量 / 最大重量」だけで収納の可否が決まる。ここでは、いまの内訳を確認できる。
func _build_cargo_page() -> void:
	var st = game.storage
	var total: int = game.total_weight()
	var maxw: int = game.max_weight()
	_body.add_child(UIKit.lbl("倉庫の制限は、拠点全体の「いまの重さ / 最大の重さ」の1本だけです（素材ごとの枠はありません）。"
			+ "\n満杯（100%）になると、新しい回収・狩猟・加工・運搬を予約しなくなります。重さが空けば、また予約できます。", 13, UIKit.C_DIM))
	var ratio := float(total) / float(maxi(1, maxw))
	var rcol := Color("7be07b")
	if ratio >= 1.0:
		rcol = Color("e0533d")
	elif ratio >= CargoDB.WARN_RATIO:
		rcol = Color("f0c040")
	_body.add_child(UIKit.lbl("── 現在重量 %d / %d（%d%%） ──" % [total, maxw, int(ratio * 100.0)], 17, rcol))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(640, 0)
	_body.add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	col.add_child(header)
	header.add_child(UIKit.lbl("アイテム", 13, UIKit.C_DIM, 140))
	header.add_child(UIKit.lbl("所持数", 13, UIKit.C_DIM, 90))
	header.add_child(UIKit.lbl("1個の重さ", 13, UIKit.C_DIM, 90))
	header.add_child(UIKit.lbl("合計の重さ", 13, UIKit.C_DIM, 90))
	for it in ItemDB.all():
		var n: int = st.count_of(it)
		if n <= 0:
			continue
		var w := CargoDB.item_weight(it)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		row.add_child(UIKit.lbl(GameData.ITEM_NAMES[it], 15, UIKit.C_TEXT, 140))
		row.add_child(UIKit.lbl("%d" % n, 15, UIKit.C_TEXT, 90))
		row.add_child(UIKit.lbl("%d" % w, 14, UIKit.C_DIM, 90))
		row.add_child(UIKit.lbl("%d" % (w * n), 15, Color("ffd24a"), 90))
	var tgt: Array = []
	for it in GameData.STOCK_TARGET:
		tgt.append("%s%d" % [GameData.ITEM_NAMES[it], GameData.STOCK_TARGET[it]])
	_body.add_child(UIKit.lbl("加工品の「作り置きの上限」（%s）は、いまの目安です（重量に空きがあるうちの目安。プレイヤーが手動で作るときはこれを超えられます）。"
			% "・".join(PackedStringArray(tgt)), 12, UIKit.C_DIM))


## 採取の道具: 誰に何を持たせるか・道具の性能・結果の目安。採取の結果は「採取ポイント × 道具 × 仲間の能力」で決まる（data/gathering.gd）。
func _build_tools_page() -> void:
	var st = game.storage
	_body.add_child(UIKit.lbl("木材・石・鉄鉱石は、採取ポイント（岩場・鉱床・枯れ木）から道具で掘ります。取れる量は「採取ポイント × 道具 × 仲間の能力」で決まります。"
			+ "\n道具は加工でつくります（誰かの道具の更新になるときだけ作ります）。良い道具は、回収ランクの高い仲間に持たせると活きます。", 13, UIKit.C_DIM))
	var auto_btn := UIKit.button("道具の自動割り当て: %s" % ("ON（倉庫の道具を、効果の大きい仲間へ自動で持たせる）" if game.tool_auto else "OFF（下のボタンで手動）"), func():
		game.tool_auto = not game.tool_auto
		_rebuild())
	auto_btn.custom_minimum_size = Vector2(560, 28)
	UIKit.style(auto_btn, game.tool_auto)
	_body.add_child(auto_btn)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	_body.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size = Vector2(640, 0)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	cols.add_child(right)

	# ---- 左: 仲間ごとの道具と、結果の目安 ----
	left.add_child(UIKit.lbl("── 仲間の道具（掘り出し10単位あたりの取れる個数の目安） ──", 14, UIKit.C_DIM))
	for w in game.workers:
		var rank: int = w.ranks.get(GameData.Field.GATHERER, 0)
		var ab: float = w.field_mult(GameData.Field.GATHERER)
		left.add_child(UIKit.lbl("%s　回収ランク %s（能力値 %.2f）%s" % [w.char_name, GameData.RANKS[rank], ab,
				"" if game._uses_tools(w) else "　※回収をしない設定"], 15, UIKit.C_ACCENT))
		for slot in GatherDB.SLOTS:
			var s: String = slot
			var cur: int = int(w.tools.get(s, -1))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			left.add_child(row)
			row.add_child(UIKit.lbl("　%s: %s" % [GatherDB.SLOTS[s], GatherDB.tool_def(cur)["name"]], 14, UIKit.C_TEXT, 200))
			# 持たせられる道具（倉庫にあるもの）
			for it in GameData.TOOL_ITEMS:
				var item: int = it
				if GatherDB.slot_of_tool(item) != s or st.count_of(item) <= 0:
					continue
				var b := UIKit.button("%s（在庫%d）" % [GameData.ITEM_NAMES[item], st.count_of(item)], func():
					game.equip_tool(w, item)
					_rebuild())
				b.custom_minimum_size = Vector2(0, 24)
				row.add_child(b)
			if cur >= 0:
				var off := UIKit.button("外す", func():
					game.unequip_tool(w, s)
					_rebuild())
				off.custom_minimum_size = Vector2(0, 24)
				row.add_child(off)
			# この枠で掘れる採取ポイントごとの結果の目安
			var parts: Array = []
			for k in GatherDB.POINTS:
				if GatherDB.POINTS[k]["slot"] != s:
					continue
				var ev: Dictionary = w.gather_eval(k)
				parts.append("%s %.1f個" % [GatherDB.POINTS[k]["name"], float(ev["eff"]) * 10.0])
			left.add_child(UIKit.lbl("　　　" + "　".join(PackedStringArray(parts)), 13, UIKit.C_DIM))

	# ---- 右: 道具の性能・在庫・作り方 ----
	right.add_child(UIKit.lbl("── 道具の性能（取れる割合＝掘り出した量のうち手に入る割合） ──", 14, UIKit.C_DIM))
	right.add_child(UIKit.lbl("素手　　　　岩場%d%% 鉱床%d%% 枯れ木%d%%　速さ×%.1f" % [
			int(GatherDB.HANDS["eff"]["rock"] * 100.0), int(GatherDB.HANDS["eff"]["vein"] * 100.0),
			int(GatherDB.HANDS["eff"]["tree"] * 100.0), GatherDB.HANDS["speed"]], 13, UIKit.C_DIM))
	for it in GameData.TOOL_ITEMS:
		var item: int = it
		var t: Dictionary = GatherDB.TOOLS[item]
		var effs: Array = []
		for k in GatherDB.POINTS:
			if t["eff"].has(k):
				effs.append("%s%d%%" % [GatherDB.POINTS[k]["name"], int(float(t["eff"][k]) * 100.0)])
		var bonus := ""
		for k in t["bonus"]:
			for bi in t["bonus"][k]:
				bonus += "　副産物: %s→%s" % [GatherDB.POINTS[k]["name"], GameData.ITEM_NAMES[bi]]
		right.add_child(UIKit.lbl("%s（在庫%d）" % [t["name"], st.count_of(item)], 14, UIKit.C_TEXT))
		right.add_child(UIKit.lbl("　%s　速さ×%.1f　必要ランク %s%s" % [" ".join(PackedStringArray(effs)), t["speed"],
				GameData.RANKS[int(t["need_rank"])], bonus], 12, UIKit.C_DIM))
		for r in GameData.RECIPES:
			if r["out"] == item:
				right.add_child(UIKit.lbl("　作り方: " + GameData.recipe_text(r), 12, UIKit.C_DIM))
	right.add_child(UIKit.lbl("回収ランクが「必要ランク」に届かないと、取れる割合が下がります。", 12, UIKit.C_DIM))
	# テスト用（生物の購入と同じ扱い）: 道具を倉庫に入れて、性能の違いをすぐ試せる
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	right.add_child(sp)
	right.add_child(UIKit.lbl("── テスト用: 道具を倉庫に入れる（加工でも作れます） ──", 14, UIKit.C_DIM))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	flow.custom_minimum_size = Vector2(520, 0)
	right.add_child(flow)
	for it in GameData.TOOL_ITEMS:
		var item: int = it
		var b := UIKit.button(GameData.ITEM_NAMES[item], func():
			st.add_item(item, 1, Inventory.SOURCE_PURCHASE)
			game.manage_tools()
			_rebuild())
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(124, 28)
		flow.add_child(b)


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
