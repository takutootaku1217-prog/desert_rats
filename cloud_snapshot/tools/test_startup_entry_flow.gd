extends SceneTree
## Real configured scene/reload and isolated real files; no mocked save layer.
var main
var failures := 0
var assertions := 0
const MANUAL := "user://first-region-a-pilot-save.json"
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL", label])
 if not ok: failures += 1
func find_main(node: Node):
 if node.get_script() != null and node.get_script().resource_path == "res://scripts/main.gd": return node
 for child in node.get_children():
  var found = find_main(child)
  if found != null: return found
 return null
func settle() -> void:
 for unused in 4: await process_frame
 main = find_main(current_scene)
func button(ui, action: String) -> Button:
 for b in ui._action_buttons:
  if b.get_meta("save_action") == action: return b
 return null
func key(code: Key, shift := false) -> void:
 var event := InputEventKey.new()
 event.keycode = code; event.pressed = true; event.shift_pressed = shift
 root.push_input(event)
 await process_frame
 event = InputEventKey.new()
 event.keycode = code; event.pressed = false; event.shift_pressed = shift
 root.push_input(event)
 await process_frame
func run() -> void:
 var home := OS.get_environment("FLUID_TEST_HOME").replace("\\", "/").simplify_path().trim_suffix("/")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\", "/").simplify_path().begins_with(home + "/"): quit(2); return
 SaveGame.disabled = false
 SaveUI.skip_start_once = false
 check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "configured entry loads")
 await settle()
 check(main != null and main.first_region_a_pilot and main.world.region == "a_start" and main.world.phase == "stopped", "normal entry starts first region at stopped A")
 check(main.save_ui.path == SaveGame.FIRST_REGION_SAVE_PATH and main.save_ui.checkpoint_path == SaveGame.FIRST_REGION_CHECKPOINT_PATH, "normal entry owns separate first-region slots")
 check(main.save_ui.is_open() and paused, "empty profile waits for explicit first-start choice")
 check(not SaveGame.exists(SaveGame.FIRST_REGION_SAVE_PATH) and not SaveGame.exists(SaveGame.FIRST_REGION_CHECKPOINT_PATH) and not SaveGame.exists(SaveGame.FIRST_REGION_SAVE_PATH + ".bak"), "first-start menu writes no files")
 var ui = main.save_ui
 check(ui.has_method("open_start"), "startup selection is available after initialization")
 if not ui.has_method("open_start"): await finish(); return
 for action in ["save", "load", "backup", "checkpoint"]:
  check(button(ui, action).disabled, "empty startup disables " + action)
 await key(KEY_TAB)
 await key(KEY_TAB, true)
 check(root.gui_get_focus_owner() == button(ui, "new"), "Tab and Shift-Tab stay within enabled startup controls")
 await key(KEY_ENTER)
 check(ui._action == "new" and ui._confirm.visible and root.gui_get_focus_owner() == ui._confirm, "keyboard selects New and focuses confirmation")
 await key(KEY_ESCAPE)
 check(ui.is_open() and paused and ui._action == "", "keyboard cancellation preserves startup gate")
 ui.ask("new"); ui.close()
 check(ui.is_open() and paused and ui._action == "", "cancel returns to first-start choices without time advancing")
 ui.ask("save")
 check(ui._action == "", "startup cannot write before explicit start")
 await key(KEY_SPACE)
 check(ui._action == "new", "Space selects focused New")
 await key(KEY_ENTER)
 await settle()
 ui = main.save_ui
 check(main.first_region_a_pilot and main.world.region == "a_start" and not ui.is_open() and not paused, "confirmed new uses actual first-region scene reload without menu loop")
 check(not SaveGame.exists(ui.path), "new game does not create manual save")
 main.process_mode = Node.PROCESS_MODE_DISABLED
 main.director.enabled = false
 main.town.credits = 321
 check(SaveGame.write(main, ui.path, true), "real manual fixture writes")
 var manual_hash := FileAccess.get_sha256(ui.path)
 ui.open_start()
 check(not button(ui, "load").disabled and button(ui, "backup").disabled and button(ui, "checkpoint").disabled, "manual-only profile enables only ordinary continue")
 ui.ask("new"); ui.close()
 check(FileAccess.get_sha256(ui.path) == manual_hash and main.town.credits == 321, "cancel new preserves file and runtime")
 main.town.credits = 12
 ui.ask("load"); ui.execute(); ui.close()
 check(main.town.credits == 321 and not ui.is_open() and not paused, "confirmed ordinary load resumes without checkpoint fee")
 check(FileAccess.get_sha256(ui.path) == manual_hash, "continue never rewrites source")
 var backup_path: String = ui.path + ".bak"
 check(DirAccess.rename_absolute(ui.path, backup_path) == OK, "isolate backup-only fixture")
 ui.open_start()
 check(button(ui, "load").disabled and not button(ui, "backup").disabled, "backup-only profile cannot falsely offer ordinary continue")
 main.town.credits = 9
 ui.ask("backup"); ui.execute(); ui.close()
 check(main.town.credits == 321 and FileAccess.get_sha256(backup_path) == manual_hash, "backup-only recovery restores without rewrite")
 check(SaveGame.write_checkpoint(main), "checkpoint fixture writes with actual API")
 var checkpoint_hash := FileAccess.get_sha256(ui.checkpoint_path)
 check(DirAccess.remove_absolute(backup_path) == OK, "remove only test-owned backup fixture")
 ui.open_start()
 check(button(ui, "load").disabled and button(ui, "backup").disabled and not button(ui, "checkpoint").disabled, "checkpoint-only offers retry not ordinary continue")
 ui.ask("checkpoint"); ui.execute(); ui.close()
 check(main.town.credits == 289 and FileAccess.get_sha256(ui.checkpoint_path) == checkpoint_hash, "checkpoint fee once and source immutable")
 var corrupt = FileAccess.open(ui.path, FileAccess.WRITE)
 corrupt.store_string("startup-test-invalid"); corrupt.close()
 var corrupt_hash := FileAccess.get_sha256(ui.path)
 ui.open_start(); ui.ask("load"); ui.execute(); ui.close()
 check(ui.is_open() and paused and main.town.credits == 289, "corrupt load remains safely in startup choice")
 check(FileAccess.get_sha256(ui.path) == corrupt_hash, "corrupt file preserved")
 ui.ask("new"); ui.execute()
 await settle()
 check(main.first_region_a_pilot and not main.save_ui.is_open() and not paused, "confirmed new with existing slots also skips startup only once")
 check(FileAccess.get_sha256(main.save_ui.path) == corrupt_hash and FileAccess.get_sha256(main.save_ui.checkpoint_path) == checkpoint_hash, "new preserves every existing first-region slot")
 check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "subsequent ordinary entry loads")
 await settle()
 check(main.save_ui.is_open() and paused, "one-shot skip does not leak to next startup")
 paused = false
 SaveGame.disabled = true
 check(change_scene_to_file("res://scenes/main.tscn") == OK, "direct legacy Main still loads")
 await settle()
 check(not main.first_region_a_pilot and main.save_ui.path == SaveGame.PATH and not main.save_ui.is_open(), "direct headless Main keeps diagnostic compatibility")
 await finish()
func finish() -> void:
 paused = false
 SaveGame.disabled = true
 if current_scene != null: current_scene.queue_free()
 await process_frame
 print("STARTUP ENTRY assertions=", assertions, " failures=", failures)
 quit(0 if failures == 0 else 1)
