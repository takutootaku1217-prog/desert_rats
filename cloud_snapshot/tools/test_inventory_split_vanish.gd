extends SceneTree
## Inventory actions with split stacks while a button is held (viewport pointer events, not OS input):
## when the selected split stack disappears from the live stock, the action must be cancelled safely.
## It must never be redirected to the surviving stack of the same item (reservation, discard, split).
## A partial reduction of the selected stack still acts on the live count.
var main
var ui
var checks := 0
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const OUTSIDE := Vector2(20, 700)
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func finish() -> void:
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
func pointer(point: Vector2, down: bool) -> void:
 var motion := InputEventMouseMotion.new()
 motion.position = point
 root.push_input(motion, true)
 var event := InputEventMouseButton.new()
 event.position = point
 event.global_position = point
 event.button_index = MOUSE_BUTTON_LEFT
 event.pressed = down
 root.push_input(event, true)
 await process_frame
func settle() -> void:
 for i in 3: await process_frame
func tick() -> void:
 ui._process(0.25)
 await process_frame
func stacks_of(item:int) -> Array:
 var out:Array=[]
 for s in ui._model().stacks:
  if s.item==item: out.append(s)
 return out
## Fixture: 10 wood split into [6,4] on the chosen tab; the second stack (4) is selected.
func fixture(tab:int) -> void:
 ui.close()
 ui._set_tab(0)
 ui._query="";ui._search.text=""
 ui._models=[InventoryModel.new(), InventoryModel.new()]
 ui._sel=-1;ui._qty_val=1
 main.storage.inventory.counts={WOOD:10,STONE:3} if tab==0 else {STONE:3}
 main.processor.stock.counts={} if tab==0 else {WOOD:10}
 main.transfer_queue.clear()
 ui.open()
 await settle()
 ui._set_tab(tab);await settle()
 var first:int=-1
 for i in ui._model().stacks.size():
  if ui._model().stacks[i].item==WOOD: first=i;break
 check(ui._model().split(first,4),"fixture(tab %d): wood split into [6,4]"%tab)
 ui._refresh(true);await settle()
 ui._select(first+1);await settle()
 ui._qty.set_value(3)
 check(ui.selected_stack()!=null and ui.selected_stack().n==4 and ui._qty.value==3,"fixture(tab %d): second stack (4) selected, quantity 3"%tab)
func live_set(tab:int, n:int) -> void:
 if tab==0: main.storage.inventory.counts[WOOD]=n
 else: main.processor.stock.counts[WOOD]=n
func decide_button():
 for c in ui._split_box.get_children():
  if c is Button: return c
 return null
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261114);root.add_child(main);await process_frame
 root.size = Vector2i(1280, 720)
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers: w.stop_work()
 ui=main.inventory_ui
 ui.process_mode=Node.PROCESS_MODE_ALWAYS
 ui.set_process(false)
 # --- move: the selected split stack vanishes (both tabs); the surviving stack must not receive the request
 for tab in [0,1]:
  await fixture(tab)
  var mp:Vector2=ui._move_btn.get_global_rect().get_center()
  await pointer(mp,true)
  live_set(tab,3)
  await tick()
  await pointer(mp,false)
  check(main.transfer_queue.is_empty(),"tab %d move: no reservation is made for the surviving stack of the same item"%tab)
  await tick()
  var surv:Array=stacks_of(WOOD)
  check(surv.size()==1 and surv[0].n==3 and ui.selected_stack()==surv[0],"tab %d move: afterwards the survivor is selected (safe fallback)"%tab)
  check(ui._qty_val==1 and ui._qty.value==1,"tab %d move: the held quantity is reset, not carried over"%tab)
  check(String(ui._msg_text).contains("なくなりました"),"tab %d move: the user is told the selection disappeared"%tab)
 # --- move: partial reduction keeps acting on the live count of the selected stack
 await fixture(0)
 var mp2:Vector2=ui._move_btn.get_global_rect().get_center()
 await pointer(mp2,true)
 live_set(0,7)
 await tick()
 await pointer(mp2,false)
 check(main.transfer_queue.size()==1 and int(main.transfer_queue[0]["n"])==1 and main.transfer_queue[0]["item"]==WOOD,"move, partial (4→1): only the live 1 of the selected stack is requested")
 # --- discard: the selected split stack vanishes; no confirmation for the surviving stack
 await fixture(0)
 var dp:Vector2=ui._discard_btn.get_global_rect().get_center()
 await pointer(dp,true)
 live_set(0,3)
 await tick()
 await pointer(dp,false)
 check(not ui._discard_dialog.visible and ui._discard_snapshot.is_empty(),"discard: no confirmation opens for the surviving stack")
 check(main.storage.count_of(WOOD)==3 and main.storage.count_of(STONE)==3,"discard: nothing is discarded")
 await tick()
 check(not ui._discard_dialog.visible and ui.selected_stack()!=null and ui.selected_stack().n==3,"discard: afterwards the survivor is selected, still no confirmation")
 # --- split: the selected split stack vanishes; no split is applied to the survivor
 await fixture(0)
 ui._split_btn.pressed.emit();await settle()
 ui._split_qty.set_value(2)
 var ok_btn=decide_button()
 var op:Vector2=ok_btn.get_global_rect().get_center()
 await pointer(op,true)
 live_set(0,3)
 await tick()
 await pointer(op,false)
 check(not String(ui._msg_text).contains("に分けた"),"split: no 'split done' result is reported for the vanished stack")
 await tick()
 var surv2:Array=stacks_of(WOOD)
 check(surv2.size()==1 and surv2[0].n==3 and String(ui._msg_text).contains("なくなりました"),"split: the survivor is untouched (one stack of 3) and the user is told")
 # --- normal split still works exactly once
 await fixture(0)
 ui._split_btn.pressed.emit();await settle()
 ui._split_qty.set_value(2)
 var ok2=decide_button()
 var op2:Vector2=ok2.get_global_rect().get_center()
 await pointer(op2,true)
 await pointer(op2,false)
 var ws:Array=stacks_of(WOOD)
 check(ws.size()==3 and ws[1].n==2 and ws[2].n==2 and ws[0].n==6,"normal split: [6,4] becomes [6,2,2] exactly once")
 # --- gestures and refresh never change stock, reservations or save by themselves
 await fixture(0)
 main.transfer_queue.append({"item":WOOD,"n":2,"dir":"to_workshop"})
 var row_before:Dictionary=main.warehouse_stock_row(WOOD)
 var queue_before:Array=main.transfer_queue.duplicate(true)
 var counts_before:Dictionary=main.storage.inventory.counts.duplicate()
 var save_before:=SaveGame.capture(main)
 var qp:Vector2=ui._qty._btns[1].get_global_rect().get_center()
 await pointer(qp,true)
 await tick()
 await pointer(OUTSIDE,false)
 await tick()
 check(main.storage.inventory.counts==counts_before and main.warehouse_stock_row(WOOD)==row_before and main.transfer_queue==queue_before,"cancelled press + refresh: stock, reservation and queue unchanged")
 check(SaveGame.capture(main)==save_before,"cancelled press + refresh: save state unchanged")
 main.queue_free();await process_frame
 finish()
