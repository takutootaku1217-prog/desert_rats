extends SceneTree
## 出来事を本来の頻度で起こしたときの、放置プレイの結果を調べる（バランス確認用）。実行:
##   Godot --headless --path . -s res://tools/sim_events.gd -- <ゲーム内の分> <回数> <倍速>
## 例: -- 12 2 12   … ゲーム内12分を、12倍速で2回。仲間の設定は初期のまま、対処方針も触らない（=放置）。
## 出力: 各回の 最低の耐久度・空腹だった時間・燃料切れの時間・出来事の回数・最後の状態。

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var minutes: float = float(a[0]) if a.size() > 0 else 12.0
	var runs: int = int(a[1]) if a.size() > 1 else 2
	var scale: float = float(a[2]) if a.size() > 2 else 12.0
	for r in runs:
		await _one(r + 1, minutes, scale)
	quit()


func _one(n: int, minutes: float, scale: float) -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var d: Director = main.director
	var H := GameData.Part.HULL
	var D := GameData.Part.DRIVE
	var M := GameData.Part.MACHINE
	var low := {H: 100.0, D: 100.0, M: 100.0}
	var hungry_t := 0.0
	var nofuel_t := 0.0
	var halted_t := 0.0
	var last := Time.get_ticks_msec()
	Engine.time_scale = scale
	var end_at := minutes * 60.0
	while d.elapsed < end_at and not main.game_over:
		await process_frame
		var now := Time.get_ticks_msec()
		var dt := float(now - last) / 1000.0 * scale
		last = now
		for p in low:
			low[p] = minf(low[p], main.base.parts[p])
		if main.hungry:
			hungry_t += dt
		if not main.base.has_fuel():
			nofuel_t += dt
		if main.scroll_speed <= 0.5:
			halted_t += dt
	Engine.time_scale = 1.0
	var over: bool = main.game_over
	paused = false
	print("--- 第%d回 ゲーム内 %.0f 分 ---" % [n, d.elapsed / 60.0])
	print("  出来事: 天候%d 襲撃%d(撃退%d 振り切り%d 撃破%d) トラブル%d 好機%d  走行 %.1f km%s" % [d.stats["weather"], d.stats["attack"], d.stats["repelled"], d.stats["escaped"], d.stats["kills"], d.stats["trouble"], d.stats["chance"], d.distance / 2500.0, "   ★ゲームオーバー（車体が壊れきった）" if over else ""])
	print("  最低の耐久度: 車体%d 走行装置%d 加工設備%d   最後: 車体%d 走行装置%d 加工設備%d" % [
			int(low[H]), int(low[D]), int(low[M]), int(main.base.parts[H]), int(main.base.parts[D]), int(main.base.parts[M])])
	print("  空腹だった時間 %d秒 / 燃料切れ %d秒 / ほぼ停止 %d秒   最後: 燃料%d 食料%d 修理資材%d" % [
			int(hungry_t), int(nofuel_t), int(halted_t), int(main.base.fuel), main.storage.count_of(GameData.Item.FOOD),
			main.storage.count_of(GameData.Item.REPAIR_KIT)])
	for e in d.log:
		print("    ・", e["text"])
	main.queue_free()
	await process_frame
