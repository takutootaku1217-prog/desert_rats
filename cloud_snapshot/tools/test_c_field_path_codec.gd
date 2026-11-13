extends SceneTree
const Snapshot=preload("res://bridge/c_field_snapshot.gd")
const Session=preload("res://bridge/route_connection_session.gd")
const Routes=preload("res://bridge/c_quarry_mine_rescue_routes.gd")
var assertions:=0
var failures:=0
func check(ok:bool,label:String) -> void:
 assertions+=1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func _init() -> void:call_deferred("run")
func run() -> void:
 # Explicit bounded geometry fixture, not a claim of 8192 natural input events.
 var s=Session.new()
 s.mine_path_engineering=true
 s.session_id="codec-fixture"
 for id in ["worker:0","worker:1"]:
  var index=0 if id=="worker:0" else 1
  var points:Array=[s.BASE]
  for i in range(1,8192):points.append(s.BASE+Vector2(float(i)*0.001,100.0+float(index)*100.0+float(i%2)*0.01))
  var a={"worker_index":index,"work_support":-1,"entry_work_support":-1,"role":"escort","x":points[-1].x,"y":points[-1].y}
  s.actors[id]=a
  s.mine_rescue_traces._rows[id]={"actor":a,"gear":-1,"points":points,"reason":"","departed":true}
 var plan=Routes.plan(s,s.actors["worker:0"],Vector2(s.actors["worker:1"].x,s.actors["worker:1"].y),"worker:0","worker:1")
 check(plan.ok and plan.path.size()>10000 and plan.path.size()<=Snapshot.MAX_PATH,"real planner merges two bounded traces beyond global array cap")
 check(not SaveGame.safe(plan),"raw merged path is still rejected by unchanged global array limit")
 var encoded=Snapshot._paths_codec(plan,true)
 check(SaveGame.safe(encoded) and encoded.path is Dictionary and encoded.path.chunks.size()<=5,"bounded path chunks preserve global array safety")
 check(Snapshot._paths_codec(encoded,false)==plan,"chunk decode exactly restores every original vertex and witness")
 var bad=encoded.duplicate(true)
 bad.path.count=Snapshot.MAX_PATH+1
 check(Snapshot._paths_codec(bad,false).path==null,"oversized declared path rejected")
 bad=encoded.duplicate(true)
 bad.path.count+=1
 check(Snapshot._paths_codec(bad,false).path==null,"mismatched declared count rejected")
 bad=encoded.duplicate(true)
 bad.path.chunks[0].append([0.0,0.0])
 check(Snapshot._paths_codec(bad,false).path==null,"individual chunk cap enforced")
 bad=encoded.duplicate(true)
 bad.path.chunks[0][0]="bad point"
 check(Snapshot._paths_codec(bad,false).path==null,"malformed chunk vertex rejected")
 # The real trace limiter must not be healed by a serialization cycle.
 s.mine_rescue_traces._rows["worker:0"].reason=s.mine_rescue_traces.LIMIT_REASON
 var row=Routes._trace_copy(s,"worker:0")
 check(Snapshot._paths_codec(Snapshot._paths_codec(row,true),false).reason==s.mine_rescue_traces.LIMIT_REASON,"cap refusal remains explicit through codec")
 print("C FIELD PATH CODEC assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
