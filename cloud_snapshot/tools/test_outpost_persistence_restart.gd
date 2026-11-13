extends SceneTree
const Session=preload("res://bridge/route_connection_session.gd")
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 var main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var saved:=SaveGame.read("user://outpost-persistence.json")
 check(not saved.is_empty() and SaveGame.apply(main,saved),"new process loads previous-process committed save")
 if not saved.is_empty():
  var stock:Dictionary=main.storage.inventory.counts.duplicate(true)
  var source:Dictionary=main.world.locations.duplicate(true)
  var made:Dictionary=Session.create_from_game(main,"restart-revisit",{"outpost_enabled":true})
  check(made.get("ok",false) and made.session.outpost_cleared and made.session.outpost_remaining()==0,"new-process revisit retains defeated guards")
  check(main.world.locations==source and main.storage.inventory.counts==stock,"restart revisit preserves finite sources and cargo")
 var partial:=SaveGame.read("user://outpost-partial.json")
 check(not partial.is_empty() and SaveGame.apply(main,partial),"new process loads partial-return save")
 if not partial.is_empty():
  var again:Dictionary=Session.create_from_game(main,"partial-restart",{"outpost_enabled":true})
  check(again.get("ok",false) and not again.session.outpost_cleared and again.session.outpost_enemies==partial.world.outpost_states.c_quarry.enemies,"new-process partial revisit retains full enemy state")
 main.queue_free();await process_frame
 print("OUTPOST RESTART failures=",failures);quit(0 if failures==0 else 1)
