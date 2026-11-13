extends SceneTree
## Real Main layout + viewport pointer fixture, not natural progression / OS input.
## Removing the reveal/layout update must put confirm/cancel outside the clip rect.
var main
var failures := 0
var checks := 0

func _init() -> void:
 call_deferred("_run")

func _check(ok: bool, label: String) -> void:
 checks += 1
 print("  %s %s" % ["ok" if ok else "FAIL", label])
 if not ok: failures += 1

func _frames(count: int = 8) -> void:
 for i in count: await process_frame

func _button(prefix: String) -> Button:
 for child in main.map_ui._land_box.get_children():
  if child is Button and child.text.begins_with(prefix): return child
 return null

func _press(prefix: String) -> void:
 var button := _button(prefix)
 _check(button != null, "plan control exists: " + prefix)
 if button != null: button.pressed.emit()

func _visible(button: Button) -> bool:
 if button == null or not button.is_visible_in_tree(): return false
 var rect := button.get_global_rect()
 return main.map_ui._land_scroll.get_global_rect().encloses(rect) and Rect2(Vector2.ZERO, root.size).encloses(rect)

func _controls_visible(label: String) -> void:
 for prefix in ["この計画を実行", "計画を取消"]:
  var button := _button(prefix)
  _check(_visible(button), label + " visible and unclipped: " + prefix)
  if button != null:
   print("    rect=", button.get_global_rect(), " viewport=", main.map_ui._land_scroll.get_global_rect())

func _click(button: Button) -> void:
 if not _visible(button):
  _check(false, "refuse synthetic pointer outside visible control")
  return
 for pressed in [true, false]:
  var event := InputEventMouseButton.new()
  event.position = button.get_global_rect().get_center()
  event.button_index = MOUSE_BUTTON_LEFT
  event.pressed = pressed
  root.push_input(event, true)
  await process_frame

func _run() -> void:
 SaveGame.disabled = true
 root.size = Vector2i(1280, 720)
 main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed", 261110)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 main.director.enabled = false
 main.save_ui.hide()
 main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
 for worker in main.workers: worker.stop_work()
 main.world.region = "b_forest"
 main.world.phase = "stopped"
 main.storage.inventory.counts = {GameData.Item.WOOD: 20, GameData.Item.STONE: 20}
 main.transfer_queue.clear()
 _check(main.world.land_operation_reason().is_empty(), "fixture crew safely returned at B")
 main.map_ui.open()
 await _frames()
 if "gui-fixture" in OS.get_cmdline_user_args():
  print("GUI FIXTURE ready: B stopped, 20 wood/20 stone, SaveGame.disabled=true; not natural progression")
  main.storage.inventory.changed.connect(func(): print("GUI inventory: ", main.storage.inventory.counts, " roads: ", main.world.region_state.roads))
  return
 var counts: Dictionary = main.storage.inventory.counts.duplicate(true)
 var land: Dictionary = main.world.region_state.duplicate(true)
 for prefix in ["B–D倒木", "A–B整地", "中継"]:
  # Construction wording is data-driven; discover it independently by plan suffix.
  var choice: String = prefix
  if prefix == "中継":
   for child in main.map_ui._land_box.get_children():
    if child is Button and child.text.ends_with("の計画を確認") and not child.text.begins_with("A–B"): choice = child.text
  _press(choice)
  await _frames()
  _controls_visible(choice)
  _check(main.storage.inventory.counts == counts and main.world.region_state == land, "preview has no payment or road mutation")
  if _visible(_button("計画を取消")): await _click(_button("計画を取消"))
  else: _press("計画を取消")
  await _frames()
  _check(main.map_ui._land_action == "" and main.storage.inventory.counts == counts and main.world.region_state == land, "cancel clears plan without resource/state change")
  _check(paused and main.map_ui.is_open(), "preview/cancel retain map time stop")
 _press("B–D倒木")
 _press("A–B整地")
 await _frames()
 _check(main.map_ui._land_action == "grade_ab", "rapid switch keeps latest plan")
 _controls_visible("rapid switch")
 _press("計画を取消")
 _press("B–D倒木")
 _press("計画を取消")
 main.map_ui._land_scroll.scroll_vertical = 0
 await _frames()
 _check(main.map_ui._land_action == "" and main.map_ui._land_scroll.scroll_vertical == 0, "same-frame cancel invalidates pending reveal")
 _press("B–D倒木")
 main.map_ui.close()
 main.map_ui.open()
 await _frames()
 _check(main.map_ui._land_action == "" and main.map_ui._land_scroll.scroll_vertical == 0, "close/reopen invalidates pending reveal")
 _press("B–D倒木")
 main.world.region = "a_start"
 main.map_ui._refresh()
 main.map_ui._land_scroll.scroll_vertical = 0
 await _frames()
 _check(main.map_ui._land_action == "" and main.map_ui._land_scroll.scroll_vertical == 0, "site change invalidates pending reveal")
 main.world.region = "b_forest"
 main.map_ui._refresh()
 for invalidation in ["generation", "cancel", "close"]:
  _press("B–D倒木")
  await _frames()
  main.map_ui._land_scroll.scroll_vertical = 0
  # Start the actual coroutine synchronously up to its frame await. No private
  # state injection or mock: these are the same captured arguments as selection.
  main.map_ui.call("_reveal_land_preview", "b_forest", "clear_shortcut", main.map_ui._land_revision)
  match invalidation:
   "generation": main.map_ui._refresh() # Same action/site, newer controls.
   "cancel": _press("計画を取消")
   "close":
    main.map_ui.close()
    main.map_ui.open()
  main.map_ui._land_scroll.scroll_vertical = 0
  await _frames()
  _check(main.map_ui._land_scroll.scroll_vertical == 0, "suspended reveal invalidated by " + invalidation)
  if main.map_ui._land_action != "": _press("計画を取消")
 _press("B–D倒木")
 await _frames()
 _controls_visible("payment")
 var confirm := _button("この計画を実行")
 if _visible(confirm): await _click(confirm)
 _check(main.world.region_state.roads.bd.cleared, "visible pointer confirm opens B–D")
 _check(main.storage.inventory.count(GameData.Item.WOOD) == 18 and main.storage.inventory.count(GameData.Item.STONE) == 19, "confirm spends existing exact B–D cost once")
 for site in ["b_forest", "d_yard"]:
  main.world.region = site
  main.map_ui._refresh()
  counts = main.storage.inventory.counts.duplicate(true)
  land = main.world.region_state.duplicate(true)
  for child in main.map_ui._land_box.get_children():
   if child is Button and child.text.ends_with("の計画を確認") and not child.text.begins_with("A–B"):
    child.pressed.emit()
    break
  await _frames()
  _controls_visible(site + " build with other services")
  if _visible(_button("計画を取消")): await _click(_button("計画を取消"))
  else: _press("計画を取消")
  _check(main.storage.inventory.counts == counts and main.world.region_state == land, "build preview/cancel leaves site and stock unchanged")
  _check(main.world.build_current_site(), "fixture builds empty store for removal layout")
  main.map_ui._refresh()
  counts = main.storage.inventory.counts.duplicate(true)
  land = main.world.region_state.duplicate(true)
  _press("保管庫を撤去")
  await _frames()
  _controls_visible(site + " remove below storage rows")
  if _visible(_button("計画を取消")): await _click(_button("計画を取消"))
  else: _press("計画を取消")
  _check(main.storage.inventory.counts == counts and main.world.region_state == land, "remove preview/cancel preserves built store and stock")
 main.map_ui.close()
 main.queue_free()
 await process_frame
 SaveGame.disabled = false
 print("LAND PREVIEW VISIBILITY checks=", checks, " failures=", failures)
 quit(1 if failures else 0)
