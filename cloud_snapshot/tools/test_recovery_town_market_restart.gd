extends SceneTree
## Restart phase (a NEW Godot process) of test_recovery_town_market_cycle: load the boundary save written after the
## real quarry recovery, sales and purchase, and check that credits, ore and food are exactly as saved, that the town
## market keeps working once, and that insufficient-credit purchases and repeated tickets stay rejected.
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
 var fuel_quote:Dictionary=main.town.quote("buy",FUEL,1)
 check(not bool(fuel_quote.get("ok",false)) and int(main.town.credits)==credits,"after restart an insufficient-credit purchase is still rejected without changing anything")
 if main.storage.count_of(ORE)>=1:
  var ticket:Dictionary=main.town.quote("sell",ORE,1)
  check(bool(ticket.get("ok",false)) and main.town.execute(ticket),"after restart a sale of the remaining recovered ore works once")
  check(int(main.town.credits)==credits+3 and main.storage.count_of(ORE)==int(expect["ore"])-1,"the sale pays exactly 3 and removes exactly 1 ore")
  check(not main.town.execute(ticket) and int(main.town.credits)==credits+3,"the same ticket cannot be executed twice")
 else:
  check(true,"(no ore left to sell in this save)")
 var credits2:int=int(main.town.credits)
 var food2:int=main.storage.count_of(FOOD)
 var buy:Dictionary=main.town.quote("buy",FOOD,1)
 if bool(buy.get("ok",false)):
  check(main.town.execute(buy) and int(main.town.credits)==credits2-4 and main.storage.count_of(FOOD)==food2+1,"a purchase debits exactly 4 credits and stores exactly 1 food")
 else:
  check(int(main.town.credits)<4,"purchase is rejected only because credits are insufficient")
 main.queue_free();await process_frame
 finish()
