extends SceneTree
const PATH := "user://c-field-snapshot.json"
const RECEIPT := "user://c-field-snapshot-receipt.json"
var main
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func advance(clock, predicate: Callable, seconds: float) -> bool:
 for unused in ceili(seconds/0.05):
  if predicate.call(): return true
  clock.tick(0.05)
 return predicate.call()
func run() -> void:
 var home := OS.get_environment("FLUID_TEST_HOME").replace("\\","/").simplify_path().trim_suffix("/")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").simplify_path().begins_with(home+"/"): quit(2); return
 SaveGame.disabled = true
 main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed",104729)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 SaveGame.disabled = false # Player policy after isolated startup preparation.
 var saved = SaveGame.read(PATH)
 check(not saved.is_empty(),"read real prior-process file")
 var receipt = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
 check(receipt is Dictionary and int(receipt.pid) != OS.get_process_id(),"independent producer and consumer PIDs")
 check(receipt.hash == FileAccess.get_sha256(PATH),"exact producer file hash")
 if failures: await finish(); return
 check(SaveGame.apply(main,saved),"fresh Main restores complete field")
 var gate = main.mine_arrival_gate
 check(gate.field != null and paused,"fresh runtime starts in paused field")
 if failures: await finish(); return
 var field = gate.field
 field.process_mode = Node.PROCESS_MODE_DISABLED
 var s = field.session
 var clock = field.life_clock
 check(s.rescue_ledger.to_dict() == saved.field_snapshot.session.rescue,"fresh process preserves residual rescue clock")
 check(s.life_clock_token != saved.field_snapshot.session.life_clock_token and clock.is_current(),"fresh process rebinds new clock token")
 var before: Dictionary = s.to_dict()
 clock.tick(1.0)
 check(s.to_dict() == before,"paused load does not advance survival or rescue")
 for id in saved.field_snapshot.traces:
  check(s.mine_rescue_traces._rows[id].points == saved.field_snapshot.traces[id].points,"exact trace vertices restored for "+id)
 var stale_clock = clock
 var stale_session = s
 var first_token = s.life_clock_token
 check(SaveGame.apply(main,saved),"same file can be loaded twice without accumulation")
 field = gate.field
 field.process_mode = Node.PROCESS_MODE_DISABLED
 s = field.session
 clock = field.life_clock
 check(clock.is_current() and not stale_clock.is_current() and s.life_clock_token != first_token,"second load retires previous generation")
 check(not stale_session.commit_to_game(main).get("ok",false),"old session cannot commit after replacement")
 check(main.storage.inventory.counts == saved.inventory and main.world.locations == saved.world.locations and s.depot_stock == saved.field_snapshot.session.depot_stock,"second load does not duplicate stocks or sources")
 check(FileAccess.get_sha256(PATH) == receipt.hash,"loads never rewrite original file")
 var old_stock = main.storage.inventory.counts.duplicate(true)
 var bad = saved.duplicate(true)
 bad.field_snapshot.session.actors["worker:0"].worker_index = 999
 check(not SaveGame.apply(main,bad),"malformed cross-reference refused")
 check(gate.field == field and clock.is_current() and main.storage.inventory.counts == old_stock,"invalid file leaves current owner and resources untouched")
 field._toggle_field_pause()
 check(not paused,"field resume button releases loaded pause")
 paused = false # Continue remaining diagnostics after recording a failed UI assertion.
 var paid_before: float = s.elapsed
 var director_before: float = main.director.elapsed
 var left_before: float = s.rescue_ledger.case_for("worker:0").left
 stale_clock.tick(2.0)
 check(s.elapsed == paid_before and main.director.elapsed == director_before,"retired clock cannot charge current runtime")
 clock.tick(0.25)
 check(is_equal_approx(s.elapsed,paid_before+0.25) and is_equal_approx(s.life_clock_paid,s.elapsed) and is_equal_approx(main.director.elapsed,director_before+0.25) and is_equal_approx(s.rescue_ledger.case_for("worker:0").left,left_before-0.25),"only new delta pays survival and rescue once")
 check(s.request_rescue("worker:0","worker:2",s.session_id).get("ok",false),"resumed natural escort can request physical rescue")
 s.request_recall()
 check(advance(clock,func(): return s.rescue_ledger.case_for("worker:0").get("phase") == "carried",60.0),"restored trail supports approach and pickup")
 check(s.request_rescue_return("worker:0",s.session_id).get("ok",false),"explicit return after restart")
 check(advance(clock,func(): return s.phase == "ready_to_exit",90.0),"normal return dock and treatment reach safe exit")
 if failures: await finish(); return
 field._commit_and_exit()
 main.process_mode = Node.PROCESS_MODE_DISABLED
 check(s.committed and gate.field == null,"normal safe commit releases field once")
 check(main.operations.stance == "alert","restored pending-entry stance returns after field commit")
 var committed = SaveGame.capture(main)
 check(s.commit_to_game(main).get("already_committed",false) and SaveGame.capture(main) == committed,"duplicate commit changes no people cargo or stock")
 await process_frame
 check(SaveGame.write(main,"user://c-field-restarted-committed.json",true),"ordinary manual save after resumed rescue")
 var worker = main.workers[0]
 for unused in 3000:
  worker.ai.tick(0.1)
  CrewStatus._tick_hp(worker,0.1)
  if main.operations.rescue_case_for(worker).is_empty(): break
 check(main.operations.rescue_case_for(worker).is_empty(),"existing healing releases treatment owner")
 # Simulate the gate's revisit eligibility, not a new session or clock.
 gate._dismissed_here = false
 gate._process(0.0)
 check(gate.enter_mine(),"next ordinary sortie opens after revisit eligibility")
 if gate.field != null:
  check(gate.field.life_clock.is_current() and gate.field.session.session_id != s.session_id,"next sortie receives unique live session identity")
 await finish()
func finish() -> void:
 SaveGame.disabled = true
 if main != null and is_instance_valid(main): main.queue_free()
 await process_frame
 print("C FIELD SNAPSHOT RESTART assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
