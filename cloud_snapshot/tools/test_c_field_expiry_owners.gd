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
 s._begin_outpost_down("worker:2",s.actors["worker:2"])
 s.request_recall()
 clock.tick(FieldOperations.RESCUE_SECONDS+FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 check(s.expired_recovery.owns("worker:0") and s.expired_recovery.owns("worker:2"),"both natural cargo and escort enter expiry owner")
 clock.tick(0.05)
 save_stage("expired_return")
 s.set_all_routes_closed(true)
 clock.tick(0.05)
 save_stage("expired_closed")
 s.set_all_routes_closed(false)
 check(advance(clock,func(): return s.expired_recovery._records["worker:0"].stage=="dock",90.0),"natural expired cargo reaches physical dock")
 save_stage("expired_dock")
 check(advance(clock,func(): return s.phase=="ready_to_exit",90.0),"expired actors reach safe wait")
 save_stage("expired_wait")
 check(SaveGame.apply(main,SaveGame.read("user://c-field-owner-expired_return.json")),"restore fixture to test invalid identity tombstone")
 adapter=main.mine_arrival_gate.field
 adapter.process_mode=Node.PROCESS_MODE_DISABLED
 s=adapter.session
 clock=adapter.life_clock
 adapter._toggle_field_pause()
 s.actors["worker:0"]=s.actors["worker:0"].duplicate(true)
 clock.tick(0.05)
 check(s.expired_recovery._records["worker:0"].invalid and s.actors["worker:0"].state=="safe_wait","identity mismatch creates inert expiry tombstone")
 save_stage("expired_invalid")
 await finish()

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
 print("C FIELD EXPIRY OWNER PRODUCER assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
