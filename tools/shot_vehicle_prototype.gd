extends SceneTree
## Real Godot rendering evidence for the large mobile-base prototype.
## Godot --headless --path . -s res://tools/shot_vehicle_prototype.gd -- <output-dir>

var main
var out_dir := "."

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s" % [out_dir, name])
	print("saved ", name)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if not args.is_empty() else "."
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(4)
	main.director.enabled = false
	main.target_speed = 0.0
	main.apply_vehicle_combat_preset()
	main.spawn_vehicle_test_enemy()
	main.vehicle_ui.open()
	await _frames(5)
	_shot("large-vehicle-customization.png")
	main.vehicle_ui.close()
	main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
	await _frames(5)
	_shot("large-vehicle-exterior.png")
	var worker = main.workers[0]
	main.storage.inventory.counts[GameData.Item.RIFLE] = 1
	main.equip_weapon(worker, GameData.Item.RIFLE)
	main.detail.open_worker(worker)
	main.detail._set_tab(1)
	await _frames(5)
	_shot("crew-rifle-equipment.png")
	quit()
