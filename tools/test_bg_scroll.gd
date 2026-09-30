extends SceneTree
## 背景・出現・消滅・重なり順の自己診断。GPT系のQA調査（背景描画・カメラワークのバグ調査報告書、2026-09-30）で
## 指摘された不具合の確認・再発防止用。実行:
##   Godot --headless --path . -s res://tools/test_bg_scroll.gd
## 確かめる:
##   BG-01 背景のタイルが、カメラの position を考えずに常に2枚しか並べていなかった（左右にパンすると灰色が見えた）
##   BG-03 資源・生物・敵の出現位置と、消える境界が、カメラなし（position=0）を前提にした固定の世界座標のままだった
##   BG-04 資源・生物・敵・仲間が、木の順番（ツリー順）でしか重なり順を決めておらず、足元の位置と逆転することがあった
## BG-02（層の隙間の灰色）と CAM-01/CAM-02（クリック判定）は、それぞれ world_scroll.gd の保険の下地と、
## tools/test_camera.gd の _pick_worker_at の確認でカバーする（見た目は tools/shot_bg_scroll.gd で確認）。

var fails := 0
var main


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	seed(20261001)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _run() -> void:
	print("-- BG-01: 背景タイルの範囲（world_scroll.gd の WorldScroll.tile_range） --")
	# カメラなし（これまでと同じ見え方）: off=0 のときは1枚、off>0 のときは2枚（これまでの挙動と一致するはず）
	var r0 := WorldScroll.tile_range(0.0, 0.0, 1280.0)
	check(r0 == Vector2i(0, 0), "カメラ位置0・off=0 のときは1枚だけ（これまでと同じ。k=%s）" % str(r0))
	var r0b := WorldScroll.tile_range(0.0, 640.0, 1280.0)
	check(r0b == Vector2i(0, 1), "カメラ位置0・off>0 のときは2枚（これまでと同じ。k=%s）" % str(r0b))
	# 報告書の再現条件そのもの: 左パンで目標左端 -190、右パンで目標左端 360 でも、見えている範囲を過不足なく覆うか
	for cam_left in [-190.0, 360.0, -1200.0, 5000.0]:
		for off in [0.0, 1.0, 639.9, 1279.9]:
			var k := WorldScroll.tile_range(cam_left, off, 1280.0)
			var covered_from: float = -off + float(k.x) * 1280.0
			var covered_to: float = -off + float(k.y + 1) * 1280.0
			check(covered_from <= cam_left + 0.01 and covered_to >= cam_left + 1280.0 - 0.01,
				"cam_left=%s off=%s: 見えている範囲 [%s, %s) を過不足なく覆う（タイル [%s,%s)）" %
				[cam_left, off, cam_left, cam_left + 1280.0, covered_from, covered_to])

	print("-- BG-03: 出現位置がカメラに追従する（main.spawn_x / camera_left） --")
	main.camera.position.x = 0.0
	check(is_equal_approx(main.spawn_x(), main.SPAWN_X), "カメラ位置0では、これまでと同じ出現位置（%.1f）" % main.SPAWN_X)
	main.camera.position.x = 360.0
	check(is_equal_approx(main.spawn_x(), main.SPAWN_X + 360.0), "カメラが右へ360動くと、出現位置も360右へ動く（画面のすぐ外に出る、が保たれる）")
	var before_res: int = main.resources_root.get_child_count()
	main._spawn_ground_resource()
	var added_res = main.resources_root.get_child(main.resources_root.get_child_count() - 1)
	check(main.resources_root.get_child_count() == before_res + 1, "資源が1つ増える")
	check(absf(added_res.position.x - main.spawn_x()) < 0.01, "増えた資源は、いまのカメラから見て画面のすぐ外（spawn_x）に出る")
	var before_c: int = main.creatures_root.get_child_count()
	main._spawn_creature()
	var added_c = main.creatures_root.get_child(main.creatures_root.get_child_count() - 1)
	check(absf(added_c.position.x - main.spawn_x()) < 0.01, "生物も、いまのカメラから見て画面のすぐ外に出る")
	main.camera.position.x = 0.0

	print("-- BG-03: 消える境界もカメラに追従する（scripts/resource.gd・scripts/creature.gd） --")
	main.camera.position.x = 400.0                         # カメラが右へ大きくパンしている状況を再現
	var r := ResourceNode.new()
	r.game = main
	r.item = GameData.Item.WOOD
	r.position = Vector2(main.camera_left() - 30.0, GameData.GROUND_Y_MIN)   # いまのカメラからはまだ画面内（左端から-30 ではなく、カメラ基準で-30）
	main.resources_root.add_child(r)
	r._process(0.0)
	check(is_instance_valid(r), "カメラが右へパンしていても、カメラの可視範囲内（左端の少し内側）の資源は消えない（以前は固定 -60 で判定していたため、ここで誤って消えていた＝BG-03）")
	r.position.x = main.camera_left() - 61.0                # カメラ基準で、本当に画面外（左に60px超）
	r._process(0.0)
	await process_frame     # queue_free は次のアイドル処理まで実際には消えない
	check(not is_instance_valid(r), "カメラ基準で本当に画面外（左）まで流れたら、これまでどおり消える")

	var c := Creature.new()
	c.setup(main, "hare")
	c.position = Vector2(main.camera_left() + 1300.0, GameData.GROUND_Y_MIN)   # カメラ基準ではまだ画面内寄り（固定境界1340なら旧仕様でも消えないが、境界の一貫性を見る）
	main.creatures_root.add_child(c)
	c._process(0.0)
	check(is_instance_valid(c), "生物も、カメラ基準の範囲内では消えない")
	c.position.x = main.camera_left() + 1341.0
	c._process(0.0)
	await process_frame     # queue_free は次のアイドル処理まで実際には消えない
	check(not is_instance_valid(c), "生物も、カメラ基準で本当に範囲外まで出たら消える")
	main.camera.position.x = 0.0

	print("-- BG-04: 資源・生物・敵・仲間が、足元のY位置で前後判定される（y_sort_enabled） --")
	check(main.ground_sort != null and main.ground_sort.y_sort_enabled, "資源・生物・敵・仲間の共通の親（ground_sort）で y_sort が有効")
	check(main.resources_root.y_sort_enabled, "Resources も y_sort が有効（下の階層まで連動させないと、箱単位でしか揃わない）")
	check(main.creatures_root.y_sort_enabled, "Creatures も y_sort が有効")
	check(main.enemies_root.y_sort_enabled, "Enemies も y_sort が有効")
	check(main.resources_root.get_parent() == main.ground_sort, "Resources は ground_sort の子（MobileBase より後ろという、これまでの前後関係はそのまま保たれる）")
	var workers_root: Node = main.workers[0].get_parent()
	check(workers_root.y_sort_enabled and workers_root.get_parent() == main.ground_sort, "Workers も ground_sort の子で y_sort が有効")
