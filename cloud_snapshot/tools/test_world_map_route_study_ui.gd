extends SceneTree
## Presentation contract only.  The route-study panel must read the existing
## region state without becoming a second engineering or journey command path.

var main
var failures := 0

func _init() -> void:
 call_deferred("_run")

func _check(ok: bool, message: String) -> void:
 print("  %s %s" % ["ok" if ok else "FAIL", message])
 if not ok:
  failures += 1

func _run() -> void:
 SaveGame.disabled = true
 main = load("res://scenes/main.tscn").instantiate()
 main.set("first_region_a_pilot", true)
 main.set_meta("diagnostic_seed", 5112026)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 if main.save_ui != null:
  main.save_ui.visible = false
  main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
 var before: Dictionary = main.world.region_state.duplicate(true)
 main.map_ui.open()
 await process_frame
 var study: Node = main.map_ui.find_child("RouteStudy", true, false)
 _check(study != null, "First-region map exposes a named route-study display")
 if study != null:
  _check(not study.visible, "Route-study cards begin collapsed so ordinary destination controls stay readable")
  main.map_ui._route_study_toggle.emit_signal("pressed")
  await process_frame
  _check(study.visible and study.get_child_count() >= 5, "Opening route study shows the existing routes, two engineering states, and a future-only comparison")
  var text := ""
  for child in study.get_children():
   if child is Label:
    text += child.text + "\n"
  _check(text.contains("future") or text.contains("����") or text.contains("未実装"), "Risky travel remains visibly future-only rather than an executable route")
 _check(main.world.region_state == before, "Opening and refreshing the route-study UI never mutates road state")
 main.map_ui.close()
 main.queue_free()
 await process_frame
 SaveGame.disabled = false
 print("WORLD MAP ROUTE STUDY UI failures=", failures)
 quit(1 if failures else 0)
