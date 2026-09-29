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


# ---------------------------------------------------------------- 積載重量（画面のアイコンゲージが読む。積載量そのものの窓口でもある）
## 積載重量 = いま置いてある量の合計（素材ごとの大きさ CargoDB.SIZES で数える）。素材棚・加工品置き場の2区画の合計。
func current_weight() -> int:
	var n := 0
	for bay in CargoDB.BAY_NAMES:
		n += used_in(bay)
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
	return maxi(0, floori(float(max_weight() - current_weight()) / float(size)))


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
	# 倉庫の中心（初期配置では x = GameData.STORAGE_X）からの相対で並べる。部屋の変更で倉庫が別の区画へ移っても、その中に描かれる
	# 素材: 棚の上（棚板の上面 = 足元から56px上）。少し小さめに7種並べる
	for i in GameData.RAW_ITEMS.size():
		_slot(GameData.RAW_ITEMS[i], RAW_X0 - GameData.STORAGE_X + i * RAW_DX, -56.0, 36.0)
	# 加工品: 床の上
	for i in GameData.PRODUCT_ITEMS.size():
		_slot(GameData.PRODUCT_ITEMS[i], PROD_X0 - GameData.STORAGE_X + i * PROD_DX, 0.0, 44.0)


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
