extends SceneTree
## Inventory UI: the periodic refresh must not rebuild the detail while a button is held,
## so a click is neither swallowed nor redirected. The refresh resumes after release.
## Uses real viewport pointer events (press, stock change + the 0.25s refresh, release).
var main
var ui
var checks := 0
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const IRON_ORE := GameData.Item.IRON_ORE
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
func idx(item:int) -> int:
 for i in ui._model().stacks.size():
  if ui._model().stacks[i].item==item: return i
 return -1
func settle() -> void:
 for i in 3: await process_frame
func reset(counts:Dictionary) -> void:
 ui.close()
 ui._set_tab(0)
 ui._query="";ui._search.text=""
 ui._models=[InventoryModel.new(), InventoryModel.new()]
 ui._sel=-1;ui._qty_val=1
 main.storage.inventory.counts=counts
 main.processor.stock.counts={}
 main.transfer_queue.clear()
 ui.open()
 await settle()
func tick() -> void:
 ui._process(0.25)
 await process_frame
func qty_label_text() -> String:
 for c in ui._qty.get_children():
  if c is Label: return String(c.text)
 return "<none>"
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
 # --- quantity button: control, dirty inside, dirty outside
 for mode in ["control","dirty_inside","dirty_outside"]:
  await reset({WOOD:10,STONE:3})
  ui._select(idx(WOOD));await settle()
  var btn=ui._qty._btns[5]
  var point:Vector2=btn.get_global_rect().get_center()
  check(root.get_visible_rect().has_point(point),mode+": target visible")
  var calls:={"n":0}
  var picker=ui._qty
  picker.changed.connect(func(_v): calls.n+=1)
  await pointer(point,true)
  check(ui._qty_val==1 and calls.n==0,mode+": press alone does not change the quantity")
  if mode!="control":
   main.storage.inventory.counts[WOOD]=9
   await tick()
   check(is_instance_valid(btn) and btn.is_inside_tree() and ui._qty==picker,mode+": detail is not rebuilt while the button is held")
  await pointer(OUTSIDE if mode=="dirty_outside" else point,false)
  var expect:int=1 if mode=="dirty_outside" else 5
  check(ui._qty_val==expect and ui._qty.value==expect,mode+": release gives the intended quantity (state and picker value)")
  check(calls.n==(0 if mode=="dirty_outside" else 1),mode+": callback exactly once, or cancelled outside")
  await tick()
  if mode!="control":
   check(find_label_text("作業場 ×")!="" and ui._model().stacks[idx(WOOD)].n==9,mode+": refresh resumes after release (stack now 9)")
  check(qty_label_text()==str(expect),mode+": displayed quantity matches the value after refresh")
 # --- action button inside: exactly one transfer request
 await reset({WOOD:10,STONE:3})
 ui._select(idx(WOOD));await settle()
 var mv=ui._move_btn
 var mp:Vector2=mv.get_global_rect().get_center()
 await pointer(mp,true)
 main.storage.inventory.counts[WOOD]=9
 await tick()
 check(main.transfer_queue.is_empty(),"move button: nothing requested while held")
 await pointer(mp,false)
 check(main.transfer_queue.size()==1 and int(main.transfer_queue[0]["n"])==1 and main.transfer_queue[0]["item"]==WOOD and main.transfer_queue[0]["dir"]=="to_workshop","move button: exactly one request of 1 wood after release")
 await tick()
 check(main.transfer_queue.size()==1 and int(main.transfer_queue[0]["n"])==1,"move button: no duplicate request after the refresh resumes")
 # --- selected stack vanishes while the move button is held: no transfer of another item
 await reset({WOOD:10,STONE:3,IRON_ORE:2})
 ui._select(idx(STONE));await settle()
 ui._qty.set_value(3)
 var mv2=ui._move_btn
 var mp2:Vector2=mv2.get_global_rect().get_center()
 await pointer(mp2,true)
 main.storage.inventory.counts.erase(STONE)
 await tick()
 await pointer(mp2,false)
 check(main.transfer_queue.is_empty(),"stale move: nothing is moved for the vanished stack or any other item")
 check(main.storage.count_of(WOOD)==10 and main.storage.count_of(IRON_ORE)==2,"stale move: other stock untouched")
 await tick()
 check(ui.selected_stack()!=null and ui.selected_stack().item!=STONE and ui._qty_val==1 and ui._qty.value==1,"stale move: afterwards a safe fallback is selected and the quantity is reset")
 check(main.transfer_queue.is_empty(),"stale move: still nothing requested after the refresh")
 # --- selected stack vanishes while the discard button is held: no confirmation for another item
 await reset({WOOD:10,STONE:3,IRON_ORE:2})
 ui._select(idx(STONE));await settle()
 ui._qty.set_value(3)
 var dp:Vector2=ui._discard_btn.get_global_rect().get_center()
 await pointer(dp,true)
 main.storage.inventory.counts.erase(STONE)
 await tick()
 await pointer(dp,false)
 check(not ui._discard_dialog.visible and ui._discard_snapshot.is_empty(),"stale discard: no confirmation opens for the vanished stack or another item")
 await tick()
 check(not ui._discard_dialog.visible and main.storage.count_of(WOOD)==10 and main.storage.count_of(IRON_ORE)==2,"stale discard: nothing discarded, no confirmation after the refresh")
 # --- quantity button held while the selected stack vanishes: the quantity is not carried to another item
 await reset({WOOD:10,STONE:9,IRON_ORE:8})
 ui._select(idx(STONE));await settle()
 var sq=ui._qty
 var qp2:Vector2=sq._btns[5].get_global_rect().get_center()
 await pointer(qp2,true)
 main.storage.inventory.counts.erase(STONE)
 await tick()
 check(ui._qty==sq,"stale quantity: detail is not rebuilt while held")
 await pointer(qp2,false)
 check(main.transfer_queue.is_empty() and main.storage.count_of(IRON_ORE)==8 and main.storage.count_of(WOOD)==10,"stale quantity: the click only changes the picker, never any stock")
 await tick()
 check(ui.selected_stack()!=null and ui.selected_stack().item==IRON_ORE,"stale quantity: fallback selects the neighbour (iron ore)")
 check(ui._qty_val==1 and ui._qty.value==1 and qty_label_text()=="1","stale quantity: the held 5 is NOT carried to the other item (value and display are 1)")
 # --- partial change while held: transfer and discard re-check the live stock
 await reset({WOOD:10,STONE:3})
 ui._select(idx(STONE));await settle()
 ui._qty.set_value(3)
 var pm:Vector2=ui._move_btn.get_global_rect().get_center()
 await pointer(pm,true)
 main.storage.inventory.counts[STONE]=1
 await tick()
 await pointer(pm,false)
 check(main.transfer_queue.size()==1 and main.transfer_queue[0]["item"]==STONE and int(main.transfer_queue[0]["n"])==1,"partial stale move: only the live 1 stone is requested (not the stale 3)")
 check(main.storage.count_of(STONE)==1 and main.storage.count_of(WOOD)==10,"partial stale move: the request does not touch stock")
 await reset({WOOD:10,STONE:3})
 ui._select(idx(STONE));await settle()
 ui._qty.set_value(3)
 var pd:Vector2=ui._discard_btn.get_global_rect().get_center()
 await pointer(pd,true)
 main.storage.inventory.counts[STONE]=1
 await tick()
 await pointer(pd,false)
 check(not ui._discard_dialog.visible and ui._discard_snapshot.is_empty() and main.storage.count_of(STONE)==1,"partial stale discard: the stale 3 is rejected against the live stock (no confirmation, nothing discarded)")
 # --- gestures and refresh never change stock, reservation or save by themselves
 await reset({WOOD:10,STONE:3})
 main.transfer_queue.append({"item":WOOD,"n":4,"dir":"to_workshop"})
 ui._select(idx(WOOD));await settle()
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
func find_label_text(prefix:String) -> String:
 return _find(ui._detail,prefix)
func _find(node:Node, prefix:String) -> String:
 if node is Label and String(node.text).begins_with(prefix): return String(node.text)
 for c in node.get_children():
  var r:=_find(c,prefix)
  if r!="": return r
 return ""
