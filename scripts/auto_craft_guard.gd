class_name AutoCraftGuard
extends RefCounted
## 自動注文だけの取り置き。手動製作・建設・既に搬出済みの材料は変更しない。
const REPAIR_RESERVE := 3
const IRON_TOOL_WOOD := 2

static func available(g, item:int, claimant = null, allow_build_buffer := false) -> int:
 var n:int=g.storage.count_of(item)-g._queued_transfer(item,"to_workshop")
 if not allow_build_buffer:
  for id in g.build_queue:n-=int(g.build_cost(id).get(item,0))
 for w in g.workers:
  if w==claimant:continue
  var a=w.ai
  if a.state==CharacterAI.State.HAUL_TAKE:n-=int(a.haul_recipe.get("in",{}).get(item,0))
  elif a.state==CharacterAI.State.REPAIR_TAKE and item==GameData.Item.REPAIR_KIT:n-=1
  elif a.state==CharacterAI.State.REFUEL_TAKE and item==a.haul_item:n-=1
  elif a.state==CharacterAI.State.EAT_TAKE and item==GameData.Item.FOOD:n-=1
 return maxi(0,n)

static func iron_tool_needed(g) -> bool:
 if not g.has_facility("workbench"):return false
 for id in ["tool_pick","tool_iron_axe"]:
  var r:=GameData.recipe_by_id(id)
  if g.recipe_priority.get(id,0)>0 and g.tool_wanted(r.out):return true
 return false

static func allows(g,r:Dictionary,claimant = null) -> bool:
 if not r["in"].has(GameData.Item.WOOD) and not r["in"].has(GameData.Item.REPAIR_KIT):return true
 var urgent_fuel:bool=r.out==GameData.Item.FUEL and g.storage.count_of(GameData.Item.FUEL)==0 and g.base.fuel<30.0
 var own_incoming:Dictionary={} if claimant==null else claimant.ai.haul_recipe
 var allow_build_buffer:bool=urgent_fuel or g.build_needs_gather_tool(r.out,own_incoming)
 # 同じ倉庫在庫を複数の運搬・修理・手動移送へ重複割当しない。
 for item in r["in"]:
  if available(g,item,claimant,allow_build_buffer)<int(r["in"][item]):return false
 if r["in"].has(GameData.Item.REPAIR_KIT):
  if available(g,GameData.Item.REPAIR_KIT,claimant)-int(r["in"][GameData.Item.REPAIR_KIT])<REPAIR_RESERVE:return false
 if not r["in"].has(GameData.Item.WOOD):return true
 var keep:=0
 var repair_stock:int=available(g,GameData.Item.REPAIR_KIT,claimant)+g.processor.pending_of(GameData.Item.REPAIR_KIT)
 # 修理板不足時は、木1を修理へ残す。最初の採掘具は材料調達を開くため例外。
 var bootstrap:bool=r.out in [GameData.Item.WOOD_PICK,GameData.Item.HAMMER] and g.build_needs_gather_tool(r.out,own_incoming)
 # 建設依頼がなくても石/鉄をまだ採れない段階の最初の道具を塞がない。
 if r.out in [GameData.Item.WOOD_PICK,GameData.Item.HAMMER]:
  var kind:String="rock" if r.out==GameData.Item.WOOD_PICK else "vein"
  bootstrap=bootstrap or not g.workers.any(func(w):return float(w.gather_eval(kind).eff)>=GatherDB.MIN_EFF)
 if bootstrap:return true
 if repair_stock<REPAIR_RESERVE and r.out!=GameData.Item.REPAIR_KIT:keep+=1
 # 鉄道具の次の1本分を薪・低位道具・修理の作り置きに使い切らない。
 # 壊れかけた部位の修理を止めず、燃料枯渇時の既存救済も維持する。
 var urgent_repair:bool=r.out==GameData.Item.REPAIR_KIT and g.base.has_critical_part()
 if iron_tool_needed(g) and r.out not in [GameData.Item.PICKAXE,GameData.Item.IRON_AXE] and not urgent_repair and not urgent_fuel:keep+=IRON_TOOL_WOOD
 if urgent_fuel:keep=0
 return available(g,GameData.Item.WOOD,claimant,allow_build_buffer)-int(r["in"][GameData.Item.WOOD])>=keep
