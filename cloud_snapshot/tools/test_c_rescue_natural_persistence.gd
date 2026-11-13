extends SceneTree
## Producer for test_c_rescue_natural_restart. Run consecutively through the
## existing runner: separate engines, shared runner-owned isolated user home.
## Natural mining/escort movement. Only down is injected; not combat or OS-input proof.
const Session = preload("res://bridge/route_connection_session.gd")
const PATH := "user://c-rescue-natural.json"
const RECEIPT := "user://c-rescue-natural-receipt.json"
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
 check(gate.enter_mine(),"actual default gate creates ordinary mine field")
 if gate.field == null: await finish(); return
 var adapter = gate.field
 adapter.process_mode = Node.PROCESS_MODE_DISABLED
 var s = adapter.session
 var clock = adapter.life_clock
 check(SaveGame.disabled and clock.is_current(),"field owns save restriction and live clock")
 check(s.mine_path_engineering and not s.outpost_enabled,"ordinary mine geometry, not outpost override")
 var source_before: Dictionary = main.world.locations.duplicate(true)
 var enemies_before: Dictionary = main.world.outpost_states.duplicate(true)
 var rewards_before := int(main.total_gathered)
 var credits_before := int(main.town.credits)
 var person_count := int(main.workers.size())
 var stock_before_all: Dictionary = main.storage.inventory.counts.duplicate(true)
 var resources_before: Dictionary = s.resources.duplicate(true)
 var escort_start := Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)
 check(advance(clock,func(): return int(s.actors["worker:0"].carry_n)>0,60.0),"natural harvest obtains real finite-source cargo")
 var target: Dictionary = s.actors["worker:0"]
 var cargo := int(target.carry_n)
 var item := int(target.carry_item)
 var resource_id := ""
 for id in resources_before:
  if int(resources_before[id].remaining)-int(s.resources[id].remaining)==cargo and int(s.resources[id].item)==item:
   resource_id=str(id)
   break
 check(cargo>0 and resources_before.has(resource_id),"natural cargo has a real source")
 if failures: await finish(); return
 var original_remaining := int(resources_before[resource_id].remaining)
 var stock_before := int(stock_before_all.get(item,0))
 check(s.actors["worker:2"].state=="escort" and Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)!=escort_start,"escort naturally followed without state or position reset")
 var target_position := Vector2(target.x,target.y)
 s._begin_outpost_down("worker:0",target)
 check(Vector2(target.x,target.y)==target_position and target.carry_n==cargo,"only down is injected, position and natural cargo unchanged")
 check(s.conservation_ok(),"natural harvest and down preserve finite-source conservation")
 check(s.request_rescue("worker:0","worker:2",s.session_id).get("ok",false),"natural moving escort rescue assignment accepted")
 s.request_recall()
 check(advance(clock,func(): return s.rescue_ledger.case_for("worker:0").get("phase") == "carried",60.0),"real approach reaches pickup and hold")
 check(s.actors["worker:0"].down and s.actors["worker:0"].hp == 0.0 and s.actors["worker:0"].carry_n == cargo,"held person remains down with original cargo")
 check(s.request_rescue_return("worker:0",s.session_id).get("ok",false),"explicit transport accepted")
 check(advance(clock,func(): return s.actors["worker:0"].state == "rescue_treatment",60.0),"real entrance transport reaches treatment")
 check(Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y) == Session.BASE and s.actors["worker:0"].hp == CrewStatusDB.HP_REVIVE_AT,"first aid occurs at exact entrance at existing threshold")
 check(main.operations.rescue_cases.is_empty() and main.world.locations == source_before and main.storage.inventory.count(item) == stock_before,"pending treatment has not committed normal authority")
 check(not Session.from_dict(s.to_dict()).get("ok",false),"pending treatment snapshot remains unsupported")
 check(SaveGame.disabled and not SaveGame.write(main,FORBIDDEN,true) and not FileAccess.file_exists(FORBIDDEN),"pending treatment player save remains prohibited")
 check(advance(clock,func(): return s.phase == "ready_to_exit",60.0),"real timed dock and recall reach safe exit")
 check(s.depot_stock.get(item,0) == cargo and s.actors["worker:0"].carry_n == 0 and s.conservation_ok(),"natural cargo docks once with empty rescue hands")
 if failures: await finish(); return
 adapter._commit_and_exit()
 # Gate enables normal processing on exit. Disable before yielding so this
 # snapshot tests the precise handoff rather than an uncontrolled recovery frame.
 main.process_mode = Node.PROCESS_MODE_DISABLED
 check(s.committed and gate.field == null and not SaveGame.disabled,"actual safe commit ends field ownership and restores normal save policy")
 await process_frame
 var worker = main.workers[0]
 check(not is_instance_valid(adapter),"field adapter is destroyed before manual save")
 check(main.workers.size() == person_count and worker.hp == CrewStatusDB.HP_REVIVE_AT and not worker.down,"handoff preserves person count and first-aid HP")
 check(worker.carrying == -1 and worker.carry_bonus.is_empty() and worker.carcass_cargo.is_empty(),"handoff leaves rescued person empty-handed")
 check(main.operations.rescue_phase_for(worker) == "recovering" and worker.ai.state == CharacterAI.State.RESCUE_RECOVER and main.operations.rescue_case_for(worker).resume_return,"normal recovering contract preserves waiting instruction")
 check(worker.position == main.storage.access_point() + worker.slot_offset and worker.target == worker.position,"adapter restores treatment position and target")
 check(main.storage.inventory.count(item) == stock_before + cargo and main.world.locations[Session.SOURCE_KEY][resource_id].data.remaining == original_remaining - cargo,"commit transfers exactly natural finite-source cargo")
 check(main.world.outpost_states == enemies_before,"normal mine does not create or clear outpost enemies")
 check(main.total_gathered == rewards_before and main.town.credits == credits_before,"rescue transfer invents no gathering reward or credits")
 var after := SaveGame.capture(main)
 check(s.commit_to_game(main).get("already_committed",false) and SaveGame.capture(main) == after,"repeated safe commit cannot replay cargo, enemies or treatment")
 check(not Session.create_from_game(main,"treatment-reentry",{}).get("ok",false),"normal treatment prevents fresh field ownership")
 if failures: await finish(); return
 check(SaveGame.write(main,PATH,true),"real manual save writes only after field release")
 var saved := SaveGame.read(PATH)
 check(not saved.is_empty() and saved == after,"written save round-trips exact committed state")
 if failures == 0:
  var receipt := FileAccess.open(RECEIPT,FileAccess.WRITE)
  check(receipt != null,"create isolated restart provenance receipt")
  if receipt != null:
   receipt.store_string(JSON.stringify({"producer_pid":OS.get_process_id(),"save_sha256":FileAccess.get_sha256(PATH),"person_count":person_count,"source_id":resource_id,"item":item,"remaining":original_remaining-cargo,"stock":stock_before+cargo}))
   receipt.flush()
   check(receipt.get_error() == OK,"flush isolated restart provenance receipt")
   receipt.close()
 await finish()
func finish() -> void:
 SaveGame.disabled = true
 if main != null and is_instance_valid(main): main.queue_free()
 await process_frame
 print("C RESCUE NATURAL PERSISTENCE assertions=",assertions," failures=",failures)
 quit(0 if failures == 0 else 1)
