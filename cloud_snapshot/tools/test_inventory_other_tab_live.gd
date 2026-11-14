extends SceneTree
## Inventory detail: the "other storage place" quantity (倉庫 x / 作業場 x) follows live stock changes
## on both tabs through a normal refresh, without rebuilding the detail (split box, quantity, search, confirmation stay).
var main
var ui
var checks := 0
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const IRON_ORE := GameData.Item.IRON_ORE
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func finish() -> void:
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
func find_label(node:Node, prefix:String):
 if node is Label and String(node.text).begins_with(prefix): return node
 for c in node.get_children():
  var r=find_label(c,prefix)
  if r!=null: return r
 return null
func txt(prefix:String) -> String:
 var l=find_label(ui._detail,prefix)
 return "<none>" if l==null else String(l.text)
func idx(item:int) -> int:
 for i in ui._model().stacks.size():
  if ui._model().stacks[i].item==item: return i
 return -1
func reset(storage:Dictionary, workshop:Dictionary) -> void:
 ui.close()
 ui._set_tab(0)
 ui._query="";ui._search.text=""
 ui._models=[InventoryModel.new(), InventoryModel.new()]
 ui._sel=-1;ui._qty_val=1
 main.storage.inventory.counts=storage
 main.processor.stock.counts=workshop
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
 # --- warehouse tab selected: workshop quantity must follow
 reset({WOOD:10,STONE:3},{WOOD:4,IRON_ORE:1})
 ui._select(idx(WOOD));await process_frame
 check(txt("倉庫 ×")=="倉庫 ×10" and txt("作業場 ×")=="作業場 ×4","fixture: warehouse tab shows 倉庫 ×10 / 作業場 ×4")
 main.processor.stock.counts[WOOD]=1
 ui._refresh();await process_frame
 check(txt("作業場 ×")=="作業場 ×1","workshop stock consumed: 作業場 label follows on a normal refresh")
 main.processor.stock.counts[WOOD]=9
 ui._refresh();await process_frame
 check(txt("作業場 ×")=="作業場 ×9","workshop stock added: 作業場 label follows")
 main.processor.stock.counts.erase(WOOD)
 ui._refresh();await process_frame
 check(txt("作業場 ×")=="作業場 ×0","workshop stock gone: 作業場 label shows 0")
 main.storage.inventory.counts[WOOD]=7
 ui._refresh();await process_frame
 check(txt("倉庫 ×")=="倉庫 ×7","same-side change still updates 倉庫 label")
 # --- workshop tab selected: warehouse quantity must follow
 reset({WOOD:10,STONE:3},{WOOD:5,STONE:2})
 ui._set_tab(1);await process_frame
 ui._select(idx(WOOD));await process_frame
 check(txt("倉庫 ×")=="倉庫 ×10" and txt("作業場 ×")=="作業場 ×5","fixture: workshop tab shows 倉庫 ×10 / 作業場 ×5")
 main.storage.inventory.counts[WOOD]=2
 ui._refresh();await process_frame
 check(txt("倉庫 ×")=="倉庫 ×2","warehouse stock consumed: 倉庫 label follows on a normal refresh")
 main.storage.inventory.counts[WOOD]=12
 ui._refresh();await process_frame
 check(txt("倉庫 ×")=="倉庫 ×12","warehouse stock added: 倉庫 label follows")
 main.storage.inventory.counts.erase(WOOD)
 ui._refresh();await process_frame
 check(txt("倉庫 ×")=="倉庫 ×0","warehouse stock gone: 倉庫 label shows 0")
 # --- the update does not rebuild the detail or disturb state
 reset({WOOD:10,STONE:3},{WOOD:4})
 ui._select(idx(WOOD));await process_frame
 var qty_node=ui._qty
 var split_node=ui._split_box
 ui._qty.set_value(3)
 ui._split_btn.pressed.emit();await process_frame
 var split_open:bool=ui._split_box.visible
 ui._split_qty.set_value(2,false)
 ui._ask_discard();await process_frame
 var dialog_open:bool=ui._discard_dialog.visible
 var snap_before:Dictionary=ui._discard_snapshot.duplicate()
 var sel_before=ui.selected_stack()
 var col_before:Color=find_label(ui._detail,"作業場 ×").get_theme_color("font_color")
 main.processor.stock.counts[WOOD]=2
 ui._refresh();await process_frame
 check(txt("作業場 ×")=="作業場 ×2","fixture: label updated while split box and confirmation are open")
 check(ui._qty==qty_node and ui._split_box==split_node,"detail is not rebuilt (same quantity picker and split box nodes)")
 check(split_open and ui._split_box.visible and ui._split_qty.value==2,"split input stays open with its value")
 check(ui._qty_val==3 and ui.selected_stack()==sel_before,"chosen quantity and selected stack are kept")
 var shown:="<none>"
 for c in ui._qty.get_children():
  if c is Label: shown=String(c.text)
 check(ui._qty.value==3 and shown=="3","the quantity picker keeps its real value and displayed text (3)")
 check(dialog_open and ui._discard_dialog.visible and ui._discard_snapshot==snap_before,"discard confirmation stays open with the same snapshot")
 check(find_label(ui._detail,"作業場 ×").get_theme_color("font_color")==col_before,"label emphasis (current tab vs other tab) unchanged")
 ui._cancel_discard()
 # --- search filter active
 ui._search.text="木";ui._search.text_changed.emit("木");await process_frame
 check(ui._query=="木" and ui.selected_stack()==sel_before,"fixture: search active, same selection")
 main.processor.stock.counts[WOOD]=6
 ui._refresh();await process_frame
 check(txt("作業場 ×")=="作業場 ×6" and ui._query=="木" and ui._search.text=="木","search active: 作業場 label follows, query kept")
 # --- UI refresh is read-only
 var counts_store:Dictionary=main.storage.inventory.counts.duplicate()
 var counts_work:Dictionary=main.processor.stock.counts.duplicate()
 var row_before:Dictionary=main.warehouse_stock_row(WOOD)
 var queue_before:Array=main.transfer_queue.duplicate(true)
 var save_before:=SaveGame.capture(main)
 ui._refresh();ui._refresh();await process_frame
 check(main.storage.inventory.counts==counts_store and main.processor.stock.counts==counts_work,"refresh leaves both stocks unchanged")
 check(main.warehouse_stock_row(WOOD)==row_before and main.transfer_queue==queue_before,"owned/reserved/usable and transfer queue unchanged")
 check(SaveGame.capture(main)==save_before,"save state unchanged by the refresh")
 main.queue_free();await process_frame
 finish()
