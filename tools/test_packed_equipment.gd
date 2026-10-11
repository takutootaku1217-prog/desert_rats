extends "res://tools/test_quarry.gd"
## 製品のAIと製作/設置APIを使う。満載・損傷だけを境界条件として注入する。
func setup() -> void:
	await fresh()
	main.target_speed = 0
	main.storage.inventory.counts.clear()
	for k in main.recipe_priority: main.recipe_priority[k] = 0
	main.base.add_facility("workbench", true)
	for w in main.workers:
		w.priorities[GameData.Job.HAUL] = 5
		w.priorities[GameData.Job.PROCESS] = 5

func _initialize() -> void:
	await packages()
	await cancellation()
	await full_and_departure()
	await manual_return()
	await emergency()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)

func packages() -> void:
	print("-- 製作物→設置。素材の二重消費と容量の二重加算を防ぐ")
	await setup()
	for id in ["bed", "cargo_rack"]:
		var d: Dictionary = FacilityDB.def(id)
		for it in d["cost"]: main.processor.stock.add(it, d["cost"][it])
		check(main.request_craft(d["pack_recipe"], 1) == 1, "手動製作を受理: " + id)
		check(await until(func(): return main.storage.count_of(d["packed_item"]) == 1, 150), "実AIで製作物を収納: " + id)
		check(main.base.facility_count(id) == 0, "製作だけでは設置されない: " + id)
		check(ItemDB.uses_of(d["packed_item"]).any(func(e): return e["kind"] == "build" and e["id"] == id), "インベントリの用途から設置へ移れる: " + id)
		var ev := CraftDB.evaluate(CraftDB.entry_of("build:" + id), main)
		check(ev["state"] == "ok" and ev["rows"].size() == 1 and ev["rows"][0]["item"] == d["packed_item"], "設置画面も製作物1個だけを要求: " + id)
		var before: int = main.storage.max_weight()
		check(main.request_build(id), "製作物の設置を依頼: " + id)
		check(await until(func(): return main.base.facility_count(id) == 1, 150), "追加素材なしで1個設置: " + id)
		check(main.storage.count_of(d["packed_item"]) == 0 and main.processor.stock.counts.values().all(func(n): return n == 0), "製作物1個を消費、材料を二重消費しない: " + id)
		check(main.storage.max_weight() == before + int(d.get("capacity_bonus", 0)), "設置分だけ容量増加: " + id)
		main.room_layout = Rooms.with_room(main.room_layout, "l3" if id == "cargo_rack" else "u3", d["room"])
		main.base.apply_layout()
		check(main.base.facility_count(id) == 1 and main.storage.max_weight() == before + int(d.get("capacity_bonus", 0)), "部屋移設で設備・容量を維持: " + id)
	# Bからの一括依頼も、同じ製作物を経て設置する。
	for it in FacilityDB.def("bed")["cost"]: main.storage.add_item(it, FacilityDB.def("bed")["cost"][it])
	check(main.request_build("bed"), "素材から製作して設置を依頼")
	check(await until(func(): return main.base.facility_count("bed") == 2, 180), "素材→寝床→設置が実AIで完了")
	main.base.add_facility("bed", true)
	main.storage.add_item(GameData.Item.BED_PACK)
	check(not main.request_build("bed") and main.storage.count_of(GameData.Item.BED_PACK) == 1, "設置枠3つが満杯なら物を消費しない")

func cancellation() -> void:
	print("-- 設置の取消と製作物保全")
	await setup()
	main.storage.add_item(GameData.Item.BED_PACK)
	check(main.request_build("bed") and main.cancel_build("bed"), "引受前の設置取消")
	check(main.storage.count_of(GameData.Item.BED_PACK) == 1 and main.build_pending("bed") == 0, "取消は製作物を消費しない")
	main.storage.inventory.counts.clear()
	for it in FacilityDB.def("bed")["cost"]: main.storage.add_item(it, FacilityDB.def("bed")["cost"][it])
	main.request_build("bed")
	check(await until(func(): return main.processor.current.get("id", "") == "bed_pack", 90), "製作中に到達")
	check(main.cancel_build("bed"), "製作中に設置だけを取消")
	check(await until(func(): return main.storage.count_of(GameData.Item.BED_PACK) == 1, 90), "製作中の品は捨てず完成して残す")
	check(main.base.facility_count("bed") == 0, "取消後は勝手に設置しない")

func full_and_departure() -> void:
	print("-- 満載、部屋変更、製作途中の出発")
	await setup()
	main.processor.stock.add(GameData.Item.STORAGE_BOX)
	check(main.request_transfer(GameData.Item.STORAGE_BOX, 1, "to_storage") == 1, "収納ボックスの手動運搬を依頼")
	var moved: int = main.begin_transfer_trip(GameData.Item.STORAGE_BOX, "to_storage")
	main.storage.capacity_bonus = -CargoDB.CAPACITY
	main.finish_transfer_trip(GameData.Item.STORAGE_BOX, "to_storage", moved)
	check(main.storage.count_of(GameData.Item.STORAGE_BOX) == 1 and main.processor.stock.count(GameData.Item.STORAGE_BOX) == 0 and main.processor.output.count(GameData.Item.STORAGE_BOX) == 0,
		"運搬中の容量減少でも既存所有の1個を倉庫へ返却し、出力へ複製しない")
	main.processor.stock.counts.clear()
	main.processor.output.clear()
	main.processor._out_times.clear()
	main.storage.inventory.counts.clear()
	park_fixture()
	var wasted: int = main.total_wasted
	check(main.storage.add_item(GameData.Item.STORAGE_BOX) == 0, "満載の新規取得は成功扱いしない")
	check(main.quarry.loose.get(GameData.Item.STORAGE_BOX,0) == 1 and main.total_wasted == wasted, "外部取得の箱は残置として保持")
	for i in 50: await step()
	check(main.quarry.loose.get(GameData.Item.STORAGE_BOX,0) == 1 and main.processor.worker == null, "外部残置で加工担当を拘束しない")
	main.storage.capacity_bonus = 0
	check(await until(func(): return main.storage.count_of(GameData.Item.STORAGE_BOX) == 1, 120), "空きができると1個だけ回収")
	main.request_build("cargo_rack")
	check(await until(func(): return main.base.facility_count("cargo_rack") == 1, 120), "退避した箱も設置できる")
	park_fixture()
	for it in FacilityDB.def("bed")["cost"]: main.storage.add_item(it, FacilityDB.def("bed")["cost"][it])
	main.request_build("bed")
	check(await until(func(): return main.processor.current.get("id", "") == "bed_pack", 120), "停泊中に寝床製作を開始")
	main.quarry.request_departure()
	check(await until(func(): return main.quarry.ready_to_leave(), 150), "製作途中でも材料を保って帰還完了")
	check(main.quarry.leave(), "製作途中の出発")
	check(await until(func(): return main.base.facility_count("bed") == 1, 180), "出発後に製作・設置を再開し完了")
	check(main.storage.count_of(GameData.Item.BED_PACK) == 0 and main.build_pending("bed") == 0, "出発による複製・依頼残留なし")

func emergency() -> void:
	print("-- 応急修理板。予約、上限、燃料・仲間HPの不変")
	await setup()
	main.storage.add_item(GameData.Item.REPAIR_KIT, 3)
	for p in main.base.parts: main.base.parts[p] = 100.0
	check(not main.emergency_repair() and main.storage.count_of(GameData.Item.REPAIR_KIT) == 3, "全耐久最大では消費しない")
	var w = main.workers[0]
	var hp: float = w.hp
	var fuel: float = main.base.fuel
	main.base.parts[GameData.Part.HULL] = 10.0
	main.base.parts[GameData.Part.DRIVE] = 90.0
	main.base.repair_reserved[GameData.Part.HULL] = w
	check(main.emergency_repair_target() == GameData.Part.DRIVE and main.emergency_repair(), "AIが修理中の部位を避けて最小耐久へ使用")
	check(main.base.parts[GameData.Part.DRIVE] == 100 and main.base.parts[GameData.Part.HULL] == 10, "25回復を上限100で止め、予約部位は変更しない")
	check(main.base.repair_reserved.get(GameData.Part.HULL) == w and not main.emergency_repair(), "予約は保持し、他に損傷がなければ重複消費しない")
	main.base.repair_reserved.clear()
	check(main.emergency_repair() and main.base.parts[GameData.Part.HULL] == 35, "未予約の最小耐久を25回復")
	check(w.hp == hp and main.base.fuel == fuel and main.storage.count_of(GameData.Item.REPAIR_KIT) == 1, "燃料・仲間HPを変更せず成功回数分だけ消費")
	# 実AIが1個を持って修理へ向かう最中に、手動で別部位を修理する。
	await setup()
	main.storage.add_item(GameData.Item.REPAIR_KIT, 2)
	main.base.parts[GameData.Part.HULL] = 20.0
	main.base.parts[GameData.Part.DRIVE] = 50.0
	w = main.workers[0]
	w.priorities[GameData.Job.REPAIR] = 5
	check(await until(func(): return w.ai.state == CharacterAI.State.REPAIR_MOVE, 90), "実AIが板1個を携行して修理へ向かう")
	check(main.storage.count_of(GameData.Item.REPAIR_KIT) == 1 and main.emergency_repair(), "AI携行分とは別の在庫1個で即時修理")
	check(await until(func(): return main.base.total_repair == 2, 90), "AIも予約を失わず修理を完了")
	check(main.storage.count_of(GameData.Item.REPAIR_KIT) == 0 and w.carrying < 0 and main.base.repair_reserved.is_empty(), "修理2回に2個だけ消費、予約と携行物を解除")


func manual_return() -> void:
	await setup()
	park_fixture()
	main.processor.stock.add(GameData.Item.STONE)
	main.request_transfer(GameData.Item.STONE, 1, "to_storage")
	var n: int = main.begin_transfer_trip(GameData.Item.STONE, "to_storage")
	main.storage.capacity_bonus = -CargoDB.CAPACITY
	main.finish_transfer_trip(GameData.Item.STONE, "to_storage", n)
	check(main.storage.count_of(GameData.Item.STONE) == 1 and main.processor.stock.count(GameData.Item.STONE) == 0 and main.quarry.loose.is_empty() and main.total_wasted == 0,
		"停泊中の原材料も保有済みなので倉庫へ1回だけ返却（残置へ複製しない）")
