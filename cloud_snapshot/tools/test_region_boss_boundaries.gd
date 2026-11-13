extends SceneTree
const Session=preload("res://bridge/route_connection_session.gd")
var main
var assertions:=0
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func advance(clock,predicate:Callable,seconds:float)->bool:
 for unused in ceili(seconds/0.05):
  if predicate.call():return true
  clock.tick(0.05)
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
  check(main.world.request(destination),"ordinary route "+destination)
  for unused in 300:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
 var gate=main.mine_arrival_gate;gate._process(0.0)
 for hp in [30.0,15.0]:
  main.workers[2].hp=hp
  var result:Dictionary=Session.create_from_game(main,"wounded-entry",{"encounter_id":FirstRegionCompletion.ENCOUNTER_ID})
  check(not result.ok,"wounded escort HP%s cannot start an invulnerable challenge"%hp)
 main.workers[2].hp=100.0
 SaveGame.disabled=false
 check(gate.enter_boss(),"healthy escort still starts through real gate")
 if gate.field==null:await finish();return
 var a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED
 var s=a.session
 check(advance(a.life_clock,func():return s.actors["worker:2"].state=="combat",60.0),"real boss combat owns escort")
 var combat:=SaveGame.capture(main)
 for hp in [30.0,15.0]:
  var bad:=combat.duplicate(true)
  bad.crew[2].worker.hp=hp
  bad.field_snapshot.session.actors["worker:2"].hp=hp
  bad.field_snapshot.session.outpost_enemies[FirstRegionCompletion.BOSS_ID].target=""
  check(not SaveGame.validate(bad,main),"complete save rejects low-HP attacker ownership: "+str(hp))
 a._update_controls()
 check(a.maintenance_button.disabled,"combat UI cannot assign the same escort to rubble")
 var before:Dictionary=s.to_dict()
 var maintenance:Dictionary=s.request_intermediate_clearance()
 check(not maintenance.ok and s.to_dict()==before,"combat-time maintenance refuses without stealing claims")
 check(SaveGame.validate(SaveGame.capture(main),main),"refused competing work leaves complete saving available")
 if maintenance.ok:
  check(SaveGame.apply(main,combat),"RED fixture restores coherent combat after unexpected acceptance")
  a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED;s=a.session;a._toggle_field_pause()
 check(advance(a.life_clock,func():return s.outpost_cleared,60.0),"normal combat still wins after refused work")
 s.request_recall()
 check(advance(a.life_clock,func():return s.phase=="ready_to_exit",80.0),"victory returns normally")
 a._commit_and_exit();await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 for w in main.workers:w.stop_work();w.floor_i=1
 var completed:=SaveGame.capture(main)
 check(main.world.region_goal_snapshot().boss_returned,"boss victory is committed")
 var revisit:Dictionary=Session.create_from_game(main,"already-won",{"encounter_id":FirstRegionCompletion.ENCOUNTER_ID})
 check(not revisit.ok,"completed encounter has no new unfinished entrance")
 gate._dismissed_here=false;gate._process(0.0)
 check(gate._boss_button.disabled and gate._boss_button.text.contains("帰還確定済み"),"arrival choice reports completed boss explicitly")
 check(not gate.enter_boss() and gate.field==null,"programmatic duplicate entrance is also refused")
 if gate.field!=null:
  SaveGame.apply(main,completed)
  main.process_mode=Node.PROCESS_MODE_DISABLED
 gate._dismissed_here=false;gate._process(0.0)
 check(gate.enter_mine(),"ordinary mining remains available after boss victory")
 if gate.field!=null:
  gate.field.process_mode=Node.PROCESS_MODE_DISABLED
  check(SaveGame.validate(SaveGame.capture(main),main),"completed-world ordinary entry is saveable before first tick")
 await finish()
func finish()->void:
 SaveGame.disabled=true
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("REGION BOSS BOUNDARIES assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
