extends SceneTree
const PATH:="user://region-boss-field.json"
const RECEIPT:="user://region-boss-receipt.json"
var main
var assertions:=0
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1
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
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"normal route "+destination)
  for unused in 300:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
 var gate=main.mine_arrival_gate;gate._process(0.0)
 var ordinary_before:=SaveGame.capture(main)
 SaveGame.disabled=false
 check(gate.enter_mine(),"ordinary entry remains separate")
 var old:Dictionary=SaveGame.capture(main)
 old.field_snapshot.session.schema=10
 old.field_snapshot.session.erase("encounter_id");old.field_snapshot.session.erase("encounter_entry")
 check(SaveGame.validate(old,main) and SaveGame.apply(main,old),"authentic previous schema10 complete save migrates with no boss")
 check(gate.field.session.encounter_id=="" and not gate.field.session.outpost_enabled,"legacy ordinary field never acquires a boss")
 check(SaveGame.apply(main,ordinary_before),"restore ordinary Main before separate boss entry")
 main.process_mode=Node.PROCESS_MODE_DISABLED
 if paused:paused=false
 gate._dismissed_here=false;gate._process(0.0)
 check(gate.enter_boss(),"real boss gate enters")
 if gate.field==null:await finish();return
 var adapter=gate.field;adapter.process_mode=Node.PROCESS_MODE_DISABLED
 var s=adapter.session
 check(SaveGame.validate(SaveGame.capture(main),main),"boss entrance complete snapshot validates")
 if failures:await finish();return
 var moving_checked:=false
 for unused in 1000:
  adapter.life_clock.tick(0.05)
  if s.actors["worker:2"].state=="outpost_move" and not s.actors["worker:2"].path.is_empty() and not moving_checked:
   moving_checked=true
   var moving:=SaveGame.capture(main)
   check(SaveGame.validate(moving,main),"moving combat path has bounded provenance")
   var forged:=moving.duplicate(true)
   var actor:Dictionary=forged.field_snapshot.session.actors["worker:2"]
   var plan:Dictionary=forged.field_snapshot.plans["worker:2"]
   actor.path[-1]=[9000.0,9000.0];plan.path=actor.path.duplicate(true);plan.combat_destination=Vector2(9000,9000)
   check(not SaveGame.validate(forged,main),"matching forged combat endpoint cannot escape the bounded boss territory")
  if s.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp<72.0:break
 check(moving_checked,"test observed natural combat approach")
 check(s.actors["worker:2"].state=="combat" and not s.outpost_cleared,"natural live combat, not injected victory")
 var snapshot:=SaveGame.capture(main)
 check(SaveGame.validate(snapshot,main),"live boss/actor combat owners validate")
 var stable:=snapshot.duplicate(true)
 for flaw in ["unknown_encounter","missing_boss","false_victory","wrong_engager","wrong_target","extra_enemy","hp","entry","ordinary_combat","actor_target"]:
  var bad:=snapshot.duplicate(true);var f:Dictionary=bad.field_snapshot.session
  match flaw:
   "unknown_encounter":f.encounter_id="outpost"
   "missing_boss":f.outpost_enemies.clear()
   "false_victory":f.outpost_cleared=true
   "wrong_engager":f.outpost_enemies[FirstRegionCompletion.BOSS_ID].engager="worker:0"
   "wrong_target":f.outpost_enemies[FirstRegionCompletion.BOSS_ID].target="worker:999"
   "extra_enemy":f.outpost_enemies["outpost:front"]=f.outpost_enemies[FirstRegionCompletion.BOSS_ID].duplicate(true)
   "hp":f.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp=NAN
   "entry":f.encounter_entry={"cleared":true}
   "ordinary_combat":f.encounter_id=""
   "actor_target":f.actors["worker:2"].combat_target="missing"
  var old_adapter=gate.field;var old_clock=old_adapter.life_clock
  check(not SaveGame.apply(main,bad),"reject invalid combat bundle: "+flaw)
  check(gate.field==old_adapter and old_clock.is_current() and SaveGame.capture(main)==stable,"invalid bundle leaves owner/clock/world unchanged: "+flaw)
 check(SaveGame.write_field(main,PATH,true),"real atomic file captures mid-combat")
 check(SaveGame.read(PATH)==snapshot,"file preserves exact enemy HP and targets")
 var receipt=FileAccess.open(RECEIPT,FileAccess.WRITE)
 receipt.store_string(JSON.stringify({"pid":OS.get_process_id(),"hash":FileAccess.get_sha256(PATH),"hp":s.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp}));receipt.close()
 var old_clock=adapter.life_clock
 check(SaveGame.apply(main,snapshot),"same-process load replaces all field/combat owners")
 check(not old_clock.is_current() and gate.field!=adapter and paused,"old runtime invalidated and restored field paused")
 check(gate.field.session.outpost_enemies==snapshot.field_snapshot.session.outpost_enemies,"restore preserves exact single boss")
 await finish()
func finish()->void:
 SaveGame.disabled=true
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("REGION BOSS SNAPSHOT assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
