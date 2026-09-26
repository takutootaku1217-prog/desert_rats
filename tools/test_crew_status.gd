extends SceneTree
## 仲間のステータス（HP・スタミナ・満腹度・疲労度・精神状態。data/crew_status.gd と scripts/crew_status.gd）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_crew_status.gd
## 段階ごとに確かめる: 1 データの追加 → 2 元気からスタミナへ（動きが同じ） → 3 満腹度と食事 → 4 疲労度 → 5 精神状態 → 6 HP・戦闘不能 →
##   7 速度への影響 → 8 自動行動（休む・食べる） → 9 表示（アイコン・頭上の警告） → 10 仲間の管理画面 → 通し（既存の動きを壊していないか）。

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
	seed(20260926)
	await _fresh()
	_test_step1_data()
	_test_step2_stamina()
	await _test_step3_hunger()
	await _test_step4_fatigue()
	await _test_step5_mental()
	await _test_step6_hp()
	await _test_step7_speed()
	await _test_step8_ai()
	await _test_step9_ui()
	await _test_step10_detail()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## ゲームを新しく作る。仲間は自分では動かさない（診断が手で1コマずつ進める）
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


func _quiet(w) -> void:
	w.set_process(false)
	for j in GameData.job_list():
		w.priorities[j] = 0


# ---------------------------------------------------------------- STEP 1: データ
func _test_step1_data() -> void:
	print("-- STEP 1: ステータスのデータ（設定と、仲間ごとの持ち物）")
	check(CrewStatusDB.STATS == ["hp", "stamina", "hunger", "fatigue"], "ステータスは HP・スタミナ・満腹度・疲労度 の4つ（精神状態は計算される状態）")
	var ok := true
	for s in CrewStatusDB.STATS:
		ok = ok and CrewStatusDB.MAX_STAT.has(s) and CrewStatusDB.EFFECTS.has(s) and CrewStatusDB.STAT_NAMES.has(s) and CrewStatusDB.GAUGE_STAGES.has(s)
	check(ok, "どのステータスにも 最大値・速度への影響・名前・色の段階 がある")
	check(CrewStatusDB.MENTAL_NAMES.size() == 5 and CrewStatusDB.MENTAL_WORK.size() == 5 and CrewStatusDB.MENTAL_COLORS.size() == 5, "精神状態は5段階（好調・普通・不安・不調・限界）")
	check(CrewStatusDB.is_high_bad("fatigue") and not CrewStatusDB.is_high_bad("hp") and not CrewStatusDB.is_high_bad("hunger"), "疲労度だけ「高いほど悪い」")
	check(W.size() == 3, "仲間は3人")
	for w in W:
		# （起動から数コマ動いているので、スタミナ・満腹度は少し減っていてよい）
		var init_ok: bool = is_equal_approx(w.hp, 100.0) and w.stamina > 98.0 and w.hunger > 99.0 and w.fatigue < 1.0
		check(init_ok and w.mental == CrewStatusDB.Mental.NORMAL and not w.down, "%s: 初期値は HP100・スタミナ100・満腹度100・疲労度0・精神状態「普通」" % w.char_name)
	var w0 = W[0]
	check(not ("energy" in w0), "旧名の「元気」（energy）はもう使わない（スタミナ stamina に置き換えた）")


# ---------------------------------------------------------------- STEP 2: 元気 → スタミナ（動きは同じ）
func _stamina_delta(w, state: int, start: float, dt := 1.0) -> float:
	w.ai.state = state
	w.ai.timer = 100.0
	w.sleeping = false
	w.stamina = start
	w._process(dt)
	return w.stamina - start


func _test_step2_stamina() -> void:
	print("-- STEP 2: 元気 → スタミナ（増減の数字は以前と同じ）")
	var w = W[0]
	_quiet(w)
	main.director.enabled = false
	# 以前の数字: 眠る +9.0/秒（車体が傷んでいると +4.5）・待機 -0.25/秒・動いている間 -0.7/秒
	var rest := _stamina_delta(w, CharacterAI.State.REST, 10.0)
	check(is_equal_approx(rest, 9.0), "眠ると +9.0/秒（以前と同じ。実測 %.3f）" % rest)
	var idle := _stamina_delta(w, CharacterAI.State.IDLE, 80.0)
	check(is_equal_approx(idle, -0.25), "待機中は -0.25/秒（以前と同じ。実測 %.3f）" % idle)
	var work := _stamina_delta(w, CharacterAI.State.COMBAT, 80.0)
	check(is_equal_approx(work, -0.7), "動いている間は -0.7/秒（以前と同じ。実測 %.3f）" % work)
	# 車体が傷んでいると、休憩の回復は半分
	var hull_prev: float = main.base.parts[GameData.Part.HULL]
	main.base.parts[GameData.Part.HULL] = GameData.PART_BAD - 1.0
	var rest_bad := _stamina_delta(w, CharacterAI.State.REST, 10.0)
	check(is_equal_approx(rest_bad, 4.5), "車体が傷んでいると、眠っても +4.5/秒（以前と同じ。実測 %.3f）" % rest_bad)
	main.base.parts[GameData.Part.HULL] = hull_prev
	# 上限・下限
	check(is_equal_approx(_stamina_delta(w, CharacterAI.State.REST, 98.0), 2.0), "スタミナは 100 を超えない")
	w.ai.state = CharacterAI.State.COMBAT
	w.stamina = 0.3
	w._process(1.0)
	check(is_equal_approx(w.stamina, 0.0), "スタミナは 0 を下回らない")
	# 酷暑・部屋の効果は、これまでどおり掛かる
	main.director.trigger("heatwave", false)
	main.director.set_stance("heatwave", "run")
	var heat_work := _stamina_delta(w, CharacterAI.State.COMBAT, 80.0)
	check(is_equal_approx(heat_work, -0.7 * 1.7), "酷暑（走り続ける）では、動いている間の疲れが 1.7 倍（%.3f/秒）" % heat_work)
	main.director.active.clear()
	# 休憩の判断（AI）は、設定の基準を読んでいる
	check(CrewStatusDB.REST_STAMINA_URGENT == 25.0 and CrewStatusDB.REST_JOB_STAMINA_BELOW == 70.0 and CrewStatusDB.REST_END_STAMINA == 98.0,
			"休憩の基準（25 未満で最優先・70 未満で休憩に入れる・98 で起きる）は、以前と同じ値で設定にまとまっている")


# ---------------------------------------------------------------- STEP 3: 満腹度と食事
func _set_food(n: int) -> void:
	main.storage.inventory.counts.erase(GameData.Item.FOOD)
	if n > 0:
		main.storage.add_item(GameData.Item.FOOD, n)


func _food() -> int:
	return main.storage.count_of(GameData.Item.FOOD)


## w を1コマずつ進めて、state になるまで待つ（最大 secs 秒）。到達したら true
func _run_until(w, state: int, secs: float, dt := 0.1) -> bool:
	var t := 0.0
	while t < secs:
		if w.ai.state == state:
			return true
		w._process(dt)
		t += dt
	return w.ai.state == state


func _test_step3_hunger() -> void:
	print("-- STEP 3: 満腹度と食事（仲間ごとに個別。全員共通の空腹は使わない）")
	await _fresh()
	var w = W[0]
	var w1 = W[1]
	for x in W:
		_quiet(x)
	# 減り方
	w.hunger = 100.0
	CrewStatus.tick(w, 60.0)
	check(absf(w.hunger - (100.0 - CrewStatusDB.HUNGER_DECAY_PER_MIN)) < 0.01, "満腹度は1分で %.0f 減る（実測 %.2f）" % [CrewStatusDB.HUNGER_DECAY_PER_MIN, 100.0 - w.hunger])
	check(CrewStatusDB.HUNGER_DECAY_PER_MIN >= 3.0 and CrewStatusDB.HUNGER_DECAY_PER_MIN <= 5.0, "減る速さは仕様の範囲（1分あたり 3〜5）")
	w.hunger = 0.5
	CrewStatus.tick(w, 60.0)
	check(w.hunger == 0.0, "満腹度は 0 を下回らない")
	main.director.trigger("coldsnap", false)
	main.director.set_stance("coldsnap", "run")
	w.hunger = 100.0
	CrewStatus.tick(w, 60.0)
	check(absf((100.0 - w.hunger) - CrewStatusDB.HUNGER_DECAY_PER_MIN * 1.5) < 0.01, "寒波（走り続ける）では、食料の減りの倍率（1.5）が満腹度の減りにも掛かる（%.2f）" % (100.0 - w.hunger))
	main.director.active.clear()
	# 旧方式（全員共通）は動かない
	_set_food(5)
	main._update_hungry_flag()
	check(_food() == 5 and not main.hungry, "倉庫の食料は、仲間が食べに行かない限り減らない（時間で自動的には減らない）・全員が空腹にもならない")
	# 空腹の判定は仲間ごと
	w.hunger = 20.0
	w1.hunger = 100.0
	main._update_hungry_flag()
	check(main.hungry, "空腹の仲間が1人でもいれば「空腹」の表示になる")
	w.hunger = 100.0
	main._update_hungry_flag()
	check(not main.hungry, "全員が空腹でなければ、表示は消える")
	# 食べに行く
	w.hunger = 20.0
	w.fatigue = 30.0
	w.stress = 20.0
	_set_food(3)
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state == CharacterAI.State.EAT_TAKE and main.food_claims == 1, "満腹度が基準（%d）を下回ると、仕事より先に食べに行く（在庫を1つ取り置く）" % int(CrewStatusDB.EAT_BELOW))
	check(_run_until(w, CharacterAI.State.EAT, 20.0), "倉庫へ着くと食料を取って、食べ始める")
	check(_food() == 2 and w.carrying == GameData.Item.FOOD and main.food_claims == 0, "倉庫の食料が1つ減り、手に食料を持つ（取り置きは戻る）")
	var eaten0: int = main.total_eaten
	check(_run_until(w, CharacterAI.State.SEARCH, 5.0), "食べ終わると探し直しに戻る")
	check(absf(w.hunger - 20.0 - CrewStatusDB.FOOD_EFFECTS[GameData.Item.FOOD]["hunger"]) < 1.0, "食べると満腹度が回復する（%.0f → %.0f）" % [20.0, w.hunger])
	check(w.fatigue < 30.0 and w.stress < 20.0, "食べると疲労度とストレスが少し下がる（疲労 %.1f・ストレス %.1f）" % [w.fatigue, w.stress])
	check(w.carrying == -1 and main.total_eaten == eaten0 + 1, "食べた食料は消え、食べた数に数えられる")
	# 満腹度が十分なら食べない
	w.hunger = 60.0
	_set_food(3)
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state != CharacterAI.State.EAT_TAKE, "満腹度が基準以上なら、食べに行かない")
	# 食料がなければ食べに行かず、ループしない
	w.hunger = 10.0
	_set_food(0)
	var moved := false
	for i in 30:
		w.ai.state = CharacterAI.State.SEARCH
		w._process(0.1)
		if w.ai.state == CharacterAI.State.EAT_TAKE:
			moved = true
	check(not moved and main.food_claims == 0, "食料がなければ食べに行かない（取り置きも残らない）")
	# 1個の食料に2人は向かわない
	w.hunger = 20.0
	w1.hunger = 20.0
	_set_food(1)
	w.ai.state = CharacterAI.State.SEARCH
	w1.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	w1._process(0.1)
	check(w.ai.state == CharacterAI.State.EAT_TAKE and w1.ai.state != CharacterAI.State.EAT_TAKE and main.food_claims == 1, "食料が1つなら、食べに向かうのは1人だけ")
	# 向かっている間に食料がなくなっても、固まらない
	_set_food(0)
	check(_run_until(w, CharacterAI.State.SEARCH, 20.0) and main.food_claims == 0 and w.ai.eat_wait > 0.0, "着いたときに食料がなければ、あきらめて仕事に戻る（待ち時間を置く）")
	w.ai.eat_wait = 0.0
	# 優先度を変えたら、取り置きは戻る
	w.hunger = 20.0
	_set_food(2)
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(main.food_claims == 1, "（準備）食べに向かっている")
	w.set_priority(GameData.Job.GATHER, 3)
	check(main.food_claims == 0, "食べに向かっている途中で優先度を変えても、取り置きが残らない")
	w.set_priority(GameData.Job.GATHER, 0)
	# 加工の途中でも、とても空腹なら食べに行く（加工の注文が残っていて、続けようと思えば続けられる状態で確かめる）
	main.processor.orders.append(GameData.recipe_by_id("cook").duplicate())
	w.hunger = 100.0
	main.processor.worker = w
	w.ai.state = CharacterAI.State.PROCESS
	w.ai.timer = 100.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.PROCESS, "（対照）元気なら、加工を続ける")
	w.hunger = 10.0
	_set_food(2)
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.SEARCH and main.processor.worker == null, "加工の途中でも、とても空腹なら中断して食事を優先する")
	main.processor.orders.clear()
	w.hunger = 100.0
	# 遠征に出るとき、取り置きが残らない
	w.hunger = 20.0
	_set_food(2)
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	w.depart()
	check(main.food_claims == 0, "遠征に出ても、食料の取り置きは残らない")
	w.arrive(80.0)
	w.set_process(false)
	w.hunger = 100.0
	# 旧方式の倍率は掛からない
	main.hungry = true
	w.hunger = 100.0
	var sp: float = w.current_speed()
	check(is_equal_approx(sp, w.speed), "全員共通の空腹の倍率（0.65）は、もう掛からない")
	main.hungry = false

# ---------------------------------------------------------------- 共通: ステータスを整えて、状態（AI）と眠りを指定して1コマ進める
func _reset(w) -> void:
	w.hp = 100.0
	w.stamina = 100.0
	w.hunger = 100.0
	w.fatigue = 0.0
	w.stress = 0.0
	w.calm = 0.0
	w.down = false
	w.sleeping = false
	w.mental = CrewStatusDB.Mental.NORMAL
	w.ai.state = CharacterAI.State.SEARCH
	w.ai.timer = 100.0
	w.ai.eat_wait = 0.0


func _tick(w, secs: float, state: int = CharacterAI.State.SEARCH, sleeping := false) -> void:
	w.ai.state = state
	w.sleeping = sleeping
	CrewStatus.tick(w, secs)


# ---------------------------------------------------------------- STEP 4: 疲労度
func _test_step4_fatigue() -> void:
	print("-- STEP 4: 疲労度（高いほど悪い。仕事で溜まり、休むと下がる）")
	await _fresh()
	var w = W[0]
	_quiet(w)
	_reset(w)
	_tick(w, 10.0, CharacterAI.State.IDLE)
	check(w.fatigue == 0.0, "待機中は疲労度が上がらない")
	_tick(w, 10.0)
	check(is_equal_approx(w.fatigue, CrewStatusDB.FATIGUE_GAIN_ACTIVE * 10.0), "動いている間は上がる（10秒で %.1f）" % w.fatigue)
	# 眠ると下がる
	w.fatigue = 50.0
	_tick(w, 10.0, CharacterAI.State.REST, true)
	check(is_equal_approx(w.fatigue, 50.0 - CrewStatusDB.FATIGUE_REST_RATE * 10.0), "眠ると下がる（10秒で %.1f）" % (50.0 - w.fatigue))
	w.fatigue = 3.0
	_tick(w, 10.0, CharacterAI.State.REST, true)
	check(w.fatigue == 0.0, "疲労度は 0 を下回らない")
	w.fatigue = 99.9
	_tick(w, 10.0)
	check(w.fatigue == 100.0, "疲労度は 100 を超えない")
	# 悪い状態で動き続けると、溜まりが速い（いちばん大きい倍率だけ。掛け算しない）
	_reset(w)
	w.stamina = 20.0
	_tick(w, 1.0)
	var f_stamina: float = w.fatigue
	_reset(w)
	w.hunger = 20.0
	_tick(w, 1.0)
	var f_hunger: float = w.fatigue
	_reset(w)
	w.hp = 20.0
	_tick(w, 1.0)
	var f_hp: float = w.fatigue
	_reset(w)
	w.stamina = 20.0
	w.hunger = 20.0
	w.hp = 20.0
	_tick(w, 1.0)
	var f_all: float = w.fatigue
	var g := CrewStatusDB.FATIGUE_GAIN_ACTIVE
	check(is_equal_approx(f_stamina, g * 2.0) and is_equal_approx(f_hunger, g * 1.5) and is_equal_approx(f_hp, g * 1.6), "スタミナ・満腹度・HPが低いと溜まりが速い（×2.0・×1.5・×1.6）")
	check(is_equal_approx(f_all, g * 2.0), "3つとも悪くても、掛け算せず、いちばん大きい倍率（×2.0）だけ")
	# 酷暑（疲れやすさ）も掛かる
	_reset(w)
	main.director.trigger("heatwave", false)
	main.director.set_stance("heatwave", "run")
	_tick(w, 1.0)
	check(is_equal_approx(w.fatigue, g * 1.7), "酷暑（走り続ける）では疲労度も 1.7 倍の速さで溜まる")
	main.director.active.clear()
	# 倒れている間もゆっくり下がる
	_reset(w)
	w.fatigue = 40.0
	w.down = true
	_tick(w, 10.0, CharacterAI.State.DOWN)
	check(is_equal_approx(w.fatigue, 40.0 - CrewStatusDB.FATIGUE_DOWN_RATE * 10.0), "倒れている間も疲労度は下がる")
	# 実際に動かしたとき（AIが動く）に、疲労度が溜まる
	_reset(w)
	w.ai.state = CharacterAI.State.SEARCH
	w.priorities[GameData.Job.GATHER] = 0
	for i in 100:
		w._process(0.1)
	check(w.fatigue >= 0.0 and w.stamina < 100.0, "（通し）動かしても値は範囲内（疲労度 %.1f・スタミナ %.1f）" % [w.fatigue, w.stamina])


# ---------------------------------------------------------------- STEP 5: 精神状態
func _test_step5_mental() -> void:
	print("-- STEP 5: 精神状態（疲労度を中心に、満腹度・HP・ストレスから計算される）")
	await _fresh()
	var w = W[0]
	_quiet(w)
	var M = CrewStatusDB.Mental
	_reset(w)
	check(w.mental == M.NORMAL, "初期は「普通」")
	# 好調は、落ち着いた時間が続いたとき
	_tick(w, CrewStatusDB.CALM_SECONDS - 1.0, CharacterAI.State.IDLE)
	check(w.mental == M.NORMAL, "元気な状態が続いても、すぐには好調にならない")
	_tick(w, 2.0, CharacterAI.State.IDLE)
	check(w.mental == M.GOOD, "疲れておらず・空腹でなく・健康な状態が %d 秒続くと「好調」" % int(CrewStatusDB.CALM_SECONDS))
	# 疲労度が中心: 上がるにつれて 好調 → 普通 → 不安 → 不調 → 限界
	var seq := []
	for f in [10.0, 30.0, 55.0, 80.0, 95.0]:
		w.fatigue = f
		w.calm = 999.0 if f < 25.0 else 0.0
		w.mental = CrewStatus.mental_of(w)
		seq.append(w.mental)
	check(seq == [M.GOOD, M.NORMAL, M.ANXIOUS, M.BAD, M.LIMIT], "疲労度が上がると 好調→普通→不安→不調→限界 と悪くなる（%s）" % str(seq))
	# 満腹度・HP・ストレスも影響する
	_reset(w)
	w.hunger = 40.0
	check(CrewStatus.mental_of(w) == M.ANXIOUS, "満腹度 40 → 不安")
	w.hunger = 20.0
	check(CrewStatus.mental_of(w) == M.BAD, "満腹度 20 → 不調")
	w.hunger = 10.0
	check(CrewStatus.mental_of(w) == M.LIMIT, "満腹度 10 → 限界")
	_reset(w)
	w.hp = 40.0
	check(CrewStatus.mental_of(w) == M.ANXIOUS, "HP 40 → 不安")
	w.hp = 20.0
	check(CrewStatus.mental_of(w) == M.BAD, "HP 20 → 不調")
	w.hp = 10.0
	check(CrewStatus.mental_of(w) == M.LIMIT, "HP 10 → 限界")
	_reset(w)
	w.stress = 20.0
	check(CrewStatus.mental_of(w) == M.ANXIOUS, "ストレス 20 → 不安")
	w.stress = 40.0
	check(CrewStatus.mental_of(w) == M.BAD, "ストレス 40 → 不調")
	w.stress = 65.0
	check(CrewStatus.mental_of(w) == M.LIMIT, "ストレス 65 → 限界")
	# ストレスは時間で消える
	_reset(w)
	w.stress = 30.0
	_tick(w, 10.0, CharacterAI.State.IDLE)
	check(is_equal_approx(w.stress, 30.0 - CrewStatusDB.STRESS_DECAY * 10.0), "ストレスは時間で減る（10秒で %.1f）" % (30.0 - w.stress))
	# 疲れると好調は途切れる
	_reset(w)
	w.calm = 100.0
	w.fatigue = 30.0
	_tick(w, 1.0, CharacterAI.State.IDLE)
	check(w.calm == 0.0 and w.mental == M.NORMAL, "疲労度が 25 以上になると、好調は途切れて「普通」に戻る")
	# 精神状態は、数値としては持たない（計算された状態）
	check(not ("mental_value" in w) and not ("morale" in w), "精神状態は独立した数値ではなく、計算される状態")
	# 食べると、精神状態が少し良くなる（ストレスが減る）
	_reset(w)
	w.stress = 20.0
	w.hunger = 60.0
	CrewStatus.eat(w, GameData.Item.FOOD)
	check(w.stress < 20.0, "食事でストレスが少し減る（精神の回復）")


# ---------------------------------------------------------------- STEP 6: HP と戦闘不能
func _test_step6_hp() -> void:
	print("-- STEP 6: HP（ケガ・回復・戦闘不能）")
	await _fresh()
	var w = W[0]
	var w1 = W[1]
	_quiet(w)
	_quiet(w1)
	_reset(w)
	CrewStatus.damage(w, 30.0, 10.0)
	check(is_equal_approx(w.hp, 70.0) and is_equal_approx(w.stress, 10.0) and not w.down, "ダメージで HP が減り、ストレスが増える")
	# 回復
	_tick(w, 10.0, CharacterAI.State.REST, true)
	check(is_equal_approx(w.hp, 70.0 + CrewStatusDB.HP_REST_RATE * 10.0), "眠っている間は HP が回復する（10秒で +%.1f）" % (w.hp - 70.0))
	_tick(w, 10.0)
	check(is_equal_approx(w.hp, 77.0), "起きて動いている間は回復しない")
	# 戦闘不能
	_reset(w)
	w.carrying = GameData.Item.WOOD
	w.carry_n = 2
	var wood0: int = main.storage.count_of(GameData.Item.WOOD)
	w.ai.state = CharacterAI.State.MOVE_TO_STORAGE
	CrewStatus.damage(w, 100.0, 20.0)
	check(w.down and w.hp == 0.0 and w.ai.state == CharacterAI.State.DOWN, "HP が 0 になると戦闘不能（倒れる。死亡ではない）")
	check(w.carrying == -1 and main.storage.count_of(GameData.Item.WOOD) == wood0 + 2, "持っていた荷物は倉庫へ戻る")
	CrewStatus.damage(w, 50.0, 50.0)
	check(w.hp == 0.0 and w.stress == 20.0, "倒れている間は、さらにダメージを受けない")
	for i in 50:
		w._process(0.1)
	check(w.ai.state == CharacterAI.State.DOWN and w.down, "倒れている間は、AI が仕事を探さない（%.0f 秒たっても倒れたまま）" % 5.0)
	check(w.ai.status_text() == "倒れている", "状態の表示は「倒れている」")
	# 起き上がる
	var t := 0.0
	while w.down and t < 200.0:
		w._process(0.5)
		t += 0.5
	check(not w.down and w.hp >= CrewStatusDB.HP_REVIVE_AT - 0.01, "放っておいても、HP が %d に戻ると起き上がる（%.0f 秒）" % [int(CrewStatusDB.HP_REVIVE_AT), t])
	w._process(0.1)
	check(w.ai.state != CharacterAI.State.DOWN, "起き上がると、AI は探し直す")
	# 優先度を変えても、倒れている仲間は動かない
	_reset(w)
	CrewStatus.damage(w, 100.0)
	w.set_priority(GameData.Job.GATHER, 4)
	check(w.ai.state == CharacterAI.State.DOWN, "倒れている間は、優先度を変えても動かない")
	w.set_priority(GameData.Job.GATHER, 0)
	# 遠征には出せない
	main.expedition.state = "offered"
	check(main.expedition.block_reason([w], "standard", false) != "", "倒れている仲間は遠征に出せない")
	main.expedition.state = "idle"
	# 敵の攻撃
	_reset(w)
	_reset(w1)
	w.position = Vector2(700, GameData.LO_Y)
	w1.position = Vector2(100, GameData.LO_Y)
	var e := Enemy.new()
	main.enemies_root.add_child(e)
	e.setup_kind(main, "scorpion")
	e.position = Vector2(700, GameData.LO_Y)
	e._hit_nearby_worker()
	check(is_equal_approx(w.hp, 100.0 - CrewStatusDB.RAID_HIT_HP) and is_equal_approx(w.stress, CrewStatusDB.RAID_HIT_STRESS) and w1.hp == 100.0, "敵の攻撃は、近くの仲間のHPを減らし、ストレスを与える（遠くの仲間は無傷）")
	w.hp = 0.0
	w.down = true
	e._hit_nearby_worker()
	check(w.hp == 0.0, "倒れている仲間は狙われない")
	e.queue_free()
	# 襲撃の開始で、全員が緊張する
	_reset(w)
	_reset(w1)
	main.director.trigger("raid_scorpion", false)
	check(w.stress >= CrewStatusDB.RAID_START_STRESS - 0.1 and w1.stress >= CrewStatusDB.RAID_START_STRESS - 0.1, "襲撃が始まると、全員のストレスが増える")
	main.director.active.clear()
	for en in main.enemies_root.get_children():
		en.queue_free()
	# 狩りの事故
	seed(1234)
	var hits := 0
	var min_dmg := 100.0
	var max_dmg := 0.0
	for i in 2000:
		_reset(w)
		CrewStatus.hunt_injury(w, "hare")
		if w.hp < 100.0:
			hits += 1
			min_dmg = minf(min_dmg, 100.0 - w.hp)
			max_dmg = maxf(max_dmg, 100.0 - w.hp)
	var rate := float(hits) / 2000.0
	check(rate > 0.015 and rate < 0.05 and min_dmg >= 4.0 and max_dmg <= 8.0, "スナウサギを倒したときの事故は約3%%（実測 %.1f%%）・ダメージ 4〜8" % (rate * 100.0))
	var hits_h := 0
	for i in 2000:
		_reset(w)
		CrewStatus.hunt_injury(w, "hump")
		if w.hp < 100.0:
			hits_h += 1
	check(float(hits_h) / 2000.0 > 0.10, "コブ獣は事故が多い（約15%%。実測 %.1f%%）" % (float(hits_h) / 20.0))
	_reset(w)
	_reset(w1)

# ---------------------------------------------------------------- STEP 7: 速度への影響
func _mults(w) -> Array:
	return [CrewStatus.work_mult(w), CrewStatus.move_mult(w)]


func _same_pair(a: Array, work: float, move: float) -> bool:
	return absf(a[0] - work) < 0.001 and absf(a[1] - move) < 0.001


func _test_step7_speed() -> void:
	print("-- STEP 7: 速度への影響（いちばん悪いもので決める。掛け算しない。完全には止まらない）")
	await _fresh()
	var w = W[0]
	_quiet(w)
	_reset(w)
	w.calm = 0.0
	w.mental = CrewStatusDB.Mental.NORMAL
	check(_same_pair(_mults(w), 1.0, 1.0), "すべて良好（普通）なら 作業100%・移動100%")
	# HP・スタミナ・満腹度（低いほど悪い）: 50 以上 100/100・50〜25 90/95・25 未満 70/80・15 未満 50/60
	for stat in ["hp", "stamina", "hunger"]:
		var got := []
		for v in [80.0, 40.0, 20.0, 10.0]:
			_reset(w)
			w.set(stat, v)
			w.mental = CrewStatusDB.Mental.NORMAL                 # 精神状態の補正は別に確かめる
			got.append(_mults(w))
		var ok: bool = _same_pair(got[0], 1.0, 1.0) and _same_pair(got[1], 0.9, 0.95) and _same_pair(got[2], 0.7, 0.8) and _same_pair(got[3], 0.5, 0.6)
		check(ok, "%s: 80→100/100・40→90/95・20→70/80・10→50/60" % CrewStatusDB.STAT_NAMES[stat])
	# 疲労度（高いほど悪い）
	var fg := []
	for v in [10.0, 30.0, 60.0, 80.0, 95.0]:
		_reset(w)
		w.fatigue = v
		w.mental = CrewStatusDB.Mental.NORMAL
		fg.append(_mults(w))
	check(_same_pair(fg[0], 1.0, 1.0) and _same_pair(fg[1], 0.95, 0.95) and _same_pair(fg[2], 0.875, 0.9) and _same_pair(fg[3], 0.7, 0.8) and _same_pair(fg[4], 0.5, 0.6),
			"疲労度: 10→100/100・30→95/95・60→87.5/90・80→70/80・95→50/60")
	# 掛け算しない: 全部が悪くても、いちばん悪いものだけ
	_reset(w)
	w.hp = 20.0
	w.stamina = 20.0
	w.hunger = 20.0
	w.fatigue = 80.0
	w.mental = CrewStatusDB.Mental.NORMAL
	check(_same_pair(_mults(w), 0.7, 0.8), "全部が「悪い」でも、掛け算せず、いちばん悪い 70/80 のまま")
	_reset(w)
	w.hp = 5.0
	w.stamina = 5.0
	w.hunger = 5.0
	w.fatigue = 99.0
	w.mental = CrewStatusDB.Mental.LIMIT
	var worst := _mults(w)
	check(worst[0] >= 0.5 - 0.001 and worst[1] >= 0.6 - 0.001 and worst[0] > 0.0, "いちばん悪くても、作業 %.0f%%・移動 %.0f%% 以下には落ちない（止まらない）" % [worst[0] * 100.0, worst[1] * 100.0])
	# 精神状態の補正
	_reset(w)
	var mm := []
	for m in [CrewStatusDB.Mental.GOOD, CrewStatusDB.Mental.NORMAL, CrewStatusDB.Mental.ANXIOUS, CrewStatusDB.Mental.BAD, CrewStatusDB.Mental.LIMIT]:
		w.mental = m
		mm.append(snappedf(CrewStatus.work_mult(w), 0.001))
	var mm_ok: bool = absf(mm[0] - 1.05) < 0.001 and absf(mm[1] - 1.0) < 0.001 and absf(mm[2] - 0.95) < 0.001 and absf(mm[3] - 0.85) < 0.001 and absf(mm[4] - 0.7) < 0.001
	check(mm_ok, "精神状態の補正は 好調105%%・普通100%%・不安95%%・不調85%%・限界70%%（%s）" % str(mm))
	w.mental = CrewStatusDB.Mental.BAD
	w.stamina = 20.0                                              # 作業70%（精神状態の85%より悪い）
	check(absf(CrewStatus.work_mult(w) - 0.7) < 0.001, "精神状態は、ほかのステータスより悪いときだけ効く（掛け算しない）")
	w.mental = CrewStatusDB.Mental.GOOD
	check(absf(CrewStatus.work_mult(w) - 0.7) < 0.001, "好調でも、ほかのステータスが悪ければ、上乗せはない")
	w.mental = CrewStatusDB.Mental.LIMIT
	w.stamina = 100.0
	check(CrewStatus.move_mult(w) == 1.0, "精神状態は移動には影響しない（作業だけ）")
	# 実際の作業・移動に反映される
	_reset(w)
	w.mental = CrewStatusDB.Mental.NORMAL
	var sp0: float = w.current_speed()
	var fm0: float = w.field_mult(GameData.Field.GATHERER)
	w.stamina = 20.0
	check(is_equal_approx(w.current_speed(), sp0 * 0.8) and is_equal_approx(w.field_mult(GameData.Field.GATHERER), fm0 * 0.7), "実際の移動速度・作業速度に反映される（スタミナ 20 → 移動×0.8・作業×0.7）")
	w.stamina = 100.0
	w.hunger = 10.0
	check(is_equal_approx(w.current_speed(), sp0 * 0.6), "空腹（満腹度 10）は、その仲間だけ遅くなる")
	check(is_equal_approx(W[1].current_speed(), W[1].speed * CrewStatus.move_mult(W[1])) and W[1].current_speed() >= W[1].speed * 0.999, "ほかの仲間は遅くならない（全員共通の空腹ではない）")
	# 戦闘不能だけが完全に止まる（AIは動かさない）
	_reset(w)


# ---------------------------------------------------------------- STEP 8: 自動行動（休む・食べる）
func _give_beds(n: int) -> void:
	main.base.built["bed"] = range(n)
	for i in main.base.beds.size():
		main.base.beds[i] = null


func _test_step8_ai() -> void:
	print("-- STEP 8: 自動行動（仕事の優先度は残したまま、休む・食べるを足す）")
	await _fresh()
	var w = W[0]
	var w1 = W[1]
	_quiet(w)
	_quiet(w1)
	_give_beds(3)
	_set_food(5)
	w.priorities[GameData.Job.REST] = 3
	# 並び順
	_reset(w)
	w.hp = 20.0
	w.hunger = 10.0
	w.fatigue = 80.0
	w.stamina = 20.0
	w.mental = CrewStatus.mental_of(w)
	var needs := CrewStatus.life_needs(w)
	check(needs.slice(0, 3) == ["rest", "eat", "rest"], "急ぎの順: HPが低い→休む／満腹度が低い→食べる／疲労度が高い→休む（%s）" % str(needs))
	_reset(w)
	check(CrewStatus.life_needs(w).is_empty(), "元気な状態では、生活の必要はない")
	# スタミナ 25 未満 → 休む（以前と同じ）
	_reset(w)
	w.stamina = 20.0
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE, "スタミナが 25 未満なら、休憩に向かう（以前と同じ）")
	check(_run_until(w, CharacterAI.State.REST, 20.0), "ベッドへ着くと眠る")
	# スタミナが戻っても、疲労度が高いあいだは休み続ける
	w.fatigue = 60.0
	w.stamina = 100.0
	w._process(0.1)
	check(w.ai.state == CharacterAI.State.REST, "スタミナが満タンでも、疲労度が高いあいだは休み続ける")
	var t := 0.0
	while w.ai.state == CharacterAI.State.REST and t < 200.0:
		w._process(0.5)
		t += 0.5
	check(w.ai.state != CharacterAI.State.REST and w.fatigue <= CrewStatusDB.REST_END_FATIGUE + 0.01, "疲労度が %d まで下がると起きる（%.0f 秒。疲労度 %.1f）" % [int(CrewStatusDB.REST_END_FATIGUE), t, w.fatigue])
	# HP が低いと休んで回復する
	_reset(w)
	w.hp = 30.0
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE, "HP が低い（25 未満）と、休憩に向かう")
	t = 0.0
	while w.ai.state != CharacterAI.State.SEARCH and t < 300.0:
		w._process(0.5)
		t += 0.5
	check(w.hp >= CrewStatusDB.REST_END_HP - 0.5, "休むと HP が %d まで回復してから起きる（HP %.0f・%.0f 秒）" % [int(CrewStatusDB.REST_END_HP), w.hp, t])
	# 休憩の優先度が 0 なら、休まない（優先度はそのまま尊重する）
	_reset(w)
	w.stamina = 10.0
	w.priorities[GameData.Job.REST] = 0
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state != CharacterAI.State.REST_MOVE, "休憩の優先度が★0なら、疲れていても休みに行かない（仕事の優先度はそのまま）")
	w.priorities[GameData.Job.REST] = 3
	# ベッドがなければ、休憩に向かわず、ループしない
	_give_beds(0)
	_reset(w)
	w.stamina = 10.0
	var loops := 0
	for i in 40:
		w.ai.state = CharacterAI.State.SEARCH
		w._process(0.1)
		if w.ai.state == CharacterAI.State.REST_MOVE or w.ai.state == CharacterAI.State.REST:
			loops += 1
	check(loops == 0 and main.base.beds == [null, null, null], "ベッドがなければ休憩に向かわない（取り置きも残らない）")
	_give_beds(3)
	# 食料がなくて空腹なら、仕事を続ける
	_reset(w)
	w.hunger = 10.0
	_set_food(0)
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state != CharacterAI.State.EAT_TAKE, "食料がなければ食べに行かない")
	# 空腹と疲れが同時: 満腹度がとても低ければ、食べるのが先
	_reset(w)
	w.hunger = 10.0
	w.stamina = 20.0
	_set_food(3)
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state == CharacterAI.State.EAT_TAKE, "とても空腹で疲れているときは、先に食べる")
	check(_run_until(w, CharacterAI.State.SEARCH, 20.0) and w.hunger >= 30.0, "食べ終わる")
	w._process(0.1)
	check(w.ai.state == CharacterAI.State.REST_MOVE, "食べたあとは、休憩に向かう")
	# 加工の途中でも、危険なほど疲れていれば中断して休む（加工の注文が残っている状態で確かめる）
	main.processor.orders.append(GameData.recipe_by_id("cook").duplicate())
	_reset(w)
	w.stamina = 10.0
	main.processor.worker = w
	w.ai.state = CharacterAI.State.PROCESS
	w.ai.timer = 100.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.SEARCH and main.processor.worker == null, "加工の途中でも、危険なほど疲れていれば中断する")
	_give_beds(0)
	_reset(w)
	w.stamina = 10.0
	main.processor.worker = w
	w.ai.state = CharacterAI.State.PROCESS
	w.ai.timer = 100.0
	w.ai.tick(0.1)
	check(w.ai.state == CharacterAI.State.PROCESS, "ベッドがないときは中断しない（中断しても休めず、往復するだけのため）")
	main.processor.worker = null
	main.processor.orders.clear()
	_give_beds(3)
	# 仕事の優先度は、元気なあいだは、そのまま効く（生活の必要がなければ、いつもどおり仕事を選ぶ）
	_reset(w)
	w.priorities[GameData.Job.REST] = 3
	w.ai.state = CharacterAI.State.SEARCH
	w._process(0.1)
	check(w.ai.state != CharacterAI.State.REST_MOVE and w.ai.state != CharacterAI.State.EAT_TAKE, "元気な仲間は、休憩や食事を挟まず、いつもどおり仕事を探す")
	# 旧処理の撤去の確認
	_reset(w)
	_reset(w1)

# ---------------------------------------------------------------- STEP 9: 表示（アイコンゲージ・精神状態の顔・頭上の警告）
func _test_step9_ui() -> void:
	print("-- STEP 9: 表示（アイコン自体がゲージ・精神状態の顔・頭上の警告）")
	await _fresh()
	# 絵（オリジナルのドット絵。枠と充填範囲の2枚）
	var art_ok := true
	for n in ["hp", "stamina", "hunger", "fatigue"]:
		var mask := IconGauge._load_image("res://assets/ui/%s_mask.png" % n)
		var frame := IconGauge._load_image("res://assets/ui/%s.png" % n)
		var dots := 0
		var covered := 0
		for y in mask.get_height():
			for x in mask.get_width():
				if mask.get_pixel(x, y).a > 0.5:
					dots += 1
					if frame.get_pixel(x, y).a > 0.05:
						covered += 1
		var good: bool = mask.get_width() == 16 and mask.get_height() == 16 and frame.get_width() == 16 and dots >= 30 and covered == 0
		art_ok = art_ok and good
		if not good:
			print("       絵に問題: %s（充填範囲 %d ドット・枠が隠す %d）" % [n, dots, covered])
	check(art_ok, "HP・スタミナ・満腹度・疲労度のアイコンは 16x16 の絵で、充填範囲が枠に隠れない")
	var faces_ok := true
	for f in CrewStatusDB.MENTAL_ICON_FILES:
		var img := IconGauge._load_image("res://assets/ui/%s.png" % f)
		faces_ok = faces_ok and img.get_width() == 16 and img.get_height() == 16
	check(faces_ok and CrewStatusDB.MENTAL_ICON_FILES.size() == 5, "精神状態の顔（5段階）の絵がある")
	# 表示部品
	var w = W[0]
	_quiet(w)
	_reset(w)
	var v := CrewStatusView.new().setup(Vector2i(8, 8), 12)
	root.add_child(v)
	await process_frame
	w.hp = 40.0
	v.update_from(w)
	var g: IconGauge = v.gauge("hp")
	check(is_equal_approx(g.ratio, 0.4) and g.current_color() == CrewStatusDB.COLOR_CAUTION and not g.blink, "HP 40: 充填 40%・黄・点滅なし")
	w.hp = 20.0
	v.update_from(w)
	check(g.current_color() == CrewStatusDB.COLOR_DANGER and not g.blink, "HP 20: 赤・（危険の線 15 までは）点滅なし")
	w.hp = 10.0
	v.update_from(w)
	var others_still := not v.gauge("stamina").blink and not v.gauge("hunger").blink and not v.gauge("fatigue").blink
	check(g.blink and others_still, "HP 10: HP のアイコンだけが赤く点滅する")
	w.hp = 100.0
	v.update_from(w)
	check(is_equal_approx(g.ratio, 1.0) and g.current_color() == CrewStatusDB.COLOR_GOOD and not g.blink, "HP 100: 満タン・緑・点滅なし")
	# 減った部分は、いまの色の暗い色
	w.stamina = 40.0
	v.update_from(w)
	var sg: IconGauge = v.gauge("stamina")
	var img := sg.interior_image()
	var order := sg.fill_dots()
	var top_dot: Vector2i = order[order.size() - 1]
	var bottom_dot: Vector2i = order[0]
	var empty_c: Color = img.get_pixel(top_dot.x, top_dot.y)
	var fill_c: Color = img.get_pixel(bottom_dot.x, bottom_dot.y)
	check(absf(empty_c.r - fill_c.r * 0.28) < 0.02 and absf(empty_c.g - fill_c.g * 0.28) < 0.02, "減った部分は、いまの色（%s）の暗い色で表す" % fill_c.to_html(false))
	# 疲労度は「余力」で表す（疲れるほど中身が減る）
	w.fatigue = 0.0
	v.update_from(w)
	var fg: IconGauge = v.gauge("fatigue")
	check(is_equal_approx(fg.ratio, 1.0) and fg.current_color() == CrewStatusDB.COLOR_GOOD and v.number_label("fatigue").text == "100", "疲労度 0: 余力いっぱい（緑・数字 100）")
	w.fatigue = 60.0
	v.update_from(w)
	check(is_equal_approx(fg.ratio, 0.4) and fg.current_color() == CrewStatusDB.COLOR_WARN and not fg.blink and v.number_label("fatigue").text == "40", "疲労度 60: 余力 40%（だいだい・点滅なし・数字 40）")
	w.fatigue = 80.0
	v.update_from(w)
	check(fg.current_color() == CrewStatusDB.COLOR_DANGER and fg.blink, "疲労度 80: 赤く点滅（疲労度 75 以上）")
	w.fatigue = 0.0
	# 数字
	w.hunger = 64.0
	v.update_from(w)
	check(v.number_label("hunger").text == "64" and v.number_label("hunger").visible, "数字はアイコンの下に出る")
	CrewStatusView.show_numbers = false
	v.update_from(w)
	check(not v.number_label("hunger").visible and not v.number_label("hp").visible, "数値の表示を OFF にすると、数字が消える（アイコンだけ）")
	check(is_equal_approx(v.gauge("hunger").ratio, 0.64), "数字を消しても、アイコンのゲージは同じ")
	CrewStatusView.show_numbers = true
	w.hunger = 100.0
	# 精神状態の顔
	for m in 5:
		w.mental = m
		v.update_from(w)
		var right_tex: bool = v.face().texture == GameData.tex("res://assets/ui/%s.png" % CrewStatusDB.MENTAL_ICON_FILES[m])
		check(right_tex and v.face().modulate.is_equal_approx(Color(CrewStatusDB.MENTAL_COLORS[m], v.face().modulate.a)), "精神状態「%s」の顔と色" % CrewStatusDB.MENTAL_NAMES[m])
	w.mental = CrewStatusDB.Mental.NORMAL
	v.update_from(w)
	check(CrewStatusView.tooltip_of(w, "fatigue").contains("余力") and CrewStatusView.tooltip_of(w, "hp").contains("HP"), "アイコンに載せたときの説明（正確な値）がある")
	v.queue_free()
	# 頭上の警告: いちばん危険なものを1つだけ（HP > 満腹度 > 疲労度 > スタミナ > 精神状態）
	_reset(w)
	check(CrewStatus.warning(w).is_empty(), "元気なら警告なし")
	w.stamina = 20.0
	check(CrewStatus.warning(w).get("stat", "") == "stamina", "スタミナだけ低い → スタミナ")
	w.fatigue = 80.0
	check(CrewStatus.warning(w).get("stat", "") == "fatigue", "疲労度も高い → 疲労度（スタミナより優先）")
	w.hunger = 20.0
	check(CrewStatus.warning(w).get("stat", "") == "hunger", "満腹度も低い → 満腹度（疲労度より優先）")
	w.hp = 20.0
	check(CrewStatus.warning(w).get("stat", "") == "hp", "HPも低い → HP（いちばん優先）")
	check(not CrewStatus.warning(w)["strong"], "HP 20 は「注意」（点滅しない）")
	w.hp = 10.0
	check(CrewStatus.warning(w)["strong"], "HP 10 は「危険」（点滅する）")
	_reset(w)
	w.mental = CrewStatusDB.Mental.LIMIT
	check(CrewStatus.warning(w).get("stat", "") == "mental", "ほかが問題なくても、精神状態が限界なら警告（顔）")
	_reset(w)
	# 上部の仲間カード: 元気のバーの代わりに、4つのアイコンと顔
	var card_ok := true
	for x in W:
		card_ok = card_ok and main.ui._cards[x].has("view") and main.ui._cards[x]["view"] is CrewStatusView
	check(card_ok, "上部の仲間カードに、アイコンゲージ（4つ）と顔がある")
	W[1].hp = 30.0
	W[1].fatigue = 60.0
	main.ui._process(0.1)
	var cv: CrewStatusView = main.ui._cards[W[1]]["view"]
	check(is_equal_approx(cv.gauge("hp").ratio, 0.3) and is_equal_approx(cv.gauge("fatigue").ratio, 0.4), "カードの表示が、その仲間の値を反映する（ほかの仲間とは別）")
	check(is_equal_approx(main.ui._cards[W[0]]["view"].gauge("hp").ratio, 1.0), "ほかの仲間のカードは影響されない")
	var found_old := _find_text(main.ui, "元気")
	check(not found_old, "カードに「元気」の文字・バーは残っていない")
	_reset(W[1])
	# アイコンは、Worker の値を読むだけ（表示が値を書き換えない）
	var before := [W[1].hp, W[1].stamina, W[1].hunger, W[1].fatigue, W[1].mental]
	main.ui._process(0.1)
	check([W[1].hp, W[1].stamina, W[1].hunger, W[1].fatigue, W[1].mental] == before, "表示は値を読むだけで、書き換えない")


func _find_text(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	if node is Button and (node as Button).text.contains(needle):
		return true
	for c in node.get_children():
		if _find_text(c, needle):
			return true
	return false


# ---------------------------------------------------------------- STEP 10: 仲間の管理画面
func _test_step10_detail() -> void:
	print("-- STEP 10: 仲間の管理画面（5つの状態を、同じアイコンで表示）")
	await _fresh()
	var w = W[0]
	_quiet(w)
	main.detail.toggle()
	await process_frame
	check(main.detail._overlay.visible and main.detail._live.has("view") and main.detail._live["view"] is CrewStatusView, "管理画面を開くと、選んだ仲間のステータスがアイコンで出る")
	var dv: CrewStatusView = main.detail._live["view"]
	check(dv.gauge("hp").display_size.x > main.ui._cards[w]["view"].gauge("hp").display_size.x, "管理画面のアイコンは、カードより大きい（同じ部品を大きさ違いで使い回す）")
	w.hp = 55.0
	w.stamina = 35.0
	w.hunger = 70.0
	w.fatigue = 45.0
	w.mental = CrewStatusDB.Mental.ANXIOUS
	main.detail._update_live()
	check(is_equal_approx(dv.gauge("hp").ratio, 0.55) and is_equal_approx(dv.gauge("stamina").ratio, 0.35) and is_equal_approx(dv.gauge("hunger").ratio, 0.70) and is_equal_approx(dv.gauge("fatigue").ratio, 0.55),
			"HP・スタミナ・満腹度・疲労度（余力）が、その仲間の値で出る")
	check(dv.face().texture == GameData.tex("res://assets/ui/mental_anxious.png"), "精神状態（不安）の顔が出る")
	check(not _find_text(main.detail._overlay, "元気"), "管理画面に「元気」の表示は残っていない")
	check(main.detail._live["status"].text.contains(w.ai.status_text()), "行動の状態の文字も、そのまま出る")
	# 別の仲間を選ぶと、その仲間の値に変わる
	W[1].hp = 15.0
	main.detail._select(W[1])
	await process_frame
	var dv2: CrewStatusView = main.detail._live["view"]
	main.detail._update_live()
	check(is_equal_approx(dv2.gauge("hp").ratio, 0.15), "別の仲間を選ぶと、その仲間の値に切り替わる")
	# 育成タブでも出る
	main.detail._set_tab(1)
	await process_frame
	check(main.detail._live.has("view"), "「育成」タブでも、ステータスが出る")
	main.detail._set_tab(0)
	main.detail.close()
	_reset(W[1])
	_reset(w)