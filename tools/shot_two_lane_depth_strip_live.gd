extends SceneTree
## 実際の Main と通常AIの描画証拠。OS入力は使わず、Viewportを保存する。

var main


func _capture(dir: String, name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _step() -> void:
	main._process(0.2)
	for resource in main.resources_root.get_children():
		if not resource.is_queued_for_deletion():
			resource._process(0.2)
	for enemy in main.enemies_root.get_children():
		if not enemy.is_queued_for_deletion():
			enemy._process(0.2)
	for worker in main.workers:
		worker._process(0.2)
	await process_frame


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _configure() -> void:
	main.set_meta("ground_depth_strip_config", {"enabled": true, "back_y": 570.0, "front_y": 625.0})
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 0.0
	main.tool_auto = false
	main.gather_policy = {GameData.Item.WOOD: 0, GameData.Item.STONE: 0, GameData.Item.IRON_ORE: 5}
	_clear(main.resources_root)
	_clear(main.enemies_root)
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.priorities[job] = 0


func _add_vein() -> GatherPoint:
	var point := GatherPoint.new()
	point.setup(main, "vein")
	point.max_amount = 1
	point.remaining = 1
	point.position = Vector2(1140.0, 621.0)
	main.resources_root.add_child(point)
	return point


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if not args.is_empty() else "."
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_configure()
	var gatherer = main.workers[0]
	var back_worker = main.workers[1]
	var front_worker = main.workers[2]
	gatherer.floor_i = 0
	gatherer.position = Vector2(940.0, 570.0)
	gatherer.tools = {"mine": GameData.Item.HAMMER}
	gatherer.priorities[GameData.Job.GATHER] = 5
	back_worker.floor_i = 0
	back_worker.position = Vector2(770.0, 570.0)
	front_worker.floor_i = 0
	front_worker.position = Vector2(770.0, 625.0)
	main._select(front_worker)
	_add_vein()
	for _frame in 3:
		await _step()
	await _capture(dir, "live-depth-gather")
	gatherer.stop_work()
	gatherer.floor_i = 0
	gatherer.position = Vector2(930.0, 570.0)
	var enemy := Enemy.new()
	enemy.setup(main, 120.0)
	enemy.position = Vector2(930.0, 625.0)
	main.enemies_root.add_child(enemy)
	main._select(gatherer)
	gatherer.ai.order_attack(enemy)
	await _step()
	await _capture(dir, "live-depth-combat-approach")
	gatherer.ai.request_return()
	for _frame in 2:
		await _step()
	await _capture(dir, "live-depth-return")
	quit()
