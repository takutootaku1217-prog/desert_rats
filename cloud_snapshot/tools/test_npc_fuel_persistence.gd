extends SceneTree
const PATH:="user://npc-fuel-field.json"
const RECEIPT:="user://npc-fuel-receipt.json"
var main
var failures:=0
var assertions:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1;print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func travel(site:String)->void:
 check(main.world.request(site),"request "+site)
 for unused in 400:
  main._process(0.25);await process_frame
  if main.world.region==site and main.world.phase=="stopped":break
 check(main.world.region==site and main.world.phase=="stopped","arrive "+site)
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true;main.set_meta("diagnostic_seed",104729)
 root.add_child(main);await process_frame;main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for j in GameData.job_list():w.priorities[j]=0
 main.storage.inventory.counts={GameData.Item.WOOD:12,GameData.Item.STONE:12};main.town.credits=40
 await travel("d_yard")
 check(main.world.build_current_site(),"independent player freight lot builds")
 check(main.world.deposit_to_site(GameData.Item.STONE,2)==2,"independent freight contains actual stock")
 var old:=SaveGame.capture(main);old.world.erase("npc_facilities")
 check(SaveGame.validate(old,main) and SaveGame.apply(main,old),"old save migrates without NPC state")
 check(not main.world.npc_service.restored() and main.world.region_state.lots.d_yard=="freight" and main.world.site_store("d_yard").get(GameData.Item.STONE)==2,"old freight remains storage, never inferred NPC restoration")
 var previous:=SaveGame.capture(main)
 var comparable:=previous.duplicate(true);comparable.world.erase("npc_facilities")
 check(comparable==old,"old save migration changes only missing extension")
 for bad_value in [{},{"version":2,"facilities":{"d_fuel":{"restored":false}}},{"version":1,"facilities":{"d_fuel":{"restored":1}}},{"version":1,"facilities":{"d_fuel":{"restored":false,"extra":0}}},{"version":1,"facilities":{"d_fuel":{"restored":false},"other":{"restored":true}}}]:
  var bad:=previous.duplicate(true);bad.world.npc_facilities=bad_value
  check(not SaveGame.apply(main,bad) and SaveGame.capture(main)==previous,"malformed NPC extension fails atomically")
 check(main.world.npc_service.execute(main.world.npc_service.quote("restore")),"restore from real available inventory")
 var expected_cr:int=main.town.credits
 SaveGame.disabled=false
 check(SaveGame.write(main,"user://npc-fuel-d.json",true),"normal D save captures restored facility")
 var q:Dictionary=main.world.npc_service.quote("fuel_cash")
 check(SaveGame.apply(main,SaveGame.read("user://npc-fuel-d.json")),"normal save loads")
 check(not main.world.npc_service.execute(q),"loading invalidates transient service quote")
 main.process_mode=Node.PROCESS_MODE_DISABLED
 await travel("c_quarry")
 var gate=main.mine_arrival_gate;gate._process(0.0)
 check(gate.enter_mine(),"ordinary C entry after restoration")
 if gate.field==null:await finish();return
 gate.field.process_mode=Node.PROCESS_MODE_DISABLED
 gate.field.life_clock.tick(0.25)
 check(main.world.npc_service.restored() and main.town.credits==expected_cr,"C entry preserves exact restored state and balance")
 var snapshot:=SaveGame.capture(main)
 check(SaveGame.validate(snapshot,main),"restored NPC field snapshot validates")
 check(SaveGame.write_field(main,PATH,true),"actual mid-field save writes")
 var f=FileAccess.open(RECEIPT,FileAccess.WRITE);f.store_string(JSON.stringify({"pid":OS.get_process_id(),"hash":FileAccess.get_sha256(PATH),"cr":expected_cr}));f.close()
 await finish()
func finish()->void:
 main.queue_free();await process_frame;SaveGame.disabled=false
 print("NPC FUEL PERSISTENCE assertions=",assertions," failures=",failures)
 quit(1 if failures else 0)
