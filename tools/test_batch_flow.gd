extends "res://tools/test_world_flow.gd"
func _initialize():
 seed(diagnostic_seed());main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed());root.add_child(main);await main.ready
 seed(diagnostic_seed());Engine.time_scale=12
 print("DIAGNOSTIC_SEED ",diagnostic_seed())
 print("BATCH_FLOW 通常初期物資と出来事、素材注入なし、既存F操作と地域移動/保存。")
 main.refill_settings[GameData.Item.FUEL].enabled=false # この試験の燃料製作は明示注文3回だけ
 main.request_build("workbench")
 # 新仕様: プレイヤーが必要な道具・精錬回数を有限注文する。
 for id in ["tool_wood_pick","tool_hammer","tool_wood_axe","tool_axe"]: main.request_order(id,1)
 main.request_order("smelt",12)
 if not await wait_for("作業台完成",func():return main.has_facility("workbench"),600):finish();return
 if not await go("east_sands"):finish();return
 if not await wait_for("既存採取で木材3を確保",func():return main.storage.count_of(GameData.Item.WOOD)>=3,400):finish();return
 if main.request_transfer(GameData.Item.WOOD,3,"to_workshop")!=3:fail("材料運搬拒否");finish();return
 if not await wait_for("木材3を作業場へ",func():return main.processor.stock.count(GameData.Item.WOOD)==3,200):finish();return
 var delivered:={"n":0}
 main.storage.inventory.item_added.connect(func(item,n,source):
  if item==GameData.Item.FUEL and source==Inventory.SOURCE_PROCESSING:delivered.n+=n)
 if main.request_craft("firewood",3)!=3:fail("まとめ製作拒否");finish();return
 var before:=SaveGame.capture(main)
 if not SaveGame.write(main,"user://batch-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://batch-flow.json")) or SaveGame.capture(main)!=before:fail("予約保存復元");finish();return
 if not await go("central_trade"):finish();return
 if not await wait_for("移動後に3回分を完了回収",func():return delivered.n==3 and ProductionPlan.future(main,GameData.Item.FUEL)==0 and main.processor.manual_status("firewood").queued==0 and main.processor.output.is_empty() and main.workers.all(func(w):return w.carry_source!=Inventory.SOURCE_PROCESSING or w.carrying<0),300):finish();return
 # 完了時の一致だけでなく、その後60秒も余分な完成・未着手予約がない。
 var settled_until:float=main.director.elapsed+60.0
 while main.director.elapsed<settled_until and not main.game_over:
  await process_frame
 if delivered.n!=3 or ProductionPlan.future(main,GameData.Item.FUEL)!=0 or main.processor.manual_status("firewood").queued!=0:fail("余剰燃料製作・予約を検出")
 if main.processor.stock.count(GameData.Item.WOOD)!=0:fail("材料未消費")
 if main.cancel_manual_craft("firewood")!=0:fail("完了後に余分な予約")
 finish()
