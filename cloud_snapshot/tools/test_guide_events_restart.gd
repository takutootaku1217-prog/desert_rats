extends SceneTree
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 var main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame;main.process_mode=Node.PROCESS_MODE_DISABLED
 for path in ["user://guide-events.json","user://guide-return-events.json"]:
  var saved:=SaveGame.read(path)
  check(not saved.is_empty() and SaveGame.apply(main,saved),"separate process loads "+path)
  if saved.is_empty():continue
  check(main.navigation.guide_snapshot().history==saved.world.guide_progress,"saved success history restores exactly")
  var flags:Dictionary=main.world.guide_progress.completed
  if path.contains("return"):
   check(flags.get("quarry_returned",false) and flags.get("returned_a",false),"cargo and safe-town success survive restart")
  else:
   check(flags.get("tool_crafted",false) and flags.get("repair_crafted",false) and flags.get("frame_crafted",false) and flags.get("frame_equipped",false),"manufacture and equip success survive restart")
  var untouched:Dictionary=main.world.guide_progress.duplicate(true)
  var exposed:Dictionary=main.navigation.guide_snapshot().history
  exposed.completed.clear()
  check(main.world.guide_progress==untouched,"UI history is a deep copy")
  for flaw in ["unknown_version","missing_completed","unknown_event","nonbool","extra_key","return_without_cargo","null"]:
   var bad:Dictionary=saved.duplicate(true)
   match flaw:
    "unknown_version":bad.world.guide_progress.version=2
    "missing_completed":bad.world.guide_progress.erase("completed")
    "unknown_event":bad.world.guide_progress.completed["free_reward"]=true
    "nonbool":bad.world.guide_progress.completed["wood_gathered"]=1
    "extra_key":bad.world.guide_progress["reward"]=1
    "return_without_cargo":bad.world.guide_progress.completed={"returned_a":true}
    "null":bad.world.guide_progress=null
   check(not SaveGame.apply(main,bad) and main.world.guide_progress==untouched,"malformed history rejected without mutation: "+flaw)
  var legacy:Dictionary=saved.duplicate(true);legacy.world.erase("guide_progress")
  check(SaveGame.apply(main,legacy) and main.world.guide_progress.completed.is_empty(),"old save with stock/equipment does not invent history")
  if main.workers[0].work_support==GameData.Item.HAUL_FRAME:
   check(main.swap_work_support(main.workers[0],GameData.Item.HAUL_FRAME).get("already_equipped",false) and main.world.guide_progress.completed.is_empty(),"already-equipped no-op does not invent legacy equip history")
  main.storage.store_owned(GameData.Item.WOOD_PICK,1,Inventory.SOURCE_PROCESSING)
  check(main.world.guide_progress.completed.is_empty(),"old completed product delivery is not a new manufacture event")
 main.queue_free();await process_frame
 print("GUIDE RESTART failures=",failures);quit(0 if failures==0 else 1)
