extends "res://tools/test_quarry.gd"
const ITEM = GameData.Item.SIMPLE_SPEAR
func _initialize():
	await fresh()
	main.target_speed = 0
	main.base.add_facility("workbench", true)
	main.storage.inventory.counts.clear()
	for k in main.recipe_priority: main.recipe_priority[k] = 0
	for w in main.workers:
		w.priorities[GameData.Job.PROCESS] = 5
		w.priorities[GameData.Job.HAUL] = 5
	main.processor.stock.add(GameData.Item.WOOD, 1)
	main.processor.stock.add(GameData.Item.IRON, 1)
	check(main.request_craft("simple_spear", 1) == 1, "既存の製作注文で簡易槍を依頼")
	check(await until(func(): return main.storage.count_of(ITEM) == 1, 150), "実AIで材料を加工し倉庫へ収納")
	for w in main.workers:
		w.stop_work()
		for j in GameData.job_list(): w.priorities[j] = 0
	var a = main.workers[0]
	var b = main.workers[1]
	var weight: int = main.storage.current_weight()
	check(main.equip_weapon(a), "個人へ装備")
	check(a.weapon == ITEM and main.storage.count_of(ITEM) == 0 and main.storage.current_weight() == weight, "倉庫と個人の単一所有・重量不変")
	check(not main.equip_weapon(a) and not main.equip_weapon(b), "連打・在庫0から他人へ装備は複製しない")
	check(not main.storage.take_item(ITEM) and GameData.RECIPES.all(func(r): return not r["in"].has(ITEM)), "装備中は倉庫消費や製作材料にならない")
	main.storage.inventory.counts[GameData.Item.FOOD] = main.storage.max_weight() - main.storage.equipped_weapon_weight()
	weight = main.storage.current_weight()
	check(weight == main.storage.max_weight() and main.unequip_weapon(a), "満載でも計上済み重量のまま倉庫へ外せる")
	check(main.storage.current_weight() == weight and main.storage.count_of(ITEM) == 1 and not main.unequip_weapon(a), "解除連打で重複せず重量・在庫保持")
	check(main.equip_weapon(b) and b.weapon == ITEM and a.weapon == -1, "別個体へ持替え")
	b.set_priority(GameData.Job.COMBAT, 5)
	b.stop_work()
	check(b.weapon == ITEM and main.storage.current_weight() == weight, "仕事切替・中断でも装備と重量保持")
	b.away = true
	check(not main.unequip_weapon(b), "遠征中の変更を拒否")
	b.away = false
	CrewStatus.damage(b, 1000)
	check(b.down and b.weapon == ITEM and not main.unequip_weapon(b), "HP0は死亡でなく戦闘不能。装備を失わず変更を拒否")
	check(main.storage.current_weight() == weight, "戦闘不能でも装備重量は消えない")
	CrewStatus._tick_hp(b, 1000)
	check(not b.down and b.weapon == ITEM, "復帰して同じ武器を保持")
	# 既存迎撃AIで同一個体・同一能力・同一敵への1秒の攻撃を比較。
	var e := Enemy.new()
	e.setup(main, 1000)
	e.position = Vector2(700, GameData.GROUND_Y_MIN)
	e.hold_x = 700
	main.enemies_root.add_child(e)
	b.hp = 100
	b.hunger = 100
	b.fatigue = 0
	b.floor_i = 0
	b.position = Vector2(670, GameData.GROUND_Y_MIN)
	b.ai._set_state(CharacterAI.State.SEARCH)
	b.ai.tick(0.0)
	check(b.ai.state == CharacterAI.State.COMBAT_MOVE and b.ai.enemy == e, "既存の襲撃優先判断で敵を選択")
	b.ai.tick(0.0)
	var before: float = e.hp
	b.ai.tick(1.0)
	var armed: float = before - e.hp
	check(main.unequip_weapon(b), "戦闘中も1枠を倉庫へ戻せる")
	b.fatigue = 0
	before = e.hp
	b.ai.tick(1.0)
	var bare: float = before - e.hp
	check(bare > 0 and is_equal_approx(armed, bare * GameData.SIMPLE_WEAPON_MULT), "本人の実攻撃だけが調整値1.2倍。他の戦闘数値は不変")
	check(a.weapon_mult() == 1.0, "未装備の他人へ補正を広げない")
	# 満載出力保全。0容量を意図的に注入し、完成品を捨てない。
	main.storage.inventory.counts.clear()
	main.storage.capacity_bonus = -CargoDB.CAPACITY
	var waste: int = main.total_wasted
	check(main.storage.add_item(ITEM) == 0 and main.processor.output.count(ITEM) == 1, "満載の武器完成品を作業場へ保全")
	check(main.processor.packed_output_blocked() and main.total_wasted == waste, "収納まで加工担当を拘束せず廃棄しない")
	main.storage.capacity_bonus = 0
	check(not main.processor.packed_output_blocked(), "空きが戻れば武器を運べる")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
