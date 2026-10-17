extends SceneTree
## 仲間管理の実Godot描画を3タブで撮る。状態と運搬中の物資だけを固定注入し、UIの見た目を比較する。
## Godot --headless --path . -s res://tools/shot_crew_detail.gd -- <出力フォルダ>

var main
var dir := "."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if not args.is_empty() else "."
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.director.enabled = false
	main.target_speed = 0.0
	main.scroll_speed = 0.0
	for worker in main.workers:
		worker.set_process(false)
	var w = main.workers[0]
	w.hp = 68.0
	w.hunger = 42.0
	w.fatigue = 72.0
	w.mental = CrewStatusDB.Mental.BAD
	w.weapon = GameData.Item.SIMPLE_SPEAR
	w.work_support = GameData.Item.HAUL_FRAME
	w.tools["mine"] = GameData.Item.HAMMER
	w.tools["chop"] = GameData.Item.AXE
	w.carrying = GameData.Item.CARCASS
	w.carry_n = 1
	w.carcass_cargo = {GameData.Item.MEAT: 2, GameData.Item.BONE: 1, GameData.Item.FAT: 1}
	w.ai._set_state(CharacterAI.State.MOVE_TO_STORAGE)
	w.ai.return_request = true
	w.ai.life_request = "rest"
	main._select(w)
	main.detail.open_worker(w)
	await _frames(5)
	_shot("crew-overview.png")
	main.detail._set_tab(1)
	await _frames(4)
	_shot("crew-equipment-cargo.png")
	main.detail._set_tab(2)
	await _frames(4)
	_shot("crew-work-ability.png")
	print("saved")
	quit()


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s" % [dir, name])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
