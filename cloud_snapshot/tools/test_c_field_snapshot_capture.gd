extends SceneTree
## Producer for test_c_rescue_natural_restart. Run consecutively through the
## existing runner: separate engines, shared runner-owned isolated user home.
## Natural mining/escort movement. Only down is injected; not combat or OS-input proof.
const Session = preload("res://bridge/route_connection_session.gd")
const PATH := "user://c-field-snapshot.json"
const RECEIPT := "user://c-field-snapshot-receipt.json"
const FORBIDDEN := "user://c-rescue-natural-forbidden.json"
var main
var assertions := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL", label])
 if not ok: failures += 1
func isolated() -> bool:
 var home := OS.get_environment("FLUID_TEST_HOME").replace("\\", "/").simplify_path().trim_suffix("/")
 return not home.is_empty() and OS.get_user_data_dir().replace("\\", "/").simplify_path().begins_with(home + "/")
func advance(clock, predicate: Callable, seconds: float) -> bool:
 for unused in ceili(seconds / 0.05):
  if predicate.call(): return true
  clock.tick(0.05)
 return predicate.call()
func run() -> void:
 if not isolated(): quit(2); return
 SaveGame.disabled = true
 paused = false
 main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed",104729)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 main.director.enabled = false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list(): w.priorities[job] = 0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"normal trip requests " + destination)
  for unused in 300:
   main._process(0.25)
   await process_frame
   if main.world.region == destination and main.world.phase == "stopped": break
  check(main.world.region == destination and main.world.phase == "stopped","normal trip reaches " + destination)
 if failures: await finish(); return
 var gate = main.mine_arrival_gate
 gate._process(0.0)
 # The actual gate must restore this pre-entry saving policy on successful exit.
 SaveGame.disabled = false
 main.operations.set_stance("alert")
 var floor_before: int = main.workers[0].floor_i
 main.workers[0].floor_i = 0 # Explicit pending-entry readiness fixture.
 check(not gate.enter_mine() and gate.visible_state() == "entry_wait","pending entry owns temporary recall stance")
 main.workers[0].floor_i = floor_before
 gate._process(0.0)
 check(gate.field != null,"actual default gate completes pending entry")
 if gate.field == null: await finish(); return
 var adapter = gate.field
 adapter.process_mode = Node.PROCESS_MODE_DISABLED
 var s = adapter.session
 var clock = adapter.life_clock
 check(SaveGame.disabled and clock.is_current(),"field owns save restriction and live clock")
 check(s.mine_path_engineering and not s.outpost_enabled,"ordinary mine geometry, not outpost override")
 clock.tick(0.25)
 var early = SaveGame.capture(main)
 # Bundled complete-DTO scalar boundary checks from independent review.
 var malformed_cases:=[]
 var ordinary_id=""
 for id in early.field_snapshot.plans:
  if early.field_snapshot.plans[id].source=="ordinary":ordinary_id=id;break
 check(not ordinary_id.is_empty(),"early fixture has an ordinary moving plan")
 var malformed=early.duplicate(true)
 malformed.field_snapshot.plans[ordinary_id].command_state=Vector2(4,5)
 malformed_cases.append([malformed,"ordinary command state type"])
 malformed=early.duplicate(true)
 malformed.field_snapshot.session.actors[2]=malformed.field_snapshot.session.actors["worker:2"]
 malformed.field_snapshot.session.actors.erase("worker:2")
 malformed_cases.append([malformed,"integer actor identity"])
 var resource_id=early.field_snapshot.session.resources.keys()[0]
 malformed=early.duplicate(true)
 malformed.field_snapshot.session.resources[resource_id].kind=Vector2(4,5)
 malformed_cases.append([malformed,"resource kind type"])
 malformed=early.duplicate(true)
 malformed.field_snapshot.session.reservations[resource_id]=Vector2(4,5)
 malformed_cases.append([malformed,"resource reservation value type"])
 malformed=early.duplicate(true)
 malformed.field_snapshot.traces["worker:2"].reason="explicit invalid trace fixture"
 malformed.field_snapshot.traces["worker:2"]["transported_by"]="worker:1"
 malformed.field_snapshot.traces["worker:2"].erase("transport_gear")
 check(SaveGame.safe(malformed),"invalid metadata fixture reaches structural validation")
 malformed_cases.append([malformed,"invalid trace transport metadata pair"])
 for test_case in malformed_cases:
  var live=gate.field
  var live_clock=live.life_clock
  var live_before=SaveGame.capture(main)
  var accepted=SaveGame.apply(main,test_case[0])
  check(not accepted,"clean rejection: "+test_case[1])
  if accepted:
   check(SaveGame.apply(main,early),"restore fixture after unexpected acceptance")
  else:
   check(gate.field==live and live_clock.is_current() and SaveGame.capture(main)==live_before,"rollback: "+test_case[1])
 var omitted=early.duplicate(true)
 check(omitted.crew[2].worker.work_support==-1,"optional default fixture is unequipped")
 omitted.crew[2].worker.erase("work_support")
 check(SaveGame.validate(omitted,main),"omitted ordinary Main support uses the same legacy default")
 adapter=gate.field
 adapter.process_mode=Node.PROCESS_MODE_DISABLED
 s=adapter.session
 clock=adapter.life_clock
 if paused:adapter._toggle_field_pause()
 var closed_only = early.duplicate(true)
 closed_only.field_snapshot.session.all_routes_closed = true
 check(not SaveGame.validate(closed_only,main),"closed routes cannot retain an active ordinary movement command")
 for unused in 200:
  if int(s.actors["worker:0"].carry_n) > 0: break
  clock.tick(0.37)
 check(int(s.actors["worker:0"].carry_n)>0,"natural harvest obtains cargo before field saving")
 check(SaveGame.validate(SaveGame.capture(main),main),"inactive harvest timer preserves valid save after overshoot")
 var target = s.actors["worker:0"]
 s._begin_outpost_down("worker:0",target)
 clock.tick(0.25)
 var before = s.to_dict()
 var inventory = main.storage.inventory.counts.duplicate(true)
 var snapshot = SaveGame.capture(main)
 check(snapshot.has("field_snapshot"),"complete save captures owned C field")
 check(s.to_dict() == before,"capture does not mutate field or rescue remainder")
 check(main.storage.inventory.counts == inventory,"capture does not return or duplicate kit")
 if snapshot.has("field_snapshot"):
  check(SaveGame.validate(snapshot,main),"complete captured bundle validates")
  var bad = snapshot.duplicate(true)
  bad.field_snapshot.session.life_clock_paid += 1.0
  check(not SaveGame.validate(bad,main),"inconsistent paid timer rejected")
 var altered = snapshot.duplicate(true)
 var rid = altered.field_snapshot.session.resources.keys()[0]
 altered.field_snapshot.session.resources[rid].initial += 1
 altered.field_snapshot.session.resources[rid].remaining += 1
 check(not SaveGame.validate(altered,main),"field initial source bound to Main source")
 altered = snapshot.duplicate(true)
 altered.field_snapshot.session.entry_director_elapsed += 1.0
 check(not SaveGame.validate(altered,main),"field clock bound to Main paid director time")
 altered = snapshot.duplicate(true)
 altered.field_snapshot.session.intermediate_access = "clearing"
 check(not SaveGame.validate(altered,main),"maintenance cannot lose its owner")
 altered = snapshot.duplicate(true)
 altered.field_snapshot.session.actors["worker:1"].state = "invented_state"
 check(not SaveGame.validate(altered,main),"unknown actor state refused")
 if not early.field_snapshot.plans.is_empty():
  var moving = early.field_snapshot.plans.keys()[0]
  altered = early.duplicate(true)
  altered.field_snapshot.plans.erase(moving)
  check(not SaveGame.validate(altered,main),"active navigation cannot lose plan witness")
  altered = early.duplicate(true)
  altered.field_snapshot.plans[moving].source = "rescue"
  check(not SaveGame.validate(altered,main),"ordinary movement cannot invent rescue authority")
 if early.field_snapshot.plans.has("worker:1"):
  altered = early.duplicate(true)
  altered.field_snapshot.session.actors["worker:1"].path = [[777.0,888.0]]
  altered.field_snapshot.session.actors["worker:1"].path_index = 0
  altered.field_snapshot.plans["worker:1"].path = [[777.0,888.0]]
  altered.field_snapshot.plans["worker:1"].index = 0
  check(not SaveGame.validate(altered,main),"coherent duplicate path cannot invent an ordinary destination")
 altered = snapshot.duplicate(true)
 altered.field_snapshot.session.actors["worker:1"].tools = 0
 check(not SaveGame.validate(altered,main),"scalar tool map refused without side effects")
 altered = snapshot.duplicate(true)
 altered.field_snapshot.session.phase = "ready_to_exit"
 check(not SaveGame.validate(altered,main),"waiting owner cannot masquerade as ready to exit")
 altered = snapshot.duplicate(true)
 altered.field_snapshot.session.actors["worker:0"].direct_depot_loop = true
 check(not SaveGame.validate(altered,main),"ordinary actor cannot adopt solo delivery policy")
 altered = snapshot.duplicate(true)
 altered.operations.rescue_cases = {"0":{"target":0,"carrier":-1,"phase":"waiting","left":90.0,"resume_return":false,"resume_manual_job":-1,"deferred_return":false}}
 altered.crew[0].ai.state = CharacterAI.State.DOWN
 check(not SaveGame.validate(altered,main),"Main and field rescue owners cannot coexist")
 altered = snapshot.duplicate(true)
 altered.erase("operations")
 check(not SaveGame.validate(altered,main),"complete field refuses missing Main operations")
 altered = snapshot.duplicate(true)
 altered.operations.erase("rescue_cases")
 check(not SaveGame.validate(altered,main),"complete field refuses missing explicit Main rescue ownership")
 var save_script = load("res://scripts/save_game.gd")
 check(save_script.has_method("write_field"),"dedicated atomic complete-field writer exists")
 if save_script.has_method("write_field"):
  check(save_script.call("write_field",main,PATH,true),"atomic field file writes")
  var file = SaveGame.read(PATH)
  check(file == snapshot,"real file preserves complete bundle")
  var receipt = FileAccess.open(RECEIPT,FileAccess.WRITE)
  receipt.store_string(JSON.stringify({"pid":OS.get_process_id(),"hash":FileAccess.get_sha256(PATH)}))
  receipt.close()
  var old_clock = adapter.life_clock
  check(SaveGame.apply(main,file),"validated field installs new runtime")
  check(gate.field != null and gate.field != adapter,"new adapter replaces old without commit")
  check(not old_clock.is_current(),"old clock invalidated")
  check(paused,"loaded field starts paused")
  if gate.field != null:
   check(gate.field.life_clock.is_current(),"fresh clock owns restored field")
   check(gate.field.session.rescue_ledger.to_dict() == before.rescue,"rescue remainder is not restarted")
   check(gate.field.session.life_clock_token != before.life_clock_token,"runtime token is replaced")
  check(main.storage.inventory.counts == inventory,"load preserves inventory without kit return")
 await finish()
func finish() -> void:
 SaveGame.disabled = true
 if main != null and is_instance_valid(main): main.queue_free()
 await process_frame
 print("C FIELD SNAPSHOT CAPTURE assertions=",assertions," failures=",failures)
 quit(0 if failures == 0 else 1)
