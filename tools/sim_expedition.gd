extends SceneTree
## 遠征に出たほうが得かを、放置プレイの長時間シミュレーションで比べる（バランス確認用）。実行:
##   Godot --headless --path . -s res://tools/sim_expedition.gd -- <ゲーム内の分> <回数> <倍速>
## 各回で「遠征なし」と「遺跡が見つかるたびに2人を標準の進め方で派遣（食料が2個以上あるとき）」を比べる。
## 出力: 最後の倉庫の在庫の合計・空腹だった時間・車体の最低値・遠征の回数と戦利品。

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var minutes: float = float(a[0]) if a.size() > 0 else 15.0
	var runs: int = int(a[1]) if a.size() > 1 else 2
	var scale: float = float(a[2]) if a.size() > 2 else 12.0
	for r in runs:
		for dispatch in [false, true]:
			await _one(r + 1, dispatch, minutes, scale)
	quit()


func _one(n: int, dispatch: bool, minutes: float, scale: float) -> void:
	seed(1000 + n)                       # 同じ回では、同じ出来事の並びになりやすいように
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var d: Director = main.director
	var ex: Expedition = main.expedition
	var hull_low := 100.0
	var hungry_t := 0.0
	var last := Time.get_ticks_msec()
	Engine.time_scale = scale
	while d.elapsed < minutes * 60.0 and not main.game_over:
		await process_frame
		var now := Time.get_ticks_msec()
		var dt := float(now - last) / 1000.0 * scale
		last = now
		hull_low = minf(hull_low, main.base.parts[GameData.Part.HULL])
		if main.hungry:
			hungry_t += dt
		if dispatch and ex.state == "offered" and main.storage.count_of(GameData.Item.FOOD) >= 2:
			var party: Array = []
			for w in main.workers:
				if not w.away and party.size() < 2:
					party.append(w)
			ex.start(party, "normal", false)
	Engine.time_scale = 1.0
	var over: bool = main.game_over
	paused = false
	var st = main.storage
	var total := 0
	for it in GameData.RAW_ITEMS + GameData.PRODUCT_ITEMS:
		total += st.count_of(it)
	print("--- 第%d回 %s ゲーム内 %.0f 分%s ---" % [n, "遠征あり" if dispatch else "遠征なし", d.elapsed / 60.0, "  ★ゲームオーバー" if over else ""])
	print("  在庫の合計 %d（食料%d 燃料%d 修理資材%d 鉄%d）  空腹 %d秒  車体の最低 %d" % [total, st.count_of(GameData.Item.FOOD),
			st.count_of(GameData.Item.FUEL), st.count_of(GameData.Item.REPAIR_KIT), st.count_of(GameData.Item.IRON), int(hungry_t), int(hull_low)])
	print("  出来事: 遺跡%d 襲撃%d 撃退%d   遠征: %d回 成功関門%d 失敗%d 設計図%d 撤退%d" % [d.stats.get("site", 0), d.stats["attack"], d.stats["repelled"],
			ex.stats["trips"], ex.stats["steps_ok"], ex.stats["steps_ng"], ex.stats["blueprints"], ex.stats["retreats"]])
	main.queue_free()
	await process_frame
