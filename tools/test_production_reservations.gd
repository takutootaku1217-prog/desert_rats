extends "res://tools/test_batch_crafting.gd"
func _initialize():
 await setup()
 main.finish_build("workbench");main.finish_build("parallel_bench")
 var st=main.storage;var p=main.processor
 st.inventory.counts={GameData.Item.WOOD:4}
 main.request_order("tool_wood_pick",2)
 var mass:int=st.current_weight()
 for i in 2:
  var w=main.workers[i]
  w.priorities[GameData.Job.HAUL]=5
  check(w.ai._try_start(GameData.Job.HAUL),"別々の仲間が1回分ずつ引受け")
 check(p.incoming.size()==2 and main.production_orders.is_empty() and st.count_of(GameData.Item.WOOD)==4,"2件の予約は物資を複製・先取りしない")
 check(not main.workers[2].ai._try_start(GameData.Job.HAUL),"3人目には同じ物資を割り当てない")
 check(roundtrip(),"複数搬入予約の保存復元")
 check(await until(func():return p.incoming.is_empty() and p.orders.size()==2,120),"2人が実AIで材料を搬入")
 check(st.count_of(GameData.Item.WOOD)==0 and st.current_weight()==mass,"倉庫→運搬→設備でも所有重量を保持")
 check(roundtrip(),"投入済の2注文を保存復元")
 p.work(1,func(_f):return 1.0);p.second.work(1,func(_f):return 1.0)
 check(not p.current.is_empty() and not p.second.current.is_empty() and p.orders.is_empty(),"2枠が同じ注文を重複せず別々に開始")
 check(main.cancel_manual_craft("tool_wood_pick")==0,"加工中2件を未着手取消で消さない")
 check(roundtrip(),"2枠同時進行を保存復元")
 p.work(10,func(_f):return 1.0);p.second.work(10,func(_f):return 1.0)
 check(p.pending_of(GameData.Item.WOOD_PICK)==2 and main.total_crafted_by_hand==2,"2回の材料から完成品は2個だけ")
 await setup();main.finish_build("workbench")
 st=main.storage;p=main.processor
 st.inventory.counts={GameData.Item.WOOD:2}
 main.request_order("tool_wood_pick",1)
 var w=main.workers[0];w.priorities[GameData.Job.HAUL]=5
 w.ai._try_start(GameData.Job.HAUL)
 check(await until(func():return p.orders.size()==1,120),"未着手取消用の材料を搬入")
 check(main.cancel_manual_craft("tool_wood_pick")==1 and st.count_of(GameData.Item.WOOD)==2 and p.orders.is_empty(),"投入済未着手取消は倉庫へ正確に返却")
 check(main.cancel_manual_craft("tool_wood_pick")==0 and st.count_of(GameData.Item.WOOD)==2,"取消連打で増殖しない")
 # 旧保存で作業場と倉庫に分かれた材料を、通常運搬で合流する。
 st.inventory.counts={GameData.Item.WOOD:1};p.stock.add(GameData.Item.WOOD,1)
 main.request_order("tool_wood_pick",1)
 check(main.transfer_queue.size()==1 and main.transfer_queue[0].dir=="to_storage","分散材料は既存の倉庫戻し運搬を依頼")
 check(await until(func():return p.orders.size()==1,120),"分散材料からも実搬入が進む")
 check(st.count_of(GameData.Item.WOOD)==0 and p.stock.count(GameData.Item.WOOD)==0,"分散した同じ材料を一度だけ使用")
 await setup();st=main.storage;p=main.processor
 st.inventory.counts={GameData.Item.MEAT:2};main.refill_settings[GameData.Item.FOOD]={"enabled":true,"target":1}
 var r:Dictionary=main.choose_recipe();check(r.get("id")=="cook","2個単位のレシピで目標1も補充可能")
 p.reserve(r)
 check(main.choose_recipe().is_empty(),"一回分の出力予定で不足を満たせば追加補充しない")
 p.incoming.clear();p.stock.add(GameData.Item.MEAT,1)
 main.request_craft("cook",1)
 check(ProductionPlan.future(main,GameData.Item.FOOD)==2 and main.choose_recipe().is_empty(),"旧経路の未投入予約も補充の完成予定に一度だけ含む")
 main.set_procurement(GameData.Item.WOOD,2)
 check(main.gather_free_for(GameData.Item.WOOD,{GameData.Item.WOOD:2})==0,"他の採取予約も目標数量から差し引く")
 await setup()
 w=main.workers[0];w.carrying=GameData.Item.WOOD;w.carry_n=2;w.carry_source=Inventory.SOURCE_ENVIRONMENT;w.ai.state=CharacterAI.State.GATHER
 w.ai.retreating=true
 check(not w.ai.store_now(),"収納指示は撤退を上書きしない")
 w.ai.retreating=false
 check(w.ai.store_now() and w.ai.state==CharacterAI.State.MOVE_TO_STORAGE and w.carry_n==2,"採取分を保持して通常収納へ切り替える")
 check(await until(func():return w.carrying<0,120) and main.storage.count_of(GameData.Item.WOOD)==2,"通常帰還は収納まで完了")
 w.carrying=GameData.Item.CARCASS;w.carcass_cargo={GameData.Item.HIDE:1};w.ai.state=CharacterAI.State.MOVE_TO_STORAGE
 check(main.procurement_transit(GameData.Item.HIDE)==1,"獲物として持帰る確定素材も運搬中に計上")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
