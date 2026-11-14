extends "res://tools/test_c_outpost_entry_v3.gd"
## Reuses real A->B->C fixture and synthetic viewport pointer helper.
## No ordinary survival/OS-input claim. Missing normal-quarry dispatch must fail.
func run() -> void:
 root.gui_embed_subwindows = true
 root.size = Vector2i(1280, 720)
 await fresh()
 var gate = main.mine_arrival_gate
 check(gate.enter_mine(), "normal quarry entry succeeds")
 var adapter = gate.field
 if adapter == null: await finish(); return
 adapter.set_process(false)
 for unused in 5: await process_frame
 var session = adapter.session
 check(not session.outpost_enabled and not session.is_region_boss(), "normal quarry fixture, not optional combat")
 check(advance(session, func(): return not session.depot_stock.is_empty(), 160), "real workers gather and unload cargo")
 adapter._update_controls()
 var button: Button = adapter.vehicle_return_button
 var stock: Dictionary = main.storage.inventory.counts.duplicate(true)
 # Hold preparation while real recall completes; release must never become commit.
 button.button_down.emit()
 session.request_recall()
 adapter._update_controls()
 check(button.disabled and button.text.contains("中"), "same button visibly waits during recall")
 check(advance(session, func(): return session.phase == "ready_to_exit", 160), "all crew/cargo physically return")
 adapter._update_controls()
 check(not button.disabled and button.text.contains("横視点"), "same visible button now offers confirmed return")
 button.pressed.emit()
 check(not session.committed and gate.field == adapter and main.storage.inventory.counts == stock, "preparation press cannot promote to commit on release")
 # Saving and stale clock reject captured input without committing.
 button.button_down.emit()
 main.save_ui.open()
 button.pressed.emit()
 check(not session.committed, "save menu blocks pending return")
 main.save_ui.close()
 adapter._update_controls()
 button.button_down.emit()
 adapter._vehicle_return_clock = null
 button.pressed.emit()
 check(not session.committed and main.storage.inventory.counts == stock, "stale captured clock cannot deposit")
 # Captured input cannot survive changed ownership or a hidden/failed view.
 button.button_down.emit()
 adapter._vehicle_return_session = null
 button.pressed.emit()
 check(not session.committed, "old session press rejected")
 for invalid_context in ["hidden", "gameover", "discard"]:
  button.button_down.emit()
  if invalid_context == "hidden": adapter.hide()
  if invalid_context == "gameover": main.game_over = true
  if invalid_context == "discard": adapter._discarding_for_load = true
  button.pressed.emit()
  check(not session.committed, "pending return rejected during " + invalid_context)
  adapter.show(); main.game_over = false; adapter._discarding_for_load = false
  adapter._update_controls()
 # Explicit capacity fixture: fill with owned food, never claim natural acquisition.
 var room: int = main.storage.max_weight() - main.storage.current_weight() - main.storage.processing_reserve()
 var added := maxi(0, room - 1)
 main.storage.store_owned(GameData.Item.FOOD, added, Inventory.SOURCE_TRANSFER)
 var before := SaveGame.capture(main)
 var field_before: Dictionary = session.to_dict()
 await pointer(button)
 check(adapter.return_confirmation.visible and not session.committed, "right-top return requests existing capacity consent")
 adapter.return_confirmation.canceled.emit(); adapter.return_confirmation.hide()
 check(SaveGame.capture(main) == before and session.to_dict() == field_before, "capacity cancellation changes no people or cargo")
 await pointer(button)
 main.storage.inventory.take_n(GameData.Item.FOOD, 6)
 var changed := SaveGame.capture(main)
 adapter.return_confirmation.confirmed.emit()
 check(adapter.return_confirmation.visible and adapter.return_confirmation.dialog_text.contains("変わりました") and not session.committed and SaveGame.capture(main) == changed, "capacity change requires refreshed explicit consent")
 adapter.return_confirmation.canceled.emit(); adapter.return_confirmation.hide()
 main.storage.inventory.take_n(GameData.Item.FOOD, added - 6)
 check(main.storage.inventory.counts == stock, "capacity fixture restores exact stock before normal commit")
 adapter.exit_to_horizontal.connect(func(_result):
  adapter._dispatch_vehicle_return()
  adapter._commit_and_exit()
 )
 # Real visible control consumes the final independent choice.
 var cargo: Dictionary = session.depot_stock.duplicate(true)
 await pointer(button)
 check(session.committed and gate.field == null, "same right-top control commits and restores horizontal view")
 for item in cargo:
  check(main.storage.count_of(item) == int(stock.get(item, 0)) + int(cargo[item]), "cargo deposited once item " + str(item))
 for item in cargo:
  check(main.storage.count_of(item) == int(stock.get(item, 0)) + int(cargo[item]), "repeated dispatch never duplicates cargo " + str(item))
 await finish()

func finish() -> void:
 if is_instance_valid(main): main.queue_free()
 await process_frame
 SaveGame.disabled = false
 print("NORMAL QUARRY RETURN: %s" % ("passed" if failures == 0 else "%d failures" % failures))
 quit(1 if failures else 0)
