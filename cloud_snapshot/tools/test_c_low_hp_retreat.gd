extends SceneTree
## Explicit boundary fixtures. No test below claims natural ordinary-input down.
const Session = preload("res://bridge/route_connection_session.gd")
var assertions := 0
var failures := 0
var main
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func pos(a: Dictionary) -> Vector2: return Vector2(a.x,a.y)
func fixture():
 var s = Session.new()
 s.session_id = "low-hp"
 for i in 3:
  s.actors["worker:%d" % i] = {"worker_index":i,"name":"Crew%d"%i,"role":["harvest","carry","escort"][i],"state":"idle","hp":100.0,"down":false,"x":150.0,"y":535.0,"carry_n":0,"carry_item":-1,"resource_id":"","combat_target":"","path":[],"path_index":0,"resume_state":"","work_support":-1,"life_move_mult":1.0,"wait_reason":"","work_left":0.0,"stress":0.0}
 s.outpost_enabled = true;s.outpost_cleared = false
 s._setup_outpost()
 return s
func nearby(s, id := "worker:2") -> Dictionary:
 var a: Dictionary = s.actors[id]
 a.x = 850.0;a.y = 326.0
 return {"x":842.0,"y":326.0,"home_x":842.0,"home_y":326.0}
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2);return
 test_exposure()
 test_damage_and_retreat()
 test_carrier_drop()
 test_mine_return_owner()
 await test_boss_and_entry()
 print("C LOW HP RETREAT assertions=",assertions," failures=",failures)
 quit(0 if failures == 0 else 1)
func test_exposure() -> void:
 var s = fixture();var e := nearby(s);var a: Dictionary = s.actors["worker:2"]
 for state in ["combat","outpost_move","injured_return","to_base_empty","rescue_move","rescue_hold","rescue_return"]:
  a.state=state
  for hp in [30.0,1.0]:
   a.hp=hp
   check(s._outpost_actor_can_be_targeted("worker:2",e),"living outdoor %s HP%s is exposed"%[state,hp])
 a.state="safe_wait";a.resume_state="injured_return"
 check(s._outpost_actor_can_be_targeted("worker:2",e),"closed retreat is not an immunity switch")
 for state in ["idle","injured_wait","rescue_treatment","harvesting","maintenance_work","dock_wait"]:
  a.state=state;a.hp=100.0
  check(not s._outpost_actor_can_be_targeted("worker:2",e),"safe or unrelated owner excluded: "+state)
  var hp:float=a.hp;s._apply_outpost_hit("worker:2","fixture")
  check(a.hp==hp,"direct hit also respects owner: "+state)
 a.state="combat";a.down=true
 check(not s._outpost_actor_can_be_targeted("worker:2",e),"down body never targets even with stale positive HP")
 a.down=false;a.hp=0.0
 check(not s._outpost_actor_can_be_targeted("worker:2",e),"zero HP cannot target before down synchronization")
 a.hp=100.0;a.state="injured_return";a.x=150.0;a.y=535.0
 e={"x":150.0,"y":535.0,"home_x":150.0,"home_y":535.0}
 check(not s._outpost_actor_can_be_targeted("worker:2",e),"arrival at parking is safe before state catches up")
 e=nearby(s);a.state="combat";a.x=1183.0;e.x=1180.0
 check(not s._outpost_actor_can_be_targeted("worker:2",e),"nearby actor beyond home territory is not chased")
 a.x=1182.0
 check(s._outpost_actor_can_be_targeted("worker:2",e),"existing340 territory boundary remains targetable")
 a.x=1050.0;e.x=849.0
 check(not s._outpost_actor_can_be_targeted("worker:2",e),"beyond existing200 sight is excluded")
 e=nearby(s);a.state="injured_return"
 s.expired_recovery._records["worker:2"]={}
 check(not s._outpost_actor_can_be_targeted("worker:2",e),"provisional expiry owner is not pulled into repeated down")
 s.expired_recovery._records.clear();s.rescue_approach._treatment["worker:2"]=60.0
 check(not s._outpost_actor_can_be_targeted("worker:2",e),"treatment ownership wins over stale movement state")
 s.rescue_approach._treatment.clear()
 var h:Dictionary=s.actors["worker:0"];h.state="to_base_empty";h.x=850.0;h.y=326.0
 check(not s._outpost_actor_can_be_targeted("worker:0",e),"unrelated harvesting return is not newly attacked")
 # Explicit refused-owner boundary, independent of other moving crew.
 h.state="idle";a.state="safe_wait";a.resume_state=""
 s.rescue_approach._mine_returns["worker:2"]="injured_return"
 check(not s._local_exit_ready(),"unresolved outdoor mine-return owner always blocks exit")
func test_damage_and_retreat() -> void:
 var s=fixture();nearby(s);var a:Dictionary=s.actors["worker:2"]
 a.state="combat";a.hp=31.0
 s._apply_outpost_hit("worker:2","outpost:front")
 check(a.hp==29.5 and a.state=="injured_return" and s.outpost_retreats==1,"existing damage crosses threshold and orders one retreat")
 s._update_actor("worker:2",0.1)
 var path:Array=a.path.duplicate(true);var index:int=a.path_index;var requests:int=s.path_requests
 s._apply_outpost_hit("worker:2","outpost:front")
 check(a.hp==28.0,"retreat still receives existing damage below30")
 check(a.path==path and a.path_index==index and s.path_requests==requests and s.outpost_retreats==1,"further hit never restarts path or recounts retreat")
 s.set_all_routes_closed(true)
 check(a.state=="safe_wait" and a.resume_state=="injured_return","closed return preserves intended state")
 s._apply_outpost_hit("worker:2","outpost:front")
 check(a.hp==26.5 and a.state=="safe_wait" and a.resume_state=="injured_return","blocked retreat is vulnerable without reopening route")
 check(not s._local_exit_ready(),"closed outdoor retreat cannot become safe exit")
 a.hp=1.5;s._apply_outpost_hit("worker:2","outpost:front")
 check(a.down and a.hp==0.0 and s.rescue_ledger.case_for("worker:2").get("left")==90.0,"lethal existing hit creates one90-second rescue case")
 var ledger:Dictionary=s.rescue_ledger.to_dict();s._apply_outpost_hit("worker:2","outpost:front")
 check(s.rescue_ledger.to_dict()==ledger,"further hit cannot restart down deadline")
func test_carrier_drop() -> void:
 for carrier in ["worker:0","worker:1","worker:2"]:
  var target := "worker:1" if carrier=="worker:0" else "worker:0"
  var s=fixture();s.outpost_enabled=false
  nearby(s,target);nearby(s,carrier)
  s._begin_outpost_down(target,s.actors[target])
  check(s.request_rescue(target,carrier,s.session_id).ok,"manual carrier allowed: "+carrier)
  s.tick(0.05)
  check(s.rescue_ledger.case_for(target).phase=="carried","physical same-position fixture picks up: "+carrier)
  var left:float=s.rescue_ledger.case_for(target).left;var drop:=pos(s.actors[target])
  s.actors[carrier].hp=31.0
  s._apply_outpost_hit(carrier,"outpost:front");s.rescue_approach.sync(s)
  check(s.rescue_ledger.case_for(target).phase=="waiting" and s.rescue_ledger.case_for(target).left==left,"injured carrier drops without consuming frozen time: "+carrier)
  check(pos(s.actors[target])==drop and s.actors[target].down and not s.rescue_approach.owns(carrier),"body stays at drop and carrier owner clears: "+carrier)
  s.tick(0.25)
  check(is_equal_approx(s.rescue_ledger.case_for(target).left,left-0.25),"dropped deadline resumes once: "+carrier)
  var hp:float=s.actors[carrier].hp
  s._apply_outpost_hit(carrier,"outpost:front")
  check(s.actors[carrier].hp==hp-1.5,"released injured rescuer remains vulnerable: "+carrier)
  s.request_recall();s.request_recall()
  check(s.actors[carrier].state=="injured_return","repeated recall keeps injured return intent: "+carrier)
  hp=s.actors[carrier].hp;s._apply_outpost_hit(carrier,"outpost:front")
  check(s.actors[carrier].hp==hp-1.5,"recall cannot restore injured rescuer immunity: "+carrier)
  s.set_all_routes_closed(true);s.request_recall()
  check(s.actors[carrier].state=="safe_wait" and s.actors[carrier].resume_state=="injured_return","blocked recall preserves injury intent: "+carrier)
  s.set_all_routes_closed(false);s.tick(0.01)
  check(s.actors[carrier].state=="injured_return","reopen during recall retains vulnerable injury return: "+carrier)
func test_mine_return_owner() -> void:
 for cart in [false,true]:
  var s=fixture();s.outpost_enabled=false;s.mine_path_engineering=true
  for id in ["worker:0","worker:1"]:
   s.actors[id].x=700.0;s.actors[id].y=325.0
   s.actors[id].work_support=GameData.Item.HANDCART if cart else -1
   s.actors[id].entry_work_support=s.actors[id].work_support
   s.mine_rescue_traces.anchor_actor(s,id)
  s._begin_outpost_down("worker:0",s.actors["worker:0"])
  check(s.request_rescue("worker:0","worker:1",s.session_id).ok,"mine canonical rescue accepted cart="+str(cart))
  s.tick(0.05)
  check(s.cancel_rescue("worker:0",s.session_id).ok and s.rescue_approach.has_mine_return("worker:1"),"cancel retains physical mine return owner")
  var a:Dictionary=s.actors["worker:1"];a.hp=31.0
  check(s._outpost_actor_can_be_targeted("worker:1",{"x":700.0,"y":325.0}),"healthy rescue-origin nonescort return stays exposed")
  s._apply_outpost_hit("worker:1","fixture")
  check(a.hp==29.5 and a.state=="injured_return" and s.rescue_approach.has_mine_return("worker:1"),"threshold preserves mine owner rather than generic return")
  check(s.mine_rescue_traces.plan_current("worker:1",a),"threshold retains authenticated mine route")
  s.tick(0.1)
  var path:Array=a.path.duplicate(true);var index:int=a.path_index
  s._apply_outpost_hit("worker:1","fixture")
  check(a.hp==28.0 and a.path==path and a.path_index==index and s.mine_rescue_traces.plan_current("worker:1",a),"second hit preserves same mine route and trace")
  for unused in 400:
   if a.state=="injured_wait":break
   s.tick(0.05)
  check(a.state=="injured_wait" and pos(a)==Session.BASE and not s.rescue_approach.owns("worker:1"),"injured mine return reaches exact entrance cart="+str(cart))
func advance(clock,predicate:Callable,seconds:float)->bool:
 for unused in ceili(seconds/0.05):
  if predicate.call():return true
  clock.tick(0.05)
 return predicate.call()
func test_boss_and_entry() -> void:
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"real route "+destination)
  for unused in 300:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
 for options in [{"outpost_enabled":true},{"encounter_id":FirstRegionCompletion.ENCOUNTER_ID}]:
  for hp in [30.0,15.0]:
   main.workers[2].hp=hp
   check(not Session.create_from_game(main,"low-reentry",options).ok,"low-HP challenge reentry rejected: %s HP%s"%[options,hp])
 main.workers[2].hp=33.0
 var gate=main.mine_arrival_gate;gate._process(0.0);SaveGame.disabled=false
 check(gate.enter_boss(),"healthy-above-threshold fixture starts boss")
 if gate.field!=null:
  var field=gate.field;field.process_mode=Node.PROCESS_MODE_DISABLED;var s=field.session
  check(advance(field.life_clock,func():return s.outpost_retreats>0,60.0),"real enemy crosses threshold")
  check("救助を中断" not in s.actors["worker:2"].wait_reason,"battle withdrawal does not falsely report rescue interruption")
  # Threshold crossing releases the combat claim; the next enemy tick reacquires.
  field.life_clock.tick(0.05)
  var e:Dictionary=s.outpost_enemies[FirstRegionCompletion.BOSS_ID]
  check(e.target=="worker:2" and s._outpost_actor_can_be_targeted("worker:2",e),"enemy keeps low-HP physical retreat target")
  var saved:=SaveGame.capture(main)
  check(SaveGame.validate(saved,main),"complete save accepts retreat target, without permitting low-HP attacker")
  check(SaveGame.apply(main,saved),"complete retreat-target roundtrip")
  field=gate.field;field.process_mode=Node.PROCESS_MODE_DISABLED;s=field.session
  check(s.actors["worker:2"].state=="injured_return" and not s.actors["worker:2"].down,"roundtrip retains physical live return")
  paused=false
  s.request_recall()
  check(advance(field.life_clock,func():return s.phase=="ready_to_exit",80.0),"early injured return can still escape")
 main.queue_free();await process_frame;SaveGame.disabled=true
