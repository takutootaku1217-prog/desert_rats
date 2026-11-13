extends SceneTree
## Real Main/WorldTrip/Inventory behavior with explicitly seeded diagnostic state.
## Catches reserved-stock theft, half-committed signals and nested mutations.
## Headless 4.6.3 diagnostics are not ordinary input or 4.7.2 validation.
var main
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE

func _init() -> void:
 call_deferred("_run")
func _check(ok: bool, label: String) -> void:
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func _fresh(site := "b_forest") -> void:
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",261109)
 root.add_child(main)
 await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 main.director.enabled=false
 main.world.region=site
 main.world.phase="stopped"
 main.world.region_state.lots[site]=WorldTrip.REGION_A_BUILD[site].lot
 main.storage.inventory.counts={WOOD:5,STONE:5}
 main.transfer_queue.clear()
 for w in main.workers:
  w.stop_work()
 _check(main.world.ready_reason().is_empty(),"transfer fixture starts with safely returned crew")
 # This optional key is absent from ordinary initial_state. A new dictionary
 # dot key is StringName in Godot; saved dictionaries require String/int keys.
 main.base.vehicle_loadout["prototype_unlimited"]=false
func _release() -> void:
 main.queue_free()
 await process_frame
func _state() -> Dictionary:
 return {"counts":main.storage.inventory.counts.duplicate(true),"stores":main.world.site_stores.duplicate(true),"land":main.world.region_state.duplicate(true),"locations":main.world.locations.duplicate(true)}
func _reserve(kind: String,n: int) -> void:
 if kind=="transfer":
  main.transfer_queue.append({"item":WOOD,"n":n,"dir":"to_workshop"})
 else:
  var a=main.workers[0].ai
  a.state=CharacterAI.State.HAUL_TAKE
  a.haul_recipe={"in":{WOOD:n}}
  if kind=="build":a.haul_recipe["build"]="workbench"
func _buttons() -> Dictionary:
 main.map_ui._refresh_land()
 var result:={}
 var name:String=main.map_ui._item_name(WOOD)
 for child in main.map_ui._land_box.get_children():
  if child is Button:
   if child.text.begins_with(name+"を1預ける"):result.deposit=child
   if child.text.begins_with(name+"を1引出す"):result.withdraw=child
 return result
func _run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="":
  push_error("Isolated FLUID_TEST_HOME required")
  quit(2);return
 SaveGame.disabled=true
 # Removing the reservation-aware available count must fail each reader below.
 for site in ["b_forest","d_yard"]:
  for kind in ["transfer","craft","build"]:
   await _fresh(site)
   _reserve(kind,5)
   var before:=_state()
   _check(main.warehouse_discard_available(WOOD)==0,kind+" fixture fully reserves stock")
   _check(main.world.deposit_to_site(WOOD,5)==0,site+" rejects fully "+kind+" reserved deposit")
   _check(_state()==before,"rejected deposit preserves all ledgers")
   await _release()
   await _fresh(site)
   _reserve(kind,3)
   _check(main.world.deposit_to_site(WOOD,5)==2,site+" moves only unreserved "+kind+" surplus")
   _check(main.storage.inventory.count(WOOD)==3 and main.world.site_store(site).get(WOOD,0)==2,"exact reserved quantity stays in vehicle")
   await _release()
 # A notify-before-site-commit or missing guard makes these callbacks fail.
 for operation in ["deposit","withdraw"]:
  for signal_name in (["changed"] if operation=="deposit" else ["item_added","changed"]):
   await _fresh()
   main.world.site_stores.b_forest={WOOD:1}
   var ledger:Dictionary=main.world.locations.duplicate(true)
   var seen:={"calls":0,"snapshot":{},"deposit":-1,"withdraw":-1,"clear":true,"grade":true,"remove":true,"source":""}
   var inspect:=func():
    seen.calls+=1
    if seen.calls!=1:return
    seen.snapshot={"vehicle":main.storage.inventory.count(WOOD),"site":main.world.site_store("b_forest").get(WOOD,0)}
    seen.deposit=main.world.deposit_to_site(WOOD,1)
    seen.withdraw=main.world.withdraw_from_site(WOOD,1)
    seen.clear=main.world.clear_shortcut()
    seen.grade=main.world.grade_ab()
    seen.remove=main.world.remove_current_site()
   var added:=func(_item:int,_amount:int,source:String):
    seen.source=source
    inspect.call()
   var callback:Callable=added if signal_name=="item_added" else inspect
   main.storage.inventory.connect(signal_name,callback)
   var moved:int=main.world.deposit_to_site(WOOD,2) if operation=="deposit" else main.world.withdraw_from_site(WOOD,1)
   main.storage.inventory.disconnect(signal_name,callback)
   _check(moved==(2 if operation=="deposit" else 1),operation+" returns actual moved count")
   var expected:={"vehicle":3,"site":3} if operation=="deposit" else {"vehicle":6,"site":0}
   _check(seen.snapshot==expected,operation+" "+signal_name+" sees both committed ledgers")
   _check(seen.calls==1,"exactly one "+signal_name+" notification")
   _check(seen.deposit==0 and seen.withdraw==0,"same and opposite nested site transfers are rejected")
   _check(not seen.clear and not seen.grade and not seen.remove,"nested land payment/removal is rejected")
   _check(main.storage.inventory.count(WOOD)==expected.vehicle and main.world.site_store("b_forest").get(WOOD,0)==expected.site,"nested callbacks cannot duplicate or lose resources")
   _check(main.world.site_built("b_forest") and main.world.locations==ledger,"transfer preserves site and finite-resource ledger")
   if signal_name=="item_added":_check(seen.source==Inventory.SOURCE_TRANSFER,"withdrawal remains an ownership transfer")
   _check(main.world.deposit_to_site(STONE,1)==1,"guard releases for a later independent command")
   await _release()
 # A payment's own synchronous notification must not initiate a new transfer.
 await _fresh()
 var cross:={"deposit":-1,"withdraw":-1,"called":false}
 main.world.site_stores.b_forest={WOOD:1}
 var during_payment:=func():
  if cross.called:return
  cross.called=true
  cross.deposit=main.world.deposit_to_site(WOOD,1)
  cross.withdraw=main.world.withdraw_from_site(WOOD,1)
 main.storage.inventory.changed.connect(during_payment)
 _check(main.world.clear_shortcut(),"outer land payment succeeds")
 main.storage.inventory.changed.disconnect(during_payment)
 _check(cross.called and cross.deposit==0 and cross.withdraw==0,"land payment guard also rejects nested site transfers")
 _check(main.storage.inventory.count(WOOD)==3 and main.world.site_store("b_forest").get(WOOD,0)==1,"only outer land payment changes ownership")
 await _release()
 # Counts are clamped to actual capacity, and failure is a silent no-op.
 for site in ["b_forest","d_yard"]:
  await _fresh(site)
  main.world.site_stores[site]={STONE:23 if site=="b_forest" else 35}
  _check(main.world.deposit_to_site(WOOD,5)==1,"deposit respects "+site+" total capacity")
  var before:=_state()
  _check(main.world.deposit_to_site(WOOD,1)==0 and _state()==before,"full site is unchanged")
  _check(main.world.site_store("d_yard" if site=="b_forest" else "b_forest").is_empty(),"other site is not credited")
  await _release()
 await _fresh()
 main.world.site_stores.b_forest={WOOD:3}
 main.storage.capacity_bonus=main.storage.current_weight()+4-main.storage.max_weight()
 _check(main.storage.free_for(WOOD)==1,"fixture allows exactly one wood by weight")
 _check(main.world.withdraw_from_site(WOOD,3)==1,"withdrawal respects vehicle weight capacity")
 var full:=_state()
 _check(main.world.withdraw_from_site(WOOD,1)==0 and _state()==full,"full vehicle leaves remaining site stock untouched")
 await _release()
 for condition in ["inactive","travel","wrong_site","unbuilt","wrong_profile","zero","negative","invalid_item","empty"]:
  await _fresh()
  main.world.site_stores.b_forest={WOOD:3}
  var item:=WOOD
  var n:=1
  match condition:
   "inactive":main.world.active=false
   "travel":main.world.phase="travel"
   "wrong_site":main.world.region="a_start"
   "unbuilt":main.world.region_state.lots.b_forest="wild";main.world.site_stores.b_forest={}
   "wrong_profile":main.world.map_profile=WorldMapDB.DESERT
   "zero":n=0
   "negative":n=-1
   "invalid_item":item=-999;main.storage.inventory.counts[item]=2;main.world.site_stores.b_forest[item]=2
   "empty":main.storage.inventory.counts.erase(WOOD);main.world.site_stores.b_forest.erase(WOOD)
  var before:=_state()
  var signals:={"count":0}
  var on_changed:=func():signals.count+=1
  main.storage.inventory.changed.connect(on_changed)
  _check(main.world.deposit_to_site(item,n)==0 and main.world.withdraw_from_site(item,n)==0,condition+" rejects both directions")
  main.storage.inventory.changed.disconnect(on_changed)
  _check(_state()==before and signals.count==0,condition+" changes no ledger and emits nothing")
  await _release()
 # UI has no separate authority; stale state is rechecked by the command.
 await _fresh()
 _reserve("transfer",5)
 var buttons:=_buttons()
 _check(buttons.deposit.disabled and buttons.withdraw.disabled,"UI disables fully reserved deposit and empty withdrawal")
 _check(buttons.deposit.text.contains("未予約") and buttons.deposit.text.contains("0"),"UI labels unreserved availability")
 main.transfer_queue.clear()
 buttons=_buttons()
 _check(not buttons.deposit.disabled,"UI enables actual surplus")
 _reserve("transfer",5)
 var before:=_state()
 buttons.deposit.emit_signal("pressed")
 _check(_state()==before,"stale UI cannot spend a newly reserved item")
 main.transfer_queue.clear()
 main.world.site_stores.b_forest={WOOD:2}
 buttons=_buttons()
 _check(not buttons.withdraw.disabled,"UI enables available withdrawal")
 main.storage.capacity_bonus=main.storage.current_weight()-main.storage.max_weight()
 before=_state()
 buttons.withdraw.emit_signal("pressed")
 _check(_state()==before,"stale UI cannot withdraw into newly full vehicle")
 buttons=_buttons()
 _check(buttons.withdraw.disabled,"UI disables full vehicle withdrawal")
 main.world.site_stores.b_forest={WOOD:24}
 buttons=_buttons()
 _check(buttons.deposit.disabled,"UI disables full site deposit")
 await _release()
 # Compatibility coverage: transfer outcome uses the existing save shape.
 # Return fixture to original A before capture; no location/entity teleport is
 # being asserted as real travel. A second engine process reads this file.
 await _fresh()
 _check(main.world.deposit_to_site(WOOD,2)==2 and main.world.withdraw_from_site(WOOD,1)==1,"save fixture completes one deposit and withdrawal")
 main.world.region_state.lots.d_yard="freight"
 main.world.site_stores.d_yard={STONE:2}
 main.world.region="a_start"
 var snapshot:=SaveGame.capture(main)
 _check(SaveGame.validate(snapshot,main),"transfer fixture is a valid existing-format save")
 _check(snapshot.inventory.get(WOOD,0)==4 and snapshot.world.site_stores.b_forest.get(WOOD,0)==1,"snapshot preserves both final ownership ledgers")
 SaveGame.disabled=false
 _check(SaveGame.write(main,"user://site-transfer-contract.json"),"real atomic writer saves transfer fixture in isolated user directory")
 SaveGame.disabled=true
 await _release()
 SaveGame.disabled=false
 print("SITE TRANSFER CONTRACT failures=",failures)
 quit(1 if failures else 0)
