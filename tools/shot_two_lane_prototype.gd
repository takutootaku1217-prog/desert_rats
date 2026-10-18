extends SceneTree

var prototype

func capture(dir: String, name: String) -> void:
	await process_frame
	await create_timer(0.4).timeout
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if not args.is_empty() else "."
	prototype = load("res://scenes/two_lane_prototype.tscn").instantiate()
	root.add_child(prototype)
	await process_frame
	await process_frame
	prototype.reset("one")
	await create_timer(7.0).timeout
	await capture(dir, "one-lane")
	prototype.reset("two")
	await create_timer(7.0).timeout
	await capture(dir, "two-lanes")
	prototype.start_retreat_test()
	await create_timer(2.0).timeout
	await capture(dir, "two-lanes-retreat")
	quit()
