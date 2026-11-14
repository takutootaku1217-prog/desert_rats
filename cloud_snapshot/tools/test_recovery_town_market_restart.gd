extends SceneTree
## Restart phase (a NEW Godot process) of test_recovery_town_market_cycle: load the boundary save written after the
## real quarry recovery, sales and purchase, and check that credits, ore and food are exactly as saved, that the town
## market keeps working once, that insufficient-credit purchases and repeated tickets stay rejected, and that the
## recovered ore can be sold, the refuel paid with the earned credits and the base can depart again (real world request).
## Limited check: main runs with process_mode DISABLED and the world is stepped by direct _process calls.
var main
var checks := 0
var failures := 0
const ORE := GameData.Item.IRON_ORE
const FOOD := GameData.Item.FOOD
const FUEL := GameData.Item.FUEL
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func finish() -> void:
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 var path:="user://recovery-town-market-test.json"
 var expect=JSON.parse_string(FileAccess.get_file_as_string("user://recovery-town-market-expect.json"))
 check(expect is Dictionary,"expectation sidecar from the cycle process is readable")
 if not expect is Dictionary: finish(); return
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var before:=FileAccess.get_sha256(path)
 check(SaveGame.apply(main,SaveGame.read(path)),"new process loads the market-boundary save")
 check(FileAccess.get_sha256(path)==before,"loading does not rewrite the save file")
 check(int(main.town.credits)==int(expect["credits"]) and main.storage.count_of(ORE)==int(expect["ore"]) and main.storage.count_of(FOOD)==int(expect["food"]) and main.storage.count_of(FUEL)==int(expect["fuel"]),"restored: credits, ore, food and fuel are exactly as saved (no free refill, nothing lost)")
 check(main.town.location_ok(),"restored: the base is still at the town")
 var credits:int=int(main.town.credits)
 var fuel_before:float=main.base.fuel
 var food_n:int=main.storage.count_of(FOOD)
 var fuel_quote:Dictionary=main.town.quote("buy",FUEL,1)
 check(not bool(fuel_quote.get("ok",false)) and int(main.town.credits)==credits,"after restart an insufficient-credit fuel purchase is still rejected without changing anything")
 var svc:Dictionary=main.town.quote("fuel_cash",-1,1)
 check(not bool(svc.get("ok",false)) and String(svc.get("reason","")).contains("資金不足") and int(main.town.credits)==credits and is_equal_approx(main.base.fuel,fuel_before),"the fuel service is not affordable yet (credits %d < cost %d): rejected, nothing changed"%[credits,int(svc.get("cost",0))])
 # sell the recovered ore left from the real quarry run (this is the real economy path, nothing is injected)
 check(main.storage.count_of(ORE)>=1 and main.storage.count_of(ORE)==int(expect["ore"]),"precondition: the saved recovered ore is available to sell (%d)"%main.storage.count_of(ORE))
 var ticket:Dictionary=main.town.quote("sell",ORE,1)
 check(bool(ticket.get("ok",false)) and main.town.execute(ticket),"after restart a sale of the recovered ore works once")
 check(int(main.town.credits)==credits+3 and main.storage.count_of(ORE)==int(expect["ore"])-1,"the sale pays exactly 3 and removes exactly 1 ore")
 check(not main.town.execute(ticket) and int(main.town.credits)==credits+3,"the same ticket cannot be executed twice")
 # pay for the refuel with the earned credits
 var credits_after_sale:int=int(main.town.credits)
 var svc2:Dictionary=main.town.quote("fuel_cash",-1,1)
 var cost:int=int(svc2.get("cost",-1))
 check(bool(svc2.get("ok",false)) and cost>0 and cost<=credits_after_sale,"the earned credits now cover the fuel service (cost %d)"%cost)
 check(main.town.execute(svc2),"the fuel service is paid and executed")
 check(int(main.town.credits)==credits_after_sale-cost and is_equal_approx(main.base.fuel,GameData.FUEL_CAP) and main.base.fuel>fuel_before,"credits are debited exactly the cost and the tank is full")
 check(not main.town.execute(svc2) and int(main.town.credits)==credits_after_sale-cost,"the same refuel ticket cannot be executed twice")
 var food_quote:Dictionary=main.town.quote("buy",FOOD,1)
 check(not bool(food_quote.get("ok",false)) and main.storage.count_of(FOOD)==food_n,"with the remaining credits a 4-credit food purchase is rejected (insufficient credits), stock unchanged")
 # depart through the real world request and drive the same stepping the cycle test uses
 var credits_dep:int=int(main.town.credits)
 var ore_dep:int=main.storage.count_of(ORE)
 var food_dep:int=main.storage.count_of(FOOD)
 check(main.town.location_ok(),"before departure the base is at the town")
 check(main.world.request("b_forest"),"the real world request to depart for the forest is accepted")
 var arrived:=false
 for frame in 800:
  main._process(0.2)
  if main.world.phase=="stopped" and main.world.region=="b_forest":
   arrived=true;break
  if frame%40==0: await process_frame
 check(arrived,"the base arrives at the forest through the real travel")
 check(not main.town.location_ok(),"after departure the base is no longer at the town")
 check(main.base.fuel>0.0 and main.base.fuel<GameData.FUEL_CAP,"the trip consumed some fuel (tank %.1f, not full, not empty)"%main.base.fuel)
 check(int(main.town.credits)==credits_dep and main.storage.count_of(ORE)==ore_dep and main.storage.count_of(FOOD)==food_dep,"credits, ore and food are unchanged by the trip (nothing refilled for free)")
 main.queue_free();await process_frame
 finish()
