extends SceneTree
## Real A departure, C entry and field-failure transition. Failure is explicitly injected.
var main
var failures:=0
const STEP:=0.25
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 SaveGame.disabled=false
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"actual departure to "+destination)
  for tick in range(300):
   main._process(STEP);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
  check(main.world.region==destination and main.world.phase=="stopped","actual arrival at "+destination)
 var path:String=main.save_ui.checkpoint_path
 var saved:=SaveGame.read(path)
 check(not saved.is_empty() and saved.world.region=="a_start","non-A departure preserves A retry point")
 var gate=main.mine_arrival_gate
 check(gate.enter_mine(true),"real dangerous field entry accepted")
 for tick in range(120):
  main._process(STEP);gate._process(STEP);await process_frame
  if gate.field!=null:break
 check(gate.field!=null and SaveGame.disabled,"active field locks ordinary saving")
 if gate.field!=null:
  var session = gate.field.session
  session.actors["worker:2"].hp = 0.0
  session.tick(STEP)
  gate._process(STEP)
  check(gate._field_failure_button.visible, "HP0 failure escape is available before rescue deadline")
  session.tick(FieldOperations.RESCUE_SECONDS + FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
  gate._process(STEP)
  check(session.rescue_ledger.case_for("worker:2").is_empty() and session.expired_recovery.owns("worker:2") and gate._field_failure_button.visible, "both deadlines retain the same immediate failure/checkpoint escape")
  check(not session.actors["worker:2"].down and session.actors["worker:2"].hp == CrewStatusDB.HP_REVIVE_AT and not session.commit_to_game(main).get("ok",false), "post-expiry self-return never grants unsafe commit")
  check(gate.fail_field_to_menu("明示的なcheckpoint回帰用の現地失敗"),"real field failure transitions to retry menu without commit")
  main.save_ui.ask("checkpoint");main.save_ui.execute();await process_frame
  check(not main.game_over and not main.save_ui._field_failure_lock and not SaveGame.disabled,"checkpoint recovery releases real field failure")
  check(main.world.region=="a_start" and main.world.phase=="stopped","real field failure returns to safe A")
  check(main.storage.inventory.counts==saved.inventory,"failed field grants no extra recovered resources")
  main.save_ui.close();check(not paused,"successful field retry can resume play")
 SaveGame.disabled=true;main.queue_free();await process_frame
 print("FIRST REGION FIELD CHECKPOINT failures=",failures)
 quit(0 if failures==0 else 1)
