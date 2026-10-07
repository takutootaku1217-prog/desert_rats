extends SceneTree
## 採取ポイント＋道具の自己診断。実行:
##   Godot --headless --path . -s res://tools/test_gather.gd
## 表・計算式（採取ポイント × 道具 × 仲間の能力）・採取ポイントの動き・回収AIの一連の流れ・道具の割り当てと加工・画面・長時間の安定を確かめる。

var fails := 0
var main
var st: BaseStorage


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20260927)
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


## 状態をきれいにする（出来事は止め、倉庫は空・割り当ては初期、道具は誰も持たない、地面の物は全部消す）。
func _reset() -> void:
	main.director.enabled = false
	main.director.active.clear()
	main.director.forecast.clear()
	main.scroll_speed = 0.0                    # 世界を止めて、採取ポイントの「選び方」だけを確かめる（追いつけるかは専用の診断で）
	for w in main.workers:
		if w.away:
			w.arrive(0.0)
		w.ai._release_task()
		w.carrying = -1
		w.carry_n = 1
		w.carry_bonus = {}
		w.tools = {}
		w.fatigue = 0.0
		w.ai._set_state(CharacterAI.State.SEARCH)
	for root_node in [main.resources_root, main.creatures_root, main.enemies_root]:
		for c in root_node.get_children():
			root_node.remove_child(c)
			c.free()
	st.enforce = true
	st.inventory.counts.clear()
	st.capacity_bonus = 0
	st.wasted.clear()
	main.total_wasted = 0
	main.total_gathered = 0
	main.tool_auto = true
	main.processor.orders.clear()
	main.processor.incoming.clear()
	main.processor.current = {}
	main.processor.output.clear()
	main.hungry = false


func _point(kind: String, x := 600.0, amount := -1) -> GatherPoint:
	var pt := GatherPoint.new()
	pt.setup(main, kind)
	if amount >= 0:
		pt.max_amount = amount
		pt.remaining = amount
	pt.position = Vector2(x, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.resources_root.add_child(pt)
	return pt


func _run() -> void:
	st = main.storage
	var W: Array = main.workers
	_reset()

	print("== 表の整合 ==")
	var files_ok := true
	for k in GatherDB.POINTS:
		if not FileAccess.file_exists("res://assets/gather/%s.png" % k):
			files_ok = false
	for it in GameData.TOOL_ITEMS:
		if not FileAccess.file_exists("res://assets/resources/item_%s.png" % GameData.ITEM_FILES[it]):
			files_ok = false
	check(files_ok, "採取ポイントの絵（3種）と道具のアイコン（5種）がある")
	var tools_ok := true
	for it in GameData.TOOL_ITEMS:
		if not GatherDB.TOOLS.has(it) or not GatherDB.SLOTS.has(GatherDB.slot_of_tool(it)) or not GameData.ITEM_NAMES.has(it):
			tools_ok = false
		var made := false
		for r in GameData.RECIPES:
			if r["out"] == it:
				made = true
		if not made:
			tools_ok = false
	check(tools_ok, "すべての道具に、枠・名前・作り方（レシピ）がある")
	var pts_ok := true
	for k in GatherDB.POINTS:
		var d: Dictionary = GatherDB.POINTS[k]
		if not GatherDB.SLOTS.has(d["slot"]) or not (d["item"] in GameData.GROUND_ITEMS) or d["amount"][0] > d["amount"][1]:
			pts_ok = false
	check(pts_ok, "採取ポイントは、木材・石・鉄鉱石のどれかを産し、道具の枠が正しい")
	check(CargoDB.bay_of(GameData.Item.HAMMER) < 0 and st.add_item(GameData.Item.HAMMER, 5) == 5, "道具は倉庫の積載量の対象外（枠なしで置ける）")
	st.inventory.counts.clear()

	print("== 計算式（採取ポイント × 道具 × 仲間の能力） ==")
	var e_h := GatherDB.evaluate("vein", -1, 5, 1.0)
	var e_ham := GatherDB.evaluate("vein", GameData.Item.HAMMER, 5, 1.0)
	var e_pk := GatherDB.evaluate("vein", GameData.Item.PICKAXE, 5, 1.0)
	var e_adv := GatherDB.evaluate("vein", GameData.Item.ADV_PICK, 5, 1.0)
	print("       鉱床10単位: 素手%.1f 簡易ハンマー%.1f 鉄製ピッケル%.1f 高性能%.1f 個" % [e_h["eff"] * 10.0, e_ham["eff"] * 10.0, e_pk["eff"] * 10.0, e_adv["eff"] * 10.0])
	check(e_h["eff"] < e_ham["eff"] and e_ham["eff"] < e_pk["eff"] and e_pk["eff"] < e_adv["eff"], "道具が良いほど取れる割合が高い（素手 < ハンマー < ピッケル < 高性能）")
	check(absf(e_ham["eff"] * 10.0 - 3.0) < 0.6 and absf(e_pk["eff"] * 10.0 - 7.0) < 0.6 and absf(e_adv["eff"] * 10.0 - 10.0) < 0.6,
			"鉱10個 → ハンマー約3個・ピッケル約7個・高性能10個（ユーザーの例）")
	check(e_h["seconds"] > e_ham["seconds"] and e_ham["seconds"] > e_pk["seconds"] and e_pk["seconds"] > e_adv["seconds"], "道具が良いほど速く掘れる")
	check(e_adv["bonus"].has(GameData.Item.STONE) and e_pk["bonus"].is_empty(), "高性能ピッケルだけ副産物がある")
	var lo := GatherDB.evaluate("vein", GameData.Item.ADV_PICK, 0, 1.0)      # 回収E
	var hi := GatherDB.evaluate("vein", GameData.Item.ADV_PICK, 4, 1.0)      # 回収A
	check(lo["eff"] < hi["eff"] and lo["fit"] < 1.0 and hi["fit"] == 1.0, "回収ランクが低いと、高性能な道具を使いこなせない（適性 %.2f → %.2f）" % [lo["fit"], hi["fit"]])
	var ab_lo := GatherDB.evaluate("rock", GameData.Item.PICKAXE, 3, 0.9)
	var ab_hi := GatherDB.evaluate("rock", GameData.Item.PICKAXE, 3, 1.5)
	check(ab_hi["eff"] > ab_lo["eff"] and ab_hi["seconds"] < ab_lo["seconds"], "仲間の能力値が高いと、多く・速く採れる")
	check(GatherDB.evaluate("vein", -1, 3, 1.0)["eff"] < GatherDB.MIN_EFF, "素手では鉱床はほとんど取れない（採らない判断の基準 %.2f 未満）" % GatherDB.MIN_EFF)
	# 3つの要素がそれぞれ結果を変える
	var base_ev := GatherDB.evaluate("rock", GameData.Item.HAMMER, 2, 1.0)
	check(GatherDB.evaluate("vein", GameData.Item.HAMMER, 2, 1.0)["eff"] != base_ev["eff"]
			and GatherDB.evaluate("rock", GameData.Item.PICKAXE, 2, 1.0)["eff"] != base_ev["eff"]
			and GatherDB.evaluate("rock", GameData.Item.HAMMER, 2, 1.4)["eff"] != base_ev["eff"], "採取ポイント・道具・仲間の能力のどれを変えても結果が変わる")
	# 低ランクには扱いやすい道具のほうが良いことがある（適性）
	var sc_pick := GatherDB.tool_score("mine", GameData.Item.PICKAXE, 0, 0.85)
	var sc_adv := GatherDB.tool_score("mine", GameData.Item.ADV_PICK, 0, 0.85)
	var sc_adv_hi := GatherDB.tool_score("mine", GameData.Item.ADV_PICK, 5, 1.3)
	var sc_pick_hi := GatherDB.tool_score("mine", GameData.Item.PICKAXE, 5, 1.3)
	check(sc_pick > sc_adv and sc_adv_hi > sc_pick_hi, "回収Eには鉄製ピッケルのほうが総合点が高く、回収Sには高性能ピッケルのほうが高い（%.2f/%.2f, %.2f/%.2f）" % [sc_pick, sc_adv, sc_pick_hi, sc_adv_hi])

	print("== 採取ポイント ==")
	_reset()
	var kinds := {}
	for i in 400:
		main._spawn_ground_resource()
	for c in main.resources_root.get_children():
		if c is GatherPoint:
			kinds[c.kind] = kinds.get(c.kind, 0) + 1
	check(kinds.size() == 3 and kinds["tree"] > kinds["vein"] and kinds["rock"] > kinds["vein"], "採取ポイントが3種類とも現れる（木%d・岩%d・鉱床%d。鉱床がいちばん少ない）" % [kinds.get("tree", 0), kinds.get("rock", 0), kinds.get("vein", 0)])
	var range_ok := true
	for c in main.resources_root.get_children():
		var d: Dictionary = GatherDB.POINTS[c.kind]
		if c.remaining < d["amount"][0] or c.remaining > d["amount"][1] or c.item != d["item"]:
			range_ok = false
	check(range_ok, "残量は種類ごとの範囲に収まり、産する素材も正しい")
	_reset()
	var pt := _point("rock", 600.0, 10)
	check(pt.frame() == 0, "たっぷりのときの絵")
	pt.remaining = 4
	check(pt.frame() == 1, "減ると「減った」絵")
	pt.remaining = 0
	check(pt.frame() == 2 and not pt.available(), "尽きると「枯れた」絵になり、もう採れない")
	var x0: float = pt.position.x
	main.scroll_speed = 60.0
	pt._process(0.5)
	main.scroll_speed = 0.0
	check(pt.position.x < x0, "採取ポイントも、砂漠と一緒に後ろへ流れる")

	print("== 流れる資源に追いつけるか ==")
	_reset()
	var far := _point("rock", 1200.0, 10)         # 右の端（これから流れてくる）
	var under := _point("rock", 600.0, 10)        # 拠点の真下（もう左へ流れていく）
	W[0].floor_i = 1
	W[0].position = Vector2(640.0, GameData.LO_Y)
	main.scroll_speed = 0.0
	check(W[0].ai._can_reach(under) and W[0].ai._can_reach(far), "世界が止まっているときは、どの資源にも追いつける")
	main.scroll_speed = 60.0
	check(W[0].ai._can_reach(far), "通常の速さ（60）: 右から流れてくる資源には追いつける")
	check(not W[0].ai._can_reach(under), "通常の速さ（60）: 拠点の真下を左へ流れていく資源には、拠点の中から出ても追いつけない")
	main.scroll_speed = 200.0
	check(not W[0].ai._can_reach(far) and not W[0].ai._can_reach(under), "速さが仲間の足を超える（200）と、どの資源にも追いつけない")
	main.scroll_speed = 60.0
	W[0].floor_i = 0
	W[0].position = Vector2(1000.0, 560.0)
	check(W[0].ai._can_reach(_point("rock", 900.0, 10)), "地面にいて、すぐ近くの資源には、通常の速さで追いつける")
	# 追いつけない資源しかないとき、回収に入らず取り消しも起きない（往復しない）
	_reset()
	W[0].floor_i = 1
	W[0].position = Vector2(640.0, GameData.LO_Y)
	_point("rock", 600.0, 10)
	main.scroll_speed = 60.0
	check(not W[0].ai._try_start(GameData.Job.GATHER), "追いつけない資源しかないときは、回収の仕事に入らない（見つけて取り消す往復をしない）")
	main.scroll_speed = 0.0

	print("== 回収AIの判断 ==")
	_reset()
	var rock := _point("rock", 620.0, 10)
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == rock and rock.claimed_by == W[0], "空きがあれば、岩場へ採りに行く")
	check(W[0].ai.bag_limit == GatherDB.CARRY_MAX and rock.reserved == GatherDB.CARRY_MAX, "袋は %d 個まで（倉庫の空き枠も予約する）" % GatherDB.CARRY_MAX)
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 空き枠が少ないと、袋も小さくなる
	st.add_item(GameData.Item.STONE, st.quota_of(GameData.Item.STONE) - 2)
	W[0].ai._try_start(GameData.Job.GATHER)
	check(W[0].ai.bag_limit == 2 and rock.reserved == 2, "倉庫の空き枠が2個なら、袋も2個まで")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# ほかの人が予約している分は空き枠から引く
	W[1].ai._try_start(GameData.Job.GATHER)
	check(W[1].ai.res == rock and not W[2].ai._try_start(GameData.Job.GATHER), "予約された岩場には、ほかの人は向かわない（1つの採取ポイントに1人）")
	W[1].ai._release_task()
	W[1].ai._set_state(CharacterAI.State.SEARCH)
	st.inventory.counts.clear()
	# 素手では鉱床を採らない。道具を持てば採る
	_reset()
	var vein := _point("vein", 640.0, 8)
	check(not W[0].ai._try_start(GameData.Job.GATHER), "素手では取れる割合が低すぎる鉱床は、採りに行かない")
	W[0].tools["mine"] = GameData.Item.HAMMER
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == vein, "簡易ハンマーを持てば、鉱床を採りに行く")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 尽きたポイントは採らない
	vein.remaining = 0
	check(not W[0].ai._try_start(GameData.Job.GATHER), "掘り尽くされた採取ポイントは採らない")
	# 取れる割合が高いほうを優先（同じ距離・同じ★なら）
	_reset()
	W[0].tools["mine"] = GameData.Item.HAMMER
	var r2 := _point("rock", 600.0, 10)                  # ハンマー: 岩70%
	var v2 := _point("vein", 600.0, 8)                   # ハンマー: 鉱床30%
	main.gather_policy[GameData.Item.STONE] = 3
	main.gather_policy[GameData.Item.IRON_ORE] = 3
	W[0].ai._try_start(GameData.Job.GATHER)
	check(W[0].ai.res == r2, "道具の相性がよい採取ポイントを優先する（岩場 70% > 鉱床 30%）")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	# 回収の方針の★0は採らない
	main.gather_policy[GameData.Item.STONE] = 0
	W[0].ai._try_start(GameData.Job.GATHER)
	check(W[0].ai.res == v2, "回収の方針が★0の素材（石）の岩場は採らない")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)
	main.gather_policy[GameData.Item.STONE] = 3

	print("== 採取の一連の流れ（掘る → 袋 → 倉庫） ==")
	_reset()
	W[0].tools["mine"] = GameData.Item.HAMMER
	var pr := _point("rock", 640.0, 10)
	var ai: CharacterAI = W[0].ai
	ai._try_start(GameData.Job.GATHER)
	ai._set_state(CharacterAI.State.GATHER)
	W[0].position = Vector2(pr.position.x - 40.0, pr.position.y)
	W[0].floor_i = 0
	var ev: Dictionary = W[0].gather_eval("rock")
	var guard := 0
	while ai.state == CharacterAI.State.GATHER and guard < 2000:
		guard += 1
		W[0].position = Vector2(pr.position.x - 40.0, pr.position.y)
		ai.tick(0.05)
	check(ai.state == CharacterAI.State.MOVE_TO_STORAGE and W[0].carrying == GameData.Item.STONE and W[0].carry_n == GatherDB.CARRY_MAX,
			"袋がいっぱいになったら倉庫へ運ぶ（石%d個）" % W[0].carry_n)
	var used: int = pr.max_amount - pr.remaining
	print("       掘り出した量 %d 単位 → 石 %d 個（取れる割合の設定 %.0f%%）・掘った時間 約%.1f秒" % [used, W[0].carry_n, ev["eff"] * 100.0, guard * 0.05])
	check(absf(float(W[0].carry_n) / float(maxi(1, used)) - ev["eff"]) < 0.25, "掘り出した量と手に入った個数の比が、取れる割合に近い")
	check(pr.claimed_by == null and pr.remaining > 0 and pr.remaining < 10, "採取ポイントは残量が減り、次の人が採れる状態に戻る（残り%d）" % pr.remaining)
	check(main.total_gathered == W[0].carry_n, "回収の累計に、袋の個数が入る")
	# 倉庫に運ぶ
	W[0].floor_i = 1
	W[0].position = st.access_point() + W[0].slot_offset
	W[0].target = W[0].position
	guard = 0
	while ai.state != CharacterAI.State.SEARCH and guard < 200:
		guard += 1
		ai.tick(0.05)
	check(st.count_of(GameData.Item.STONE) == GatherDB.CARRY_MAX and W[0].carrying == -1 and W[0].carry_n == 1, "倉庫へ袋の中身がすべて入り、手ぶらに戻る")
	# 残量が尽きるまで
	_reset()
	W[0].tools["mine"] = GameData.Item.PICKAXE
	var small := _point("rock", 640.0, 2)
	ai = W[0].ai
	ai._try_start(GameData.Job.GATHER)
	ai._set_state(CharacterAI.State.GATHER)
	guard = 0
	while ai.state == CharacterAI.State.GATHER and guard < 2000:
		guard += 1
		W[0].position = Vector2(small.position.x - 40.0, small.position.y)
		ai.tick(0.05)
	check(small.remaining == 0 and W[0].carry_n >= 1 and ai.state == CharacterAI.State.MOVE_TO_STORAGE, "残量が尽きたら、掘れた分だけ持って倉庫へ向かう（%d個）" % W[0].carry_n)
	check(small.frame() == 2 and small.claimed_by == null, "尽きた採取ポイントは「枯れた」絵になり、予約も外れる")
	# 副産物
	_reset()
	W[0].tools["mine"] = GameData.Item.ADV_PICK
	W[0].ranks[GameData.Field.GATHERER] = 6
	var big := _point("vein", 640.0, 300)
	big.max_amount = 300
	ai = W[0].ai
	ai.bag_limit = 100
	W[0].ai.res = big
	big.claimed_by = W[0]
	ai._set_state(CharacterAI.State.GATHER)
	guard = 0
	while ai.state == CharacterAI.State.GATHER and guard < 4000 and W[0].carry_n < 90:
		guard += 1
		W[0].position = Vector2(big.position.x - 40.0, big.position.y)
		ai.tick(0.05)
	var got_stone: int = W[0].carry_bonus.get(GameData.Item.STONE, 0)
	check(got_stone > 10 and got_stone < W[0].carry_n, "高性能ピッケルで鉱床を掘ると、副産物の石が手に入る（鉄鉱石%d個に対して石%d個）" % [W[0].carry_n, got_stone])
	W[0].ranks[GameData.Field.GATHERER] = 3
	# 副産物も一緒に倉庫へ
	W[0].floor_i = 1
	W[0].position = st.access_point() + W[0].slot_offset
	W[0].target = W[0].position
	var ore_n: int = W[0].carry_n
	st.capacity_bonus += 10000                             # 積載量を十分広げておく（枠ではなく重さで管理するため）
	ai._release_task()
	ai._set_state(CharacterAI.State.MOVE_TO_STORAGE)
	guard = 0
	while ai.state != CharacterAI.State.SEARCH and guard < 200:
		guard += 1
		ai.tick(0.05)
	check(st.count_of(GameData.Item.IRON_ORE) == ore_n and st.count_of(GameData.Item.STONE) == got_stone and W[0].carry_bonus.is_empty(), "副産物も、袋の中身と一緒に倉庫へ入る")
	# 天候で屋外に出られなくなったら、掘った分を持って戻る
	_reset()
	W[0].tools["chop"] = GameData.Item.AXE
	var tr := _point("tree", 640.0, 12)
	ai = W[0].ai
	ai._try_start(GameData.Job.GATHER)
	ai._set_state(CharacterAI.State.GATHER)
	guard = 0
	while W[0].carrying < 0 and guard < 1000:
		guard += 1
		W[0].position = Vector2(tr.position.x - 40.0, tr.position.y)
		ai.tick(0.05)
	main.director.trigger("sandstorm", false)
	main.director.set_stance("sandstorm", "halt")
	ai.tick(0.05)
	check(main.director.outdoor_blocked() and ai.state == CharacterAI.State.MOVE_TO_STORAGE and W[0].carry_n >= 1 and tr.claimed_by == null,
			"砂嵐で屋外に出られなくなったら、掘った分を持って倉庫へ戻る（%d個）" % W[0].carry_n)
	main.director.active.clear()
	# 襲撃で敵が拠点を攻撃している間、戦闘担当は採取を切り上げる（掘った分は倉庫へ。何もなければすぐ迎撃へ）
	_reset()
	W[0].tools["chop"] = GameData.Item.AXE
	W[1].tools["chop"] = GameData.Item.AXE
	var tr2 := _point("tree", 640.0, 12)
	var tr3 := _point("tree", 700.0, 12)
	ai = W[0].ai
	ai._try_start(GameData.Job.GATHER)
	ai._set_state(CharacterAI.State.GATHER)
	var ai1: CharacterAI = W[1].ai
	ai1._try_start(GameData.Job.GATHER)
	ai1._set_state(CharacterAI.State.GATHER)
	guard = 0
	while W[0].carrying < 0 and guard < 1000:
		guard += 1
		W[0].position = Vector2(tr2.position.x - 40.0, tr2.position.y)
		W[1].position = Vector2(tr3.position.x - 40.0, tr3.position.y)
		ai.tick(0.05)
		if ai1.state == CharacterAI.State.GATHER and W[1].carrying < 0:
			ai1.tick(0.05)
	W[1].carrying = -1
	W[1].carry_n = 1
	ai1.gather_ev = {}
	tr3.remaining = 12
	main.director.trigger("raid_scorpion", false)
	for e in main.enemies_root.get_children():
		e.position.x = e.hold_x - 1.0
	check(main.director.raid_pressing(), "（準備）敵が拠点を攻撃している")
	W[0].priorities[GameData.Job.COMBAT] = 3
	W[1].priorities[GameData.Job.COMBAT] = 3
	ai.tick(0.05)
	check(ai.state == CharacterAI.State.MOVE_TO_STORAGE and tr2.claimed_by == null and W[0].carry_n >= 1, "袋に掘った分がある戦闘担当は、採取を切り上げて倉庫へ向かう")
	ai1.tick(0.05)
	check(ai1.state == CharacterAI.State.SEARCH and tr3.claimed_by == null, "何も掘っていない戦闘担当は、すぐ採取をやめて迎撃へ向かえる")
	W[2].priorities[GameData.Job.COMBAT] = 0
	main.director.active.clear()
	# 遠征に出るとき、袋の中身は倉庫へ戻る
	_reset()
	W[1].carrying = GameData.Item.WOOD
	W[1].carry_n = 3
	W[1].carry_bonus = {GameData.Item.BONE: 1}
	W[1].ai.state = CharacterAI.State.MOVE_TO_STORAGE
	W[1].depart()
	check(st.count_of(GameData.Item.WOOD) == 3 and st.count_of(GameData.Item.BONE) == 1 and W[1].carry_n == 1, "遠征に出る仲間の袋（複数個・副産物）は、倉庫へ戻る")
	W[1].arrive(20.0)
	# 積載量: 袋を運んでいる分も空き枠に数える
	_reset()
	st.add_item(GameData.Item.WOOD, st.quota_of(GameData.Item.WOOD) - 3)
	W[2].carrying = GameData.Item.WOOD
	W[2].carry_n = 3
	W[2].ai.state = CharacterAI.State.MOVE_TO_STORAGE
	_point("tree", 640.0, 10)
	W[0].tools["chop"] = GameData.Item.AXE
	check(not W[0].ai._try_start(GameData.Job.GATHER), "運んでいる袋で枠がいっぱいになるなら、木は採りに行かない（積載量との連携）")
	W[2].carrying = -1
	W[2].ai.state = CharacterAI.State.SEARCH

	print("== 道具の割り当て ==")
	_reset()
	# 素手の状態。倉庫にハンマー1つ → 効果がいちばん大きい仲間（回収ランクの高いネズ吉）へ
	st.add_item(GameData.Item.HAMMER, 1)
	main.manage_tools()
	check(W[0].tools.get("mine", -1) == GameData.Item.HAMMER and st.count_of(GameData.Item.HAMMER) == 0, "ハンマーは、回収ランクの高い仲間（%s）へ自動で持たされる" % W[0].char_name)
	# 上位の道具ができたら持ち替え、古い道具は次の仲間へ回る
	st.add_item(GameData.Item.PICKAXE, 1)
	main.manage_tools()
	check(W[0].tools["mine"] == GameData.Item.PICKAXE, "鉄製ピッケルが来たら、持ち替える")
	var passed := 0
	for w in W:
		if w != W[0] and w.tools.get("mine", -1) == GameData.Item.HAMMER:
			passed += 1
	check(passed == 1 and st.count_of(GameData.Item.HAMMER) == 0, "古いハンマーは、道具のない次の仲間へ回る（お下がり）")
	# 自動をOFFにすると、勝手には持たせない
	st.add_item(GameData.Item.AXE, 1)
	main.tool_auto = false
	main.manage_tools()
	check(st.count_of(GameData.Item.AXE) == 1 and W[0].tools.get("chop", -1) < 0, "自動割り当てがOFFなら、勝手には持たせない")
	# 手動: 持たせる・外す
	check(main.equip_tool(W[2], GameData.Item.AXE) and W[2].tools["chop"] == GameData.Item.AXE and st.count_of(GameData.Item.AXE) == 0, "手動で道具を持たせられる")
	st.add_item(GameData.Item.IRON_AXE, 1)
	main.equip_tool(W[2], GameData.Item.IRON_AXE)
	check(W[2].tools["chop"] == GameData.Item.IRON_AXE and st.count_of(GameData.Item.AXE) == 1, "持たせ替えると、前の道具は倉庫へ戻る")
	main.unequip_tool(W[2], "chop")
	check(W[2].tools.get("chop", -1) < 0 and st.count_of(GameData.Item.IRON_AXE) == 1, "外すと倉庫へ戻る")
	check(not main.equip_tool(W[1], GameData.Item.ADV_PICK), "倉庫にない道具は持たせられない")
	# 回収をしない仲間には持たせない
	_reset()
	W[0].priorities[GameData.Job.GATHER] = 0
	st.add_item(GameData.Item.HAMMER, 1)
	main.manage_tools()
	check(W[0].tools.get("mine", -1) < 0 and W[1].tools.get("mine", -1) == GameData.Item.HAMMER, "回収の優先度が0の仲間には、道具を持たせない")
	W[0].priorities[GameData.Job.GATHER] = 5

	print("== 道具の加工（作る意味があるときだけ作る） ==")
	_reset()
	for r in GameData.RECIPES:
		main.recipe_priority[r["id"]] = 0
	main.recipe_priority["tool_hammer"] = 2
	main.recipe_priority["tool_pick"] = 1
	st.add_item(GameData.Item.STONE, 4)
	st.add_item(GameData.Item.WOOD, 4)
	check(main.tool_wanted(GameData.Item.HAMMER) and main.choose_recipe().get("id", "") == "tool_hammer", "みんな素手なら、簡易ハンマーを作る")
	main.processor.reserve(GameData.recipe_by_id("tool_hammer"))
	check(not main.tool_wanted(GameData.Item.HAMMER), "作りかけ（運搬中）があるときは、重ねて作らない")
	main.processor.incoming.clear()
	st.add_item(GameData.Item.HAMMER, 1)
	check(not main.tool_wanted(GameData.Item.HAMMER), "倉庫に予備があるときは作らない")
	st.inventory.counts[GameData.Item.HAMMER] = 0
	for w in W:
		w.tools["mine"] = GameData.Item.PICKAXE
	check(not main.tool_wanted(GameData.Item.HAMMER), "全員がもっと良い道具を持っていたら、ハンマーは作らない")
	check(main.choose_recipe().get("id", "") != "tool_hammer", "…加工の選択にも出てこない")
	st.add_item(GameData.Item.IRON, 2)
	check(not main.tool_wanted(GameData.Item.PICKAXE), "全員が鉄製ピッケルを持っていたら、もう作らない")
	W[0].ranks[GameData.Field.GATHERER] = 6
	W[0].level = 12
	check(main.tool_wanted(GameData.Item.ADV_PICK), "回収ランクの高い仲間には、高性能ピッケルが更新になる → 作る意味がある")
	W[0].ranks[GameData.Field.GATHERER] = 3
	W[0].level = 3
	# 加工した道具が、倉庫を経由して仲間に渡る
	_reset()
	main.processor.output.append(GameData.Item.HAMMER)
	W[2].carrying = main.processor.take_output()
	W[2].ai._set_state(CharacterAI.State.STORE)
	W[2].ai.timer = 0.0
	W[2].ai.tick(0.1)
	check(st.count_of(GameData.Item.HAMMER) == 1, "加工した道具は倉庫に入る")
	main.manage_tools()
	check(st.count_of(GameData.Item.HAMMER) == 0 and W[0].tools.get("mine", -1) == GameData.Item.HAMMER, "そのあと、仲間に持たされる")

	print("== 画面 ==")
	_reset()
	st.add_item(GameData.Item.HAMMER, 1)
	st.add_item(GameData.Item.ADV_PICK, 1)
	main.manage_tools()
	var pol: PolicyUI = main.policy
	pol.toggle()
	for page in [0, 1, 2]:
		pol._page = page
		pol._rebuild()
	check(pol._page == 2, "運営の方針に「採取の道具」のページが出る")
	main.tool_auto = false
	pol._rebuild()
	main.tool_auto = true
	pol.toggle()
	pol._page = 0
	# 採取中の描画（道具が手に見える）
	_reset()
	var dp := _point("rock", 640.0, 10)
	W[0].tools["mine"] = GameData.Item.HAMMER
	W[0].ai._try_start(GameData.Job.GATHER)
	W[0].ai._set_state(CharacterAI.State.GATHER)
	W[0].pose = "pick"
	W[0].queue_redraw()
	dp.queue_redraw()
	await process_frame
	check(true, "採取ポイントと、道具を持った仲間が描画できる")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)

	print("== 落ちている物（従来の方式）との共存 ==")
	_reset()
	var loose := ResourceNode.new()
	loose.game = main
	loose.item = GameData.Item.MEAT
	loose.position = Vector2(700.0, (GameData.GROUND_Y_MIN + GameData.GROUND_Y_MAX) / 2.0)
	main.resources_root.add_child(loose)
	check(W[0].ai._try_start(GameData.Job.GATHER) and W[0].ai.res == loose, "敵の落とし物など、落ちている物は1個ずつ拾う")
	W[0].ai._release_task()
	W[0].ai._set_state(CharacterAI.State.SEARCH)

	print("== 長く動かす（ゲーム内約8分。放置） ==")
	_reset()
	st.add_item(GameData.Item.FOOD, 8)
	st.add_item(GameData.Item.FUEL, 2)
	st.add_item(GameData.Item.REPAIR_KIT, 2)
	st.add_item(GameData.Item.HAMMER, 1)
	st.add_item(GameData.Item.AXE, 1)
	main.director.enabled = true
	Engine.time_scale = 8.0
	var t_end := Time.get_ticks_msec() + 60000
	var stuck := 0
	var spawned_max := 0
	var min_count := 0
	while Time.get_ticks_msec() < t_end and not main.game_over:
		await process_frame
		var pts := 0
		for c in main.resources_root.get_children():
			if c is GatherPoint:
				pts += 1
				if c.claimed_by != null:
					var owner = c.claimed_by
					if not is_instance_valid(owner) or owner.ai.res != c:
						# 掘ったあと予約が外れる直前など、一瞬のずれは許す（次のフレームでも続いたら数える）
						stuck += 1
		spawned_max = maxi(spawned_max, pts)
		for it in GameData.Item.values():
			min_count = mini(min_count, st.count_of(it))
	Engine.time_scale = 1.0
	paused = false
	var tool_txt := ""
	for w in W:
		tool_txt += "%s[%s/%s] " % [w.char_name, GatherDB.tool_def(int(w.tools.get("mine", -1)))["name"], GatherDB.tool_def(int(w.tools.get("chop", -1)))["name"]]
	print("       走行 %.1f km・回収%d 加工%d・捨てた%d・同時に見えた採取ポイント 最大%d・道具 %s" % [main.director.distance / 2500.0, main.total_gathered,
			main.processor.total_done, main.total_wasted, spawned_max, tool_txt])
	check(main.total_gathered > 8, "採取ポイントから、回収が回り続ける（累計 %d 個）" % main.total_gathered)
	check(min_count >= 0, "倉庫の個数がマイナスにならない")
	check(stuck < 20, "予約したまま動かない採取ポイントが残らない（ずれ %d 回）" % stuck)
	if main.game_over:
		print("       （途中で車体が壊れてゲームオーバーになった。出来事を本来の頻度で起こしているため）")
