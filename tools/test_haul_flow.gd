extends "res://tools/test_world_flow.gd"
func _initialize():
 seed(diagnostic_seed())
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed());root.add_child(main);await main.ready
 seed(diagnostic_seed());Engine.time_scale=12
 print("DIAGNOSTIC_SEED ",diagnostic_seed())
 print("HAUL_FLOW 通常初期物資・既定出来事・実AI・定期保存復元。数量注入なし。")
 main.request_build("workbench")
 # 新仕様: プレイヤーが必要な道具・精錬回数を有限注文する。
 for id in ["tool_wood_pick","tool_hammer","tool_wood_axe","tool_axe"]: main.request_order(id,1)
 main.request_order("smelt",12)
 if not await wait_for("作業台完成",func():return main.has_facility("workbench"),600):finish();return
 main.workers[0].set_priority(GameData.Job.HUNT,5)
 if not await go("east_sands"):finish();return
 if not await go("central_trade"):finish();return
 if not await wait_for("狩猟と獲物回収で皮を確保",func():return main.storage.count_of(GameData.Item.HIDE)>=1,450):finish();return
 main.workers[0].set_priority(GameData.Job.HUNT,3)
 for item in [GameData.Item.WOOD,GameData.Item.HIDE]:
  var n:int=GameData.recipe_by_id("haul_frame")["in"][item]
  if not await wait_for("素材確保 "+ItemDB.name_of(item),func():return main.storage.count_of(item)>=n,450):finish();return
  if main.request_transfer(item,n,"to_workshop")!=n:fail("運搬拒否");finish();return
  if not await wait_for("作業場へ "+ItemDB.name_of(item),func():return main.processor.stock.count(item)>=n,200):finish();return
 if not await go("old_mine"):finish();return
 if not main.quarry.select():fail("鉱床選択拒否");finish();return
 if not await wait_for("鉱床到着",func():return main.quarry.state=="parked",300):finish();return
 if not await wait_for("近場12単位を採取",func():return main.quarry.group_left("近場")==0,900):finish();return
 main.quarry.request_departure()
 if not await wait_for("鉱床帰還",func():return main.quarry.crew_ready_to_leave(),300):finish();return
 if main.quarry.loose.is_empty():main.quarry.leave()
 else:main.quarry.discard_and_leave(main.quarry.loose.duplicate())
 if not await wait_for("鉱山入口復帰",func():return main.quarry.state=="road",300):finish();return
 for item in [GameData.Item.IRON]:
  var n:int=GameData.recipe_by_id("haul_frame")["in"][item]
  if not await wait_for("素材確保 "+ItemDB.name_of(item),func():return main.storage.count_of(item)>=n,450):finish();return
  if main.request_transfer(item,n,"to_workshop")!=n:fail("運搬拒否");finish();return
  if not await wait_for("作業場へ "+ItemDB.name_of(item),func():return main.processor.stock.count(item)>=n,200):finish();return
 if main.request_craft("haul_frame",1)!=1:fail("製作拒否");finish();return
 if not await wait_for("フレーム製作・収納",func():return main.storage.count_of(GameData.Item.HAUL_FRAME)==1,300):finish();return
 var a=main.workers[0]
 if not main.equip_work_support(a):fail("装備拒否");finish();return
 var data:=SaveGame.capture(main)
 if not SaveGame.write(main,"user://haul-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://haul-flow.json")) or SaveGame.capture(main)!=data:fail("装備保存復元");finish();return
 if a.carry_limit()!=5:fail("装備効果なし");finish();return
 if not main.unequip_work_support(a) or not main.equip_work_support(main.workers[1]):fail("持替え拒否");finish();return
 if not await go("central_trade"):finish();return
 if main.workers[1].work_support!=GameData.Item.HAUL_FRAME:fail("道中保存後の所有不一致")
 stages.append("製作→装備→保存→解除→持替え→地域移動を完了")
 finish()
