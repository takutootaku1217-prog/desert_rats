extends SceneTree
## Contract for the purpose-first entry bar.  This uses the real panels so that
## the visual shortcuts cannot bypass the existing modal/ownership rules.

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
	main.set_meta("diagnostic_seed", 251101)
	root.add_child(main)
	await process_frame


func _state() -> Dictionary:
	return {
		"fuel": main.base.fuel,
		"hull": main.base.parts.duplicate(true),
		"inventory": main.storage.inventory.counts.duplicate(true),
		"world": SaveGame.fields(main.world, WorldTrip.FIELDS),
		"workers": main.workers.map(func(worker): return [worker.carrying, worker.carry_n, worker.gather_focus_item]),
	}


func _run() -> void:
	await _fresh()
	var nav = main.navigation
	_check(nav.has_method("purpose_entry_ids"), "navigation exposes its purpose-first entry contract")
	var expected := ["作成", "移動", "所持品", "仲間"]
	if nav.has_method("purpose_entry_ids"):
		_check(nav.purpose_entry_ids() == expected, "purpose entries have the expected short labels and order")
	for entry in expected:
		_check(nav.buttons.has(entry), "%s has a visible navigation button" % entry)
	_check(not main.has_facility("workbench"), "fresh prototype starts before the workbench is built")
	var before := _state()
	nav.activate("作成")
	_check(main.craft_ui.is_open(), "作成 opens the existing craft panel")
	_check(main.craft_ui.selected_entry().get("key", "") == "build:workbench", "first 作成 opens the existing no-prerequisite workbench")
	main.craft_ui.close()
	nav.activate("移動")
	_check(main.map_ui.is_open(), "移動 opens the existing destination map")
	main.map_ui.close()
	nav.activate("所持品")
	_check(main.inventory_ui.is_open(), "所持品 opens the existing inventory panel")
	main.inventory_ui.close()
	nav.activate("仲間")
	_check(main.detail._overlay.visible, "仲間 opens the existing crew and equipment panel")
	main.detail.close()
	nav.activate("拠点・街")
	_check(nav.popup.visible and nav.groups.get("拠点") != null and nav.groups["拠点"].visible, "拠点・街 keeps town, vehicle, building, and room actions reachable")
	nav.activate("その他")
	_check(nav.popup.visible and nav.groups.get("その他") != null and nav.groups["その他"].visible, "その他 keeps field, policy, and save actions reachable")
	nav.close()
	_check(before == _state(), "opening and closing purpose entries does not mutate travel, cargo, or crew state")
	main.world.phase = "travel"
	nav._process(0.0)
	_check(not nav.bar.visible, "road travel hides the large purpose bar behind the compact travel HUD")
	main.world.phase = "stopped"
	nav._process(0.0)
	_check(nav.bar.visible, "stopping restores purpose entries")
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("== purpose entry flow: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
