extends "res://tools/test_batch_crafting.gd"
func city() -> void:
 await setup()
 main.world.active=true;main.world.region="central_trade";main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination=""
 main.quarry.state="road"
 for w in main.workers:
  w.stop_work();w.position=Vector2(700,GameData.LO_Y);w.floor_i=1;w._climb_dest=null
 main.world._ensure_location()
func act(a:String,it:int=-1,n:int=1) -> bool:
 return main.town.execute(main.town.quote(a,it,n))
func _initialize():
 await city()
 check(TownDB.MISSIONS.size()==3 and TownDB.MISSIONS.values().all(func(m):return m.category=="sub" and m.repeatable) and TownDB.MISSION_CATEGORIES.has("main"),"3種は繰り返しサブクエスト・メインは分類のみ")
 var t=main.town;var st=main.storage
 check(t.entry_reason()=="" and not t.quote("buy",GameData.Item.FOOD).ok,"都市で入場可能・資金0の購入拒否")
 check(act("accept_help") and not act("accept_help"),"資源なしで手伝い受注・重複拒否")
 t.work(12.0);check(is_equal_approx(t.help_left,18) and roundtrip() and t.help=="working","途中保存で残り18秒保持")
 check(not act("claim_help"),"途中受領禁止")
 t.work(17.9);check(t.help=="working","即時完了しない")
 t.work(0.1);var q:Dictionary=t.quote("claim_help")
 check(t.execute(q) and not t.execute(q) and t.credits==24,"1回だけ報酬受領")
 check(roundtrip() and not act("claim_help") and t.claimed.help==1,"ロード後も受領済みで二重受領なし")
 check(act("buy",GameData.Item.FOOD,2) and t.credits==16 and st.count_of(GameData.Item.FOOD)==2,"食料2個購入・8支払い")
 q=t.quote("buy",GameData.Item.FUEL)
 t.credits=0;check(not t.execute(q) and st.count_of(GameData.Item.FUEL)==0,"見積後の資金変化で原子的拒否")
 t.credits=100;st.inventory.counts={GameData.Item.FOOD:st.max_weight()}
 check(not act("buy",GameData.Item.FOOD),"満載で購入・支払いなし")
 st.inventory.counts={GameData.Item.WOOD:5,GameData.Item.IRON:1}
 main.request_order("tool_pick",1)
 check(t.available(GameData.Item.WOOD)==3 and not act("sell",GameData.Item.WOOD,5),"注文素材は売却保護")
 check(act("sell",GameData.Item.WOOD,2),"余剰だけ売却")
 main.request_transfer(GameData.Item.WOOD,2,"to_workshop")
 check(t.available(GameData.Item.WOOD)==0 and not act("sell",GameData.Item.WOOD),"運搬予約と注文保護を売らない")
 check(not act("sell",GameData.Item.SIMPLE_SPEAR),"装備品は買い取り対象外")
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
 check(act("accept_supply"),"納品受注")
 st.inventory.counts={GameData.Item.WOOD:3};main.request_transfer(GameData.Item.WOOD,1,"to_workshop")
 check(not act("claim_supply") and st.count_of(GameData.Item.WOOD)==3,"予約素材の納品を原子的拒否")
 main.cancel_transfers();q=t.quote("claim_supply")
 check(t.execute(q) and not t.execute(q) and st.count_of(GameData.Item.WOOD)==0 and t.claimed.supply==1,"納品素材3を一度だけ消費・報酬一度")
 check(roundtrip() and not act("claim_supply"),"納品受領後ロード")
 check(act("accept_delivery"),"配達受注")
 check(roundtrip() and t.delivery=="outbound","配達往路保存")
 main.world.region=TownDB.DELIVERY_TO;t.observe();check(t.delivery=="return" and roundtrip(),"村の停泊で配達・復路保存")
 main.world.region="central_trade";t.observe()
 check(t.delivery=="ready" and act("claim_delivery") and not act("claim_delivery"),"都市帰還後だけ配達報酬1回")
 for kind in ["supply","delivery","help"]:
  check(act("accept_"+kind) and act("cancel_"+kind) and not act("claim_"+kind),"受注取消・無報酬 "+kind)
 var d:=SaveGame.capture(main);d.erase("town")
 check(SaveGame.apply(main,d) and t.credits==0 and t.help=="idle","旧v3の省略項目は0 Cr・依頼なし")
 d=SaveGame.capture(main);d.town.credits=-1
 check(not SaveGame.apply(main,d),"負の通貨を拒否")
 d=SaveGame.capture(main);d.town.help_left=NAN
 check(not SaveGame.apply(main,d),"不正な進捗拒否")
 main.world.region="south_oasis"
 check(not act("accept_help") and t.entry_reason()!="","都市以外は取引・受注禁止")
 check(is_equal_approx(GameData.FUEL_CAP/(60*GameData.FUEL_PER_PX),900),"15分満タンの距離式")
 print("FUEL_COMPARE 15min=900s / 30min=1800s; 4800px roundtrip=",4800*GameData.FUEL_PER_PX," / ",4800*100.0/(60*30*60))
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
