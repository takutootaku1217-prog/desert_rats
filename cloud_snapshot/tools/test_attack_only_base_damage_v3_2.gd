extends SceneTree
## Explicit boundary fixtures: no automatic crew repair; state adjustments labeled below.
var g
var fails:=0
func _init():call_deferred("run")
func check(ok:bool,label:String):
 print("ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func run():
 SaveGame.disabled=true
 g=load("res://scenes/main.tscn").instantiate()
 g.first_region_a_pilot=true
 g.set_meta("diagnostic_seed",104729)
 root.add_child(g)
 g.process_mode=Node.PROCESS_MODE_DISABLED
 await process_frame
 paused=false
 g.director.enabled=false
 for w in g.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 var initial:Dictionary=g.base.parts.duplicate()
 var fuel:float=g.base.fuel
 g.world.request("b_forest")
 for i in 1000:
  g._process(0.2)
  if g.world.phase=="stopped" and g.world.region=="b_forest":break
 check(g.base.parts==initial,"actual ordinary road travel causes no part deterioration")
 check(g.base.fuel<fuel,"normal travel still burns fuel")
 var hunger:float=g.workers[0].hunger
 var elapsed:float=g.director.elapsed
 for i in 3600:
  g._process(1.0)
  CrewStatus._tick_hunger(g.workers[0],1.0)
 check(g.base.parts==initial,"one-hour stopped non-town simulation causes no passive wear")
 check(g.director.elapsed>=elapsed+3599 and g.workers[0].hunger<hunger,"clock and hunger still advance while stopped")
 var moving_fuel:float=g.base.fuel
 g.base.burn(60.0*3600.0) # explicit long-distance fuel boundary; does not fabricate trip rewards
 check(g.base.fuel<moving_fuel,"one-hour moving-distance fuel requirement remains")
 g.base.fuel=moving_fuel # restore only test fuel budget for independent weather checks
 g.base.wear_by(3600.0,1000000.0)
 g.base.wear(GameData.Part.MACHINE,10000.0)
 check(g.base.parts==initial,"all passive wear entry points disabled, not just field HUD")
 # Existing processor work API on a recipe fixture (not an ordinary crafting playthrough).
 g.processor.current=GameData.recipe_by_id("cook").duplicate(true)
 g.processor.progress=0.0
 g.processor.work(10.0,func(_field):return 1.0)
 check(g.processor.output.size()>0 and g.base.parts==initial,"real processor completes output without machine deterioration")
 g.processor.current={};g.processor.output.clear()
 for id in ["sandstorm","heatwave","coldsnap"]:
  g.director.active.clear();g.director.forecast.clear()
  g.director.trigger(id,false)
  g.base.wear_by(3600.0,100000.0)
  g.base.wear(GameData.Part.MACHINE,10000.0)
  check(g.base.parts==initial,"ordinary weather does not damage parts: "+id)
 check(g.director.food_mult()>1.0 and g.director.speed_mult()<1.0,"ordinary weather food/speed debuffs remain")
 var before_heat:float=g.base.fuel
 g.director.tick(1.0,0.0)
 check(g.base.fuel<before_heat,"cold weather heating still consumes fuel")
 g.director.active.clear();g.director.forecast.clear()
 g.base.parts=initial.duplicate() # reset boundary fixture before trigger tests
 var unchanged:Dictionary=g.base.parts.duplicate()
 for i in 30:g.director.trigger("breakdown",false)
 check(g.base.parts==unchanged,"explicit random-breakdown trigger is inert")
 var selected_breakdown:=false
 for i in 1000:
  if g.director._pick()=="breakdown":selected_breakdown=true
 check(not selected_breakdown,"random event selection excludes unexplained breakdown")
 var disabled:bool=not bool(load("res://scripts/game_data.gd").get_script_constant_map().get("ENABLE_RANDOM_BREAKDOWNS",true))
 check(disabled,"random breakdown policy explicitly disabled")
 if disabled:
  g.director.forecast.append({"id":"breakdown","left":0.1})
  g.director.active.append({"id":"breakdown","left":1.0,"total":1.0,"stance":"","spawned":0,"flee_t":0.0})
  g.director.tick(1.0,0.0)
  check(g.base.parts==unchanged and g.director.forecast.is_empty() and g.director.active.is_empty(),"legacy breakdown forecast/active removed without damage or crash")
 # Attack fixture: restore numeric budget only, then invoke existing attack entry.
 g.base.parts=initial.duplicate();g.base.fuel=100.0
 g.game_over=false;paused=false
 var before:Dictionary=g.base.parts.duplicate()
 var enemy=Enemy.new()
 enemy.setup_kind(g,"scorpion")
 enemy.hold_x=g.base.rear_engine_attack_point().x
 enemy.position=Vector2(enemy.hold_x,1000.0) # fixture separates nearby worker injury from vehicle damage
 g.enemies_root.add_child(enemy)
 for i in 45:enemy._process(1.0)
 enemy.free()
 check(g.base.parts[GameData.Part.HULL]<before[GameData.Part.HULL] and g.base.parts[GameData.Part.DRIVE]<before[GameData.Part.DRIVE],"existing Enemy attack ticks still damage HULL and DRIVE")
 check(g.base.engine_leaking(),"rear attack damage still triggers independent fuel leak")
 var leak_fuel:float=g.base.fuel
 g.base.leak_fuel(2.0,0.0)
 check(g.base.fuel<leak_fuel,"attack-caused leak persists at rest")
 var damaged:Dictionary=g.base.parts.duplicate()
 var rear:float=g.base.rear_engine_damage
 var saved=SaveGame.capture(g)
 check(SaveGame.validate(saved,g) and SaveGame.apply(g,saved),"existing damaged snapshot loads through existing SaveGame API")
 check(g.base.parts==damaged and g.base.rear_engine_damage==rear,"loading damaged save never heals prior damage")
 # Travel to the existing town and exercise both material and money repair APIs.
 g.world.request("a_start")
 for i in 2000:
  g._process(0.2)
  if g.world.phase=="stopped" and g.world.region=="a_start":break
 g.storage.add_item(GameData.Item.REPAIR_KIT,1,Inventory.SOURCE_PURCHASE) # explicit transaction fixture budget
 g.town.credits=1000 # fixture budget, not earned-income evidence
 var kits:int=g.storage.count_of(GameData.Item.REPAIR_KIT)
 var drive:float=g.base.parts[GameData.Part.DRIVE]
 var kit_quote=g.town.quote("repair_item",GameData.Part.DRIVE,1)
 check(kit_quote.ok and g.town.execute(kit_quote) and g.storage.count_of(GameData.Item.REPAIR_KIT)==kits-1 and g.base.parts[GameData.Part.DRIVE]>drive,"existing town material repair consumes one kit and restores attacked drive")
 var cr:int=g.town.credits
 var money_quote=g.town.quote("repair_cash",GameData.Part.DRIVE,99)
 check(money_quote.ok and g.town.execute(money_quote) and g.town.credits<cr and not g.base.engine_leaking(),"existing paid repair consumes Cr and resolves rear attack leak")
 var hull_quote=g.town.quote("repair_cash",GameData.Part.HULL,99)
 check(hull_quote.ok and g.town.execute(hull_quote),"existing paid HULL repair remains useful after attack")
 # Existing C clock: elapsed, hunger and damage authority remain intact.
 for dest in ["b_forest","c_quarry"]:
  g.world.request(dest)
  for i in 2000:
   g._process(0.2)
   if g.world.phase=="stopped" and g.world.region==dest:break
 var made=load("res://bridge/route_connection_session.gd").create_from_game(g,"attack-only-life",{})
 check(made.ok,"C recovery session remains available")
 if made.ok:
  var s=made.session
  var c=load("res://bridge/field_survival_clock.gd").new()
  c.setup(g,s)
  g.workers[0].hunger=80.0;s.actors["worker:0"].hunger=80.0
  var et:float=g.director.elapsed
  var oldparts:Dictionary=g.base.parts.duplicate()
  for i in 300:c.tick(0.2)
  check(is_equal_approx(g.director.elapsed-et,s.elapsed) and is_equal_approx(s.elapsed,s.life_clock_paid),"C field clock is exactly-once, not disabled")
  check(g.base.parts==oldparts and g.workers[0].hunger<80.0,"C passive wear stops while hunger continues")
 g.free()
 print("ATTACK ONLY failures=",fails)
 quit(1 if fails else 0)
