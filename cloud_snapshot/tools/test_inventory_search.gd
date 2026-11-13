extends SceneTree
## Inventory (warehouse) list name search: filters displayed rows only.
## Stock, reservations, selection, save state and the workshop tab's data stay untouched.
var main
var ui
var checks := 0
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const IRON_ORE := GameData.Item.IRON_ORE
const IRON := GameData.Item.IRON
const HAMMER := GameData.Item.HAMMER
const WOOD_AXE := GameData.Item.WOOD_AXE
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func rows() -> int:
 return ui._list.get_child_count()
## Item rows are PanelContainers whose tooltip starts with the item name; notices are Labels.
func names() -> Array:
 var out:Array=[]
 for c in ui._list.get_children():
  if c is PanelContainer: out.append(String(c.tooltip_text).split(" ")[0])
 return out
func search(q:String) -> void:
 ui._search.text=q;ui._search.text_changed.emit(q);await process_frame
func stack_index(item:int) -> int:
 for i in ui._model().stacks.size():
  if ui._model().stacks[i].item==item: return i
 return -1
func finish() -> void:
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261114);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers: w.stop_work()
 main.transfer_queue.clear()
 # 木材, 石, 鉄鉱石, 鉄, 石のハンマー (names chosen so "石" matches at start/middle/end positions)
 main.storage.inventory.counts={WOOD:10,STONE:3,IRON_ORE:2,IRON:1,HAMMER:1}
 main.transfer_queue.append({"item":WOOD,"n":4,"dir":"to_workshop"})
 ui=main.inventory_ui
 ui.open();await process_frame
 check(ui._search is LineEdit,"search field exists")
 if not ui._search is LineEdit:
  finish();return
 var row_before:Dictionary=main.warehouse_stock_row(WOOD)
 var queue_before:Array=main.transfer_queue.duplicate(true)
 var counts_before:Dictionary=main.storage.inventory.counts.duplicate()
 var save_before:=SaveGame.capture(main)
 # --- empty query / partial match / Japanese names
 check(rows()==5 and names().size()==5,"empty query lists every held stack")
 await search("石")
 var n1:=names()
 check(n1.size()==3 and n1.has("石") and n1.has("鉄鉱石") and n1.has("石のハンマー"),"query 石 matches by substring at start/middle/end of the name")
 check(not n1.has("木材") and not n1.has("鉄"),"query 石 hides non-matching names")
 await search("鉄")
 var n2:=names()
 check(n2.size()==2 and n2.has("鉄") and n2.has("鉄鉱石"),"query 鉄 is a partial match (鉄 and 鉄鉱石)")
 await search("鉄鉱")
 check(names()==["鉄鉱石"],"longer partial query narrows to one row")
 await search("  石 ")
 check(names().size()==3,"surrounding whitespace is ignored")
 await search("   ")
 check(rows()==5,"whitespace-only query behaves like empty")
 # --- no match
 await search("存在しない")
 check(rows()==1 and names().is_empty() and ui._list.get_child(0) is Label,"no match shows a single notice row, no item rows")
 check(String(ui._list.get_child(0).text).contains("存在しない"),"notice names the query")
 check(main.storage.count_of(WOOD)==10 and main.storage.count_of(STONE)==3,"no match leaves stock unchanged")
 # --- clear
 await search("")
 check(rows()==5,"clearing the query restores the full list")
 # --- selection survives filtering (row numbers are real stack numbers)
 var si:=stack_index(STONE)
 ui._select(si);await process_frame
 await search("木")
 check(ui._sel==si and ui.selected_stack()!=null and ui.selected_stack().item==STONE,"selection stays on the same stack while it is filtered out")
 check(names().has("木材") and not names().has("石"),"query 木 shows 木材 only (石 filtered out of the list)")
 await search("")
 check(ui._sel==si and ui.selected_stack().item==STONE,"selection is intact after clearing")
 # --- live update while a query is active
 await search("木")
 main.storage.inventory.counts[WOOD_AXE]=1
 ui._refresh(true);await process_frame
 check(names().has("木製の斧") and names().size()==2,"newly held item that matches appears while the query is active")
 main.storage.inventory.counts.erase(WOOD_AXE)
 ui._refresh(true);await process_frame
 await search("")
 # --- signature carries the query (so the list is rebuilt on change)
 var sig_empty:String=ui._signature()
 ui._query="石"
 check(ui._signature()!=sig_empty,"signature changes with the query")
 ui._query=""
 # --- tab switch keeps the query and does not touch the other tab
 await search("石")
 ui._set_tab(1);await process_frame
 check(ui._search.text=="石" and names().all(func(x):return x.contains("石")),"workshop tab applies the same query; only matching names are listed")
 ui._set_tab(0);await process_frame
 check(names().size()==3,"back on the warehouse tab the same query applies again")
 await search("")
 # --- read-only guarantees: stock, reservation, queue, save
 check(main.storage.inventory.counts==counts_before,"stock counts identical after all searches")
 var row_after:Dictionary=main.warehouse_stock_row(WOOD)
 check(row_after==row_before and row_after.reserved==4 and row_after.usable==6,"owned/reserved/usable for 木材 unchanged (10/4/6)")
 check(main.transfer_queue==queue_before,"transfer queue (reservations) unchanged")
 check(SaveGame.capture(main)==save_before,"searching does not change save state")
 main.queue_free();await process_frame
 finish()
