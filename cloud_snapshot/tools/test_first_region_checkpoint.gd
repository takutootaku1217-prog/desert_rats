extends SceneTree
## Real files only within the runner-owned isolated user directory.
var main
var failures := 0
const CP := "user://first-region-a-pilot-checkpoint.json"
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
 print("  %s %s" % ["ok" if ok else "FAIL",message])
 if not ok: failures+=1
func fresh() -> void:
 paused=false
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",261108)
 root.add_child(main)
 await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 main.director.enabled=false
 for worker in main.workers:
  worker.stop_work()
  for job in GameData.job_list(): worker.priorities[job]=0
 SaveGame.disabled=false
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="":
  push_error("Isolated FLUID_TEST_HOME required")
  quit(2);return
 await fresh()
 check(main.world.ready_reason()=="","fresh A is safe for checkpoint")
 check(SaveGame.validate(SaveGame.capture(main),main),"fresh snapshot validates")
 main.town.credits=123
 check(SaveGame.write(main,main.save_ui.path,true),"manual save fixture uses real atomic writer")
 var manual_hash:=FileAccess.get_sha256(main.save_ui.path)
 var desert=FileAccess.open(SaveGame.CHECKPOINT_PATH,FileAccess.WRITE)
 desert.store_string("unrelated desert checkpoint sentinel");desert.close()
 var desert_hash:=FileAccess.get_sha256(SaveGame.CHECKPOINT_PATH)
 check(main.world.request("b_forest"),"safe A departure accepted")
 check(SaveGame.exists(CP),"A departure creates first-region checkpoint")
 check(FileAccess.get_sha256(main.save_ui.path)==manual_hash,"manual save unchanged")
 check(FileAccess.get_sha256(SaveGame.CHECKPOINT_PATH)==desert_hash,"desert checkpoint unchanged")
 var saved:=SaveGame.read(CP)
 check(not saved.is_empty() and saved.world.region=="a_start" and saved.world.phase=="stopped","snapshot precedes departure")
 if saved.is_empty():
  check(SaveGame.apply(main,SaveGame.read(main.save_ui.path)),"fallback retry fixture restores valid manual snapshot")
  check(SaveGame.write(main,CP,true),"fallback writes real checkpoint to test recovery independently")
  saved=SaveGame.read(CP)
 if not saved.is_empty():
  check(saved.world.map_profile==WorldMapDB.FIRST_REGION_A,"checkpoint stores matching profile")
  main.game_over=true
  main.save_ui.open_failed_field("checkpoint regression defeat",false)
  main.save_ui.ask("checkpoint")
  check(main.save_ui._action=="checkpoint","defeat screen allows checkpoint confirmation")
  main.save_ui.execute()
  check(not main.game_over and not main.save_ui._field_failure_lock and not SaveGame.disabled,"successful retry releases failure locks")
  check(main.world.region=="a_start" and main.world.phase=="stopped" and main.town.credits==111,"retry restores A and applies existing ten-percent fee once")
  check(SaveGame.restore_checkpoint(main,CP) and main.town.credits==111,"same frozen checkpoint fee never compounds")
  main.save_ui.close();paused=false
  # Reset failed baseline UI fixture so disk and safety checks are independent.
  main.save_ui._release_failed_field();main.game_over=false;SaveGame.disabled=false
  SaveGame.apply(main,saved)
 else:
  main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination=""
 var before:Dictionary=SaveGame.capture(main)
 main.workers[0].floor_i=0
 check(main.world.request("b_forest"),"A request preserves existing departing-and-recall behavior for outside worker")
 main.workers[0].floor_i=int(before.crew[0].worker.floor_i)
 main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination=""
 var cp_hash:=FileAccess.get_sha256(CP) if SaveGame.exists(CP) else ""
 DirAccess.make_dir_absolute(CP+".tmp")
 var state:Dictionary=SaveGame.capture(main)
 check(not main.world.request("b_forest"),"checkpoint disk failure blocks departure")
 check(main.world.phase=="stopped","disk failure leaves route stopped")
 check(SaveGame.last_error!="","disk failure is explained")
 check((FileAccess.get_sha256(CP) if SaveGame.exists(CP) else "")==cp_hash,"disk failure preserves previous checkpoint")
 main.map_ui.open()
 main.map_ui._target="b_forest";main.map_ui._path=["b_forest"];main.map_ui._reserved=[]
 main.map_ui._go()
 check(main.map_ui._info.text.contains("checkpoint") and main.map_ui._info.text.contains("出発しません"),"new-route save failure is visible in map")
 main.journey.remaining=["b_forest"]
 main.map_ui._resume.emit_signal("pressed")
 check(main.map_ui._info.text.contains("checkpoint") and main.map_ui._info.text.contains("出発しません"),"resume save failure is visible in map")
 main.map_ui._path=["not-a-region"]
 main.map_ui._go()
 check(not main.map_ui._info.text.contains("checkpointを作成できない"),"invalid next attempt does not show stale save error")
 main.map_ui.close();paused=false
 DirAccess.remove_absolute(CP+".tmp")
 main.save_ui.checkpoint_path="user://checkpoint-override.json"
 check(SaveGame.write_checkpoint(main) and SaveGame.exists(main.save_ui.checkpoint_path),"checkpoint writer follows the same explicit UI path")
 main.save_ui.checkpoint_path=main.save_ui.path
 check(not SaveGame.write_checkpoint(main),"checkpoint may not alias manual save")
 main.save_ui.checkpoint_path=CP
 var original_manual:String=main.save_ui.path
 for protected in [SaveGame.PATH,SaveGame.CHECKPOINT_PATH+".bak",SaveGame.CHECKPOINT_PATH+".tmp"]:
  var sentinel=FileAccess.open(protected,FileAccess.WRITE);sentinel.store_string("protected slot sentinel");sentinel.close()
  var protected_hash:=FileAccess.get_sha256(protected)
  main.save_ui.checkpoint_path=protected
  check(not SaveGame.write_checkpoint(main),"reject protected save namespace "+protected)
  check(FileAccess.get_sha256(protected)==protected_hash,"protected namespace content unchanged")
 var reverse_path:="user://checkpoint-reverse-alias.json"
 main.save_ui.checkpoint_path=reverse_path
 check(SaveGame.write(main,reverse_path,true),"prepare reverse-alias checkpoint fixture")
 main.save_ui.path=reverse_path+".bak"
 var reverse_file=FileAccess.open(main.save_ui.path,FileAccess.WRITE);reverse_file.store_string("manual reverse alias sentinel");reverse_file.close()
 var reverse_hash:=FileAccess.get_sha256(main.save_ui.path)
 check(not SaveGame.write_checkpoint(main),"checkpoint backup cannot overlap manual path")
 check(FileAccess.get_sha256(main.save_ui.path)==reverse_hash,"reverse-alias manual preserved")
 main.save_ui.path=original_manual;main.save_ui.checkpoint_path=CP
 var field=Node.new();root.add_child(field);main.mine_arrival_gate.field=field
 SaveGame.disabled=true
 check(not main.world.request("b_forest"),"active field blocks request even while saving is disabled")
 main.mine_arrival_gate.field=null;field.queue_free();SaveGame.disabled=false
 main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination=""
 main.journey.clear()
 # Explicit persistence fixture, not a claim these improvements were earned.
 main.world.region_state.roads.ab.graded=true
 main.world.region_state.roads.bd.cleared=true
 main.world.region_state.lots.b_forest="supply"
 main.world.site_stores.b_forest={GameData.Item.WOOD:2}
 main.world.set_c_quarry_cart_shortcut_cleared(true)
 check(SaveGame.write_checkpoint(main),"leave real first-region checkpoint for next-process reader")
 var checkpoint_bytes:=FileAccess.get_file_as_bytes(CP)
 main.world.map_profile=WorldMapDB.DESERT
 main.game_over=true;main.save_ui.open_failed_field("wrong-profile fixture",false)
 main.save_ui.ask("checkpoint")
 check(main.save_ui._action=="","wrong-profile checkpoint is rejected before confirmation")
 check(not SaveGame.restore_checkpoint(main,CP) and main.world.map_profile==WorldMapDB.DESERT,"wrong-profile execution leaves gameplay untouched")
 check(main.save_ui._field_failure_lock and main.game_over and SaveGame.disabled and paused,"failed retry retains pause and failure locks")
 main.world.map_profile=WorldMapDB.FIRST_REGION_A
 main.save_ui._action=""
 var corrupt=FileAccess.open(CP,FileAccess.WRITE);corrupt.store_string("broken checkpoint");corrupt.close()
 main.save_ui.ask("checkpoint")
 check(main.save_ui._action=="" and main.save_ui._field_failure_lock,"corrupt checkpoint cannot escape failure lock")
 var restored_file=FileAccess.open(CP,FileAccess.WRITE);restored_file.store_buffer(checkpoint_bytes);restored_file.close()
 main.save_ui._release_failed_field();main.game_over=false;main.save_ui.close();paused=false
 check(FileAccess.get_sha256(main.save_ui.path)==manual_hash,"all retry work preserves manual save")
 SaveGame.disabled=true
 main.queue_free();await process_frame
 print("FIRST REGION CHECKPOINT failures=",failures)
 quit(0 if failures==0 else 1)
