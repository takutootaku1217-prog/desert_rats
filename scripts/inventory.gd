class_name Inventory
extends RefCounted
## アイテムの持ち物（倉庫の中身）。
## 環境物資・敵ドロップ・探索隊の持ち帰りは、すべてここへ add() で入る。
## source で入手元を区別できる（将来の統計・演出用）。

signal changed
signal item_added(item: int, amount: int, source: String)

const SOURCE_ENVIRONMENT := "environment"
const SOURCE_ENEMY_DROP := "enemy_drop"       # 将来: 敵ドロップ
const SOURCE_EXPEDITION := "expedition"       # 将来: 探索隊の持ち帰り
const SOURCE_PROCESSING := "processing"
const SOURCE_HUNT := "hunt"                   # 生物を倒して解体
const SOURCE_CAPTURE := "capture"             # 将来: 捕獲した生物から
const SOURCE_PURCHASE := "purchase"           # 将来: 購入（今はテスト用のみ）
const SOURCE_TRANSFER := "transfer"           # 倉庫 ⇄ 作業場の運搬（アイテム・インベントリ・制作。増えたのではなく、置き場が変わっただけ）

var counts := {}


func add(item: int, amount: int = 1, source: String = SOURCE_ENVIRONMENT) -> void:
	counts[item] = counts.get(item, 0) + amount
	item_added.emit(item, amount, source)
	changed.emit()


func take(item: int) -> bool:
	if counts.get(item, 0) <= 0:
		return false
	counts[item] -= 1
	changed.emit()
	return true


## item を n 個まで取り出す。取り出せた個数を返す（足りなければ、あるだけ）
func take_n(item: int, n: int) -> int:
	var got := mini(maxi(0, n), counts.get(item, 0))
	if got > 0:
		counts[item] -= got
		changed.emit()
	return got


func count(item: int) -> int:
	return counts.get(item, 0)


func has_any_of(items: Array) -> bool:
	for it in items:
		if counts.get(it, 0) > 0:
			return true
	return false


## 必要な素材がすべて揃っていれば、まとめて取り出す（揃っていなければ何も取らない）。
func take_set(need: Dictionary) -> bool:
	for it in need:
		if counts.get(it, 0) < need[it]:
			return false
	for it in need:
		counts[it] -= need[it]
	changed.emit()
	return true


func has_set(need: Dictionary) -> bool:
	for it in need:
		if counts.get(it, 0) < need[it]:
			return false
	return true


## items のうち最初に在庫があるものを1つ取り出す（なければ -1）。
func take_any_of(items: Array) -> int:
	for it in items:
		if take(it):
			return it
	return -1
