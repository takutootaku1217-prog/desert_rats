extends SceneTree
## Inventory selection stability: the selected stack must survive live stock changes.
## The selection is tracked by stack object identity, not by the list index.
var main
var ui
var checks := 0
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const IRON_ORE := GameData.Item.IRON_ORE
const MEAT := GameData.Item.MEAT
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func finish() -> void:
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
func idx(item:int, nth:=0) -> int:
 var k:=0
 for i in ui._model().stacks.size():
  if ui._model().stacks[i].item==item:
   if k==nth: return i
   k+=1
 return -1
func sel_item() -> int:
 var s=ui.selected_stack()
 return -1 if s==null else int(s.item)
func reset(counts:Dictionary) -> void:
 ui.close()
 ui._set_tab(0)
 ui._query="";ui._search.text=""
 ui._models=[InventoryModel.new(), InventoryModel.new()]
 ui._sel=-1;ui._qty_val=1
 main.storage.inventory.counts=counts
 main.transfer_queue.clear()
 ui.open()
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261114);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers: w.stop_work()
 ui=main.inventory_ui
 # --- 1. earlier stack vanishes: the selected stack is kept (the reported bug)
 reset({WOOD:10,STONE:3,IRON_ORE:2})
 check(ui._model().stacks.size()==3 and idx(STONE)==1,"fixture: wood, stone, iron ore at index 0,1,2")
 ui._select(1);await process_frame
 var picked=ui.selected_stack()
 ui._qty_val=3
 main.storage.inventory.counts.erase(WOOD)
 ui._refresh();await process_frame
 check(ui.selected_stack()==picked and sel_item()==STONE,"earlier stack consumed: selection stays on the same stone stack, not iron ore")
 check(ui._qty_val==3,"unchanged selection keeps the chosen quantity")
 # --- 2. earlier stack consumed to zero then restocked: still the same object
 main.storage.inventory.counts[WOOD]=4
 ui._refresh();await process_frame
 check(ui.selected_stack()==picked and sel_item()==STONE,"new earlier stack inserted: selection still the same stone stack")
 # --- 3. split same-item stacks: identity wins over index/first-of-item
 reset({WOOD:10,STONE:3})
 check(ui._model().split(idx(WOOD),4),"fixture: wood split into two stacks")
 ui._refresh(true);await process_frame
 ui._select(idx(WOOD,1));await process_frame
 var second=ui.selected_stack()
 check(second!=null and second.n==4 and ui._model().stacks[idx(WOOD,0)]!=second,"fixture: second wood stack (4) selected")
 main.storage.inventory.counts[MEAT]=2
 ui._refresh();await process_frame
 check(ui.selected_stack()==second,"stack inserted before the split stacks: the same second wood stack stays selected")
 main.storage.inventory.counts.erase(MEAT)
 ui._refresh();await process_frame
 check(ui.selected_stack()==second,"inserted stack removed again: still the same second wood stack")
 # --- 4. selected stack itself disappears while another stack of the item remains
 ui._qty_val=4
 main.storage.inventory.counts[WOOD]=3
 ui._refresh();await process_frame
 check(sel_item()==WOOD and ui.selected_stack()!=second and ui.selected_stack().n==3,"selected split stack consumed: falls back to the remaining stack of the same item")
 check(ui._qty_val==1,"fallback to a different stack resets the carried quantity")
 # --- 5. selected item vanishes entirely: deterministic neighbour fallback, no quantity carry-over
 reset({WOOD:10,STONE:3,IRON_ORE:2})
 ui._select(1);await process_frame
 ui._qty_val=3
 main.storage.inventory.counts.erase(STONE)
 ui._refresh();await process_frame
 check(sel_item()==IRON_ORE,"selected item gone: falls back to the stack now at that position (iron ore)")
 check(ui._qty_val==1,"item gone: carried quantity reset")
 main.storage.inventory.counts.erase(IRON_ORE)
 ui._refresh();await process_frame
 check(sel_item()==WOOD,"last stack gone: falls back to the previous stack")
 main.storage.inventory.counts.clear()
 ui._refresh();await process_frame
 check(ui.selected_stack()==null and ui._sel==-1,"empty list: no selection")
 # --- 6. pending discard confirmation is dropped when its stack vanishes; never redirected
 reset({WOOD:10,STONE:3,IRON_ORE:2})
 ui._select(1);await process_frame
 ui._ask_discard();await process_frame
 check(ui._discard_dialog.visible and int(ui._discard_snapshot.get("item",-1))==STONE,"fixture: discard confirmation open for stone")
 main.storage.inventory.counts.erase(WOOD)
 ui._refresh();await process_frame
 check(ui._discard_dialog.visible and int(ui._discard_snapshot.get("item",-1))==STONE and sel_item()==STONE,"unrelated stack consumed: confirmation stays on the same stone stack")
 main.storage.inventory.counts.erase(STONE)
 ui._refresh();await process_frame
 check(not ui._discard_dialog.visible and ui._discard_snapshot.is_empty(),"selected stack gone: confirmation is cancelled")
 var before_counts:Dictionary=main.storage.inventory.counts.duplicate()
 ui._confirm_discard();await process_frame
 check(main.storage.inventory.counts==before_counts and main.storage.count_of(IRON_ORE)==2,"late confirm after cancel changes no stock (iron ore untouched)")
 # --- 7. active search filter and workshop tab
 reset({WOOD:10,STONE:3,IRON_ORE:2})
 ui._select(1);await process_frame
 var s2=ui.selected_stack()
 ui._search.text="石";ui._search.text_changed.emit("石");await process_frame
 main.storage.inventory.counts.erase(WOOD)
 ui._refresh();await process_frame
 check(ui.selected_stack()==s2,"search active: selection stays on the same stone stack when an earlier stack is consumed")
 ui._search.text="";ui._search.text_changed.emit("");await process_frame
 ui._set_tab(1);await process_frame
 main.processor.stock.counts={WOOD:5,STONE:2,IRON_ORE:1}
 ui._refresh(true);await process_frame
 ui._select(idx(STONE));await process_frame
 var ws=ui.selected_stack()
 main.processor.stock.counts.erase(WOOD)
 ui._refresh();await process_frame
 check(ui.selected_stack()==ws and sel_item()==STONE,"workshop tab: selection stays on the same stone stack")
 ui._set_tab(0);await process_frame
 # --- 8. refresh and selection handling are read-only
 reset({WOOD:10,STONE:3,IRON_ORE:2})
 main.transfer_queue.append({"item":WOOD,"n":4,"dir":"to_workshop"})
 var row_before:Dictionary=main.warehouse_stock_row(WOOD)
 var queue_before:Array=main.transfer_queue.duplicate(true)
 var counts_snapshot:Dictionary=main.storage.inventory.counts.duplicate()
 var save_before:=SaveGame.capture(main)
 ui._select(1);await process_frame
 main.storage.inventory.counts.erase(WOOD)
 main.storage.inventory.counts[WOOD]=10
 ui._refresh();await process_frame
 check(main.storage.inventory.counts==counts_snapshot,"selection/refresh handling leaves stock unchanged")
 check(main.warehouse_stock_row(WOOD)==row_before and main.transfer_queue==queue_before,"owned/reserved/usable and the transfer queue unchanged")
 check(SaveGame.capture(main)==save_before,"save state unchanged by selection handling")
 main.queue_free();await process_frame
 finish()
