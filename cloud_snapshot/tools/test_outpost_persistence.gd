extends SceneTree
const Session=preload("res://bridge/route_connection_session.gd")
const PATH:="user://outpost-persistence.json"
var main
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func advance(session,predicate:Callable,seconds:float)->bool:
 for tick in ceili(seconds/0.2):
  session.tick(0.2)
  if not session.apply_projection_to_workers(main).get("ok",false):return false
  if predicate.call():return true
 return predicate.call()
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"request real route to "+destination)
  for tick in range(300):
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
  check(main.world.region==destination,"arrive at "+destination)
 var before:=SaveGame.capture(main)
 var made:Dictionary=Session.create_from_game(main,"persistent-clear",{"outpost_enabled":true})
 check(made.get("ok",false),"create real outpost session")
 if not made.get("ok",false):await finish();return
 var session=made.session
 check(advance(session,func():return session.outpost_cleared,180.0),"existing combat clears all three guards")
 check(advance(session,func():return int(session.state_summary().depot)>0,100.0),"real cleared outpost produces finite cargo for conservation test")
 var before_commit:=SaveGame.capture(main)
 check(before_commit.world==before.world,"uncommitted combat does not change authoritative world record")
 session.request_recall()
 check(advance(session,func():return session.phase=="ready_to_exit",100.0),"all actors and cargo return before commit")
 var unchanged:Dictionary=main.world.outpost_states.duplicate(true)
 var stock_before:Dictionary=main.storage.inventory.counts.duplicate(true)
 var first_actor:String=session.actors.keys()[0]
 session.actors[first_actor].down=true
 check(not session.commit_to_game(main).get("ok",false) and main.world.outpost_states==unchanged and main.storage.inventory.counts==stock_before,"down actor rejects progress and cargo commit")
 session.actors[first_actor].down=false
 var correct_hp:float=session.outpost_enemies["outpost:front"].hp
 session.outpost_enemies["outpost:front"].hp=9999.0
 check(not session.commit_to_game(main).get("ok",false) and main.world.outpost_states==unchanged and main.storage.inventory.counts==stock_before,"invalid durable candidate is rejected before cargo mutation")
 session.outpost_enemies["outpost:front"].hp=correct_hp
 var first_source:String=session.resources.keys()[0]
 var correct_initial:int=session.resources[first_source].initial
 session.resources[first_source].initial+=1
 check(not session.commit_to_game(main).get("ok",false) and main.world.outpost_states==unchanged and main.storage.inventory.counts==stock_before,"source mismatch rejects progress and cargo commit")
 session.resources[first_source].initial=correct_initial
 var callbacks:={"seen":false,"nested_ok":false}
 main.storage.inventory.changed.connect(func():
  if not callbacks.seen:
   callbacks.seen=true
   callbacks.nested_ok=session.commit_to_game(main).get("ok",false)
 )
 check(session.commit_to_game(main).get("ok",false),"commit actual completed return")
 check(callbacks.seen and not callbacks.nested_ok,"synchronous inventory callback cannot repeat cargo commit")
 var stock:Dictionary=main.storage.inventory.counts.duplicate(true)
 check(session.commit_to_game(main).get("already_committed",false) and main.storage.inventory.counts==stock,"duplicate commit adds no cargo reward")
 var after:=SaveGame.capture(main)
 check(after.world.has("outpost_states") and not after.world.get("outpost_states",{}).is_empty(),"committed outpost lives in normal saved world")
 SaveGame.disabled=false
 check(SaveGame.write(main,PATH,true),"write real manual save containing committed state")
 check(SaveGame.apply(main,before),"restore older preclear snapshot")
 var older:Dictionary=Session.create_from_game(main,"older-save-revisit",{"outpost_enabled":true})
 check(older.get("ok",false) and older.session.outpost_remaining()==3,"loading earlier save discards later committed progress")
 check(SaveGame.apply(main,after),"restore committed snapshot")
 var revisit:Dictionary=Session.create_from_game(main,"committed-revisit",{"outpost_enabled":true})
 check(revisit.get("ok",false) and revisit.session.outpost_cleared and revisit.session.outpost_remaining()==0,"saved snapshot revisit does not respawn defeated guards")
 check(main.storage.inventory.counts==stock,"revisit grants no cargo or invented loot")
 var stable:=SaveGame.capture(main)
 for flaw in ["unknown_site","missing_enemy","extra_enemy","hp_type","hp_range","dead_type","dead_hp","cleared_type","cleared_mismatch","nan","target","home","extra_field","null_ledger"]:
  var bad:Dictionary=after.duplicate(true)
  var enemy:Dictionary=bad.world.outpost_states.c_quarry.enemies["outpost:front"]
  match flaw:
   "unknown_site":bad.world.outpost_states["unknown"]={}
   "missing_enemy":bad.world.outpost_states.c_quarry.enemies.erase("outpost:front")
   "extra_enemy":bad.world.outpost_states.c_quarry.enemies["unknown"]=enemy.duplicate(true)
   "hp_type":enemy.hp="0"
   "hp_range":enemy.hp=enemy.max_hp+1
   "dead_type":enemy.dead=1
   "dead_hp":enemy.dead=false
   "cleared_type":bad.world.outpost_states.c_quarry.cleared=1
   "cleared_mismatch":bad.world.outpost_states.c_quarry.cleared=false
   "nan":enemy.x=NAN
   "target":enemy.target="worker:999"
   "home":enemy.home_x+=1
   "extra_field":enemy["reward"]=100
   "null_ledger":bad.world.outpost_states=null
  check(not SaveGame.validate(bad,main) and not SaveGame.apply(main,bad),"reject malformed durable record "+flaw)
  check(main.world.outpost_states==stable.world.outpost_states and main.storage.inventory.counts==stable.inventory,"invalid load leaves progress and stock unchanged")
 var legacy:Dictionary=before.duplicate(true);legacy.world.erase("outpost_states")
 check(SaveGame.apply(main,legacy) and main.world.outpost_states.is_empty(),"missing old-v3 field migrates to empty without inferred completion")
 var partial_made:Dictionary=Session.create_from_game(main,"partial-retreat",{"outpost_enabled":true})
 check(partial_made.get("ok",false),"old save starts uncommitted outpost normally")
 if partial_made.get("ok",false):
  var partial=partial_made.session
  check(advance(partial,func():return partial.outpost_enemies.values().any(func(e):return e.hp<e.max_hp),80.0),"real combat damages at least one guard")
  var original:Dictionary=main.world.outpost_states.duplicate(true)
  check(not partial.commit_to_game(main).get("ok",false) and main.world.outpost_states==original,"unreturned session cannot record partial combat")
  partial.request_recall()
  check(advance(partial,func():return partial.phase=="ready_to_exit",100.0),"damaged-guard sortie returns all actors")
  check(not partial.outpost_cleared and partial.outpost_remaining()>0,"partial retreat preserves surviving guards")
  check(partial.commit_to_game(main).get("ok",false),"partial return commits existing guard damage")
  check(SaveGame.write(main,"user://outpost-partial.json",true),"write partial-return save for separate process")
  var exact:Dictionary=partial.outpost_enemies.duplicate(true)
  var again:Dictionary=Session.create_from_game(main,"partial-revisit",{"outpost_enabled":true})
  check(again.get("ok",false) and again.session.outpost_enemies==exact,"partial revisit preserves full enemy snapshot")
 await finish()
func finish()->void:
 SaveGame.disabled=true
 main.queue_free();await process_frame
 print("OUTPOST PERSISTENCE failures=",failures)
 quit(0 if failures==0 else 1)
