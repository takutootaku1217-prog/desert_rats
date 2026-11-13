extends SceneTree
## UI signal/layout witness only; not OS mouse input or rendered-image validation.
var main
var hud
var failures := 0
func _init() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
 print("%s %s" % ["ok" if ok else "FAIL", label])
 if not ok: failures += 1
func _run() -> void:
 SaveGame.disabled = true
 main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed", 104729)
 root.add_child(main)
 await process_frame
 main.set_process(false)
 main.world.road = "ab"
 main.world.origin = "a_start"
 main.world.phase = "travel"
 main.world.destination = "b_forest"
 hud = load("res://ui/travel_hud.gd").new()
 hud.game = main
 root.add_child(hud)
 await process_frame
 _check(hud.has_method("set_hunt_open"), "travel HUD has an explicit vehicle-hunting entry")
 if not hud.has_method("set_hunt_open"):
  _finish(); return
 _check(not hud._hunt_panel.visible, "hunt choices start collapsed")
 hud._hunt_toggle.pressed.emit()
 await process_frame
 _check(hud._hunt_panel.visible, "button signal opens hunt choices")
 var species: String = hud._hunt_species.get_item_metadata(hud._hunt_species.selected)
 var before: int = main.hunt_request_remaining(species)
 _check(before == 0, "opening UI does not enable hunting")
 hud._hunt_request.pressed.emit()
 _check(main.hunt_request_remaining(species) == 1, "request button explicitly requests one selected species")
 hud._hunt_cancel.pressed.emit()
 _check(main.hunt_request_remaining(species) == 0, "cancel button revokes selected species request")
 # Explicit display fixture only: no claim of naturally acquired cargo here.
 main.vehicle_hunt.cargo = GameData.CREATURES["dodo"].drops.duplicate(true)
 main.vehicle_hunt.cargo_species = "dodo"
 main.vehicle_hunt.tick(1.5)
 hud._refresh()
 _check(hud._hunt_status.text.contains("50%"), "recovery progress is visible without opening another panel")
 main.vehicle_hunt.restore({})
 _check(hud._hunt_note.text.contains("検証用"), "provisional device label is visible")
 _check(hud._cooking_reason.text != "", "cooking next step has a visible reason")
 # Display-only stock fixture, deliberately separates warehouse from workshop.
 main.storage.inventory.counts[GameData.Item.MEAT] = 3
 main.storage.inventory.counts[GameData.Item.FOOD] = 4
 main.processor.stock.counts[GameData.Item.MEAT] = 7
 var stock_before: Dictionary = main.storage.inventory.counts.duplicate(true)
 hud._refresh()
 var forecast = hud.get("_food_forecast")
 _check(forecast != null, "cooking panel shows warehouse food forecast")
 if forecast != null:
  _check(forecast.text.contains("生肉3") and forecast.text.contains("食料4") and forecast.text.contains("+6"), "forecast uses warehouse counts and actual cook recipe yield")
  _check(forecast.text.contains("回収中・作業場は含まず"), "forecast explicitly excludes cargo and workshop")
 _check(main.storage.inventory.counts == stock_before, "forecast display does not mutate stock")
 hud._cook.pressed.emit()
 await process_frame
 _check(main.craft_ui.is_open() and main.craft_ui.selected_entry().get("id", "") == "cook", "cooking button opens existing cook creation entry")
 _check(not hud._card.visible, "travel HUD hides while a modal is open")
 main.craft_ui.close()
 hud.set_hunt_open(true)
 hud.set_details_open(true)
 await process_frame
 await process_frame
 _check(hud._card.get_global_rect().end.x <= 1280 and hud._card.get_global_rect().end.y <= 720, "expanded HUD fits 1280x720")
 print("HUD rect ", hud._card.get_global_rect())
 _finish()
func _finish() -> void:
 if hud != null: hud.queue_free()
 if main != null: main.queue_free()
 SaveGame.disabled = false
 print("vehicle hunt UI: %s" % ("passed" if failures == 0 else "%d failures" % failures))
 quit(1 if failures else 0)
