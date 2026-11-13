extends SceneTree
const Guide=preload("res://ui/first_loop_guide.gd")
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
 check(main.world.has_method("region_goal_snapshot"),"first region has an independent saved completion goal")
 if not main.world.has_method("region_goal_snapshot"):await finish();return
 var before:=SaveGame.capture(main)
 var goal:Dictionary=main.world.call("region_goal_snapshot")
 check(not goal.boss_returned and not goal.route_connected and not goal.completed,"new game has neither goal and no completion")
 check(before.world.has("region_completion"),"goal ledger belongs to normal saved world")
 check(SaveGame.validate(before,main),"new completion ledger validates in complete Main save")
 var legacy:=before.duplicate(true);legacy.world.erase("region_completion")
 var old_guards:={}
 for row in WorldTrip.C_OUTPOST_LAYOUT:
  old_guards[row.id]={"id":row.id,"kind":WorldTrip.C_OUTPOST_KIND,"lane":row.lane,"home_x":row.position.x,"home_y":row.position.y,"x":row.position.x,"y":row.position.y,"hp":0.0,"max_hp":float(EventDB.ENEMIES[WorldTrip.C_OUTPOST_KIND].hp),"attack_left":1.0,"target":"","engager":"","dead":true}
 legacy.world.outpost_states={"c_quarry":{"enemies":old_guards,"cleared":true}}
 check(SaveGame.apply(main,legacy) and not main.world.region_goal_snapshot().boss_returned,"old three-guard victory never migrates into boss victory")
 legacy.world.region_state.roads.bd.cleared=true
 check(SaveGame.apply(main,legacy),"legacy save without goal migrates explicitly")
 goal=main.world.call("region_goal_snapshot")
 check(goal.route_connected and not goal.boss_returned and not goal.completed,"legacy open road is kept but never infers boss completion")
 check(main.storage.inventory.counts==before.inventory,"migration preserves inventory")
 check(main.world.outpost_states==legacy.world.outpost_states,"migration preserves the completed old outpost")
 check(main.world.region_state==legacy.world.region_state,"migration preserves roads, lots and mine upgrades")
 for id in ["a_start","b_forest","c_quarry","d_yard"]:
  check(WorldMapDB.public_region(id,main.world.map_profile),"existing region remains open: "+id)
 var migrated:=SaveGame.capture(main)
 for flaw in ["null","version","extra","completion","encounter"]:
  var bad:=migrated.duplicate(true)
  match flaw:
   "null":bad.world.region_completion=null
   "version":bad.world.region_completion.version=999
   "extra":bad.world.region_completion.reward=42
   "completion":bad.world.region_completion.completed=true
   "encounter":bad.world.region_completion.encounters["outpost"]={"cleared":true}
  check(not SaveGame.apply(main,bad) and SaveGame.capture(main)==migrated,"reject malformed goal atomically: "+flaw)
 var guide:=Guide.snapshot(main)
 check(str(guide.sections).contains("採掘中・ボス挑戦中も") and str(guide.sections).contains("帰還確定ではありません"),"guide distinguishes complete field saving from victory return")
 check(str(guide.sections).contains("第1地域の目標") and str(guide.sections).contains("B–D"),"guide explains the two independent goals")
 main.map_ui.open()
 check(main.map_ui._info.text.contains("第1地域") and main.map_ui._info.text.contains("B–D"),"map reads the same goal status")
 main.map_ui.close()
 await finish()
func finish()->void:
 SaveGame.disabled=true
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("REGION COMPLETION assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
