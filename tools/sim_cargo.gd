extends SceneTree
## 積載量（倉庫の容量）が、放置プレイの結果にどう効くかを比べる（バランス確認用）。実行:
##   Godot --headless --path . -s res://tools/sim_cargo.gd -- <ゲーム内の分> <回数> <倍速>
## 各回で「制限なし（enforce=false）」と「制限あり」を、同じ乱数の種で比べる。方針・仲間の設定は初期のまま（=放置）。
## 出力: 倉庫の中身・捨てた数・空腹・燃料切れの時間・仲間の待機時間・回収/狩猟/加工の回数・車体の最低値。

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var minutes: float = float(a[0]) if a.size() > 0 else 15.0
	var runs: int = int(a[1]) if a.size() > 1 else 2
	var scale: float = float(a[2]) if a.size() > 2 else 12.0
	for r in runs:
		for limited in [false, true]:
			await _one(r + 1, limited, minutes, scale)
	quit()


func _one(n: int, limited: bool, minutes: float, scale: float) -> void:
	seed(2000 + n)
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var d: Director = main.director
	var st: BaseStorage = main.storage
	st.enforce = limited
	var hull_low := 100.0
	var hungry_t := 0.0
	var nofuel_t := 0.0
	var idle_t := 0.0                       # 仲間が「待機中」だった延べ時間（人×秒）
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
		if not main.base.has_fuel():
			nofuel_t += dt
		for w in main.workers:
			if w.ai.state == CharacterAI.State.IDLE:
				idle_t += dt
	Engine.time_scale = 1.0
	var over: bool = main.game_over
	paused = false
	print("--- 第%d回 %s ゲーム内 %.0f 分%s ---" % [n, "制限あり" if limited else "制限なし", d.elapsed / 60.0, "  ★ゲームオーバー" if over else ""])
	var parts: Array = []
	for it in GameData.RAW_ITEMS + GameData.PRODUCT_ITEMS:
		parts.append("%s%d" % [GameData.ITEM_NAMES[it], st.count_of(it)])
	print("  倉庫: %s" % " ".join(PackedStringArray(parts)))
	print("  素材棚 %d/%d  加工品 %d/%d  捨てた %d個" % [st.used_in(CargoDB.Bay.RAW), st.capacity_of(CargoDB.Bay.RAW),
			st.used_in(CargoDB.Bay.PRODUCT), st.capacity_of(CargoDB.Bay.PRODUCT), main.total_wasted])
	var w_parts: Array = []
	for it in st.wasted:
		w_parts.append("%s%d" % [GameData.ITEM_NAMES[it], st.wasted[it]])
	if not w_parts.is_empty():
		print("  捨てた内訳: %s" % " ".join(PackedStringArray(w_parts)))
	print("  空腹 %d秒 / 燃料切れ %d秒 / 仲間の待機 %d人秒（%d%%）/ 車体の最低 %d" % [int(hungry_t), int(nofuel_t), int(idle_t),
			int(100.0 * idle_t / maxf(1.0, d.elapsed * main.workers.size())), int(hull_low)])
	print("  回収%d 狩猟%d 加工%d 補給%d 修理%d 食事%d" % [main.total_gathered, main.total_hunted, main.processor.total_done,
			main.base.total_refuel, main.base.total_repair, main.total_eaten])
	main.queue_free()
	await process_frame
