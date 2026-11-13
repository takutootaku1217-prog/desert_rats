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
 for unused in 200:
  if int(s.actors["worker:0"].carry_n)>0: break
  clock.tick(0.37)
 check(int(s.actors["worker:0"].carry_n)>0,"natural cargo before active-owner save matrix")
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 clock.tick(0.05)
 save_stage("waiting")
 check(s.request_rescue("worker:0","worker:2",s.session_id).get("ok",false),"real natural escort assignment")
 s.request_recall()
 clock.tick(0.05)
 save_stage("assigned")
 check(s.cancel_rescue("worker:0",s.session_id).get("ok",false),"cancel creates physical released-return owner")
 clock.tick(0.05)
 save_stage("released_return")
 check(s.request_rescue("worker:0","worker:2",s.session_id).get("ok",false),"reassign remaining waiting target")
 check(advance(clock,func(): return s.rescue_ledger.case_for("worker:0").get("phase")=="carried",60.0),"reach carried hold")
 save_stage("hold")
 check(s.request_rescue_return("worker:0",s.session_id).get("ok",false),"explicit carried return")
 clock.tick(0.05)
 save_stage("return")
 check(advance(clock,func(): return s.actors["worker:0"].state=="rescue_treatment",60.0),"reach physical entrance treatment")
 save_stage("treatment")
 check(advance(clock,func(): return s.phase=="ready_to_exit",60.0),"resolve legitimate treatment cargo dock")
 save_stage("treatment_ready")
 check(SaveGame.apply(main,SaveGame.read("user://c-field-owner-return.json")),"restore real carried return for final-correction save")
 adapter=main.mine_arrival_gate.field
 adapter.process_mode=Node.PROCESS_MODE_DISABLED
 s=adapter.session
 clock=adapter.life_clock
 adapter._toggle_field_pause()
 check(reach_return_correction(clock,s),"live clock creates a final return correction without editing positions")
 save_stage("return_correction")
 await finish()

func reach_return_correction(clock,s) -> bool:
 var a=s.actors["worker:2"]
 var root_witness=s.mine_rescue_traces._plans["worker:2"].witness.duplicate(true)
 for unused in 128:
  var plan=s.mine_rescue_traces._plans["worker:2"]
  if plan.get("correction",false):
   var gap=Vector2(a.x,a.y).distance_to(s.BASE)
   check(gap>0.0 and gap<=0.1 and a.path==[[s.BASE.x,s.BASE.y]] and a.path_index==0,"real final correction retains positive sub-tolerance gap")
   check(s.rescue_ledger.case_for("worker:0").get("phase")=="carried" and Vector2(a.x,a.y)==Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y) and s.rescue_approach._treatment.is_empty(),"correction keeps exact carried ownership before treatment")
   check(plan.witness==root_witness,"correction keeps the same immutable creation witness")
   return true
  if a.state!="rescue_return" or a.path_index>=a.path.size():return false
  var goal=Vector2(a.path[a.path_index][0],a.path[a.path_index][1])
  var distance=Vector2(a.x,a.y).distance_to(goal)
  var speed=maxf(1.0,float(a.path_speed))*float(a.get("life_move_mult",1.0))
  var travel=distance-minf(0.05,distance/2.0) if a.path_index==a.path.size()-1 else distance+0.001
  clock.tick(maxf(0.000001,travel/speed))
 return false

func save_stage(stage: String) -> void:
 var field = main.mine_arrival_gate.field
 var before = field.session.to_dict()
 var stock = main.storage.inventory.counts.duplicate(true)
 var path = "user://c-field-owner-"+stage+".json"
 var ok = SaveGame.write_field(main,path,true)
 check(ok,"write complete active owner stage "+stage)
 check(field.session.to_dict()==before and main.storage.inventory.counts==stock,"save stage has no ownership/time side effects "+stage)
 if ok:
  var file = SaveGame.read(path)
  check(file.field_snapshot.session.rescue==before.rescue,"exact residual rescue timer "+stage)
  var receipt = FileAccess.open(path+".receipt",FileAccess.WRITE)
  receipt.store_string(JSON.stringify({"pid":OS.get_process_id(),"hash":FileAccess.get_sha256(path),"stage":stage}))
  receipt.close()

func finish() -> void:
 SaveGame.disabled = true
 if main != null and is_instance_valid(main): main.queue_free()
 await process_frame
 print("C FIELD ACTIVE OWNER PRODUCER assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
