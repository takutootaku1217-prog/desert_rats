extends "res://tools/test_world_flow.gd"
func _initialize():
 seed(diagnostic_seed());main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed());root.add_child(main);await main.ready
 seed(diagnostic_seed());Engine.time_scale=12
 print("DIAGNOSTIC_SEED ",diagnostic_seed())
 print("BATCH_FLOW 通常初期物資と出来事、素材注入なし、既存F操作と地域移動/保存。")
 main.request_build("workbench")
 if not await wait_for("作業台完成",func():return main.has_facility("workbench"),600):finish();return
 if not await go("east_sands"):finish();return
 if not await wait_for("既存採取で木材3を確保",func():return main.storage.count_of(GameData.Item.WOOD)>=3,400):finish();return
 if main.request_transfer(GameData.Item.WOOD,3,"to_workshop")!=3:fail("材料運搬拒否");finish();return
 if not await wait_for("木材3を作業場へ",func():return main.processor.stock.count(GameData.Item.WOOD)==3,200):finish();return
 var crafted:int=main.total_crafted_by_hand
 if main.request_craft("firewood",3)!=3:fail("まとめ製作拒否");finish();return
 var before:=SaveGame.capture(main)
 if not SaveGame.write(main,"user://batch-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://batch-flow.json")) or SaveGame.capture(main)!=before:fail("予約保存復元");finish();return
 if not await go("central_trade"):finish();return
 if not await wait_for("移動後に3回分を完了回収",func():return main.total_crafted_by_hand==crafted+3 and main.processor.output.is_empty() and main.workers.all(func(w):return w.carry_source!=Inventory.SOURCE_PROCESSING or w.carrying<0),300):finish();return
 if main.processor.stock.count(GameData.Item.WOOD)!=0:fail("材料未消費")
 if main.cancel_manual_craft("firewood")!=0:fail("完了後に余分な予約")
 finish()
