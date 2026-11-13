extends SceneTree
const Session = preload("res://bridge/route_connection_session.gd")
var main
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
 assertions+=1; print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures+=1
func pos(a: Dictionary) -> Vector2: return Vector2(a.x,a.y)
func fresh():
 var result:Dictionary=Session.create_from_game(main,"traces",{"mine_path_engineering":true})
 check(result.ok,"real default C source creates ordinary session")
 return result.session
func advance(s,predicate:Callable,limit:=1800) -> bool:
 for i in limit:
  if predicate.call():return true
  s.tick(0.05)
 return predicate.call()
func down(s,id:String) -> void:s._begin_outpost_down(id,s.actors[id])
func rescue(s,target:String,carrier:String,label:String) -> bool:
 var before:=pos(s.actors[carrier]);var target_before:=pos(s.actors[target])
 var r:Dictionary=s.request_rescue(target,carrier,s.session_id)
 check(r.ok,label+" accepts")
 if not r.ok: print("  reason ",r.reason);return false
 check(pos(s.actors[carrier])==before and pos(s.actors[target])==target_before,label+" assignment never snaps")
 check(advance(s,func():return s.actors[carrier].state=="rescue_hold"),label+" reaches exact hold")
 check(pos(s.actors[carrier])==pos(s.actors[target]),label+" exact pickup")
 var returned:Dictionary=s.request_rescue_return(target,s.session_id)
 check(returned.ok,label+" explicit return")
 if not returned.ok:print("  return reason ",returned.reason)
 check(advance(s,func():return s.actors[target].state=="rescue_treatment"),label+" physical return completes")
 check(pos(s.actors[target])==Session.BASE and s.conservation_ok(),label+" entrance and conservation")
 return true
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true;main.set_meta("diagnostic_seed",104729)
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for region in ["b_forest","c_quarry"]:
  check(main.world.request(region),"real trip "+region)
  for i in 400:
   main._process(0.25);await process_frame
   if main.world.region==region and main.world.phase=="stopped":break
 test_natural()
 test_maintenance()
 test_boundaries()
 test_drop()
 test_live_bindings()
 test_crossing()
 main.queue_free();await process_frame
 print("C RESCUE TRACES assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
func test_natural() -> void:
 var s=fresh()
 for i in 80:s.tick(0.05)
 check(s.actors["worker:2"].state=="escort" and pos(s.actors["worker:2"])!=Session.BASE,"natural escort moves without state or coordinate injection")
 down(s,"worker:0")
 rescue(s,"worker:0","worker:2","natural escort")
func test_maintenance() -> void:
 for stage in ["complete","cancel","down_move","down_work"]:
  var s=fresh()
  check(s.request_mine_path_clearance().ok,"start real maintenance "+stage)
  if stage=="complete":check(advance(s,func():return s.intermediate_access=="cleared"),"actual rubble work finishes")
  elif stage=="down_work":check(advance(s,func():return s.actors["worker:2"].state=="maintenance_work"),"actual escort reaches rubble")
  else:s.tick(0.35)
  if stage=="cancel":check(s.cancel_mine_path_clearance().ok,"actual maintenance cancel")
  if stage.begins_with("down"):
   down(s,"worker:2")
   check(s.maintenance_actor_id.is_empty() and s.intermediate_access=="blocked","down releases maintenance ownership "+stage)
   rescue(s,"worker:2","worker:1",stage)
  else:
   down(s,"worker:0")
   rescue(s,"worker:0","worker:2",stage)

func natural_down():
 var s=fresh()
 for i in 40:s.tick(0.05)
 down(s,"worker:0")
 return s
func rejected(s,label:String) -> void:
 var before:Dictionary=s.to_dict()
 var result:Dictionary=s.request_rescue("worker:0","worker:2",s.session_id)
 check(not result.ok and s.to_dict()==before,label+" rejects without public mutation")
func test_boundaries() -> void:
 var s=natural_down()
 s.actors["worker:2"].x+=77.0
 rejected(s,"forged position")
 s=natural_down()
 s.actors["worker:2"]=s.actors["worker:2"].duplicate(true)
 rejected(s,"replaced actor with same values")
 s=natural_down()
 s.actors["worker:2"].work_support=GameData.Item.HANDCART
 rejected(s,"cart cannot inherit foot trail")
 s.actors["worker:2"].work_support=-1
 rejected(s,"observed equipment change cannot revive old trail")
 s=fresh()
 for i in 40:s.tick(0.05)
 var loaded:Dictionary=Session.from_dict(s.to_dict())
 check(loaded.ok,"ordinary off-corridor session snapshot fixture restores without trusted trails")
 if loaded.ok:
  down(loaded.session,"worker:0")
  rejected(loaded.session,"restored off-corridor provenance")
 s=fresh()
 for i in 3:s.tick(0.05)
 # Synthetic ledger boundary fixture, not a claim of long-duration simulation.
 var points:Array=s.mine_rescue_traces._rows["worker:2"].points
 while points.size()<s.mine_rescue_traces.MAX_POINTS:points.append(points[-1])
 s.tick(0.001)
 down(s,"worker:0")
 var limited:Dictionary=s.request_rescue("worker:0","worker:2",s.session_id)
 check(not limited.ok and "上限" in limited.reason,"bounded trace overflow has explicit refusal reason")
 s=natural_down()
 check(s.request_rescue("worker:0","worker:2",s.session_id).ok,"target mutation fixture begins rescue")
 var carrier_start:=pos(s.actors["worker:2"])
 s.actors["worker:0"].x+=77.0
 s.tick(0.05)
 check(s.rescue_ledger.case_for("worker:0").phase=="waiting" and s.actors["worker:2"].state!="rescue_move","moved target invalidates previously approved approach")
 check(pos(s.actors["worker:2"]).distance_to(carrier_start)<=11.501,"invalid target cannot cause a jump")
 s=natural_down()
 check(s.request_rescue("worker:0","worker:2",s.session_id).ok,"path tamper fixture begins rescue")
 s.actors["worker:2"].path_index=s.actors["worker:2"].path.size()-1
 s.tick(0.05)
 check(s.rescue_ledger.case_for("worker:0").phase=="waiting","skipping approved path vertices interrupts before movement")
func test_drop() -> void:
 var s=fresh()
 s.request_mine_path_clearance();s.tick(0.35);down(s,"worker:2")
 check(s.request_rescue("worker:2","worker:1",s.session_id).ok,"off-corridor dropped target starts")
 check(advance(s,func():return s.actors["worker:1"].state=="rescue_hold"),"off-corridor pickup")
 check(s.request_rescue_return("worker:2",s.session_id).ok,"off-corridor return starts")
 s.tick(0.05)
 var dropped:=pos(s.actors["worker:2"])
 var left:float=s.rescue_ledger.case_for("worker:2").left
 check(s.cancel_rescue("worker:2",s.session_id).ok,"cancel on witnessed trail")
 check(pos(s.actors["worker:2"])==dropped and s.rescue_ledger.case_for("worker:2").left==left,"off-corridor cancellation preserves exact drop and timer")
 check(s.request_rescue("worker:2","worker:1",s.session_id).ok,"dropped target has new endpoint provenance")
 check(advance(s,func():return s.actors["worker:1"].state=="rescue_hold"),"same-position repickup")
 check(s.request_rescue_return("worker:2",s.session_id).ok,"reassigned transport accepted")
 s.tick(0.02);s.set_all_routes_closed(true)
 var closed_pos:=pos(s.actors["worker:2"])
 s.tick(0.2)
 check(pos(s.actors["worker:2"])==closed_pos and s.rescue_ledger.case_for("worker:2").phase=="waiting","closed routes drop exactly and prevent transport")
 s.set_all_routes_closed(false)
 check(s.request_rescue("worker:2","worker:1",s.session_id).ok,"reopened route can recover traced target")
 check(advance(s,func():return s.actors["worker:1"].state=="rescue_hold"),"reopen pickup")
 check(s.request_rescue_return("worker:2",s.session_id).ok,"reopen return accepted")
 check(advance(s,func():return s.actors["worker:2"].state=="rescue_treatment") and s.conservation_ok(),"reopened trace return reaches treatment without cargo duplication")

func test_live_bindings() -> void:
 for mode in ["gear","target_move","target_hold","carrier_hold","release_path"]:
  var s=natural_down()
  check(s.request_rescue("worker:0","worker:2",s.session_id).ok,"live binding fixture starts "+mode)
  if mode in ["target_hold","carrier_hold"]:
   check(advance(s,func():return s.actors["worker:2"].state=="rescue_hold"),"live binding reaches hold "+mode)
  if mode=="gear":s.actors["worker:2"].work_support=GameData.Item.HANDCART
  elif mode in ["target_move","target_hold"]:s.actors["worker:0"]=s.actors["worker:0"].duplicate(true)
  elif mode=="carrier_hold":s.actors["worker:2"]=s.actors["worker:2"].duplicate(true)
  else:
   s.tick(0.05)
   s.cancel_rescue("worker:0",s.session_id)
   s.actors["worker:2"].path_index=s.actors["worker:2"].path.size()-1
  var before:=pos(s.actors["worker:2"])
  if mode in ["target_hold","carrier_hold"]:
   check(not s.request_rescue_return("worker:0",s.session_id).ok,"held binding replacement refuses transport "+mode)
  s.tick(0.05)
  check(s.rescue_ledger.case_for("worker:0").phase=="waiting","live identity/gear mutation interrupts "+mode)
  if mode in ["gear","release_path","carrier_hold"]:check(pos(s.actors["worker:2"])==before,"invalid live owner never advances old path "+mode)

func test_crossing() -> void:
 var s=fresh()
 var a:Dictionary=s.actors["worker:2"]
 var origin:=pos(a)
 var crossing:=Session.BASE.lerp(Session.MINE_PATH_STEP,0.5)
 var off:=crossing+Vector2(0,40)
 # Unit-level authenticated movement-hook fixture, not ordinary gameplay.
 for point in [off,crossing]:
  var step:Dictionary=s.mine_rescue_traces.begin_step(s,"worker:2")
  a.x=point.x;a.y=point.y
  s.mine_rescue_traces.end_step(s,"worker:2",step)
 var endpoint:Dictionary=s.mine_rescue_traces.endpoint(s,"worker:2",a)
 check(endpoint.ok and endpoint.points.size()==3 and endpoint.points[0]==origin,"trace crossing canonical segment does not invent a junction")
 s.actors["worker:0"].x=Session.RESOURCE.x;s.actors["worker:0"].y=Session.RESOURCE.y;down(s,"worker:0")
 check(s.request_rescue("worker:0","worker:2",s.session_id).ok,"crossing fixture can use original witnessed anchor")
 check(a.path[0]==[off.x,off.y],"planner reverses witnessed trail instead of cutting at crossing")
 s.cancel_rescue("worker:0",s.session_id)
 a.work_support=GameData.Item.HANDCART
 s.request_rescue("worker:0","worker:2",s.session_id)
 a.work_support=-1
 rejected(s,"invalid historical trail at non-anchor crossing")
 s=natural_down()
 s._begin_injured_return("worker:2",s.actors["worker:2"])
 s.tick(0.01)
 var unsupported:Dictionary=s.mine_rescue_traces.endpoint(s,"worker:2",s.actors["worker:2"])
 check(not unsupported.ok,"unrelated legacy injury direct path cannot authorize off-corridor rescue trail")
