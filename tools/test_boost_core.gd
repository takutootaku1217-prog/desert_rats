extends "res://tools/test_save_game.gd"

func _initialize():
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await main.ready
	paused = true
	# Use the legacy street fixture only to isolate movement; the normal map begins parked.
	main.world.active = false
	main.quarry.state = "road"
	main.target_speed = 60.0
	main.base.fuel = GameData.FUEL_CAP
	check(main.select_boost_core(BoostCores.SUSTAINED), "持続型を選択")
	check(main.request_boost_toggle() and main.boost_active, "明示操作でブーストを開始")
	main._process(1.0)
	check(is_equal_approx(main.scroll_speed, 90.0), "両コア共通の速度1.5倍")
	check(is_equal_approx(main.boost_load, 12.5), "持続型は8秒で負荷満杯")
	main._process(7.0)
	check(not main.boost_active and is_equal_approx(main.boost_load, 100.0), "負荷満杯で自動解除")
	check(not main.request_boost_toggle(), "満杯では再点火しない")
	main._process(12.0)
	check(is_equal_approx(main.boost_load, 50.0), "持続型は24秒で負荷全解消")
	check(main.request_boost_toggle(), "回復後は明示操作で再開")
	check(not main.select_boost_core(BoostCores.BURST), "稼働中の交換を拒否")
	main.request_boost_toggle()
	var before_switch: float = main.boost_load
	check(main.select_boost_core(BoostCores.BURST) and is_equal_approx(main.boost_load, before_switch), "交換しても負荷を無料回復しない")
	main.boost_load = 0.0
	check(main.request_boost_toggle(), "短時間型を開始")
	main._process(2.0)
	check(not main.boost_active and is_equal_approx(main.boost_load, 100.0), "短時間型は2秒で負荷満杯")
	main._process(6.0)
	check(is_zero_approx(main.boost_load), "短時間型は6秒で負荷全解消")
	main.world.active = true
	main.world.phase = "stopped"
	check(not main.request_boost_toggle(), "停車中は開始不可")
	main.world.phase = "travel"
	main.base.fuel = 0.0
	check(not main.request_boost_toggle(), "燃料切れでは開始不可")
	main.base.fuel = GameData.FUEL_CAP
	main.world.progress = WorldMapDB.LENGTH - 1.0
	main.world.direction = 1
	check(main.request_boost_toggle(), "走行中は開始可能")
	check(is_equal_approx(main.world.speed_limit(90.0, 1.0), 1.0), "到着境界を越えない")
	main.boost_active = false
	main.world.active = false
	main.world.phase = "stopped"
	main.world.road = ""
	main.world.origin = ""
	main.world.destination = ""
	main.world.progress = 0.0
	main.boost_load = 37.5
	var saved := SaveGame.capture(main)
	check(SaveGame.validate(saved, main), "ブースト負荷を含む保存形式を検証")
	main.boost_load = 0.0
	main.boost_core_id = BoostCores.SUSTAINED
	check(SaveGame.apply(main, saved), "ブースト負荷を復元")
	check(main.boost_core_id == BoostCores.BURST and is_equal_approx(main.boost_load, 37.5) and not main.boost_active, "コアと負荷が保存復元で一致")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
