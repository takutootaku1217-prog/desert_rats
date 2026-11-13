extends SceneTree
const Snapshot=preload("res://bridge/c_field_snapshot.gd")
var main
var assertions:=0
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1;print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func run()->void:
 var home:=OS.get_environment("FLUID_TEST_HOME").replace("\\","/").simplify_path().trim_suffix("/")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").simplify_path().begins_with(home+"/"):quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main)
 await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;SaveGame.disabled=false
 for stage in ["long","capped"]:
  var path="user://field-bounded-"+stage+".json"
  var d=SaveGame.read(path)
  check(not d.is_empty(),"read bounded complete file "+stage)
  if d.is_empty():continue
  var receipt=JSON.parse_string(FileAccess.get_file_as_string(path+".receipt"))
  check(receipt.pid!=OS.get_process_id() and receipt.hash==FileAccess.get_sha256(path),"distinct process reads exact file hash "+stage)
  check(SaveGame.apply(main,d),"restore bounded complete file "+stage)
  var field=main.mine_arrival_gate.field
  field.process_mode=Node.PROCESS_MODE_DISABLED
  var s=field.session
  var decoded=Snapshot._paths_codec(d.field_snapshot,false)
  check(s.actors["worker:2"].path==decoded.session.actors["worker:2"].path and s.actors["worker:2"].path.size()>10000,"every long waypoint preserved "+stage)
  check(s.mine_rescue_traces._rows["worker:2"].points==decoded.traces["worker:2"].points,"all 8192 current trace vertices preserved "+stage)
  check(s.elapsed==decoded.session.elapsed and s.life_clock_token!=decoded.session.life_clock_token,"new clock preserves paid elapsed "+stage)
  if stage=="long":
   field._toggle_field_pause()
   var clock=field.life_clock
   var old_position=Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)
   var old_paid=s.life_clock_paid
   clock.tick(0.00001)
   check(Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)!=old_position,"restored long path actually advances through live clock")
   check(absf(s.life_clock_paid-old_paid-0.00001)<0.000001,"restored long movement pays only its new delta")
   var moved_path=s.actors["worker:2"].path.duplicate(true)
   var moved_position=Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)
   var actual_reason=s.mine_rescue_traces.invalid_reason("worker:2")
   check(SaveGame.write_field(main,"user://field-bounded-continued.json",true),"save the actual advanced long-path state")
   check(SaveGame.apply(main,SaveGame.read("user://field-bounded-continued.json")),"restore the actual advanced long-path state")
   field=main.mine_arrival_gate.field
   field.process_mode=Node.PROCESS_MODE_DISABLED
   s=field.session
   check(not clock.is_current() and s.actors["worker:2"].path==moved_path and Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)==moved_position,"continued restore retains exact path and position with fresh clock")
   check(s.mine_rescue_traces.invalid_reason("worker:2")==actual_reason,"continued restore never heals the actual cap or provenance state")
  if stage=="capped":
   check(s.mine_rescue_traces.needs_anchor("worker:2") and s.mine_rescue_traces.invalid_reason("worker:2")==s.mine_rescue_traces.LIMIT_REASON,"cap refusal remains invalid after fresh restore")
   check(s.cancel_rescue("worker:0",s.session_id).get("ok",false),"cancel bounded assignment explicitly")
   check(not s.request_rescue("worker:0","worker:2",s.session_id).get("ok",false),"reload does not heal cap to allow a new rescue")
  var before=SaveGame.capture(main)
  var bad=d.duplicate(true)
  bad.field_snapshot.session.actors["worker:2"].path.count=Snapshot.MAX_PATH+1
  check(not SaveGame.apply(main,bad) and SaveGame.capture(main)==before,"malformed bounded file rejects before live mutation "+stage)
  check(FileAccess.get_sha256(path)==receipt.hash,"consumer never rewrites producer file "+stage)
 SaveGame.disabled=true
 main.queue_free()
 await process_frame
 print("C FIELD BOUNDED RESTART assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
