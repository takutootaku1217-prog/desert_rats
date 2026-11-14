extends SceneTree
## Phase B (a NEW Godot process): read/apply the save written mid-transfer, then let the real AI deliver with ordinary ticking.
## Deliveries are witnessed independently through the workshop stock's item_added signal (source transfer), not by re-reading counters.
## Variant 1: the waiting queue is cancelled after the restart; the carried goods must still arrive exactly once and nothing else moves.
## Variant 2 (same save applied again): the queue is kept; the rest is delivered by a later trip, each unit exactly once.
var main
var checks := 0
var failures := 0
var deliveries: Array = []
const HIDE := GameData.Item.HIDE
const PATH := "user://transfer-save-test.json"
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func carried() -> int:
 var n := 0
 for w in main.workers:
  if w.carrying == HIDE: n += w.carry_n
 return n
func total() -> int:
 return main.storage.count_of(HIDE)+main.processor.stock.count(HIDE)+carried()
func _delivered(item:int, amount:int, source:String) -> void:
 if item==HIDE and source==Inventory.SOURCE_TRANSFER: deliveries.append(amount)
func load_save(expect:Dictionary) -> bool:
 if main!=null:
  main.queue_free();await process_frame
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 if not SaveGame.apply(main,SaveGame.read(PATH)): return false
 main.director.enabled=false
 deliveries.clear()
 main.processor.stock.item_added.connect(_delivered)
 return true
## Ordinary ticking of the live game until the predicate holds (bounded).
func run_until(pred:Callable, cap:=8000) -> bool:
 main.process_mode=Node.PROCESS_MODE_INHERIT
 Engine.time_scale=12.0
 var ok:=false
 for i in cap:
  if pred.call(): ok=true;break
  await process_frame
 Engine.time_scale=1.0
 main.process_mode=Node.PROCESS_MODE_DISABLED
 return ok
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 var expect=JSON.parse_string(FileAccess.get_file_as_string("user://transfer-save-expect.json"))
 check(expect is Dictionary,"expectation sidecar from process 1 is readable")
 if not expect is Dictionary: quit(1); return
 var before:=FileAccess.get_sha256(PATH)
 # --- variant 1: cancel the waiting queue after the restart
 check(await load_save(expect),"new process reads and applies the mid-transfer save")
 check(FileAccess.get_sha256(PATH)==before,"loading does not rewrite the save file")
 var carrier=main.workers[int(expect["carrier"])]
 check(main.storage.count_of(HIDE)==int(expect["storage"]) and main.processor.stock.count(HIDE)==int(expect["workshop"]) and carried()==int(expect["carried"]) and main._queued_transfer(HIDE,"to_workshop")==int(expect["queued"]),"restored: warehouse 5, workshop 0, carried 3, queued 2")
 check(carrier.ai.state==CharacterAI.State.XFER_MOVE and carrier.carrying==HIDE and carrier.carry_n==3 and main.transfer_worker==carrier,"restored: the same worker is still carrying the 3 hides and owns the job")
 check(total()==8 and deliveries.is_empty(),"restored: total 8, nothing delivered by loading")
 main.cancel_transfers()
 check(main.transfer_queue.is_empty() and carried()==3 and total()==8,"cancelling the waiting queue does not remove the goods being carried")
 check(await run_until(func(): return carrier.ai.state!=CharacterAI.State.XFER_MOVE),"the carrier finishes the trip with ordinary ticking")
 check(deliveries==[3],"exactly one delivery of 3 was witnessed at the workshop (events %s)"%str(deliveries))
 check(main.processor.stock.count(HIDE)==3 and main.storage.count_of(HIDE)==5 and carried()==0 and total()==8,"after delivery: workshop 3, warehouse 5, carried 0, total 8")
 check(carrier.carrying==-1 and main.transfer_worker==null,"the carrier and the job owner are released")
 check(int(main.total_transferred)==int(expect["transferred"])+3,"transfer counter grew by exactly the witnessed 3")
 await run_until(func(): return false,600)
 check(deliveries==[3] and main.processor.stock.count(HIDE)==3 and main.storage.count_of(HIDE)==5 and total()==8,"waiting longer: no second delivery and the cancelled remainder stays in the warehouse")
 # --- variant 2: the same save again, queue kept
 check(await load_save(expect),"the same save is applied again (fresh state)")
 check(total()==8 and carried()==3 and main._queued_transfer(HIDE,"to_workshop")==2 and deliveries.is_empty(),"re-applied: same mid-trip state, no accumulation")
 check(await run_until(func(): return main.processor.stock.count(HIDE)>=5 and carried()==0),"with the queue kept, the remaining 2 are carried by a later trip")
 var sum:=0
 for d in deliveries: sum+=int(d)
 check(deliveries.size()==2 and int(deliveries[0])==3 and sum==5,"witnessed deliveries: first 3, then 2; each unit once (events %s)"%str(deliveries))
 check(main.processor.stock.count(HIDE)==5 and main.storage.count_of(HIDE)==3 and total()==8 and main.transfer_queue.is_empty(),"final: workshop 5, warehouse 3, total 8, queue empty")
 check(main.transfer_worker==null and main.workers.all(func(w): return w.carrying!=HIDE),"all carriers released, nobody still holds hides")
 main.queue_free();await process_frame
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
