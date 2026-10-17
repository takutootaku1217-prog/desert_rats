class_name TownEconomy
extends RefCounted
## 取引の見積→単発実行。保存は経済状態のみ。見積券はロードで失効。
var game
var credits := 0
var supply := "idle"
var delivery := "idle" # idle / outbound / return / ready
var help := "idle" # idle / working / ready
var help_left := 0.0
var helper := -1
var claimed := {"supply":0,"delivery":0,"help":0}
var _ticket := {}
var _nonce := 0
const FIELDS := ["credits","supply","delivery","help","help_left","helper","claimed"]

func setup(g) -> void: game=g
func location_ok() -> bool:
 return game.world.active and game.world.region=="central_trade" and game.world.phase=="stopped" and game.quarry.state=="road" and not game.game_over
func entry_reason() -> String:
 if not location_ok(): return "中央都市に停泊すると利用できます"
 return game.world.ready_reason()
func available(item:int) -> int:
 return maxi(0,AutoCraftGuard.available(game,item)-int(ProductionPlan.held_for_orders(game).get(item,0)))
func snapshot() -> Dictionary: return SaveGame.fields(self,FIELDS)
func restore(d:Dictionary) -> void:
 var fallback:=TownEconomy.new()
 SaveGame.put(self,SaveGame.fields(fallback,FIELDS) if d.is_empty() else d,FIELDS)
 _ticket.clear(); _nonce+=1
 if game.town_ui!=null: game.town_ui.stop_clock()
static func valid(d, crew_size:int) -> bool:
 if not d is Dictionary:return false
 if d.is_empty():return true
 for key in FIELDS:
  if not d.has(key):return false
 if not d.credits is int or d.credits<0 or d.credits>1000000000:return false
 if d.supply not in ["idle","accepted"] or d.delivery not in ["idle","outbound","return","ready"] or d.help not in ["idle","working","ready"]:return false
 if not d.help_left is float or not is_finite(d.help_left) or d.help_left<0 or d.help_left>TownDB.HELP_SECONDS:return false
 if not d.helper is int or d.helper< -1 or d.helper>=crew_size:return false
 if d.help=="idle" and (d.help_left!=0 or d.helper!=-1):return false
 if d.help!="idle" and d.helper<0:return false
 if d.help=="ready" and d.help_left!=0:return false
 if d.help=="working" and d.help_left<=0:return false
 if not d.claimed is Dictionary or d.claimed.size()!=3:return false
 for key in ["supply","delivery","help"]:
  if not d.claimed.get(key) is int or d.claimed[key]<0:return false
 return true
func observe() -> void:
 if delivery=="outbound" and game.world.region==TownDB.DELIVERY_TO and game.world.phase=="stopped": delivery="return"
 if delivery=="return" and location_ok():delivery="ready"
func helper_index() -> int:
 for i in game.workers.size():
  var w=game.workers[i]
  if not w.away and not w.down and w.floor_i>0 and w.carrying<0:return i
 return -1
## 専用勤務表示だけが呼ぶ。世界・維持・加工は停止する等価的な街内勤務。
func work(delta:float) -> void:
 if help!="working" or entry_reason()!="" or helper<0 or game.workers[helper].down or game.workers[helper].away:return
 help_left=maxf(0.0,help_left-maxf(0.0,delta))
 if help_left<=0.00001:help_left=0.0;help="ready"
func _state() -> Dictionary:
 return {"town":snapshot(),"inventory":game.storage.inventory.counts.duplicate(true),"available":_availability(),"parts":game.base.parts.duplicate(),"fuel":game.base.fuel,"free":game.storage.max_weight()-game.storage.current_weight()-game.storage.processing_reserve(),"reserved_fuel":game.base.refuel_reserved,"reserved_repair":game.base.repair_reserved.duplicate()}
func _availability() -> Dictionary:
 var a:Dictionary={}
 for it in ItemDB.ORDER:a[it]=available(it)
 return a
func quote(action:String,item:int=-1,n:int=1) -> Dictionary:
 _nonce+=1
 _ticket={}
 var q:=evaluate(action,item,n)
 q["nonce"]=_nonce
 if q.ok:_ticket=q.duplicate(true)
 return q
func evaluate(action:String,item:int,n:int) -> Dictionary:
 var q:Dictionary={"action":action,"item":item,"n":n,"ok":false,"reason":entry_reason(),"cost":0,"amount":0.0,"text":""}
 if q.reason!="":return q
 if n<1 or n>99:q.reason="数量は1〜99";return q
 if help=="working" and action not in ["cancel_help"]:q.reason="手伝いを完了または取り消してください";return q
 var before:int=game.storage.count_of(item)
 match action:
  "buy","sell":
   var prices:Dictionary=TownDB.BUY if action=="buy" else TownDB.SELL
   if not prices.has(item):q.reason="取扱対象外";return q
   q.cost=int(prices[item])*n*(1 if action=="buy" else -1)
   if action=="buy" and game.storage.free_for(item)<n:q.reason="積載容量不足（加工予約も含む）";return q
   if action=="sell" and available(item)<n:q.reason="未予約の余剰素材が不足";return q
   q.text="%s %d個 × %d Cr = %d Cr\n倉庫 %d → %d個"%[ItemDB.name_of(item),n,prices[item],absi(q.cost),before,before+n*(1 if action=="buy" else -1)]
  "fuel_cash","fuel_item":
   if game.base.refuel_reserved:q.reason="仲間が給油予約中";return q
   q.amount=minf(TownDB.SERVICE_UNIT*n,GameData.FUEL_CAP-game.base.fuel)
   if q.amount<=0:q.reason="満タンです";return q
   if action=="fuel_item":
    if n!=1 or available(GameData.Item.FUEL)<1:q.reason="未予約の燃料1個が必要";return q
   else:q.cost=ceili(q.amount*TownDB.SERVICE_PRICE/TownDB.SERVICE_UNIT)
   q.text="給油 %.1f → %.1f / 100\n%s"%[game.base.fuel,game.base.fuel+q.amount,"燃料1個を消費（端数は上限で切捨て）" if action=="fuel_item" else "単価 %.0fあたり%d Cr・実量 %.1f / 合計 %d Cr"%[TownDB.SERVICE_UNIT,TownDB.SERVICE_PRICE,q.amount,q.cost]]
  "repair_cash","repair_item":
   if item not in GameData.Part.values():q.reason="部位を選択してください";return q
   if game.base.repair_reserved.has(item):q.reason="仲間がこの部位を修理予約中";return q
   q.amount=minf((GameData.REPAIR_AMOUNT if action=="repair_item" else TownDB.SERVICE_UNIT*n),100.0-game.base.parts[item])
   if q.amount<=0:q.reason="この部位は修理不要";return q
   if action=="repair_item":
    if n!=1 or available(GameData.Item.REPAIR_KIT)<1:q.reason="未予約の修理板1個が必要";return q
   else:q.cost=ceili(q.amount*TownDB.SERVICE_PRICE/TownDB.SERVICE_UNIT)
   q.text="耐久 %.1f → %.1f / 100\n%s"%[game.base.parts[item],game.base.parts[item]+q.amount,"修理板1個を消費（端数は上限で切捨て）" if action=="repair_item" else "単価 %.0fあたり%d Cr・実量 %.1f / 合計 %d Cr"%[TownDB.SERVICE_UNIT,TownDB.SERVICE_PRICE,q.amount,q.cost]]
  "accept_supply":
   if supply!="idle":q.reason="納品は受注済み";return q
   q.text="%s%d個の納品を受注。報酬%d Cr。納品時だけ素材を消費。"%[ItemDB.name_of(TownDB.SUPPLY_ITEM),TownDB.SUPPLY_COUNT,TownDB.SUPPLY_REWARD]
  "claim_supply":
   if supply!="accepted" or available(TownDB.SUPPLY_ITEM)<TownDB.SUPPLY_COUNT:q.reason="受注と未予約の%s%d個が必要"%[ItemDB.name_of(TownDB.SUPPLY_ITEM),TownDB.SUPPLY_COUNT];return q
   q.cost=-TownDB.SUPPLY_REWARD;q.text="%s%d個を納品（倉庫 %d → %d）、報酬%d Crを受領"%[ItemDB.name_of(TownDB.SUPPLY_ITEM),TownDB.SUPPLY_COUNT,game.storage.count_of(TownDB.SUPPLY_ITEM),game.storage.count_of(TownDB.SUPPLY_ITEM)-TownDB.SUPPLY_COUNT,TownDB.SUPPLY_REWARD]
  "accept_delivery":
   if delivery!="idle":q.reason="配達は受注済み";return q
   q.text="%sへの書状配達を受注。現地で停泊すると配達完了、都市へ戻って%d Cr受領。書状はミッション記録で管理（積載0）。"%[WorldMapDB.name_of(TownDB.DELIVERY_TO),TownDB.DELIVERY_REWARD]
  "claim_delivery":
   if delivery!="ready":q.reason="村へ配達して都市へ戻ってください";return q
   q.cost=-TownDB.DELIVERY_REWARD;q.text="配達報酬%d Crを受領"%TownDB.DELIVERY_REWARD
  "accept_help":
   if help!="idle" or helper_index()<0:q.reason="手伝い中、または働ける仲間がいません";return q
   q.text="%sがヤードの荷札整理を%.0f秒行う。報酬%d Cr。勤務表示中は街の滞在支援で維持費0、通常作業も停止。途中取消は報酬なし。"%[game.workers[helper_index()].char_name,TownDB.HELP_SECONDS,TownDB.HELP_REWARD]
  "claim_help":
   if help!="ready":q.reason="手伝いが未完了";return q
   q.cost=-TownDB.HELP_REWARD;q.text="手伝い報酬%d Crを受領"%TownDB.HELP_REWARD
  "cancel_supply","cancel_delivery","cancel_help":
   var state:String=supply if action=="cancel_supply" else (delivery if action=="cancel_delivery" else help)
   if state=="idle":q.reason="取消対象なし";return q
   q.text="ミッションを取り消す。報酬なし、未受領報酬と作業進捗も破棄。"
  _:q.reason="対象外の操作";return q
 if credits<q.cost:q.reason="資金不足（必要 %d / 所持 %d Cr）"%[q.cost,credits];return q
 if credits-q.cost>1000000000:q.reason="所持金上限";return q
 q.text+="\n所持金 %d → %d Cr"%[credits,credits-q.cost]
 q.ok=true;q["state"]=_state()
 return q
func execute(q:Dictionary) -> bool:
 if q.is_empty() or q!=_ticket:return false
 _ticket={}
 var fresh:=evaluate(q.action,q.item,q.n)
 if not fresh.ok or fresh.state!=q.state:return false
 credits-=int(q.cost)
 match q.action:
  "buy":game.storage.inventory.add(q.item,q.n,Inventory.SOURCE_PURCHASE)
  "sell":game.storage.inventory.take_n(q.item,q.n)
  "fuel_cash","fuel_item":
   if q.action=="fuel_item":game.storage.inventory.take(GameData.Item.FUEL)
   game.base.fuel+=q.amount;game.base.total_refuel+=1
  "repair_cash","repair_item":
   if q.action=="repair_item":game.storage.inventory.take(GameData.Item.REPAIR_KIT)
   game.base.parts[q.item]+=q.amount;game.base.total_repair+=1
  "accept_supply":supply="accepted"
  "accept_delivery":delivery="outbound"
  "accept_help":help="working";help_left=TownDB.HELP_SECONDS;helper=helper_index()
  "claim_supply":game.storage.inventory.take_n(TownDB.SUPPLY_ITEM,TownDB.SUPPLY_COUNT);supply="idle";claimed.supply+=1
  "claim_delivery":delivery="idle";claimed.delivery+=1
  "claim_help":help="idle";help_left=0.0;helper=-1;claimed.help+=1
  "cancel_supply":supply="idle"
  "cancel_delivery":delivery="idle"
  "cancel_help":help="idle";help_left=0.0;helper=-1
 return true
