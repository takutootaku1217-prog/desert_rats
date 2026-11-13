extends SceneTree
## Second-process compatibility check. Producer is test_site_transfer_contract.
var failures:=0
func _init() -> void:call_deferred("_run")
func _check(ok:bool,label:String) -> void:
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func _run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 var main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var saved:=SaveGame.read("user://site-transfer-contract.json")
 _check(not saved.is_empty() and SaveGame.apply(main,saved),"new engine process loads transfer file")
 if not saved.is_empty():
  _check(main.storage.inventory.count(GameData.Item.WOOD)==4,"vehicle keeps post-transfer stock across restart")
  _check(main.world.site_store("b_forest")=={GameData.Item.WOOD:1} and main.world.site_store("d_yard")=={GameData.Item.STONE:2},"B and D stores restore separately")
  var before:Dictionary=main.world.site_stores.duplicate(true)
  main.map_ui.open();main.map_ui.close()
  _check(main.world.site_stores==before and main.storage.inventory.count(GameData.Item.WOOD)==4,"opening and closing map cannot replay transfer")
  _check(SaveGame.apply(main,saved) and main.world.site_stores==before and main.storage.inventory.count(GameData.Item.WOOD)==4,"reloading the same snapshot does not replay transfer")
  main.world.region="b_forest"
  _check(main.world.withdraw_from_site(GameData.Item.WOOD,1)==1,"transient mutation guard is clear after restart")
  _check(main.storage.inventory.count(GameData.Item.WOOD)==5 and main.world.site_store("b_forest").is_empty(),"post-restart withdrawal transfers once without duplication")
  _check(main.world.withdraw_from_site(GameData.Item.WOOD,1)==0,"empty site cannot withdraw again after restart")
 main.queue_free();await process_frame
 SaveGame.disabled=false
 print("SITE TRANSFER RESTART failures=",failures)
 quit(1 if failures else 0)
