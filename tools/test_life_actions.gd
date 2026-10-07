extends SceneTree
## 自動生活行動と一度だけの「休憩／食事を促す」の自己診断。
## 実行: Godot --headless --path . -s res://tools/test_life_actions.gd
## AI の実際の採取・加工・運搬・予約経路を使う。背景の時間進行は止め、対象の仲間だけを進める。

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
	await _test_automatic_thresholds()
	await _test_early_requests()
	await _test_beds()
	await _test_food_contention()
	await _test_safe_interruption()
	await _test_gather_delivery()
	await _test_deleted_gather_target()
	await _test_urgent_food_before_rest()
	await _test_transfer_delivery()
	await _test_processor_pause()
	await _test_priority_changes()
	await _test_rejection_and_cleanup()
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
	main.director.active.clear()
	main.target_speed = 0.0
	main.scroll_speed = 0.0
	main.storage.inventory.counts.clear()
	main.processor.stock.counts.clear()
	W = main.workers
	for w in W:
		_reset(w)
	_give_beds(3)


func _reset(w) -> void:
	w.stop_work()
	w.set_process(false)
	for job in GameData.job_list():
		w.priorities[job] = 0
	w.hp = 100.0
	w.hunger = 100.0
	w.fatigue = 0.0
	w.stress = 0.0
	w.calm = 0.0
	w.mental = CrewStatusDB.Mental.NORMAL
	w.down = false
	w.away = false
	w.sleeping = false
	w.resting = false
	w.floor_i = 1
	w.position = Vector2(600.0, GameData.LO_Y)
	w.target = w.position
	w.slot_offset = Vector2.ZERO
	w._climb_dest = null
	w.ai.eat_wait = 0.0
	w.ai.timer = 0.0
	w.ai._set_state(CharacterAI.State.SEARCH)


func _give_beds(n: int) -> void:
	main.base.built["bed"] = range(n)
	for i in main.base.beds.size():
		main.base.beds[i] = null


func _set_food(n: int) -> void:
	main.storage.inventory.counts.erase(GameData.Item.FOOD)
	if n > 0:
		main.storage.inventory.counts[GameData.Item.FOOD] = n


func _is_rest(w) -> bool:
	return w.ai.state in [CharacterAI.State.REST_MOVE, CharacterAI.State.REST, CharacterAI.State.REST_HERE]


func _run_until(w, cond: Callable, secs := 60.0, dt := 0.1) -> bool:
	var elapsed := 0.0
	while elapsed < secs:
		if cond.call():
			return true
		w._process(dt)
		elapsed += dt
	return cond.call()


func _wood_resource() -> ResourceNode:
	var r := ResourceNode.new()
	r.game = main
	r.item = GameData.Item.WOOD
	r.position = Vector2(900.0, GameData.GROUND_Y_MIN)
	main.resources_root.add_child(r)
	r.set_process(false)
	return r


func _test_automatic_thresholds() -> void:
	print("-- 自動休憩: 仕事の有無、境界値、REST★0")
	await _fresh()
	var w = W[0]
	var r := _wood_resource()
	w.priorities[GameData.Job.GATHER] = 1
	w.fatigue = 74.99
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.NOTICE and r.claimed_by == w, "疲労74.99・仕事あり・REST★0なら、通常の仕事を選ぶ")
	_reset(w)
	w.priorities[GameData.Job.GATHER] = 1
	w.fatigue = 75.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE and w.priorities[GameData.Job.REST] == 0, "疲労75からは、REST★0でも仕事より先に休憩する")
	_reset(w)
	w.priorities[GameData.Job.GATHER] = 1
	w.hp = 25.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.NOTICE, "HP25・仕事ありでは、HPによる急ぎの休憩を始めない")
	_reset(w)
	w.priorities[GameData.Job.GATHER] = 1
	w.hp = 24.99
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE, "HP25未満なら、REST★0でも自動休憩する")
	_reset(w)
	w.fatigue = 50.0
	w.ai.tick(0.1)
	check(not _is_rest(w), "仕事がなくても、疲労50では休憩を始めない")
	_reset(w)
	w.fatigue = 50.01
	w.ai.tick(0.1)
	check(_is_rest(w), "仕事がなければ、疲労50超でREST★0でも休憩する")
	_reset(w)
	w.hp = 49.99
	w.ai.tick(0.1)
	check(_is_rest(w), "仕事がなければ、HP50未満でも休憩する")
	_reset(w)
	w.ai.tick(0.1)
	check(not _is_rest(w) and main.base.bed_index_of(w) < 0, "健康な仲間は、仕事がなくても不要な休憩・ベッド予約を繰り返さない")


func _test_early_requests() -> void:
	print("-- 早めの促し: 受理は1件の保留だけ、実行時に既存の生活経路へ")
	await _fresh()
	var w = W[0]
	w.fatigue = 30.0
	check(not CrewStatus.can_rest(w) and w.ai.life_action_reason("rest").is_empty(), "疲労30は自動休憩の開始条件未満だが、手動の休憩を促せる")
	check(w.ai.request_life_action("rest"), "早めの休憩の促しを受理する")
	check(w.ai.life_request == "rest" and w.ai.state == CharacterAI.State.SEARCH and main.base.bed_index_of(w) < 0, "受理直後は保留だけで、状態やベッド予約を変えない")
	for i in 5:
		check(not w.ai.request_life_action("rest"), "同じ休憩の促しは重複受理しない（%d回目）" % (i + 1))
	check(w.ai.life_request == "rest" and main.base.beds == [null, null, null], "連打しても保留は1件、ベッドの先取りもない")
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE and main.base.bed_index_of(w) >= 0 and w.ai.life_request.is_empty(), "安全な区切りで、疲労30でもベッドへ向かい保留を消費する")
	check(_run_until(w, func(): return w.ai.state == CharacterAI.State.REST), "早めの休憩でも実際にベッドへ到着する")
	check(_run_until(w, func(): return w.ai.state == CharacterAI.State.SEARCH, 40.0) and CrewStatus.rest_done(w), "早めの休憩も疲労20以下・HP80以上まで続き、終了する")
	_reset(w)
	_set_food(1)
	w.hunger = 70.0
	check(not CrewStatus.wants_to_eat(w) and w.ai.request_life_action("eat"), "自動食事の条件未満でも、満腹度70なら食事を促せる")
	check(main.food_claims == 0 and w.ai.life_request == "eat", "促しの受理だけでは食料を予約しない")
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.EAT_TAKE and main.food_claims == 1 and w.ai.life_request.is_empty(), "実行開始時に食料を1つ予約し、既存の食事経路へ進む")
	check(_run_until(w, func(): return main.total_eaten == 1) and w.hunger > 70.0, "早めの食事も、倉庫から食料を取り実際に満腹度を回復する")
	check(main.food_claims == 0 and main.storage.count_of(GameData.Item.FOOD) == 0 and w.carrying < 0, "食べ終わると食料1個だけを消費し、手持ち・予約を解放する")


func _test_beds() -> void:
	print("-- ベッドなし／満床と、空いたベッドへの移動")
	await _fresh()
	var w = W[0]
	_give_beds(0)
	w.fatigue = 80.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_HERE and w.bed_index == -1, "ベッドなし・REST★0でも、必要な休憩はその場で始める")
	var before: float = w.fatigue
	w._process(1.0)
	check(w.resting and w.fatigue < before, "その場の休憩でも、実際に疲労が回復する")
	_reset(w)
	w.fatigue = 30.0
	check(w.ai.request_life_action("rest"), "ベッドがなくても、早めの休憩の促しを受理する")
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_HERE, "早めの促しも、ベッドなしならその場で休む")
	_give_beds(1)
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE and main.base.beds[0] == w, "疲労30・REST★0の休憩中でも、空いたベッドへ移る")
	_reset(w)
	_give_beds(1)
	main.base.beds[0] = W[1]
	w.fatigue = 80.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_HERE and main.base.beds[0] == W[1], "満床なら他の仲間の予約を奪わず、その場で休む")
	main.base.release_bed(W[1])
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE and main.base.beds[0] == w, "満床が解消されたら、空いたベッドへ移る")


func _test_food_contention() -> void:
	print("-- 食料1個への複数要求と、開始前／到着時の在庫変化")
	await _fresh()
	var w = W[0]
	var other = W[1]
	_set_food(1)
	w.hunger = 70.0
	other.hunger = 70.0
	check(w.ai.request_life_action("eat") and other.ai.request_life_action("eat"), "予約開始前なら、2人それぞれに食事を促せる")
	check(main.food_claims == 0, "2人に促しても、受理だけでは食料を先取りしない")
	w.ai.tick(0.1)
	other.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.EAT_TAKE and other.ai.state != CharacterAI.State.EAT_TAKE and main.food_claims == 1, "開始時に在庫を再確認し、食料1個へ向かうのは1人だけ")
	check(other.ai.life_request.is_empty() and other.ai.eat_wait <= 0.0, "開始前に不足した要求は保留を解消し、到着失敗用の待ち時間は増やさない")
	check(not other.ai.request_life_action("eat") and not other.ai.life_action_reason("eat").is_empty(), "他の仲間が予約した最後の食料には、促しを再受理しない")
	check(_run_until(w, func(): return main.total_eaten == 1), "予約した1人は食事を完了する")
	check(main.food_claims == 0 and main.total_eaten == 1, "複数要求でも消費と予約解放は1個ぶんだけ")
	_reset(w)
	_set_food(1)
	w.hunger = 70.0
	check(w.ai.request_life_action("eat"), "（準備）到着時に食料が消える食事を促す")
	w.ai.tick(0.1)
	_set_food(0)
	check(_run_until(w, func(): return w.ai.state == CharacterAI.State.SEARCH), "到着時に食料がなくても、通常行動へ戻る")
	check(main.food_claims == 0 and not w.ai._eat_claimed and w.ai.eat_wait > 0.0 and w.carrying < 0, "到着失敗時は食料予約を解放し、既存の再試行待ちだけを残す")


func _test_safe_interruption() -> void:
	print("-- 手ぶらの危険中断: 採取予約と加工材料の取り置きを解放する")
	await _fresh()
	var w = W[0]
	var resource := _wood_resource()
	w.priorities[GameData.Job.GATHER] = 1
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.NOTICE and resource.claimed_by == w, "（準備）資源への移動前に採取を予約する")
	w.fatigue = 90.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.SEARCH and resource.claimed_by == null and w.ai.res == null and w.carrying < 0, "手ぶらで危険な疲労になったら、採取予約を返して仕事を中断する")
	w.ai.tick(0.1)
	check(_is_rest(w), "採取予約を返した後、REST★0でも自動休憩する")
	_reset(w)
	main.storage.inventory.counts[GameData.Item.WOOD] = 10
	w.priorities[GameData.Job.HAUL] = 1
	w.ai.tick(0.1)
	var reserved: bool = w.ai.state == CharacterAI.State.HAUL_TAKE and main.processor.incoming.size() == 1
	check(reserved, "（準備）加工材料を取りに行く前に、注文の運搬を予約する")
	if not reserved:
		return
	var wood: int = main.storage.count_of(GameData.Item.WOOD)
	w.hp = 14.99
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.SEARCH and main.processor.incoming.is_empty() and w.ai.haul_recipe.is_empty(), "危険なHPで材料の取り出し前に中断したら、加工材料の運搬予約を解放する")
	check(main.storage.count_of(GameData.Item.WOOD) == wood and w.carrying < 0, "予約のキャンセルは、まだ倉庫にある材料を減らしたり二重返却したりしない")
	w.ai.tick(0.1)
	check(_is_rest(w), "材料運搬の予約を返した後、HP回復の休憩を開始する")


func _test_gather_delivery() -> void:
	print("-- 採取途中の促し: 採取済みの荷物を先に届ける")
	await _fresh()
	var w = W[0]
	var point := GatherPoint.new()
	point.setup(main, "tree")
	point.position = Vector2(900.0, GameData.GROUND_Y_MIN)
	main.resources_root.add_child(point)
	point.set_process(false)
	w.tools["chop"] = GameData.Item.IRON_AXE
	w.ranks[GameData.Field.GATHERER] = 2
	w.priorities[GameData.Job.GATHER] = 1
	w.ai.tick(0.1)
	var picked := _run_until(w, func(): return w.ai.state == CharacterAI.State.GATHER and w.carrying == GameData.Item.WOOD, 60.0)
	check(picked and point.claimed_by == w, "実際に採取を始め、袋の途中まで木材を掘る")
	if not picked:
		return
	var bag: int = w.carry_n
	var stored: int = main.storage.count_of(GameData.Item.WOOD)
	w.fatigue = 30.0
	check(w.ai.request_life_action("rest"), "採取済みの荷物があっても、休憩を一度保留できる")
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.MOVE_TO_STORAGE and w.carrying == GameData.Item.WOOD and w.carry_n == bag, "促されたら採取を切り上げ、袋の中身を保持して倉庫へ向かう")
	check(point.claimed_by == null and w.ai.res == null and w.ai.life_request == "rest", "採取ポイントの予約を返し、休憩は荷卸しまで保留する")
	check(main.storage.count_of(GameData.Item.WOOD) == stored and main.base.bed_index_of(w) < 0, "移動前に物資を瞬間返却したり、ベッドを先取りしたりしない")
	check(_run_until(w, func(): return w.carrying < 0 and main.storage.count_of(GameData.Item.WOOD) == stored + bag), "実際に倉庫へ着いて、採取済みの袋を収納する")
	w.ai.tick(0.1)
	check(_is_rest(w) and w.ai.life_request.is_empty(), "荷卸し後に、保留していた休憩を始める")


func _test_deleted_gather_target() -> void:
	print("-- 採取対象の解放後も、手持ちを通常配達してから生活行動へ")
	for action in ["rest", "eat", "urgent"]:
		await _fresh()
		var w = W[0]
		var point := GatherPoint.new()
		point.setup(main, "tree")
		point.position = Vector2(900.0, GameData.GROUND_Y_MIN)
		main.resources_root.add_child(point)
		point.set_process(false)
		w.tools["chop"] = GameData.Item.IRON_AXE
		w.ranks[GameData.Field.GATHERER] = 2
		w.priorities[GameData.Job.GATHER] = 1
		_set_food(1)
		w.ai.tick(0.1)
		var picked := _run_until(w, func(): return w.ai.state == CharacterAI.State.GATHER and w.carrying == GameData.Item.WOOD)
		check(picked, "%s: 実採取で木材入りの袋を作る" % action)
		if not picked:
			continue
		var bag: int = w.carry_n
		w.fatigue = 30.0
		if action == "urgent":
			w.fatigue = 95.0
			w.hunger = 10.0
		else:
			w.hunger = 70.0
			check(w.ai.request_life_action(action), "%s: 採取中の生活行動を一度保留する" % action)
		point.free()
		check(not is_instance_valid(point), "%s: 荷物を持ったGATHER中に、対象だけを解放する" % action)
		w.ai.tick(0.1)
		check(w.ai.state == CharacterAI.State.MOVE_TO_STORAGE and w.carrying == GameData.Item.WOOD and w.carry_n == bag and w.ai.res == null, "%s: 対象の生存に依存せず採取を切り上げ、木材入りの袋を保持する" % action)
		check(main.food_claims == 0 and main.storage.count_of(GameData.Item.FOOD) == 1 and main.base.bed_index_of(w) < 0, "%s: 配達前に食料・ベッドを予約せず、木材を食料で上書きしない" % action)
		var delivered := _run_until(w, func(): return w.carrying < 0 and main.storage.count_of(GameData.Item.WOOD) == bag)
		check(delivered, "%s: 対象解放後も、通常の収納経路で袋の木材をすべて届ける" % action)
		if not delivered:
			continue
		w.ai.tick(0.1)
		if action == "rest":
			check(_is_rest(w) and w.ai.life_request.is_empty(), "対象解放＋休憩の促し: 配達後にだけ休憩を始める")
		else:
			check(w.ai.state == CharacterAI.State.EAT_TAKE and main.food_claims == 1, "%s: 木材を収納してから、食料1個を予約して食事へ向かう" % action)
			check(_run_until(w, func(): return main.total_eaten == 1), "%s: 倉庫の食料を実際に1個食べる" % action)
			check(main.storage.count_of(GameData.Item.WOOD) == bag and main.storage.count_of(GameData.Item.FOOD) == 0 and main.food_claims == 0, "%s: 木材の実数を保ち、食料1個だけを消費・予約解放する" % action)
			if action == "urgent":
				w.ai.tick(0.1)
				check(_is_rest(w), "対象解放＋疲労95・満腹10: 配達、食事、休憩の順に進む")


func _test_urgent_food_before_rest() -> void:
	print("-- HP低下と重度の空腹が同時なら、食事の後に休憩する")
	await _fresh()
	var w = W[0]
	w.hp = 10.0
	w.hunger = 10.0
	w.fatigue = 80.0
	_set_food(1)
	check(CrewStatus.life_needs(w).slice(0, 3) == ["eat", "rest", "rest"], "HP10・満腹10・疲労80では、食事、HPの休憩、疲労の休憩の順になる")
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.EAT_TAKE and main.food_claims == 1 and main.base.bed_index_of(w) < 0, "REST★0でも、低HPによる休憩より先に食料へ向かう")
	check(_run_until(w, func(): return main.total_eaten == 1), "低HP・重度の空腹が重なっても、食事を実際に完了する")
	check(w.hunger > CrewStatusDB.EAT_URGENT_BELOW and w.hp < CrewStatusDB.REST_HP_URGENT and main.storage.count_of(GameData.Item.FOOD) == 0 and main.food_claims == 0, "食料1個で空腹を回復し、低HPと未解放の食料予約を取り違えない")
	w.ai.tick(0.1)
	check(_is_rest(w) and main.total_eaten == 1, "食事後は残る低HPを理由に休憩し、食料の再消費を繰り返さない")


func _begin_transfer(w, dir: String) -> bool:
	w.priorities[GameData.Job.HAUL] = 1
	if main.request_transfer(GameData.Item.WOOD, CraftDB.TRANSFER_TRIP, dir) != CraftDB.TRANSFER_TRIP:
		return false
	w.ai.tick(0.1)
	return _run_until(w, func(): return w.ai.state == CharacterAI.State.XFER_MOVE)


func _test_transfer_delivery() -> void:
	print("-- 運搬中の促し: 手持ちを保ち通常配達、倉庫満杯でも強制返却しない")
	await _fresh()
	var w = W[0]
	main.storage.inventory.counts[GameData.Item.WOOD] = CraftDB.TRANSFER_TRIP
	var started := _begin_transfer(w, "to_workshop")
	check(started, "実際の運搬依頼で、倉庫から木材を受け取る")
	if not started:
		return
	var bag: int = w.carry_n
	w.fatigue = 30.0
	check(w.ai.request_life_action("rest"), "運搬中の休憩の促しを保留する")
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.XFER_MOVE and w.carrying == GameData.Item.WOOD and w.carry_n == bag and main.transfer_worker == w, "運搬途中で手持ち・運搬担当を失わず、行き先への移動を続ける")
	check(w.ai.life_request == "rest" and main.base.bed_index_of(w) < 0, "配達前には休憩を開始せず、ベッドも予約しない")
	check(_run_until(w, func(): return main.processor.stock.count(GameData.Item.WOOD) == bag and w.carrying < 0), "通常の運搬経路で作業場へ木材を届ける")
	check(main.transfer_worker == null and main.storage.count_of(GameData.Item.WOOD) == 0, "配達後に運搬担当を解放し、倉庫へ強制返却しない")
	w.ai.tick(0.1)
	check(_is_rest(w) and w.ai.life_request.is_empty(), "配達が済んでから休憩する")
	await _fresh()
	w = W[0]
	main.processor.stock.counts[GameData.Item.WOOD] = CraftDB.TRANSFER_TRIP
	started = _begin_transfer(w, "to_storage")
	check(started, "（準備）作業場から倉庫へ戻す木材を受け取る")
	if not started:
		return
	bag = w.carry_n
	main.storage.inventory.counts[GameData.Item.FOOD] = main.storage.max_weight()
	w.fatigue = 95.0
	check(w.ai.request_life_action("rest"), "倉庫が満杯・危険な疲労でも、運搬中の促しを保留する")
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.XFER_MOVE and w.carry_n == bag and w.carrying == GameData.Item.WOOD and main.total_wasted == 0, "促しや危険判定でstop_workの強制返却を使わず、満杯でも荷物を保持する")
	check(_run_until(w, func(): return w.carrying < 0 and main.transfer_worker == null), "満杯時も、通常の倉庫への配達を完了する")
	check(main.storage.count_of(GameData.Item.WOOD) + main.processor.stock.count(GameData.Item.WOOD) == bag, "通常の運搬経路で入りきらない木材は作業場へ残り、物資の実数を失わない")
	w.ai.tick(0.1)
	check(_is_rest(w), "満杯時の配達を終えた後、危険な疲労の休憩を始める")


func _test_processor_pause() -> void:
	print("-- 加工の中断: 作業者予約だけ解放し、注文と進捗を残す")
	await _fresh()
	var w = W[0]
	var recipe: Dictionary = GameData.recipe_by_id("cook").duplicate(true)
	main.processor.receive_manual(recipe)
	w.priorities[GameData.Job.PROCESS] = 3
	w.ai.tick(0.1)
	var started := _run_until(w, func(): return w.ai.state == CharacterAI.State.PROCESS)
	check(started and main.processor.worker == w, "実際に加工設備の作業者を予約し、加工位置へ到着する")
	if not started:
		return
	w.ai.tick(0.5)
	var progress: float = main.processor.progress
	var current: Dictionary = main.processor.current.duplicate(true)
	check(progress > 0.0 and not current.is_empty(), "実際の加工を進め、途中経過を作る")
	w.fatigue = 90.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.SEARCH and main.processor.worker == null, "REST★0でも、危険な疲労で加工を中断し作業者予約を返す")
	check(main.processor.current == current and is_equal_approx(main.processor.progress, progress), "中断しても加工中の注文と進捗を消さない")
	w.ai.tick(0.1)
	check(_is_rest(w), "加工予約を解放した次の区切りで自動休憩する")
	_reset(w)
	w.priorities[GameData.Job.PROCESS] = 3
	w.ai.tick(0.1)
	check(_run_until(w, func(): return w.ai.state == CharacterAI.State.PROCESS), "残っている加工を再び引き受ける")
	w.fatigue = 30.0
	progress = main.processor.progress
	check(w.ai.request_life_action("rest"), "危険域未満でも、加工中の早めの休憩を促せる")
	w.ai.tick(0.1)
	check(main.processor.worker == null and main.processor.current == current and is_equal_approx(main.processor.progress, progress), "手動の促しでも、作業者だけを返し注文と進捗を保持する")
	check(_run_until(w, func(): return _is_rest(w), 5.0), "加工途中の手動促しを、安全な区切りで実行する")


func _test_priority_changes() -> void:
	print("-- 生活行動中の仕事優先度変更は、食料・ベッド予約を壊さない")
	await _fresh()
	var w = W[0]
	w.fatigue = 30.0
	check(w.ai.request_life_action("rest"), "（準備）早めの休憩を促す")
	w.ai.tick(0.1)
	var bed: int = w.bed_index
	w.set_priority(GameData.Job.GATHER, 5)
	w.set_priority(GameData.Job.REST, 0)
	check(w.ai.state == CharacterAI.State.REST_MOVE and w.bed_index == bed and main.base.bed_index_of(w) == bed, "ベッドへの移動中に仕事★を変えても、休憩と予約を維持する")
	check(_run_until(w, func(): return w.ai.state == CharacterAI.State.REST), "優先度変更後も、ベッドへ到着する")
	w.set_priority(GameData.Job.HAUL, 5)
	check(w.ai.state == CharacterAI.State.REST and main.base.bed_index_of(w) == bed, "睡眠中の仕事★変更でも、回復するまで休憩を続ける")
	_reset(w)
	_set_food(1)
	w.hunger = 70.0
	check(w.ai.request_life_action("eat"), "（準備）早めの食事を促す")
	w.ai.tick(0.1)
	w.set_priority(GameData.Job.GATHER, 5)
	check(w.ai.state == CharacterAI.State.EAT_TAKE and main.food_claims == 1 and w.ai._eat_claimed, "食料への移動中に仕事★を変えても、食事と食料予約を維持する")
	check(_run_until(w, func(): return w.ai.state == CharacterAI.State.EAT), "優先度変更後も食料を受け取る")
	w.set_priority(GameData.Job.HAUL, 5)
	check(w.ai.state == CharacterAI.State.EAT and w.carrying == GameData.Item.FOOD, "食事中の仕事★変更でも、手持ちの食料を食べ終えるまで維持する")
	check(_run_until(w, func(): return main.total_eaten == 1), "仕事★を変えても、食事を一度だけ完了する")
	_reset(w)
	_give_beds(0)
	w.fatigue = 30.0
	w.ai.request_life_action("rest")
	w.ai.tick(0.1)
	w.set_priority(GameData.Job.GATHER, 5)
	check(w.ai.state == CharacterAI.State.REST_HERE, "その場の休憩中も、通常の仕事★変更では中断しない")


func _test_rejection_and_cleanup() -> void:
	print("-- 促せない理由、緊急行動の優先、遠征・戦闘不能時の解放")
	await _fresh()
	var w = W[0]
	check(not w.ai.request_life_action("rest") and not w.ai.life_action_reason("rest").is_empty(), "休憩完了条件を満たす健康な仲間には、不要な休憩を促さない")
	check(not w.ai.request_life_action("eat") and not w.ai.life_action_reason("eat").is_empty(), "満腹の仲間には、不要な食事を促さない")
	w.fatigue = 30.0
	w.hunger = 70.0
	check(not w.ai.request_life_action("eat") and not w.ai.life_action_reason("eat").is_empty(), "食料がなければ促しを受理せず、理由を返す")
	_set_food(1)
	w.away = true
	check(not w.ai.request_life_action("rest") and not w.ai.request_life_action("eat") and not w.ai.life_action_reason("rest").is_empty(), "遠征中は両方の促しを拒否し、理由を返す")
	w.away = false
	w.down = true
	check(not w.ai.request_life_action("rest") and not w.ai.request_life_action("eat") and not w.ai.life_action_reason("eat").is_empty(), "戦闘不能中も両方の促しを拒否し、理由を返す")
	w.down = false
	check(w.ai.life_request.is_empty() and main.food_claims == 0 and main.base.bed_index_of(w) < 0, "拒否された促しは、保留・食料予約・ベッド予約を残さない")
	w.fatigue = 80.0
	check(w.ai.request_life_action("eat"), "（準備）自動休憩が必要な仲間に、早めの食事を促す")
	w.ai.tick(0.1)
	check(_is_rest(w) and main.food_claims == 0, "自動の緊急生活行動を、手動の保留より先に開始する")
	_reset(w)
	w.fatigue = 30.0
	w.hunger = 70.0
	w.ai.request_life_action("eat")
	w.ai.tick(0.1)
	check(not w.ai.request_life_action("eat") and not w.ai.life_action_reason("eat").is_empty(), "すでに同じ生活行動に向かっている場合、重複要求を拒否する")
	check(w.ai.request_life_action("rest"), "食事へ移動中に、別の生活行動を一度保留する")
	w.depart()
	check(w.away and w.ai.life_request.is_empty() and main.food_claims == 0 and not w.ai._eat_claimed and main.base.bed_index_of(w) < 0, "遠征出発は、食料予約と生活保留をすべて解放する")
	await _fresh()
	w = W[0]
	w.fatigue = 30.0
	w.hunger = 70.0
	_set_food(1)
	w.ai.request_life_action("rest")
	w.ai.tick(0.1)
	check(main.base.bed_index_of(w) >= 0 and w.ai.request_life_action("eat"), "（準備）ベッド予約と別の生活保留を持つ")
	CrewStatus.damage(w, 100.0)
	check(w.down and w.ai.state == CharacterAI.State.DOWN and w.ai.life_request.is_empty() and main.base.bed_index_of(w) < 0 and main.food_claims == 0, "戦闘不能になると、ベッド予約と生活保留を解放する")
	_reset(w)
	w.fatigue = 30.0
	w.ai.request_life_action("rest")
	w.stop_work()
	check(w.ai.life_request.is_empty(), "stop_workで、まだ予約を取っていない生活保留も解放する")
