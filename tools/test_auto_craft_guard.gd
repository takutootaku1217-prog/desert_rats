extends "res://tools/test_batch_crafting.gd"
func _initialize():
 await setup()
 main.finish_build("workbench")
 var st=main.storage;var p=main.processor;var w=main.workers[0]
 st.inventory.counts={GameData.Item.WOOD:2,GameData.Item.STONE:2,GameData.Item.IRON:1}
 check(main.choose_recipe().is_empty(),"注文なしで道具を自動製作しない")
 main.refill_settings=ProductionPlan.defaults()
 check(not main.choose_recipe().is_empty(),"木2・鉄1・板0でも消耗品補充が相互保護で停止しない")
 st.inventory.counts.erase(GameData.Item.IRON)
 check(not main.choose_recipe().is_empty(),"木2・鉄0でも補充開始可能")
 for s in main.refill_settings.values():s.enabled=false
 main.request_order("tool_pick",1)
 check(main.choose_recipe().is_empty() and AutoCraftGuard.available(main,GameData.Item.WOOD,null,true)==2,"不足注文は木材を予約しない")
 main.request_order("tool_wood_pick",1)
 check(main.choose_recipe().get("id")=="tool_wood_pick","不足注文を飛ばして製作可能な明示注文を選ぶ")
 w.priorities[GameData.Job.HAUL]=5
 check(w.ai._try_start(GameData.Job.HAUL),"注文材料の搬入を引受け")
 check(main.production_orders.size()==1 and p.incoming.size()==1,"引受け時に待ち注文から一回だけ移す")
 check(AutoCraftGuard.available(main,GameData.Item.WOOD,null,true)==0,"別の仲間・移送は予約木材を使えない")
 check(main.request_transfer(GameData.Item.WOOD,2,"to_workshop")==0,"手動移送との重複予約を防ぐ")
 check(roundtrip(),"搬入前予約と不足注文の保存復元")
 check(main.cancel_manual_craft("tool_wood_pick")==1 and p.incoming.is_empty() and st.count_of(GameData.Item.WOOD)==2,"搬入前取消で予約だけ解放・素材不変")
 main.cancel_manual_craft("tool_pick")
 main.request_order("tool_wood_pick",1)
 check(w.ai._try_start(GameData.Job.HAUL),"再注文を引受け")
 w.ai._release_task();w.ai._set_state(CharacterAI.State.SEARCH)
 check(main.production_orders.size()==1 and p.incoming.is_empty(),"割込み時に未搬出注文を待ちへ戻す")
 check(roundtrip(),"中断後の保存復元")
 main.cancel_manual_craft("tool_wood_pick")
 main.refill_settings=ProductionPlan.defaults()
 main.request_order("tool_wood_pick",1)
 check(main.choose_recipe().get("id")=="tool_wood_pick","通常は手動注文を補充より優先")
 main.base.parts[GameData.Part.HULL]=10.0
 check(main.choose_recipe().get("out")==GameData.Item.REPAIR_KIT,"危険水準の修理板を手動注文より優先")
 main.base.parts[GameData.Part.HULL]=100.0
 main.cancel_manual_craft("tool_wood_pick")
 main.refill_settings[GameData.Item.FUEL].target=1
 main.refill_settings[GameData.Item.REPAIR_KIT].enabled=false
 var fuel:=GameData.recipe_by_id("firewood").duplicate(true);p.reserve(fuel)
 check(main.choose_recipe().is_empty(),"加工予定1を一度だけ数え目標超過を防ぐ")
 p.incoming.clear();w.carrying=GameData.Item.FUEL;w.carry_n=1;w.ai.state=CharacterAI.State.MOVE_TO_STORAGE
 check(main.choose_recipe().is_empty(),"完成品運搬中も補充在庫へ計上")
 w.carrying=-1;w.ai.state=CharacterAI.State.SEARCH
 main.set_procurement(GameData.Item.WOOD,5);main.set_procurement(GameData.Item.WOOD,5)
 check(main.procurement_goals.size()==1 and main.gather_weight(GameData.Item.WOOD)==30.0,"目標再送は重複せず優先採取")
 main.set_procurement(GameData.Item.WOOD,2);main.update_procurement()
 check(main.procurement_goals.is_empty(),"数量変更で達成した目標を終了")
 main.set_procurement(GameData.Item.WOOD,6);main.set_procurement(GameData.Item.WOOD,0)
 check(main.procurement_goals.is_empty(),"採取目標取消")
 main.set_procurement(GameData.Item.WOOD,6)
 check(roundtrip(),"補充ON/OFF・目標在庫・採取目標を保存")
 var old:=SaveGame.capture(main);old.erase("production")
 check(SaveGame.apply(main,old) and main.production_orders.is_empty() and main.refill_settings==ProductionPlan.legacy_settings(old.main.recipe_priority),"旧セーブは注文自動生成なし・補充ON/OFFを旧方針から移行")
 var bad:=SaveGame.capture(main);bad.production.goals={GameData.Item.WOOD:-1}
 check(not SaveGame.validate(bad,main),"不正な目標数量を拒否")
 check(main.storage.current_weight()+main.storage.processing_reserve()<=main.storage.max_weight(),"所有重量と予約が容量内")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
