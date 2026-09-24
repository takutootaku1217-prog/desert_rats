extends SceneTree
## 個体システムの自己診断。実行:
##   Godot --headless --path . -s res://tools/selftest.gd
## プレイヤーのセーブは触らない（ヘッドレスでは SaveGame.enabled() が false。ラウンドトリップは別ファイルで確認）。

var fails := 0
var main


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	print("== 表の整合 ==")
	var n := GameData.RANKS.size()
	check(Balance.RANK_POWER.size() == n and Balance.RANK_DEPT_POINTS.size() == n and Balance.RANK_SPAWN_WEIGHTS.size() == n,
			"ランク表の長さが %d で揃っている" % n)
	for id in SkillDB.SKILLS:
		if SkillDB.describe(id) == "":
			check(false, "スキル %s に説明がない" % id)

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _worker_named(nm: String):
	for w in main.workers:
		if w.char_name == nm:
			return w
	return null


func _run() -> void:
	print("== 初期状態 ==")
	check(main.workers.size() == 3, "仲間は3匹")
	var nezu = _worker_named("ハヤト")
	var momo = _worker_named("モモ")
	var chuu = _worker_named("ダイ")
	check(nezu.dept == GameData.Field.GATHERER and momo.dept == GameData.Field.DEV and chuu.dept == -1, "初期配置")
	check(chuu.best_fields().size() == 2, "ダイは戦闘・回収が同ランクで、得意分野が2つ")
	check(main.storage.count_of(GameData.Item.FOOD) == Balance.START_ITEMS[GameData.Item.FOOD], "初期の倉庫")

	print("== 仲間の見た目（人間） ==")
	var sheets_ok := true
	for pal in CrewGen.PALETTES:
		var sheet := Image.load_from_file(ProjectSettings.globalize_path("res://assets/characters/crew_%s.png" % pal))
		if sheet == null or sheet.get_size() != Vector2i(16 * 13, 16):
			sheets_ok = false
	check(sheets_ok, "全ての見た目（%d種）にコマ絵があり、16x16 が13コマ" % CrewGen.PALETTES.size())
	check(CrewGen.renamed("ネズ吉") == "ハヤト" and CrewGen.renamed("チュー太") == "ダイ" and CrewGen.renamed("モモ") == "モモ",
			"ネズミだった頃の名前は人間の名前に直る")
	var pal_seen := {}
	for i in 200:
		pal_seen[CrewGen.generate([])["palette"]] = true
	check(pal_seen.size() == CrewGen.PALETTES.size(), "募集では全ての見た目が出る")

	print("== 個体の生成 ==")
	var rank_hist := {}
	var ties := 0
	var skill_hist := {}
	var ok_shape := true
	var used: Array = []
	for i in 600:
		var d := CrewGen.generate(used)
		if d["ranks"].size() != 5 or d["talent"].size() != 5 or d["growth"].size() != 5:
			ok_shape = false
		var top := 0
		for f in d["ranks"]:
			top = maxi(top, d["ranks"][f])
		rank_hist[top] = rank_hist.get(top, 0) + 1
		var c := 0
		for f in d["ranks"]:
			if d["ranks"][f] == top:
				c += 1
		if c >= 2:
			ties += 1
		skill_hist[d["skills"].size()] = skill_hist.get(d["skills"].size(), 0) + 1
		if d["skills"].size() != (d["skills"] as Array).duplicate().size():
			ok_shape = false
	check(ok_shape, "全分野のランク・才能・成長率が入っている")
	var max_top := 0
	for k in rank_hist:
		max_top = maxi(max_top, k)
	check(max_top <= 6, "出現するランクは S(6)以下 (最大 %s)" % GameData.RANKS[max_top])
	check(ties > 0, "同じ最高ランクが複数分野に並ぶ個体も出る (%d/600)" % ties)
	check(skill_hist.has(1) and skill_hist.has(2) and not skill_hist.has(0) and not skill_hist.has(4), "スキル数は1〜3 %s" % str(skill_hist))
	var names_line: Array = []
	for r in range(0, 7):
		names_line.append("%s:%d" % [GameData.RANKS[r], rank_hist.get(r, 0)])
	print("       得意分野のランク分布: ", " ".join(PackedStringArray(names_line)))

	print("== レベルと経験値 ==")
	var t = _worker_named("モモ")
	var lv0: int = t.level
	var a0: float = t.ability(GameData.Field.DEV)
	var m0: float = t.skill_mult(GameData.Job.PROCESS)
	t.gain_xp(Balance.xp_needed(t.level))
	check(t.level == lv0 + 1, "必要経験値ぶんでレベルが1上がる")
	check(t.ability(GameData.Field.DEV) > a0, "レベルが上がると能力値が伸びる (%.1f -> %.1f)" % [a0, t.ability(GameData.Field.DEV)])
	check(t.skill_mult(GameData.Job.PROCESS) > m0, "仕事の速さも上がる (%.2f -> %.2f)" % [m0, t.skill_mult(GameData.Job.PROCESS)])
	t.gain_xp(100000.0)
	check(t.level == Balance.MAX_LEVEL and t.xp == 0.0, "最大レベルで止まる (Lv%d)" % t.level)
	main.depts = {}
	main.refresh_departments()

	print("== 配置 ==")
	var w2 = _worker_named("ダイ")
	w2.dept = -1
	main.refresh_departments()
	var base_mult: float = w2.skill_mult(GameData.Job.GATHER)
	check(main.assign(w2, GameData.Field.GATHERER), "回収部に配置できる")
	var placed: float = w2.skill_mult(GameData.Job.GATHER)
	check(placed > base_mult * Balance.ASSIGN_BONUS * 0.999, "自分の分野なら速くなる (%.2f -> %.2f)" % [base_mult, placed])
	main.assign(w2, GameData.Field.COOK)
	check(w2.skill_mult(GameData.Job.GATHER) < base_mult, "別分野の部署に置くと少し遅くなる")
	main.assign(w2, GameData.Field.GATHERER)

	print("== 部署レベルと収容 ==")
	var lv_before: int = main.dept_level(GameData.Field.GATHERER)
	var pts_before: float = main.dept_info(GameData.Field.GATHERER)["points"]
	# 人数が増えるとポイントが増える
	var extra = main.recruit()
	check(extra != null, "募集できる（%s）" % extra.char_name)
	check(main.workers.size() == 4, "仲間が4匹になった")
	check(main.storage.count_of(GameData.Item.FOOD) == Balance.START_ITEMS[GameData.Item.FOOD] - Balance.RECRUIT_COST[GameData.Item.FOOD],
			"募集の費用が引かれた")
	main.assign(extra, GameData.Field.GATHERER)
	var pts_after: float = main.dept_info(GameData.Field.GATHERER)["points"]
	check(pts_after > pts_before, "所属が増えるとポイントが増える (%.1f -> %.1f)" % [pts_before, pts_after])
	check(main.dept_level(GameData.Field.GATHERER) >= lv_before, "部署レベルは下がらない (Lv%d)" % main.dept_level(GameData.Field.GATHERER))
	# 初期の加工品(サボテン食4)で2匹まで募集できる → 5匹
	var third = main.recruit()
	check(third != null and main.workers.size() == 5, "2匹目も募集できる（5匹）")
	check(main.recruit() == null and main.workers.size() == 5,
			"加工品が足りないと募集できない（サボテン食 %d）" % main.storage.count_of(GameData.Item.FOOD))
	main.storage.add_item(GameData.Item.FOOD, 10)
	var sixth = main.recruit()
	check(sixth != null, "続けて募集できる")
	while main.workers.size() < main.max_crew():
		main.storage.add_item(GameData.Item.FOOD, 2)
		main.recruit()
	check(main.recruit() == null and main.workers.size() == main.max_crew(),
			"収容人数 %d 匹で募集が止まる（加工品があっても）" % main.max_crew())
	# 定員: この時点で回収部は ハヤト・ダイ・募集した1人 の3人
	check(main.dept_info(GameData.Field.GATHERER)["members"].size() == Balance.DEPT_CAPACITY, "回収部が定員(%d人)" % Balance.DEPT_CAPACITY)
	check(not main.assign(third, GameData.Field.GATHERER) and third.dept == -1, "定員を超えては配置できない")
	check(main.assign(nezu, -1), "無所属に戻せる")
	check(main.assign(third, GameData.Field.GATHERER), "空きができれば配置できる")
	main.assign(w2, GameData.Field.COOK)

	print("== スキルの効果 ==")
	var s = _worker_named("ハヤト")
	s.skills = []
	s.dept = -1
	main.refresh_departments()
	var plain: float = s.skill_mult(GameData.Job.GATHER)
	s.skills = ["keen_eye"]
	check(is_equal_approx(s.skill_mult(GameData.Job.GATHER), plain * 1.15), "目利き: 回収の効率 +15%")
	check(is_equal_approx(s.skill_mult(GameData.Job.PROCESS), s.skill_mult(GameData.Job.PROCESS)) and
			is_equal_approx(s.skill_mult(GameData.Job.HAUL), _worker_base(s, GameData.Job.HAUL) * 1.15),
			"目利き: 運搬（同じ回収分野）にも効く")
	s.skills = ["sturdy_legs"]
	check(is_equal_approx(s.skill_mult(GameData.Job.HAUL), _worker_base(s, GameData.Job.HAUL) / 0.85), "健脚: 運搬の作業時間 -15%")
	check(is_equal_approx(s.skill_mult(GameData.Job.GATHER), plain), "健脚は回収には効かない")
	s.skills = ["all_rounder"]
	check(is_equal_approx(s.skill_mult(GameData.Job.PROCESS), _worker_base(s, GameData.Job.PROCESS) * 1.06), "万能型: 全分野 +6%")
	s.skills = ["scavenger"]
	check(is_equal_approx(s.yield_chance(), 0.15), "拾い上手: 追加資源の確率 15%")
	s.skills = ["nutrition", "hard_worker"]
	check(is_equal_approx(s.stamina_mult(), 1.0 - 0.12 - 0.08), "栄養管理+働き者: 元気の消耗が減る")
	s.skills = ["spoils", "survivor"]
	check(is_equal_approx(s.atk_mult(), 1.15) and is_equal_approx(s.def_bonus(), 0.15), "戦闘スキル: 攻撃 +15% / 防御 +15%")
	# 相乗効果
	var a = _worker_named("ハヤト")
	var b = _worker_named("モモ")
	a.dept = GameData.Field.DEV
	b.dept = GameData.Field.DEV
	a.skills = ["weapon_design"]
	b.skills = ["weapon_design"]
	main.refresh_departments()
	var syn: float = main.dept_info(GameData.Field.DEV)["synergy"]
	check(syn >= Balance.DEPT_SYNERGY_POINT, "同じスキルが2人で部署に相乗効果 (+%.1f)" % syn)

	print("== 部署レベルによる解放 ==")
	var lv1 := {}
	for f in GameData.Field.values():
		lv1[f] = {"level": 1}
	check(is_equal_approx(Unlocks.total("hopper_cap", lv1), 0.0) and is_equal_approx(Unlocks.mult("process_speed", lv1), 1.0),
			"Lv1では何も解放されていない")
	var lv_mid := {
		GameData.Field.DEV: {"level": 4}, GameData.Field.GATHERER: {"level": 4},
		GameData.Field.MEDIC: {"level": 2}, GameData.Field.COOK: {"level": 5},
		GameData.Field.COMBAT: {"level": 5},
	}
	check(is_equal_approx(Unlocks.total("hopper_cap", lv_mid), 2.0), "開発部Lv4で増設ホッパー(+2)が解放")
	check(is_equal_approx(Unlocks.mult("process_speed", lv_mid), 0.85), "開発部Lv4で高速加工ライン(×0.85)が解放")
	check(is_equal_approx(Unlocks.total("bone_rate", lv_mid), 1.0) and is_equal_approx(Unlocks.mult("spawn_speed", lv_mid), 0.85),
			"回収部Lv4で骨の目利き・広域捜索が解放")
	check(is_equal_approx(Unlocks.total("bed_cap", lv_mid), 1.0), "医務部Lv2で簡易寝床(+1)が解放")
	check(is_equal_approx(Unlocks.total("crew_cap", lv_mid), 2.0), "料理部Lv5で配給改善・非常食備蓄(+1+1)が解放")
	check(is_equal_approx(Unlocks.total("atk_bonus", lv_mid), 0.3), "戦闘部Lv5で武装強化・特別装甲(+15%+15%)が解放")

	var saved_depts: Dictionary = main.depts
	main.depts = lv1
	check(main.base.bed_capacity() == 3 and main.processor.hopper_cap() == BaseProcessor.BASE_HOPPER_CAP
			and is_equal_approx(main.processor.process_time(), BaseProcessor.BASE_PROCESS_TIME) and main.max_crew() == Balance.BASE_MAX_CREW,
			"部署Lv1のときは基礎値のまま")
	main.depts = lv_mid
	check(main.base.bed_capacity() == 4, "医務部の解放でベッドが4つに増える")
	check(main.processor.hopper_cap() == BaseProcessor.BASE_HOPPER_CAP + 2, "開発部の解放でホッパーが増える")
	check(is_equal_approx(main.processor.process_time(), BaseProcessor.BASE_PROCESS_TIME * 0.85), "開発部の解放で加工が速くなる")
	check(main.base_level() == 3, "部署が育つと拠点レベルが上がる (Lv%d)" % main.base_level())
	check(main.max_crew() == Balance.BASE_MAX_CREW + 2 + (main.base_level() - 1) * Balance.CREW_CAP_PER_BASE_LEVEL,
			"料理部の解放と拠点レベルで収容人数が増える (%d匹)" % main.max_crew())
	var fighter = _worker_named("ダイ")
	fighter.dept = GameData.Field.COMBAT
	fighter.skills = []
	check(is_equal_approx(fighter.atk_mult(), 1.3), "戦闘部に配置した個体は戦闘部の解放の攻撃力上乗せを受ける")
	main.depts = saved_depts
	main.refresh_departments()

	print("== 速度と資源の出現（速度を落としても溜まりすぎない） ==")
	main.scroll_speed = Balance.SCROLL_SPEED_DEFAULT
	check(is_equal_approx(main._speed_spawn_mult(), 1.0), "基準速度では出現間隔の倍率は1.0")
	main.scroll_speed = Balance.SCROLL_SPEED_MIN
	var slow_mult: float = main._speed_spawn_mult()
	check(slow_mult > 1.0 and slow_mult <= Balance.SPAWN_INTERVAL_MULT_MAX, "最低速度では出現間隔が延びる (×%.2f)" % slow_mult)
	# 「画面上にいる資源の数」がだいたい一定になっているか（滞在時間 / 出現間隔）を確認
	var dist := 1330.0 + 60.0
	var density_ref: float = (dist / Balance.SCROLL_SPEED_DEFAULT) / ((Balance.SPAWN_INTERVAL_MIN + Balance.SPAWN_INTERVAL_MAX) / 2.0)
	var density_slow: float = (dist / Balance.SCROLL_SPEED_MIN) / ((Balance.SPAWN_INTERVAL_MIN + Balance.SPAWN_INTERVAL_MAX) / 2.0 * slow_mult)
	check(density_slow < density_ref * 1.5, "最低速度でも画面上の資源数は基準速度の1.5倍未満 (%.1f 個 vs %.1f 個)" % [density_slow, density_ref])
	main.scroll_speed = Balance.SCROLL_SPEED_DEFAULT
	check(is_equal_approx(Balance.clamp_scroll_speed(10.0), Balance.SCROLL_SPEED_MIN)
			and is_equal_approx(Balance.clamp_scroll_speed(999.0), Balance.SCROLL_SPEED_MAX),
			"古いセーブの遅すぎる速度は下限に収める")
	# 保険: 万一とても長く残った資源（回収中でない）は自動で消える
	var stale := ResourceNode.new()
	stale.game = main
	stale.age = Balance.RESOURCE_MAX_AGE + 1.0
	stale.position = Vector2(400, 600)
	main.resources_root.add_child(stale)
	stale._process(0.01)
	check(not is_instance_valid(stale) or stale.is_queued_for_deletion(), "長時間残った資源（回収中でない）は自動で消える")

	print("== 部屋の部品化（区画の入れ替え） ==")
	main.depts = lv1
	main.room_layout = Rooms.default_layout()
	main._apply_layout()
	check(main.processor.position == Vector2(340, 354) and main.storage.position == Vector2(640, 482),
			"初期配置: 加工設備・倉庫が今までと同じ位置")
	var bp: Array = main.base.bed_points()
	check(bp.size() == 3 and bp[0] == Vector2(540, 354) and bp[1] == Vector2(600, 354) and bp[2] == Vector2(660, 354),
			"初期配置: ベッドが今までと同じ位置")
	# 絵（Python が作る重ね絵）と、区画の表（data/rooms.gd）が食い違っていないか
	var art_ok := true
	var art_msg := ""
	for slot_id in Rooms.SLOT_ORDER:
		for rtype in Rooms.TYPE_ORDER:
			if not Rooms.can_place(rtype, slot_id):
				continue
			var img := Image.load_from_file(ProjectSettings.globalize_path(Rooms.overlay_path(slot_id, rtype)))
			if img == null:
				art_ok = false
				art_msg += " 無い:" + Rooms.overlay_path(slot_id, rtype)
			elif Vector2(img.get_size()) * float(Rooms.PX) != Rooms.overlay_rect(slot_id).size:
				art_ok = false
				art_msg += " 大きさ違い:" + Rooms.overlay_path(slot_id, rtype)
	check(art_ok, "全ての(区画,部屋)に重ね絵があり、大きさが区画と一致" + art_msg)
	# ルール
	var lay: Dictionary = main.room_layout
	check(Rooms.block_reason(lay, "u1", "storage", 1) == "この階には置けない", "倉庫は下の階だけ")
	check(Rooms.block_reason(lay, "u2", "empty", 1).begins_with("最後の"), "最後の寝室は壊せない")
	check(Rooms.block_reason(lay, "u1", "mess", 1).begins_with("最後の"), "最後の加工室は壊せない")
	check(Rooms.block_reason(lay, "l2", "engine", 1).begins_with("最後の"), "最後の倉庫は壊せない")
	check(Rooms.block_reason(lay, "l1", "training", 1) == "拠点Lv2で解放", "訓練室は拠点Lv2から")
	check(Rooms.block_reason(lay, "l1", "training", 2) == "", "拠点Lv2なら訓練室を建てられる")
	check(Rooms.block_reason(lay, "l2", "storage", 1).begins_with("すでに"), "同じ部屋には建てられない")
	# 建てる（費用・効果）
	for it in GameData.PRODUCT_ITEMS:
		main.storage.add_item(it, 20)
	var fab0: int = main.storage.count_of(GameData.Item.FABRIC)
	var bone0: int = main.storage.count_of(GameData.Item.BONE_PROD)
	check(main.build_room("l1", "infirmary"), "機関室を医務室に建て替えられる")
	check(main.room_layout["l1"] == "infirmary" and is_equal_approx(main.room_effect("rest_rate"), 0.25),
			"医務室で休憩の回復 +25%")
	check(main.storage.count_of(GameData.Item.FABRIC) == fab0 - 3 and main.storage.count_of(GameData.Item.BONE_PROD) == bone0 - 2,
			"建てる費用が引かれた")
	var stock_before_fail: int = main.storage.count_of(GameData.Item.METAL)
	check(not main.build_room("u1", "mess") and main.storage.count_of(GameData.Item.METAL) == stock_before_fail,
			"建てられないときは費用を払わない（最後の加工室）")
	# 移設: 加工室を下の階へ（元の区画は空き部屋になる）
	check(Rooms.is_relocation(main.room_layout, "l1", "workshop"), "加工室を別の区画に建てるのは移設")
	main.depts = lv_mid          # 拠点Lv3
	check(main.build_room("l1", "workshop"), "加工室を下の階へ移設できる")
	check(main.room_layout["u1"] == "empty" and main.room_layout["l1"] == "workshop", "元の区画は空き部屋になる")
	check(main.processor.position == Rooms.processor_pos("l1") and is_equal_approx(main.processor.position.y, GameData.LO_Y),
			"加工設備が下の階へ移る")
	# 寝室を増やすとベッドが増える
	check(main.build_room("u1", "bedroom"), "空き部屋に寝室を建てられる")
	check(main.base.room_bed_count() == 6 and main.base.bed_capacity() >= 6, "寝室が2つでベッド6つ")
	# 食堂（寝室が2つあるので1つは建て替えできる）
	check(main.build_room("u1", "mess") and is_equal_approx(main.room_effect("drain_cut"), 0.12), "食堂で元気の消耗 -12%")
	# 訓練室（効果の確認。建てる条件は上で確認済み）
	main.room_layout = Rooms.with_room(main.room_layout, "u1", "training")
	main._apply_layout()
	check(is_equal_approx(main.train_xp(), Balance.TRAIN_XP * 1.5), "訓練室で訓練の経験値 +50%")
	# 配置を変えるとベッドの割り当てはリセットされる
	var sleeper = _worker_named("ハヤト")
	var bi: int = main.base.claim_bed(sleeper)
	sleeper.bed_index = bi
	main._apply_layout()
	check(main.base.beds[bi] == null and sleeper.bed_index == -1, "配置を変えるとベッドの割り当てがリセットされる")
	# セーブ・ロード
	var rpath := "user://selftest_rooms.json"
	check(SaveGame.write(main, rpath), "部屋の配置を含めて書き込める")
	var rdata := SaveGame.read(rpath)
	check(Rooms.sanitize(rdata.get("rooms", {})) == main.room_layout, "部屋の配置がセーブ・ロードで復元される")
	SaveGame.delete(rpath)
	check(Rooms.sanitize({}) == Rooms.default_layout(), "古いセーブ（配置なし）は初期配置になる")
	check(Rooms.sanitize({"u1": "storage", "u2": "bedroom", "l1": "engine", "l2": "storage"}) == Rooms.default_layout(),
			"置けない階の部屋を含む配置は初期配置に戻る")
	check(Rooms.sanitize({"u1": "empty", "u2": "bedroom", "l1": "engine", "l2": "storage"}) == Rooms.default_layout(),
			"加工室が無い配置は初期配置に戻る")
	# 元に戻す
	main.room_layout = Rooms.default_layout()
	main._apply_layout()
	main.refresh_departments()

	print("== 訓練 ==")
	var trainee = _worker_named("ハヤト")
	trainee.level = 1
	trainee.xp = 0.0
	main.storage.add_item(GameData.Item.FABRIC, 1)
	var cloth_before: int = main.storage.count_of(GameData.Item.FABRIC)
	check(main.train(trainee) and trainee.xp == main.train_xp(), "訓練で経験値 +%d" % int(main.train_xp()))
	check(main.storage.count_of(GameData.Item.FABRIC) == cloth_before - 1, "訓練の費用が引かれた")

	print("== セーブ・ロード ==")
	var path := "user://selftest_save.json"
	check(SaveGame.write(main, path), "書き込める")
	var data := SaveGame.read(path)
	check(data.has("crew") and data["crew"].size() == main.workers.size(), "個体が全員入っている")
	var dw := Worker.new()
	dw.setup(main, data["crew"][2], 2)
	var src = main.workers[2]
	check(dw.char_name == src.char_name and dw.level == src.level and dw.dept == src.dept and dw.skills == src.skills
			and dw.ranks == src.ranks and dw.priorities == src.priorities and is_equal_approx(dw.ability(0), src.ability(0)),
			"個体が同じ状態で復元される（%s）" % dw.char_name)
	check(is_equal_approx(dw.talent.get(0, 0.0), src.talent.get(0, 0.0)) and dw.tint.to_html() == src.tint.to_html(),
			"才能・成長率・色も復元される")
	var inv := Inventory.new()
	inv.load_counts(data["inventory"])
	check(inv.counts == main.storage.inventory.counts, "倉庫の中身が復元される")
	dw.free()
	SaveGame.delete(path)
	check(not SaveGame.exists(path), "テスト用セーブを消した")
	check(not SaveGame.enabled(), "ヘッドレスではプレイヤーのセーブを触らない設定")

	print("== 実際に進める（ゲーム内約4分） ==")
	Engine.time_scale = 8.0
	var xp_before := {}
	for w in main.workers:
		xp_before[w] = float(w.level) * 1000.0 + w.xp
	var stock_before := 0
	for it in GameData.RAW_ITEMS + GameData.PRODUCT_ITEMS:
		stock_before += main.storage.count_of(it)
	await create_timer(30.0).timeout
	Engine.time_scale = 1.0
	var gained := 0
	for w in main.workers:
		if float(w.level) * 1000.0 + w.xp > xp_before[w]:
			gained += 1
	check(gained >= 3, "働いた個体が経験値を得ている (%d/%d匹)" % [gained, main.workers.size()])
	var stock_after := 0
	for it in GameData.RAW_ITEMS + GameData.PRODUCT_ITEMS:
		stock_after += main.storage.count_of(it)
	check(stock_after != stock_before, "資源が回っている (倉庫の合計 %d -> %d)" % [stock_before, stock_after])
	for w in main.workers:
		print("       %s Lv%d xp %.0f 元気 %.0f 状態 %s 所属 %s" % [w.char_name, w.level, w.xp, w.energy, w.ai.status_text(),
				GameData.dept_name(w.dept) if w.dept >= 0 else "-"])


## スキルを外した状態の同じ仕事の速さ
func _worker_base(w, job: int) -> float:
	var keep: Array = w.skills
	w.skills = []
	var m: float = w.skill_mult(job)
	w.skills = keep
	return m
