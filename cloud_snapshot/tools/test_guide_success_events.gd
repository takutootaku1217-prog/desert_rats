extends SceneTree
var main
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func history()->Dictionary:return main.navigation.guide_snapshot().get("history",{})
func done(event:String)->bool:return bool(history().get("completed",{}).get(event,false))
func craft(id:String,item:int)->bool:
 var initial:int=main.storage.count_of(item)
 if main.request_craft(id,1)!=1:return false
 for tick in range(1800):
  main._process(0.2)
  for w in main.workers:w._process(0.2)
  if main.storage.count_of(item)>initial:return true
  if tick%48==0:await process_frame
 return false
func move_material(item:int,n:int)->bool:
 if main.request_transfer(item,n,"to_workshop")!=n:return false
 for tick in range(1800):
  main._process(0.2)
  for w in main.workers:w._process(0.2)
  if main.workshop_count(item)>=n:return true
  if tick%48==0:await process_frame
 return false
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",261108);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 check(history().get("version",0)==1,"guide exposes versioned success history separately")
 check(history().get("completed",{}).is_empty(),"startup supplies are not earned history")
 main.storage.add_item(GameData.Item.WOOD,1,Inventory.SOURCE_PURCHASE)
 main.storage.store_owned(GameData.Item.STONE,1,Inventory.SOURCE_TRANSFER)
 check(not done("wood_gathered") and not done("stone_gathered"),"purchases and internal transfer do not fabricate gathering")
 main.storage.add_item(GameData.Item.WOOD,1,Inventory.SOURCE_ENVIRONMENT)
 main.storage.add_item(GameData.Item.STONE,1,Inventory.SOURCE_ENVIRONMENT)
 check(done("wood_gathered") and done("stone_gathered"),"accepted environmental delivery records gathering")
 var state:=SaveGame.capture(main)
 main.navigation.activate("はじめの一周");main.navigation._process(0.0)
 check(SaveGame.capture(main)==state,"opening and refreshing guide changes no saved state")
 check(main.navigation.guide_text.text.contains("未記録") and main.navigation.guide_text.text.contains("記録"),"visible guide distinguishes missing record from current inventory")
 main.navigation.close();paused=false
 # Explicit fixture materials/workbench, not earned history.
 main.finish_build("workbench")
 main.storage.inventory.counts.merge({GameData.Item.WOOD:30,GameData.Item.STONE:10,GameData.Item.HIDE:3,GameData.Item.IRON:3},true)
 main.refill_settings={}
 main.workers[0].set_priority(GameData.Job.HAUL,5)
 main.workers[1].set_priority(GameData.Job.PROCESS,5)
 for material in [[GameData.Item.WOOD,5],[GameData.Item.STONE,1],[GameData.Item.HIDE,1],[GameData.Item.IRON,1]]:
  check(await move_material(material[0],material[1]),"real transfer supplies crafting workstation")
 check(not done("tool_crafted") and not done("frame_crafted"),"injected setup stock and transfer do not invent production")
 check(main.request_craft("tool_wood_pick",1)==1,"real craft request accepted")
 main.cancel_craft(0)
 check(not done("tool_crafted"),"cancelled queued work is not completed history")
 check(await craft("tool_wood_pick",GameData.Item.WOOD_PICK),"real workers complete and deliver wooden mining tool")
 check(done("tool_crafted"),"manufacture success records wooden tool")
 check(await craft("repair_stone",GameData.Item.REPAIR_KIT),"real workers complete repair recipe")
 check(done("repair_crafted"),"manufacture success records repair material")
 check(await craft("haul_frame",GameData.Item.HAUL_FRAME),"real workers complete frame")
 check(done("frame_crafted") and not done("frame_equipped"),"manufacturing and equipping are separate events")
 for w in main.workers:w.stop_work()
 check(main.equip_work_support(main.workers[0]),"real equipment command succeeds")
 check(done("frame_equipped"),"actual exchange records frame equip")
 SaveGame.disabled=false
 check(SaveGame.write(main,"user://guide-events.json",true),"history is captured in normal real-file save")
 SaveGame.disabled=true;main.queue_free();await process_frame
 print("GUIDE SUCCESS EVENTS failures=",failures);quit(0 if failures==0 else 1)
