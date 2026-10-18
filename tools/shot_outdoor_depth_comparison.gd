extends SceneTree
## Renderer-only visual comparison. No OS input and no gameplay reward changes.

var main


func _capture(dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _point(x: float, y: float) -> void:
	var point := GatherPoint.new()
	point.setup(main, "vein")
	point.position = Vector2(x, y)
	main.resources_root.add_child(point)


func _set_workers(ys: Array) -> void:
	for i in main.workers.size():
		var worker = main.workers[i]
		worker.stop_work()
		worker.floor_i = 0
		worker.position = Vector2(1020.0 + i * 100.0, float(ys[i]))
		for job in GameData.job_list():
			worker.priorities[job] = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if not args.is_empty() else "."
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 0.0
	_clear(main.resources_root)
	_clear(main.creatures_root)
	_clear(main.enemies_root)
	_set_workers([680.0, 680.0, 680.0])
	_point(1270.0, 680.0)
	await _capture(dir, "one-line-baseline")
	_clear(main.resources_root)
	_set_workers([625.0, 680.0, 625.0])
	_point(1080.0, 625.0)
	_point(1270.0, 680.0)
	main._select(main.workers[1])
	await _capture(dir, "two-lane-normal-map")
	quit()
