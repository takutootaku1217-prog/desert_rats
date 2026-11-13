extends SceneTree
## Read-only overhead guide contract for the normal C-quarry mine-path spike.
## Production controls retain ownership of rubble clearance and route state.

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")
const STEP := 0.2

var main
var field
var failures := 0

func _init() -> void:
 call_deferred("_run")

func _check(ok: bool, message: String) -> void:
 print("  %s %s" % ["ok" if ok else "FAIL", message])
 if not ok:
  failures += 1

func _run() -> void:
 SaveGame.disabled = true
 await _fresh_c_quarry()
 if main == null:
  _finish()
  return
 main.storage.store_owned(GameData.Item.HANDCART, 1, Inventory.SOURCE_TRANSFER)
 _check(main.equip_work_support(main.workers[1], GameData.Item.HANDCART), "Fixture equips the existing cart carrier")
 var created: Dictionary = RouteSession.create_from_game(main, "canyon-route-guide", {"mine_path_engineering": true})
 _check(bool(created.get("ok", false)), "Normal C creates the route-engineering session for guide readback")
 if not bool(created.get("ok", false)):
  _finish()
  return
 var session = created.session
 var blocked: Dictionary = session.mine_path_guide_snapshot()
 _check(bool(blocked.get("fixed_entry", false)) and bool(blocked.get("backpack_step", false)), "Guide snapshot retains the fixed entry and backpack-only step")
 _check(str(blocked.get("cart_route", "")) == "detour" and str(blocked.get("rubble", "")) == "blocked", "Guide snapshot distinguishes cart detour from blocked rubble shortcut")
 main.visible = false
 var layer := CanvasLayer.new()
 layer.layer = 100
 root.add_child(layer)
 field = FieldAdapter.new()
 field.configure(main, session)
 layer.add_child(field)
 await process_frame
 field.process_mode = Node.PROCESS_MODE_DISABLED
 field._update_controls()
 _check(field.route_guide_button != null and field.route_guide_button.visible, "Engineering C exposes a separate route-guide toggle")
 var before: Dictionary = session.to_dict().duplicate(true)
 field.route_guide_button.emit_signal("pressed")
 await process_frame
 _check(field.route_guide != null and field.route_guide.visible, "Route-guide toggle opens the overhead comparison diagram")
 _check(session.to_dict() == before, "Opening the route guide cannot mutate the live quarry session")
 field.maintenance_button.emit_signal("pressed")
 var cleared := await _advance_until(session, func(): return str(session.intermediate_access) == "cleared", 30.0)
 field._update_controls()
 var open: Dictionary = session.mine_path_guide_snapshot()
 _check(cleared and str(open.get("cart_route", "")) == "shortcut" and str(open.get("rubble", "")) == "cleared", "Guide readback changes only after the existing rubble job completes")
 _check(field.route_guide.snapshot == open, "Visible route guide refreshes to the authoritative completed state")
 _finish()

func _fresh_c_quarry() -> void:
 main = load("res://scenes/main.tscn").instantiate()
 main.set("first_region_a_pilot", true)
 main.set_meta("diagnostic_seed", 5112026)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 main.director.enabled = false
 if main.save_ui != null:
  main.save_ui.visible = false
  main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
 for worker in main.workers:
  worker.stop_work()
  for job in GameData.job_list():
   worker.priorities[job] = 0
 if not await _move_leg("b_forest") or not await _move_leg("c_quarry"):
  _check(false, "Fixture reaches stopped C quarry")
  main.queue_free()
  main = null

func _move_leg(destination: String) -> bool:
 if not main.world.request(destination):
  return false
 for unused in 320:
  main._process(STEP)
  await process_frame
  if main.world.phase == "stopped" and main.world.region == destination:
   return true
 return main.world.phase == "stopped" and main.world.region == destination

func _advance_until(session, predicate: Callable, seconds: float) -> bool:
 for unused in ceili(seconds / STEP):
  session.tick(STEP)
  var projected: Dictionary = session.apply_projection_to_workers(main)
  if not bool(projected.get("ok", false)):
   return false
  if predicate.call():
   return true
 return predicate.call()

func _finish() -> void:
 if field != null and is_instance_valid(field):
  var layer: Node = field.get_parent()
  field.queue_free()
  if layer != null:
   layer.queue_free()
 if main != null and is_instance_valid(main):
  main.queue_free()
 await process_frame
 SaveGame.disabled = false
 print("CANYON ROUTE GUIDE failures=", failures)
 quit(1 if failures else 0)
