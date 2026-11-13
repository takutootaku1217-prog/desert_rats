extends SceneTree
const Session = preload("res://bridge/route_connection_session.gd")
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func pos(a: Dictionary) -> Vector2: return Vector2(a.x,a.y)
func place(a: Dictionary,p: Vector2) -> void: a.x=p.x; a.y=p.y
func fixture(cart := false,cleared := false):
 var s = Session.new()
 s.session_id="mine-rescue"
 s.mine_path_engineering=true
 s.intermediate_access="cleared" if cleared else "blocked"
 for i in 3:
  s.actors["worker:%d" % i]={"worker_index":i,"name":"Crew%d" % i,"role":"harvest","state":"idle","hp":100.0,"down":false,"x":150.0,"y":535.0,"carry_n":0,"carry_item":-1,"resource_id":"","combat_target":"","path":[],"path_index":0,"resume_state":"","work_support":GameData.Item.HANDCART if cart else -1,"entry_work_support":GameData.Item.HANDCART if cart else -1,"life_move_mult":1.0,"wait_reason":"","work_left":0.0}
 place(s.actors["worker:0"],Session.RESOURCE)
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 return s
func edges(cart: bool, cleared: bool) -> Array:
 var es: Array=[[Session.GATE,Session.RESOURCE]]
 if cart:
  es.append_array([[Session.BASE,Session.MINE_PATH_CART_DETOUR_ENTRY],[Session.MINE_PATH_CART_DETOUR_ENTRY,Session.MINE_PATH_CART_DETOUR],[Session.MINE_PATH_CART_DETOUR,Session.RELAY],[Session.RELAY,Session.MINE_PATH_CART_DETOUR_ENTRY],[Session.MINE_PATH_CART_DETOUR,Session.GATE]])
  if cleared: es.append_array([[Session.BASE,Session.MINE_PATH_CART_SHORTCUT],[Session.MINE_PATH_CART_SHORTCUT,Session.RELAY],[Session.MINE_PATH_CART_SHORTCUT,Session.GATE]])
 else: es.append_array([[Session.BASE,Session.MINE_PATH_STEP],[Session.MINE_PATH_STEP,Session.RELAY],[Session.MINE_PATH_STEP,Session.GATE]])
 return es
func on_edge(p: Vector2,a: Vector2,b: Vector2) -> bool:
 return p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))<=0.111
func segment_ok(a: Vector2,b: Vector2,es: Array) -> bool:
 if a==b: return true
 for e in es:
  if on_edge(a,e[0],e[1]) and on_edge(b,e[0],e[1]): return true
 return false
func walk(s, stop_state: String, paired := false, cart := false, cleared := false) -> bool:
 var legal := true
 var bounded := true
 var equal := true
 for i in 1600:
  var a: Dictionary=s.actors["worker:2"]
  if a.state==stop_state: break
  var before := pos(a)
  s.tick(0.025)
  legal=legal and segment_ok(before,pos(a),edges(cart,cleared))
  bounded=bounded and before.distance_to(pos(a))<=5.751
  if paired: equal=equal and pos(a)==pos(s.actors["worker:0"])
 check(legal,"each movement segment stays on allowed corridor")
 check(bounded,"movement keeps existing speed bound")
 if paired: check(equal,"target shares every carried position")
 return s.actors["worker:2"].state==stop_state
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2); return
 test_routes()
 test_reject()
 test_interrupt()
 test_clearance()
 print("C RESCUE MINE ROUTES assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
func test_routes() -> void:
 for config in [[false,false],[true,false],[true,true]]:
  var cart: bool=config[0]
  var cleared: bool=config[1]
  var s=fixture(cart,cleared)
  var before: Dictionary=s.to_dict()
  var accepted: bool=s.request_rescue("worker:0","worker:2",s.session_id).ok
  check(accepted,"default mine accepts reachable manual rescue gear=%s cleared=%s" % [cart,cleared])
  if not accepted: continue
  check(pos(s.actors["worker:2"])==Session.BASE,"assignment never teleports")
  check(walk(s,"rescue_hold",false,cart,cleared),"real corridor approach reaches exact hold")
  check(pos(s.actors["worker:2"])==Session.RESOURCE,"pickup exact resource position")
  var left: float=s.rescue_ledger.case_for("worker:0").left
  check(s.request_rescue_return("worker:0",s.session_id).ok,"explicit mine return accepted")
  check(walk(s,"idle",true,cart,cleared),"corridor return completes")
  check(pos(s.actors["worker:0"])==Session.BASE and s.actors["worker:0"].state=="rescue_treatment" and s.actors["worker:0"].hp==CrewStatusDB.HP_REVIVE_AT,"exact entrance first aid uses existing value")
  check(s.rescue_approach._treatment["worker:0"]==left,"carried timer retained for handoff")
  check(not Session.from_dict(s.to_dict()).get("ok",false),"live treatment does not enable snapshot restore")
  check(before.actors.size()==s.actors.size(),"no actor creation/deletion")
  # Same-edge and reverse midpoints on every legal canonical edge.
  for e in edges(cart,cleared):
   for reverse in [false,true]:
    var mid=fixture(cart,cleared)
    var p: Vector2=e[0].lerp(e[1],0.3 if reverse else 0.7)
    var q: Vector2=e[0].lerp(e[1],0.7 if reverse else 0.3)
    place(mid.actors["worker:2"],p);place(mid.actors["worker:0"],q)
    check(mid.request_rescue("worker:0","worker:2",mid.session_id).ok,"mid-segment approach in both directions")
    check(walk(mid,"rescue_hold",false,cart,cleared),"midpoint pickup is physically reachable")
    check(pos(mid.actors["worker:2"])==q,"midpoint pickup never snaps")
func test_reject() -> void:
 for config in [[true,Session.MINE_PATH_STEP],[true,Session.MINE_PATH_CART_SHORTCUT],[false,Session.MINE_PATH_CART_DETOUR],[false,Vector2(613,271)]]:
  var s=fixture(config[0])
  place(s.actors["worker:0"],config[1])
  var before: Dictionary=s.to_dict()
  check(not s.request_rescue("worker:0","worker:2",s.session_id).ok and s.to_dict()==before,"unreachable or equipment-incompatible rescue rejects without mutation")
func test_interrupt() -> void:
 for cart in [false,true]:
  for mode in ["cancel_move","cancel_hold","cancel_return","injured","closed"]:
   var s=fixture(cart)
   if not s.request_rescue("worker:0","worker:2",s.session_id).ok: continue
   if mode=="cancel_move": s.tick(0.3)
   else:
    walk(s,"rescue_hold",false,cart)
    if mode in ["cancel_return","closed"]:
     s.request_rescue_return("worker:0",s.session_id);s.tick(0.4)
   var dropped := pos(s.actors["worker:0"])
   var left: float=s.rescue_ledger.case_for("worker:0").left
   if mode=="injured":
    s.actors["worker:2"].hp=10.0
    s._begin_injured_return("worker:2",s.actors["worker:2"])
    s.rescue_approach.sync(s)
   elif mode=="closed": s.set_all_routes_closed(true)
   else: s.cancel_rescue("worker:0",s.session_id)
   check(s.rescue_ledger.case_for("worker:0").phase=="waiting" and s.rescue_ledger.case_for("worker:0").left==left and pos(s.actors["worker:0"])==dropped,"interruption preserves exact drop and remainder")
   if mode=="closed":
    var here := pos(s.actors["worker:2"])
    s.tick(1.0)
    check(pos(s.actors["worker:2"])==here and s.actors["worker:2"].state=="safe_wait","closed route pauses released carrier")
    s.set_all_routes_closed(false)
   check(walk(s,"injured_wait" if mode=="injured" else "idle",false,cart),"released carrier reaches entrance safely mode="+mode)
   check(pos(s.actors["worker:2"])==Session.BASE and not s.rescue_approach.owns("worker:2"),"release owner ends only at exact BASE")
   check(pos(s.actors["worker:0"])==dropped and s.actors["worker:0"].down,"release never drags or heals target")
func test_clearance() -> void:
 var s=fixture(true)
 place(s.actors["worker:2"],Session.MINE_PATH_CART_DETOUR_ENTRY.lerp(Session.MINE_PATH_CART_DETOUR,0.5))
 check(s.request_rescue("worker:0","worker:2",s.session_id).ok,"mid-detour rescue starts")
 if s.actors["worker:2"].state!="rescue_move": return
 var path: Array=s.actors["worker:2"].path.duplicate(true)
 s.intermediate_access="cleared";s._mine_path_route_changed("test clearance")
 check(s.actors["worker:2"].path==path,"clearance does not replan active rescue leg")
 check(walk(s,"rescue_hold",false,true,true),"old detour remains reachable after clearance")
 check(s.request_rescue_return("worker:0",s.session_id).ok,"new return plans after clearance")
 check(s.actors["worker:2"].path.has(s._point_array(Session.MINE_PATH_CART_SHORTCUT)),"next return uses cleared shortcut through anchors")
 check(walk(s,"idle",true,true,true),"cleared return remains on valid edges")
