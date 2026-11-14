extends SceneTree
## Phase B (a NEW Godot process): load the mid-expedition save of test_expedition_party_cycle, check the restored state,
## Limited check: main runs with process_mode DISABLED and the expedition is advanced by direct tick() calls,
## so the whole-world clock and consumption are stopped (this is NOT a normal-survival guarantee).
## then run the expedition to its end (success or retreat) and check that supplies, members and loot are applied exactly once.
var main
var checks := 0
var failures := 0
const FOOD := GameData.Item.FOOD
const KIT := GameData.Item.REPAIR_KIT
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func finish() -> void:
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
func total_counts() -> Dictionary:
 return main.storage.inventory.counts.duplicate()
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 var path:="user://expedition-party-test.json"
 var expect=JSON.parse_string(FileAccess.get_file_as_string("user://expedition-party-expect.json"))
 check(expect is Dictionary,"expectation sidecar from process 1 is readable")
 if not expect is Dictionary: finish(); return
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var before:=FileAccess.get_sha256(path)
 check(SaveGame.apply(main,SaveGame.read(path)),"new process loads the mid-expedition save")
 check(FileAccess.get_sha256(path)==before,"loading does not rewrite the save file")
 check(main.expedition.state=="running" and main.expedition.party.size()==2 and int(main.expedition.stats["trips"])==int(expect["trips"]),"restored: running, two members, same trip count")
 check(main.workers.map(func(x):return x.away)==expect["away"] and main.workers.map(func(x):return main.expedition.party.has(x))==expect["party"],"restored: the same members are away; the others are not")
 check(main.storage.count_of(FOOD)==int(expect["food"]) and main.storage.count_of(KIT)==int(expect["kit"]),"restored: supplies are as saved (nothing re-consumed or refunded)")
 var base_counts:=total_counts()
 var kit_in_party:bool=main.expedition.kit
 # run the expedition to its end (deterministic stepping of the same code the game uses)
 var guard:=0
 while main.expedition.state=="running" and guard<50:
  main.expedition.tick(main.expedition.step_time+1.0)
  guard+=1
 check(main.expedition.state=="done","the expedition ends (return or retreat) after %d steps"%guard)
 var loot:Dictionary=main.expedition.loot.duplicate()
 var lost:Dictionary=main.expedition.lost.duplicate()
 var after:=total_counts()
 var exact:=true
 var keys:Dictionary={}
 for it in loot: keys[it]=true
 for it in after: keys[it]=true
 for it in base_counts: keys[it]=true
 for it in keys:
  if int(after.get(it,0))-int(base_counts.get(it,0))!=int(loot.get(it,0)): exact=false
 print("INFO outcome: retreated=%s ok=%d ng=%d loot=%s lost=%s" % [main.expedition.retreated,main.expedition.ok_count,main.expedition.ng_count,loot,lost])
 check(lost.is_empty() and exact,"every loot item reaches the warehouse exactly once (stock delta equals the reported loot, even when the outcome is a retreat with no loot; nothing else changes)")
 check(main.workers.all(func(x):return not x.away),"all members are back (away cleared)")
 check(int(main.expedition.stats["trips"])==int(expect["trips"]),"the trip is counted once")
 var done_counts:=total_counts()
 for i in 10: main.expedition.tick(30.0)
 check(total_counts()==done_counts,"waiting out the result screen changes no stock (nothing applied twice)")
 check(main.expedition.state in ["idle","done"] and main.workers.all(func(x):return not x.away),"state settles; nobody is re-sent")
 # restoring the same save twice yields the same state (idempotent, no accumulation)
 check(SaveGame.apply(main,SaveGame.read(path)) and main.expedition.state=="running" and main.storage.count_of(FOOD)==int(expect["food"]) and main.storage.count_of(KIT)==int(expect["kit"]),"re-applying the same save restores exactly the saved state (no accumulation)")
 check(main.workers.map(func(x):return x.away)==expect["away"],"re-applying restores the same away flags (no double release)")
 main.queue_free();await process_frame
 finish()
