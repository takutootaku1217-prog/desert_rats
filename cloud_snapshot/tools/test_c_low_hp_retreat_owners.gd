extends SceneTree
## Real boss movement with explicitly injected lethal/expiry boundary fixtures.
## Producer of a targeted healthy rescue return for a separate-process restart.
const Session=preload("res://bridge/route_connection_session.gd")
const PATH="user://low-hp-target-return.json"
var main
var assertions:=0
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1;print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func advance(clock,predicate:Callable,seconds:float)->bool:
 for unused in ceili(seconds/0.05):
  if predicate.call():return true
  clock.tick(0.05)
 return predicate.call()
func restored(saved:Dictionary):
 check(SaveGame.apply(main,saved),"restore exact combat boundary fixture")
 paused=false;main.process_mode=Node.PROCESS_MODE_DISABLED
 var field=main.mine_arrival_gate.field;field.process_mode=Node.PROCESS_MODE_DISABLED
 return field
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"ordinary route "+destination)
  for unused in 300:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
 main.workers[2].hp=33.0 # Explicit boundary fixture, not ordinary injury evidence.
 var gate=main.mine_arrival_gate;gate._process(0.0);SaveGame.disabled=false
 check(gate.enter_boss(),"enter actual boss")
 if gate.field==null:await finish();return
 var field=gate.field;field.process_mode=Node.PROCESS_MODE_DISABLED;var s=field.session
 check(advance(field.life_clock,func():return s.actors["worker:2"].state=="combat",60.0),"authentic combat approach creates witnessed position")
 var combat:=SaveGame.capture(main)
 check(SaveGame.validate(combat,main),"combat control snapshot validates")
 for mode in ["injury","recall"]:
  field=restored(combat);s=field.session
  if mode=="injury":check(advance(field.life_clock,func():return s.outpost_retreats>0,10.0),"real hits start injury retreat")
  else:s.request_recall()
  field.life_clock.tick(0.05)
  check(s.rescue_approach.has_mine_return("worker:2"),"boss return uses existing safe route owner: "+mode)
  check(s.mine_rescue_traces.endpoint(s,"worker:2",s.actors["worker:2"]).ok,"moving boss return retains authenticated trace: "+mode)
  var returned:=SaveGame.capture(main)
  check(SaveGame.validate(returned,main),"moving safe-owner return is saveable: "+mode)
  var actor:Dictionary=s.actors["worker:2"]
  var distance:=0.0;var previous:=Vector2(actor.x,actor.y)
  for i in range(actor.path_index,actor.path.size()):
   var point:=Vector2(actor.path[i][0],actor.path[i][1]);distance+=previous.distance_to(point);previous=point
  var start_time:float=s.elapsed;var start_hp:float=actor.hp
  check(advance(field.life_clock,func():return s.actors["worker:2"].state in ["injured_wait","idle"],30.0),"live safe return reaches entrance with unchanged combat values: "+mode)
  print("BOSS_RETURN_OBSERVATION ",JSON.stringify({"mode":mode,"remaining_distance":distance,"seconds":s.elapsed-start_time,"hp_before":start_hp,"hp_after":s.actors["worker:2"].hp,"at_base":Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)==s.BASE,"fixture":"initial HP33, actual combat and movement"}))
  field=restored(returned);s=field.session
  s.set_all_routes_closed(true)
  s.actors["worker:2"].hp=1.5 # Lethal-hit boundary, not a natural-down claim.
  s._apply_outpost_hit("worker:2",FirstRegionCompletion.BOSS_ID)
  field.life_clock.tick(0.05)
  check(s.actors["worker:2"].down,"blocked exposed return can down: "+mode)
  s.set_all_routes_closed(false)
  check(s.request_rescue("worker:2","worker:0",s.session_id).ok,"authentic return-down position remains manually rescuable: "+mode)
  # Current owner must reject a changed path rather than authorizing a new chord.
  field=restored(returned);s=field.session
  if s.rescue_approach.has_mine_return("worker:2"):
   var a:Dictionary=s.actors["worker:2"];var here:=Vector2(a.x,a.y)
   a.path=[[150.0,535.0]];a.path_index=0
   field.life_clock.tick(0.05)
   check(Vector2(a.x,a.y)==here and a.state=="safe_wait","changed return command cannot reuse old witness: "+mode)
   s.request_recall()
   advance(field.life_clock,func():return s.actors["worker:0"].state=="idle" and s.actors["worker:1"].state=="idle",15.0)
   check(not s._local_exit_ready() and s.phase!="ready_to_exit","invalid outdoor return owner cannot authorize remote exit: "+mode)
  for mutation in ["gear","identity"]:
   field=restored(returned);s=field.session
   var a:Dictionary=s.actors["worker:2"];var here:=Vector2(a.x,a.y)
   if mutation=="gear":a.work_support=GameData.Item.HANDCART
   else:s.actors["worker:2"]=a.duplicate(true)
   field.life_clock.tick(0.05)
   a=s.actors["worker:2"]
   check(Vector2(a.x,a.y)==here and a.state=="safe_wait","changed "+mutation+" cannot reuse return owner: "+mode)
  var stale:=returned.duplicate(true);stale.field_snapshot.session.session_id="previous-session"
  check(not SaveGame.validate(stale,main),"session identity cannot reuse return snapshot: "+mode)
 # A normal rescue-origin nonescort return has target ownership before load.
 field=restored(combat);s=field.session
 s._begin_outpost_down("worker:2",s.actors["worker:2"]);field.life_clock.tick(0.05)
 check(s.request_rescue("worker:2","worker:0",s.session_id).ok,"available harvest role starts actual rescue")
 check(advance(field.life_clock,func():return s.rescue_ledger.case_for("worker:2").get("phase")=="carried",15.0),"rescuer physically reaches body")
 check(s.cancel_rescue("worker:2",s.session_id).ok,"cancel creates existing healthy mine return")
 field.life_clock.tick(0.05)
 var enemy:Dictionary=s.outpost_enemies[FirstRegionCompletion.BOSS_ID]
 check(enemy.target=="worker:0" and s.actors["worker:0"].hp>30.0 and s.rescue_approach.has_mine_return("worker:0"),"boss targets healthy nonescort rescue-owned return")
 var healthy:=SaveGame.capture(main)
 check(SaveGame.validate(healthy,main),"complete validation sees restored nonescort return owner")
 check(SaveGame.write_field(main,PATH,true),"write targeted return for independent-process restart")
 if SaveGame.validate(healthy,main):
  field=restored(healthy);s=field.session
  check(s.outpost_enemies[FirstRegionCompletion.BOSS_ID].target=="worker:0" and s.rescue_approach.has_mine_return("worker:0"),"target and owner survive full apply")
 # Existing post-expiry owner is protected; forging an enemy target must fail.
 field=restored(combat);s=field.session
 s._begin_outpost_down("worker:2",s.actors["worker:2"]);field.life_clock.tick(0.05)
 field.life_clock.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 check(s.expired_recovery.owns("worker:2"),"existing provisional expiry owner starts physical return")
 var expired:=SaveGame.capture(main)
 check(SaveGame.validate(expired,main),"unforged expiry-return snapshot is coherent")
 var forged:=expired.duplicate(true)
 forged.field_snapshot.session.outpost_enemies[FirstRegionCompletion.BOSS_ID].target="worker:2"
 check(not SaveGame.validate(forged,main),"restored protected expiry owner rejects forged enemy target")
 check(advance(field.life_clock,func():return s.actors["worker:2"].state=="injured_wait",30.0),"expiry return can still reach safe entrance")
 # Malformed enemies must fail before owner code reads their fields.
 forged=healthy.duplicate(true);forged.field_snapshot.session.outpost_enemies[FirstRegionCompletion.BOSS_ID]=17
 check(not SaveGame.validate(forged,main),"malformed enemy remains safely rejected before owner validation")
 await finish()
func finish()->void:
 SaveGame.disabled=true
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("C LOW HP OWNERS assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
