extends SceneTree
const Snapshot=preload("res://bridge/c_field_snapshot.gd")
const Routes=preload("res://bridge/c_quarry_mine_rescue_routes.gd")
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
 check(SaveGame.apply(main,SaveGame.read("user://c-field-owner-waiting.json")),"load waiting file for explicit bounded geometry fixture")
 var field=main.mine_arrival_gate.field
 field.process_mode=Node.PROCESS_MODE_DISABLED
 var s=field.session
 # Deliberate geometry fixture, not natural play: preserve the real actors,
 # Main state and cargo while exercising the maximum two historical traces.
 for id in ["worker:0","worker:2"]:
  var a=s.actors[id]
  var points:Array=[s.BASE]
  for i in range(1,8192):points.append(s.BASE+Vector2(float(i)*0.001,100.0+float(a.worker_index)*100.0+float(i%2)*0.01))
  a.x=points[-1].x;a.y=points[-1].y
  var row={"actor":a,"gear":a.work_support,"points":points,"reason":"","departed":true}
  if a.work_support==GameData.Item.HANDCART:
   row["transported_by"]="worker:2";row["transport_gear"]=s.actors["worker:2"].work_support
  s.mine_rescue_traces._rows[id]=row
 check(s.request_rescue("worker:0","worker:2",s.session_id).get("ok",false),"existing planner accepts explicit bounded historical traces")
 check(s.actors["worker:2"].path.size()>10000,"actual owner path exceeds ordinary safe array limit")
 save("long")
 # Cap refusal is an inert provenance state, not a license to anchor on load.
 s.mine_rescue_traces._rows["worker:2"].reason=s.mine_rescue_traces.LIMIT_REASON
 save("capped")
 await finish()
func save(stage:String)->void:
 var path="user://field-bounded-"+stage+".json"
 check(SaveGame.write_field(main,path,true),"write complete bounded file "+stage)
 var d=SaveGame.read(path)
 check(not d.is_empty() and d.field_snapshot.session.actors["worker:2"].path is Dictionary,"real file contains bounded path chunks "+stage)
 var receipt=FileAccess.open(path+".receipt",FileAccess.WRITE)
 receipt.store_string(JSON.stringify({"pid":OS.get_process_id(),"hash":FileAccess.get_sha256(path)}));receipt.close()
func finish()->void:
 SaveGame.disabled=true
 main.queue_free()
 await process_frame
 print("C FIELD BOUNDED FILE assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
