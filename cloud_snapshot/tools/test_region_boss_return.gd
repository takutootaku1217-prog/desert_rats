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
  check(main.world.request(destination),"request ordinary trip "+destination)
  for unused in 300:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
  check(main.world.region==destination,"arrive "+destination)
 var gate=main.mine_arrival_gate
 check(gate.has_method("enter_boss"),"C offers separate boss challenge without renaming the outpost")
 if not gate.has_method("enter_boss"):await finish();return
 gate._process(0.0)
 # Low starting HP is an explicit test fixture; boss damage/retreat are real ticks.
 main.workers[2].hp=33.0
 var before:=SaveGame.capture(main)
 SaveGame.disabled=false
 check(gate.call("enter_boss"),"player-facing boss entry starts")
 if gate.field==null:await finish();return
 var adapter=gate.field;adapter.process_mode=Node.PROCESS_MODE_DISABLED
 var s=adapter.session
 check(s.encounter_id==FirstRegionCompletion.ENCOUNTER_ID and s.outpost_enemy_total()==1,"one independent boss, not old three guards")
 check(s.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp==72.0,"provisional HP72 is used")
 check(main.world.outpost_states.is_empty() and not main.world.region_goal_snapshot().boss_returned,"entry publishes no victory")
 check(advance(adapter.life_clock,func():return s.outpost_retreats>0,60.0),"real boss hits trigger low-HP retreat")
 check(not s.outpost_cleared,"injured sortie does not defeat the boss")
 var partial_hp:float=s.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp
 check(partial_hp>0.0 and partial_hp<72.0,"real combat leaves a damaged surviving boss")
 check(not s.commit_to_game(main).ok,"unreturned battle cannot commit")
 s.request_recall()
 check(advance(adapter.life_clock,func():return s.phase=="ready_to_exit",80.0),"injured crew physically returns before commit")
 var result:Dictionary=s.commit_to_game(main)
 check(result.ok,"safe retreat records partial encounter")
 check(not main.world.region_goal_snapshot().boss_returned and main.world.outpost_states.is_empty(),"partial record stays independent and unfinished")
 gate._on_field_exit(result);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 # Recovery setup only: healthy retry uses the same real gate and enemy damage.
 for w in main.workers:
  w.hp=100.0;w.ai.low_hp_retreat=false;w.stop_work();w.floor_i=1
 gate._dismissed_here=false;gate._process(0.0)
 check(gate.call("enter_boss"),"return enables a separate retry")
 if gate.field==null:await finish();return
 adapter=gate.field;adapter.process_mode=Node.PROCESS_MODE_DISABLED;s=adapter.session
 check(s.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp==partial_hp,"retry preserves return-committed enemy damage")
 check(advance(adapter.life_clock,func():return s.outpost_cleared,80.0),"existing equipment/combat defeats independent boss")
 check(not main.world.region_goal_snapshot().boss_returned,"defeat alone is not permanent before return")
 check(not main.region_clear_ui.is_open(),"unreturned defeat cannot acknowledge region clear")
 var stale:Dictionary=s.to_dict()
 s.request_recall()
 check(advance(adapter.life_clock,func():return s.phase=="ready_to_exit",80.0),"all workers/cargo return after victory")
 var bad_source:String=s.resources.keys()[0]
 s.resources[bad_source].initial+=1
 var durable_before:Dictionary=main.world.region_completion.duplicate(true)
 check(not s.commit_to_game(main).ok and main.world.region_completion==durable_before,"failed return cannot publish boss victory")
 s.resources[bad_source].initial-=1
 result=s.commit_to_game(main)
 check(result.ok and main.world.region_goal_snapshot().boss_returned,"successful return publishes boss victory once")
 check(not main.world.region_goal_snapshot().completed,"boss-only is not region completion")
 var stock:Dictionary=main.storage.inventory.counts.duplicate(true)
 check(s.commit_to_game(main).already_committed and main.storage.inventory.counts==stock,"duplicate commit grants no additional cargo/rewards")
 gate._on_field_exit(result);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 for w in main.workers:w.stop_work();w.floor_i=1
 check(main.world.request("b_forest"),"travel to B to reconnect route")
 for unused in 300:
  main._process(0.25);await process_frame
  if main.world.region=="b_forest" and main.world.phase=="stopped":break
 # Cost fixture only. Real clear_shortcut applies its existing transaction.
 for item in WorldTrip.REGION_A_CLEAR_COST:main.storage.store_owned(item,WorldTrip.REGION_A_CLEAR_COST[item],Inventory.SOURCE_TRANSFER)
 var observed:={"seen":false,"valid":false}
 var observer:=func():
  observed.seen=true
  observed.valid=SaveGame.validate(SaveGame.capture(main),main)
 main.storage.inventory.changed.connect(observer)
 check(main.world.clear_shortcut(),"existing paid B–D road action succeeds")
 main.storage.inventory.changed.disconnect(observer)
 check(observed.seen and observed.valid,"synchronous road-payment observers see a coherent completed save")
 var goal:Dictionary=main.world.region_goal_snapshot()
 check(goal.completed and goal.route_connected and goal.boss_returned,"boss-first then route reaches first-region endpoint")
 check(not main.region_clear_ui.is_open(),"road transaction does not open reentrant modal")
 main.map_ui.open();await process_frame
 check(not main.region_clear_ui.is_open(),"road map retains priority after boss-first completion")
 main.map_ui.close()
 for unused in 3:await process_frame
 check(main.region_clear_ui.is_open() and paused,"boss-first completion acknowledges on safe frame")
 main.region_clear_ui.acknowledge()
 for unused in 3:await process_frame
 check(not main.world.region_state.roads.ab.graded and main.world.region_state.lots.b_forest=="wild" and main.world.region_state.lots.d_yard=="wild","no full paving/construction required")
 var complete:=SaveGame.capture(main)
 check(SaveGame.validate(complete,main),"completed ordinary save validates")
 check(SaveGame.apply(main,complete) and main.world.region_goal_snapshot().completed,"completed state survives complete reload")
 check(SaveGame.apply(main,before),"earlier save still explicitly reverts later victory")
 check(not main.world.region_goal_snapshot().boss_returned,"old save never infers later victory")
 await finish()
func finish()->void:
 SaveGame.disabled=true
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("REGION BOSS RETURN assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
