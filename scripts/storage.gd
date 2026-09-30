class_name BaseStorage
extends Node2D
## 拠点の倉庫（下の階の奥の棚）。素材は棚の上、加工品は床の上に見える（表示の分類だけで、収納の上限には関係ない）。
## 獲物を運び込むと、ここで解体して肉・皮・骨・脂肪になる。
##
## 積載量は、区画・アイテムごとの枠ではなく、拠点全体の「現在重量 / 最大重量」の1本（data/cargo.gd）。
## 現在重量・最大重量の正本は Main（作業場・加工中・装備中の道具・運搬中のアイテムも含めた合計。Main.total_weight/max_weight）。
## ここでの current_weight は「この倉庫（棚）だけの重さ」。収納できるかどうかの判定（add_item・free_for）は、
## 拠点全体の残り重量（base().game.remaining_weight）を見て行う。

var inventory := Inventory.new()
var total_butchered := 0       # 解体した数（確認用）
var enforce := true            # false なら制限なし（自己診断ツール用）

const RAW_X0 := 548.0          # 棚（素材7種）の左端
const RAW_DX := 36.0
const PROD_X0 := 560.0         # 床（加工品4種）の左端
const PROD_DX := 52.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inventory.changed.connect(queue_redraw)


func base():
	return get_parent()


# ---------------------------------------------------------------- 重量
## この倉庫（棚）だけの重さ（作業場・装備中の道具・運搬中のぶんは含まない）。拠点全体の合計は Main.total_weight。
func current_weight() -> int:
	var n := 0
	for it in inventory.counts:
		n += CargoDB.weight_of(it, inventory.counts[it])
	return n


## 拠点の最大重量（基本値＋建てた設備の効果。別変数に二重保存せず、そのつど建設数から計算する）
func max_weight() -> int:
	if not enforce:
		return 999999999
	var n := CargoDB.BASE_MAX_WEIGHT
	var b = base()
	if b != null:
		for id in FacilityDB.ids():
			var bonus := int(FacilityDB.def(id).get("capacity_bonus", 0))
			if bonus > 0:
				n += bonus * b.facility_count(id)
	return n


## 拠点全体のいまの重さ（Main が分かればそちらの合計、無ければこの倉庫だけの重さ＝単体テスト用の後退互換）
func total_current_weight() -> int:
	var b = base()
	if b != null and b.game != null and b.game.has_method("total_weight"):
		return b.game.total_weight()
	return current_weight()


## 積載率 0〜1（画面のアイコンゲージの充填に使う）
func weight_ratio() -> float:
	return clampf(float(total_current_weight()) / float(maxi(1, max_weight())), 0.0, 1.0)


func remaining_weight() -> int:
	if not enforce:
		return 999999999
	return maxi(0, max_weight() - total_current_weight())


## そのアイテムが、拠点全体の残り重量に、あと何個入るか（enforce=false なら十分大きい数）
func free_for(item: int) -> int:
	if not enforce:
		return 1000000
	var w := CargoDB.item_weight(item)
	if w <= 0:
		return 1000000
	return maxi(0, floori(float(remaining_weight()) / float(w)))


func is_full(item: int) -> bool:
	return enforce and free_for(item) <= 0


# ---------------------------------------------------------------- 収納（重量超過でも捨てない）
## 倉庫に入れる。全体の残り重量に入る分だけ、この倉庫（棚）へ入れる。入りきらない分は、作業場（processor.stock。
## 元から容量の上限がない置き場）へ預ける（捨てない。実装指示書 2.3）。作業場も拠点全体の重さに含まれるので、
## 「倉庫が満杯でも作業場へ逃がせば増やせる」抜け道にはならない。入った個数（倉庫にそのまま入った分）を返す。
func add_item(item: int, n: int = 1, source: String = Inventory.SOURCE_ENVIRONMENT) -> int:
	if n <= 0:
		return 0
	var stored := mini(n, free_for(item))
	if stored > 0:
		inventory.add(item, stored, source)
	var leftover := n - stored
	if leftover > 0:
		_stash_overflow(item, leftover, source)
	return stored


## 倉庫に入りきらない分を、作業場へ預ける（作業場も拠点の一部として重さに数えるので、まずは残り重量まで）。
## それでも入らない場合（拠点全体がすでに満杯）だけ、作業場へそのまま置く（一時的に重量超過になり得るが、
## 既存アイテムを削除しない・消さない。実装指示書 2.3「旧データや競合で一時的に最大重量を超えても削除しない」）。
func _stash_overflow(item: int, n: int, source: String) -> void:
	var b = base()
	if b == null or b.processor == null:
		inventory.add(item, n, source)          # 単体テストなどで作業場が用意されていない場合の後退互換（捨てない）
		return
	var room := free_for(item)                   # 倉庫に入れた分を差し引いた、いまの残り重量で数え直す
	var take := mini(n, maxi(0, room))
	if take > 0:
		b.processor.stock.add(item, take, source)
	if take < n:
		b.processor.stock.add(item, n - take, source)   # 拠点全体が満杯でも、消さずに作業場へ置く


func butcher(species: String, source: String = Inventory.SOURCE_HUNT) -> void:
	var drops: Dictionary = GameData.CREATURES[species]["drops"]
	for it in drops:
		add_item(it, drops[it], source)
	total_butchered += 1


## 獲物を解体したとき、素材の重さのうちどれだけが、いまの残り重量に入るか（0〜1）。狩り・運搬の判断に使う。
func drop_fit(species: String) -> float:
	var drops: Dictionary = GameData.CREATURES[species]["drops"]
	var total_w := 0
	for it in drops:
		total_w += CargoDB.weight_of(it, int(drops[it]))
	if total_w <= 0:
		return 1.0
	return clampf(float(remaining_weight()) / float(total_w), 0.0, 1.0)


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
	# 個別の枠は無くなったので、拠点全体の積載率で数字の色を変える（近い・満杯は、どの素材の数字も同じ色になる）
	var r := weight_ratio()
	var col := Color("fff7c0")
	if enforce and r >= 1.0:
		col = Color("ff8a70")
	elif enforce and r >= CargoDB.WARN_RATIO:
		col = Color("ffc266")
	GameData.draw_text(self, Vector2(cx - 4, base_y - 2), "%d" % n, 12, col, 30.0, HORIZONTAL_ALIGNMENT_LEFT)
