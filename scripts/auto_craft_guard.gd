class_name AutoCraftGuard
extends RefCounted
## 利用可能数は実予約だけを差し引く。通常補充のみ別途、注文の次の1回分を保護。

static func available(g, item:int, claimant = null, _allow_build_buffer := false) -> int:
 var n:int=g.storage.count_of(item)-g._queued_transfer(item,"to_workshop")
 for w in g.workers:
  if w==claimant:continue
  var a=w.ai
  if a.state==CharacterAI.State.HAUL_TAKE:n-=int(a.haul_recipe.get("in",{}).get(item,0))
  elif a.state==CharacterAI.State.REPAIR_TAKE and item==GameData.Item.REPAIR_KIT:n-=1
  elif a.state==CharacterAI.State.REFUEL_TAKE and item==a.haul_item:n-=1
  elif a.state==CharacterAI.State.EAT_TAKE and item==GameData.Item.FOOD:n-=1
 return maxi(0,n)

static func allows(g,r:Dictionary,claimant = null) -> bool:
 if r.get("automatic",false) and not ProductionPlan.urgent(g,r.out) and not ProductionPlan.spares_orders(g,r,claimant):return false
 for item in r["in"]:
  # An accepted supply contract is player-owned cargo, not spare crafting
  # input. Keep its exact requirement available until it is claimed/cancelled;
  # TownEconomy.available remains the authority that verifies the claim.
  var town_reserve:=0
  if g.town!=null and g.town.supply=="accepted" and g.town.supply_item==item:
   town_reserve=g.town.supply_count
  if available(g,item,claimant,true)-town_reserve<int(r["in"][item]):return false
 return true
