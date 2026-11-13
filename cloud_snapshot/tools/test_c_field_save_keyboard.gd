extends SceneTree
var main
var failures:=0
func check(ok:bool,label:String)->void:
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func _init()->void:call_deferred("run")
func press_enter()->void:
 var down=InputEventKey.new()
 down.keycode=KEY_ENTER;down.physical_keycode=KEY_ENTER;down.pressed=true
 root.push_input(down)
 await process_frame
 var up=InputEventKey.new()
 up.keycode=KEY_ENTER;up.physical_keycode=KEY_ENTER;up.pressed=false
 root.push_input(up)
 await process_frame
func run()->void:
 var home:=OS.get_environment("FLUID_TEST_HOME").replace("\\","/").simplify_path().trim_suffix("/")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").simplify_path().begins_with(home+"/"):quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main)
 await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 SaveGame.disabled=false
 check(SaveGame.apply(main,SaveGame.read("user://c-field-owner-waiting.json")),"load local waiting fixture")
 var field=main.mine_arrival_gate.field
 field.process_mode=Node.PROCESS_MODE_INHERIT
 var button=field.get_node("FieldVehicleStatus/Contents/Actions/Return")
 main.save_ui.open()
 button.grab_focus()
 await press_enter()
 check(field.session.phase=="local","open modal blocks Enter on focused field return")
 main.save_ui.close()
 button.grab_focus()
 await press_enter()
 check(field.session.phase=="recall","same Enter reaches field after modal closes")
 SaveGame.disabled=true
 main.queue_free()
 await process_frame
 print("C FIELD SAVE KEYBOARD failures=",failures)
 quit(0 if failures==0 else 1)
