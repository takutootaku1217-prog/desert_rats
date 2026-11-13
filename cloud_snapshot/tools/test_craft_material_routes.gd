extends SceneTree
## Contract for material-to-action routing in the existing CraftUI.  The test
## inspects actual buttons created by the real panel; it never injects goods.

var main
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _fresh() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 251102)
	root.add_child(main)
	await process_frame


func _has_named(node: Node, id: String) -> bool:
	return node.find_child(id, true, false) != null


func _pointer(point: Vector2, down: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)
	await process_frame


func _quantity_pointer_contract(ui) -> void:
	# Artificial UI update boundary, not native play: no goods/orders injected.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.set_process(false)
	root.size = Vector2i(1280, 720)
	var stock: Dictionary = main.storage.inventory.counts.duplicate(true)
	var orders: Array = main.production_orders.duplicate(true)
	var crafts: Array = main.craft_queue.duplicate(true)
	var transfers: Array = main.transfer_queue.duplicate(true)
	for mode in ["control", "dirty_inside", "dirty_outside", "after_cancel"]:
		ui.open_entry("cook")
		ui._qty_val = 1 # UI-only precondition, never used as gesture.
		ui._refresh(true)
		for frame in 3: await process_frame
		ui._detail.get_parent().ensure_control_visible(ui._qty)
		for frame in 3: await process_frame
		var button = ui._qty._btns[5]
		var point: Vector2 = button.get_global_rect().get_center()
		_check(root.get_visible_rect().has_point(point) and ui._detail.get_parent().get_global_rect().has_point(point), mode + " target visible")
		var calls := {"n": 0}
		ui._qty.changed.connect(func(_value): calls.n += 1)
		await _pointer(point, true)
		_check(ui._qty_val == 1 and calls.n == 0, mode + " down does not change quantity")
		if mode.begins_with("dirty_"):
			ui._sig = "pointer-stale-signature"
			ui._process(0.25)
			await process_frame
		await _pointer(Vector2(450, 100) if mode == "dirty_outside" else point, false)
		_check(ui._qty_val == (1 if mode == "dirty_outside" else 5), mode + " release keeps intended quantity")
		_check(calls.n == (0 if mode == "dirty_outside" else 1), mode + " callback occurs exactly once or cancels")
		ui._process(0.25)
		await process_frame
		_check(ui._sig != "pointer-stale-signature", mode + " refresh resumes after release")
	_check(main.storage.inventory.counts == stock and main.production_orders == orders and main.craft_queue == crafts and main.transfer_queue == transfers, "quantity gestures never change resources or orders")


func _run() -> void:
	await _fresh()
	var ui = main.craft_ui
	_check(ui.has_method("material_route"), "craft UI exposes a data-driven material route")
	if ui.has_method("material_route"):
		_check(ui.material_route(GameData.Item.WOOD) == "ground", "wood is a direct ground-gather route")
		_check(ui.material_route(GameData.Item.HIDE) == "creature", "hide stays an explicit creature-hunt route")
		_check(ui.material_route(GameData.Item.IRON) == "process", "iron is routed through existing processing, not direct gathering")
	ui.open_entry("simple_spear")
	_check(_has_named(ui._detail, "CollectGoal%d" % GameData.Item.WOOD), "a ground input keeps the existing global gather-request action")
	_check(_has_named(ui._detail, "OpenSourceMap%d" % GameData.Item.WOOD), "a ground input keeps the existing known-source map action")
	_check(not _has_named(ui._detail, "CollectGoal%d" % GameData.Item.IRON), "processed iron never offers an impossible direct collection goal")
	_check(not _has_named(ui._detail, "CancelGoal%d" % GameData.Item.IRON), "processed iron never offers a direct collection cancel action")
	_check(not _has_named(ui._detail, "OpenSourceMap%d" % GameData.Item.IRON), "processed iron never pretends to have a ground source")
	_check(_has_named(ui._detail, "OpenProcess%d_smelt" % GameData.Item.IRON), "processed iron links to its existing smelting recipe")
	ui.open_entry("bed_pack")
	var local_hide_sources: Array = CraftUI.local_hunt_sources(main, GameData.creature_sources_for(GameData.Item.HIDE))
	_check(not local_hide_sources.is_empty(), "fresh region has an existing local wildlife source for hide")
	for species in local_hide_sources:
		_check(_has_named(ui._detail, "RequestHunt_%s" % species), "creature input has an explicit %s hunt action" % species)
	_check(not _has_named(ui._detail, "CollectGoal%d" % GameData.Item.HIDE), "creature input never turns into an automatic collection goal")
	await _quantity_pointer_contract(ui)
	await _queue_pointer_contract(ui)
	ui.close()
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("== craft material routes: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)


func _cancel_buttons(node: Node) -> Array:
	var found: Array = []
	if node is Button and node.text == "×":
		found.append(node)
	for child in node.get_children():
		found.append_array(_cancel_buttons(child))
	return found


func _queue_pointer_contract(ui) -> void:
	# Synthetic queue progression only: held native-like pointer events still
	# target real controls. This is not normal-play or material-consumption proof.
	var stock: Dictionary = main.storage.inventory.counts.duplicate(true)
	var original: Array = main.craft_queue.duplicate()
	for mode in ["unchanged", "target_gone", "target_shifted", "equal_replacement"]:
		var first := {"id": "cook", "n": 1, "batch": false}
		var second := {"id": "smelt", "n": 1, "batch": false}
		main.craft_queue.clear()
		main.craft_queue.append_array([first, second])
		ui.open_entry("cook")
		ui._refresh(true)
		for frame in 3: await process_frame
		var buttons := _cancel_buttons(ui._detail)
		_check(buttons.size() == 2, mode + " both queue controls exist")
		if buttons.size() != 2: continue
		var button = buttons[1 if mode == "target_shifted" else 0]
		ui._detail.get_parent().ensure_control_visible(button)
		for frame in 3: await process_frame
		var point: Vector2 = button.get_global_rect().get_center()
		_check(ui._detail.get_parent().get_global_rect().has_point(point), mode + " cancel visible")
		await _pointer(point, true)
		if mode in ["target_gone", "target_shifted"]:
			main.craft_queue.remove_at(0)
		elif mode == "equal_replacement":
			main.craft_queue[0] = first.duplicate(true)
		ui._sig = "queue-progressed-during-hold"
		ui._process(0.25)
		await process_frame
		await _pointer(point, false)
		if mode == "target_shifted":
			_check(main.craft_queue.is_empty(), mode + " cancels the same order at its new index")
		elif mode == "equal_replacement":
			_check(main.craft_queue.size() == 2, mode + " never cancels a new identical order")
		else:
			_check(main.craft_queue.size() == 1 and is_same(main.craft_queue[0], second), mode + " leaves the unrelated order untouched")
	main.craft_queue.assign(original)
	_check(main.storage.inventory.counts == stock, "queue cancellation does not create or consume materials")
