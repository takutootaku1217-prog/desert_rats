extends SceneTree
## 基本ループの各段階を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_loop.gd -- <出力フォルダ> [倍速]
## 段階: 拠点が移動 → 資源を発見 → 掘る（回収）→ 拠点へ運ぶ → 素材棚に収納 → 加工設備へ運ぶ → 加工中 → 加工品を収納。
## 出来事は止めて、基本ループだけを見る。すべて撮れるか、ゲーム内5分たったら終わる。

var main


func _shot(dir: String, name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "."
	var scale: float = float(args[1]) if args.size() > 1 else 3.0
	seed(20260926)
	FacilityDB.start_all = true      # 設備は最初から全部ある状態で確かめる（設備の建設は test_build.gd）
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	Engine.time_scale = scale
	var W: Array = main.workers
	var P: BaseProcessor = main.processor
	var done := {}
	var since := {}
	var last := {}
	var want := ["s1_move", "s2_notice", "s3_gather", "s4_carry", "s5_store", "s6_haul", "s7_process", "s8_product"]
	while main.director.elapsed < 300.0 and done.size() < want.size():
		await process_frame
		var t: float = main.director.elapsed
		if t > 6.0 and not done.has("s1_move") and main.scroll_speed > 0.0:
			done["s1_move"] = true
			_shot(dir, "s1_move")
		for w in W:
			var s: int = w.ai.state
			if last.get(w, -1) != s:
				last[w] = s
				since[w] = t
			var held: float = t - float(since[w])
			if s == CharacterAI.State.NOTICE and not done.has("s2_notice"):
				done["s2_notice"] = true
				_shot(dir, "s2_notice")
			elif s == CharacterAI.State.GATHER and held > 1.2 and not done.has("s3_gather"):
				done["s3_gather"] = true
				_shot(dir, "s3_gather")
			elif s == CharacterAI.State.MOVE_TO_STORAGE and w.carrying in GameData.RAW_ITEMS and held > 0.8 and not done.has("s4_carry"):
				done["s4_carry"] = true
				_shot(dir, "s4_carry")
			elif s == CharacterAI.State.STORE and w.carrying in GameData.RAW_ITEMS and not done.has("s5_store"):
				done["s5_store"] = true
				_shot(dir, "s5_store")
			elif s == CharacterAI.State.HAUL_MOVE and held > 0.8 and not done.has("s6_haul"):
				done["s6_haul"] = true
				_shot(dir, "s6_haul")
			elif s == CharacterAI.State.PROCESS and not P.current.is_empty() and held > 1.0 and not done.has("s7_process"):
				done["s7_process"] = true
				_shot(dir, "s7_process")
			elif s == CharacterAI.State.STORE and (w.carrying in GameData.PRODUCT_ITEMS or w.carrying in GameData.TOOL_ITEMS) and not done.has("s8_product"):
				done["s8_product"] = true
				_shot(dir, "s8_product")
	Engine.time_scale = 1.0
	await create_timer(0.3).timeout
	var missing: Array = []
	for k in want:
		if not done.has(k):
			missing.append(k)
	print("撮れた: %d / %d %s（ゲーム内 %.0f 秒）" % [done.size(), want.size(), ("未達: " + ",".join(PackedStringArray(missing))) if not missing.is_empty() else "", main.director.elapsed])
	quit()
