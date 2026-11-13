extends SceneTree
## Runtime counterpart to the deterministic mine gate test. It leaves Main in
## normal processing mode and drives the same map UI action through rendered
## frames, catching a gate that only fails outside direct `_process` stepping.

var failures := 0
var main = null

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	print("  %s %s" % ["ok" if value else "FAIL", message])
	if not value:
		failures += 1

func _run() -> void:
	var old_scale := Engine.time_scale
	Engine.time_scale = 20.0
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	await process_frame
	main.director.enabled = false
	main.target_speed = 200.0
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	main.map_ui.open()
	main.map_ui.select_region("c_quarry")
	main.map_ui._go()
	_check(not paused, "map UI restores runtime processing after departure")
	for frame in 240:
		await process_frame
		if main.world.region == "c_quarry" and main.world.phase == "stopped" and main.mine_arrival_gate.visible_state() == "arrival_choice":
			break
	_check(main.world.region == "c_quarry" and main.world.phase == "stopped", "normal runtime reaches stopped C")
	_check(main.mine_arrival_gate.visible_state() == "arrival_choice", "normal runtime presents the C entry choice")
	_check(main.mine_arrival_gate.get_parent() == main, "C entry choice stays in the normal game UI tree")
	_check(main.mine_arrival_gate._overlay.visible and main.mine_arrival_gate._panel.visible and main.mine_arrival_gate._overlay.is_visible_in_tree() and main.mine_arrival_gate._panel.is_visible_in_tree(), "C entry choice makes both visual controls visible in the game viewport")
	if is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	await process_frame
	Engine.time_scale = old_scale
	print("== first-region mine journey runtime gate: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
