extends "res://tools/test_batch_crafting.gd"
func _initialize():
 await setup()
 main.finish_build("workbench")
 var st=main.storage;var p=main.processor;var w=main.workers[0]
 w.priorities[GameData.Job.GATHER]=5
 var adv:=GameData.recipe_by_id("tool_adv_pick")
 st.inventory.counts={GameData.Item.IRON:1,GameData.Item.REPAIR_KIT:3}
 var before:Dictionary=st.inventory.counts.duplicate()
 check(not AutoCraftGuard.allows(main,adv) and st.inventory.counts==before,"自動高性能道具は最後の修理板3を消費しない・判定は無変更")
 main.recipe_priority["tool_adv_pick"]=5
 check(main.choose_recipe().is_empty(),"優先度5でも自動の修理備蓄保護")
 st.inventory.counts[GameData.Item.REPAIR_KIT]=6
 check(AutoCraftGuard.allows(main,adv),"余剰3個を得れば自動強化を再開可能")
 var selected:Dictionary=main.choose_recipe()
 check(selected.get("id","")=="tool_adv_pick" and selected.get("automatic",false),"自動選択の由来を保存可能な注文に記録")
 w.ai.haul_recipe=selected;w.ai._set_state(CharacterAI.State.HAUL_TAKE);p.reserve(selected)
 check(AutoCraftGuard.allows(main,selected,w) and not AutoCraftGuard.allows(main,adv),"自分の予約は一度だけ、他人の予約は二重消費しない")
 check(roundtrip(),"未搬出の自動予約・在庫・積載を保存復元")
 st.inventory.counts[GameData.Item.REPAIR_KIT]=3
 w.position=st.access_point()+w.slot_offset;w.floor_i=1
 w.ai.tick(0.2)
 check(st.count_of(GameData.Item.REPAIR_KIT)==3 and w.ai.haul_recipe.is_empty() and p.incoming.is_empty(),"搬出前に不足したら消費せず予約を解除")
 st.inventory.counts[GameData.Item.REPAIR_KIT]=6
 check(main.choose_recipe().get("id","")=="tool_adv_pick","補充後に自動注文が再開")
 main.request_transfer(GameData.Item.REPAIR_KIT,3,"to_workshop")
 check(not AutoCraftGuard.allows(main,adv),"手動運搬へ予約した3個を自動強化に流用しない")
 main.cancel_transfers()
 p.stock.add(GameData.Item.REPAIR_KIT,3);p.stock.add(GameData.Item.IRON,1)
 check(main.request_craft("tool_adv_pick",1)==1,"Fの明示製作は備蓄保護で拒否しない")
 var mass:int=st.current_weight();main._feed_crafts()
 check(p.orders.size()==1 and p.orders[0].get("manual",false) and not p.orders[0].get("automatic",false),"手動注文を自動注文と区別")
 check(roundtrip() and st.current_weight()==mass,"手動注文・積載・予約の保存互換")
 p.work(7,func(_f):return 1.0)
 check(p.output.has(GameData.Item.ADV_PICK) and p.stock.count(GameData.Item.REPAIR_KIT)==0,"明示製作は指定材料を一度だけ消費して完成")
 var old:=adv.duplicate(true)
 check(SaveGame.recipe(old),"automatic項目のない旧注文も有効")
 p.output.clear();p.receive_manual(old);p.orders[0].erase("manual")
 check(roundtrip(),"旧版の投入済み注文を保持して読込")
 p.work(7,func(_f):return 1.0)
 check(p.output.has(GameData.Item.ADV_PICK),"旧版で投入済みの材料は返却/再消費せず完成")
 await setup();main.finish_build("workbench");st=main.storage;p=main.processor;w=main.workers[0]
 w.priorities[GameData.Job.GATHER]=5;w.tools={"mine":GameData.Item.HAMMER,"chop":GameData.Item.AXE}
 main.recipe_priority["tool_pick"]=3;main.recipe_priority["tool_iron_axe"]=3
 var woodfuel:=GameData.recipe_by_id("firewood")
 st.inventory.counts={GameData.Item.WOOD:3,GameData.Item.STONE:2,GameData.Item.IRON:1,GameData.Item.FUEL:2}
 check(not AutoCraftGuard.allows(main,woodfuel),"薪は修理用木1＋次の鉄道具用木2を使い切らない")
 check(AutoCraftGuard.allows(main,GameData.recipe_by_id("tool_pick")),"木3なら鉄道具に2を使い修理用1を残す")
 st.inventory.counts[GameData.Item.WOOD]=2
 check(not AutoCraftGuard.allows(main,GameData.recipe_by_id("tool_pick")),"修理板不足時は鉄道具も修理用木1を保護")
 main.base.parts[GameData.Part.HULL]=10
 check(AutoCraftGuard.allows(main,GameData.recipe_by_id("repair_stone")),"緊急修理は鉄道具用の木より優先")
 st.inventory.counts[GameData.Item.FUEL]=0;main.base.fuel=0
 check(AutoCraftGuard.allows(main,woodfuel),"燃料枯渇時の既存救済を維持")
 main.base.fuel=100;st.inventory.counts[GameData.Item.WOOD]=10
 check(AutoCraftGuard.allows(main,woodfuel),"十分な補充で通常の薪作りを再開")
 st.inventory.counts[GameData.Item.REPAIR_KIT]=6
 w.ai.repair_part=GameData.Part.HULL;w.ai._set_state(CharacterAI.State.REPAIR_TAKE)
 check(not AutoCraftGuard.allows(main,adv),"修理へ予約中の板を自動強化に二重割当しない")
 w.ai._set_state(CharacterAI.State.SEARCH)
 main.build_queue.append("cargo_rack")
 st.inventory.counts[GameData.Item.WOOD]=10
 var other=main.workers[1]
 other.ai.haul_recipe=GameData.recipe_by_id("tool_pick").duplicate(true)
 other.ai._set_state(CharacterAI.State.HAUL_TAKE)
 check(AutoCraftGuard.available(main,GameData.Item.WOOD)==2,"建設用6＋運搬予約2を合算して保護")
 check(not AutoCraftGuard.allows(main,woodfuel),"建設・運搬・維持の予約を合算して自動薪を拒否")
 other.ai._release_task();other.ai._set_state(CharacterAI.State.SEARCH);main.build_queue.clear()
 var bad:=adv.duplicate(true);bad.automatic="yes"
 check(not SaveGame.recipe(bad),"新しい注文由来の不正型を拒否")
 check(main.storage.current_weight()+main.storage.processing_reserve()<=main.storage.max_weight(),"検査後も総積載＋加工予約が容量内")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
