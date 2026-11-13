extends SceneTree
const Session = preload("res://bridge/route_connection_session.gd")
const MODEL_PATH := "res://bridge/c_quarry_rescue_ledger.gd"
var failures := 0
var assertions := 0
var model
var main
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL", label])
 if not ok: failures += 1
func fixture() -> Dictionary:
 var a := {}
 for i in 4:
  a["worker:%d" % i] = {"hp":0.0 if i < 2 else 100.0,"down":i < 2,"x":0.0,"y":0.0,"carry_n":0,"carry_item":-1,"resource_id":"","combat_target":"","state":"down" if i < 2 else "idle"}
 return a
func ledger():
 var l = model.new()
 l.observe_down("worker:0", fixture())
 return l
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2); return
 var exists := ResourceLoader.exists(MODEL_PATH)
 check(exists, "actor rescue state contract exists")
 if exists:
  model = load(MODEL_PATH)
  test_clock()
  test_manual_and_interrupt()
  test_snapshots()
 await test_session(exists)
 print("C RESCUE STATE CONTRACT assertions=", assertions, " failures=", failures)
 quit(0 if failures == 0 else 1)
func test_clock() -> void:
 var a := fixture()
 var original: Dictionary = a.duplicate(true)
 var l = ledger()
 check(l.case_for("worker:0").phase == "waiting" and l.case_for("worker:0").left == FieldOperations.RESCUE_SECONDS, "down creates the existing 90-second rescue deadline")
 l.tick(2.25, a)
 check(l.case_for("worker:0").left == 87.75, "fractional game time is retained")
 check(not l.observe_down("worker:0", a) and l.case_for("worker:0").left == 87.75, "duplicate down never resets deadline")
 check(not l.observe_down("worker:2", a) and not l.observe_down("missing", a), "healthy and missing actors cannot become rescue targets")
 var snapshot: Dictionary = l.to_dict()
 for delta in [-1.0, 0.0, NAN, INF]:
  l.tick(delta, a)
  check(l.to_dict() == snapshot, "invalid delta is non-mutating " + str(delta))
 l.tick(900.0, a, true)
 check(l.to_dict() == snapshot, "explicit pause freezes deadline and phases")
 l.tick(87.75, a)
 check(l.case_for("worker:0").phase == "incapacitated" and l.case_for("worker:0").left == FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS, "expiry starts the shared provisional 600-second incapacitation")
 l.tick(0.125, a)
 check(l.case_for("worker:0").left == 599.875, "incapacitation uses game time")
 snapshot = l.to_dict()
 l.tick(700.0, a, true)
 check(l.to_dict() == snapshot, "explicit pause also freezes incapacitation")
 l.tick(599.875, a)
 check(l.case_for("worker:0").phase == "recovery_due" and l.case_for("worker:0").left == 0.0, "long incapacitation ends in internal recovery handoff intent")
 check(not l.assign("worker:0", "worker:2", a), "expired case cannot restart as a fresh rescue")
 l.tick(10000.0, a)
 check(l.case_for("worker:0").phase == "recovery_due" and a == original, "model never heals, deletes actors, moves cargo or charges money")
 var one = ledger()
 one.tick(100.0, a)
 check(one.case_for("worker:0").phase == "incapacitated" and one.case_for("worker:0").left == 590.0, "large delta carries overflow into incapacitation")
 var split = ledger()
 for i in 100: split.tick(1.0, a)
 check(one.to_dict() == split.to_dict(), "time partition does not add a free frame")
 one.tick(1000.0, a)
 check(one.case_for("worker:0").phase == "recovery_due", "oversized delta reaches bounded terminal intent")
func test_manual_and_interrupt() -> void:
 var a := fixture()
 var l = ledger()
 check(l.observe_down("worker:1", a), "separate target gets its own deadline")
 var before: Dictionary = l.to_dict()
 for pair in [["worker:0","worker:0"],["worker:0","worker:1"],["missing","worker:2"],["worker:0","missing"]]:
  check(not l.assign(pair[0], pair[1], a) and l.to_dict() == before, "invalid manual identity is non-mutating " + str(pair))
 check(not l.assign("worker:0","worker:2",a,false), "closed route blocks manual assignment")
 for field in ["hp","down","carry_n","carry_item","resource_id","combat_target","state"]:
  var bad := a.duplicate(true)
  match field:
   "hp": bad["worker:2"][field] = FieldOperations.RETREAT_HP
   "down": bad["worker:2"][field] = true
   "carry_n": bad["worker:2"][field] = 1
   "carry_item": bad["worker:2"][field] = GameData.Item.STONE
   "resource_id": bad["worker:2"][field] = "reserved-resource"
   "combat_target": bad["worker:2"][field] = "claimed-enemy"
   "state": bad["worker:2"][field] = "maintenance_work"
  check(not l.assign("worker:0","worker:2",bad) and l.to_dict() == before, "unavailable carrier rejected: " + field)
 check(l.assign("worker:0","worker:2",a), "manual carrier assignment accepted")
 check(not l.assign("worker:1","worker:2",a), "carrier cannot own two rescues")
 check(not l.pickup("worker:0","worker:3",a), "other carrier cannot perform pickup")
 l.tick(5.5, a)
 check(l.case_for("worker:0").left == 84.5, "assigned approach still consumes rescue time")
 a["worker:2"].x = 1.0
 check(not l.pickup("worker:0","worker:2",a), "pickup needs confirmed same-position arrival")
 a["worker:2"].x = 0.0
 check(not l.pickup("worker:0","worker:2",a,false), "closed route cannot pick up")
 check(l.pickup("worker:0","worker:2",a), "arrival allows the carried transition")
 var actors_before: Dictionary = a.duplicate(true)
 l.tick(10.0, a)
 check(l.case_for("worker:0").left == 84.5 and l.case_for("worker:1").left == 74.5, "pickup pauses only its target deadline, not other cases")
 check(a == actors_before, "carrying state does not impersonate physical movement")
 check(l.interrupt("worker:0") and l.case_for("worker:0").carrier == "", "manual interruption releases carrier")
 l.tick(0.5, a)
 check(l.case_for("worker:0").left == 84.0, "interrupt resumes exact remainder")
 check(not l.interrupt("worker:0"), "repeat interruption does not invent assignment")
 for cause in ["down","injured","cargo","reserved","missing","route"]:
  var actors := fixture()
  var active = ledger()
  active.assign("worker:0","worker:2",actors)
  active.pickup("worker:0","worker:2",actors)
  match cause:
   "down": actors["worker:2"].down = true; actors["worker:2"].hp = 0.0
   "injured": actors["worker:2"].hp = 30.0
   "cargo": actors["worker:2"].carry_n = 1
   "reserved": actors["worker:2"].resource_id = "new-reservation"
   "missing": actors.erase("worker:2")
  active.tick(1.25, actors, false, cause != "route")
  check(active.case_for("worker:0").phase == "waiting" and active.case_for("worker:0").carrier == "" and active.case_for("worker:0").left == 88.75, "interruption resumes clock: " + cause)
 var expired = ledger()
 expired.assign("worker:0","worker:2",a)
 expired.tick(91.0,a)
 check(expired.case_for("worker:0").carrier == "" and expired.case_for("worker:0").left == 599.0, "expiry releases assigned carrier and preserves overflow")
func test_snapshots() -> void:
 var a := fixture()
 for phase in ["waiting","assigned","carried","incapacitated","recovery_due"]:
  var l = ledger()
  l.tick(0.125, a)
  if phase in ["assigned","carried"]: l.assign("worker:0","worker:2",a)
  if phase == "carried": l.pickup("worker:0","worker:2",a)
  if phase == "incapacitated": l.tick(100.0,a)
  if phase == "recovery_due": l.tick(1000.0,a)
  var saved: Dictionary = l.to_dict()
  var result: Dictionary = model.from_dict(JSON.parse_string(JSON.stringify(saved)),a)
  check(result.get("ok",false) and result.ledger.to_dict() == saved, "JSON roundtrip preserves " + phase)
  saved.cases["worker:0"].left = 123.0
  var copied: Dictionary = l.case_for("worker:0")
  copied.left = 456.0
  check(l.case_for("worker:0").left != 123.0 and l.case_for("worker:0").left != 456.0, "snapshots and case reads are defensive: " + phase)
 var tuned: Dictionary = ledger().to_dict()
 tuned.cases["worker:0"].phase = "incapacitated"
 tuned.cases["worker:0"].left = FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS + 123.25
 var preserved: Dictionary = model.from_dict(tuned,a)
 check(preserved.get("ok",false), "older incapacitation remainder survives a lower current default")
 if preserved.get("ok",false):
  preserved.ledger.tick(0.25,a)
  check(preserved.ledger.case_for("worker:0").left == tuned.cases["worker:0"].left - 0.25, "restored long remainder decrements without retuning")
 var valid: Dictionary = ledger().to_dict()
 for flaw in ["schema_type","schema_future","null_cases","row_type","missing_field","extra_field","target_mismatch","missing_actor","phase","left_string","left_bool","nan","inf","negative","too_large","zero_wait","carrier_wait","assigned_empty","healthy_target","schema_extra"]:
  var bad: Dictionary = valid.duplicate(true)
  var actors := a.duplicate(true)
  var row: Dictionary = bad.cases["worker:0"]
  match flaw:
   "schema_type": bad.schema = "1"
   "schema_future": bad.schema = 2
   "null_cases": bad.cases = null
   "row_type": bad.cases["worker:0"] = []
   "missing_field": row.erase("left")
   "extra_field": row.reward = 1
   "target_mismatch": row.target = "worker:1"
   "missing_actor": actors.erase("worker:0")
   "phase": row.phase = "healthy"
   "left_string": row.left = "90"
   "left_bool": row.left = true
   "nan": row.left = NAN
   "inf": row.left = INF
   "negative": row.left = -1
   "too_large": row.left = 91
   "zero_wait": row.left = 0
   "carrier_wait": row.carrier = "worker:2"
   "assigned_empty": row.phase = "assigned"
   "healthy_target": actors["worker:0"].down = false
   "schema_extra": bad.reward = 1
  check(not model.from_dict(bad,actors).get("ok",false), "reject malformed snapshot: " + flaw)
 var l = ledger()
 l.observe_down("worker:1",a)
 l.assign("worker:0","worker:2",a)
 var duplicate: Dictionary = l.to_dict()
 duplicate.cases["worker:1"].phase = "assigned"
 duplicate.cases["worker:1"].carrier = "worker:2"
 check(not model.from_dict(duplicate,a).get("ok",false), "restore rejects duplicate carrier claims")
 duplicate.cases["worker:1"].carrier = "worker:0"
 check(not model.from_dict(duplicate,a).get("ok",false), "restore rejects target-as-carrier cycles")
func test_session(has_model: bool) -> void:
 SaveGame.disabled = true
 main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed",104729)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 main.director.enabled = false
 for worker in main.workers:
  worker.stop_work()
  for job in GameData.job_list(): worker.priorities[job] = 0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination), "real fixture route to " + destination)
  for step in 300:
   main._process(0.25)
   await process_frame
   if main.world.region == destination and main.world.phase == "stopped": break
 var made: Dictionary = Session.create_from_game(main,"rescue-contract")
 check(made.get("ok",false), "create C session through existing authority")
 if not made.get("ok",false): main.queue_free(); await process_frame; return
 var s = made.session
 var healthy: Dictionary = s.to_dict()
 check(healthy.schema == 11, "session uses versioned rescue, regeneration and independent encounter schema 11")
 check(healthy.has("rescue"), "session serializes its actor rescue ledger")
 if not has_model or not healthy.has("rescue"): main.queue_free(); await process_frame; return
 var ordinary_cases: Dictionary = main.operations.rescue_cases.duplicate(true)
 var stock: Dictionary = main.storage.inventory.counts.duplicate(true)
 var world: Dictionary = main.world.locations.duplicate(true)
 var first: String = s.actors.keys()[0]
 var clock = FieldSurvivalClock.new()
 check(clock.setup(main,s).get("ok",false), "existing field life clock binds this rescue session")
 s.actors[first].hp = 0.0
 clock.tick(0.25)
 var down_snapshot: Dictionary = s.to_dict()
 check(s.actors[first].down and s.rescue_ledger.case_for(first).phase == "waiting" and s.rescue_ledger.case_for(first).left == 90.0, "new down registers once without backdating frame time")
 clock.tick(2.5)
 check(s.rescue_ledger.case_for(first).left == 87.5 and s.life_clock_paid == s.elapsed, "bound life clock advances rescue once and pays normal life time")
 var before_pause: Dictionary = s.to_dict()
 paused = true
 clock.tick(10.0)
 paused = false
 check(s.to_dict() == before_pause, "actual tree pause freezes bound rescue and survival clock")
 var time_before: float = s.elapsed
 s.tick(50.0,true)
 check(s.elapsed == time_before and s.rescue_ledger.case_for(first).left == 87.5, "explicit session pause freezes world and rescue clock")
 var roundtrip: Dictionary = Session.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
 check(roundtrip.get("ok",false) and roundtrip.session.rescue_ledger.case_for(first).left == 87.5, "session roundtrip retains down-case remainder")
 s.request_recall()
 s.tick(700.0)
 check(s.rescue_ledger.case_for(first).is_empty() and not s.actors[first].down and s.actors[first].hp == CrewStatusDB.HP_REVIVE_AT and s.expired_recovery.owns(first), "session consumes expiry once into provisional physical self-return")
 check(s.phase != "ready_to_exit" and not s.commit_to_game(main).get("ok",false), "partial rescue cannot bypass safe return or commit")
 check(main.operations.rescue_cases == ordinary_cases and main.storage.inventory.counts == stock and main.world.locations == world, "model-only rescue does not double-tick normal ledger or commit stock/world")
 check(SaveGame.disabled and not SaveGame.write(main,"user://rescue-must-not-save.json",true), "C snapshot support never enables normal player save")
 for schema in [2,3,4,5,6,7,8]:
  var legacy: Dictionary = healthy.duplicate(true)
  legacy.schema = schema
  legacy.erase("rescue")
  check(Session.from_dict(legacy).get("ok",false), "healthy legacy snapshot migrates empty: " + str(schema))
 for schema in [8,9]:
  var inconsistent: Dictionary = healthy.duplicate(true)
  inconsistent.schema = schema
  if schema < 9: inconsistent.erase("rescue")
  inconsistent.actors[first].hp = 0.0
  inconsistent.actors[first].down = false
  check(not Session.from_dict(inconsistent).get("ok",false), "HP0 without down cannot restore a fresh deadline: " + str(schema))
 for flaw in ["hp_string","hp_nan","hp_negative","down_string"]:
  var malformed: Dictionary = healthy.duplicate(true)
  match flaw:
   "hp_string": malformed.actors[first].hp = "100"
   "hp_nan": malformed.actors[first].hp = NAN
   "hp_negative": malformed.actors[first].hp = -1
   "down_string": malformed.actors[first].down = "false"
  check(not Session.from_dict(malformed).get("ok",false), "strict actor rescue health boundary: " + flaw)
 var missing: Dictionary = down_snapshot.duplicate(true)
 missing.erase("rescue")
 check(not Session.from_dict(missing).get("ok",false), "current missing rescue data is refused")
 missing.schema = 8
 check(not Session.from_dict(missing).get("ok",false), "legacy down state cannot gain a fresh deadline")
 var uncovered: Dictionary = down_snapshot.duplicate(true)
 uncovered.rescue.cases.clear()
 check(not Session.from_dict(uncovered).get("ok",false), "every current down actor requires its own case")
 var bad: Dictionary = down_snapshot.duplicate(true)
 bad.rescue.cases[first].phase = "assigned"
 bad.rescue.cases[first].carrier = s.actors.keys()[1]
 check(not Session.from_dict(bad).get("ok",false), "session refuses model-only assignment without physical movement integration")
 var downgrade: Dictionary = healthy.duplicate(true)
 downgrade.schema = 8
 check(not Session.from_dict(downgrade).get("ok",false), "schema downgrade cannot smuggle a rescue ledger")
 main.queue_free()
 await process_frame
