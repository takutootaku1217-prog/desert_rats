extends "res://tools/test_batch_crafting.gd"
## 街の3種類の反復依頼。境界は資源注入ではなく、保存・予約・通常AIの実行で確認する。
var _city_save := {}
func city() -> void:
 if _city_save.is_empty():
  await setup()
  main.world.active=true;main.world.region="central_trade";main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination=""
  main.quarry.state="road"
  for w in main.workers:
   w.stop_work();w.position=Vector2(700,GameData.LO_Y);w.floor_i=1;w._climb_dest=null
  main.world._ensure_location()
  _city_save=SaveGame.capture(main)
 else:
  SaveGame.apply(main,_city_save)
func act(a:String,it:int=-1,n:int=1) -> bool:
 return main.town.execute(main.town.quote(a,it,n))
func _initialize():
 await city()
 var t=main.town;var st=main.storage
 check(TownDB.MISSIONS.size()==3 and TownDB.MISSIONS.has("supply") and TownDB.MISSIONS.has("delivery") and TownDB.MISSIONS.has("recovery") and TownDB.MISSIONS.values().all(func(m):return m.category=="sub" and m.repeatable),"3種は繰り返しサブクエスト・メインは分類のみ")
 check(t.entry_reason()=="" and not t.quote("buy",GameData.Item.FOOD).ok,"都市で入場可能・資金0の購入拒否")
 check(act("accept_supply",GameData.Item.WOOD) and not act("accept_supply",GameData.Item.STONE),"木材納品の受注・同時受注拒否")
 st.inventory.counts={GameData.Item.WOOD:6};main.request_transfer(GameData.Item.WOOD,1,"to_workshop")
 check(not act("claim_supply") and st.count_of(GameData.Item.WOOD)==6,"予約素材の納品を原子的拒否")
 main.cancel_transfers();var q:Dictionary=t.quote("claim_supply")
 check(t.execute(q) and not t.execute(q) and st.count_of(GameData.Item.WOOD)==0 and t.credits==24 and t.claimed.supply==1,"木材6を一度だけ納品し24 Cr")
 check(act("accept_supply",GameData.Item.STONE) and t.supply_item==GameData.Item.STONE and t.supply_count==6,"石材の調達納品も選択できる")
 check(act("cancel_supply") and t.supply=="idle" and st.count_of(GameData.Item.STONE)==0,"納品取消で通常素材を増やさない")
 st.inventory.counts={GameData.Item.WOOD:5,GameData.Item.IRON:1}
 main.request_order("tool_pick",1)
 check(t.available(GameData.Item.WOOD)==3 and not act("sell",GameData.Item.WOOD,5),"注文素材は売却保護")
 check(act("sell",GameData.Item.WOOD,2),"余剰だけ売却")
 main.request_transfer(GameData.Item.WOOD,2,"to_workshop")
 check(t.available(GameData.Item.WOOD)==0 and not act("sell",GameData.Item.WOOD),"運搬予約と注文保護を売らない")
 await city();t=main.town;st=main.storage;t.credits=100
 main.base.fuel=98
 check(act("fuel_cash") and main.base.fuel==100 and t.credits==99,"端数給油2だけ回復・1 Cr・上限")
 check(not act("fuel_cash") and t.credits==99,"満タンは支払いなし")
 main.base.fuel=74;st.inventory.counts={GameData.Item.FUEL:1,GameData.Item.REPAIR_KIT:1}
 check(act("fuel_item") and main.base.fuel==99 and st.count_of(GameData.Item.FUEL)==0,"手持ち燃料で25回復")
 main.base.parts[0]=99
 check(act("repair_cash",0) and main.base.parts[0]==100 and t.credits==98,"修理端数1・1 Cr・上限")
 main.base.parts[1]=70
 check(act("repair_item",1) and main.base.parts[1]==95 and st.count_of(GameData.Item.REPAIR_KIT)==0,"修理板1個で25回復")
 main.base.refuel_reserved=true
 check(not act("fuel_cash"),"仲間の給油予約中はサービス拒否")
 main.base.refuel_reserved=false;main.base.repair_reserved[1]=true
 check(not act("repair_cash",1),"仲間の修理予約保護")
 main.base.repair_reserved.clear()
 await city();t=main.town;main.base.fuel=0
 var weight0:float=st.current_weight()
 check(act("accept_delivery") and t.delivery=="outbound" and t.delivery_cargo and is_equal_approx(main.base.fuel,TownDB.DELIVERY_FUEL_ADVANCE),"無資金・無燃料都市で配達受注、専用荷物と一回限り前渡し燃料")
 check(st.current_weight()==weight0+TownDB.DELIVERY_PARCEL_WEIGHT and roundtrip(),"配達荷物の積載会計と往路途中保存")
 check(act("cancel_delivery") and not t.delivery_cargo and is_equal_approx(main.base.fuel,TownDB.DELIVERY_FUEL_ADVANCE),"取消は荷物を消し、前渡し燃料を返金・再発行しない")
 check(act("accept_delivery") and is_equal_approx(main.base.fuel,TownDB.DELIVERY_FUEL_ADVANCE),"取消再受注で前渡し燃料を無限取得できない")
 main.world.region=TownDB.DELIVERY_TO;main.world.phase="arriving";t.observe()
 check(t.delivery=="outbound" and t.delivery_cargo and t.field_status_text().contains("停車"),"交易村の通過・到着中は配達未完了で停車引渡しを表示")
 main.world.phase="stopped";t.observe()
 check(t.delivery=="return" and not t.delivery_cargo and roundtrip(),"目的地停泊で専用荷物だけ配達済みにし保存")
 main.world.region="central_trade";t.observe()
 check(t.delivery=="ready" and act("claim_delivery") and not act("claim_delivery") and t.claimed.delivery==1,"都市帰還後だけ配達報酬を一度受領")
 await city();t=main.town;main.base.fuel=GameData.FUEL_CAP
 var full_quote:Dictionary=t.quote("accept_delivery")
 check(full_quote.ok and full_quote.text.contains("今回 0.0") and t.execute(full_quote) and is_equal_approx(main.base.fuel,GameData.FUEL_CAP) and is_equal_approx(t.delivery_advance_given,0.0),"満タン受注は前渡し済みにせず実授与0を明示")
 check(act("cancel_delivery"),"満タン受注の取消は前渡し残額を消費しない")
 main.base.fuel=95.0
 check(act("accept_delivery") and is_equal_approx(main.base.fuel,100.0) and is_equal_approx(t.delivery_advance_given,5.0) and is_equal_approx(t.delivery_advance_remaining(),5.0),"部分空きでは実際の5だけ前渡しし残額を保持")
 check(act("cancel_delivery"),"部分前渡しの取消は荷物だけを消し残額は保持")
 main.base.fuel=90.0
 check(act("accept_delivery") and is_equal_approx(main.base.fuel,95.0) and is_equal_approx(t.delivery_advance_given,TownDB.DELIVERY_FUEL_ADVANCE),"再受注は残額5だけを渡し前渡し増殖を防ぐ")
 check(act("cancel_delivery"),"前渡し累計済みの取消を許可")
 var legacy_advance:=SaveGame.capture(main);legacy_advance.town.erase("delivery_advance_given");legacy_advance.town["delivery_advance_issued"]=true
 check(SaveGame.apply(main,legacy_advance) and is_equal_approx(t.delivery_advance_given,TownDB.DELIVERY_FUEL_ADVANCE),"旧bool前渡し保存を実授与量へ移行")
 await city();t=main.town;st=main.storage;st.inventory.counts={GameData.Item.FOOD:st.max_weight()}
 check(not act("accept_delivery"),"満載倉庫では預かり荷物の配達受注を拒否")
 check(act("accept_recovery"),"満載でも回収依頼は受注できる（現地で容量待ち）")
 main.world.region=TownDB.RECOVERY_TO;main.world.phase="stopped";t.observe()
 var capacity_wait:bool=t.recovery_job_for(main.workers[0])==0 and t.recovery=="site"
 main.world.region="central_trade";t.observe()
 check(capacity_wait and act("cancel_recovery"),"満載時は回収役を出発させず、取消で通常素材を増やさない")
 await city();t=main.town;st=main.storage;st.inventory.counts.clear()
 check(act("accept_recovery") and t.recovery=="outbound","遺失物回収を受注")
 main.world.region=TownDB.RECOVERY_TO;main.world.phase="stopped";main.operations.set_stance("normal");t.observe()
 check(TownDB.RECOVERY_POINT.y>=520.0,"recovery parcel is placed on the ground")
 var recovery_worker=main.workers[0]
 recovery_worker.position=Vector2(614.0,GameData.LO_Y);recovery_worker.floor_i=1;recovery_worker._climb_dest=null
 check(t.recovery_job_for(recovery_worker)==1 and t.recovery=="loading" and not main.world.request("central_trade"),"active recovery blocks a regional departure")
 main.world.cancel_or_return();t.release_recovery_worker(recovery_worker)
 check(t.recovery=="site","指定地点への実停泊で回収待ち")
 check(await until(func():return t.recovery=="loading",20),"仲間が既存の安全判定を通って遺失物へ向かう")
 check(roundtrip() and t.recovery=="loading","仲間が向かう途中の回収を保存復元")
 check(await until(func():return t.recovery=="return",80),"仲間が専用荷物を移動拠点へ運び込む")
 check(st.current_weight()==TownDB.RECOVERY_PARCEL_WEIGHT,"回収荷物は通常素材を増やさず重量だけを使う")
 main.world.region="central_trade";main.world.phase="stopped";t.observe()
 check(t.recovery=="ready" and act("cancel_recovery") and t.recovery=="idle" and st.current_weight()==0,"回収後取消は報酬なし・専用荷物を消し素材を増やさない")
 await city();t=main.town;st=main.storage;st.inventory.counts.clear()
 check(act("accept_recovery"),"回収中断ケースの依頼を受注")
 main.world.region=TownDB.RECOVERY_TO;main.world.phase="stopped";t.observe()
 var interrupted=main.workers[0];interrupted.position=Vector2(614.0,GameData.LO_Y);interrupted.floor_i=1;interrupted.down=false
 var started_interrupt:bool=t.recovery_job_for(interrupted)==1 and t.recovery=="loading"
 interrupted.down=true;t.observe()
 var injury_released:bool=t.recovery=="site" and t.recovery_worker==-1
 interrupted.down=false
 var abandoned_field:bool=t.abandon_recovery_from_field()
 var departure_after_abandon:bool=main.world.request("central_trade")
 check(started_interrupt and injury_released and abandoned_field and t.recovery=="idle" and interrupted.ai.return_request and departure_after_abandon,"負傷中断は仲間を残さず現地断念後に帰還でき、別地域で拾わない")
 main.world.cancel_or_return()
 await city();t=main.town
 var d:=SaveGame.capture(main);d.erase("town")
 check(SaveGame.apply(main,d) and t.credits==0 and t.delivery=="idle" and t.recovery=="idle","旧v3のtown省略は0 Cr・依頼なし")
 d=SaveGame.capture(main)
 d.town={"credits":7,"supply":"idle","delivery":"idle","help":"ready","help_left":0.0,"helper":0,"claimed":{"supply":0,"delivery":0,"help":0}}
 check(SaveGame.apply(main,d) and t.legacy_help_credit==24 and act("claim_legacy_help") and t.credits==31,"旧街内勤務の未受領分だけを一度移行し、新規勤務は復活させない")
 d=SaveGame.capture(main);d.town.credits=-1
 check(not SaveGame.apply(main,d),"負の通貨を拒否")
 d=SaveGame.capture(main);d.town.recovery="carried";d.town.recovery_worker=-1
 check(not SaveGame.apply(main,d),"回収中の担当者欠落を拒否")
 main.world.region="south_oasis"
 check(not act("accept_delivery") and t.entry_reason()!="","都市以外は取引・受注禁止")
 check(is_equal_approx(GameData.FUEL_CAP/(60*GameData.FUEL_PER_PX),900),"15分満タンの距離式")
 print("SUBQUEST_UNIT rewards supply=24 delivery=32 recovery=38 advance_fuel=",TownDB.DELIVERY_FUEL_ADVANCE," weights=",TownDB.DELIVERY_PARCEL_WEIGHT,"/",TownDB.RECOVERY_PARCEL_WEIGHT)
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
