extends SceneTree
## 仲間のステータス（HP・スタミナ・満腹度・疲労度・精神状態）を入れる前後で、放置プレイのテンポが変わっていないかを比べる測定。実行:
##   Godot --headless --path . -s res://tools/sim_crew.gd -- <分> <回数> <倍速> <出来事0/1> [設備が最初からある 0/1] [建設を自動で依頼 0/1]
## 例: 15 3 12 0 0 1  （出来事なし・設備なしで始めて、建てられるようになった設備をすぐ依頼する熱心なプレイヤー。15分×3回・12倍速）
## 出力: 回ごとの 回収・加工・狩猟・食事・仲間の状態の時間の割合・スタミナ／満腹度／疲労度の様子。新旧のどちらのコードでも動く
## （新しい項目は、なければ出さない）。

var main
var minutes := 15.0
var runs := 3
var scale := 12.0
var events := false
var start_all := false
var auto_build := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		minutes = float(a[0])
	if a.size() > 1:
		runs = int(a[1])
	if a.size() > 2:
		scale = float(a[2])
	if a.size() > 3:
		events = a[3] == "1"
	if a.size() > 4:
		start_all = a[4] == "1"
	if a.size() > 5:
		auto_build = a[5] == "1"
	await _run()
	quit()


func _run() -> void:
	var sums := {}
	for n in runs:
		seed(20260930 + n)
		if main != null:
			root.remove_child(main)
			main.free()
		FacilityDB.start_all = start_all
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		main.director.enabled = events
		Engine.time_scale = scale
		var t0: float = main.director.elapsed
		var rest_t := 0.0
		var work_t := 0.0
		var hungry_t := 0.0
		var stamina_sum := 0.0
		var stamina_min := 100.0
		var samples := 0
		var last: float = t0
		var fat_sum := 0.0
		var hun_sum := 0.0
		var hun_min := 100.0
		var fat_max := 0.0
		var wb_at := -1.0
		var hp_min := 100.0
		var down_t := 0.0
		var downs := 0
		var was_down := {}
		var mental_t := [0.0, 0.0, 0.0, 0.0, 0.0]
		var prev_hunger := {}
		var meals: Array = []                          # 食事の記録（時刻・仲間・食べる前後の満腹度・そのときの食料の在庫）
		while main.director.elapsed - t0 < minutes * 60.0 and not main.game_over:
			await process_frame
			var now: float = main.director.elapsed
			var dt := now - last
			last = now
			if wb_at < 0.0 and main.has_facility("workbench"):
				wb_at = now - t0
			if auto_build:
				for id in FacilityDB.ids():
					if main.build_blocked_reason(id) == "":
						main.request_build(id)
			if main.hungry:
				hungry_t += dt
			for w in main.workers:
				var st: int = w.ai.state
				if st == CharacterAI.State.REST or st == CharacterAI.State.REST_MOVE:
					rest_t += dt
				elif st != CharacterAI.State.IDLE and st != CharacterAI.State.SEARCH:
					work_t += dt
				stamina_sum += w.stamina
				stamina_min = minf(stamina_min, w.stamina)
				var f = w.get("fatigue")
				if f != null:
					fat_sum += f
					fat_max = maxf(fat_max, f)
				var hp = w.get("hp")
				if hp != null:
					hp_min = minf(hp_min, hp)
					if w.down:
						down_t += dt
						if not was_down.get(w, false):
							downs += 1
					was_down[w] = w.down
					mental_t[w.mental] += dt
				if prev_hunger.has(w) and w.hunger > prev_hunger[w] + 5.0:
					meals.append("%d分%02d秒 %s 満腹度 %.0f → %.0f（食料の在庫 %d）" % [int((now - t0) / 60.0), int(now - t0) % 60, w.char_name, prev_hunger[w], w.hunger, main.storage.count_of(GameData.Item.FOOD)])
				prev_hunger[w] = w.hunger
				var h = w.get("hunger")
				if h != null:
					hun_sum += h
					hun_min = minf(hun_min, h)
				samples += 1
		Engine.time_scale = 1.0
		var res := {
			"gathered": main.total_gathered, "done": main.processor.total_done, "hunted": main.total_hunted, "eaten": main.total_eaten,
			"built": main.total_built, "hungry_s": hungry_t, "rest_pct": 100.0 * rest_t / (3.0 * minutes * 60.0),
			"work_pct": 100.0 * work_t / (3.0 * minutes * 60.0), "stamina_avg": stamina_sum / float(maxi(1, samples)), "stamina_min": stamina_min,
			"food": main.storage.count_of(GameData.Item.FOOD), "hull": main.base.parts[GameData.Part.HULL],
		}
		var line := "[回%d] 回収 %d ・加工 %d ・狩猟 %d ・食事 %d ・建設 %d ・ワークベンチ %s ・空腹の時間 %ds ・休憩 %.0f%% ・作業 %.0f%% ・スタミナ 平均 %.0f 最低 %.0f ・食料 %d ・車体 %.0f%s" % [
				n + 1, res["gathered"], res["done"], res["hunted"], res["eaten"], res["built"], ("%.0f秒" % wb_at) if wb_at >= 0.0 else "なし",
				int(res["hungry_s"]), res["rest_pct"], res["work_pct"], res["stamina_avg"], res["stamina_min"], res["food"], res["hull"],
				"  ゲームオーバー" if main.game_over else ""]
		if samples > 0 and fat_sum > 0.0:
			line += " ・疲労度 平均 %.0f 最大 %.0f ・満腹度 平均 %.0f 最低 %.0f" % [fat_sum / float(samples), fat_max, hun_sum / float(samples), hun_min]
			var mt: float = mental_t[0] + mental_t[1] + mental_t[2] + mental_t[3] + mental_t[4]
			if mt > 0.0:
				line += " ・HP 最低 %.0f 倒れた %d回（計%ds） ・精神状態 好調%.0f%% 普通%.0f%% 不安%.0f%% 不調%.0f%% 限界%.0f%%" % [hp_min, downs, int(down_t),
						100.0 * mental_t[0] / mt, 100.0 * mental_t[1] / mt, 100.0 * mental_t[2] / mt, 100.0 * mental_t[3] / mt, 100.0 * mental_t[4] / mt]
		print(line)
		if not meals.is_empty():
			print("     食事の記録: " + " ／ ".join(PackedStringArray(meals)))
		for k in res:
			sums[k] = float(sums.get(k, 0.0)) + float(res[k])
	var out := "平均:"
	for k in ["gathered", "done", "hunted", "eaten", "built", "hungry_s", "rest_pct", "work_pct", "stamina_avg"]:
		out += " %s=%.1f" % [k, float(sums[k]) / float(runs)]
	print(out)
