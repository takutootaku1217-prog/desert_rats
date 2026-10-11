class_name BaseStorage
extends Node2D
## 拠点の倉庫（下の階の奥の棚）。素材は棚の上、加工品は床の上に見える。
## 獲物を運び込むと、ここで解体して肉・皮・骨・脂肪になる。

signal overflowed(item: int, amount: int)   # 置き場がなくて捨てた（積載量。data/cargo.gd）

var inventory := Inventory.new()
var total_butchered := 0       # 解体した数（確認用）
# ---- 積載量（data/cargo.gd。重量制）。拠点全体の「いまの重さ / 最大の重さ」がいっぱいなら回収・狩猟・加工をしない ----
var capacity_bonus := 0                # 増えた最大の重さ（設備「荷台の増設」・将来の拠点強化）
var enforce := true                    # false なら制限なし（自己診断ツール用）
var wasted := {}                       # Item -> 捨てた累計

const RAW_X0 := 548.0          # 棚（素材7種）の左端
const RAW_DX := 36.0
const PROD_X0 := 560.0         # 床（加工品4種）の左端
const PROD_DX := 52.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inventory.changed.connect(queue_redraw)


## 外部から倉庫へ取得。入る分だけ収納し、超過分は地点/地面へ保持。内部移動はstore_owned。
func add_item(item: int, n: int = 1, source: String = Inventory.SOURCE_ENVIRONMENT) -> int:
	var stored := mini(n, free_for(item))
	if stored > 0:
		inventory.add(item, stored, source)
	if stored < n and source == Inventory.SOURCE_TRANSFER:
		pass # 手動運搬の返却は Main.finish_transfer_trip が1回だけ行う。
	elif stored < n and game() != null:
		game().keep_outside(item, n - stored, GameData.RAMP_FOOT)
	elif stored < n:
		wasted[item] = wasted.get(item, 0) + (n - stored)
		overflowed.emit(item, n - stored)
	return stored


## 獲物を解体して素材にする（倒した・購入した・捕獲した生物で共通）。入りきらない素材は地点/地面へ保持する。
func butcher(species: String, source: String = Inventory.SOURCE_HUNT) -> void:
	var drops: Dictionary = GameData.CREATURES[species]["drops"]
	for it in drops:
		add_item(it, drops[it], source)
	total_butchered += 1


# ---------------------------------------------------------------- 積載重量（画面のアイコンゲージが読む。積載量そのものの窓口でもある）
## 保有重量。倉庫・作業場・加工材料/出力・全運搬物・装備武器・遠征修理板。設置設備と採取道具は従来どおり対象外。
func current_weight() -> int:
	var n := 0
	for bay in CargoDB.BAY_NAMES:
		n += used_in(bay)
	return n + equipped_weapon_weight() + workshop_weight() + carried_weight() + expedition_weight()


func item_weight(item: int, n := 1) -> int:
	return CargoDB.size_of(item) * n if CargoDB.bay_of(item) >= 0 else 0


func set_weight(items: Dictionary) -> int:
	var n := 0
	for it in items: n += item_weight(it, items[it])
	return n


func game():
	return get_parent().game if get_parent() is MobileBase else null


func workshop_weight() -> int:
	var g = game()
	if g == null or not is_instance_valid(g.processor): return 0
	var p = g.processor
	var n: int = set_weight(p.stock.counts) + set_weight(p.committed_inputs())
	for it in p.output: n += item_weight(it)
	return n


func carried_weight() -> int:
	var g = game()
	if g == null: return 0
	var n := 0
	for w in g.workers:
		if w.ai.state == CharacterAI.State.HAUL_MOVE and not w.ai.haul_recipe.is_empty():
			n += set_weight(w.ai.haul_recipe["in"])
		elif w.carrying == GameData.Item.CARCASS:
			n += set_weight(w.carcass_cargo)
		elif w.carrying >= 0:
			n += item_weight(w.carrying, w.carry_n)
		n += set_weight(w.carry_bonus)
	return n


func expedition_weight() -> int:
	var g = game()
	if g != null and g.expedition != null and g.expedition.state == "running" and g.expedition.kit and not g.expedition.kit_used:
		return item_weight(GameData.Item.REPAIR_KIT)
	return 0


## 正味の加工増量だけを予約。材料自体は所有場所に一度だけ数える。
func recipe_growth(r: Dictionary) -> int:
	return item_weight(r.get("out", -1), r.get("n", 0)) - set_weight(r.get("in", {}))


func processing_reserve() -> int:
	var g = game()
	if g == null or not is_instance_valid(g.processor): return 0
	var p = g.processor
	var recipes: Array = p.orders + p.incoming
	if not p.current.is_empty(): recipes.append(p.current)
	var n := 0
	for r in recipes: n += maxi(0, recipe_growth(r))
	return n


func transform_limit(r: Dictionary) -> int:
	var growth := recipe_growth(r)
	if not enforce or growth <= 0: return 1000000
	var room := max_weight() - current_weight() - processing_reserve()
	var g = game()
	if g != null: room -= set_weight(g.gather_room())
	return maxi(0, floori(float(room) / growth))


## 既に保有している物の内部移動。呼出側で元の所有場所を先に外す。
func store_owned(item: int, n := 1, source := Inventory.SOURCE_TRANSFER) -> void:
	if n > 0: inventory.add(item, n, source)



func equipped_weapon_weight() -> int:
	var n := 0
	if get_parent() is MobileBase:
		for w in get_parent().game.workers:
			if is_instance_valid(w) and w.weapon in GameData.WEAPON_ITEMS:
				n += CargoDB.size_of(w.weapon)
	return n


## 積載できる重量の合計（CargoDB.CAPACITY ＋ 拠点の強化で増えた分 capacity_bonus）。区画ごとの上限はない。
func max_weight() -> int:
	return CargoDB.CAPACITY + capacity_bonus


## 積載率 0〜1（画面のアイコンゲージの充填に使う）
func weight_ratio() -> float:
	return clampf(float(current_weight()) / float(maxi(1, max_weight())), 0.0, 1.0)


# ---------------------------------------------------------------- 積載量（重量制。素材ごとの枠はない）
## その素材が、いまの残りの重さであと何個置けるか。制限なしのときは十分大きな数。
func free_for(item: int) -> int:
	if not enforce or CargoDB.bay_of(item) < 0:
		return 1000000
	var size := CargoDB.size_of(item)
	return maxi(0, floori(float(max_weight() - current_weight() - processing_reserve()) / float(size)))


## その素材を、拠点がいま最大で何個まで持てるか（いま置いてある分＋残りの重さで置ける分）。
## 加工の作り置きの上限（Main.choose_recipe の room）など、「枠」があった頃の使い方をそのまま保つための窓口。
func quota_of(item: int) -> int:
	if not enforce or CargoDB.bay_of(item) < 0:
		return 1000000
	return inventory.count(item) + free_for(item)


func is_full(item: int) -> bool:
	return enforce and CargoDB.bay_of(item) >= 0 and free_for(item) <= 0


## 区画（素材棚／加工品置き場）に置いてある重さ。上限はなく、内訳の表示だけに使う。
func used_in(bay: int) -> int:
	var n := 0
	for it in CargoDB.items_of(bay):
		n += inventory.count(it) * CargoDB.size_of(it)
	return n


## 獲物を解体したとき、素材のうち何割が入るか（0〜1）。狩りや運搬をしてよいかの判断に使う。
func drop_fit(species: String) -> float:
	var drops: Dictionary = GameData.CREATURES[species]["drops"]
	var total := 0
	var fit := 0
	var room := maxi(0, max_weight() - current_weight() - processing_reserve())
	# butcher と同じ素材順で空きを使う。予測では在庫も廃棄数も変更しない。
	for it in drops:
		var n := int(drops[it])
		total += n
		if enforce and CargoDB.bay_of(it) >= 0:
			n = mini(n, floori(float(room) / CargoDB.size_of(it)))
			room -= n * CargoDB.size_of(it)
		fit += n
	return float(fit) / float(maxi(1, total))


func take_item(item: int) -> bool:
	return inventory.take(item)


func take_set(need: Dictionary) -> bool:
	return inventory.take_set(need)


func has_set(need: Dictionary) -> bool:
	return inventory.has_set(need)


func count_of(item: int) -> int:
	return inventory.count(item)


func has_any_product() -> bool:
	return inventory.has_any_of(GameData.PRODUCT_ITEMS)


func take_any_product() -> int:
	return inventory.take_any_of(GameData.PRODUCT_ITEMS)


func access_point() -> Vector2:
	return global_position


func _draw() -> void:
	# 区画幅から棚の列幅を決め、後方区画や製作物追加でも絵をはみ出させない。
	var slot: String = get_parent().room_slot("storage")
	var width := Rooms.slot_size(slot).x * Rooms.UNIT - 12.0
	var left := -float(Rooms.ANCHORS["storage"]["storage"]) * Rooms.UNIT + 6.0
	for group in [GameData.RAW_ITEMS, GameData.PRODUCT_ITEMS]:
		var dx: float = width / group.size()
		var y := -56.0 if group == GameData.RAW_ITEMS else 0.0
		for i in group.size():
			_slot(group[i], left + dx * (i + 0.5), y, minf(36.0 if y < 0 else 44.0, dx - 2.0))


func _slot(item: int, cx: float, base_y: float, sz: float) -> void:
	var n := inventory.count(item)
	var t := GameData.item_tex(item)
	var size := Vector2(sz, sz)
	if n <= 0:
		# 空きスロットはうっすら表示
		draw_texture_rect(t, Rect2(Vector2(cx - sz / 2.0, base_y - sz), size), false, Color(1, 1, 1, 0.12))
		return
	for k in mini(n, 3):
		draw_texture_rect(t, Rect2(Vector2(cx - sz / 2.0, base_y - sz - k * 8), size), false)
	# 数字は、その素材がいま置けるだけ置けていれば赤「満」、拠点全体の積載率が高ければ橙（素材ごとの上限はない。重量制）
	var col := Color("fff7c0")
	var txt := "%d" % n
	if is_full(item):
		col = Color("ff8a70")
		txt += "満"
	elif enforce and weight_ratio() >= CargoDB.WARN_RATIO:
		col = Color("ffc266")
	GameData.draw_text(self, Vector2(cx - 4, base_y - 2), txt, 12, col, 30.0, HORIZONTAL_ALIGNMENT_LEFT)
