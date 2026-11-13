extends SceneTree
## Explicit equipment fixtures test an unsupported boss-route boundary, not
## natural combat difficulty. The ordinary mining handcart remains supported.
const Session=preload("res://bridge/route_connection_session.gd")
var main
var assertions:=0
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1;print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func fresh()->void:
 paused=false
 if is_instance_valid(main):main.queue_free();await process_frame
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"ordinary route "+destination)
  for unused in 300:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
 main.mine_arrival_gate._process(0.0)
func equip_cart(index:int)->void:
 main.storage.store_owned(GameData.Item.HANDCART,1,Inventory.SOURCE_TRANSFER)
 check(main.equip_work_support(main.workers[index],GameData.Item.HANDCART),"explicit fixture equips existing cart: "+str(index))
func unchanged(before:Dictionary,gate)->bool:
 return SaveGame.capture(main)==before.save and gate._entry_options==before.options and gate._session_serial==before.serial and gate._entry_stance==before.entry_stance and SaveGame.disabled==before.disabled
func boundary(gate)->Dictionary:
 return {"save":SaveGame.capture(main),"options":gate._entry_options.duplicate(true),"serial":gate._session_serial,"entry_stance":gate._entry_stance,"disabled":SaveGame.disabled}
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 await fresh();await equip_cart(2)
 var gate=main.mine_arrival_gate
 var before:=boundary(gate)
 check(not gate.enter_boss() and gate.field==null and gate.visible_state()=="arrival_choice","participating cart escort is refused before field creation")
 check(unchanged(before,gate),"refused gate preserves complete save, equipment, stock, positions, commands and serial")
 check(gate._notice.text.contains("手押し車") and gate._notice.text.contains("安全帰路") and gate._notice.text.contains("未対応") and gate._notice.text.contains("外"),"notice identifies temporary unsupported boss return and removal remedy")
 if gate.field==null:
  check(main.unequip_work_support(main.workers[2]),"ordinary unequip remains available after refusal")
  check(gate.enter_boss(),"removing cart allows immediate ordinary retry")
 await fresh();await equip_cart(2);gate=main.mine_arrival_gate
 before=boundary(gate)
 var made:Dictionary=Session.create_from_game(main,"unsupported-cart",{"encounter_id":FirstRegionCompletion.ENCOUNTER_ID})
 check(not made.ok and str(made.get("reason","")).contains("安全帰路"),"direct session creation applies same boss loadout boundary")
 check(unchanged(before,gate),"direct refusal leaves world and equipment untouched")
 await fresh();await equip_cart(2);gate=main.mine_arrival_gate
 main.workers[0].floor_i=0 # Explicit pending-recall boundary, not movement evidence.
 check(not main.world.ready_reason().is_empty(),"fixture would otherwise enter pending recall")
 before=boundary(gate)
 check(not gate.enter_boss() and gate.visible_state()=="arrival_choice" and gate.field==null,"unsupported cart is refused before pending entry")
 check(unchanged(before,gate),"preflight refusal issues no recall or entry ownership changes")
 await fresh();await equip_cart(0);await equip_cart(1)
 main.storage.store_owned(GameData.Item.HANDCART,1,Inventory.SOURCE_TRANSFER)
 gate=main.mine_arrival_gate
 check(gate.enter_boss(),"unrelated harvest, carrier and stored carts do not block boss")
 if gate.field!=null:gate.field.process_mode=Node.PROCESS_MODE_DISABLED
 # Explicit legacy compatibility fixture: matching gear in actor, crew and
 # traces models the previously accepted active-cart boss bundle. No old save
 # file is read or overwritten; both rejection APIs must leave the live owner.
 await fresh();gate=main.mine_arrival_gate
 check(gate.enter_boss(),"control boss entry for legacy snapshot boundary")
 if gate.field!=null:
  var adapter=gate.field;adapter.process_mode=Node.PROCESS_MODE_DISABLED
  var session=adapter.session
  for mode in ["outpost_move","combat"]:
   for unused in 1200:
    adapter.life_clock.tick(0.05)
    if session.actors["worker:2"].state==mode and not session.actors["worker:2"].path.is_empty():break
   var control:=SaveGame.capture(main)
   check(SaveGame.validate(control,main),"unarmed control snapshot remains valid: "+mode)
   var legacy:=control.duplicate(true)
   legacy.crew[2].worker.work_support=GameData.Item.HANDCART
   var actor:Dictionary=legacy.field_snapshot.session.actors["worker:2"]
   actor.work_support=GameData.Item.HANDCART;actor.entry_work_support=GameData.Item.HANDCART;actor.route="cart_detour"
   if legacy.field_snapshot.traces.has("worker:2"):
    legacy.field_snapshot.traces["worker:2"].gear=GameData.Item.HANDCART
    legacy.field_snapshot.traces["worker:2"].reason="手押し車の経路外移動は救助経路として利用できません"
   if legacy.field_snapshot.plans.has("worker:2"):legacy.field_snapshot.plans["worker:2"].gear=GameData.Item.HANDCART
   if mode=="combat":
    var probe=CFieldSnapshot.prepare(control).session
    var pa:Dictionary=probe.actors["worker:2"]
    pa.work_support=GameData.Item.HANDCART;pa.entry_work_support=GameData.Item.HANDCART;pa.combat_target=""
    probe.outpost_enemies[FirstRegionCompletion.BOSS_ID].engager="";probe.outpost_enemies[FirstRegionCompletion.BOSS_ID].target=""
    var validator=preload("res://bridge/c_field_boss_snapshot.gd")
    for state in ["escort","to_base_empty","injured_return","safe_wait"]:
     pa.state=state;pa.resume_state="";pa.entry_hp=100.0
     check(not validator.valid(probe,control.world),"narrow boss validator rejects assigned cart before safe return: "+state)
    pa.x=probe.BASE.x;pa.y=probe.BASE.y
    for state in ["idle","injured_wait","rescue_treatment"]:
     pa.state=state;pa.resume_state=""
     check(validator.valid(probe,control.world),"narrow boss validator permits safely returned cart: "+state)
    pa.state="injured_return";pa.entry_hp=30.0;pa.hp=30.0;pa.x=probe.BASE.x+56.0
    check(validator.valid(probe,control.world),"narrow boss validator permits initially nonparticipating low-HP cart short return")
   legacy.weight=SaveGame.saved_weight(legacy) # Match the explicit cart fixture, not a malformed mass ledger.
   check(not SaveGame.validate(legacy,main),"reject unsupported active-cart legacy validation: "+mode)
   check(gate.field==adapter and adapter.life_clock.is_current() and SaveGame.capture(main)==control,"validation has no live mutation: "+mode)
   var applied:=SaveGame.apply(main,legacy)
   check(not applied,"reject unsupported active-cart legacy load: "+mode)
   check(gate.field==adapter and adapter.life_clock.is_current() and SaveGame.capture(main)==control,"rejected load is atomic: "+mode)
   if applied:
    check(SaveGame.apply(main,control),"RED restores original supported control owner")
    paused=false;adapter=gate.field;adapter.process_mode=Node.PROCESS_MODE_DISABLED;session=adapter.session
 await fresh();await equip_cart(2);main.workers[2].hp=30.0
 made=Session.create_from_game(main,"low-hp-cart",{"encounter_id":FirstRegionCompletion.ENCOUNTER_ID})
 check(not made.ok and str(made.get("reason","")).contains("HP30") and not str(made.get("reason","")).contains("手押し車"),"nonparticipating low-HP cart escort retains health refusal instead")
 await fresh();await equip_cart(0);await equip_cart(2);gate=main.mine_arrival_gate
 check(gate.enter_mine(),"ordinary mine entry still supports carts including escort")
 if gate.field!=null:
  gate.field.process_mode=Node.PROCESS_MODE_DISABLED
  check(gate.field.session.actors["worker:0"].route=="cart_detour","ordinary mining handcart keeps existing wide detour")
  var ordinary:=SaveGame.capture(main)
  check(SaveGame.validate(ordinary,main) and SaveGame.apply(main,ordinary),"ordinary mining cart complete save still validates and loads")
 SaveGame.disabled=true
 if is_instance_valid(main):main.queue_free()
 await process_frame
 print("C BOSS CART ENTRY assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
