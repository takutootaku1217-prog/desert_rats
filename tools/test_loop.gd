extends SceneTree
## 基本ループの確認と、異常（詰まり・予約の取り残し・アイテムの消失など）の監視。実行:
##   Godot --headless --path . -s res://tools/test_loop.gd -- <ゲーム内の分> <回数> <倍速> <乱数の種> <出来事 0/1> [シナリオ]
## 例: -- 10 2 12 500 0   … 出来事なしで10分を2回（基本ループだけを見る）／ -- 15 3 12 700 1 … 出来事あり
## シナリオ（省略すると normal）: stop（90秒で拠点を止める）／ fast（速度200）／ slow（速度10）／ rawfull（素材棚が満杯から始める）／
##   prodfull（加工品置き場が満杯から始める）／ priostress（仲間の優先度と加工の方針を数秒ごとに乱数で変える）
## 確認する流れ: 拠点が移動 → 資源が発生 → 仲間が発見 → 回収 → 運搬 → 素材棚に収納 → 加工設備へ送られる → 加工される → 加工品置き場に収納。
## 監視する異常: 同じ状態で動かない・発見と取り消しの繰り返し・運んでいる物が消える・予約したまま動かない・
##   加工が始まらない/終わらない/取り出されない・倉庫の個数がおかしい・元気が0のまま。

## 状態ごとの「これ以上続いたらおかしい」秒数（ゲーム内の秒）
const LIMITS := {
	CharacterAI.State.NOTICE: 4.0, CharacterAI.State.MOVE_TO_RESOURCE: 40.0, CharacterAI.State.GATHER: 45.0,
	CharacterAI.State.MOVE_TO_STORAGE: 40.0, CharacterAI.State.STORE: 4.0, CharacterAI.State.HAUL_TAKE: 40.0,
	CharacterAI.State.HAUL_MOVE: 40.0, CharacterAI.State.MOVE_TO_MACHINE: 40.0, CharacterAI.State.PROCESS: 300.0,
	CharacterAI.State.REPAIR_TAKE: 40.0, CharacterAI.State.REPAIR_MOVE: 40.0, CharacterAI.State.REPAIR: 6.0,
	CharacterAI.State.REST_MOVE: 40.0, CharacterAI.State.REST: 90.0, CharacterAI.State.REFUEL_TAKE: 40.0,
	CharacterAI.State.REFUEL_MOVE: 40.0, CharacterAI.State.REFUEL: 6.0, CharacterAI.State.HUNT_MOVE: 60.0,
	CharacterAI.State.HUNT_ATTACK: 60.0, CharacterAI.State.COMBAT_MOVE: 60.0, CharacterAI.State.COMBAT: 120.0,
	CharacterAI.State.IDLE: 3.0, CharacterAI.State.SEARCH: 3.0,
}
## 荷物を持っている状態から手ぶらになってよい、直前の状態（それ以外で消えたら「荷物が消えた」）
const CARRY_END_OK := [CharacterAI.State.STORE, CharacterAI.State.HAUL_MOVE, CharacterAI.State.REFUEL, CharacterAI.State.REPAIR]

var fails := 0
var all_ok := true


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var minutes: float = float(a[0]) if a.size() > 0 else 10.0
	var runs: int = int(a[1]) if a.size() > 1 else 2
	var scale: float = float(a[2]) if a.size() > 2 else 12.0
	var seed_base: int = int(a[3]) if a.size() > 3 else 500
	var events_on: bool = (int(a[4]) != 0) if a.size() > 4 else false
	var scenario: String = a[5] if a.size() > 5 else "normal"
	for r in runs:
		await _one(r + 1, minutes, scale, seed_base, events_on, scenario)
	print("== 結果: %s ==" % ("問題なし" if all_ok else "問題あり（上の ★ を確認）"))
	quit(0 if all_ok else 1)


func _one(n: int, minutes: float, scale: float, seed_base: int, events_on: bool, scenario: String) -> void:
	seed(seed_base + n)
	FacilityDB.start_all = scenario != "build"      # 設備は最初から全部ある状態で確かめる（シナリオ build だけ、設備なしで始めて依頼していく）
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var d: Director = main.director
	d.enabled = events_on
	var st: BaseStorage = main.storage
	match scenario:
		"fast":
			main.target_speed = 200.0
		"slow":
			main.target_speed = 10.0
		"rawfull":
			for it in GameData.RAW_ITEMS:
				st.inventory.counts[it] = st.quota_of(it)
		"prodfull":
			for it in GameData.PRODUCT_ITEMS:
				st.inventory.counts[it] = st.quota_of(it)
	var next_stress := 5.0
	var W: Array = main.workers
	var P: BaseProcessor = main.processor
	var ms := {}                         # 確認する流れ -> 初めて起きた時刻
	var errors: Array = []               # 異常（★）
	var notes: Array = []                # 気づいたこと（参考）
	var seen_keys := {}
	var stored := {}                     # Item -> 環境（回収・狩猟）から倉庫に入った量
	var made := {}                       # Item -> 加工品として倉庫に入った量
	var lost_claim := 0
	var spawned := {"point": 0, "loose": 0}
	var since := {}                      # Worker -> 今の状態に入った時刻
	var last_state := {}
	var prev_state := {}
	var prev_carry := {}
	var notice_times := {}               # Worker -> 直近の NOTICE に入った時刻の一覧
	var gather_times := {}
	var state_secs := {}                 # Worker -> {状態: 秒}
	var wait := {}                       # 異常の種類 -> 続き始めた時刻
	var seen_res := {}
	var energy0 := {}
	var max_wait := {"orders": 0.0, "output": 0.0}
	var hungry_t := 0.0
	var last_t := d.elapsed
	var prog_last := -1.0                # 加工の進みが最後に変わった時の値・種類・時刻
	var prog_id := ""
	var prog_changed_at := d.elapsed

	var mark := func(key: String) -> void:
		if not ms.has(key):
			ms[key] = d.elapsed
	var err := func(key: String, text: String) -> void:
		if not seen_keys.has(key):
			seen_keys[key] = true
			errors.append("[%.0f秒] %s" % [d.elapsed, text])
	var note := func(key: String, text: String) -> void:
		if not seen_keys.has(key):
			seen_keys[key] = true
			notes.append("[%.0f秒] %s" % [d.elapsed, text])
	# 続いている間の時間を測る。条件が偽になったらリセットし、limit を超えたら true を返す
	var lasting := func(key: String, cond: bool, limit: float) -> bool:
		if not cond:
			wait.erase(key)
			return false
		if not wait.has(key):
			wait[key] = d.elapsed
		return d.elapsed - float(wait[key]) > limit

	st.inventory.item_added.connect(func(item, amount, source):
		if source == Inventory.SOURCE_ENVIRONMENT or source == Inventory.SOURCE_HUNT:
			if item in GameData.RAW_ITEMS:
				stored[item] = stored.get(item, 0) + amount
				mark.call("6 素材棚に収納")
			elif item in GameData.PRODUCT_ITEMS or item in GameData.TOOL_ITEMS:
				made[item] = made.get(item, 0) + amount
				mark.call("9 加工品置き場に収納"))
	for w in W:
		var ww = w
		ww.state_changed.connect(func():
			var s: int = ww.ai.state
			var t: float = d.elapsed
			if s == CharacterAI.State.NOTICE:
				notice_times[ww] = notice_times.get(ww, []) + [t]
			elif s == CharacterAI.State.GATHER:
				gather_times[ww] = gather_times.get(ww, []) + [t])

	Engine.time_scale = scale
	while d.elapsed < minutes * 60.0 and not main.game_over:
		await process_frame
		var t: float = d.elapsed
		var dt: float = t - last_t
		last_t = t
		if main.hungry:
			hungry_t += dt
		if scenario == "build":
			for bid in FacilityDB.ids():             # 熱心なプレイヤー: 建てられるようになった設備を、すぐ依頼する
				if main.build_blocked_reason(bid) == "":
					main.request_build(bid)
			if main.base.facility_count("workbench") > 0:
				mark.call("B1 ワークベンチ完成")
			if main.base.facility_count("bed") > 0:
				mark.call("B2 最初のベッド完成")
			if main.base.facility_count("bed") >= 3:
				mark.call("B3 ベッド3つ完成")
			if lasting.call("buildq", not main.build_queue.is_empty(), 240.0):
				note.call("buildq", "建設の依頼が 4 分以上、待ったまま（材料が集まらない？）")
		if scenario == "stop" and t >= 90.0:
			main.target_speed = 0.0                  # 最初の90秒は普通に走り、そのあと拠点を止める（止まっても加工・運搬が回るか）
		if scenario == "priostress" and t >= next_stress:
			# 優先度と方針を乱数で変え続ける（途中で仕事を切り替えても、予約や荷物が取り残されないか）
			next_stress = t + 4.0
			var sw = W[randi() % W.size()]
			if not sw.away:
				var jobs: Array = GameData.job_list()
				sw.set_priority(jobs[randi() % jobs.size()], randi() % (GameData.MAX_PRIORITY + 1))
			if randi() % 2 == 0:
				var rid: String = GameData.RECIPES[randi() % GameData.RECIPES.size()]["id"]
				main.recipe_priority[rid] = randi() % (GameData.MAX_PRIORITY + 1)
			else:
				main.gather_policy[GameData.GROUND_ITEMS[randi() % GameData.GROUND_ITEMS.size()]] = randi() % (GameData.MAX_PRIORITY + 1)

		# ---- 確認する流れ ----
		if d.distance > 200.0 and main.scroll_speed > 0.0:
			mark.call("1 拠点が移動")
		for r in main.resources_root.get_children():
			if not seen_res.has(r.get_instance_id()):
				seen_res.set(r.get_instance_id(), true)
				spawned["point" if r is GatherPoint else "loose"] += 1
				mark.call("2 資源が発生")
				var rr = r
				r.tree_exiting.connect(func():
					# 仲間が向かっている最中に消えた（画面の外へ流れた・別の理由）
					for w2 in W:
						if is_instance_valid(w2) and w2.ai.res == rr and not w2.away and w2.ai.state != CharacterAI.State.SEARCH:
							lost_claim += 1)
		if not P.orders.is_empty() or not P.current.is_empty():
			mark.call("7 加工設備へ送られる")
		if P.total_done > 0:
			mark.call("8 加工される")

		# ---- 仲間ごと ----
		for w in W:
			if w.away:
				prev_carry[w] = -1
				continue
			var s: int = w.ai.state
			if last_state.get(w, -1) != s:
				last_state[w] = s
				since[w] = t
			if s == CharacterAI.State.NOTICE:
				mark.call("3 資源を発見")
			if s == CharacterAI.State.GATHER and w.carrying >= 0:
				mark.call("4 資源を回収")
			if s == CharacterAI.State.MOVE_TO_STORAGE and w.carrying >= 0:
				mark.call("5 拠点へ運ぶ")
			var ss: Dictionary = state_secs.get(w, {})
			ss[s] = float(ss.get(s, 0.0)) + dt
			state_secs[w] = ss
			# 同じ状態が長すぎる（詰まり）
			var lim: float = LIMITS.get(s, 999.0)
			if t - float(since[w]) > lim:
				err.call("stuck_%s_%d" % [w.char_name, s], "%s が「%s」のまま %.0f 秒以上（位置 %d,%d）" % [w.char_name,
						CharacterAI.STATE_TEXT[s], lim, int(w.position.x), int(w.position.y)])
			# 発見と取り消しの繰り返し（30秒に8回以上、回収に入れない）
			var nt: Array = notice_times.get(w, [])
			nt = nt.filter(func(x): return t - x <= 30.0)
			notice_times[w] = nt
			var gt: Array = gather_times.get(w, [])
			gt = gt.filter(func(x): return t - x <= 30.0)
			gather_times[w] = gt
			if nt.size() >= 8 and gt.is_empty():
				err.call("flap_%s" % w.char_name, "%s が資源を見つけては取り消すのを繰り返している（30秒に%d回）" % [w.char_name, nt.size()])
			# 運んでいる物が消えた
			var pc: int = prev_carry.get(w, -1)
			if pc >= 0 and w.carrying < 0:
				var ps: int = prev_state.get(w, -1)
				if not (ps in CARRY_END_OK):
					err.call("carry_lost_%s_%d" % [w.char_name, ps], "%s の荷物（%s）が「%s」の途中で消えた" % [w.char_name,
							GameData.ITEM_NAMES.get(pc, "?"), CharacterAI.STATE_TEXT.get(ps, "?")])
			prev_carry[w] = w.carrying
			prev_state[w] = s
			# 元気が0のまま
			# （休憩の優先度を0にした仲間は休まないので、元気が0でも異常ではない）
			# （シナリオ build では、ベッドを建てるまでは休めないので、元気が0でも異常ではない）
			var can_rest: bool = scenario != "build" or main.base.facility_count("bed") > 0
			if lasting.call("energy0_" + w.char_name, w.energy <= 0.5 and w.priorities.get(GameData.Job.REST, 0) > 0 and can_rest, 60.0):
				err.call("energy0_" + w.char_name, "%s の元気が 60 秒以上 0 のまま（休憩に入れない？）" % w.char_name)

		# ---- 予約の取り残し ----
		for r in main.resources_root.get_children():
			if r.claimed_by != null:
				var cw = r.claimed_by
				var bad: bool = not is_instance_valid(cw) or cw.ai.res != r
				if lasting.call("res_%d" % r.get_instance_id(), bad, 10.0):
					err.call("resclaim_%d" % r.get_instance_id(), "資源（%s）が、向かっていない仲間に予約されたまま" % GameData.ITEM_NAMES.get(r.item, "?"))
		for c in main.creatures_root.get_children():
			if c.hunted_by != null and not c.dead:
				var hw = c.hunted_by
				var bad2: bool = not is_instance_valid(hw) or hw.ai.prey != c
				if lasting.call("prey_%d" % c.get_instance_id(), bad2, 10.0):
					err.call("preyclaim_%d" % c.get_instance_id(), "生物が、狩っていない仲間に予約されたまま")
		var haulers := 0
		var refuelers := 0
		var repairers := {}
		var resting := {}
		for w in W:
			if w.away:
				continue
			var s2: int = w.ai.state
			if s2 in [CharacterAI.State.HAUL_TAKE, CharacterAI.State.HAUL_MOVE]:
				haulers += 1
			if s2 in [CharacterAI.State.REFUEL_TAKE, CharacterAI.State.REFUEL_MOVE, CharacterAI.State.REFUEL]:
				refuelers += 1
			if s2 in [CharacterAI.State.REPAIR_TAKE, CharacterAI.State.REPAIR_MOVE, CharacterAI.State.REPAIR]:
				repairers[w.ai.repair_part] = true
			if s2 in [CharacterAI.State.REST_MOVE, CharacterAI.State.REST]:
				resting[w] = true
		if lasting.call("incoming", not P.incoming.is_empty() and haulers == 0, 60.0):
			err.call("incoming", "加工設備への運搬の予約が残ったまま（運んでいる人がいない）")
		if lasting.call("refuel", main.base.refuel_reserved and refuelers == 0, 30.0):
			err.call("refuel", "燃料補給の予約が残ったまま（補給に向かう人がいない）")
		for part in main.base.repair_reserved.keys():
			if lasting.call("repair_%d" % part, not repairers.has(part), 30.0):
				err.call("repair_%d" % part, "修理の予約（%s）が残ったまま" % GameData.PART_NAMES[part])
		for i in main.base.beds.size():
			var bw = main.base.beds[i]
			if bw != null and is_instance_valid(bw):
				if lasting.call("bed_%d" % i, not resting.has(bw), 30.0):
					err.call("bed_%d" % i, "ベッドが、休んでいない仲間に予約されたまま")

		# ---- 加工 ----
		var idle_orders: bool = not P.orders.is_empty() and P.current.is_empty() and P.worker == null and not P.only_blocked()
		if lasting.call("orders", idle_orders, 60.0):
			note.call("orders", "加工の注文が 60 秒以上、誰にも加工されずに待っている（加工担当が他の仕事で手いっぱい？）")
		if wait.has("orders"):
			max_wait["orders"] = maxf(max_wait["orders"], t - float(wait["orders"]))
		if lasting.call("output", not P.output.is_empty() and P.worker == null, 60.0):
			err.call("output", "できあがった加工品が 60 秒以上、取り出されずに残っている")
		if wait.has("output"):
			max_wait["output"] = maxf(max_wait["output"], t - float(wait["output"]))
		if lasting.call("current", not P.current.is_empty() and P.worker == null, 90.0):
			err.call("current", "加工の途中で止まったまま（作業者がいない）")
		# 作業者がいるのに、加工の進みが止まったまま
		if P.current.is_empty() or P.worker == null or absf(P.progress - prog_last) > 0.001 or str(P.current.get("id", "")) != prog_id:
			prog_last = P.progress
			prog_id = str(P.current.get("id", ""))
			prog_changed_at = t
		elif t - prog_changed_at > 40.0:
			err.call("progress", "加工の進みが 40 秒以上変わらない（%s）" % str(P.current.get("name", "")))

		# ---- 倉庫 ----
		for it in GameData.Item.values():
			if st.count_of(it) < 0:
				err.call("neg_%d" % it, "倉庫の個数がマイナス（%s）" % GameData.ITEM_NAMES.get(it, "?"))
		for bay in [CargoDB.Bay.RAW, CargoDB.Bay.PRODUCT]:
			if st.used_in(bay) > st.capacity_of(bay):
				err.call("cap_%d" % bay, "%s が積載量を超えている（%d/%d）" % [CargoDB.BAY_NAMES[bay], st.used_in(bay), st.capacity_of(bay)])
		for it in st.quota:
			if st.count_of(it) > st.quota_of(it):
				err.call("quota_%d" % it, "%s の個数（%d）が枠（%d）を超えている" % [GameData.ITEM_NAMES[it], st.count_of(it), st.quota_of(it)])

	Engine.time_scale = 1.0
	paused = false
	# ---- 画面の数字と実際の個数が合っているか ----
	main.status._process(0.0)
	var text: String = main.status._stock.text + "\n" + main.status._weight.tooltip_text     # 素材棚・加工品置き場の内訳は、重りのアイコンのツールチップ
	var rx := RegEx.new()
	var labels := [["食料", GameData.Item.FOOD], ["燃料", GameData.Item.FUEL], ["修理資材", GameData.Item.REPAIR_KIT], ["肉", GameData.Item.MEAT],
			["皮", GameData.Item.HIDE], ["骨", GameData.Item.BONE], ["脂", GameData.Item.FAT], ["木", GameData.Item.WOOD], ["石", GameData.Item.STONE],
			["鉱", GameData.Item.IRON_ORE], ["鉄", GameData.Item.IRON]]
	var ui_ok := true
	for lb in labels:
		rx.compile(str(lb[0]) + " ?(\\d+)")
		var m := rx.search(text)
		if m == null or int(m.get_string(1)) != st.count_of(lb[1]):
			ui_ok = false
			errors.append("右上の表示（%s %s）が倉庫の個数（%d）と違う" % [lb[0], m.get_string(1) if m != null else "なし", st.count_of(lb[1])])
	# 積載重量のアイコンゲージ: 数字（アイコンの内側）が実際の積載重量、充填率が実際の積載率と合っているか
	var wg: IconGauge = main.status._weight
	if wg.text != str(st.current_weight()) or absf(wg.ratio - st.weight_ratio()) > 0.001:
		ui_ok = false
		errors.append("積載重量のアイコン（数字 %s・充填 %.2f）が、実際の積載重量（%d・%.2f）と違う" % [wg.text, wg.ratio, st.current_weight(), st.weight_ratio()])
	rx.compile("素材棚 (\\d+) / (\\d+)")
	var m2 := rx.search(text)
	if m2 == null or int(m2.get_string(1)) != st.used_in(CargoDB.Bay.RAW) or int(m2.get_string(2)) != st.capacity_of(CargoDB.Bay.RAW):
		ui_ok = false
		errors.append("右上の素材棚の表示が、実際の積載量と違う")
	rx.compile("加工品置き場 (\\d+) / (\\d+)")
	var m3 := rx.search(text)
	if m3 == null or int(m3.get_string(1)) != st.used_in(CargoDB.Bay.PRODUCT) or int(m3.get_string(2)) != st.capacity_of(CargoDB.Bay.PRODUCT):
		ui_ok = false
		errors.append("右上の加工品置き場の表示が、実際の積載量と違う")
	if ui_ok:
		notes.append("右上の表示（素材・加工品の個数、素材棚・加工品置き場の積載量）は、実際の倉庫と一致している")

	# ---- 出力 ----
	var over: bool = main.game_over
	print("--- 第%d回（出来事 %s・シナリオ %s）ゲーム内 %.0f 分 走行 %.1f km%s ---" % [n, "あり" if events_on else "なし", scenario, d.elapsed / 60.0,
			d.distance / 2500.0, "  ★ゲームオーバー" if over else ""])
	var names := ["1 拠点が移動", "2 資源が発生", "3 資源を発見", "4 資源を回収", "5 拠点へ運ぶ", "6 素材棚に収納", "7 加工設備へ送られる", "8 加工される", "9 加工品置き場に収納"]
	var line := ""
	for k in names:
		if ms.has(k):
			line += "%s %.0f秒 / " % [k, ms[k]]
		else:
			line += "%s ★未達 / " % k
			all_ok = false
	print("  流れ: " + line.trim_suffix(" / "))
	if scenario == "build":
		var bl := ""
		for k in ["B1 ワークベンチ完成", "B2 最初のベッド完成", "B3 ベッド3つ完成"]:
			bl += ("%s %.0f秒 / " % [k, ms[k]]) if ms.has(k) else ("%s ★未達 / " % k)
			if not ms.has(k):
				notes.append("%s が最後まで起きなかった（運が悪い回。詰まりではないか確認）" % k)
		print("  建設: " + bl.trim_suffix(" / "))
	var sp: Array = []
	for it in stored:
		sp.append("%s%d" % [GameData.ITEM_NAMES[it], stored[it]])
	var mp: Array = []
	for it in made:
		mp.append("%s%d" % [GameData.ITEM_NAMES[it], made[it]])
	print("  資源: 発生 採取ポイント%d・落ちている物%d ／ 倉庫に入った素材 %s ／ 加工品 %s ／ 加工%d回 ／ 捨てた%d ／ 途中で消えた(向かっている最中) %d" % [
			spawned["point"], spawned["loose"], " ".join(PackedStringArray(sp)), " ".join(PackedStringArray(mp)), P.total_done, main.total_wasted, lost_claim])
	var share := ""
	for w in W:
		var ss2: Dictionary = state_secs.get(w, {})
		var tot := 0.0
		for k in ss2:
			tot += float(ss2[k])
		var top: Array = ss2.keys()
		top.sort_custom(func(x, y): return ss2[x] > ss2[y])
		var parts: Array = []
		for k in top.slice(0, 4):
			parts.append("%s%d%%" % [CharacterAI.STATE_TEXT[k], int(100.0 * ss2[k] / maxf(1.0, tot))])
		share += "%s[%s] " % [w.char_name, "・".join(PackedStringArray(parts))]
	print("  仲間の時間の使い方: " + share)
	print("  空腹 %d秒 ／ 加工の注文が待たされた最長 %d秒 ／ 加工品が取り出されなかった最長 %d秒" % [int(hungry_t), int(max_wait["orders"]), int(max_wait["output"])])
	if lost_claim > 0:
		notes.append("資源が、向かっている仲間がいるまま消えた回数: %d" % lost_claim)
	for e in errors:
		print("  ★ ", e)
		all_ok = false
	for x in notes:
		print("  ・ ", x)
	if errors.is_empty() and ms.size() == names.size():
		print("  → 異常なし")
	main.queue_free()
	await process_frame
