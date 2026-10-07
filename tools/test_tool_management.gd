extends SceneTree
## 道具管理APIと在庫の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_tool_management.gd
## 個体情報画面と同じMainのAPIを使い、交換・解除・拒否・自動割り当てで道具の実数を保存する。

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
	seed(20261007)
	await _fresh()
	_test_manual_exchange()
	await _fresh()
	_test_invalid_requests()
	await _fresh()
	_test_full_storage()
	await _fresh()
	_test_automatic_assignment()
	await _fresh()
	_test_inventory_sync()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _fresh() -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	await process_frame
	main.director.enabled = false
	main.tool_auto = false
	main.storage.inventory.counts.clear()
	main.storage.capacity_bonus = 0
	main.storage.wasted.clear()
	main.total_wasted = 0
	main.processor.stock.counts.clear()
	W = main.workers
	for i in W.size():
		var w = W[i]
		w.stop_work()
		w.set_process(false)
		w.tools.clear()
		w.hp = 100.0
		w.hunger = 100.0
		w.fatigue = 0.0
		w.mental = CrewStatusDB.Mental.NORMAL
		w.level = 1
		for job in GameData.job_list():
			w.priorities[job] = 0
		for field in GameData.Field.values():
			w.ranks[field] = 0
		w.ranks[GameData.Field.GATHERER] = [6, 3, 0][i]


func _snapshot() -> Dictionary:
	var held: Array = []
	for w in W:
		held.append(w.tools.duplicate(true))
	return {"stock": main.storage.inventory.counts.duplicate(true), "held": held,
		"wasted": main.storage.wasted.duplicate(true), "total_wasted": main.total_wasted}


func _total(item: int) -> int:
	var n: int = main.storage.count_of(item) + main.processor.stock.count(item)
	for w in W:
		for slot in w.tools:
			if w.tools[slot] == item:
				n += 1
	return n


func _test_manual_exchange() -> void:
	print("-- 手動の上位交換と、片方の枠だけの解除")
	var w = W[0]
	for item in [GameData.Item.HAMMER, GameData.Item.PICKAXE, GameData.Item.AXE]:
		main.storage.add_item(item)
	check(main.tool_equip_reason(w, GameData.Item.HAMMER).is_empty() and main.equip_tool(w, GameData.Item.HAMMER), "倉庫のハンマーを採掘枠へ持たせる")
	check(main.equip_tool(w, GameData.Item.AXE) and w.tools.get("chop", -1) == GameData.Item.AXE, "別の伐採枠へ斧を持たせる")
	var notified := {"calls": 0, "complete": true}
	var on_changed: Callable = func():
		notified["calls"] += 1
		var complete: bool = main.storage.count_of(GameData.Item.HAMMER) == 1 and main.storage.count_of(GameData.Item.PICKAXE) == 0 and w.tools.get("mine", -1) == GameData.Item.PICKAXE
		notified["complete"] = notified["complete"] and complete
	main.storage.inventory.changed.connect(on_changed)
	check(main.equip_tool(w, GameData.Item.PICKAXE) and w.tools.get("mine", -1) == GameData.Item.PICKAXE, "同じ採掘枠を上位のピッケルへ交換する")
	main.storage.inventory.changed.disconnect(on_changed)
	check(notified["calls"] == 1 and notified["complete"], "在庫の変更通知は交換後に1回だけで、通知先から見える新旧数量と装備はすべて確定済み")
	check(main.storage.count_of(GameData.Item.HAMMER) == 1 and main.storage.count_of(GameData.Item.PICKAXE) == 0 and w.tools.get("chop", -1) == GameData.Item.AXE, "交換した旧道具だけが倉庫へ戻り、別枠の斧は変わらない")
	var before := _snapshot()
	check(main.tool_equip_reason(w, GameData.Item.PICKAXE).is_empty() and main.equip_tool(w, GameData.Item.PICKAXE) and _snapshot() == before, "同一道具の再選択は在庫0でも無変更で成功する")
	check(main.tool_unequip_reason(w, "mine").is_empty() and main.unequip_tool(w, "mine"), "採掘枠だけを解除できる")
	check(w.tools.get("mine", -1) < 0 and w.tools.get("chop", -1) == GameData.Item.AXE and main.storage.count_of(GameData.Item.PICKAXE) == 1, "解除は指定した枠だけを素手にして、その道具1個を返す")
	before = _snapshot()
	check(main.unequip_tool(w, "mine") and _snapshot() == before, "すでに素手の正当な枠の解除は、無変更で成功する")
	check(_total(GameData.Item.HAMMER) == 1 and _total(GameData.Item.PICKAXE) == 1 and _total(GameData.Item.AXE) == 1, "交換・再選択・解除を通して各道具の総数を保存する")


func _test_invalid_requests() -> void:
	print("-- 不在在庫、不正対象・枠・アイテムは変更を残さない")
	var w = W[0]
	main.storage.add_item(GameData.Item.AXE)
	var before := _snapshot()
	check(not main.tool_equip_reason(w, GameData.Item.ADV_PICK).is_empty() and not main.equip_tool(w, GameData.Item.ADV_PICK) and _snapshot() == before, "倉庫にない別の道具は理由を返して拒否し、在庫と装備を変えない")
	var foreign := Worker.new()
	var gone = Worker.new()
	gone.free()
	var wrong_type := Node2D.new()
	for target in [null, gone, foreign, wrong_type]:
		check(not main.tool_equip_reason(target, GameData.Item.AXE).is_empty() and not main.equip_tool(target, GameData.Item.AXE), "null・解放済み・所属外・Worker以外の装備対象を安全に拒否する")
		check(not main.tool_unequip_reason(target, "mine").is_empty() and not main.unequip_tool(target, "mine") and _snapshot() == before, "不正対象の解除も拒否し、全員の在庫・装備を変えない")
	foreign.free()
	wrong_type.free()
	for item in [-1, GameData.Item.WOOD, 999999]:
		check(not main.tool_equip_reason(w, item).is_empty() and not main.equip_tool(w, item) and _snapshot() == before, "道具でないアイテム・未知の番号を拒否し、変更しない")
	for slot in ["", "hands", "MINe"]:
		check(not main.tool_unequip_reason(w, slot).is_empty() and not main.unequip_tool(w, slot) and _snapshot() == before, "未知の枠・空文字を拒否し、変更しない")
	main.tool_auto = true
	w.away = true
	w.down = true
	check(main.equip_tool(w, GameData.Item.AXE) and main.unequip_tool(w, "chop") and _total(GameData.Item.AXE) == 1, "モデルAPIにはUI専用の自動ON・遠征中・戦闘不能の操作制限を追加しない")
	before = _snapshot()
	W[2].queue_free()
	check(not main.tool_equip_reason(W[2], GameData.Item.AXE).is_empty() and not main.equip_tool(W[2], GameData.Item.AXE) and not main.unequip_tool(W[2], "mine") and _snapshot() == before, "解放待ちの所属Workerも拒否し、解放前に在庫を消費しない")


func _test_full_storage() -> void:
	print("-- 重い素材で満杯でも、重量対象外の道具を失わず返す")
	var w = W[0]
	main.storage.add_item(GameData.Item.HAMMER)
	main.storage.add_item(GameData.Item.PICKAXE)
	check(main.equip_tool(w, GameData.Item.HAMMER), "（準備）倉庫を満たす前にハンマーを装備する")
	var ore: int = floori(float(main.storage.max_weight()) / float(CargoDB.size_of(GameData.Item.IRON_ORE)))
	main.storage.add_item(GameData.Item.IRON_ORE, ore)
	var weight: int = main.storage.current_weight()
	check(main.storage.free_for(GameData.Item.IRON_ORE) == 0 and weight == main.storage.max_weight(), "鉄鉱石で倉庫の重量上限を使い切る")
	check(main.unequip_tool(w, "mine") and main.storage.count_of(GameData.Item.HAMMER) == 1, "満杯でも、重量対象外のハンマーを解除して倉庫へ返せる")
	check(main.equip_tool(w, GameData.Item.HAMMER) and main.equip_tool(w, GameData.Item.PICKAXE), "満杯でも、旧道具を返す上位交換ができる")
	check(w.tools.get("mine", -1) == GameData.Item.PICKAXE and _total(GameData.Item.HAMMER) == 1 and _total(GameData.Item.PICKAXE) == 1, "満杯の交換でも、新旧道具をそれぞれ1個だけ保存する")
	check(main.storage.current_weight() == weight and main.storage.count_of(GameData.Item.IRON_ORE) == ore and main.total_wasted == 0 and main.storage.wasted.is_empty(), "交換・解除で重い素材の量や重量を変えず、捨てた数も増やさない")


func _test_automatic_assignment() -> void:
	print("-- 自動ONの上位割り当て・お下がりと、OFFでの抑止")
	for w in W:
		w.priorities[GameData.Job.GATHER] = 5
	main.tool_auto = true
	main.storage.add_item(GameData.Item.HAMMER)
	main.manage_tools()
	check(W[0].tools.get("mine", -1) == GameData.Item.HAMMER and _total(GameData.Item.HAMMER) == 1, "自動ONで、効果が大きい仲間へ倉庫のハンマーを割り当てる")
	main.storage.add_item(GameData.Item.PICKAXE)
	main.manage_tools()
	var passed := 0
	for w in W.slice(1):
		if w.tools.get("mine", -1) == GameData.Item.HAMMER:
			passed += 1
	check(W[0].tools.get("mine", -1) == GameData.Item.PICKAXE and passed == 1 and main.storage.count_of(GameData.Item.HAMMER) == 0, "上位道具へ交換すると、旧ハンマーは別の仲間へお下がりになる")
	check(_total(GameData.Item.HAMMER) == 1 and _total(GameData.Item.PICKAXE) == 1, "自動交換でも、新旧道具の総数を保存する")
	var before := _snapshot()
	main.manage_tools()
	check(_snapshot() == before, "改善のない再評価で装備・在庫を行き来させない")
	main.storage.add_item(GameData.Item.IRON_AXE)
	main.tool_auto = false
	before = _snapshot()
	main.manage_tools()
	check(_snapshot() == before, "自動OFFなら、倉庫の新しい道具を勝手に割り当てない")
	main.tool_auto = true
	main.manage_tools()
	check(W[0].tools.get("chop", -1) == GameData.Item.IRON_AXE and _total(GameData.Item.IRON_AXE) == 1, "自動ONへ戻すと、別枠の上位道具も総数を保って割り当てる")


func _test_inventory_sync() -> void:
	print("-- InventoryModelの束表示は、装備への移動と倉庫への出戻りに追随する")
	var w = W[0]
	main.storage.add_item(GameData.Item.HAMMER, 3)
	var model := InventoryModel.new()
	model.sync(main.storage.inventory.counts)
	check(model.total_of(GameData.Item.HAMMER) == 3, "倉庫のハンマー3個が、表示用の束へ反映される")
	check(main.equip_tool(w, GameData.Item.HAMMER), "（準備）束の中のハンマー1個を装備する")
	model.sync(main.storage.inventory.counts)
	check(model.total_of(GameData.Item.HAMMER) == 2 and _total(GameData.Item.HAMMER) == 3, "装備へ移った1個は倉庫表示から減り、全体の実数は3個のまま")
	check(main.unequip_tool(w, "mine"), "（準備）装備していたハンマーを倉庫へ戻す")
	model.sync(main.storage.inventory.counts)
	check(model.total_of(GameData.Item.HAMMER) == 3 and _total(GameData.Item.HAMMER) == 3, "装備品の出戻りが束へ反映され、在庫・装備の総数を増やさない")
