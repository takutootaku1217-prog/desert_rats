extends SceneTree
var main
var failures:=0
var assertions:=0
const W:=GameData.Item.WOOD
const S:=GameData.Item.STONE
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1;print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func state()->Dictionary:
 return {"inventory":main.storage.inventory.counts.duplicate(true),"cr":main.town.credits,"fuel":main.base.fuel,"refuels":main.base.total_refuel,"world":SaveGame.fields(main.world,WorldTrip.FIELDS)}
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame;main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for j in GameData.job_list():w.priorities[j]=0
 main.world.region="d_yard";main.world.phase="stopped"
 main.storage.inventory.counts={W:8,S:6};main.town.credits=40
 var has_state:=false
 for p in main.world.get_property_list():
  if p.name=="npc_facilities":has_state=true
 check(has_state,"independent NPC facility extension exists")
 if not has_state:await finish();return
 var service=main.world.npc_service
 check(not service.restored(),"old/wild D starts closed")
 var before:=state()
 main.storage.inventory.counts[W]=3
 check(not service.quote("restore").ok,"short materials reject")
 main.storage.inventory.counts[W]=8;main.town.credits=11
 check(not service.quote("restore").ok,"short Cr reject")
 main.town.credits=40
 for reservation in ["transfer","build","craft"]:
  main.storage.inventory.counts[W]=4
  if reservation=="transfer":main.transfer_queue.append({"item":W,"n":1,"dir":"to_workshop"})
  else:
   main.workers[0].ai.state=CharacterAI.State.HAUL_TAKE
   main.workers[0].ai.haul_recipe={"in":{W:1}}
   if reservation=="build":main.workers[0].ai.haul_recipe["build"]="workbench"
  before=state()
  check(not service.quote("restore").ok and state()==before,"reserved-only materials refused: "+reservation)
  main.transfer_queue.clear();main.workers[0].stop_work();main.build_queue.clear()
 main.storage.inventory.counts[W]=8
 var q:Dictionary=service.quote("restore")
 check(q.ok and q.cost==12 and q.materials=={W:4,S:2},"provisional configured material and cash quote")
 main.town.credits=39;before=state()
 check(not service.execute(q) and state()==before,"changed balance invalidates quote unchanged")
 main.town.credits=40;q=service.quote("restore")
 var nested:={"signals":0,"coherent":false,"restore":true,"fuel":true,"land":true,"deposit":-1,"departure":true}
 var observer:=func():
  nested.signals+=1
  nested.coherent=service.restored() and main.town.credits==28 and main.storage.count_of(W)==4 and main.storage.count_of(S)==4
  nested.restore=service.quote("restore").ok
  nested.fuel=service.quote("fuel_cash").ok
  nested.land=main.world.build_current_site()
  nested.deposit=main.world.deposit_to_site(W,1)
  nested.departure=main.world.request("c_quarry")
 main.storage.inventory.changed.connect(observer)
 check(service.execute(q),"restore succeeds")
 main.storage.inventory.changed.disconnect(observer)
 check(nested.signals==1 and nested.coherent and not nested.restore and not nested.fuel and not nested.land and nested.deposit==0 and not nested.departure,"atomic signal sees all ledgers and refuses nested mutations")
 main.world.cancel_or_return() # Repeated cancel also invalidates any transient quote.
 check(main.world.region_state.lots.d_yard=="wild" and main.world.site_stores.d_yard.is_empty(),"NPC does not reinterpret freight lot")
 before=state();check(not service.execute(q) and not service.quote("restore").ok and state()==before,"repeat restore and quote replay are no-ops")
 main.base.fuel=94.5;q=service.quote("fuel_cash")
 check(q.ok and q.amount==5.5 and q.cost==2,"partial fuel costs actual rounded amount")
 check(service.execute(q) and main.base.fuel==100.0 and main.town.credits==26 and main.base.total_refuel==1,"cash service fills actual amount once")
 check(not service.quote("fuel_cash").ok,"full tank refuses")
 main.base.fuel=40.0;main.base.refuel_reserved=true;before=state()
 check(not service.quote("fuel_cash").ok and state()==before,"worker fuel reservation refuses")
 main.base.refuel_reserved=false;q=service.quote("fuel_cash")
 main.world.region="a_start";before=state()
 check(not service.execute(q) and state()==before,"D quote cannot execute at A")
 check(main.town.location_ok() and main.town.quote("fuel_cash").ok,"A cash service remains available")
 var aq:Dictionary=main.town.quote("fuel_cash")
 main.world.region="d_yard";before=state()
 check(not main.town.location_ok() and not main.town.execute(aq) and state()==before,"A quote cannot transfer to D")
 for action in ["buy","sell","accept_supply","repair_cash","fuel_item"]:
  check(not service.quote(action).ok and not main.town.quote(action,W,1).ok,"D cannot gain town service: "+action)
 q=service.quote("fuel_cash");main.world.phase="departing";before=state()
 check(not service.execute(q) and state()==before,"departure invalidates service")
 main.world.phase="stopped"
 main.world.region_state.lots.d_yard="freight"
 check(main.world.remove_current_site() and service.restored(),"removing independent empty freight lot retains NPC service")
 main.base.fuel=40.0
 q=service.quote("fuel_cash")
 check(main.world.request("c_quarry") and main.world.cancel_or_return(),"real departure/cancel cycle")
 before=state();check(not service.execute(q) and state()==before,"depart and return to same D cannot reuse old quote")
 main.map_ui.open();main.map_ui._refresh_land()
 var text:=""
 for child in main.map_ui._land_box.get_children():
  if child is Label:text+=child.text
 check(text.contains("NPC") and text.contains("営業") and text.contains("Cr"),"ordinary map explains independent cash-only facility")
 var offer:Button
 for child in main.map_ui._land_box.get_children():
  if child is Button and child.text.begins_with("給油の見積り"):offer=child
 check(offer!=null,"ordinary map exposes fuel quote")
 offer.emit_signal("pressed")
 var confirm:Button
 for child in main.map_ui._land_box.get_children():
  if child is Button and child.text=="この金額で給油":confirm=child
 check(confirm!=null and not confirm.disabled,"map quote requires explicit cash confirmation")
 main.map_ui._refresh_land();before=state();confirm.emit_signal("pressed")
 check(state()==before,"old map generation cannot pay")
 main.map_ui._npc_action="fuel_cash";main.map_ui._refresh_land()
 for child in main.map_ui._land_box.get_children():
  if child is Button and child.text=="この金額で給油":confirm=child
 main.map_ui.close();before=state();confirm.emit_signal("pressed")
 check(state()==before,"closed map callback cannot pay")
 main.map_ui.open();main.map_ui._npc_action="fuel_cash";main.map_ui._refresh_land()
 for child in main.map_ui._land_box.get_children():
  if child is Button and child.text=="この金額で給油":confirm=child
 var cr:int=main.town.credits;confirm.emit_signal("pressed")
 check(main.base.fuel==65.0 and main.town.credits==cr-8,"ordinary map signal pays the shared full-unit price")
 before=state();confirm.emit_signal("pressed");check(state()==before,"same confirm cannot double-charge")
 main.map_ui.close()
 await finish()
func finish()->void:
 main.queue_free();await process_frame;SaveGame.disabled=false
 print("NPC FUEL RESTORATION assertions=",assertions," failures=",failures)
 quit(1 if failures else 0)
