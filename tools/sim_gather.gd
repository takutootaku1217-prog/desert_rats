extends SceneTree
## 採取ポイント＋道具が、放置プレイの結果にどう効くかを、従来の「落ちている物を拾う」方式と比べる（バランス確認用）。実行:
##   Godot --headless --path . -s res://tools/sim_gather.gd -- <ゲーム内の分> <回数> <倍速>
## 各回で「従来（落ちている物）」と「採取ポイント＋道具」を、同じ乱数の種で比べる。方針・仲間の設定は初期のまま（=放置）。
## 出力: 倉庫の中身・素材ごとに採れた量・空腹/燃料切れの時間・仲間の待機・回収/狩猟/加工の回数・道具の持ち方。

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var minutes: float = float(a[0]) if a.size() > 0 else 15.0
	var runs: int = int(a[1]) if a.size() > 1 else 2
	var scale: float = float(a[2]) if a.size() > 2 else 12.0
	var seed_base: int = int(a[3]) if a.size() > 3 else 3000
	for r in runs:
		for points in [false, true]:
			await _one(r + 1, points, minutes, scale, seed_base)
	GameData.ENABLE_GATHER_POINTS = true
	quit()


func _one(n: int, points: bool, minutes: float, scale: float, seed_base: int) -> void:
	seed(seed_base + n)
	GameData.ENABLE_GATHER_POINTS = points
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var d: Director = main.director
	var st: BaseStorage = main.storage
	var got := {}                            # Item -> 回収して倉庫に入った量（環境から）
	st.inventory.item_added.connect(func(item, amount, source):
		if source == Inventory.SOURCE_ENVIRONMENT:
			got[item] = got.get(item, 0) + amount)
	var hull_low := 100.0
	var hungry_t := 0.0
	var nofuel_t := 0.0
	var idle_t := 0.0
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
			if not w.away and w.ai.state == CharacterAI.State.IDLE:
				idle_t += dt
	Engine.time_scale = 1.0
	var over: bool = main.game_over
	paused = false
	print("--- 第%d回 %s ゲーム内 %.0f 分%s ---" % [n, "採取ポイント＋道具" if points else "従来（落ちている物）", d.elapsed / 60.0, "  ★ゲームオーバー" if over else ""])
	var parts: Array = []
	for it in GameData.RAW_ITEMS + GameData.PRODUCT_ITEMS:
		parts.append("%s%d" % [GameData.ITEM_NAMES[it], st.count_of(it)])
	print("  倉庫: %s" % " ".join(PackedStringArray(parts)))
	print("  採れた量: 木材%d 石%d 鉄鉱石%d（肉%d 皮%d）  捨てた %d個" % [got.get(GameData.Item.WOOD, 0), got.get(GameData.Item.STONE, 0),
			got.get(GameData.Item.IRON_ORE, 0), got.get(GameData.Item.MEAT, 0), got.get(GameData.Item.HIDE, 0), main.total_wasted])
	print("  空腹 %d秒 / 燃料切れ %d秒 / 仲間の待機 %d%% / 車体の最低 %d" % [int(hungry_t), int(nofuel_t),
			int(100.0 * idle_t / maxf(1.0, d.elapsed * main.workers.size())), int(hull_low)])
	print("  回収%d 狩猟%d 加工%d 補給%d 修理%d 食事%d" % [main.total_gathered, main.total_hunted, main.processor.total_done,
			main.base.total_refuel, main.base.total_repair, main.total_eaten])
	if points:
		var tl := ""
		for w in main.workers:
			tl += "%s[採掘:%s 伐採:%s] " % [w.char_name, GatherDB.tool_def(int(w.tools.get("mine", -1)))["name"], GatherDB.tool_def(int(w.tools.get("chop", -1)))["name"]]
		var spare := ""
		for it in GameData.TOOL_ITEMS:
			if st.count_of(it) > 0:
				spare += "%s×%d " % [GameData.ITEM_NAMES[it], st.count_of(it)]
		print("  道具: %s／倉庫の予備: %s" % [tl, spare if spare != "" else "なし"])
	main.queue_free()
	await process_frame
