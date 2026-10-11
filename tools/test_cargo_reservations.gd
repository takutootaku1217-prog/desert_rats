extends SceneTree
## 共有重量の予約と、解体予測／実収納の一致。初期条件はこの診断内だけで変更する。
var fails := 0
var main
var st: BaseStorage

func check(ok: bool, msg: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", msg])
	if not ok:
		fails += 1

func point(kind: String) -> GatherPoint:
	var p := GatherPoint.new()
	p.setup(main, kind)
	p.position = Vector2(650, 610)
	main.resources_root.add_child(p)
	return p

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for w in main.workers:
		w.set_process(false)
		w.ai._release_task()
		w.carrying = -1
		w.carry_bonus.clear()
	for r in main.resources_root.get_children():
		r.free()
	main.director.enabled = false
	main.scroll_speed = 0.0
	st = main.storage
	st.inventory.counts.clear()
	st.capacity_bonus = 24 - CargoDB.CAPACITY
	var wood := point("tree")
	var rock := point("rock")
	var a = main.workers[0]
	var b = main.workers[1]
	wood.claimed_by = a
	wood.reserved = 4 # 木材4個=重量16、残り8には石1個だけ
	a.ai.res = wood
	b.tools["mine"] = GameData.Item.PICKAXE
	check(b.ai._try_start(GameData.Job.GATHER), "残り重量8で石の採取を開始できる")
	check(b.ai.res == rock and b.ai.bag_limit == 1, "異種予約を引いた袋サイズは石1個")
	b.ai._release_task()
	wood.reserved = 6
	check(not main.has_room_for(rock, main.gather_room()), "木材6個が全重量を予約すると石は回収しない")
	check(not main.has_room_for(wood, main.gather_room()), "同品目の予約も引く")
	wood.claimed_by = null
	a.ai.res = null
	a.carrying = GameData.Item.WOOD
	a.carry_n = 6
	a.ai._set_state(CharacterAI.State.MOVE_TO_STORAGE)
	check(not main.has_room_for(rock, main.gather_room()), "倉庫へ運搬中の異種重量も引く")
	st.enforce = false
	check(main.has_room_for(rock, main.gather_room()), "制限なしでは予約で採取を止めない")
	st.enforce = true
	a.carrying = -1
	var match_all := true
	for species in GameData.CREATURES:
		for room in range(0, 25):
			st.inventory.counts.clear()
			st.capacity_bonus = room - CargoDB.CAPACITY
			var predicted := st.drop_fit(species)
			if room == 0:
				check(st.inventory.counts.is_empty(), "予測は在庫を変更しない")
			st.butcher(species)
			var total := 0
			var stored := 0
			for it in GameData.CREATURES[species]["drops"]:
				total += int(GameData.CREATURES[species]["drops"][it])
				stored += st.count_of(it)
			if not is_equal_approx(predicted, float(stored) / total):
				print("  mismatch %s room=%d predicted=%.3f actual=%d/%d" % [species, room, predicted, stored, total])
				match_all = false
	check(match_all, "全生物・空き重量0〜24で予測と逐次解体の収納割合が一致")
	st.inventory.counts.clear()
	st.capacity_bonus = 2 - CargoDB.CAPACITY
	check(not main.hunt_has_room("hump"), "重量2ではhumpの1/6だけ収納、50%基準に届かず狩らない")
	st.enforce = false
	check(st.drop_fit("hump") == 1.0, "制限なしの解体予測は100%")
	print("== 結果: %d 件失敗 ==" % fails)
	quit(1 if fails else 0)
