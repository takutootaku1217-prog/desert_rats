class_name InventoryModel
extends RefCounted
## インベントリの画面が見せる「束（ItemStack）の並び」。実際の数量（Inventory の counts）に合わせて作り、画面の操作（分割・整理）を受け持つ。
## 数量そのものはここでは持たない（倉庫・作業場のデータが正）。分割した束の並びは、数量が変わっても、できるだけ保つ。
##  - sync: 実際の数量に合わせる（増えた分は先頭の束へ、減った分は後ろの束から。0 の束は消える。新しいアイテムは並び順の位置へ）。
##  - split: 束を2つに分ける（例: 木材 ×20 → ×12 と ×8。分けた束は元の束のすぐ後ろに並ぶ）。
##  - merge_all（整理）: 同じアイテムを1つにまとめて、並び順（ItemDB.ORDER）に整える。

var stacks: Array = []            # ItemStack の並び


## 実際の数量 counts（アイテム → 個数）に合わせる
func sync(counts: Dictionary) -> void:
	var have := {}
	for s in stacks:
		have[s.item] = int(have.get(s.item, 0)) + s.n
	for it in counts:
		var c := int(counts[it])
		var h := int(have.get(it, 0))
		if c > h:
			var first := _first_stack_of(it)
			if first == null:
				_insert_new(ItemStack.new(it, c - h))
			else:
				first.n += c - h
		elif c < h:
			var over := h - c
			var i := stacks.size() - 1
			while over > 0 and i >= 0:
				var s: ItemStack = stacks[i]
				if s.item == it:
					var cut := mini(s.n, over)
					s.n -= cut
					over -= cut
				i -= 1
	# 数量のなくなった束・アイテムを消す
	var kept: Array = []
	for s in stacks:
		if s.n > 0 and int(counts.get(s.item, 0)) > 0:
			kept.append(s)
	stacks = kept


func _first_stack_of(item: int) -> ItemStack:
	for s in stacks:
		if s.item == item:
			return s
	return null


## 新しいアイテムの束を、並び順（ItemDB.ORDER）の位置に入れる
func _insert_new(s: ItemStack) -> void:
	var pos := stacks.size()
	for i in stacks.size():
		if ItemDB.order_of(stacks[i].item) > ItemDB.order_of(s.item):
			pos = i
			break
	stacks.insert(pos, s)


func total_of(item: int) -> int:
	var t := 0
	for s in stacks:
		if s.item == item:
			t += s.n
	return t


## 束 index を、n個の束（新しい束。元の束の後ろに入る）と、残りの束に分ける。n は 1 以上、元の個数より小さい。分けられたら true。
func split(index: int, n: int) -> bool:
	if index < 0 or index >= stacks.size():
		return false
	var s: ItemStack = stacks[index]
	if n < 1 or n >= s.n:
		return false
	s.n -= n
	stacks.insert(index + 1, s.duplicate_with(n))
	return true


## 整理: 同じ（まとめてよい）束を1つにして、アイテムの並び順に整える
func merge_all() -> void:
	var merged: Array = []
	for s in stacks:
		var target: ItemStack = null
		for m in merged:
			if m.can_stack_with(s):
				target = m
				break
		if target == null:
			merged.append(ItemStack.new(s.item, s.n, s.data))
		else:
			target.n += s.n
	merged.sort_custom(func(a, b): return ItemDB.order_of(a.item) < ItemDB.order_of(b.item))
	stacks = merged