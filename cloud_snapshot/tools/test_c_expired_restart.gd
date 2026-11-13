extends SceneTree
## Consumer: must follow test_c_expired_natural in the existing
## runner, in a separate official engine process sharing only isolated HOME.
const Session = preload("res://bridge/route_connection_session.gd")
const PATH := "user://c-expired-natural.json"
const RECEIPT := "user://c-expired-natural-receipt.json"
var main
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func isolated() -> bool:
 var home := OS.get_environment("FLUID_TEST_HOME").replace("\\", "/").simplify_path().trim_suffix("/")
 return not home.is_empty() and OS.get_user_data_dir().replace("\\", "/").simplify_path().begins_with(home + "/")
func run() -> void:
 if not isolated(): quit(2); return
 SaveGame.disabled = true
 paused = false
 check(FileAccess.file_exists(RECEIPT),"previous process produced provenance receipt")
 if not FileAccess.file_exists(RECEIPT): await finish(); return
 var receipt = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
 check(receipt is Dictionary,"restart provenance is readable")
 if not receipt is Dictionary: await finish(); return
 check(int(receipt.get("producer_pid",-1)) > 0 and int(receipt.get("producer_pid",-1)) != OS.get_process_id(),"consumer is a different engine process")
 var saved := SaveGame.read(PATH)
 check(not saved.is_empty() and FileAccess.get_sha256(PATH) == receipt.get("save_sha256",""),"consumer reads the exact previous-process save")
 if saved.is_empty(): await finish(); return
 main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed",104729)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 check(SaveGame.apply(main,saved),"fresh Main applies persisted post-expiry save")
 if failures: await finish(); return
 var restored := SaveGame.capture(main)
 for key in ["world","inventory","stock","operations","main","town","crew"]:
  check(restored[key] == saved[key],"restart preserves exact " + key)
 var worker = main.workers[0]
 check(main.workers.size() == int(receipt.person_count),"restart preserves person count")
 check(worker.hp == CrewStatusDB.HP_REVIVE_AT and not worker.down,"restart preserves post-expiry wake HP and conscious person")
 check(worker.carrying == -1 and worker.carry_bonus.is_empty() and worker.carcass_cargo.is_empty(),"restart does not recreate cargo in recovered hands")
 check(main.operations.rescue_cases.is_empty() and worker.ai.low_hp_retreat,"restart restores ordinary low-HP retreat without manual recovery owner")
 check(main.mine_arrival_gate.field == null,"restart has no live C adapter ownership")
 check(main.storage.inventory.count(int(receipt.item)) == int(receipt.stock) and main.world.locations[Session.SOURCE_KEY][str(receipt.source_id)].data.remaining == int(receipt.remaining),"restart retains exact cargo/source conservation")
 check(main.world.outpost_states == saved.world.outpost_states,"restart preserves unchanged outpost state")
 check(SaveGame.apply(main,saved),"same file may be loaded again")
 var twice := SaveGame.capture(main)
 for key in ["world","inventory","operations","main","town","crew"]:
  check(twice[key] == restored[key],"repeated load cannot replay " + key)
 worker = main.workers[0]
 var initial_hp:=float(worker.hp)
 # Exercise actual ordinary low-HP AI and rest; no HP/position injection.
 for unused in 6000:
  worker.ai.tick(0.1)
  CrewStatus._tick_hp(worker,0.1)
  if worker.hp>initial_hp:break
 check(worker.hp>initial_hp and not worker.down,"existing low-HP retreat reaches natural rest healing")
 check(main.operations.rescue_cases.is_empty(),"ordinary rest never invents manual rescue recovering")
 check(main.world.locations == saved.world.locations and main.world.outpost_states == saved.world.outpost_states and main.storage.inventory.counts == saved.inventory and main.total_gathered == saved.main.total_gathered and main.town.credits == int(saved.town.credits),"rest cannot replay source, cargo, enemy state or rewards")
 check(FileAccess.get_sha256(PATH) == receipt.save_sha256,"load and recovery never rewrite producer save")
 await finish()
func finish() -> void:
 SaveGame.disabled = true
 if main != null and is_instance_valid(main): main.queue_free()
 await process_frame
 print("C EXPIRED RESTART assertions=",assertions," failures=",failures)
 quit(0 if failures == 0 else 1)
