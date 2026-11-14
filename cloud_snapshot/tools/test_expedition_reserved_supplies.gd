extends SceneTree
## Expedition supplies: food and the repair kit that other crew members have reserved (REPAIR_TAKE / EAT_TAKE)
## or that sit in a queued transfer must not be carried away by an expedition.
## Reservations are created by the real AI (a damaged part / a hungry worker), not injected.
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
func fresh(counts:Dictionary) -> void:
 if main!=null:
  main.queue_free()
  await process_frame
 Engine.time_scale=12.0
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261114);root.add_child(main);await process_frame
 main.director.enabled=false
 main.transfer_queue.clear()
 main.storage.inventory.counts=counts.duplicate()
## Step the live game until a worker reaches the given state (bounded). Returns that worker or null.
func reach(state:int, cap:=4000):
 for i in cap:
  for w in main.workers:
   if w.ai.state==state: return w
  await process_frame
 return null
func freeze() -> void:
 Engine.time_scale=1.0
 main.process_mode=Node.PROCESS_MODE_DISABLED
func offer() -> void:
 main.expedition.state="idle"
 main.expedition.offer("ruins_small")
func other_than(w) -> Array:
 for x in main.workers:
  if x!=w and not x.away and not x.down: return [x]
 return []
func snap() -> Dictionary:
 return {"counts":main.storage.inventory.counts.duplicate(),"queue":main.transfer_queue.duplicate(true),"rr":main.base.repair_reserved.size(),
  "state":main.expedition.state,"party":main.expedition.party.size(),"away":main.workers.map(func(x):return x.away),"save":SaveGame.capture(main)}
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 # --- repair kit: the last kit is reserved by a repairer (REPAIR_TAKE)
 await fresh({FOOD:5,KIT:1})
 main.base.parts[GameData.Part.DRIVE]=20.0
 var a=await reach(CharacterAI.State.REPAIR_TAKE)
 check(a!=null and main.base.repair_reserved.size()>=1,"fixture: a repairer is walking to take the last kit (reservation made by the real AI)")
 if a==null: finish(); return
 freeze()
 offer()
 var party:Array=other_than(a)
 check(party.size()==1 and main.expedition.state=="offered","fixture: another member can be dispatched")
 var before:Dictionary=snap()
 var reason:String=main.expedition.block_reason(party,"normal",true)
 check(reason!="" and reason.contains("修理板"),"last kit reserved by another worker: departure is blocked with a clear reason (%s)"%reason)
 check(main.expedition.start(party,"normal",true)==false,"last kit reserved: start refuses")
 check(snap()==before,"blocked attempt leaves stock, reservations, party, expedition state and save unchanged")
 check(main.expedition.block_reason(party,"normal",false)=="","without bringing the kit the expedition may still depart (food is plentiful)")
 # --- surplus: a second kit makes it possible; exactly one is consumed; the repairer's reservation survives
 main.storage.inventory.counts[KIT]=2
 check(main.expedition.block_reason(party,"normal",true)=="","surplus kit: departure allowed")
 var rr:int=main.base.repair_reserved.size()
 check(main.expedition.start(party,"normal",true),"surplus kit: the expedition starts")
 check(main.storage.count_of(KIT)==1 and main.storage.count_of(FOOD)==4,"surplus kit: exactly one kit and one food consumed")
 check(main.base.repair_reserved.size()==rr and a.ai.state==CharacterAI.State.REPAIR_TAKE,"surplus kit: the other repairer keeps its reservation and state")
 # --- release: once the reservation is gone the last kit can go
 await fresh({FOOD:5,KIT:1})
 main.base.parts[GameData.Part.DRIVE]=20.0
 var a2=await reach(CharacterAI.State.REPAIR_TAKE)
 freeze()
 offer()
 var p2:Array=other_than(a2)
 check(main.expedition.block_reason(p2,"normal",true)!="","fixture 2: blocked while reserved")
 a2.stop_work()
 a2.ai._set_state(CharacterAI.State.IDLE)
 main.base.repair_reserved.clear()
 check(main.expedition.block_reason(p2,"normal",true)=="","reservation released: the last kit may depart")
 # --- the dispatched member's own reservation is released by depart and not double counted
 await fresh({FOOD:5,KIT:1})
 main.base.parts[GameData.Part.DRIVE]=20.0
 var a3=await reach(CharacterAI.State.REPAIR_TAKE)
 freeze()
 offer()
 check(main.expedition.block_reason([a3],"normal",true)=="","own reservation: the member holding the reservation may take that kit")
 check(main.expedition.start([a3],"normal",true),"own reservation: starts")
 check(main.storage.count_of(KIT)==0 and a3.away and not main.base.repair_reserved.values().has(a3),"own reservation: kit consumed once (not negative), reservation released by depart")
 # --- food: reserved by a hungry worker walking to eat (EAT_TAKE)
 await fresh({FOOD:1,KIT:0})
 for w in main.workers: w.hunger=100.0
 main.workers[0].hunger=10.0
 var h=await reach(CharacterAI.State.EAT_TAKE)
 check(h!=null,"fixture: a hungry worker is walking to take the last food (real AI)")
 if h==null: finish(); return
 freeze()
 offer()
 var pf:Array=other_than(h)
 var fb:Dictionary=snap()
 var fr:String=main.expedition.block_reason(pf,"normal",false)
 check(fr!="" and fr.contains("食料"),"last food reserved for eating: departure blocked with a clear reason (%s)"%fr)
 check(main.expedition.start(pf,"normal",false)==false and snap()==fb,"last food reserved: start refuses and nothing changes")
 main.storage.inventory.counts[FOOD]=2
 check(main.expedition.block_reason(pf,"normal",false)=="","surplus food: departure allowed")
 check(main.expedition.start(pf,"normal",false) and main.storage.count_of(FOOD)==1,"surplus food: exactly the needed 1 is consumed")
 # --- queued transfer to the workshop reserves food as well
 await fresh({FOOD:2,KIT:0})
 freeze()
 offer()
 main.transfer_queue.append({"item":FOOD,"n":2,"dir":"to_workshop"})
 var pt:Array=[main.workers[0]]
 var tr:String=main.expedition.block_reason(pt,"normal",false)
 check(tr!="" and tr.contains("食料"),"food reserved by a queued transfer: departure blocked (%s)"%tr)
 main.cancel_transfers()
 check(main.expedition.block_reason(pt,"normal",false)=="","transfer cancelled: departure allowed")
 Engine.time_scale=1.0
 main.queue_free();await process_frame
 finish()
