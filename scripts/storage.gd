class_name BaseStorage
extends Node2D
## 拠点の倉庫（下の階の奥の棚）。素材は棚の上、加工品は床の上に見える。
## 獲物を運び込むと、ここで解体して肉・皮・骨・脂肪になる。

var inventory := Inventory.new()
var total_butchered := 0       # 解体した数（確認用）

const RAW_X0 := 548.0          # 棚（素材7種）の左端
const RAW_DX := 36.0
const PROD_X0 := 560.0         # 床（加工品4種）の左端
const PROD_DX := 52.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inventory.changed.connect(queue_redraw)


func add_item(item: int, n: int = 1, source: String = Inventory.SOURCE_ENVIRONMENT) -> void:
	inventory.add(item, n, source)


## 獲物を解体して素材にする（倒した・購入した・捕獲した生物で共通）。
func butcher(species: String, source: String = Inventory.SOURCE_HUNT) -> void:
	var drops: Dictionary = GameData.CREATURES[species]["drops"]
	for it in drops:
		inventory.add(it, drops[it], source)
	total_butchered += 1


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
	if n <= 0:
		# 空きスロットはうっすら表示
		draw_texture_rect(t, Rect2(Vector2(cx - sz / 2.0, base_y - sz), size), false, Color(1, 1, 1, 0.12))
		return
	for k in mini(n, 3):
		draw_texture_rect(t, Rect2(Vector2(cx - sz / 2.0, base_y - sz - k * 8), size), false)
	GameData.draw_text(self, Vector2(cx - 4, base_y - 2), "%d" % n, 12, Color("fff7c0"), 30.0, HORIZONTAL_ALIGNMENT_LEFT)
