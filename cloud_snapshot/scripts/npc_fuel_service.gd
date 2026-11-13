class_name NpcFuelService
extends RefCounted
## Narrow service adapter, not a second town. Quotes are transient and one-use.
var game
var _ticket := {}
var _nonce := 0
func setup(g) -> void:game=g
func restored() -> bool:
 return game.world.first_region() and bool(game.world.npc_facilities.get("facilities",{}).get(NpcFuelFacility.ID,{}).get("restored",false))
func cancel_quote() -> void:
 _ticket={};_nonce+=1
func _reason() -> String:
 if game.world._land_payment_active:return "別の支払いを確定中です"
 return game.world.land_operation_reason(NpcFuelFacility.SITE)
func _state() -> Dictionary:
 var available:={}
 for item in NpcFuelFacility.MATERIALS:available[item]=game.warehouse_discard_available(item)
 return {"site":game.world.region,"profile":game.world.map_profile,"facility":NpcFuelFacility.ID,"revision":int(restored()),"inventory":game.storage.inventory.counts.duplicate(true),"available":available,"cr":game.town.credits,"fuel":game.base.fuel,"reserved":game.base.refuel_reserved}
func evaluate(action:String) -> Dictionary:
 var q:={"action":action,"ok":false,"reason":_reason(),"cost":0,"materials":{},"amount":0.0,"text":""}
 if not q.reason.is_empty():return q
 match action:
  "restore":
   q.cost=NpcFuelFacility.CREDITS;q.materials=NpcFuelFacility.MATERIALS.duplicate(true)
   q.text="復旧支援：木材%d・石材%d・%d Crを一度だけ支払います。\nNPCが運営し、現金給油のみ営業。備蓄・市場・修理は別です。"%[q.materials[GameData.Item.WOOD],q.materials[GameData.Item.STONE],q.cost]
   if restored():q.reason="復旧済みです。再支払いは不要です";return q
   for item in q.materials:
    if game.warehouse_discard_available(item)<int(q.materials[item]):q.reason="未予約の%sが%d個必要です"%[ItemDB.name_of(item),q.materials[item]];return q
  "fuel_cash":
   if not restored():q.reason="未復旧・休業中です。先に資材とCrで復旧してください";return q
   var fuel:=TownEconomy.fuel_service_quote(game.base,1)
   q.amount=fuel.amount;q.cost=fuel.cost;q.text=fuel.text;q.reason=fuel.reason
   if not q.reason.is_empty():return q
  _:q.reason="この施設は復旧支援と現金給油だけです";return q
 if game.town.credits<q.cost:q.reason="資金不足（必要 %d / 所持 %d Cr）"%[q.cost,game.town.credits];return q
 q.text+="\n所持金 %d → %d Cr"%[game.town.credits,game.town.credits-q.cost]
 q.ok=true;q["state"]=_state()
 return q
func quote(action:String) -> Dictionary:
 cancel_quote()
 var q:=evaluate(action);q["nonce"]=_nonce
 if q.ok:_ticket=q.duplicate(true)
 return q
func execute(q:Dictionary) -> bool:
 if game.world._land_payment_active or q.is_empty() or q!=_ticket:return false
 _ticket={}
 var fresh:=evaluate(q.action)
 if not fresh.ok or fresh.state!=q.state:return false
 game.world._land_payment_active=true
 var previous_cr:int=game.town.credits
 var previous_state:Dictionary=game.world.npc_facilities.duplicate(true)
 game.town.credits-=int(fresh.cost)
 var paid:=true
 if q.action=="restore":
  # take_set emits synchronously; all three ledgers must already agree there.
  game.world.npc_facilities.facilities[NpcFuelFacility.ID].restored=true
  paid=game.storage.inventory.take_set(fresh.materials)
  if not paid:
   game.town.credits=previous_cr;game.world.npc_facilities=previous_state
 else:game.town.apply_fuel_amount(fresh.amount)
 game.world._land_payment_active=false
 if paid:game.director.note("NPC給油所：復旧して現金給油の営業を開始しました" if q.action=="restore" else "NPC給油所：%.1f給油 / %d Cr"%[fresh.amount,fresh.cost])
 return paid
