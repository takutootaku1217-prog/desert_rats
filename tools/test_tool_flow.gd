extends "res://tools/test_world_flow.gd"
func owns_tool(item:int)->bool:
 return main.storage.count_of(item)>0 or main.workers.any(func(w):return w.tools.values().has(item))
# Fの「素材を運ぶ」と同じAPIで必要数だけ確保。自動加工から分離し、採れない鉱床へ持参する。
func prepare_material(item:int,n:int,label:String)->bool:
 var ready:=func()->bool:
  var missing:int=maxi(0,n-main.workshop_count(item)-main.workshop_incoming(item))
  var available:int=main.warehouse_discard_available(item)
  if missing>0 and available>0:
   var requested:int=main.request_transfer(item,mini(missing,available),"to_workshop")
   if requested>0:print("ACTION 作業場へ確保 ",ItemDB.name_of(item)," x",requested)
  return main.workshop_count(item)>=n
 return await wait_for(label,ready,240)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed());root.add_child(main);await main.ready
 Engine.time_scale=12
 print("TOOL_FLOW 新規開始・通常物資・出来事あり・実AI・定期保存再開。素材/道具/設備の注入なし。seed=",diagnostic_seed())
 if main.storage.count_of(GameData.Item.IRON)!=0 or GameData.TOOL_ITEMS.any(func(it):return owns_tool(it)):fail("初期支給が進行を迂回");finish();return
 for id in ["tool_pick","tool_iron_axe","tool_adv_pick"]:main.recipe_priority[id]=0
 main.request_build("workbench")
 if not await wait_for("木材のみで作業台完成",func():return main.has_facility("workbench"),240):finish();return
 if not await wait_for("木製採掘具を製作・装備",func():return main.workers.any(func(w):return w.tools.get("mine",-1)==GameData.Item.WOOD_PICK),180):finish();return
 if not await go("east_sands"):finish();return
 if not await wait_for("木製斧と石製採掘具を製作",func():return owns_tool(GameData.Item.WOOD_AXE) and owns_tool(GameData.Item.HAMMER),240):finish();return
 if not await wait_for("石の斧を製作",func():return owns_tool(GameData.Item.AXE),180):finish();return
 if not await go("central_trade"):finish();return
 if not await prepare_material(GameData.Item.WOOD,4,"鉱床へ行く前に鉄道具2種の柄用木材4を確保"):finish();return
 if not await go("old_mine"):finish();return
 if not main.quarry.select():fail("鉱床選択拒否");finish();return
 if not await wait_for("鉱床到着",func():return main.quarry.state=="parked",180):finish();return
 if not await wait_for("石製道具で採取した鉄鉱石を精錬",func():return main.storage.count_of(GameData.Item.IRON)>0,240):finish();return
 if not await prepare_material(GameData.Item.IRON,2,"採取した鉄鉱石から鉄2を精錬・運搬"):finish();return
 for id in ["tool_pick","tool_iron_axe"]:
  if main.request_craft(id,1)!=1:fail("鉄製道具の手動製作拒否 "+id);finish();return
 if not await wait_for("鉄製採掘具・斧の製作と装備",func():return main.workers.any(func(w):return w.tools.get("mine",-1)==GameData.Item.PICKAXE) and main.workers.any(func(w):return w.tools.get("chop",-1)==GameData.Item.IRON_AXE),300):finish();return
 var d:=SaveGame.capture(main)
 if not SaveGame.write(main,"user://tool-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://tool-flow.json")) or SaveGame.capture(main)!=d:fail("鉄段階の保存再開不一致")
 stages.append("木→石→鉄と装備・保存再開を完了")
 finish()
