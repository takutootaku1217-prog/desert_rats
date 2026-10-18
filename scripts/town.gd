class_name TownEconomy
extends RefCounted
## 現地の遺失荷物は通常素材にしない。2Dの専用マーカーだけを地上に描画する。
class RecoveryMarker extends Node2D:
 var loading := false
 func set_loading(value:bool) -> void:
  if loading==value:return
  loading=value;queue_redraw()
 func _draw() -> void:
  draw_circle(Vector2(0,-14),11.0,Color("402c1e",0.96))
  draw_rect(Rect2(-12,-10,24,17),Color("b8793e"),true)
  draw_rect(Rect2(-12,-10,24,17),Color("ffe0a1"),false,2.0)
  draw_line(Vector2(-10,-2),Vector2(10,-2),Color("5a3622"),2.0)
  draw_line(Vector2(0,-9),Vector2(0,6),Color("5a3622"),2.0)
  if loading:
   draw_arc(Vector2(0,-14),16.0,-2.4,0.5,10,Color("ffe18c"),2.0)

## 街の取引と反復サブクエスト。見積は一回だけ有効、依頼用荷物は通常素材に混ぜない。
var game
var credits := 0
var supply := "idle"
var supply_item := GameData.Item.WOOD
var supply_count := 6
var supply_reward := 24
var delivery := "idle" # idle / outbound / return / ready
var delivery_cargo := false
## 同じ配達契約で実際に前渡した燃料。0は「未供与」であり、満タン受注で使用済みにしない。
var delivery_advance_given := 0.0
var recovery := "idle" # idle / outbound / site / loading / carried / return / ready
var recovery_worker := -1
var claimed := {"supply":0,"delivery":0,"recovery":0}
## 旧版の街内勤務を途中で失わせないための、一回限りの保存移行用受領額。新規には発生しない。
var legacy_help_credit := 0
var _ticket := {}
var _nonce := 0
var _recovery_marker: RecoveryMarker = null
const FIELDS := ["credits","supply","supply_item","supply_count","supply_reward","delivery","delivery_cargo","delivery_advance_given","recovery","recovery_worker","claimed","legacy_help_credit"]
const LEGACY_HELP_CREDIT := 24

func setup(g) -> void: game=g
func location_ok() -> bool:
 return game.world.active and game.world.region=="central_trade" and game.world.phase=="stopped" and game.quarry.state=="road" and not game.game_over
func entry_reason() -> String:
 if not location_ok(): return "中央都市に停泊すると利用できます"
 return game.world.ready_reason()
func available(item:int) -> int:
 return maxi(0,AutoCraftGuard.available(game,item)-int(ProductionPlan.held_for_orders(game).get(item,0)))
func snapshot() -> Dictionary: return SaveGame.fields(self,FIELDS)

## v3の旧town項目（街内勤務）を、新しい3依頼へ移す。未受領の旧勤務は一度だけ明示受領できる。
static func normalized(d:Dictionary) -> Dictionary:
 var base:=TownEconomy.new()
 var out:Dictionary=SaveGame.fields(base,FIELDS)
 if d.is_empty():return out
 var legacy:bool=d.has("help") and not d.has("recovery")
 if legacy:
  for key in ["credits","supply","delivery"]:
   if d.has(key):out[key]=d[key]
  var old_claimed:Dictionary=d.get("claimed",{})
  out.claimed={"supply":int(old_claimed.get("supply",0)),"delivery":int(old_claimed.get("delivery",0)),"recovery":0}
  if out.supply=="accepted":
   out.supply_item=GameData.Item.WOOD;out.supply_count=3;out.supply_reward=9
  # 旧版の配達は積載0だったため、進行中のものへ新しい荷物を後付けしない。
  out.delivery_cargo=false
  out.legacy_help_credit=LEGACY_HELP_CREDIT if d.get("help","idle") in ["working","ready"] else 0
  return out
 var source:Dictionary=d.duplicate(true)
 # v4までのboolは、過去の契約で一度で10を前渡した扱いに移行する。
 # 新版は実際の供与量で管理し、満タン受注で0を使用済みにしない。
 if not source.has("delivery_advance_given") and source.has("delivery_advance_issued"):
  source["delivery_advance_given"]=TownDB.DELIVERY_FUEL_ADVANCE if bool(source["delivery_advance_issued"]) else 0.0
  source.erase("delivery_advance_issued")
 for key in FIELDS:
  if not source.has(key):return {}
  out[key]=source[key]
 return out

func restore(d:Dictionary) -> void:
 var restored:=normalized(d)
 SaveGame.put(self,restored if not restored.is_empty() else SaveGame.fields(TownEconomy.new(),FIELDS),FIELDS)
 _ticket.clear(); _nonce+=1
 if game.town_ui!=null: game.town_ui.stop_clock()
 _sync_recovery_marker()

static func valid(d, crew_size:int) -> bool:
 if not d is Dictionary:return false
 if d.is_empty():return true
 var legacy:bool=d.has("help") and not d.has("recovery")
 if not legacy and d.size()!=FIELDS.size():return false
 var v:=normalized(d)
 if v.is_empty():return false
 if not v.credits is int or v.credits<0 or v.credits>1000000000:return false
 if v.supply not in ["idle","accepted"] or v.delivery not in ["idle","outbound","return","ready"] or v.recovery not in ["idle","outbound","site","loading","carried","return","ready"]:return false
 if v.supply_item not in TownDB.SUPPLY_OFFERS:return false
 var offer:Dictionary=TownDB.SUPPLY_OFFERS[v.supply_item]
 if not v.supply_count is int or not v.supply_reward is int or v.supply_count<1 or v.supply_reward<1:return false
 # 旧受注だけは、当時の木材3→9 Crをそのまま完了できる。
 if not (v.supply_count==offer.count and v.supply_reward==offer.reward) and not (legacy and v.supply=="accepted" and v.supply_item==GameData.Item.WOOD and v.supply_count==3 and v.supply_reward==9):return false
 if not v.delivery_cargo is bool or typeof(v.delivery_advance_given) not in [TYPE_FLOAT,TYPE_INT] or v.delivery_advance_given<0.0 or v.delivery_advance_given>TownDB.DELIVERY_FUEL_ADVANCE:return false
 if v.delivery_cargo and v.delivery!="outbound":return false
 if not v.recovery_worker is int or v.recovery_worker< -1 or v.recovery_worker>=crew_size:return false
 if v.recovery in ["loading","carried"] and v.recovery_worker<0:return false
 if v.recovery not in ["loading","carried"] and v.recovery_worker!=-1:return false
 if not v.claimed is Dictionary or v.claimed.size()!=3:return false
 for key in ["supply","delivery","recovery"]:
  if not v.claimed.get(key) is int or v.claimed[key]<0:return false
 if not v.legacy_help_credit is int or v.legacy_help_credit<0 or v.legacy_help_credit>LEGACY_HELP_CREDIT:return false
 return true

func mission_cargo_weight() -> int:
 var n:=TownDB.DELIVERY_PARCEL_WEIGHT if delivery=="outbound" and delivery_cargo else 0
 if recovery in ["carried","return","ready"]:n+=TownDB.RECOVERY_PARCEL_WEIGHT
 return n
func cargo_room(weight:int) -> bool:
 return not game.storage.enforce or game.storage.current_weight()+game.storage.processing_reserve()+weight<=game.storage.max_weight()
func supply_text() -> String:
 return "%s%d個"%[ItemDB.name_of(supply_item),supply_count]
func recovery_target_text() -> String:return WorldMapDB.name_of(TownDB.RECOVERY_TO)
func delivery_advance_remaining() -> float:return maxf(0.0,TownDB.DELIVERY_FUEL_ADVANCE-delivery_advance_given)
func recovery_site_ok() -> bool:
 return game.world.region==TownDB.RECOVERY_TO and game.world.phase=="stopped" and game.quarry.state=="road" and not game.game_over
func recovery_blocks_departure() -> bool:return recovery in ["site","loading","carried"]
func field_status_text() -> String:
 var parts:Array[String]=[]
 if delivery=="outbound":
  if game.world.region==TownDB.DELIVERY_TO and game.world.phase!="stopped":parts.append("配達：交易村で停車して引渡しが必要")
  elif game.world.region==TownDB.DELIVERY_TO:parts.append("配達：引渡し済み、都市へ帰還")
  else:parts.append("配達中：%sへ"%WorldMapDB.name_of(TownDB.DELIVERY_TO))
 elif delivery=="return":parts.append("配達：都市で報酬を受取")
 if recovery=="site":
  parts.append("回収待ち：満載の解消または断念後に帰還" if not cargo_room(TownDB.RECOVERY_PARCEL_WEIGHT) else "回収待ち：現地の地上荷物へ仲間を派遣")
 elif recovery=="loading":parts.append("回収中：仲間が地上荷物へ移動中")
 elif recovery=="carried":parts.append("回収中：専用荷物を拠点へ運搬中")
 elif recovery=="return":parts.append("回収済み：都市へ帰還して報酬を受取")
 elif recovery=="ready":parts.append("回収済み：都市で報酬を受取")
 if game.operations.stance=="alert":parts.append("警戒中")
 elif game.operations.stance=="recall":parts.append("帰還指示中")
 return " / ".join(parts) if not parts.is_empty() else "依頼なし"

func _sync_recovery_marker() -> void:
 var visible:=recovery in ["site","loading"] and recovery_site_ok()
 if not visible:
  if is_instance_valid(_recovery_marker):_recovery_marker.queue_free()
  _recovery_marker=null
  return
 if not is_instance_valid(_recovery_marker):
  _recovery_marker=RecoveryMarker.new();_recovery_marker.name="RecoveryParcel";game.ground_sort.add_child(_recovery_marker)
 _recovery_marker.position=TownDB.RECOVERY_POINT
 _recovery_marker.set_loading(recovery=="loading")

func abandon_recovery_from_field() -> bool:
 if recovery not in ["site","loading"] or not recovery_site_ok():return false
 var index:=recovery_worker
 recovery="idle";recovery_worker=-1
 if index>=0 and index<game.workers.size():game.workers[index].ai.return_request=true
 _sync_recovery_marker()
 return true
func delivery_status_text() -> String:return {"idle":"未受注","outbound":"%sへ配達中"%WorldMapDB.name_of(TownDB.DELIVERY_TO),"return":"都市へ帰還","ready":"報酬未受領"}.get(delivery,delivery)
func recovery_status_text() -> String:return {"idle":"未受注","outbound":"%sへ向かう"%recovery_target_text(),"site":"現地で仲間が回収待ち","loading":"仲間が遺失物へ移動中","carried":"仲間が拠点へ運搬中","return":"都市へ帰還","ready":"報酬未受領"}.get(recovery,recovery)

func observe() -> void:
 if delivery=="outbound" and game.world.region==TownDB.DELIVERY_TO and game.world.phase=="stopped":
  delivery="return";delivery_cargo=false
 if delivery=="return" and location_ok():delivery="ready"
 if recovery=="outbound" and recovery_site_ok():recovery="site"
 if recovery=="return" and location_ok():recovery="ready"
 if recovery in ["loading","carried"]:
  if recovery_worker<0 or recovery_worker>=game.workers.size():
   recovery="site";recovery_worker=-1
  elif game.workers[recovery_worker].down or game.workers[recovery_worker].away:
   release_recovery_worker(game.workers[recovery_worker])
 if recovery=="loading" and not recovery_site_ok() and recovery_worker>=0 and recovery_worker<game.workers.size():release_recovery_worker(game.workers[recovery_worker])
 _sync_recovery_marker()

## SEARCHから呼ぶ。遺失物は画面上の仲間が実際に現地へ歩いて回収する。生物への新しい予兆は増やさない。
func recovery_job_for(w) -> int:
 var index:int=game.workers.find(w)
 if index<0:return 0
 if recovery=="carried" and recovery_worker==index:return 2
 if recovery!="site" or not recovery_site_ok() or not cargo_room(TownDB.RECOVERY_PARCEL_WEIGHT):return 0
 if not game.operations.can_depart(w,TownDB.RECOVERY_POINT):return 0
 if w.away or w.down or w.floor_i<=0 or w.carrying>=0 or not w.carry_bonus.is_empty():return 0
 recovery="loading";recovery_worker=index
 return 1
func recovery_loaded(w) -> bool:
 if recovery=="loading" and recovery_worker==game.workers.find(w):
  if not recovery_site_ok() or w.floor_i!=0 or w.position.distance_to(TownDB.RECOVERY_POINT)>18.0:
   recovery="site";recovery_worker=-1;_sync_recovery_marker();return false
  # 出発後に他の仲間が倉庫を満たした場合も、専用荷物で容量超過させない。
  if not cargo_room(TownDB.RECOVERY_PARCEL_WEIGHT):recovery="site";recovery_worker=-1;return false
  recovery="carried";_sync_recovery_marker();return true
 return false
func recovery_stowed(w) -> bool:
 if recovery=="carried" and recovery_worker==game.workers.find(w):recovery="return";recovery_worker=-1;_sync_recovery_marker();return true
 return false
func recovery_carried_by(w) -> bool:return recovery=="carried" and recovery_worker==game.workers.find(w)
func release_recovery_worker(w) -> void:
 if recovery in ["loading","carried"] and recovery_worker==game.workers.find(w):
  # 中断・負傷・出発では任務だけを解放し、担当者には既存の帰還AIを必ず通させる。
  # これで別地域に残留したまま再回収したり、甲板で永久待機したりしない。
  w.ai.return_request=true
  recovery="site";recovery_worker=-1;_sync_recovery_marker()

func _state() -> Dictionary:
 return {"town":snapshot(),"inventory":game.storage.inventory.counts.duplicate(true),"available":_availability(),"parts":game.base.parts.duplicate(),"fuel":game.base.fuel,"free":game.storage.max_weight()-game.storage.current_weight()-game.storage.processing_reserve(),"reserved_fuel":game.base.refuel_reserved,"reserved_repair":game.base.repair_reserved.duplicate()}
func _availability() -> Dictionary:
 var a:Dictionary={}
 for it in ItemDB.ORDER:a[it]=available(it)
 return a
func quote(action:String,item:int=-1,n:int=1) -> Dictionary:
 _nonce+=1;_ticket={}
 var q:=evaluate(action,item,n);q["nonce"]=_nonce
 if q.ok:_ticket=q.duplicate(true)
 return q
func evaluate(action:String,item:int,n:int) -> Dictionary:
 var q:Dictionary={"action":action,"item":item,"n":n,"ok":false,"reason":entry_reason(),"cost":0,"amount":0.0,"text":""}
 if q.reason!="":return q
 if n<1 or n>99:q.reason="数量は1〜99";return q
 var before:int=game.storage.count_of(item)
 match action:
  "buy","sell":
   var prices:Dictionary=TownDB.BUY if action=="buy" else TownDB.SELL
   if not prices.has(item):q.reason="取扱対象外";return q
   q.cost=int(prices[item])*n*(1 if action=="buy" else -1)
   if action=="buy" and game.storage.free_for(item)<n:q.reason="積載容量不足（依頼荷物・加工予約も含む）";return q
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
   if not TownDB.SUPPLY_OFFERS.has(item):q.reason="納品物を選択してください";return q
   var offer:Dictionary=TownDB.SUPPLY_OFFERS[item]
   q.text="%s%d個の納品を受注。報酬%d Cr。納品時だけ未予約素材を消費。"%[ItemDB.name_of(item),offer.count,offer.reward]
  "claim_supply":
   if supply!="accepted" or available(supply_item)<supply_count:q.reason="受注と未予約の%sが必要"%supply_text();return q
   q.cost=-supply_reward;q.text="%sを納品（倉庫 %d → %d）、報酬%d Crを受領"%[supply_text(),game.storage.count_of(supply_item),game.storage.count_of(supply_item)-supply_count,supply_reward]
  "accept_delivery":
   if delivery!="idle":q.reason="配達は受注済み";return q
   if not cargo_room(TownDB.DELIVERY_PARCEL_WEIGHT):q.reason="預かり荷物（重量%d）の積載余裕が必要"%TownDB.DELIVERY_PARCEL_WEIGHT;return q
   var advance:float=minf(delivery_advance_remaining(),GameData.FUEL_CAP-game.base.fuel)
   q.text="預かり荷物（重量%d）を%sへ届け、都市で%d Crを受領。"%[TownDB.DELIVERY_PARCEL_WEIGHT,WorldMapDB.name_of(TownDB.DELIVERY_TO),TownDB.DELIVERY_REWARD]
   q.text+="\n出発支援として燃料%.1fを前渡し（取消しても同じ依頼では再発行されません）。"%advance if advance>0 else "\n前渡し燃料はこの依頼で使用済みです。"
  "claim_delivery":
   if delivery!="ready":q.reason="%sで荷物を届け、都市へ戻ってください"%WorldMapDB.name_of(TownDB.DELIVERY_TO);return q
   q.cost=-TownDB.DELIVERY_REWARD;q.text="配達報酬%d Crを受領"%TownDB.DELIVERY_REWARD
  "accept_recovery":
   if recovery!="idle":q.reason="遺失物回収は受注済み";return q
   q.text="%sの遺失地点へ向かう。現地で仲間1人が荷物（重量%d）を拾い、移動拠点へ運ぶ。都市へ戻って%d Crを受領。"%[recovery_target_text(),TownDB.RECOVERY_PARCEL_WEIGHT,TownDB.RECOVERY_REWARD]
  "claim_recovery":
   if recovery!="ready":q.reason="%sで回収し、荷物を積んで都市へ戻ってください"%recovery_target_text();return q
   q.cost=-TownDB.RECOVERY_REWARD;q.text="遺失物回収の報酬%d Crを受領。依頼用荷物は通常素材になりません。"%TownDB.RECOVERY_REWARD
  "claim_legacy_help":
   if legacy_help_credit<=0:q.reason="旧勤務の未受領報酬はありません";return q
   q.cost=-legacy_help_credit;q.text="旧版の荷札整理の未受領報酬%d Crを一度だけ受領"%legacy_help_credit
  "cancel_supply","cancel_delivery","cancel_recovery":
   var state:String=supply if action=="cancel_supply" else (delivery if action=="cancel_delivery" else recovery)
   if state=="idle":q.reason="取消対象なし";return q
   q.text="依頼を取り消す。報酬なし、依頼専用荷物と未受領報酬は破棄。通常素材・注文予約は増減しません。"
  _:q.reason="対象外の操作";return q
 if credits<q.cost:q.reason="資金不足（必要 %d / 所持 %d Cr）"%[q.cost,credits];return q
 if credits-q.cost>1000000000:q.reason="所持金上限";return q
 q.text+="\n所持金 %d → %d Cr"%[credits,credits-q.cost]
 if action=="accept_delivery":
  var quoted_advance:=minf(delivery_advance_remaining(),GameData.FUEL_CAP-game.base.fuel)
  q.text+="\n交易村で停車して引渡しが必要です。前渡し累計 %.1f / %.1f、今回 %.1f、残り %.1f。"%[delivery_advance_given,TownDB.DELIVERY_FUEL_ADVANCE,quoted_advance,delivery_advance_remaining()-quoted_advance]
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
   game.base.repair_amount(q.item,q.amount);game.base.total_repair+=1
  "accept_supply":
   var offer:Dictionary=TownDB.SUPPLY_OFFERS[q.item]
   supply="accepted";supply_item=q.item;supply_count=offer.count;supply_reward=offer.reward
  "claim_supply":game.storage.inventory.take_n(supply_item,supply_count);supply="idle";claimed.supply+=1;game.quarry.schedule_mission_replenishment()
  "accept_delivery":
   delivery="outbound";delivery_cargo=true
   var issued:float=minf(delivery_advance_remaining(),GameData.FUEL_CAP-game.base.fuel)
   if issued>0.0:
    game.base.fuel+=issued;delivery_advance_given+=issued
  "claim_delivery":delivery="idle";delivery_cargo=false;delivery_advance_given=0.0;claimed.delivery+=1;game.quarry.schedule_mission_replenishment()
  "accept_recovery":recovery="outbound";recovery_worker=-1
  "claim_recovery":recovery="idle";recovery_worker=-1;claimed.recovery+=1;game.quarry.schedule_mission_replenishment()
  "claim_legacy_help":legacy_help_credit=0
  "cancel_supply":supply="idle"
  "cancel_delivery":delivery="idle";delivery_cargo=false # 前渡しフラグは完了まで保持し、取消再受注で燃料を増やさない。
  "cancel_recovery":recovery="idle";recovery_worker=-1
 _sync_recovery_marker()
 return true
