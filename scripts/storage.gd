class_name BaseStorage
extends Node2D
## 拠点の倉庫（下の階の奥の棚）。素材は棚の上、加工品は床の上に見える。
## 獲物を運び込むと、ここで解体して肉・皮・骨・脂肪になる。

signal overflowed(item: int, amount: int)   # 置き場がなくて捨てた（積載量。data/cargo.gd）

var inventory := Inventory.new()
var total_butchered := 0       # 解体した数（確認用）
# ---- 積載量（data/cargo.gd）。素材ごとの「枠」を決め、いっぱいなら回収・狩猟・加工をしない ----
var quota := CargoDB.default_quota()   # Item -> 置ける個数（プレイヤーが割り当てを変える）
var capacity_bonus := {}               # Bay -> 増えた積載量（将来: 拠点の強化・部屋）
var enforce := true                    # false なら制限なし（自己診断ツール用）
var wasted := {}                       # Item -> 捨てた累計

const RAW_X0 := 548.0          # 棚（素材7種）の左端
const RAW_DX := 36.0
const PROD_X0 := 560.0         # 床（加工品4種）の左端
const PROD_DX := 52.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inventory.changed.connect(queue_redraw)


## 倉庫に入れる。枠がいっぱいなら入る分だけ入れて、残りは捨てる。入った個数を返す。
func add_item(item: int, n: int = 1, source: String = Inventory.SOURCE_ENVIRONMENT) -> int:
	var stored := mini(n, free_for(item))
	if stored > 0:
		inventory.add(item, stored, source)
	if stored < n:
		wasted[item] = wasted.get(item, 0) + (n - stored)
		overflowed.emit(item, n - stored)
	return stored


## 獲物を解体して素材にする（倒した・購入した・捕獲した生物で共通）。入りきらない素材は捨てる。
func butcher(species: String, source: String = Inventory.SOURCE_HUNT) -> void:
	var drops: Dictionary = GameData.CREATURES[species]["drops"]
	for it in drops:
		add_item(it, drops[it], source)
	total_butchered += 1


# ---------------------------------------------------------------- 積載量
func capacity_of(bay: int) -> int:
	return int(CargoDB.CAPACITY[bay]) + int(capacity_bonus.get(bay, 0))


## 素材ごとの枠（個数）。制限なしのときは十分大きな数。
func quota_of(item: int) -> int:
	if not enforce or CargoDB.bay_of(item) < 0:
		return 1000000
	return int(quota.get(item, 0))


## その素材があと何個置けるか
func free_for(item: int) -> int:
	return maxi(0, quota_of(item) - inventory.count(item))


func is_full(item: int) -> bool:
	return enforce and CargoDB.bay_of(item) >= 0 and free_for(item) <= 0


## 区画に置いてある量（大きさで数える）
func used_in(bay: int) -> int:
	var n := 0
	for it in CargoDB.items_of(bay):
		n += inventory.count(it) * CargoDB.size_of(it)
	return n


## 区画の積載量のうち、素材ごとの枠に割り当て済みの量
func allocated_in(bay: int) -> int:
	var n := 0
	for it in CargoDB.items_of(bay):
		n += int(quota.get(it, 0)) * CargoDB.size_of(it)
	return n


func unallocated_in(bay: int) -> int:
	return maxi(0, capacity_of(bay) - allocated_in(bay))


## 枠を変える。増やすときは、割り当てていない積載量の範囲まで。変えたあとの枠を返す。
func set_quota(item: int, value: int) -> int:
	var bay := CargoDB.bay_of(item)
	if bay < 0:
		return 0
	value = maxi(0, value)
	var cur := int(quota.get(item, 0))
	if value > cur:
		var size := CargoDB.size_of(item)
		value = mini(value, cur + floori(float(unallocated_in(bay)) / float(size)))
	quota[item] = value
	queue_redraw()
	return value


## 獲物を解体したとき、素材のうち何割が入るか（0〜1）。狩りや運搬をしてよいかの判断に使う。
func drop_fit(species: String) -> float:
	var drops: Dictionary = GameData.CREATURES[species]["drops"]
	var total := 0
	var fit := 0
	for it in drops:
		total += int(drops[it])
		fit += mini(int(drops[it]), free_for(it))
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
	# 素材: 棚の上（棚板の上面 = 足元から56px上）。少し小さめに7種並べる
	for i in GameData.RAW_ITEMS.size():
		_slot(GameData.RAW_ITEMS[i], RAW_X0 + i * RAW_DX - position.x, -56.0, 36.0)
	# 加工品: 床の上
	for i in GameData.PRODUCT_ITEMS.size():
		_slot(GameData.PRODUCT_ITEMS[i], PROD_X0 + i * PROD_DX - position.x, 0.0, 44.0)


func _slot(item: int, cx: float, base_y: float, sz: float) -> void:
	var n := inventory.count(item)
	var t := GameData.item_tex(item)
	var size := Vector2(sz, sz)
	var q := quota_of(item)
	if n <= 0:
		# 空きスロットはうっすら表示
		draw_texture_rect(t, Rect2(Vector2(cx - sz / 2.0, base_y - sz), size), false, Color(1, 1, 1, 0.12))
		if enforce and q <= 0:
			GameData.draw_text(self, Vector2(cx - 4, base_y - 2), "枠0", 12, Color("ff8a70"), 30.0, HORIZONTAL_ALIGNMENT_LEFT)
		return
	for k in mini(n, 3):
		draw_texture_rect(t, Rect2(Vector2(cx - sz / 2.0, base_y - sz - k * 8), size), false)
	# 数字は、枠がいっぱいに近づくと橙、いっぱい（「満」）で赤にする
	var col := Color("fff7c0")
	var txt := "%d" % n
	if enforce and n >= q:
		col = Color("ff8a70")
		txt += "満"
	elif enforce and float(n) >= float(q) * CargoDB.WARN_RATIO:
		col = Color("ffc266")
	GameData.draw_text(self, Vector2(cx - 4, base_y - 2), txt, 12, col, 30.0, HORIZONTAL_ALIGNMENT_LEFT)
