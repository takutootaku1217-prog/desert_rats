extends SceneTree
## Phase A (process 1): a normal transfer request (the same API the inventory/craft UI uses) is carried by the real AI.
## After the warehouse pickup and before the workshop delivery (XFER_MOVE) the game is saved for the restart phase.
## Fixture: the stock (8 hides, 8 food) is set by the test; hide is used because no automatic recipe consumes it alone.
## API input: request_transfer. Ordinary ticking: real frames of the live game (director events off for determinism).
var main
var checks := 0
var failures := 0
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
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 Engine.time_scale=12.0
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261114);root.add_child(main);await process_frame
 main.director.enabled=false
 main.transfer_queue.clear()
 main.storage.inventory.counts={HIDE:8,GameData.Item.FOOD:8}
 main.processor.stock.counts={}
 check(main.request_transfer(HIDE,5,"to_workshop")==5 and main.transfer_queue.size()==1,"normal transfer request of 5 hides accepted")
 var carrier=null
 for i in 6000:
  for w in main.workers:
   if w.ai.state==CharacterAI.State.XFER_MOVE: carrier=w
  if carrier!=null: break
  await process_frame
 Engine.time_scale=1.0
 check(carrier!=null,"a worker picked the hides up at the warehouse and is walking to the workshop (real AI)")
 if carrier==null:
  print("RESULT checks=%d failures=%d" % [checks,failures]); quit(1); return
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var st:int=main.storage.count_of(HIDE)
 var ws:int=main.processor.stock.count(HIDE)
 var cr:int=carried()
 var queued:int=main._queued_transfer(HIDE,"to_workshop")
 check(cr==3 and st==5 and ws==0 and queued==2,"mid-trip state: warehouse 5, carried 3, workshop 0, queued 2 (got %d/%d/%d/%d)"%[st,cr,ws,queued])
 check(st+ws+cr==8,"total hides conserved before the save (8)")
 check(main.transfer_worker==carrier and carrier.carrying==HIDE and carrier.ai.xfer_dir=="to_workshop","the carrier owns the transfer job")
 SaveGame.disabled=false
 var saved:bool=SaveGame.write(main,PATH,true)
 SaveGame.disabled=true
 check(saved,"real save written between pickup and delivery (%s)"%SaveGame.last_error)
 var f:=FileAccess.open("user://transfer-save-expect.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"storage":st,"workshop":ws,"carried":cr,"queued":queued,"carrier":main.workers.find(carrier),"transferred":main.total_transferred}))
 f.close()
 main.queue_free();await process_frame
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
