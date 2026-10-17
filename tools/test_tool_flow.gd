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
func make_item(id: String)->bool:
 var recipe:=GameData.recipe_by_id(id)
 for item in recipe["in"]:
  if not await prepare_material(item,recipe["in"][item],id+" 材料確保 "+ItemDB.name_of(item)):return false
 if main.request_craft(id,1)!=1:fail("製作拒否 "+id);return false
 return await wait_for(id+" 製作回収",func():return owns_tool(recipe.out) if recipe.out in GameData.TOOL_ITEMS else main.storage.count_of(recipe.out)>0,240)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed());root.add_child(main);await main.ready
 Engine.time_scale=12
 print("TOOL_FLOW 通常開始3人・有限資源・既定出来事・素材/道具/設備注入なし seed=",diagnostic_seed())
 if main.storage.count_of(GameData.Item.IRON)!=0 or GameData.TOOL_ITEMS.any(func(it):return owns_tool(it)):fail("初期支給が進行を迂回");finish();return
 main.request_build("workbench")
 for id in ["tool_wood_pick","tool_hammer","tool_wood_axe","tool_axe"]:main.request_order(id,1)
 main.request_order("smelt",12)
 if not await wait_for("木のみの作業台",func():return main.has_facility("workbench"),240):finish();return
 if not await wait_for("木製採掘具→石製採掘具",func():return owns_tool(GameData.Item.HAMMER),300):finish();return
 if not await wait_for("木製斧・石製斧を通常製作",func():return owns_tool(GameData.Item.WOOD_AXE) and owns_tool(GameData.Item.AXE),240):finish();return
 if not await prepare_material(GameData.Item.WOOD,4,"鉄道具の柄用木4を先に確保"):finish();return
 if not await make_item("tool_pick"):finish();return
 if not await wait_for("安全寄りの村で基本鉄採掘具を装備",func():return main.workers.any(func(w):return w.tools.get("mine",-1)==GameData.Item.PICKAXE),120):finish();return
 if not await make_item("tool_iron_axe"):finish();return
 if not await wait_for("安全寄りの村で基本鉄斧を装備",func():return main.workers.any(func(w):return w.tools.get("chop",-1)==GameData.Item.IRON_AXE),120):finish();return
 var d:=SaveGame.capture(main)
 if not SaveGame.write(main,"user://tool-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://tool-flow.json")) or SaveGame.capture(main)!=d:fail("鉄装備の保存復元不一致")
 finish()
