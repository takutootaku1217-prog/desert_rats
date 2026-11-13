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
func transport(s, target := "worker:0", generation := "return") -> Dictionary:
 return s.call("request_rescue_return",target,generation) if s.has_method("request_rescue_return") else {"ok":false}
func fixture():
 var s = Session.new()
 s.session_id = "return"
 for i in 4:
  s.actors["worker:%d" % i] = {"worker_index":i,"name":"Crew%d" % i,"role":"escort" if i == 2 else "harvest","state":"idle","hp":100.0,"down":false,"x":150.0,"y":535.0,"carry_n":0,"carry_item":-1,"resource_id":"","combat_target":"","path":[],"path_index":0,"resume_state":"","work_support":-1,"life_move_mult":1.0,"wait_reason":"","work_left":0.0}
 s.actors["worker:0"].x = 1030.0
 s.actors["worker:0"].y = 235.0
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 return s
func pickup(s) -> void:
 s.request_rescue("worker:0","worker:2",s.session_id)
 for i in 1200:
  if s.rescue_ledger.case_for("worker:0").get("phase") == "carried": return
  s.tick(0.05)
func deliver(s) -> void:
 for i in 1200:
  if s.actors["worker:0"].state == "rescue_treatment": return
  s.tick(0.05)
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2); return
 test_return()
 test_interruption()
 test_capacity()
 test_return_enemy()
 test_treatment_ownership()
 await test_commit()
 print("C RESCUE RETURN assertions=",assertions," failures=",failures)
 quit(0 if failures == 0 else 1)
func test_return() -> void:
 var s = fixture()
 var before: Dictionary = s.to_dict()
 check(not transport(s).get("ok",false) and s.to_dict() == before,"unpicked target cannot start return")
 pickup(s)
 before = s.to_dict()
 check(not transport(s,"worker:0","old").get("ok",false) and s.to_dict() == before,"stale return command is non-mutating")
 check(transport(s).get("ok",false),"held rescue accepts explicit physical return")
 if not s.has_method("request_rescue_return"): return
 check(s.actors["worker:2"].state == "rescue_return" and s.actors["worker:2"].path == [[700.0,325.0],[150.0,535.0]],"return uses existing gate and entrance")
 before = s.to_dict()
 check(not transport(s).get("ok",false) and s.to_dict() == before,"repeated return does not restart or duplicate")
 var start := pos(s.actors["worker:0"])
 var left: float = s.rescue_ledger.case_for("worker:0").left
 s.tick(0.25)
 check(pos(s.actors["worker:0"]) == pos(s.actors["worker:2"]) and pos(s.actors["worker:0"]).distance_to(start) > 0.0 and pos(s.actors["worker:0"]).distance_to(start) <= 57.501,"carrier and target physically travel together at existing bounded speed")
 check(s.actors["worker:0"].down and s.actors["worker:0"].hp == 0.0 and s.rescue_ledger.case_for("worker:0").left == left,"travel preserves down state and frozen target deadline")
 before = s.to_dict()
 s.tick(100.0,true)
 check(s.to_dict() == before,"explicit pause freezes paired return")
 var point := pos(s.actors["worker:2"])
 s.set_gate_closed(true)
 check(pos(s.actors["worker:2"]) == point and s.actors["worker:2"].path == [[700.0,535.0],[150.0,535.0]],"gate change repaths paired return without moving actors")
 s.request_recall()
 check(s.actors["worker:2"].state == "rescue_return","recall cannot steal transport owner")
 deliver(s)
 check(pos(s.actors["worker:0"]) == Session.BASE and pos(s.actors["worker:2"]) == Session.BASE,"treatment only starts at exact entrance for both actors")
 check(not s.actors["worker:0"].down and s.actors["worker:0"].hp == CrewStatusDB.HP_REVIVE_AT and s.actors["worker:0"].state == "rescue_treatment","entrance uses existing first-aid threshold and holds treatment")
 check(s.rescue_ledger.case_for("worker:0").is_empty() and not s.rescue_approach.owns("worker:2"),"delivered target releases rescue countdown and carrier exactly once")
 s.tick(20.0)
 check(s.actors["worker:0"].hp == CrewStatusDB.HP_REVIVE_AT and s.actors["worker:0"].state == "rescue_treatment","field never starts normal healing or work AI")
 check(not s.cancel_rescue("worker:0",s.session_id).get("ok",false),"completed transport cannot be cancelled into a new deadline")
 var near = fixture()
 near.actors["worker:0"].x = 150.06
 near.actors["worker:0"].y = 535.0
 pickup(near)
 transport(near)
 near.tick(0.0001)
 check(near.actors["worker:0"].down and pos(near.actors["worker:0"]) != Session.BASE,"0.1 ordinary path tolerance cannot deliver early")
 near.tick(0.01)
 check(near.actors["worker:0"].state == "rescue_treatment","subpixel final segment reaches entrance and delivers")
func test_interruption() -> void:
 for flaw in ["cancel","closed","injured","down","reservation"]:
  var s = fixture()
  pickup(s)
  check(transport(s).get("ok",false),"return interruption setup: " + flaw)
  if not s.has_method("request_rescue_return"): continue
  s.tick(0.5)
  var point := pos(s.actors["worker:0"])
  var left: float = s.rescue_ledger.case_for("worker:0").left
  match flaw:
   "cancel": s.cancel_rescue("worker:0",s.session_id)
   "closed": s.set_all_routes_closed(true)
   "injured": s.actors["worker:2"].hp = 30.0
   "down": s.actors["worker:2"].hp = 0.0
   "reservation": s.reservations["ore"] = "worker:2"
  s.tick(0.25)
  check(s.rescue_ledger.case_for("worker:0").phase == "waiting" and s.rescue_ledger.case_for("worker:0").left == left-0.25,"interruption resumes original deadline: " + flaw)
  check(pos(s.actors["worker:0"]) == point and s.actors["worker:0"].down,"interruption drops at current return position: " + flaw)
func test_capacity() -> void:
 var s = fixture()
 s.vertical_slice = true
 s.field_capacity_limit_weight = 0
 s.resources["ore"] = {"item":GameData.Item.STONE,"initial":2,"remaining":0,"reservation":""}
 s.actors["worker:0"].carry_n = 2
 s.actors["worker:0"].carry_item = GameData.Item.STONE
 pickup(s)
 check(transport(s).get("ok",false),"loaded target can return without making carrier cargo")
 if not s.has_method("request_rescue_return"): return
 deliver(s)
 s.tick(1.0)
 check(s.actors["worker:0"].state == "rescue_treatment" and s.actors["worker:0"].carry_n == 2 and s.depot_stock.is_empty() and s.conservation_ok(),"full depot retains treatment target cargo at entrance")
 s.request_recall()
 s.tick(1.0)
 check(s.phase != "ready_to_exit" and s.actors["worker:0"].state == "rescue_treatment","recall cannot discard pending treatment cargo")
 s.field_capacity_limit_weight = 100
 s.tick(0.01)
 check(s.dock_busy.has("worker:0") and s.actors["worker:0"].carry_n == 2,"treatment cargo uses existing timed dock rather than teleport deposit")
 s.tick(0.5)
 check(s.actors["worker:0"].carry_n == 0 and s.depot_stock.get(GameData.Item.STONE,0) == 2 and s.conservation_ok(),"dock deposits cargo once without releasing treatment state")
 s.tick(1.0)
 check(s.depot_stock.get(GameData.Item.STONE,0) == 2 and s.actors["worker:0"].state == "rescue_treatment","repeat treatment ticks cannot duplicate deposited cargo")
func test_treatment_ownership() -> void:
 for job in ["maintenance","frame","tool"]:
  var s = fixture()
  s.vertical_slice = true
  s.resources["ore"] = {"item":GameData.Item.STONE,"initial":10,"remaining":10,"reservation":""}
  s.actors["worker:0"].role = "harvest" if job == "tool" else "escort"
  s.actors["worker:1"].role = "carry" if job == "tool" else "harvest"
  s.actors["worker:2"].role = "carry"
  s.actors["worker:3"].role = "carry"
  s.actors["worker:0"].work_support = GameData.Item.HAUL_FRAME if job == "frame" else -1
  s.actors["worker:0"].tools = {"mine":GameData.Item.HAMMER}
  s.actors["worker:0"].field_tool_kit = {"mine":GameData.Item.PICKAXE}
  pickup(s)
  transport(s)
  deliver(s)
  check(s.actors["worker:0"].state == "rescue_treatment","treatment owner fixture: " + job)
  var before: Dictionary = s.to_dict()
  var result: Dictionary = {}
  match job:
   "maintenance": result = s.request_intermediate_clearance()
   "frame": result = s.request_field_frame_to_harvest()
   "tool": result = s.request_field_tool_swap()
  check(not result.get("ok",false) and s.to_dict() == before,"ordinary job cannot steal pending treatment actor: " + job)
func test_return_enemy() -> void:
 for role in ["harvest","carry","escort"]:
  var s = fixture()
  pickup(s)
  s.actors["worker:2"].role = role
  transport(s)
  s.actors["worker:2"].hp = 31.0
  s.outpost_enabled = true
  s.outpost_cleared = false
  s.outpost_enemies["enemy"] = {"kind":Session.OUTPOST_KIND,"x":1030.0,"y":235.0,"home_x":1030.0,"home_y":235.0,"hp":100.0,"dead":false,"engager":"","target":"","attack_left":0.0}
  var left: float = s.rescue_ledger.case_for("worker:0").left
  s.tick(0.05)
  var point := pos(s.actors["worker:0"])
  check(s.actors["worker:2"].hp == 29.5 and s.rescue_ledger.case_for("worker:0").phase == "waiting" and s.rescue_ledger.case_for("worker:0").left == left,"real enemy tick interrupts transport same frame: " + role)
  s.tick(0.25)
  check(pos(s.actors["worker:0"]) == point and s.rescue_ledger.case_for("worker:0").left == left-0.25,"enemy interruption drops at moved position and resumes next tick: " + role)
func test_commit() -> void:
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
 var made: Dictionary = Session.create_from_game(main,"return",{"outpost_enabled":true})
 check(made.get("ok",false),"real return session created")
 if not made.get("ok",false): main.queue_free(); await process_frame; return
 var s = made.session
 for state in ["rescue_return","rescue_treatment"]:
  for field in ["state","resume_state"]:
   var orphan: Dictionary = s.to_dict()
   orphan.actors["worker:2"][field] = state
   check(not Session.from_dict(orphan).get("ok",false),"orphan live ownership snapshot rejected: " + field + "/" + state)
 for a in s.actors.values(): a.state = "idle"; a.path = []
 s.outpost_cleared = true # Isolated damage-free fixture, not a combat success claim.
 for enemy in s.outpost_enemies.values(): enemy.dead = true; enemy.hp = 0.0
 s.actors["worker:0"].x = 1030.0
 s.actors["worker:0"].y = 235.0
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 var clock = FieldSurvivalClock.new()
 check(clock.setup(main,s).get("ok",false),"bind real life clock")
 var adapter = load("res://bridge/route_connection_adapter.gd").new()
 adapter.configure(main,s)
 adapter.process_mode = Node.PROCESS_MODE_DISABLED
 root.add_child(adapter)
 await process_frame
 var ordinary: Dictionary = main.operations.rescue_cases.duplicate(true)
 var stock: Dictionary = main.storage.inventory.counts.duplicate(true)
 var world: Dictionary = main.world.locations.duplicate(true)
 pickup(s)
 check(transport(s).get("ok",false),"real session accepts transport")
 if not s.has_method("request_rescue_return"): main.queue_free(); await process_frame; return
 check(not Session.from_dict(s.to_dict()).get("ok",false),"live return snapshot remains unsupported")
 for i in 1200:
  if s.actors["worker:0"].state == "rescue_treatment": break
  clock.tick(0.05)
 check(main.operations.rescue_cases == ordinary and main.storage.inventory.counts == stock and main.world.locations == world,"field transport never runs normal rescue or changes source/inventory authority")
 check(not Session.from_dict(s.to_dict()).get("ok",false),"pending treatment snapshot cannot lose live handoff ownership")
 check(SaveGame.disabled and not SaveGame.write(main,"user://rescue-return-forbidden.json",true),"pending treatment does not enable field save")
 s.request_recall()
 for i in 300:
  if s.phase == "ready_to_exit": break
  clock.tick(0.05)
 check(s.phase == "ready_to_exit" and s._local_exit_ready(),"all returned actors and cargo permit pending treatment commit")
 var worker = main.workers[0]
 for pair in [["hp",NAN],["hp",INF],["hp",101.0],["hp","20"],["carry_n",0.5],["carry_n",NAN],["carry_item",GameData.Item.STONE],["worker_index",0.5],["down",0]]:
  var original: Dictionary = s.actors["worker:0"].duplicate(true)
  s.actors["worker:0"][pair[0]] = pair[1]
  check(not s.rescue_approach.commit_preflight(s,main).get("ok",false) and main.storage.inventory.counts == stock and main.world.locations == world,"malformed pending value rejected before external writes: " + str(pair))
  s.actors["worker:0"] = original
 for flaw in ["position","hp","state"]:
  var original: Dictionary = s.actors["worker:0"].duplicate(true)
  match flaw:
   "position": s.actors["worker:0"].x += 1.0
   "hp": s.actors["worker:0"].hp = 0.1
   "state": s.actors["worker:0"].state = "idle"
  var rejected: Dictionary = s.to_dict()
  check(not s.commit_to_game(main).get("ok",false) and s.to_dict() == rejected and main.storage.inventory.counts == stock and main.world.locations == world,"invalid treatment rejects before external writes: " + flaw)
  s.actors["worker:0"] = original
 main.operations.rescue_cases["0"] = {"foreign":true}
 var before: Dictionary = s.to_dict()
 check(not s.commit_to_game(main).get("ok",false) and s.to_dict() == before and main.storage.inventory.counts == stock and main.world.locations == world,"conflicting normal rescue ledger rejects before any commit writes")
 main.operations.rescue_cases.erase("0")
 var count: int = main.workers.size()
 check(s.commit_to_game(main).get("ok",false),"safe return commits treatment handoff")
 check(main.workers.size() == count and worker.hp == CrewStatusDB.HP_REVIVE_AT and not worker.down and worker.ai.state == CharacterAI.State.RESCUE_RECOVER,"commit preserves person count and sets only existing recovery state")
 check(main.operations.rescue_phase_for(worker) == "recovering" and FieldOperations.rescue_cases_valid(main.operations.rescue_cases,main.workers.size()),"handoff conforms to existing serializable normal rescue contract")
 check(main.operations.rescue_case_for(worker).get("resume_return") == true,"recovery defaults to waiting, never newly invented automatic work resume")
 var entry_stock: Dictionary = main.storage.inventory.counts.duplicate(true)
 var entry_world: Dictionary = main.world.locations.duplicate(true)
 var entry_cases: Dictionary = main.operations.rescue_cases.duplicate(true)
 check(not Session.create_from_game(main,"early-reentry",{}).get("ok",false) and main.operations.rescue_cases == entry_cases and main.storage.inventory.counts == entry_stock and main.world.locations == entry_world,"new C entry cannot suspend existing normal treatment authority")
 var after: Dictionary = main.operations.rescue_cases.duplicate(true)
 var committed_stock: Dictionary = main.storage.inventory.counts.duplicate(true)
 check(s.commit_to_game(main).get("already_committed",false) and main.operations.rescue_cases == after and main.storage.inventory.counts == committed_stock,"repeat commit does not duplicate treatment or inventory")
 adapter._restore_workers()
 check(worker.position == main.storage.access_point() + worker.slot_offset and worker.target == worker.position and worker.floor_i == GameData.floor_of_y(worker.position.y),"actual adapter restoration preserves treatment entrance position and floor")
 adapter.queue_free()
 await process_frame
 worker.ai.tick(0.1)
 check(worker.resting and worker.ai.state == CharacterAI.State.RESCUE_RECOVER,"only post-commit normal AI begins existing rest treatment")
 worker.hp = FieldOperations.RECOVER_HP
 main.operations.finish_rescue_recovery(worker)
 check(main.operations.rescue_case_for(worker).is_empty() and worker.ai.return_request,"existing provisional recovery gate ends in explicit waiting")
 check(Session.create_from_game(main,"after-recovery",{}).get("ok",false),"new C entry is available after existing recovery clears ownership")
 main.operations.rescue_cases["1"] = {"target":1,"carrier":0,"phase":"assigned","left":80.0,"resume_return":false,"resume_manual_job":-1,"deferred_return":false}
 var carrier_entry: Dictionary = Session.create_from_game(main,"carrier-reentry",{})
 check(not carrier_entry.get("ok",false) and "救助" in str(carrier_entry.get("reason","")),"normal carrier ownership also blocks new C entry before target handling")
 main.operations.rescue_cases.erase("1")
 main.queue_free()
 await process_frame
