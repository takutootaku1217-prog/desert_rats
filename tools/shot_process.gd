extends SceneTree
## 加工設備の見た目（文字ではなく、絵と動きで「いま何が起きているか」が分かるか）を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 --fixed-fps 60 -s res://tools/shot_process.gd -- <出力フォルダ>
## 出力: p1_idle（待機）／p2_queued（材料が待っている）／p3_drop（材料が投入口へ落ちる）／p4_work（加工中。湯気・進み具合）／
##   p5_fuel（燃料待ち）／p6_done（完成のきらり・弾む完成品）／p7_waiting（完成品が取りに来るのを待つ）／p_sheet（全部を並べた拡大）。

var main
var dir := "."
var crops: Array = []
var labels: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260927)
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.director.enabled = false
	main.target_speed = 0.0
	for w in main.workers:
		w.set_process(false)
		for j in GameData.job_list():
			w.priorities[j] = 0
		w.position = Vector2(140.0, GameData.deck_y(1))                # 撮影の邪魔にならない所へ
		w.queue_redraw()
	var P: BaseProcessor = main.processor
	var cook: Dictionary = GameData.recipe_by_id("cook").duplicate()
	await _frames(8)
	await _shot("p1_idle", "待機")
	# 材料が待っている
	P.orders.append(cook.duplicate())
	P.orders.append(GameData.recipe_by_id("firewood").duplicate())
	await _frames(8)
	await _shot("p2_queued", "材料が待っている")
	P.orders.clear()
	# 材料が投入口へ落ちる（受け取った直後）
	P.receive(cook.duplicate())
	await _frames(12)
	await _shot("p3_drop", "材料が落ちる")
	P.orders.clear()
	# 加工中: 機械が動き、湯気が出て、作っている物のアイコンが満ちていく
	P.current = cook.duplicate()
	P.progress = float(cook["time"]) * 0.55
	for i in 40:
		P._last_work_ms = Time.get_ticks_msec()
		await process_frame
	await _shot("p4_work", "加工中（進み 55%）")
	# 燃料待ち
	P.current = {}
	P.progress = 0.0
	var smelt: Dictionary = GameData.recipe_by_id("smelt").duplicate() if not GameData.recipe_by_id("smelt").is_empty() else cook.duplicate()
	smelt["tank_fuel"] = 999.0
	P.orders.append(smelt)
	P.waiting_fuel = true
	await _frames(20)
	await _shot("p5_fuel", "燃料待ち")
	P.orders.clear()
	P.waiting_fuel = false
	# 完成: きらり・弾む完成品
	P.current = cook.duplicate()
	P.progress = float(cook["time"]) - 0.02
	P._last_work_ms = Time.get_ticks_msec()
	P.work(0.05, func(f): return 1.0)
	await _frames(6)
	await _shot("p6_done", "完成（きらり）")
	# 完成品が待っている（揺れて目立つ）
	await _frames(40)
	await _shot("p7_waiting", "完成品が待っている")
	# 全部を並べた拡大
	var cw: int = crops[0].get_width()
	var ch: int = crops[0].get_height()
	var cols := 4
	var rows := int(ceil(float(crops.size()) / float(cols)))
	var sheet := Image.create(cols * (cw + 8) + 8, rows * (ch + 8) + 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.12))
	for i in crops.size():
		sheet.blit_rect(crops[i], Rect2i(0, 0, cw, ch), Vector2i(8 + (i % cols) * (cw + 8), 8 + (i / cols) * (ch + 8)))
	sheet.save_png("%s/p_sheet.png" % dir)
	print("saved ", labels)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## 加工設備のまわりを撮って保存し、拡大した切り出しを覚えておく
func _shot(name: String, label: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	var pos: Vector2 = main.processor.global_position
	var r := Rect2i(int(pos.x) - 90, int(pos.y) - 170, 300, 200)
	var c := img.get_region(r)
	c.resize(c.get_width() * 2, c.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crops.append(c)
	labels.append(label)
