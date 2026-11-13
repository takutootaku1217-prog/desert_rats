extends SceneTree
## One-off diagnostic for test_normal_haul_frame_progression reproducibility.
## It intentionally changes no game data and uses the same Main setup as the
## progression test, printing only the finite C-site ledger after a trip.

const STEP := 0.2
const SEED := 104729

var main = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for case_index in 3:
		await _free_main()
		await _fresh(case_index)
		# Probe whether an explicit measurement-boundary seed stabilizes C's
		# finite source ledger after presentation/setup work has run.
		seed(SEED)
		var moved := await _move_to_quarry()
		print("CASE=%d moved=%s c_ledger=%s roots=%s" % [case_index, moved, _ledger_text(), _root_names()])
	await _free_main()
	quit()

func _fresh(case_index: int) -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", SEED)
	root.add_child(main)
	await process_frame
	print("FRESH=%d a_ledger=%s roots=%s" % [case_index, _ledger_text("region:a_start"), _root_names()])
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 60.0
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	for worker in main.workers:
		worker.stop_work()

func _move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for frame in 240:
		main._process(STEP)
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
		if frame % 24 == 0:
			await process_frame
	return false

func _move_to_quarry() -> bool:
	return await _move_leg("b_forest") and await _move_leg("c_quarry")

func _ledger_text(key := "region:c_quarry") -> String:
	var rows: Array = []
	for id in main.world.locations.get(key, {}):
		var row: Dictionary = main.world.locations[key][id]
		if row.get("type") == "gather":
			rows.append("%s:%s:%s" % [id, str(row.data.get("kind", "")), str(row.data.get("max_amount", ""))])
	return ",".join(rows)

func _root_names() -> String:
	var names: Array = []
	for node in root.get_children():
		names.append(node.name)
	return ",".join(names)

func _free_main() -> void:
	if main == null:
		return
	if is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	main = null
	await process_frame
