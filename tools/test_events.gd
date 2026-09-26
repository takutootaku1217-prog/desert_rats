extends SceneTree
## 旅の出来事（天候・トラブル・好機）の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_events.gd
## 出来事の倍率・予報→発生→終了・対処方針・実際の効果・ランダム進行を確かめる。

var fails := 0
var main


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _quiet() -> void:
	## 確認のため、自動の出来事を止めて、状態をきれいにする
	var d: Director = main.director
	d.enabled = false
	d.active.clear()
	d.forecast.clear()
	d.default_stance.clear()


func _run() -> void:
	var d: Director = main.director
	var H := GameData.Part.HULL
	var D := GameData.Part.DRIVE
	var M := GameData.Part.MACHINE

	print("== 初期状態 ==")
	_quiet()
	check(d != null and main.event_hud != null, "出来事の進行役と画面がある")
	check(is_equal_approx(d.speed_mult(), 1.0) and is_equal_approx(d.wear_mult(H), 1.0) and is_equal_approx(d.energy_mult(), 1.0)
			and is_equal_approx(d.food_mult(), 1.0) and is_equal_approx(d.spawn_mult(), 1.0) and not d.outdoor_blocked(),
			"何も起きていないときは全ての倍率が 1.0")
	check(EventDB.EVENTS.size() >= 6, "出来事の表に %d 種類ある" % EventDB.EVENTS.size())

	print("== 砂嵐の対処方針 ==")
	d.trigger("sandstorm", false)
	check(d.active.size() == 1 and d.active[0]["stance"] == "slow", "砂嵐が発生し、初期の対処は「減速して進む」")
	check(is_equal_approx(d.speed_mult(), 0.5) and is_equal_approx(d.wear_mult(H), 1.3) and is_equal_approx(d.outdoor_mult(), 0.75),
			"減速: 速度×0.5・車体の傷み×1.3・屋外作業×0.75")
	d.set_stance("sandstorm", "push")
	check(is_equal_approx(d.speed_mult(), 1.0) and is_equal_approx(d.wear_mult(H), 2.6) and is_equal_approx(d.wear_mult(M), 1.0),
			"突っ切る: 速度そのまま・車体と走行装置の傷み×2.6（加工設備は変わらない）")
	d.set_stance("sandstorm", "halt")
	check(d.speed_mult() == 0.0 and d.outdoor_blocked() and is_equal_approx(d.wear_mult(D), 0.0) and d.spawn_mult() == 0.0,
			"停止: 速度0・屋外作業不可・走行装置は傷まず・資源が出ない")
	check(d.default_stance["sandstorm"] == "halt", "選んだ対処は、次の砂嵐の自動対処になる")
	d.active.clear()
	d.trigger("sandstorm", false)
	check(d.active[0]["stance"] == "halt", "次の砂嵐は、最後に選んだ対処で始まる（放置しても回る）")

	print("== 実際の効果 ==")
	# 車体の傷み
	main.base.parts[H] = 100.0
	main.base.wear(H, 10.0)
	check(is_equal_approx(main.base.parts[H], 100.0 - 10.0 * 0.5), "停止中の砂嵐では車体の傷みが半分（-5）")
	d.set_stance("sandstorm", "push")
	main.base.parts[H] = 100.0
	main.base.wear(H, 10.0)
	check(is_equal_approx(main.base.parts[H], 100.0 - 26.0), "突っ切ると車体の傷みが2.6倍（-26）")
	# 停止すると実際に止まる
	d.set_stance("sandstorm", "halt")
	await process_frame
	await process_frame
	check(main.scroll_speed == 0.0, "停止を選ぶと拠点の速度が実際に0になる")
	# 屋外作業の禁止
	var w = main.workers[0]
	check(not w.ai._try_start(GameData.Job.GATHER) and not w.ai._try_start(GameData.Job.HUNT),
			"屋外作業が禁止のあいだ、回収と狩猟は始まらない")
	# 仲間の疲れ
	d.active.clear()
	d.trigger("heatwave", false)
	d.set_stance("heatwave", "run")
	check(is_equal_approx(d.energy_mult(), 1.7) and is_equal_approx(d.wear_mult(M), 1.8), "酷暑・走り続ける: 疲れ×1.7・加工設備の傷み×1.8")
	var e0: float = w.energy
	w.energy = 100.0
	w.ai.state = CharacterAI.State.SEARCH
	w._process(1.0)
	check(w.energy < 100.0 - 0.7 * 1.5, "酷暑では仲間が実際に疲れやすくなる (%.2f)" % (100.0 - w.energy))
	# 寒波: 暖房の燃料
	d.active.clear()
	d.trigger("coldsnap", false)
	d.set_stance("coldsnap", "run")
	main.base.fuel = 100.0
	d.tick(10.0, 0.0)
	check(is_equal_approx(main.base.fuel, 100.0 - 0.30 * 10.0), "寒波・走り続ける: 暖房で燃料が減る（10秒で3）")
	check(is_equal_approx(d.food_mult(), 1.5), "寒波・走り続ける: 食料の減りが1.5倍")

	print("== 予報 → 発生 → 終了 ==")
	_quiet()
	d.trigger("sandstorm", true)
	check(d.forecast.size() == 1 and d.active.is_empty(), "予報の間は、まだ天候の効果は出ない")
	check(d.focus_weather().get("active", true) == false and d.speed_mult() == 1.0, "予報は画面に出る（効果なし）")
	d.forecast[0]["left"] = 0.05
	d.tick(0.1, 0.0)
	check(d.forecast.is_empty() and d.active.size() == 1, "予報の時間が来ると天候が発生する")
	d.active[0]["left"] = 0.05
	d.tick(0.1, 0.0)
	check(d.active.is_empty() and is_equal_approx(d.speed_mult(), 1.0), "時間が来ると天候が終わり、倍率が元に戻る")
	check(d.log.size() >= 3, "予報・発生・終了が記録に残る (%d件)" % d.log.size())

	print("== トラブルと好機 ==")
	_quiet()
	var before: float = main.base.parts[GameData.Part.HULL] + main.base.parts[GameData.Part.DRIVE] + main.base.parts[GameData.Part.MACHINE]
	d.trigger("breakdown")
	var after: float = main.base.parts[GameData.Part.HULL] + main.base.parts[GameData.Part.DRIVE] + main.base.parts[GameData.Part.MACHINE]
	check(after < before - 20.0, "故障で部位が傷む (%.0f -> %.0f)" % [before, after])
	var c0: int = main.creatures_root.get_child_count()
	d.trigger("herd")
	check(main.creatures_root.get_child_count() >= c0 + 5, "生物の群れが現れる (+%d)" % (main.creatures_root.get_child_count() - c0))
	var r0: int = main.resources_root.get_child_count()
	d.trigger("salvage")
	check(main.resources_root.get_child_count() >= r0 + 4, "漂流物の資源が散らばる (+%d)" % (main.resources_root.get_child_count() - r0))

	print("== 選び方 ==")
	_quiet()
	d.trigger("sandstorm", false)
	var weather_picked := false
	for i in 300:
		var id := d._pick()
		if EventDB.def(id).get("kind", "") == "weather":
			weather_picked = true
	check(not weather_picked, "天候が発生中は、次の天候は選ばれない（同時に1つだけ）")
	_quiet()
	var kinds := {}
	for i in 600:
		kinds[EventDB.def(d._pick()).get("kind", "")] = true
	check(kinds.has("weather") and kinds.has("trouble") and kinds.has("chance"), "天候・トラブル・好機の全てが選ばれる")
	_quiet()
	d.enabled = true
	d._next_in = 0.01
	d.tick(0.1, 0.0)
	check(d.forecast.size() + d.active.size() + d.log.size() > 0, "時間が来ると、自動で次の出来事が起きる")

	print("== 襲撃（バトル） ==")
	_quiet()
	var early := false
	for i in 500:
		if EventDB.def(d._pick()).get("kind", "") == "attack":
			early = true
	check(not early, "序盤（走行距離が短い間）には襲撃が起きない")
	main.base.parts[H] = 100.0
	d.trigger("raid_scorpion", false)
	var spawned: int = d.active[0]["spawned"]
	check(spawned >= 1 and main.enemies_root.get_child_count() == spawned, "襲撃で敵が %d体 現れる" % spawned)   # 敵の数は EventDB の count（1〜2体）でランダム
	check(d.active[0]["stance"] == "fight" and is_equal_approx(d.speed_mult(), 0.5) and is_equal_approx(d.hull_dmg_mult(), 1.0),
			"初期の対処は「迎え撃つ」（速度×0.5・被害はそのまま）")
	var wk = main.workers[0]
	var work_before: float = wk.field_mult(GameData.Field.GATHERER)
	d.set_stance("raid_scorpion", "guard")
	check(d.speed_mult() == 0.0 and is_equal_approx(d.hull_dmg_mult(), 0.4) and is_equal_approx(d.work_mult(), 0.7),
			"防備を固める: 停止・車体の被害×0.4・作業×0.7")
	check(is_equal_approx(wk.field_mult(GameData.Field.GATHERER), work_before * 0.7), "防備を固めると仲間の作業が実際に遅くなる")
	d.set_stance("raid_scorpion", "flee")
	check(is_equal_approx(d.speed_mult(), 1.6) and is_equal_approx(d.burn_mult(), 1.8) and is_equal_approx(d.wear_mult(D), 1.8),
			"振り切る: 速度×1.6・燃料×1.8・走行装置の傷み×1.8")
	# 敵の攻撃は車体に当たる
	d.set_stance("raid_scorpion", "fight")
	var en0 = main.enemies_root.get_child(0)
	en0.position.x = en0.hold_x - 1.0             # 境界ぴったりだと、位置の小数の丸めで攻撃に入らないことがある
	main.base.parts[H] = 100.0
	en0._atk_timer = 0.0
	en0._process(0.01)
	check(is_equal_approx(main.base.parts[H], 100.0 - en0.damage), "敵が攻撃すると車体が傷む（-%.0f）" % en0.damage)
	d.set_stance("raid_scorpion", "guard")
	main.base.parts[H] = 100.0
	en0.position.x = en0.hold_x - 1.0
	en0._atk_timer = 0.0
	en0._process(0.01)
	check(is_equal_approx(main.base.parts[H], 100.0 - en0.damage * 0.4), "防備を固めていると被害は 0.4 倍")
	# 戦闘担当が戦う
	d.set_stance("raid_scorpion", "fight")
	main.base.parts[H] = 100.0
	var fighter = main.workers[1]                  # 戦闘の優先度が高い仲間
	fighter.priorities[GameData.Job.COMBAT] = 5
	fighter.energy = 100.0
	var res0: int = main.resources_root.get_child_count()
	var killed0: int = main.kills
	var ticks := 0
	while ticks < 1500:
		ticks += 1
		for e in main.enemies_root.get_children():
			if not e.dead:
				e._process(0.1)
		for wkr in main.workers:
			wkr._process(0.1)
		var alive := 0
		for e in main.enemies_root.get_children():
			if not e.dead:
				alive += 1
		if alive == 0:
			break
	check(main.kills > killed0, "戦闘担当が敵を倒した（%d体・%.0f秒）" % [main.kills - killed0, ticks * 0.1])
	check(main.base.parts[H] < 100.0, "戦っている間に車体も傷んだ (%.0f)" % main.base.parts[H])
	await process_frame
	check(main.resources_root.get_child_count() > res0, "倒した敵が戦利品を落とす（資源 +%d）" % (main.resources_root.get_child_count() - res0))
	d.tick(0.1, 0.0)
	check(d.active.is_empty() and d.stats["repelled"] >= 1, "全て倒すと襲撃を撃退した扱いになる")
	# 振り切る
	_quiet()
	d.trigger("raid_scorpion", false)
	d.set_stance("raid_scorpion", "flee")
	for i in 12:
		d.tick(1.0, 0.0)
	check(d.active.is_empty() and d.stats["escaped"] >= 1, "「振り切る」を選び続けると、%d秒ほどで襲撃を振り切れる" % int(EventDB.FLEE_SECONDS))
	await process_frame
	check(d._alive_enemies().is_empty(), "振り切ったあと、敵はいなくなる")
	# 時間切れで去る
	_quiet()
	d.trigger("raid_scorpion", false)
	d.active[0]["left"] = 0.05
	d.tick(0.1, 0.0)
	await process_frame
	check(d.active.is_empty() and d._alive_enemies().is_empty(), "時間が来ると、残った敵は去っていく")
	# 天候と襲撃は同時に選べる
	_quiet()
	d.trigger("sandstorm", false)
	d.trigger("raid_scorpion", false)
	var fl := d.focus_list()
	check(fl.size() == 2 and EventDB.def(fl[0]["id"])["kind"] == "attack", "天候と襲撃が同時に来ると、両方の対処方針が画面に出る（襲撃が先）")
	check(is_equal_approx(d.speed_mult(), 0.5 * 0.5), "倍率は重なる（砂嵐の減速×襲撃の迎撃）")
	for e in d._alive_enemies():
		e.queue_free()
	_quiet()

	print("== 実際に進める（ゲーム内約8分。出来事がランダムに起きる） ==")
	_quiet()
	d.enabled = true
	d._next_in = 5.0
	# 確認しやすいよう、間隔だけ短くして進める
	var base_gap_min := EventDB.GAP_MIN
	Engine.time_scale = 8.0
	var products0 := 0
	for it in GameData.PRODUCT_ITEMS:
		products0 += main.storage.count_of(it)
	var t_end := Time.get_ticks_msec() + 60000
	var seen := {}
	while Time.get_ticks_msec() < t_end:
		await create_timer(1.0).timeout
		for a in d.active:
			seen[a["id"]] = true
		for i in [0]:
			if d._next_in > 25.0:
				d._next_in = 12.0            # 出来事が起きる頻度を上げて、たくさん確かめる
	Engine.time_scale = 1.0
	var total: int = d.stats["weather"] + d.stats["trouble"] + d.stats["chance"]
	check(total >= 4, "8分ほどで出来事が %d 回起きた（天候%d・トラブル%d・好機%d）" % [total, d.stats["weather"], d.stats["trouble"], d.stats["chance"]])
	check(main.base.parts[H] >= 0.0 and main.base.fuel >= 0.0 and main.scroll_speed >= 0.0, "進めたあとも値が壊れていない")
	print("       走行 %.1f km / 車体 %d 走行装置 %d 加工設備 %d 燃料 %d 食料 %d 記録: %s" % [
			d.distance / 2500.0, int(main.base.parts[H]), int(main.base.parts[D]), int(main.base.parts[M]),
			int(main.base.fuel), main.storage.count_of(GameData.Item.FOOD), str(d.log.size())])
	for e in d.log:
		print("         ・", e["text"])

	print("== 車体が壊れきると終わり ==")
	_quiet()
	main.game_over = false
	main.base.parts[H] = 0.0
	main._process(0.016)
	check(main.game_over, "車体の耐久度が0になると、ゲームオーバーになる")
	paused = false
