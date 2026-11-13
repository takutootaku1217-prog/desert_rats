extends SceneTree
const Session = preload("res://bridge/route_connection_session.gd")
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL", label])
 if not ok: failures += 1
func pos(a: Dictionary) -> Vector2: return Vector2(a.x,a.y)
func request(s, target := "worker:0", carrier := "worker:2", generation := "approach") -> Dictionary:
 return s.call("request_rescue",target,carrier,generation) if s.has_method("request_rescue") else {"ok":false}
func cancel(s, target := "worker:0", generation := "approach") -> Dictionary:
 return s.call("cancel_rescue",target,generation) if s.has_method("cancel_rescue") else {"ok":false}
func fixture():
 var s = Session.new()
 s.session_id = "approach"
 for i in 4:
  s.actors["worker:%d" % i] = {"worker_index":i,"name":"Crew%d" % i,"role":"escort" if i == 2 else "harvest","state":"idle","hp":100.0,"down":false,"x":150.0,"y":535.0,"carry_n":0,"carry_item":-1,"resource_id":"","combat_target":"","path":[],"path_index":0,"resume_state":"","work_support":-1,"life_move_mult":1.0,"wait_reason":"","work_left":0.0}
 s.actors["worker:0"].x = 1030.0
 s.actors["worker:0"].y = 235.0
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 return s
func pickup(s) -> void:
 for i in 250:
  if s.rescue_ledger.case_for("worker:0").get("phase") == "carried": return
  s.tick(0.05)
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2); return
 test_movement_and_hold()
 test_invalid_and_reserved()
 test_interruption()
 test_recall_and_routes()
 test_enemy_interruption()
 await test_real_clock()
 print("C RESCUE APPROACH assertions=",assertions," failures=",failures)
 quit(0 if failures == 0 else 1)
func test_movement_and_hold() -> void:
 var s = fixture()
 var target_start := pos(s.actors["worker:0"])
 var carrier_start := pos(s.actors["worker:2"])
 check(request(s).get("ok",false),"manual session command accepts an unladen available carrier")
 check(pos(s.actors["worker:2"]) == carrier_start and pos(s.actors["worker:0"]) == target_start,"assignment never teleports either actor")
 check(s.actors["worker:2"].state == "rescue_move" and s.actors["worker:2"].path == [[700.0,325.0],[1030.0,235.0]],"approach uses existing open gate route")
 s.tick(0.25)
 check(pos(s.actors["worker:2"]).distance_to(carrier_start) > 0.0 and pos(s.actors["worker:2"]).distance_to(carrier_start) <= 57.501,"real movement is bounded by existing 230 per second")
 check(s.rescue_ledger.case_for("worker:0").left == 89.75 and s.rescue_ledger.case_for("worker:0").phase == "assigned","approach consumes deadline and cannot pick up from afar")
 check(pos(s.actors["worker:0"]) == target_start,"downed target stays in place during approach")
 var before: Dictionary = s.to_dict()
 s.tick(100.0,true)
 check(s.to_dict() == before,"explicit pause freezes approach and deadline together")
 pickup(s)
 check(s.rescue_ledger.case_for("worker:0").phase == "carried" and s.actors["worker:2"].state == "rescue_hold","physical arrival performs pickup and holds")
 check(pos(s.actors["worker:2"]) == target_start and pos(s.actors["worker:0"]) == target_start,"pickup needs exact shared coordinates")
 var left: float = s.rescue_ledger.case_for("worker:0").left
 s._begin_outpost_down("worker:1",s.actors["worker:1"])
 var time: float = s.elapsed
 s.tick(3.0)
 check(s.rescue_ledger.case_for("worker:0").left == left and s.rescue_ledger.case_for("worker:1").left == 87.0 and s.elapsed == time + 3.0,"hold pauses only its target, not other rescue or world time")
 check(pos(s.actors["worker:0"]) == target_start and pos(s.actors["worker:2"]) == target_start and s.actors["worker:0"].down,"holding is not transport, healing or deletion")
 check(s._outpost_actor_can_be_targeted("worker:2",{"x":1030.0,"y":235.0}),"pickup does not make the escort immune to nearby existing enemies")
 check(not Session.from_dict(s.to_dict()).get("ok",false),"active approach snapshot does not enable unimplemented restore")
 var near = fixture()
 near.actors["worker:0"].x = 150.06
 near.actors["worker:0"].y = 535.0
 request(near)
 near.tick(0.0001)
 check(near.rescue_ledger.case_for("worker:0").phase == "assigned" and pos(near.actors["worker:2"]) != pos(near.actors["worker:0"]),"existing 0.1 path tolerance cannot pick up before exact arrival")
 near.tick(0.01)
 check(near.rescue_ledger.case_for("worker:0").phase == "carried","remaining subpixel approach reaches exact target without stuck assignment")
 var slowed = fixture()
 slowed.actors["worker:2"].life_move_mult = 0.5
 request(slowed)
 slowed.tick(0.25)
 check(absf(pos(slowed.actors["worker:2"]).distance_to(carrier_start)-28.75) < 0.002,"approach retains the existing life movement multiplier")
func test_invalid_and_reserved() -> void:
 for flaw in ["stale","empty_id","self","missing_target","missing_carrier","healthy_target","closed","committed","ready","mine","maintenance","frame","tool","handcart","dock_queue","dock_busy","reservation","resource_owner","enemy_owner","cargo","injured","combat","other_assignment"]:
  var s = fixture()
  var generation := "approach"
  var target := "worker:0"
  var carrier := "worker:2"
  match flaw:
   "stale": generation = "previous"
   "empty_id": generation = ""
   "self": carrier = target
   "missing_target": target = "missing"
   "missing_carrier": carrier = "missing"
   "healthy_target": target = "worker:1"
   "closed": s.all_routes_closed = true
   "committed": s.committed = true
   "ready": s.phase = "ready_to_exit"
   "mine":
    s.mine_path_engineering = true
    s.actors[target].x = 613.0
    s.actors[target].y = 271.0
   "maintenance": s.maintenance_actor_id = carrier
   "frame": s.field_frame_exchange = {"status":"scheduled","source_id":carrier,"target_id":"worker:1"}
   "tool": s.field_tool_swap = {"status":"scheduled","actor_id":carrier}
   "handcart": s.return_handcart_exchange = {"status":"reserved","target_id":carrier}
   "dock_queue": s.dock_queue.append(carrier)
   "dock_busy": s.dock_busy[carrier] = 1.0
   "reservation": s.reservations["ore"] = carrier
   "resource_owner": s.resources["ore"] = {"reservation":carrier,"remaining":1,"initial":1,"item":GameData.Item.STONE}
   "enemy_owner": s.outpost_enemies["enemy"] = {"engager":carrier}
   "cargo": s.actors[carrier].carry_n = 1; s.actors[carrier].carry_item = GameData.Item.STONE
   "injured": s.actors[carrier].hp = 30.0
   "combat": s.actors[carrier].combat_target = "enemy"
   "other_assignment": s._begin_outpost_down("worker:1",s.actors["worker:1"]); request(s,"worker:1",carrier)
  var before: Dictionary = s.to_dict()
  check(not request(s,target,carrier,generation).get("ok",false) and s.to_dict() == before,"invalid or reserved command is non-mutating: " + flaw)
 var s = fixture()
 request(s)
 var before: Dictionary = s.to_dict()
 check(not request(s).get("ok",false) and s.to_dict() == before,"repeat assignment cannot reset path or deadline")
 check(not cancel(s,"worker:0","previous").get("ok",false) and s.to_dict() == before,"stale cancel cannot alter current rescue")
 s.vertical_slice = true
 s.actors["worker:2"].work_support = GameData.Item.HAUL_FRAME
 s.resources["ore"] = {"reservation":"","remaining":10,"initial":10,"item":GameData.Item.STONE}
 check(not s.request_field_frame_to_harvest().get("ok",false),"new frame job cannot steal rescue carrier")
 check(not s.request_intermediate_clearance().get("ok",false),"new maintenance job cannot steal rescue carrier")
 var conflict = fixture()
 conflict.actors["worker:0"].role = "carry"
 conflict.actors["worker:1"].role = "harvest"
 conflict.actors["worker:2"].work_support = GameData.Item.HAUL_FRAME
 conflict.vertical_slice = true
 conflict.resources["ore"] = {"reservation":"","remaining":10,"initial":10,"item":GameData.Item.STONE}
 request(conflict)
 before = conflict.to_dict()
 check(not conflict.request_field_frame_to_harvest().get("ok",false) and conflict.to_dict() == before,"otherwise valid frame job cannot steal a healthy rescue carrier")
 var tool = fixture()
 tool.vertical_slice = true
 tool.actors["worker:0"].role = "carry"
 tool.actors["worker:1"].role = "carry"
 tool.actors["worker:2"].role = "harvest"
 tool.actors["worker:2"].tools = {"mine":GameData.Item.HAMMER}
 tool.actors["worker:2"].field_tool_kit = {"mine":GameData.Item.PICKAXE}
 check(tool.request_field_tool_swap().get("ok",false) and tool.cancel_field_tool_swap().get("ok",false),"tool fixture has a valid exchange before rescue")
 check(request(tool).get("ok",false),"tool carrier can instead receive manual rescue")
 before = tool.to_dict()
 check(not tool.request_field_tool_swap().get("ok",false) and tool.to_dict() == before,"otherwise valid tool exchange cannot reserve a rescue carrier")
func test_interruption() -> void:
 for flaw in ["cancel","closed","down","injured","missing","reservation","expired"]:
  var s = fixture()
  request(s)
  if flaw != "expired": pickup(s)
  var point := pos(s.actors["worker:0"])
  var left: float = s.rescue_ledger.case_for("worker:0").left
  match flaw:
   "cancel": check(cancel(s).get("ok",false),"explicit interruption accepted")
   "closed": s.set_all_routes_closed(true)
   "down": s.actors["worker:2"].hp = 0.0
   "injured": s.actors["worker:2"].hp = 30.0
   "missing": s.actors.erase("worker:2")
   "reservation": s.reservations["ore"] = "worker:2"
  s.tick(91.0 if flaw == "expired" else 0.25)
  var row: Dictionary = s.rescue_ledger.case_for("worker:0")
  check(row.carrier == "" and row.phase == ("incapacitated" if flaw == "expired" else "waiting"),"interruption releases ledger assignment: " + flaw)
  check(row.left == (599.0 if flaw == "expired" else left-0.25),"interruption retains exact remainder: " + flaw)
  check(pos(s.actors["worker:0"]) == point and s.actors["worker:0"].down,"interruption leaves target in place: " + flaw)
  if s.actors.has("worker:2"):
   check(s.actors["worker:2"].state not in ["rescue_move","rescue_hold"],"interruption releases movement ownership: " + flaw)
  var after: Dictionary = s.to_dict()
  check(not cancel(s).get("ok",false) and s.to_dict() == after,"repeat cancel is non-mutating: " + flaw)
 var loaded = fixture()
 loaded.actors["worker:0"].carry_item = GameData.Item.STONE
 loaded.actors["worker:0"].carry_n = 2
 request(loaded)
 pickup(loaded)
 cancel(loaded)
 check(loaded.actors["worker:0"].carry_item == GameData.Item.STONE and loaded.actors["worker:0"].carry_n == 2 and loaded.depot_stock.is_empty() and loaded.relay_stock.is_empty(),"pickup and interruption leave downed actor cargo in place")
func test_recall_and_routes() -> void:
 var s = fixture()
 s.set_gate_closed(true)
 request(s)
 check(s.actors["worker:2"].path == [[700.0,535.0],[1030.0,235.0]],"closed main route uses existing bypass")
 s.tick(0.25)
 var point := pos(s.actors["worker:2"])
 s.set_gate_closed(false)
 check(pos(s.actors["worker:2"]) == point and s.actors["worker:2"].path == [[700.0,325.0],[1030.0,235.0]],"route change replans from current position without teleport")
 s.request_recall()
 check(s.actors["worker:2"].state == "rescue_move" and s.rescue_ledger.case_for("worker:0").phase == "assigned","recall does not steal a manually assigned rescue carrier")
 pickup(s)
 s.tick(1.0)
 check(s.phase == "recall" and s.actors["worker:2"].state == "rescue_hold","partial rescue keeps return blocked until transport and treatment are connected")
func test_enemy_interruption() -> void:
 for role in ["harvest","carry","escort"]:
  var s = fixture()
  s.actors["worker:2"].role = role
  s.outpost_enabled = true
  s.outpost_cleared = false
  s.outpost_enemies["test-enemy"] = {"kind":Session.OUTPOST_KIND,"x":1030.0,"y":235.0,"home_x":1030.0,"home_y":235.0,"hp":100.0,"dead":false,"engager":"","target":"","attack_left":0.0}
  check(not s._outpost_actor_can_be_targeted("worker:2",{"x":150.0,"y":535.0}),"ordinary idle carrier does not gain a new combat order: " + role)
  request(s)
  pickup(s)
  check(s.rescue_ledger.case_for("worker:0").phase == "carried","live enemy fixture reaches pickup: " + role)
  var left: float = s.rescue_ledger.case_for("worker:0").left
  var point := pos(s.actors["worker:0"])
  s.actors["worker:2"].hp = 31.0
  s.outpost_enemies["test-enemy"].attack_left = 0.0
  s.tick(0.25)
  check(s.actors["worker:2"].hp == 29.5 and s.actors["worker:2"].state == "injured_return","real existing enemy damages and interrupts rescue role: " + role)
  check(s.rescue_ledger.case_for("worker:0").phase == "waiting" and s.rescue_ledger.case_for("worker:0").left == left and pos(s.actors["worker:0"]) == point,"end-of-frame hit releases hold in place without backdating time: " + role)
  s.tick(0.25)
  check(s.rescue_ledger.case_for("worker:0").left == left-0.25,"interrupted deadline resumes on next real tick: " + role)
func test_real_clock() -> void:
 SaveGame.disabled = true
 var main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed",104729)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 main.director.enabled = false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list(): w.priorities[job] = 0
 for dest in ["b_forest","c_quarry"]:
  check(main.world.request(dest),"real route fixture " + dest)
  for i in 300:
   main._process(0.25)
   await process_frame
   if main.world.region == dest and main.world.phase == "stopped": break
 var made: Dictionary = Session.create_from_game(main,"approach",{"outpost_enabled":true})
 check(made.get("ok",false),"real C outpost session created")
 if not made.get("ok",false): main.queue_free(); await process_frame; return
 var s = made.session
 var orphan: Dictionary = s.to_dict()
 orphan.actors["worker:2"].state = "rescue_move"
 check(not Session.from_dict(orphan).get("ok",false),"orphan rescue movement snapshot cannot restore a frozen healthy actor")
 for state in ["rescue_move","rescue_hold"]:
  orphan = s.to_dict()
  orphan.actors["worker:2"].state = "safe_wait"
  orphan.actors["worker:2"].resume_state = state
  check(not Session.from_dict(orphan).get("ok",false),"orphan rescue resume state cannot restore a frozen healthy actor: " + state)
 for a in s.actors.values(): a.state = "idle"; a.path = []
 s.outpost_cleared = true # Isolated damage-free fixture, not a combat success claim.
 for enemy in s.outpost_enemies.values(): enemy.dead = true; enemy.hp = 0.0
 s.actors["worker:0"].x = 1030.0
 s.actors["worker:0"].y = 235.0
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 check(Session.from_dict(s.to_dict()).get("ok",false),"real waiting rescue snapshot is otherwise valid before movement")
 var clock = FieldSurvivalClock.new()
 check(clock.setup(main,s).get("ok",false),"bind real life clock")
 var ordinary: Dictionary = main.operations.rescue_cases.duplicate(true)
 var stock: Dictionary = main.storage.inventory.counts.duplicate(true)
 var world: Dictionary = main.world.locations.duplicate(true)
 check(request(s).get("ok",false),"real session starts physical approach")
 clock.tick(0.25)
 check(s.rescue_ledger.case_for("worker:0").left == 89.75 and s.elapsed == s.life_clock_paid,"life clock pays approach once")
 var before: Dictionary = s.to_dict()
 paused = true
 clock.tick(20.0)
 paused = false
 check(s.to_dict() == before,"tree pause freezes real approach")
 for i in 250:
  if s.rescue_ledger.case_for("worker:0").phase == "carried": break
  clock.tick(0.05)
 check(s.rescue_ledger.case_for("worker:0").phase == "carried","bound real clock reaches pickup")
 check(not Session.from_dict(s.to_dict()).get("ok",false),"otherwise valid active rescue snapshot remains explicitly blocked")
 check(main.operations.rescue_cases == ordinary and main.storage.inventory.counts == stock and main.world.locations == world,"approach does not run ordinary rescue AI or transfer inventory/world")
 check(not s.commit_to_game(main).get("ok",false) and SaveGame.disabled and not SaveGame.write(main,"user://rescue-approach-forbidden.json",true),"pickup never enables partial return or field save")
 main.storage.store_owned(GameData.Item.HANDCART,1,Inventory.SOURCE_TRANSFER)
 var cart = fixture()
 cart.vertical_slice = true
 cart.actors["worker:1"].role = "carry"
 check(cart.request_return_handcart_exchange(main).get("ok",false) and cart.cancel_return_handcart_exchange().get("ok",false),"handcart fixture has a valid return exchange before rescue")
 check(request(cart,"worker:0","worker:1").get("ok",false),"handcart carrier can instead receive manual rescue")
 var cart_before: Dictionary = cart.to_dict()
 var stock_before: Dictionary = main.storage.inventory.counts.duplicate(true)
 check(not cart.request_return_handcart_exchange(main).get("ok",false) and cart.to_dict() == cart_before and main.storage.inventory.counts == stock_before,"otherwise valid return exchange cannot reserve a rescue carrier or touch stock")
 main.queue_free()
 await process_frame
