extends SceneTree
## Real behavioral regression: executed in isolated Godot 4.6.3 diagnostics.
## Passing here is not a Godot 4.7.2 acceptance claim.
## Exercises real Main, WorldTrip and Inventory, with isolated diagnostic state.
## Catches reservation bypass, notification ordering and repeated payment.
var main
var failures := 0
const CASES := [
	{"method": "build_current_site", "site": "b_forest", "wood": 4, "stone": 2},
	{"method": "build_current_site", "site": "d_yard", "wood": 3, "stone": 3},
	{"method": "clear_shortcut", "site": "b_forest", "wood": 2, "stone": 1},
	{"method": "grade_ab", "site": "a_start", "wood": 2, "stone": 3},
]

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", label])
	if not ok: failures += 1

func _fresh(row: Dictionary) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 261108)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	# The first live frame can reserve an outdoor target. This payment fixture
	# requires a safely returned crew, before its deliberate interior reservations.
	for worker in main.workers: worker.stop_work()
	_check(main.world.ready_reason().is_empty(), "payment fixture starts with safely returned crew")
	main.world.region = row.site
	main.world.phase = "stopped"
	main.storage.inventory.counts = {GameData.Item.WOOD: row.wood, GameData.Item.STONE: row.stone}
	main.transfer_queue.clear()

func _release() -> void:
	main.queue_free()
	await process_frame

func _completed(row: Dictionary) -> bool:
	match row.method:
		"build_current_site": return main.world.site_built(row.site)
		"clear_shortcut": return bool(main.world.region_state.roads.bd.cleared)
		"grade_ab": return bool(main.world.region_state.roads.ab.graded)
	return false

func _payment_panel(row: Dictionary) -> Dictionary:
	main.map_ui._land_action = "build" if row.method == "build_current_site" else row.method
	main.map_ui._refresh_land()
	var button: Button = null
	var labels := ""
	for child in main.map_ui._land_box.get_children():
		if child is Button and child.text == "この計画を実行": button = child
		if child is Label: labels += child.text + "\n"
	return {"button": button, "labels": labels}

func _run() -> void:
	SaveGame.disabled = true
	for row in CASES:
		# Exercise all real reservation readers, not a mocked availability value.
		for reservation in ["transfer", "build", "craft"]:
			await _fresh(row)
			if reservation == "transfer":
				main.transfer_queue.append({"item": GameData.Item.WOOD, "n": row.wood, "dir": "to_workshop"})
			else:
				var worker = main.workers[0]
				worker.ai.state = CharacterAI.State.HAUL_TAKE
				worker.ai.haul_recipe = {"in": {GameData.Item.WOOD: row.wood}}
				if reservation == "build": worker.ai.haul_recipe["build"] = "workbench"
			_check(main.warehouse_discard_available(GameData.Item.WOOD) == 0, "%s fixture reserves wood" % reservation)
			var panel := _payment_panel(row)
			_check(panel.button != null and panel.button.disabled, "reserved payment is disabled in the real confirmation UI")
			var wood_name: String = main.map_ui._item_name(GameData.Item.WOOD)
			_check(panel.labels.contains(wood_name + " 0/" + str(row.wood) + "（不足" + str(row.wood) + "）"), "confirmation reports spendable wood shortage")
			var counts: Dictionary = main.storage.inventory.counts.duplicate(true)
			var land: Dictionary = main.world.region_state.duplicate(true)
			_check(not main.world.call(row.method), "%s rejects %s reserved wood" % [row.method, reservation])
			_check(main.storage.inventory.counts == counts and main.world.region_state == land, "rejection leaves inventory and land unchanged")
			await _release()

		await _fresh(row)
		# Keeping one reserved wood must not prevent spending the actual surplus.
		main.storage.inventory.counts[GameData.Item.WOOD] += 1
		main.transfer_queue.append({"item": GameData.Item.WOOD, "n": 1, "dir": "to_workshop"})
		var surplus_panel := _payment_panel(row)
		_check(surplus_panel.button != null and not surplus_panel.button.disabled, "exact surplus enables the actual confirmation button")
		var wood_name: String = main.map_ui._item_name(GameData.Item.WOOD)
		_check(surplus_panel.labels.contains(wood_name + " " + str(row.wood) + "/" + str(row.wood)), "confirmation excludes reserved wood from available quantity")
		if surplus_panel.button != null and not surplus_panel.button.disabled:
			surplus_panel.button.emit_signal("pressed")
		_check(main.map_ui._land_action == "", "successful real confirmation clears its selected action")
		_check(main.storage.inventory.count(GameData.Item.WOOD) == 1 and main.storage.inventory.count(GameData.Item.STONE) == 0, "payment preserves reserved wood")
		_check(_completed(row), "successful payment commits land outcome")
		await _release()

		await _fresh(row)
		# Double cost enables a bounded reentrant attempt to reveal double charging.
		main.storage.inventory.counts[GameData.Item.WOOD] *= 2
		main.storage.inventory.counts[GameData.Item.STONE] *= 2
		var observed := {"calls": 0, "complete": false, "reentered": false, "wood": -1, "stone": -1}
		var callback := func():
			observed.calls += 1
			if observed.calls != 1: return
			observed.complete = _completed(row)
			observed.wood = main.storage.inventory.count(GameData.Item.WOOD)
			observed.stone = main.storage.inventory.count(GameData.Item.STONE)
			observed.reentered = main.world.call(row.method)
		main.storage.inventory.changed.connect(callback)
		var ledger: Dictionary = main.world.locations.duplicate(true)
		_check(main.world.call(row.method), "%s initial payment succeeds" % row.method)
		main.storage.inventory.changed.disconnect(callback)
		_check(observed.calls == 1 and observed.complete, "inventory notification sees committed land outcome exactly once")
		_check(observed.wood == row.wood and observed.stone == row.stone, "notification sees exactly one payment")
		_check(not observed.reentered, "nested land payment is rejected")
		_check(main.storage.inventory.count(GameData.Item.WOOD) == row.wood and main.storage.inventory.count(GameData.Item.STONE) == row.stone, "reentrant attempt cannot charge twice")
		_check(main.world.locations == ledger, "land payment preserves finite resource ledger")
		_check(not main.world.call(row.method), "repeated completed action is rejected")
		await _release()
	# The guard must cover other land commands, including removal, too.
	await _fresh(CASES[0])
	main.storage.inventory.counts = {GameData.Item.WOOD: 20, GameData.Item.STONE: 20}
	var cross := {"called": false, "clear": false, "grade": false, "remove": false}
	var cross_callback := func():
		if cross.called: return
		cross.called = true
		cross.clear = main.world.clear_shortcut()
		cross.grade = main.world.grade_ab()
		cross.remove = main.world.remove_current_site()
	main.storage.inventory.changed.connect(cross_callback)
	_check(main.world.build_current_site(), "outer B construction succeeds")
	main.storage.inventory.changed.disconnect(cross_callback)
	_check(cross.called and not cross.clear and not cross.grade and not cross.remove, "all nested land mutations are rejected")
	_check(main.world.site_built("b_forest"), "notification cannot remove newly paid B construction")
	_check(not main.world.region_state.roads.bd.cleared and not main.world.region_state.roads.ab.graded, "nested command cannot add an unrequested road improvement")
	_check(main.storage.inventory.count(GameData.Item.WOOD) == 16 and main.storage.inventory.count(GameData.Item.STONE) == 18, "only B construction cost is paid")
	await _release()
	SaveGame.disabled = false
	print("LAND PAYMENT CONTRACT failures=", failures)
	quit(1 if failures else 0)
