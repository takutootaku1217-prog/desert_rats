extends SceneTree
const Session = preload("res://bridge/route_connection_session.gd")
var assertions := 0
var failures := 0
func _init() -> void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1;print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func pos(a:Dictionary)->Vector2:return Vector2(a.x,a.y)
func fixture(cart:=false):
 var s=Session.new();s.session_id="expired-recovery";s.mine_path_engineering=true
 for i in 3:
  s.actors["worker:%d"%i]={"worker_index":i,"name":"Crew%d"%i,"role":"harvest","state":"idle","hp":100.0,"down":false,"x":150.0,"y":535.0,"carry_n":0,"carry_item":-1,"resource_id":"","combat_target":"","path":[],"path_index":0,"resume_state":"","work_support":GameData.Item.HANDCART if cart else -1,"entry_work_support":GameData.Item.HANDCART if cart else -1,"life_move_mult":1.0,"wait_reason":"","work_left":0.0}
 s.actors["worker:0"].x=Session.RESOURCE.x;s.actors["worker:0"].y=Session.RESOURCE.y
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 return s
func advance(s,predicate:Callable,limit:=2400)->bool:
 for i in limit:
  if predicate.call():return true
  s.tick(0.025)
 return predicate.call()
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 test_time_and_return()
 test_closed()
 test_cargo()
 test_tampering()
 test_capacity_and_redown()
 test_assigned_expiry()
 test_unwitnessed()
 print("C EXPIRED RECOVERY assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
func test_time_and_return()->void:
 for cart in [false,true]:
  var s=fixture(cart);var a:Dictionary=s.actors["worker:0"];var before:Dictionary=s.to_dict()
  s.tick(999.0,true)
  check(s.to_dict()==before,"explicit pause freezes expiry and incapacitation")
  s.tick(FieldOperations.RESCUE_SECONDS)
  check(a.down and s.rescue_ledger.case_for("worker:0").phase=="incapacitated" and s.rescue_ledger.case_for("worker:0").left==FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS,"90 seconds begins shared provisional incapacitation")
  s.tick(FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS-0.25)
  check(a.down and a.hp==0.0,"no revival before full existing provisional delay")
  var here:=pos(a);s.tick(0.25)
  check(not a.down and a.hp==CrewStatusDB.HP_REVIVE_AT,"due is consumed into existing wake threshold")
  check(pos(a)==here,"wake does not teleport or spend pre-wake frame on movement")
  check(s.rescue_ledger.case_for("worker:0").is_empty(),"expiry timer consumed exactly once")
  if a.down:continue
  check(not Session.from_dict(s.to_dict()).get("ok",false),"active self-return does not enable unsupported snapshot restoration")
  var bounded:=true
  for i in 2400:
   if a.state=="injured_wait":break
   var p:=pos(a);s.tick(0.025);bounded=bounded and p.distance_to(pos(a))<=Session.MOVE_SPEED*0.025+0.001
  check(bounded and pos(a)==Session.BASE and a.state=="injured_wait","physical bounded self-return reaches exact entrance")
  s.tick(20.0)
  check(a.hp==CrewStatusDB.HP_REVIVE_AT and a.state=="injured_wait" and s.rescue_ledger.case_for("worker:0").is_empty(),"extra ticks neither heal further nor restart timer/work")
  check(s.rescue_approach._treatment.is_empty(),"post-expiry recovery is not manual rescue treatment")
func test_closed()->void:
 var s=fixture();var a:Dictionary=s.actors["worker:0"];s.set_all_routes_closed(true)
 s.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 check(not a.down and a.hp==CrewStatusDB.HP_REVIVE_AT,"closed route does not prolong biological recovery")
 var p:=pos(a);s.request_recall();s.tick(1.0)
 check(pos(a)==p and s.phase!="ready_to_exit" and not s._local_exit_ready(),"closed self-return cannot teleport or commit away from entrance")
 if a.down:return
 s.set_all_routes_closed(false)
 check(advance(s,func():return a.state=="injured_wait") and pos(a)==Session.BASE,"reopening resumes existing physical return")
func test_cargo()->void:
 var s=fixture();var a:Dictionary=s.actors["worker:0"]
 a.carry_n=2;a.carry_item=GameData.Item.STONE
 s.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 check(not a.down and a.carry_n==2 and s.depot_stock.is_empty(),"wake preserves carried cargo until physical delivery")
 if a.down:return
 s.request_recall()
 check(advance(s,func():return s.phase=="ready_to_exit"),"loaded recovered actor reaches safe recall completion")
 check(pos(a)==Session.BASE and a.state=="injured_wait" and a.carry_n==0 and a.carry_item==-1 and s.depot_stock.get(GameData.Item.STONE,0)==2,"existing dock deposits cargo once then retains injured wait")
 var stock:Dictionary=s.depot_stock.duplicate(true);s.tick(100.0)
 check(s.depot_stock==stock,"completed recall never repeats recovered cargo")

func test_tampering()->void:
 for mode in ["path","position","gear","identity","dock_position","dock_gear"]:
  var s=fixture();var a:Dictionary=s.actors["worker:0"]
  a.carry_n=2;a.carry_item=GameData.Item.STONE
  s.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
  if a.down:check(false,"tamper fixture wakes");continue
  if mode.begins_with("dock"):
   check(advance(s,func():return a.state=="dock_wait"),"reach real dock before "+mode)
  var stock:Dictionary=s.depot_stock.duplicate(true)
  if mode=="path":a.path_index=a.path.size()
  elif mode in ["position","dock_position"]:a.x+=123.0
  elif mode in ["gear","dock_gear"]:a.work_support=GameData.Item.HANDCART
  else:s.actors["worker:0"]=a.duplicate(true)
  var here:=pos(s.actors["worker:0"])
  s.request_recall();s.tick(10.0)
  check(s.depot_stock==stock and pos(s.actors["worker:0"])==here and not s._local_exit_ready(),"tampering rejects movement/deposit/commit: "+mode)

func test_capacity_and_redown()->void:
 var s=fixture();var a:Dictionary=s.actors["worker:0"]
 s.vertical_slice=true;s.field_capacity_limit_weight=0
 s.resources["ore"]={"item":GameData.Item.STONE,"initial":2,"remaining":0,"reservation":""}
 a.carry_n=2;a.carry_item=GameData.Item.STONE
 s.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 s.request_recall()
 check(advance(s,func():return a.state=="capacity_wait"),"full depot leaves real cargo at entrance")
 check(a.carry_n==2 and s.depot_stock.is_empty() and not s._local_exit_ready() and s.conservation_ok(),"capacity wait blocks exit and conserves cargo")
 s.field_capacity_limit_weight=CargoDB.size_of(GameData.Item.STONE)
 s.tick(1.0);s.tick(1.0)
 check(a.carry_n==1 and s.depot_stock.get(GameData.Item.STONE,0)==1 and not s._local_exit_ready() and s.conservation_ok(),"partial capacity deposits only one real unit")
 s.field_capacity_limit_weight=100
 check(advance(s,func():return s.phase=="ready_to_exit") and a.carry_n==0 and s.depot_stock.get(GameData.Item.STONE,0)==2 and s.conservation_ok(),"capacity release completes physical dock once")
 var r=fixture();var b:Dictionary=r.actors["worker:0"]
 r.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 r.tick(0.025);var here:=pos(b)
 r._begin_outpost_down("worker:0",b)
 check(not r.expired_recovery.owns("worker:0") and b.down and b.hp==0 and pos(b)==here and r.rescue_ledger.case_for("worker:0").phase=="waiting","new genuine down releases expiry ownership and starts ordinary rescue")

func test_assigned_expiry()->void:
 var s=fixture();var a:Dictionary=s.actors["worker:0"]
 check(s.request_rescue("worker:0","worker:1",s.session_id).get("ok",false),"assign carrier before expiry")
 s.tick(FieldOperations.RESCUE_SECONDS)
 check(not s.rescue_approach.owns("worker:1") and a.down and s.rescue_ledger.case_for("worker:0").phase=="incapacitated","expiry releases approaching carrier without pickup")
 s.tick(FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 check(not a.down and s.expired_recovery.owns("worker:0"),"released assignment does not prevent due consumption")

func test_unwitnessed()->void:
 var s=fixture();var a:Dictionary=s.actors["worker:0"]
 a.x=410.123;a.y=410.123
 s.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 var here:=pos(a);s.request_recall();s.tick(10.0)
 check(not a.down and pos(a)==here and a.state=="safe_wait" and not s._local_exit_ready(),"unwitnessed off-route location cannot forge straight-line return or exit")
