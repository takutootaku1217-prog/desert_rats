class_name InventoryModel
extends RefCounted
## インベントリの画面が見せる「束（ItemStack）の並び」。実際の数量（Inventory の counts）に合わせて作り、画面の操作（分割・整理）を受け持つ。
## 数量そのものはここでは持たない（倉庫・作業場のデータが正）。分割した束の並びは、数量が変わっても、できるだけ保つ。
## 1スタックの最大数は ItemDB.stack_limit（通常100・道具1）。100を超える分は、新しいスタックに分かれる（実装指示書）。
##  - sync: 実際の数量に合わせる（増えた分は、既存の未満スタックを詰めてから新しいスタックを作る。減った分は後ろの束から。
##    0 の束は消える。新しいアイテムは並び順の位置へ）。
##  - split: 束を2つに分ける（例: 木材 ×20 → ×12 と ×8。分けた束は元の束のすぐ後ろに並ぶ）。上限を超える束は作らない。
##  - merge_all（整理）: 同じアイテムを、1スタックの最大数ごとに詰め直し、並び順（ItemDB.ORDER）に整える。

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
			_add_to_item(it, c - h)
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


## item を add 個ぶん増やす。まず1スタックの最大数（ItemDB.stack_limit）に満たない既存の束を詰め、
## それでも余れば、最大数ごとの新しい束を追加していく（230個 → 100・100・30 のように分かれる）。
func _add_to_item(item: int, add: int) -> void:
	var limit := ItemDB.stack_limit(item)
	var left := add
	for s in stacks:
		if left <= 0:
			break
		if s.item != item:
			continue
		var room: int = limit - int(s.n)
		if room <= 0:
			continue
		var take := mini(room, left)
		s.n += take
		left -= take
	while left > 0:
		var take := mini(limit, left)
		_insert_new(ItemStack.new(item, take))
		left -= take


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


## 束 index を、n個の束（新しい束。元の束の後ろに入る）と、残りの束に分ける。n は 1 以上、元の個数より小さい。
## 分けた2つの束は、どちらも元の束（1スタックの最大数以下）を超えないので、上限は自動的に守られる。分けられたら true。
func split(index: int, n: int) -> bool:
	if index < 0 or index >= stacks.size():
		return false
	var s: ItemStack = stacks[index]
	if n < 1 or n >= s.n:
		return false
	s.n -= n
	stacks.insert(index + 1, s.duplicate_with(n))
	return true


## 整理: 同じ（まとめてよい）束の合計を、1スタックの最大数（ItemDB.stack_limit）ごとに詰め直し、並び順に整える。
## 例: 木材×20 と 木材×8 が2束あっても、まとめて1つの巨大な束にはしない（230個の食料なら 100・100・30 の3束のまま）。
func merge_all() -> void:
	var totals: Array = []            # {item, data, n}（まとめてよい組み合わせごとの合計。最初に出てきた順）
	for s in stacks:
		var target = null
		for t in totals:
			if int(t["item"]) == s.item and t["data"] == s.data:
				target = t
				break
		if target == null:
			totals.append({"item": s.item, "data": s.data, "n": s.n})
		else:
			target["n"] += s.n
	totals.sort_custom(func(a, b): return ItemDB.order_of(int(a["item"])) < ItemDB.order_of(int(b["item"])))
	var merged: Array = []
	for t in totals:
		var left: int = t["n"]
		var limit := ItemDB.stack_limit(int(t["item"]))
		while left > 0:
			var take := mini(limit, left)
			merged.append(ItemStack.new(int(t["item"]), take, t["data"]))
			left -= take
	stacks = merged