extends SceneTree
## Consumer runs in a separate Godot process in the runner's shared isolated home.
var failures:=0
func _init() -> void:call_deferred("_run")
func check(ok:bool,label:String) -> void:
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func _run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 SaveGame.disabled=true
 var main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame;main.process_mode=Node.PROCESS_MODE_DISABLED
 var saved:=SaveGame.read("user://fuel-depot-ui.json")
 check(not saved.is_empty() and SaveGame.apply(main,saved),"separate PID loads fuel-depot file")
 if not saved.is_empty():
  var fuel:=GameData.Item.FUEL
  check(main.storage.count_of(fuel)==1 and main.world.site_store("b_forest")=={fuel:1} and main.world.site_store("d_yard")=={fuel:1},"warehouse and both depot quantities survive")
  var tank:float=main.base.fuel
  for repeat in range(2):
   main.map_ui.open();main.map_ui.close()
   check(SaveGame.apply(main,saved),"repeated read remains valid")
  check(main.storage.count_of(fuel)==1 and main.base.fuel==tank and main.base.total_refuel==0,"load and map viewing never withdraw or refuel")
  for site in ["b_forest","d_yard"]:
   main.world.region=site
   check(main.world.withdraw_from_site(fuel,1)==1 and main.world.withdraw_from_site(fuel,1)==0,"remaining "+site+" fuel can be withdrawn only once")
  check(main.storage.count_of(fuel)==3 and main.base.fuel==tank,"all three items conserved after separate-process re-visits")
 main.queue_free();await process_frame;SaveGame.disabled=false
 print("FUEL DEPOT RESTART failures=",failures);quit(1 if failures else 0)
