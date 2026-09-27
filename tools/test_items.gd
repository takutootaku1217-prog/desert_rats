extends SceneTree
## アイテム・インベントリ・制作システム（仕様書 v0.1）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_items.gd
## 確かめる: アイテムの情報（ItemDB）→ 束の並び（ItemStack・InventoryModel。分割・整理）→ 制作の一覧と判定（CraftDB）→
##   倉庫と作業場の分離と運搬（仲間が運ぶ）→ 手動の制作（作業場の材料だけを使う）→ 既存の自動の加工は変わらないこと →
##   画面（インベントリ・制作）。ゲームの数値・既存の仕組みは変えていない。

var fails := 0
var main
var W := []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260927)
	await _fresh(false)
	_test_itemdb()
	_test_model()
	await _test_craftdb()
	await _test_transfer()
	await _test_craft()
	await _test_auto_unchanged()
	await _test_ui()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## ゲームを新しく作る（all_facilities: 設備が最初から全部ある状態にするか）。仲間は自分では動かさない（診断が1コマずつ進める）
func _fresh(all_facilities := true) -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = all_facilities
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	W = main.workers
	for w in W:
		w.set_process(false)
		w.ai.timer = 100.0
		for j in GameData.job_list():
			w.priorities[j] = 0
	main.storage.inventory.counts.clear()
	main.processor.stock.counts.clear()


func _set_storage(counts: Dictionary) -> void:
	main.storage.inventory.counts.clear()
	for it in counts:
		main.storage.inventory.counts[it] = int(counts[it])


## w を1コマずつ進めて、cond が true になるまで待つ（最大 secs 秒）
func _run_until(w, cond: Callable, secs: float, dt := 0.1) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		w._process(dt)
		main._feed_crafts()
		t += dt
	return cond.call()


# ---------------------------------------------------------------- アイテムの情報
func _test_itemdb() -> void:
	print("-- アイテムの情報（ItemDB）: 名前・分類・色・使い道・入手先")
	var all := ItemDB.all()
	var ok := true
	for it in all:
		ok = ok and ItemDB.name_of(it) != "?" and ItemDB.CATEGORIES.has(ItemDB.category_of(it)) and ItemDB.tex(it) != null
	check(ok and all.size() == 16, "インベントリに出る16種すべてに、名前・分類・絵がある")
	var covered := true
	for it in GameData.RAW_ITEMS + GameData.PRODUCT_ITEMS + GameData.TOOL_ITEMS:
		covered = covered and all.has(it)
	check(covered and not all.has(GameData.Item.CARCASS), "倉庫に入る物はすべて並ぶ（獲物は運搬中の物なので出ない）")
	check(ItemDB.category_of(GameData.Item.WOOD) == "素材" and ItemDB.category_of(GameData.Item.IRON) == "加工品" and ItemDB.category_of(GameData.Item.FOOD) == "食料"
			and ItemDB.category_of(GameData.Item.FUEL) == "燃料" and ItemDB.category_of(GameData.Item.AXE) == "道具", "分類: 木材=素材・鉄=加工品・食料・燃料・斧=道具")
	var order_ok := true
	for i in all.size() - 1:
		order_ok = order_ok and ItemDB.CATEGORIES.find(ItemDB.category_of(all[i])) <= ItemDB.CATEGORIES.find(ItemDB.category_of(all[i + 1]))
	check(order_ok, "並び順は、分類の順（素材 → 加工品 → 食料 → 燃料 → 道具）")
	var uses := ItemDB.uses_of(GameData.Item.WOOD)
	var has_build := false
	var has_recipe := false
	for u in uses:
		has_build = has_build or (u["kind"] == "build" and u["id"] == "workbench")
		has_recipe = has_recipe or (u["kind"] == "recipe" and u["id"] == "firewood")
	check(has_build and has_recipe, "木材の使い道は、加工のレシピと設備の材料から数える（薪・ワークベンチ ほか %d 件）" % uses.size())
	check(ItemDB.sources_of(GameData.Item.WOOD) == ["採取"] and ItemDB.sources_of(GameData.Item.MEAT) == ["狩猟"] and ItemDB.sources_of(GameData.Item.IRON) == ["加工"], "入手先: 木材=採取・生肉=狩猟・鉄=加工")
	check(ItemDB.color_of(GameData.Item.FOOD) != ItemDB.color_of(GameData.Item.FUEL), "分類ごとに色がある（一目で見分ける）")


# ---------------------------------------------------------------- 束の並び（分割・整理）
func _test_model() -> void:
	print("-- 束の並び（ItemStack・InventoryModel）: 分割・整理・数量の追従")
	var W_ := GameData.Item.WOOD
	var S_ := GameData.Item.STONE
	var m := InventoryModel.new()
	m.sync({W_: 20, S_: 5})
	check(m.stacks.size() == 2 and m.total_of(W_) == 20 and m.total_of(S_) == 5, "数量に合わせて、アイテムごとに束ができる（木材 20・石 5）")
	check(m.stacks[0].item == W_ and m.stacks[1].item == S_, "束は、アイテムの並び順（木材 → 石）")
	check(m.split(0, 8) and m.stacks.size() == 3, "分割: 木材 ×20 → 2つの束に分かれる")
	check(m.stacks[0].n == 12 and m.stacks[1].n == 8 and m.stacks[1].item == W_ and m.stacks[2].item == S_, "木材 ×12 と 木材 ×8（分けた束は、元のすぐ後ろ）")
	check(not m.split(0, 12) and not m.split(0, 0) and not m.split(9, 1), "分けられない数（全部・0・存在しない束）は分割しない")
	check(m.total_of(W_) == 20, "分割しても、合計は変わらない")
	m.sync({W_: 25, S_: 5})
	check(m.stacks[0].n == 17 and m.stacks[1].n == 8, "数量が増えたら、先頭の束に足される（分割は保たれる）")
	m.sync({W_: 10, S_: 5})
	check(m.total_of(W_) == 10 and m.stacks[0].n == 10, "数量が減ったら、後ろの束から減る（17 と 8 → 10）")
	check(m.stacks.size() == 2 and m.stacks[1].item == S_, "0 になった束（8 の束）は消える")
	m.sync({W_: 10})
	check(m.total_of(S_) == 0 and not m.stacks.any(func(s): return s.item == S_), "数量が 0 になったアイテムは、並びから消える")
	m.sync({W_: 10, GameData.Item.MEAT: 3, GameData.Item.IRON: 2})
	check(m.stacks[0].item == GameData.Item.MEAT and m.stacks[m.stacks.size() - 1].item == GameData.Item.IRON, "新しく入ったアイテムは、並び順の位置に入る（生肉が先頭・鉄が後ろ）")
	var mm := InventoryModel.new()
	mm.sync({W_: 20})
	mm.split(0, 8)
	mm.split(0, 4)
	check(mm.stacks.size() == 3, "何回でも分けられる（12 → 8 と 4 と 8）")
	mm.merge_all()
	check(mm.stacks.size() == 1 and mm.stacks[0].n == 20, "整理: 同じアイテムは1つにまとまる（木材 ×20）")
	var cmp := InventoryModel.new()
	cmp.sync({GameData.Item.FUEL: 1, GameData.Item.WOOD: 2, GameData.Item.MEAT: 3})
	cmp.stacks.reverse()
	cmp.merge_all()
	check(cmp.stacks[0].item == GameData.Item.MEAT and cmp.stacks[2].item == GameData.Item.FUEL, "整理: アイテムの並び順に整う")
	# 個体差のあるアイテム（将来）は、まとまらない
	var a := ItemStack.new(GameData.Item.AXE, 1, {"quality": 3})
	var b := ItemStack.new(GameData.Item.AXE, 1, {"quality": 5})
	var c := ItemStack.new(GameData.Item.AXE, 2)
	var d := ItemStack.new(GameData.Item.AXE, 1)
	check(not a.can_stack_with(b) and not a.can_stack_with(c) and c.can_stack_with(d), "個体ごとの情報（data）が違う束は、まとまらない（将来の装備・特殊アイテム用。今は空で、同じアイテムは全部まとまる）")
	var ind := InventoryModel.new()
	ind.stacks = [a, b, c, d]
	ind.merge_all()
	check(ind.stacks.size() == 3, "整理しても、個体差のある物は別々のまま（%d つの束）" % ind.stacks.size())


# ---------------------------------------------------------------- 制作の一覧と判定
func _test_craftdb() -> void:
	print("-- 制作の一覧と判定（CraftDB）: 作れる／材料不足／解放待ち／置き場なし／建設")
	await _fresh(false)                                            # 設備なしで始める（ワークベンチがない）
	var es := CraftDB.entries()
	check(es.size() == GameData.RECIPES.size() + FacilityDB.ids().size(), "一覧は、加工のレシピ（%d）と設備の建設（%d）の全部" % [GameData.RECIPES.size(), FacilityDB.ids().size()])
	var cats := CraftDB.categories_in_use()
	check(cats.has("道具") and cats.has("建設") and cats.has("料理") and cats.has("加工") and not cats.has("装備"), "分類は、エントリのあるものだけ出る（%s。装備・その他は、まだない）" % str(cats))
	var known := true
	for e in es:
		known = known and CraftDB.CATEGORIES.has(e["cat"])
	check(known, "どのエントリも、分類の表にある分類に入っている（分類は増減できる）")
	# 材料は作業場で数える
	_set_storage({GameData.Item.STONE: 50, GameData.Item.WOOD: 50})
	var hammer := CraftDB.entry_of("tool_hammer")               # 石2＋木材1（手作業）
	var ev: Dictionary = CraftDB.evaluate(hammer, main, 1)
	check(ev["state"] == "short" and ev["source"] == "作業場", "倉庫に石も木材も50個あっても、作業場に無ければ「材料不足」（倉庫の分は使えない）")
	check(ev["can_transfer"] and ev["missing"].size() == 2, "足りない分が倉庫にあるので、「運べば作れる」と分かる")
	var rows: Array = ev["rows"]
	check(rows.size() == 2 and rows[0]["have"] == 0 and rows[0]["need"] in [1, 2] and not rows[0]["ok"] and rows[0]["in_storage"] == 50, "行: 必要数・作業場の数・倉庫の数（0 / 必要。倉庫 50）")
	main.processor.stock.add(GameData.Item.STONE, 2)
	main.processor.stock.add(GameData.Item.WOOD, 1)
	ev = CraftDB.evaluate(hammer, main, 1)
	check(ev["state"] == "ok" and ev["max_qty"] == 1 and ev["rows"].all(func(r): return r["ok"]), "作業場に石2・木材1があれば「作れる」（最大 1 回）")
	main.processor.stock.add(GameData.Item.STONE, 8)
	main.processor.stock.add(GameData.Item.WOOD, 4)
	ev = CraftDB.evaluate(hammer, main, 1)
	check(ev["max_qty"] == 5, "石10・木材5なら、最大 5 回（材料の少ないほうで決まる）")
	ev = CraftDB.evaluate(hammer, main, 6)
	check(ev["state"] == "short" and ev["can_transfer"] and ev["missing"][GameData.Item.STONE] == 2, "6回分は足りない（石12・木材6が要る。足りない分は倉庫にある）")
	# 必要設備がない（解放待ち）
	var pick := CraftDB.entry_of("tool_pick")                    # ワークベンチが必要
	ev = CraftDB.evaluate(pick, main, 1)
	check(ev["state"] == "locked" and ev["reason"] == "ワークベンチが必要" and ev["hint"].contains("建設"), "ワークベンチがないうちは「解放待ち」で、何をすれば解放されるか（ワークベンチの建設）が分かる")
	# 建設
	var wb := CraftDB.entry_of("build:workbench")
	ev = CraftDB.evaluate(wb, main, 1)
	check(ev["source"] == "倉庫" and ev["state"] in ["ok", "short"], "建設は、これまでどおり倉庫の材料で数える（材料は仲間が自動で運ぶ）")
	var bed := CraftDB.entry_of("build:bed")
	ev = CraftDB.evaluate(bed, main, 1)
	check(ev["state"] == "locked" and ev["reason"].contains("ワークベンチ"), "ベッドは、ワークベンチが必要（解放待ち）")
	# 置き場がいっぱい
	main.storage.inventory.counts[GameData.Item.HAMMER] = 0
	main.storage.quota[GameData.Item.FOOD] = 3
	main.storage.inventory.counts[GameData.Item.FOOD] = 3
	main.processor.stock.add(GameData.Item.MEAT, 2)
	ev = CraftDB.evaluate(CraftDB.entry_of("cook"), main, 1)
	check(ev["state"] == "blocked" and ev["reason"] == "置き場がいっぱい" and ev["max_qty"] == 0, "作った物の置き場（倉庫の枠）がいっぱいなら「置き場がいっぱい」（捨てないため、作れない）")


# ---------------------------------------------------------------- 倉庫と作業場・運搬
func _test_transfer() -> void:
	print("-- 倉庫と作業場は別（運ぶまで材料は移らない）。運搬は仲間が行う")
	await _fresh(true)
	var st: BaseStorage = main.storage
	var P: BaseProcessor = main.processor
	st.quota[GameData.Item.WOOD] = 40                             # 倉庫へ戻す試験のため、枠を広げる
	_set_storage({GameData.Item.WOOD: 20, GameData.Item.STONE: 5})
	check(main.workshop_count(GameData.Item.WOOD) == 0 and P.stock.count(GameData.Item.WOOD) == 0, "作業場の材料置き場は、最初は空（倉庫とは別の置き場）")
	check(main.request_craft("tool_hammer", 1) == 0 and main.craft_queue.is_empty(), "倉庫に材料が100個あっても、作業場に無ければ、手動の制作は頼めない")
	# 運搬の依頼の検証
	check(main.request_transfer(GameData.Item.WOOD, 100, "to_workshop") == 20, "倉庫にある分（20）までしか頼めない")
	check(main.request_transfer(GameData.Item.WOOD, 5, "to_workshop") == 0, "すでに全部頼んだので、それ以上は頼めない")
	check(main.request_transfer(GameData.Item.CARCASS, 1, "to_workshop") == 0 and main.request_transfer(GameData.Item.STONE, 0, "to_workshop") == 0, "獲物・0個は頼めない")
	check(main.request_transfer(GameData.Item.STONE, 3, "to_storage") == 0, "作業場にない物は、倉庫へ戻す依頼にならない")
	main.cancel_transfers()
	check(main.transfer_queue.is_empty(), "運搬の依頼は取り消せる")
	# 仲間が運ぶ（運搬の仕事 = HAUL の優先度がある仲間だけ）
	var w = W[0]
	w.priorities[GameData.Job.HAUL] = 3
	var w2 = W[1]
	w2.priorities[GameData.Job.HAUL] = 3
	check(main.request_transfer(GameData.Item.WOOD, 8, "to_workshop") == 8, "木材 8 個を作業場へ運ぶ依頼")
	for x in [w, w2]:
		x.ai.state = CharacterAI.State.SEARCH
		x._process(0.1)
	var states := [w.ai.state, w2.ai.state]
	check((states[0] == CharacterAI.State.XFER_TAKE) != (states[1] == CharacterAI.State.XFER_TAKE), "運搬の依頼を引き受けるのは、同時に1人だけ（もう1人はこれまでの仕事）")
	var carrier = w if w.ai.state == CharacterAI.State.XFER_TAKE else w2
	var other = w2 if carrier == w else w
	other.priorities[GameData.Job.HAUL] = 0
	check(main.transfer_worker == carrier, "引き受けた仲間が記録される")
	check(_run_until(carrier, func(): return carrier.ai.state == CharacterAI.State.XFER_MOVE, 40.0), "倉庫へ着いて、材料を取る")
	check(carrier.carrying == GameData.Item.WOOD and carrier.carry_n == CraftDB.TRANSFER_TRIP, "1回に運ぶのは、袋の大きさ（%d 個）" % CraftDB.TRANSFER_TRIP)
	check(st.count_of(GameData.Item.WOOD) == 20 - CraftDB.TRANSFER_TRIP and P.stock.count(GameData.Item.WOOD) == 0, "運んでいる間は、倉庫から減り、作業場にはまだ入っていない（物が動いている）")
	check(main.transfer_queue[0]["n"] == 8 - CraftDB.TRANSFER_TRIP, "依頼の残りが減る")
	check(_run_until(carrier, func(): return P.stock.count(GameData.Item.WOOD) == CraftDB.TRANSFER_TRIP, 40.0), "作業場へ着いて、材料を置く")
	check(carrier.carrying == -1 and main.transfer_worker == null, "置いたら、手ぶらに戻り、引き受けを返す")
	# 最後まで運ぶ（合計 8）
	var done := _run_until(carrier, func(): return P.stock.count(GameData.Item.WOOD) == 8 and main.transfer_queue.is_empty() and carrier.ai.state != CharacterAI.State.XFER_MOVE, 200.0)
	check(done and st.count_of(GameData.Item.WOOD) == 12 and main.total_transferred == 8, "全部で 8 個が作業場へ移った（倉庫 12・作業場 8・運んだ数 %d）" % main.total_transferred)
	# 途中で仲間が離れても、物は消えない
	main.request_transfer(GameData.Item.STONE, 5, "to_workshop")
	carrier.ai.state = CharacterAI.State.SEARCH
	carrier.priorities[GameData.Job.HAUL] = 3
	carrier._process(0.1)
	check(carrier.ai.state == CharacterAI.State.XFER_TAKE, "（準備）石を運びに行く")
	check(_run_until(carrier, func(): return carrier.ai.state == CharacterAI.State.XFER_MOVE, 40.0), "（準備）石を持った")
	var stone_total: int = st.count_of(GameData.Item.STONE) + carrier.carry_n + P.stock.count(GameData.Item.STONE)
	carrier.depart()
	check(st.count_of(GameData.Item.STONE) + P.stock.count(GameData.Item.STONE) == stone_total and main.transfer_worker == null, "運搬の途中で遠征に出ても、持っていた物は倉庫に戻る（消えない）。引き受けも返す")
	carrier.arrive(80.0)
	carrier.set_process(false)
	main.cancel_transfers()
	# 戻す（作業場 → 倉庫）
	carrier.priorities[GameData.Job.HAUL] = 3
	check(main.request_transfer(GameData.Item.WOOD, 100, "to_storage") == 8, "作業場にある分（8）までを、倉庫へ戻す依頼にできる")
	carrier.ai.state = CharacterAI.State.SEARCH
	check(_run_until(carrier, func(): return st.count_of(GameData.Item.WOOD) == 20 and main.transfer_queue.is_empty() and carrier.ai.state == CharacterAI.State.SEARCH, 200.0), "作業場から倉庫へ戻せる（倉庫 20）")
	check(P.stock.count(GameData.Item.WOOD) == 0, "戻した分は、作業場から無くなる")
	# 元に材料がなくなった依頼は消える（詰まらない）
	main.request_transfer(GameData.Item.WOOD, 5, "to_workshop")
	st.inventory.counts[GameData.Item.WOOD] = 0
	check(main.next_transfer().is_empty() and main.transfer_queue.is_empty(), "倉庫にもう材料がない依頼は、消える（仲間が空振りしない）")
	carrier.priorities[GameData.Job.HAUL] = 0


# ---------------------------------------------------------------- 手動の制作
func _test_craft() -> void:
	print("-- 手動の制作（作業場の材料だけを使う）。既存の加工の仕組みへ接続する")
	await _fresh(true)
	var P: BaseProcessor = main.processor
	var st: BaseStorage = main.storage
	var w = W[0]
	w.priorities[GameData.Job.PROCESS] = 3
	P.stock.add(GameData.Item.STONE, 6)
	P.stock.add(GameData.Item.WOOD, 3)
	check(main.request_craft("tool_hammer", 5) == 3, "作業場の材料（石6・木材3）の範囲（3回）まで頼める")
	check(main.workshop_reserved(GameData.Item.STONE) == 6 and main.workshop_available(GameData.Item.STONE) == 0, "頼んだ分の材料は、ほかの制作に使えない（取り置き）")
	check(main.request_craft("tool_hammer", 1) == 0, "材料が残っていなければ、追加は頼めない")
	check(main.request_craft("tool_pick", 1) == 0, "（必要設備があっても）材料が作業場になければ頼めない")
	# 注文になる（加工設備の空きの範囲）
	main._feed_crafts()
	check(P.orders.size() == BaseProcessor.ORDER_CAP and P.stock.count(GameData.Item.STONE) == 0 and main.craft_queue.is_empty(), "材料が作業場から取り出されて、加工設備の注文になる（%d 件）" % P.orders.size())
	check(P.orders[0].get("manual", false) and P.orders[0]["out"] == GameData.Item.HAMMER, "注文は、手動の制作の印つき。中身は自動の加工と同じ形")
	# 加工が終わると、加工品置き場（倉庫）に入る
	var hammers0: int = st.count_of(GameData.Item.HAMMER)
	w.ai.state = CharacterAI.State.SEARCH
	var finished := _run_until(w, func(): return st.count_of(GameData.Item.HAMMER) >= hammers0 + 3, 200.0)
	check(finished and main.total_crafted_by_hand == 3, "仲間が加工して、完成品が倉庫に入る（簡易ハンマー +3。手動で作った回数 %d）" % main.total_crafted_by_hand)
	check(P.stock.count(GameData.Item.STONE) == 0 and P.stock.count(GameData.Item.WOOD) == 0, "材料は使い切った（作業場の材料も、注文も、残らない）")
	# 数量（1・5・全部）
	st.quota[GameData.Item.FOOD] = 50
	P.stock.add(GameData.Item.MEAT, 7)
	var ev: Dictionary = CraftDB.evaluate(CraftDB.entry_of("cook"), main, 1)
	check(ev["max_qty"] == 7, "「全部」= 材料の範囲の最大回数（生肉 7 個 → 7 回）")
	check(main.request_craft("cook", ev["max_qty"]) == 7, "最大回数を頼める")
	main.cancel_craft(0)
	check(main.craft_queue.is_empty() and P.stock.count(GameData.Item.MEAT) == 7, "待ちの制作を取り消すと、材料は作業場に残る")
	# 建設は制作の一覧に出るが、材料はこれまでどおり倉庫から
	var bed := CraftDB.entry_of("build:bed")
	check(main.request_craft("build:bed", 1) == 0, "建設は、手動の制作の待ち（作業場の材料）にはならない（これまでの建設の依頼を使う）")


# ---------------------------------------------------------------- 自動の加工は変わらない
func _test_auto_unchanged() -> void:
	print("-- 既存の自動の加工（choose_recipe → 運搬 → 注文）は変わらない")
	await _fresh(true)
	_set_storage({GameData.Item.MEAT: 5, GameData.Item.WOOD: 10, GameData.Item.STONE: 10, GameData.Item.IRON_ORE: 3, GameData.Item.HIDE: 4, GameData.Item.BONE: 3, GameData.Item.FAT: 3})
	var r0: Dictionary = main.choose_recipe()
	main.processor.stock.add(GameData.Item.MEAT, 50)
	main.processor.stock.add(GameData.Item.WOOD, 50)
	var r1: Dictionary = main.choose_recipe()
	check(r0.get("id", "") == r1.get("id", "x") and r0.get("id", "") != "", "作業場に材料があっても、自動の加工の選び方は変わらない（%s）" % r0.get("name", ""))
	# 自動の運搬は、倉庫から材料を運んで注文にする（作業場の材料は使わない）
	var w = W[0]
	w.priorities[GameData.Job.HAUL] = 3
	var meat0: int = main.storage.count_of(GameData.Item.MEAT)
	var stock_meat0: int = main.processor.stock.count(GameData.Item.MEAT)
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state == CharacterAI.State.HAUL_TAKE or w.ai.state == CharacterAI.State.REFUEL_TAKE, "自動の加工の運搬は、これまでどおり始まる（運搬の依頼がなければ）")
	w.ai.state = CharacterAI.State.SEARCH
	w.ai._release_task()
	w.priorities[GameData.Job.HAUL] = 0
	check(main.processor.stock.count(GameData.Item.MEAT) == stock_meat0 and main.storage.count_of(GameData.Item.MEAT) == meat0, "作業場の材料は、自動の加工に使われない（作業場の生肉 %d・倉庫の生肉 %d のまま）" % [stock_meat0, meat0])
	# 依頼が空なら、既存の動きに何も足さない
	check(main.transfer_queue.is_empty() and main.craft_queue.is_empty() and main.transfer_worker == null, "手動の依頼がなければ、何も起きない")


# ---------------------------------------------------------------- 画面
func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


func _count_type(node: Node, cls: String) -> int:
	var n := 1 if node.is_class(cls) else 0
	for c in node.get_children():
		n += _count_type(c, cls)
	return n


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _test_ui() -> void:
	print("-- 画面（インベントリ・制作）")
	await _fresh(true)
	var inv: InventoryUI = main.inventory_ui
	var craft: CraftUI = main.craft_ui
	check(inv != null and craft != null and inv.game == main and craft.game == main, "インベントリと制作の画面がある")
	var b_inv := _find_button(inv, "インベントリ (Tab)")
	var b_craft := _find_button(craft, "制作 (F)")
	check(b_inv != null and b_craft != null, "右のボタン列に「インベントリ (Tab)」「制作 (F)」がある")
	var others_ok := true
	for b in [_find_button(main.build_ui, "建設 (B)"), _find_button(main.room_ui, "部屋の変更 (R)"), _find_button(main.detail, "仲間の管理 (C)")]:
		others_ok = others_ok and b != null and not b.get_global_rect().intersects(b_inv.get_global_rect()) and not b.get_global_rect().intersects(b_craft.get_global_rect())
	check(others_ok and not b_inv.get_global_rect().intersects(b_craft.get_global_rect()), "新しいボタンは、ほかのボタンに重ならない（建設・部屋の変更・仲間の管理は残っている）")
	# ---- インベントリ
	_set_storage({GameData.Item.WOOD: 20, GameData.Item.STONE: 18, GameData.Item.MEAT: 8, GameData.Item.IRON: 1})
	main.storage.quota[GameData.Item.WOOD] = 40
	inv._unhandled_input(_key(KEY_TAB))
	await process_frame
	check(inv.is_open(), "Tab キーでインベントリが開く")
	var st_rows := inv._model().stacks
	check(st_rows.size() == 4 and st_rows[0].item == GameData.Item.MEAT and st_rows[1].item == GameData.Item.WOOD, "アイテムが並ぶ（生肉・木材・石・鉄。数が0の物は出ない）")
	check(inv._list.get_child_count() == 4, "一覧の行は、アイテムの数だけ（アイコン・名前・分類・数量）")
	var first_row := inv._list.get_child(1)
	check(_count_type(first_row, "TextureRect") == 1 and _count_type(first_row, "Label") == 3, "1行は「絵1つ・名前・分類の札・数量」（文字を増やしていない）")
	var wood_i := 1
	inv._select(wood_i)
	check(inv.selected_stack().item == GameData.Item.WOOD and inv._detail.get_child_count() > 3, "アイテムを選ぶと、詳細（絵・名前・入手先・使い道・数量・操作）が出る")
	# 分割
	inv._split_btn.pressed.emit()
	check(inv._split_box.visible, "「分割」で、分ける数の選び方が出る")
	inv._split_qty.set_value(8)
	inv._do_split()
	check(inv._model().stacks.size() == 5 and inv._model().stacks[1].n == 12 and inv._model().stacks[2].n == 8, "木材 ×20 が 木材 ×12 と 木材 ×8 に分かれて並ぶ")
	check(main.storage.count_of(GameData.Item.WOOD) == 20, "分割しても、倉庫の木材は 20 のまま（画面上の束の分け方だけ）")
	inv._refresh(true)
	check(inv._list.get_child_count() == 5, "一覧の行が増える")
	# 分けた束のうち、×8 を運ぶ
	inv._select(2)
	check(inv.selected_stack().n == 8 and inv._qty.max_value == 8, "分けた ×8 の束を選ぶと、選べる最大は 8")
	inv._qty.set_value(8)
	inv._move_btn.pressed.emit()
	check(main.transfer_queue.size() == 1 and main.transfer_queue[0]["item"] == GameData.Item.WOOD and main.transfer_queue[0]["n"] == 8 and main.transfer_queue[0]["dir"] == "to_workshop", "「作業場へ運ぶ」で、選んだ数（8）の運搬の依頼になる")
	check(inv._msg.text.contains("運搬を頼んだ"), "結果が画面に出る（%s）" % inv._msg.text)
	main.cancel_transfers()
	# 整理
	inv._sort()
	check(inv._model().stacks.size() == 4 and inv._model().stacks[1].n == 20, "「整理」で、同じアイテムが1つにまとまる（木材 ×20）")
	# 作業場
	inv._set_tab(1)
	check(inv._model().stacks.is_empty() and inv._list.get_child_count() == 1, "作業場は、最初は空（倉庫とは別の置き場）")
	main.processor.stock.add(GameData.Item.STONE, 4)
	main.processor.orders.append(GameData.recipe_by_id("cook").duplicate())
	inv._refresh(true)
	check(inv._model().stacks.size() == 1 and inv._model().stacks[0].item == GameData.Item.STONE, "作業場に運ばれた材料が、作業場の一覧に出る")
	check(inv._list.get_child_count() >= 3, "加工待ち（注文に割り当て済み）の材料も、見るだけの行で出る")
	inv._select(0)
	check(inv._move_btn.text == "倉庫へ戻す", "作業場では、「倉庫へ戻す」になる")
	main.processor.orders.clear()
	# 制作へ
	_find_button(inv, "制作").pressed.emit()
	await process_frame
	check(craft.is_open() and not inv.is_open(), "インベントリの［制作］で、制作の画面が開く（インベントリは閉じる）")
	inv._unhandled_input(_key(KEY_ESCAPE))
	# ---- 制作
	check(craft._cat == "道具" and craft._list.get_child_count() == 5, "制作の画面: 分類「道具」に5つ（簡易ハンマー・簡易の斧・鉄製ピッケル・鉄の斧・高性能ピッケル）")
	check(_find_button(craft, "道具") != null and _find_button(craft, "建設") != null and _find_button(craft, "料理") != null and _find_button(craft, "加工") != null and _find_button(craft, "装備") == null, "分類の切り替え（道具・建設・料理・加工。エントリのない分類は出ない）")
	craft.open_entry("tool_hammer")
	main.processor.stock.counts.clear()
	craft._refresh(true)
	var rows_in_detail := 0
	for c in craft._detail.get_children():
		if c is PanelContainer and c.get_child_count() > 0 and c.get_child(0) is HBoxContainer and _count_type(c, "TextureRect") >= 2:
			rows_in_detail += 1
	check(rows_in_detail == 2, "必要な材料の行は、材料の数（石・木材の2つ）")
	check(craft._craft_btn.disabled and not craft._carry_btn.disabled, "材料が作業場になければ［制作］は押せず、倉庫にあるので［素材を運ぶ］は押せる")
	craft._carry_btn.pressed.emit()
	check(main.transfer_queue.size() == 2, "［素材を運ぶ］で、足りない材料（石・木材）の運搬の依頼が入る")
	main.cancel_transfers()
	main.processor.stock.add(GameData.Item.STONE, 12)
	main.processor.stock.add(GameData.Item.WOOD, 6)
	craft._refresh(true)
	check(not craft._craft_btn.disabled, "作業場に材料が揃うと、［制作］が押せる")
	craft._qty.set_value(5)
	check(craft._qty_val == 5, "回数を 5 に選べる")
	craft._qty.set_value(0)
	craft._refresh(true)
	craft._qty_val = 99
	craft._refresh(true)
	check(craft._qty.max_value == 15 and craft._qty.all_value == 6, "選べる最大は、倉庫の材料も運べば作れる回数（15）。「全部」は、いま作れる最大の回数（6）")
	craft._qty_val = 1
	craft._refresh(true)
	_find_button(craft._qty, "全部").pressed.emit()
	check(craft._qty.value == 6 and craft._qty_val == 6, "「全部」を押すと、いま作れる最大の回数（6 回。石12・木材6）になる")
	craft._qty.set_value(5)
	craft._do_craft()
	check(main.craft_queue.size() == 1 and main.craft_queue[0]["n"] == 5, "［制作］で、5回分の制作の待ちが入る")
	check(craft._msg.text.contains("制作を頼んだ"), "結果が画面に出る（%s）" % craft._msg.text)
	main.cancel_craft(0)
	# 建設
	craft._select_cat("建設")
	craft._select_entry("build:workbench")
	check(craft._craft_btn.text == "建設を依頼する", "建設は［建設を依頼する］（これまでの建設の依頼）")
	# 解放待ち（設備なしの世界で）
	await _fresh(false)
	main.craft_ui.open_entry("tool_pick")
	var lock_found := false
	for c in main.craft_ui._detail.get_children():
		if c is HBoxContainer and _count_type(c, "TextureRect") >= 1:
			for cc in c.get_children():
				if cc is Label and (cc as Label).text.contains("ワークベンチが必要"):
					lock_found = true
	check(lock_found, "解放待ちの物は、鍵の印と「ワークベンチが必要」が出る")
	check(_find_button(main.craft_ui, "建設の画面へ (B)") != null, "何をすれば解放されるか分かる（［建設の画面へ］）")
	check(main.craft_ui._craft_btn.disabled, "解放待ちの物は、［制作］が押せない")
	main.craft_ui.close()
	# 画面は同時に1つ
	main.build_ui.open()
	main.inventory_ui.open()
	check(not main.build_ui._overlay.visible and main.inventory_ui.is_open(), "別の画面を開くと、ほかの画面は閉じる（重ならない）")
	main.inventory_ui.close()