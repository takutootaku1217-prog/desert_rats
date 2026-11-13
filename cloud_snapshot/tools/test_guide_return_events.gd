extends SceneTree
const Session=preload("res://bridge/route_connection_session.gd")
var main
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func done(event:String)->bool:return main.navigation.guide_snapshot().get("history",{}).get("completed",{}).get(event,false)
func advance(session,predicate:Callable,seconds:float)->bool:
 for tick in ceili(seconds/0.2):
  session.tick(0.2)
  if not session.apply_projection_to_workers(main).get("ok",false):return false
  if predicate.call():return true
 return predicate.call()
func arrive(destination:String)->bool:
 for tick in range(1800):
  main._process(0.25);await process_frame
  if main.world.region==destination and main.world.phase=="stopped":return true
 return false
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 check(not done("returned_a"),"initial A location is not return history")
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination) and await arrive(destination),"real trip reaches "+destination)
 var earlier:=SaveGame.capture(main)
 var empty_made:Dictionary=Session.create_from_game(main,"empty-guide-return")
 check(empty_made.get("ok",false),"create empty-return session")
 if not empty_made.get("ok",false):await finish();return
 var empty=empty_made.session
 empty.request_recall()
 check(advance(empty,func():return empty.phase=="ready_to_exit",100.0),"empty sortie recalls")
 check(empty.commit_to_game(main).get("ok",false) and not done("quarry_returned"),"empty return grants no cargo milestone")
 var made:Dictionary=Session.create_from_game(main,"positive-guide-return")
 check(made.get("ok",false),"create positive cargo session")
 if not made.get("ok",false):await finish();return
 var session=made.session
 check(advance(session,func():return int(session.state_summary().depot)>0,150.0),"real finite quarry cargo reaches depot")
 check(not done("quarry_returned"),"local cargo not yet committed is not history")
 session.request_recall();check(advance(session,func():return session.phase=="ready_to_exit",100.0),"all cargo and actors return")
 var first_source:String=session.resources.keys()[0]
 session.resources[first_source].initial+=1
 check(not session.commit_to_game(main).get("ok",false) and not done("quarry_returned"),"failed return records nothing")
 session.resources[first_source].initial-=1
 check(session.commit_to_game(main).get("ok",false) and done("quarry_returned"),"successful positive cargo return records event")
 var recorded:Dictionary=main.navigation.guide_snapshot().get("history",{}).duplicate(true)
 check(session.commit_to_game(main).get("already_committed",false) and main.navigation.guide_snapshot().get("history",{})==recorded,"duplicate commit has no additional progress effect")
 main.journey.confirm_each=false
 check(main.journey.plan(["b_forest","a_start","d_yard"],[]),"plan automatic pass through A")
 check(await arrive("d_yard"),"real multi-leg journey reaches D")
 check(not done("returned_a"),"passing A without stopping is not safe-town return history")
 check(main.world.request("a_start") and await arrive("a_start"),"real route stops at A")
 check(done("returned_a"),"stopped A after cargo commit records return")
 var after:=SaveGame.capture(main)
 check(SaveGame.apply(main,earlier) and not done("quarry_returned") and not done("returned_a"),"earlier snapshot restores earlier history without residue")
 check(SaveGame.apply(main,after),"restore completed-return history")
 SaveGame.disabled=false
 check(SaveGame.write(main,"user://guide-return-events.json",true),"write real completed-return save")
 await finish()
func finish()->void:
 SaveGame.disabled=true;main.queue_free();await process_frame
 print("GUIDE RETURN EVENTS failures=",failures);quit(0 if failures==0 else 1)
