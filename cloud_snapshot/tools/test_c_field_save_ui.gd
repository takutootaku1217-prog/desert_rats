extends SceneTree
var main
var assertions:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
 assertions+=1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures+=1
func run() -> void:
 var home:=OS.get_environment("FLUID_TEST_HOME").replace("\\","/").simplify_path().trim_suffix("/")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").simplify_path().begins_with(home+"/"):quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 root.add_child(main)
 await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 SaveGame.disabled=false
 var saved=SaveGame.read("user://c-field-owner-assigned.json")
 check(not saved.is_empty() and SaveGame.apply(main,saved),"load assigned source fixture")
 if saved.is_empty():await finish();return
 var gate=main.mine_arrival_gate
 var field=gate.field
 field.process_mode=Node.PROCESS_MODE_DISABLED
 var ui=main.save_ui
 ui.path="user://field-public-ui.json"
 var entry=field.get_node_or_null("FieldVehicleStatus/Contents/Actions/Save")
 check(entry is Button,"field exposes manual save and resume entry")
 if entry is Button:entry.pressed.emit()
 else:ui.open()
 check(ui.is_open() and paused and ui.layer>gate.layer,"field save modal pauses above field controls")
 var before=field.session.to_dict()
 ui.ask("save");ui._confirm.pressed.emit()
 check(SaveGame.exists(ui.path),"public confirmation writes complete field file")
 check(field.session.to_dict()==before,"public save is side effect free")
 if not SaveGame.exists(ui.path):await finish();return
 var first_hash=FileAccess.get_sha256(ui.path)
 ui.ask("save");ui._confirm.pressed.emit()
 check(FileAccess.get_sha256(ui.path+".bak")==first_hash,"confirmed overwrite retains prior complete backup")
 ui.close()
 check(paused and field._owns_field_pause,"closing original paused menu preserves field pause")
 field._toggle_field_pause()
 check(not paused,"field pause control resumes")
 ui.open();ui.ask("backup");ui._confirm.pressed.emit()
 check(gate.field!=field and ui.is_open() and paused,"public load replaces runtime while paused")
 field=gate.field
 field.process_mode=Node.PROCESS_MODE_DISABLED
 ui.close()
 check(paused and field._owns_field_pause,"closing loaded menu leaves explicit paused field")
 field._toggle_field_pause()
 check(not paused,"restored field has usable resume control")
 check(gate.fail_field_to_menu("QA failure"),"enter actual field failure menu")
 check(ui._field_failure_lock and main.game_over,"failure blocks saving and owns pause")
 ui.ask("save")
 check(ui._action=="","failed state cannot invoke manual save")
 ui.ask("load");ui._confirm.pressed.emit()
 check(not ui._field_failure_lock and not main.game_over and gate.field!=null,"failure menu restores complete field")
 check(SaveGame.disabled and gate._save_override_active and not gate._save_was_disabled,"failure release preserves field override and original enabled policy")
 ui.close()
 check(paused,"failure field load remains paused")
 field=gate.field
 field.process_mode=Node.PROCESS_MODE_DISABLED
 field._toggle_field_pause()
 var s=field.session
 var clock=field.life_clock
 for unused in 1800:
  var row=s.rescue_ledger.case_for("worker:0")
  if row.get("phase")=="carried" and s.actors["worker:2"].state=="rescue_hold":s.request_rescue_return("worker:0",s.session_id)
  if s.phase=="ready_to_exit":break
  clock.tick(0.05)
 check(s.phase=="ready_to_exit","UI restored rescue physically finishes")
 field._commit_and_exit()
 check(gate.field==null and not SaveGame.disabled,"field exit returns original ordinary saving policy")
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var normal=SaveGame.capture(main)
 check(SaveGame.write(main,"user://field-ui-normal.json",true),"prepare ordinary return fixture")
 for baseline in [false,true]:
  SaveGame.disabled=baseline
  check(SaveGame.apply(main,saved),"install field with original saving policy "+str(baseline))
  gate.field.process_mode=Node.PROCESS_MODE_DISABLED
  gate.field._toggle_field_pause()
  ui.open();ui.close()
  check(not paused,"running field open/cancel preserves running time policy")
  for repeat in 2:
   check(gate.fail_field_to_menu("QA repeated failure"),"repeat failure "+str(repeat))
   ui.path="user://field-public-ui.json"
   var hash=FileAccess.get_sha256(ui.path)
   ui.ask("load");ui._confirm.pressed.emit()
   check(ui.layer>gate.layer and SaveGame.disabled and gate._save_was_disabled==baseline,"failure recovery transfers original policy and keeps modal on top")
   gate.field.process_mode=Node.PROCESS_MODE_DISABLED
   ui.ask("save");ui._confirm.pressed.emit()
   check(not baseline or FileAccess.get_sha256(ui.path)==hash,"diagnostic policy blocks saving without rewriting file")
   ui.close()
   check(paused,"repeated recovery remains paused")
  var old=gate.field
  var old_clock=old.life_clock
  var malformed=saved.duplicate(true)
  malformed.field_snapshot.schema=-100
  check(not SaveGame.apply(main,malformed) and gate.field==old and old_clock.is_current(),"invalid complete load retains current field and clock")
  ui.path="user://field-ui-normal.json"
  ui.open();ui.ask("load");ui._confirm.pressed.emit();ui.close()
  check(gate.field==null and not paused and SaveGame.disabled==baseline,"field to ordinary UI load preserves baseline and resumes")
  check(SaveGame.capture(main)==normal,"field to ordinary load does not commit its cargo")

 await finish()
func finish() -> void:
 SaveGame.disabled=true
 if is_instance_valid(main):main.queue_free()
 await process_frame
 print("C FIELD SAVE UI assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
