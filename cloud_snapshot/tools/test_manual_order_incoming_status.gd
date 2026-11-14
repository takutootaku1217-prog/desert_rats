extends SceneTree
## 手動の製作注文が、実AIの引受け（HAUL_TAKE / HAUL_MOVE）で processor.incoming へ移っている間も、
## 製作画面の内訳（Processor.manual_status → CraftUI の BatchStatus）に1回として数えられること。
##
## 範囲: 通常の main シーン（first_region_a_pilot）、注文は CraftUI._do_craft と同じ Main.request_order、
## 引受け・搬入・加工は実AIの通常 tick（await process_frame、Engine.time_scale で早送り）。
## fixture: 作業台がなければ base.add_facility で足す／倉庫の木材が足りなければ store_owned で足す（実行時に表示）。
## incoming への直接の追加は「除外の検査」（自動補充・建設・別品目を数えないこと）にだけ使い、成功の根拠にしない。
## 実OS入力・GUI描画・Windows は対象外。

const ID := "tool_wood_pick"
const OTHER := "tool_wood_axe"
const WALL_LIMIT_MS := 150000

var main
var failures := 0
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _fresh() -> void:
	if main != null:
		main.queue_free()
		await process_frame
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	await process_frame
	var item_wood: int = GameData.Item.WOOD
	if not main.has_facility("workbench"):
		main.base.add_facility("workbench", true)
		print("  fixture: workbench added by base.add_facility")
	var need: int = 4 - int(main.storage.count_of(item_wood))
	if need > 0:
		main.storage.store_owned(item_wood, need)
		print("  fixture: wood +%d into storage" % need)
	Engine.time_scale = 6.0


func _hauler():
	for w in main.workers:
		var st: int = w.ai.state
		if st in [CharacterAI.State.HAUL_TAKE, CharacterAI.State.HAUL_MOVE] and w.ai.haul_recipe.get("player_order", false) and w.ai.haul_recipe.get("id", "") == ID:
			return w
	return null


func _total(s: Dictionary) -> int:
	return int(s.queued) + int(s.get("incoming", 0)) + int(s.loaded) + int(s.active)


func _wait_hauler():
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WALL_LIMIT_MS:
		var w = _hauler()
		if w != null: return w
		await process_frame
	return null


func _status_label_text() -> String:
	var ui = main.craft_ui
	ui.open_entry(ID)
	ui._refresh(true)
	var label = ui.find_child("BatchStatus", true, false)
	var text: String = label.text if label != null else ""
	ui.close()
	return text


func _scenario_haul() -> void:
	print("-- 通常注文 → 実AI引受け → 搬入 → 加工")
	await _fresh()
	var got: int = main.request_order(ID, 1)
	_check(got == 1, "request_order が1回を受付")
	var in_orders := false
	for q in main.production_orders:
		if q.id == ID and int(q.n) == 1: in_orders = true
	_check(in_orders and main.craft_queue.is_empty(), "注文は production_orders（倉庫材料の通常注文）に入る")
	_check(_total(main.processor.manual_status(ID)) == 1, "引受け前: 内訳の合計は1（未投入1）")

	var w = await _wait_hauler()
	_check(w != null, "実AIが注文を HAUL_TAKE / HAUL_MOVE で引受けた（必須到達）")
	if w == null: return
	var p = main.processor
	var owned := 0
	for r in p.incoming:
		if r.get("manual", false) and r.get("id", "") == ID: owned += 1
	_check(owned == 1, "引受けた注文が processor.incoming に1件ある（AIの reserve による。テストは追加していない）")
	_check(main.production_orders.is_empty(), "production_orders からは外れている（claim_order）")

	# 読み取りだけで何も変えないこと（世界を止めて比較）
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var stock_before: Dictionary = main.storage.inventory.counts.duplicate(true)
	var ws_before: Dictionary = p.stock.counts.duplicate(true)
	var incoming_before: int = p.incoming.size()
	var orders_before: int = p.orders.size()
	var save_before: String = var_to_str(SaveGame.capture(main))
	var s: Dictionary = p.manual_status(ID)
	var text := _status_label_text()
	var s_other: Dictionary = p.manual_status(OTHER)
	_check(main.storage.inventory.counts == stock_before and p.stock.counts == ws_before, "読み取りで倉庫・作業場の在庫は不変")
	_check(p.incoming.size() == incoming_before and p.orders.size() == orders_before and main.production_orders.is_empty() and main.craft_queue.is_empty(), "読み取りで予約・注文は不変")
	_check(var_to_str(SaveGame.capture(main)) == save_before, "読み取りでセーブ内容（capture）は不変")
	main.process_mode = Node.PROCESS_MODE_INHERIT

	_check(int(s.get("incoming", -1)) == 1, "搬入中の1回が manual_status の別枠に出る（実測 %s）" % str(s.get("incoming", "キーなし")))
	_check(int(s.queued) == 0 and int(s.loaded) == 0 and int(s.active) == 0, "搬入中は 未投入0・投入済0・加工中0（二重に数えない）")
	_check(_total(s) == 1, "搬入中: 内訳の合計は1（実測 %d）" % _total(s))
	_check(text.contains("搬入中 1回"), "製作画面の内訳に「搬入中 1回」が出る（実測: %s）" % text.split("\n")[1 if text.split("\n").size() > 1 else 0])
	_check(_total(s_other) == 0 and int(s_other.get("incoming", 0)) == 0, "別品目（%s）には数えない" % OTHER)

	# 除外の検査（ここだけ incoming へ直接足す。成功の根拠には使わない）
	var auto_r: Dictionary = GameData.recipe_by_id("firewood").duplicate(true)
	auto_r["automatic"] = true
	var build_r := {"id": ID, "build": "bed", "in": {}, "out": -1}
	p.incoming.append(auto_r)
	p.incoming.append(build_r)
	_check(int(p.manual_status("firewood").get("incoming", 0)) == 0, "除外: 自動補充の搬入は数えない")
	_check(int(p.manual_status(ID).get("incoming", 0)) == 1, "除外: 建設の搬入は数えない（対象は1のまま）")
	p.incoming.erase(auto_r)
	p.incoming.erase(build_r)

	# 到着まで毎フレーム: 合計は常に1（消えない・二重にならない）
	var t0 := Time.get_ticks_msec()
	var worst_low := 1
	var worst_high := 1
	var arrived := false
	var saw_move := false
	while Time.get_ticks_msec() - t0 < WALL_LIMIT_MS:
		var now: Dictionary = p.manual_status(ID)
		if int(now.output) > 0 or main.storage.count_of(GameData.Item.WOOD_PICK) > 0: break
		var hw = _hauler()
		if hw != null and hw.ai.state == CharacterAI.State.HAUL_MOVE: saw_move = true
		worst_low = mini(worst_low, _total(now))
		worst_high = maxi(worst_high, _total(now))
		if hw == null and not arrived:
			arrived = true
			_check(int(now.get("incoming", 0)) == 0 and int(now.loaded) + int(now.active) == 1 and int(now.queued) == 0, "到着後: 搬入中0、投入済または加工中が1（実測 %s）" % str(now))
		await process_frame
	_check(saw_move, "HAUL_MOVE（運搬中）を通過した（必須到達）")
	_check(arrived, "搬入が完了した（必須到達）")
	_check(worst_low == 1 and worst_high == 1, "引受けから完成まで、内訳の合計は常に1（最小 %d・最大 %d）" % [worst_low, worst_high])
	var done: Dictionary = p.manual_status(ID)
	_check(int(done.get("incoming", 0)) == 0 and int(done.queued) == 0 and int(done.loaded) == 0, "完成後: 搬入中・未投入・投入済は0")


func _scenario_cancel() -> void:
	print("-- 引受け直後（HAUL_TAKE）の取消は従来どおり")
	await _fresh()
	var wood_before: int = main.storage.count_of(GameData.Item.WOOD)
	main.request_order(ID, 1)
	var w = await _wait_hauler()
	_check(w != null and w.ai.state == CharacterAI.State.HAUL_TAKE, "HAUL_TAKE の間に捕捉（必須到達）")
	if w == null or w.ai.state != CharacterAI.State.HAUL_TAKE: return
	var cancelled: int = main.cancel_manual_craft(ID)
	var s: Dictionary = main.processor.manual_status(ID)
	_check(cancelled == 1, "取消数は1（従来と同じ）")
	_check(_total(s) == 0 and int(s.get("incoming", 0)) == 0, "取消後: 内訳はすべて0")
	_check(main.production_orders.is_empty() and main.processor.incoming.filter(func(r): return r.get("id", "") == ID).is_empty(), "取消後: 注文・予約は残らない")
	_check(main.storage.count_of(GameData.Item.WOOD) == wood_before, "取消後: 倉庫の木材は注文前と同じ")


func _run() -> void:
	if OS.get_environment("FLUID_TEST_HOME") == "":
		print("FLUID_TEST_HOME が未設定（隔離なしでは実行しない）")
		quit(2)
		return
	await _scenario_haul()
	await _scenario_cancel()
	Engine.time_scale = 1.0
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
