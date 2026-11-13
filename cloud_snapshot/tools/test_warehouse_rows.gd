extends SceneTree
## Warehouse list model: owned / reserved / usable are distinct; name search; read-only.
var main
var checks := 0
var failures := 0
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="": quit(2); return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",20261113);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers: w.stop_work()
 main.transfer_queue.clear()
 main.storage.inventory.counts={WOOD:10,STONE:3}
 var r:Dictionary=main.warehouse_stock_row(WOOD)
 check(r.owned==10 and r.reserved==0 and r.usable==10,"unreserved stock: owned=usable, reserved 0")
 main.transfer_queue.append({"item":WOOD,"n":4,"dir":"to_workshop"})
 r=main.warehouse_stock_row(WOOD)
 check(r.owned==10 and r.reserved==4 and r.usable==6 and r.owned==r.reserved+r.usable,"queued transfer is reserved, not usable; no stock lost")
 check(main.storage.count_of(WOOD)==10,"reading rows does not change warehouse stock")
 var rows:Array=main.warehouse_rows()
 check(rows.size()==2 and rows.all(func(x):return x.owned==x.reserved+x.usable),"list has only held items and balanced counts")
 check(main.warehouse_rows("石").size()==1 and main.warehouse_rows("石")[0].item==STONE,"name search filters rows")
 check(main.warehouse_rows("  ").size()==2 and main.warehouse_rows("存在しない名前").is_empty(),"blank query lists all; unmatched is empty")
 main.transfer_queue.clear()
 main.storage.inventory.counts={WOOD:0}
 check(main.warehouse_rows().is_empty() and main.warehouse_stock_row(WOOD).usable==0,"empty warehouse has no rows and zero usable")
 var before:=SaveGame.capture(main)
 main.warehouse_rows("木");main.warehouse_stock_row(WOOD)
 check(SaveGame.capture(main)==before,"queries are read-only for save state")
 main.queue_free();await process_frame
 print("RESULT checks=%d failures=%d" % [checks,failures])
 quit(1 if failures>0 else 0)
