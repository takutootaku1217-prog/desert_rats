extends SceneTree
## 外装・内装の切り替えと、外装の見た目を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_view.gd -- <出力フォルダ>
## 段階: v0 内装（最初）→ v1 外装（最初。簡素）→ v2 切り替えの途中（消えていく）→ v3 外装（設備を建てたあと）→
##   v4 外装（中盤）→ v5 外装（後半・部屋を変えた。窓の色・看板・換気管・燃料の口）→ v6 同じ拠点の内装（屋根が外装と同じ）→ v7 外装（機関室を壊した）。

var main
var dir := "."


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fresh(all_facilities: bool) -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = all_facilities
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.director.enabled = false


func _give(rtype: String) -> void:
	var c: Dictionary = Rooms.TYPES[rtype]["cost"]
	for it in c:
		main.storage.add_item(it, c[it])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260928)
	await _fresh(false)
	await create_timer(1.2).timeout
	_shot("v0_interior_start")
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	await create_timer(1.0).timeout
	_shot("v1_exterior_start")
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
	await _frames(2)
	main.base_view.set_mode(BaseView.Mode.EXTERIOR)               # 演出つきの切り替え
	await create_timer(0.07).timeout
	_shot("v2_fade_out")
	await create_timer(0.5).timeout
	# 設備を建てたあと（ワークベンチ・ベッド）、荷物が増えた段階
	await _fresh(true)
	main.director.distance = 7000.0
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	await create_timer(1.0).timeout
	_shot("v3_exterior_built")
	main.director.distance = 13000.0
	await create_timer(0.4).timeout
	_shot("v4_exterior_mid")
	# 後半 + 部屋を変える（機関室 → 医務室、倉庫はそのまま、上階・左を食堂へ… 加工室は下へ移す）
	main.director.distance = 46000.0
	main.build_room("l1", "empty")
	_give("infirmary")
	main.build_room("l1", "infirmary")
	_give("workshop")
	main.build_room("l1", "workshop")                              # 加工室が下へ。上階・左が空き部屋
	_give("mess")
	main.build_room("u1", "mess")
	await create_timer(0.6).timeout
	_shot("v5_exterior_late_rooms")
	main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
	await create_timer(0.8).timeout
	_shot("v6_interior_same_base")
	# 機関室を壊したあと（燃料の口が別の場所へ）＋ 医務室の看板
	await _fresh(true)
	main.director.distance = 20000.0
	main.build_room("l1", "empty")
	_give("infirmary")
	main.build_room("l1", "infirmary")
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	await create_timer(0.8).timeout
	_shot("v7_exterior_no_engine")
	quit()
