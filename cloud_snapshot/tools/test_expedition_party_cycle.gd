extends SceneTree
## Phase A (process 1): a two-member expedition departs while another worker holds a real repair-kit reservation
## and one member holds its own real food reservation (both created by the real AI, not injected).
## The run is saved mid-expedition to user://expedition-party-test.json for the restart phase (a separate Godot process).
## Fixture note: the stock numbers (food, kits) are set up by the test; no supply is added after the departure.
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
 Engine.time_scale=1.0
 quit(1 if failures>0 else 0)
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 Engine.time_scale=12.0
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261114);root.add_child(main);await process_frame
 main.director.enabled=false
 main.transfer_queue.clear()
 main.storage.inventory.counts={FOOD:2,KIT:2}
 main.base.parts[GameData.Part.DRIVE]=20.0
 main.workers[0].hunger=10.0
 var repairer=null
 var eater=null
 for i in 6000:
  for w in main.workers:
   if w.ai.state==CharacterAI.State.REPAIR_TAKE and repairer==null: repairer=w
   if w.ai.state==CharacterAI.State.EAT_TAKE and eater==null and w!=repairer: eater=w
  if repairer!=null and eater!=null and repairer!=eater: break
  await process_frame
 check(repairer!=null and eater!=null and repairer!=eater,"fixture: one worker reserves a kit (REPAIR_TAKE), another reserves food (EAT_TAKE) via the real AI")
 if repairer==null or eater==null or repairer==eater: finish(); return
 Engine.time_scale=1.0
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var third=null
 for w in main.workers:
  if w!=repairer and w!=eater: third=w
 var party:Array=[eater,third]
 main.expedition.state="idle"
 main.expedition.offer("ruins_small")
 # food 2 = exactly the 2 members; only the eater's own reservation covers one of them. kit 2, repairer holds 1.
 check(main.expedition.block_reason(party,"normal",true)=="","two members, own reservation released, other worker's kit reservation kept: departure allowed")
 var kit_reserved_by_other:int=main.base.repair_reserved.size()
 check(main.expedition.start(party,"normal",true),"two-member expedition departs")
 check(main.storage.count_of(FOOD)==0 and main.storage.count_of(KIT)==1,"exactly 2 food and 1 kit consumed")
 check(eater.away and third.away and not repairer.away,"both members away; the repairer stays")
 check(main.base.repair_reserved.size()==kit_reserved_by_other and repairer.ai.state==CharacterAI.State.REPAIR_TAKE,"the repairer's reservation and state are kept; the member's own reservation was released once (no double release)")
 check(main.expedition.state=="running" and main.expedition.party.size()==2 and int(main.expedition.stats["trips"])==1,"expedition running with two members, one trip counted")
 var path:="user://expedition-party-test.json"
 var expect:={"food":main.storage.count_of(FOOD),"kit":main.storage.count_of(KIT),"away":main.workers.map(func(x):return x.away),"party":main.workers.map(func(x):return main.expedition.party.has(x)),"trips":int(main.expedition.stats["trips"]),"kit_flag":main.expedition.kit}
 SaveGame.disabled=false # same as the existing armor save test: writes only to the isolated test home (FLUID_TEST_HOME is set)
 check(SaveGame.write(main,path,true),"mid-expedition save written (%s)"%SaveGame.last_error)
 SaveGame.disabled=true
 var f:=FileAccess.open("user://expedition-party-expect.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(expect));f.close()
 main.queue_free();await process_frame
 finish()
