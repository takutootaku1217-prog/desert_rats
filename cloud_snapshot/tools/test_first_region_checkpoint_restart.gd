extends SceneTree
## Must follow test_first_region_checkpoint in a separate process with same isolated HOME.
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 var main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",261108);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 SaveGame.disabled=false
 var path:String=main.save_ui.checkpoint_path
 var saved:=SaveGame.read(path)
 check(not saved.is_empty(),"fresh process reads previous-process checkpoint")
 if not saved.is_empty():
  var h:=FileAccess.get_sha256(path)
  main.game_over=true;main.save_ui.open();main.save_ui.ask("checkpoint");main.save_ui.execute()
  check(not main.game_over,"normal game-over recovery clears terminal state")
  var restored:=SaveGame.capture(main)
  for key in ["world","inventory","stock","crew","base"]:
   check(restored[key]==saved[key],"restart restores exact "+key)
  check(main.town.credits==int(saved.town.credits)-SaveGame.checkpoint_loss(int(saved.town.credits)),"restart uses frozen fee basis")
  check(FileAccess.get_sha256(path)==h,"restoration never rewrites retry point")
  main.save_ui.close();paused=false
  check(main.world.request("d_yard"),"restored A can depart again via other route")
 SaveGame.disabled=true;main.queue_free();await process_frame
 print("FIRST REGION CHECKPOINT RESTART failures=",failures)
 quit(0 if failures==0 else 1)
