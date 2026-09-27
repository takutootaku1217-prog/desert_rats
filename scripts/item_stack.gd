class_name ItemStack
extends RefCounted
## アイテムの「束」（同じアイテムをまとめたもの）。インベントリの画面が、束を並べて見せる（分割・整理）。
## data は個体ごとの情報（将来の装備・特殊アイテム・個体差のあるアイテム用）。今は空で、同じアイテムは何個でも1つにまとまる。
## data が違う束は、まとまらない（別々に管理される）。個体管理へ広げるときは、この data と can_stack_with だけを使う。

var item := -1
var n := 0
var data := {}


func _init(p_item: int = -1, p_n: int = 0, p_data: Dictionary = {}) -> void:
	item = p_item
	n = p_n
	data = p_data.duplicate(true)


## 同じ束にまとめてよいか（同じアイテムで、個体ごとの情報も同じ）
func can_stack_with(o: ItemStack) -> bool:
	return item == o.item and data == o.data


func duplicate_with(p_n: int) -> ItemStack:
	return ItemStack.new(item, p_n, data)