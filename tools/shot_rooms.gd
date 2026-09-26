extends SceneTree
## 部屋の変更を、実際のゲーム画面（ウィンドウ表示）で撮る。実行（ウィンドウが開く）:
##   Godot --path . --windowed --resolution 1280x720 -s res://tools/shot_rooms.gd -- <出力フォルダ>
## 段階（画面のボタンを押して部屋を変え、車体の見た目が変わるところを撮る）:
##   r0 最初 → r1 部屋の変更の画面（下の階・左を選択）→ r2 「壊して空ける」を押したあと → r3 空き部屋（車体）→
##   r4 医務室を建てた → r5 食堂に建て替えた → r6 加工室を下の階へ移した（加工設備が下へ）→ r7 寝室を上の階・左へ移した（ベッドも一緒に）→
##   r8 倉庫を下の階・左へ移した（別のゲームで）→ r9 上の階の区画の一覧。ワークベンチ・ベッドは最初から建ててある状態で撮る。

var main
var dir := "."


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fresh() -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.director.enabled = false


func _give(rtype: String) -> void:
	var c: Dictionary = Rooms.TYPES[rtype]["cost"]
	for it in c:
		main.storage.add_item(it, c[it])


## 画面の右の一覧で、その部屋の「建てる」を押す
func _click(slot: String, rtype: String) -> void:
	var ui: BaseUI = main.room_ui
	ui.select_slot(slot)
	var order: Array = []
	for t in Rooms.TYPE_ORDER:
		if Rooms.can_place(t, slot):
			order.append(t)
	var rows: Array = []
	for c in ui._right.get_children():
		if c is PanelContainer:
			rows.append(c)
	var h: Node = rows[order.find(rtype)].get_child(0)
	var b: Button = h.get_child(h.get_child_count() - 1)
	print("click ", slot, " ", rtype, " -> ", b.text, " disabled=", b.disabled)
	b.pressed.emit()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if args.size() > 0 else "."
	seed(20260927)
	await _fresh()
	var ui: BaseUI = main.room_ui
	await create_timer(1.5).timeout
	_shot("r0_start")
	ui.open()
	ui.select_slot("l1")
	await _frames(3)
	_shot("r1_ui_l1")
	_click("l1", "empty")
	await _frames(3)
	_shot("r2_ui_after_empty")
	ui.close()
	await create_timer(0.4).timeout
	_shot("r3_world_l1_empty")
	_give("infirmary")
	ui.open()
	_click("l1", "infirmary")
	ui.close()
	await create_timer(0.4).timeout
	_shot("r4_world_infirmary")
	_give("mess")
	ui.open()
	_click("l1", "mess")
	await _frames(3)
	_shot("r5_ui_mess")
	ui.close()
	await create_timer(0.4).timeout
	_shot("r5_world_mess")
	_give("workshop")
	main.room_ui.open()
	_click("l1", "workshop")
	ui.close()
	await create_timer(0.4).timeout
	_shot("r6_world_workshop_moved")
	await create_timer(2.0).timeout
	_give("bedroom")
	ui.open()
	_click("u1", "bedroom")
	ui.close()
	await create_timer(0.4).timeout
	_shot("r7_world_bedroom_moved")
	await create_timer(3.0).timeout
	_shot("r7b_world_later")
	# 別のゲーム: 倉庫を移す
	await _fresh()
	await create_timer(0.5).timeout
	main.build_room("l1", "empty")
	_give("storage")
	ui = main.room_ui
	ui.open()
	_click("l1", "storage")
	ui.close()
	await create_timer(0.4).timeout
	_shot("r8_world_storage_moved")
	await create_timer(2.0).timeout
	ui.open()
	ui.select_slot("u1")
	await _frames(3)
	_shot("r9_ui_u1")
	quit()
