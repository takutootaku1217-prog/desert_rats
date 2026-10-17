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
  if available(g,item,claimant,true)<int(r["in"][item]):return false
 return true
