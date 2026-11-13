extends SceneTree
## Consumer of the real-file producer in c_low_hp_retreat_owners.
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 SaveGame.disabled=true
 var main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame;main.process_mode=Node.PROCESS_MODE_DISABLED
 var saved:=SaveGame.read("user://low-hp-target-return.json")
 check(not saved.is_empty(),"separate process reads producer file")
 if not saved.is_empty():
  check(SaveGame.validate(saved,main) and SaveGame.apply(main,saved),"independent process restores targeted nonescort return")
  var field=main.mine_arrival_gate.field
  if field!=null:
   field.process_mode=Node.PROCESS_MODE_DISABLED;var s=field.session
   check(paused and s.rescue_approach.has_mine_return("worker:0"),"load is paused with exact return ownership")
   check(s.outpost_enemies[FirstRegionCompletion.BOSS_ID].target=="worker:0","same enemy target survives process boundary")
   paused=false;s.request_recall()
   for unused in 800:
    if s.actors["worker:0"].state=="idle":break
    field.life_clock.tick(0.05)
   check(s.actors["worker:0"].state=="idle" and Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)==s.BASE,"restored rescuer reaches actual safe entrance")
   check(not s.rescue_approach.owns("worker:0") and s.actors["worker:2"].down,"return releases owner without healing or teleporting dropped body")
 main.queue_free();await process_frame;SaveGame.disabled=true
 print("C LOW HP RESTART failures=",failures);quit(0 if failures==0 else 1)
