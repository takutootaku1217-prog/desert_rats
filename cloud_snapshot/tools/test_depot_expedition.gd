extends SceneTree
## Depot (site storage) -> expedition prep summary. Real Main/WorldTrip, explicit fixtures.
## Read-only summary must never move, create or destroy goods or alter saves.
var main
var checks := 0
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const Guide = preload("res://ui/first_loop_guide.gd")

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func total_goods() -> int:
 var n:int=main.storage.count_of(WOOD)+main.storage.count_of(STONE)
 for site in main.world.site_stores:
  n+=int(main.world.site_stores[site].get(WOOD,0))+int(main.world.site_stores[site].get(STONE,0))
 return n
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261112);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers: w.stop_work()
 main.world.phase="stopped";main.world.region="d_yard"
 main.storage.inventory.counts={WOOD:10,STONE:6}
 check(main.world.depot_status().contains("未設置"),"no depot built: summary says unbuilt")
 main.world.region_state.lots["d_yard"]=WorldTrip.REGION_A_BUILD["d_yard"].lot
 main.world.site_stores["d_yard"]={}
 var s0:String=main.world.depot_status()
 check(s0.contains("貨物設備") and s0.contains("空（0/36）"),"built empty depot shows capacity 0/36")
 var before_goods:=total_goods()
 check(main.world.deposit_to_site(WOOD,4)==4 and main.world.deposit_to_site(STONE,2)==2,"normal deposit moves goods")
 var s1:String=main.world.depot_status()
 check(s1.contains("木材4") and s1.contains("石2") and s1.contains("（6/36）"),"non-empty depot lists stock and fill")
 check(s1.contains("積載空き") and s1.contains("自動では運ばれない"),"summary explains room and that stock is not auto-carried")
 check(total_goods()==before_goods,"deposit conserves goods across vehicle+depot")
 var cap_before:=SaveGame.capture(main)
 for i in 3: main.world.depot_status()
 check(SaveGame.capture(main)==cap_before,"summary is read-only (save state unchanged)")
 check(main.world.withdraw_from_site(WOOD,4)==4 and total_goods()==before_goods,"withdraw returns goods, total conserved")
 check(main.world.depot_status().contains("石2") and not main.world.depot_status().contains("木材"),"summary tracks withdrawal")
 var d:=SaveGame.capture(main)
 check(SaveGame.validate(d,main) and SaveGame.apply(main,d) and main.world.depot_status()==main.world.depot_status() and main.world.site_stores["d_yard"].get(STONE,0)==2,"restore keeps depot stock and summary")
 main.storage.inventory.counts[GameData.Item.FOOD]=3
 main.world.region_completion.completed=true
 var tip:Dictionary=Guide.snapshot(main).next_step
 check(tip.get("id","")=="free_play" and str(tip.get("body","")).contains("地点保管") and str(tip.body).contains("石2"),"post-clear guide surfaces depot stock for the next outing")
 main.queue_free();await process_frame
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
