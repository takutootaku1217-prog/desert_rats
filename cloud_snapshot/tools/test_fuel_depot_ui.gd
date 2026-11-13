extends SceneTree
## Synthetic real-Main fixtures, not ordinary GUI play. UI signals use existing
## transaction APIs, and refuelling drives the real worker movement/state machine.
var main
var failures := 0
const FUEL := GameData.Item.FUEL
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func fresh(site := "b_forest") -> void:
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",261109)
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 main.director.enabled=false
 for worker in main.workers:
  worker.stop_work()
  for job in GameData.job_list():worker.priorities[job]=0
 main.world.region=site;main.world.phase="stopped"
 main.world.region_state.lots[site]=WorldTrip.REGION_A_BUILD[site].lot
 main.storage.inventory.counts={FUEL:3,WOOD:5,STONE:5}
 main.base.vehicle_loadout["prototype_unlimited"]=false
func release() -> void:
 main.queue_free();await process_frame;paused=false
func state() -> Dictionary:
 return {"inventory":main.storage.inventory.counts.duplicate(true),"stores":main.world.site_stores.duplicate(true),"land":main.world.region_state.duplicate(true),"locations":main.world.locations.duplicate(true),"guide":main.world.guide_progress.duplicate(true),"fuel":main.base.fuel,"refuel":main.base.total_refuel,"cr":main.town.credits}
func buttons() -> Dictionary:
 main.map_ui._refresh_land()
 var result:={}
 for child in main.map_ui._land_box.get_children():
  if child is Button:
   if child.text.begins_with(main.map_ui._item_name(FUEL)+"を1預ける"):result.deposit=child
   if child.text.begins_with(main.map_ui._item_name(FUEL)+"を1引出す"):result.withdraw=child
 return result
func labels() -> String:
 var result:=""
 for child in main.map_ui._land_box.get_children():
  if child is Label:result+=child.text+"\n"
 return result
func run_ui(site: String) -> void:
 await fresh(site)
 var ui:=buttons()
 check(ui.has("deposit") and ui.has("withdraw"),site+" exposes fuel deposit and withdrawal buttons")
 if ui.is_empty():await release();return
 check(labels().contains("個") and labels().contains("重量"),"site count and vehicle weight capacities are distinguished")
 check(labels().contains("車両倉庫") and labels().contains("運搬") and labels().contains(str(int(GameData.FUEL_CAP-GameData.FUEL_ITEMS[FUEL]))),"fuel instructions distinguish warehouse withdrawal and automatic tank threshold")
 var before:=state()
 var weight:int=main.storage.current_weight()
 ui.deposit.emit_signal("pressed")
 check(main.storage.count_of(FUEL)==2 and main.world.site_store(site).get(FUEL)==1,"UI deposits exactly one fuel")
 check(main.storage.current_weight()==weight-CargoDB.size_of(FUEL),"deposit releases exactly one fuel weight")
 var once:=state()
 ui.deposit.emit_signal("pressed")
 check(state()==once,"same old button cannot double-deposit after refresh")
 check(main.base.fuel==before.fuel and main.base.total_refuel==before.refuel and main.town.credits==before.cr and main.world.locations==before.locations and main.world.guide_progress==before.guide,"deposit changes no tank, cash, resource or guide ledger")
 check(not main.world.remove_current_site() and state()==once,"nonempty fuel depot cannot be removed")
 var source:={"value":"","nested":-1}
 var added:=func(item:int,_n:int,why:String):
  if item==FUEL:
   source.value=why
   source.nested=main.world.withdraw_from_site(FUEL,1)
 main.storage.inventory.item_added.connect(added)
 ui=buttons();ui.withdraw.emit_signal("pressed")
 main.storage.inventory.item_added.disconnect(added)
 check(main.storage.count_of(FUEL)==3 and main.world.site_store(site).is_empty(),"UI withdrawal restores the single warehouse fuel")
 check(source.value==Inventory.SOURCE_TRANSFER and source.nested==0,"withdrawal is transfer-sourced and nested withdrawal is refused")
 check(main.base.fuel==before.fuel and main.base.total_refuel==before.refuel and main.world.guide_progress==before.guide,"withdrawal alone neither refuels nor awards guide progress")
 var empty:=state();ui=buttons()
 check(ui.withdraw.disabled and main.world.withdraw_from_site(FUEL,1)==0 and state()==empty,"empty withdrawal is disabled and a no-op")
 # REFUEL_TAKE reserves only the stock not yet physically lifted.
 var worker=main.workers[0]
 worker.ai.state=CharacterAI.State.REFUEL_TAKE;worker.ai.haul_item=FUEL;main.base.refuel_reserved=true
 main.storage.inventory.counts[FUEL]=1
 ui=buttons();before=state()
 check(ui.deposit.disabled and main.world.deposit_to_site(FUEL,1)==0 and state()==before,"last fuel reserved for refuelling cannot be deposited")
 main.storage.inventory.counts[FUEL]=2
 ui=buttons();ui.deposit.emit_signal("pressed")
 check(main.storage.count_of(FUEL)==1 and main.world.site_store(site).get(FUEL)==1,"only surplus above refuel reservation moves")
 worker.stop_work();main.base.refuel_reserved=false
 main.world.site_stores[site]={STONE:main.world.site_capacity(site)-1,FUEL:1}
 ui=buttons();before=state()
 check(main.world.site_capacity(site)==(24 if site=="b_forest" else 36),"existing site capacity stays unchanged")
 check(ui.deposit.disabled and main.world.deposit_to_site(FUEL,1)==0 and state()==before,"full site refuses fuel without changing either ledger")
 main.world.site_stores[site]={FUEL:1}
 main.storage.capacity_bonus=main.storage.current_weight()+CargoDB.size_of(FUEL)-1-main.storage.max_weight()
 ui=buttons();before=state()
 check(ui.withdraw.disabled and main.world.withdraw_from_site(FUEL,1)==0 and state()==before,"less than one fuel weight of room rejects withdrawal unchanged")
 main.storage.capacity_bonus+=1
 ui=buttons();ui.withdraw.emit_signal("pressed")
 check(main.world.site_store(site).is_empty() and main.storage.free_for(FUEL)==0,"exactly one fuel weight of room admits one item")
 main.storage.capacity_bonus=0
 main.world.site_stores[site]={FUEL:1}
 ui=buttons();main.map_ui._refresh_land();before=state();ui.withdraw.emit_signal("pressed")
 check(state()==before,"stale refresh-generation fuel callback does nothing")
 ui=buttons();main.world.region="a_start";before=state();ui.deposit.emit_signal("pressed")
 check(state()==before,"callback from a departed site does nothing")
 main.world.region=site
 main.map_ui.open();ui=buttons();main.map_ui.close();before=state();ui.withdraw.emit_signal("pressed")
 check(state()==before,"closed-map fuel callback does nothing")
 main.map_ui.open();ui=buttons();check(not ui.withdraw.disabled,"reopening reacquires current valid fuel controls");main.map_ui.close()
 await release()
func worker_refuel() -> void:
 await fresh()
 main.storage.inventory.counts={}
 main.world.site_stores.b_forest={FUEL:1}
 main.base.fuel=GameData.FUEL_CAP-GameData.FUEL_ITEMS[FUEL]+0.1
 check(main.world.withdraw_from_site(FUEL,1)==1,"refuel fixture withdraws actual stored fuel")
 var w=main.workers[0]
 w.set_priority(GameData.Job.HAUL,GameData.MAX_PRIORITY)
 for tick in range(100):w._process(0.1)
 check(main.storage.count_of(FUEL)==1 and main.base.total_refuel==0 and not main.base.refuel_reserved,"above threshold no automatic refuelling starts")
 main.base.fuel=GameData.FUEL_CAP-GameData.FUEL_ITEMS[FUEL]
 var saw_take:=false;var saw_move:=false;var saw_work:=false
 var p:Vector2=w.position
 for tick in range(1000):
  w._process(0.1)
  saw_take=saw_take or w.ai.state==CharacterAI.State.REFUEL_TAKE
  if w.ai.state==CharacterAI.State.REFUEL_MOVE:
   saw_move=true
   check(main.storage.count_of(FUEL)==0 and w.carrying==FUEL and main.base.fuel==GameData.FUEL_CAP-GameData.FUEL_ITEMS[FUEL],"physical carried fuel is removed from stock before tank changes")
  saw_work=saw_work or w.ai.state==CharacterAI.State.REFUEL
  if main.base.total_refuel==1:break
 check(saw_take and saw_move and saw_work and w.position!=p,"real worker visits take, movement and timed refuel states")
 check(main.base.fuel==GameData.FUEL_CAP and main.base.total_refuel==1 and main.storage.count_of(FUEL)==0 and w.carrying==-1,"one carried item adds exactly configured tank amount once")
 await release()
func save_fixture() -> void:
 await fresh()
 check(main.world.deposit_to_site(FUEL,2)==2,"save fixture deposits B fuel")
 main.world.region="d_yard";main.world.region_state.lots.d_yard="freight"
 check(main.world.deposit_to_site(FUEL,1)==1,"save fixture deposits D independently")
 main.world.region="b_forest"
 check(main.world.withdraw_from_site(FUEL,1)==1,"save fixture withdraws one B fuel")
 main.world.region="a_start"
 check(SaveGame.validate(SaveGame.capture(main),main),"fuel ledgers fit the unchanged save schema")
 SaveGame.disabled=false
 check(SaveGame.write(main,"user://fuel-depot-ui.json"),"real file stores both fuel depots for separate process")
 SaveGame.disabled=true
 await release()
func _run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 SaveGame.disabled=true
 for site in ["b_forest","d_yard"]:await run_ui(site)
 if failures==0:
  await worker_refuel()
  await save_fixture()
 SaveGame.disabled=false
 print("FUEL DEPOT UI failures=",failures)
 quit(1 if failures else 0)
