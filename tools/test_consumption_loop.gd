extends SceneTree
## 診断専用: 世界の時間と他の仲間を止め、初期加工品ゼロから既存AIの経路を順に通す。
## レシピ・道具性能・容量・製品初期値は変更しない。自然な時間進行は test_loop の vanilla で別に確認。
var fails := 0
var main
var w
var st: BaseStorage

func check(ok: bool, msg: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", msg])
	if not ok:
		fails += 1

func drive(done: Callable) -> bool:
	for i in 6000:
		if done.call():
			return true
		w.ai.tick(0.1)
	return done.call()

func job(kind: int) -> bool:
	if not w.ai._try_start(kind):
		return false
	return drive(func(): return w.ai.state == CharacterAI.State.SEARCH)

func gather(kind: String) -> void:
	var p := GatherPoint.new()
	p.setup(main, kind)
	p.position = Vector2(650, 610)
	main.resources_root.add_child(p)
	var before := st.count_of(p.item)
	check(job(GameData.Job.GATHER) and st.count_of(p.item) > before, "%sを採取→運搬→収納" % kind)
	p.free()

func craft(id: String) -> void:
	for r in GameData.RECIPES:
		main.recipe_priority[r["id"]] = 5 if r["id"] == id else 0
	var rec := GameData.recipe_by_id(id)
	var before := st.inventory.counts.duplicate()
	var count_before: int = main.processor.total_done
	check(main.choose_recipe().get("id", "") == id, "%sが既存の自動加工候補になる" % id)
	check(job(GameData.Job.HAUL), "%sの材料を加工設備へ運ぶ" % id)
	for it in rec["in"]:
		check(st.count_of(it) == int(before.get(it, 0)) - int(rec["in"][it]), "%sの材料%sを一度だけ消費" % [id, GameData.ITEM_NAMES[it]])
	for i in int(rec["n"]):
		check(job(GameData.Job.PROCESS), "%sの加工／出力運搬を完了" % id)
	check(st.count_of(rec["out"]) == int(before.get(rec["out"], 0)) + int(rec["n"]), "%sの出力が指定数だけ倉庫に届く" % id)
	check(main.processor.total_done == count_before + 1 and main.processor.incoming.is_empty()
		and main.processor.orders.is_empty() and main.processor.output.is_empty(), "%sの加工1回、予約・出力の取り残しなし" % id)

func _initialize() -> void:
	FacilityDB.start_all = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	await process_frame
	seed(20261011)
	main.director.enabled = false
	main.scroll_speed = 0.0
	main.target_speed = 0.0
	st = main.storage
	st.inventory.counts.clear()
	for worker in main.workers:
		worker.stop_work()
		for j in GameData.job_list():
			worker.priorities[j] = 0
	w = main.workers[0]
	w.floor_i = 1
	w.position = Vector2(600, GameData.LO_Y)
	w.slot_offset = Vector2.ZERO
	w.hunger = 100.0
	w.fatigue = 0.0
	w.tools = {"mine": GameData.Item.HAMMER, "chop": GameData.Item.AXE}
	check(st.inventory.counts.is_empty(), "初期食料・燃料・修理資材を含め在庫ゼロ（診断専用条件）")
	gather("tree")
	gather("rock")
	var carcass := ResourceNode.new()
	carcass.game = main
	carcass.item = GameData.Item.CARCASS
	carcass.species = "hare"
	carcass.position = Vector2(650, 610)
	main.resources_root.add_child(carcass)
	check(job(GameData.Job.GATHER) and st.count_of(GameData.Item.MEAT) > 0, "獲物の回収→運搬→解体で生肉が入る（獲物は診断配置）")
	craft("cook")
	var food_before := st.count_of(GameData.Item.FOOD)
	w.hunger = CrewStatusDB.EAT_BELOW - 1.0
	var hunger_before: float = w.hunger
	var eaten_before: int = main.total_eaten
	check(drive(func(): return main.total_eaten > eaten_before), "調理した食料で自動食事を完了")
	check(st.count_of(GameData.Item.FOOD) == food_before - 1 and w.carrying < 0, "食料1個を取り出して消費、持ち物に残らない")
	var effect: float = CrewStatusDB.FOOD_EFFECTS[GameData.Item.FOOD]["hunger"]
	check(is_equal_approx(w.hunger, hunger_before + effect), "満腹度が既定効果ぶん回復: %.1f→%.1f" % [hunger_before, w.hunger])
	craft("firewood")
	main.base.fuel = 0.0
	# 製品の燃料ゼロ経路を実際に1フレーム通す（資源出現まで進めない）。
	main.target_speed = 60.0
	var distance_before: float = main.director.distance
	main._process(0.1)
	check(main.scroll_speed > 0.0 and main.scroll_speed <= 15.0 and main.director.distance > distance_before,
		"燃料ゼロでも速度上限15で走行する")
	main.target_speed = 0.0
	main.scroll_speed = 0.0
	var fuel_before := st.count_of(GameData.Item.FUEL)
	check(job(GameData.Job.HAUL), "加工した燃料を機関室へ運び補給")
	check(st.count_of(GameData.Item.FUEL) == fuel_before - 1 and w.carrying < 0
		and is_equal_approx(main.base.fuel, GameData.FUEL_ITEMS[GameData.Item.FUEL]), "燃料1個の実消費とタンクの既定量回復")
	craft("repair_stone")
	main.base.parts[GameData.Part.HULL] = GameData.REPAIR_BELOW - 1.0
	var hp_before: float = main.base.condition(GameData.Part.HULL)
	var kits_before := st.count_of(GameData.Item.REPAIR_KIT)
	check(job(GameData.Job.REPAIR), "加工した修理資材を運び拠点を修理")
	check(st.count_of(GameData.Item.REPAIR_KIT) == kits_before - 1 and w.carrying < 0
		and is_equal_approx(main.base.condition(GameData.Part.HULL), minf(100.0, hp_before + GameData.REPAIR_AMOUNT)),
		"修理資材1個の実消費と拠点耐久の既定量回復")
	check(main.total_wasted == 0, "この通し経路で物資の廃棄なし")
	print("== 結果: %d 件失敗 ==" % fails)
	quit(1 if fails else 0)
