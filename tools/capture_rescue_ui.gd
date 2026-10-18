extends SceneTree
## Real Godot Viewport captures for rescue UI states. Usage:
## godot --path . -s res://tools/capture_rescue_ui.gd -- --screenshots=C:/temp/rescue-ui

var main
var destination := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			destination = arg.trim_prefix("--screenshots=")
	if destination.is_empty():
		destination = OS.get_user_data_dir().path_join("rescue-ui-captures")
	DirAccess.make_dir_recursive_absolute(destination)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames()
	main.set_process(false)
	for worker in main.workers: worker.set_process(false)
	var injured = main.workers[0]
	var carrier = main.workers[1]
	injured.floor_i = 0
	carrier.floor_i = 0
	injured.position = Vector2(900, GameData.LO_Y)
	carrier.position = Vector2(700, GameData.LO_Y)
	CrewStatus.damage(injured, 999.0)
	main.detail.open_worker(injured)
	await _capture("01-awaiting-rescue-timer")
	main.rescue.assign(carrier, injured)
	for i in 500:
		main.rescue.carrier_tick(carrier, 0.1)
		if bool(main.rescue.record_for(injured).get("carried", false)): break
	main.detail._update_live()
	await _capture("02-carrier-assigned-carrying")
	for i in 1200:
		main.rescue.carrier_tick(carrier, 0.1)
		if not injured.down: break
	main.detail.open_worker(injured)
	await _capture("03-recovery-awaiting-explicit-resume")
	for worker in main.workers:
		if not worker.down: CrewStatus.damage(worker, 999.0)
	main.rescue.tick(0.1)
	main.detail.close()
	await _capture("04-all-down-checkpoint-restart")
	print("SCREENSHOTS ", destination)
	quit()

func _frames() -> void:
	for i in 4: await process_frame

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination.path_join(label + ".png"))
	await process_frame
