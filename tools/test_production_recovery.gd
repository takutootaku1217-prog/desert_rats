extends "res://tools/test_batch_crafting.gd"
const WOOD=GameData.Item.WOOD
const IRON=GameData.Item.IRON
func _initialize():
 await allocation()
 await workshop_orders()
 await goals()
 await interruptions()
 await haul_rescue_cargo()
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
func haul_rescue_cargo():
 # HAUL_MOVE's `carrying` field is only a lead-item marker. Interrupt a real
 # two-material haul through the down/rescue path and verify each input exists
 # once (including after a real save/apply) before it is returned to storage.
 await setup();main.finish_build("workbench")
 main.storage.inventory.counts={}
 main.request_order("tool_pick",1)
 main.storage.inventory.counts={WOOD:2,IRON:1}
 var hauler=main.workers[0]
 var rescue_carrier=main.workers[1]
 hauler.priorities[GameData.Job.HAUL]=5
 check(hauler.ai._try_start(GameData.Job.HAUL),"two-material haul begins before rescue interruption")
 hauler.position=main.storage.access_point()+hauler.slot_offset
 hauler.floor_i=1
 hauler.ai.tick(0.2)
 check(hauler.ai.state==CharacterAI.State.HAUL_MOVE,"two-material recipe reaches real HAUL_MOVE")
 CrewStatus.damage(hauler,999)
 check(hauler.carrying>=0 and ((hauler.carry_n if hauler.carrying==WOOD else 0)+int(hauler.carry_bonus.get(WOOD,0)))==2 and ((hauler.carry_n if hauler.carrying==IRON else 0)+int(hauler.carry_bonus.get(IRON,0)))==1,"downed HAUL_MOVE owns each reserved input exactly once")
 check(main.storage.count_of(WOOD)==0 and main.storage.count_of(IRON)==0 and main.processor.incoming.is_empty(),"rescue interruption releases the reservation without duplicating its materials")
 var carried_save:=SaveGame.capture(main)
 check(SaveGame.validate(carried_save,main) and SaveGame.apply(main,carried_save),"interrupted multi-material haul round-trips through save")
 hauler=main.workers[0]
 rescue_carrier=main.workers[1]
 check(((hauler.carry_n if hauler.carrying==WOOD else 0)+int(hauler.carry_bonus.get(WOOD,0)))==2 and ((hauler.carry_n if hauler.carrying==IRON else 0)+int(hauler.carry_bonus.get(IRON,0)))==1 and main.processor.incoming.is_empty(),"saved HAUL interruption keeps exact personal cargo and no stale reservation")
 for w in main.workers:w.set_process(false)
 hauler.position=Vector2(900,GameData.LO_Y)
 rescue_carrier.position=Vector2(700,GameData.LO_Y)
 check(main.rescue.assign(rescue_carrier,hauler),"carrier accepts interrupted multi-material haul")
 for n in 1200:
  main.rescue.carrier_tick(rescue_carrier,0.1)
  if not hauler.down:break
 check(not hauler.down and main.storage.count_of(WOOD)==2 and main.storage.count_of(IRON)==1,"rescue delivery returns each interrupted haul material once")

func allocation():
 await setup();main.finish_build("workbench");main.refill_settings=ProductionPlan.defaults()
 var st=main.storage
 st.inventory.counts={WOOD:1,IRON:1,GameData.Item.FUEL:8,GameData.Item.FOOD:12}
 main.request_order("tool_pick",1)
 check(main.choose_recipe().is_empty(),"A 木不足の鉄道具注文の鉄・木を通常補充から確保")
 check(AutoCraftGuard.available(main,IRON)==1,"論理保護は物理在庫・移送を予約しない")
 check(roundtrip() and main.choose_recipe().is_empty(),"未着手の論理保護は保存後も再計算")
 main.base.parts[GameData.Part.HULL]=10
 check(main.choose_recipe().get("id")=="repair_iron","緊急修理は注文素材より優先")
 main.base.parts[GameData.Part.HULL]=100
 main.cancel_manual_craft("tool_pick")
 check(main.choose_recipe().get("id")=="repair_iron","注文取消で通常補充へ素材を解放")
 st.inventory.counts[GameData.Item.STONE]=1
 check(main.choose_recipe().get("id")=="repair_stone","同じ修理板は鉄より石レシピを優先")
 main.request_order("tool_pick",1);st.inventory.counts[WOOD]=2
 main.request_order("tool_wood_pick",1);st.inventory.counts[IRON]=0
 check(main.choose_recipe().get("id")=="tool_wood_pick","不足注文の保護で前提の明示道具注文を塞がない")
 main.base.fuel=0;st.inventory.counts[GameData.Item.FUEL]=0
 check(main.choose_recipe().get("out")==GameData.Item.FUEL,"緊急燃料は不足注文の木保護を越えて製作可能")
 check(main.refill_settings==ProductionPlan.defaults(),"既定の12/8/6・ONを変更していない")
 main.production_orders.clear();st.inventory.counts={WOOD:2,GameData.Item.STONE:1,GameData.Item.FOOD:12}
 main.base.fuel=100
 check(main.choose_recipe().get("id")=="firewood","E 停泊時も通常の燃料8補充が修理板より先（既存順維持）")
 main.base.parts[GameData.Part.HULL]=10
 check(main.choose_recipe().get("id")=="repair_stone","E 危険水準なら通常燃料より修理を優先")
 # 引受け済みの通常補充も、搬出前に新規注文の保護を再確認。
 await setup();main.finish_build("workbench");main.refill_settings=ProductionPlan.defaults()
 st=main.storage;st.inventory.counts={WOOD:1,IRON:1,GameData.Item.FUEL:8,GameData.Item.FOOD:12}
 var w=main.workers[0]
 check(w.ai._try_start(GameData.Job.HAUL),"通常補充を一度引受け")
 main.request_order("tool_pick",1)
 w.position=main.storage.access_point()+w.slot_offset;w.floor_i=1
 w.ai.tick(0.2)
 check(main.processor.incoming.is_empty() and st.count_of(IRON)==1,"搬出前の注文追加でも通常補充の横取りを取消")
func workshop_orders():
 await setup();main.finish_build("workbench")
 main.storage.inventory.counts={WOOD:2}
 main.request_order("tool_wood_pick",1)
 check(main.request_transfer(WOOD,2,"to_workshop")==2,"B 注文後にF相当の素材運搬")
 var w=main.workers[0];w.priorities[GameData.Job.HAUL]=5;w.priorities[GameData.Job.PROCESS]=5
 check(roundtrip(),"注文後・素材運搬前を保存復元")
 check(await until(func():return main.total_crafted_by_hand==1 and main.processor.pending_of(GameData.Item.WOOD_PICK)==0,180),"作業場へ移した材料から1回だけ加工して収納")
 check(main.production_orders.is_empty() and main.craft_queue.is_empty() and main.workshop_count(WOOD)==0 and main.storage.count_of(WOOD)==0,"作業場注文の二重消費・未着手残留なし")
 check(roundtrip(),"完了後も保存一致")
func goals():
 await setup();main.finish_build("workbench")
 main.storage.inventory.counts={WOOD:2};main.request_order("tool_wood_pick",1)
 var w=main.workers[0];w.ai._try_start(GameData.Job.HAUL)
 main.set_procurement(WOOD,2);main.update_procurement()
 check(main.procurement_goals.has(WOOD) and main.procurement_available(WOOD)==0,"C 実予約在庫は採取目標達成に使わない")
 check(main.gather_free_for(WOOD,{})==2,"予約済み箱在庫があっても不足2を採取可能")
 main.cancel_manual_craft("tool_wood_pick");main.update_procurement()
 check(main.procurement_goals.is_empty(),"取消で利用可能になった在庫は目標達成")
 main.request_transfer(WOOD,2,"to_workshop");main.set_procurement(WOOD,2)
 check(main.procurement_available(WOOD)==0 and main.procurement_transit(WOOD)==2 and main.gather_free_for(WOOD,{})==0,"内部移送予定は元在庫と二重に数えない")
 var n:int=main.begin_transfer_trip(WOOD,"to_workshop",w)
 w.carrying=WOOD;w.carry_n=n;w.ai.state=CharacterAI.State.XFER_MOVE;w.ai.xfer_dir="to_workshop"
 check(main.procurement_available(WOOD)==0 and main.procurement_transit(WOOD)==2,"搬出後も移送数は一度だけ")
 main.finish_transfer_trip(WOOD,"to_workshop",n);w.carrying=-1;w.carry_n=1;w.ai.state=CharacterAI.State.SEARCH
 main.update_procurement()
 check(main.procurement_available(WOOD)==2 and main.procurement_transit(WOOD)==0 and main.procurement_goals.is_empty(),"作業場到着で利用可能数へ移り達成")
 main.set_procurement(WOOD,5)
 check(main.gather_free_for(WOOD,{WOOD:2})==1,"採取予約・作業場在庫も同じ目標式で一度だけ差引き")
 check(roundtrip(),"採取目標と移送後の在庫を保存復元")
func interruptions():
 for loaded in [false,true]:
  for cause in ["撤退","負傷","戦闘"]:
   await setup();main.finish_build("workbench");main.storage.inventory.counts={WOOD:2};main.request_order("tool_wood_pick",1)
   var w=main.workers[0]
   w.ai._try_start(GameData.Job.HAUL)
   if loaded:
    check(await until(func():return w.ai.state==CharacterAI.State.HAUL_MOVE,90),cause+"の搬出を実行")
   check(roundtrip(),cause+"前の搬入予約/運搬を保存")
   w=main.workers[0]
   if cause=="負傷":CrewStatus.damage(w,100)
   else:
    w.floor_i=0;w.position=Vector2(1050,680);w._climb_dest=null
    if cause=="撤退":main.operations.set_stance("recall")
    else:
     var enemy:=Enemy.new();enemy.setup_kind(main,"sand_stalker");enemy.ecological=true;enemy.position=w.position+Vector2(20,0);enemy.home_x=enemy.position.x;main.enemies_root.add_child(enemy)
    w.ai.tick(0.2)
   if loaded and w.down:
    check(w.carrying==WOOD and main.processor.incoming.is_empty() and main.production_orders.size()==1 and main.storage.count_of(WOOD)==0,"down retains the worker's reserved cargo for rescue")
    check(roundtrip(),"down state and personal cargo save")
    continue
   if not loaded or cause=="負傷":
    check(main.processor.incoming.is_empty() and main.production_orders.size()==1 and main.storage.count_of(WOOD)==2,cause+"で予約解放・注文復帰・木2保持")
   else:
    check(w.carrying==WOOD and main.processor.incoming.size()==1,cause+"でも搬出済み材料を保持")
    check(await until(func():return main.processor.incoming.is_empty(),180),cause+"の後に実運搬を完了")
    check(main.processor.orders.size()==1 and main.storage.count_of(WOOD)==0,cause+"で加工材料を一度だけ搬入")
   check(roundtrip(),cause+"割込後の数量・状態を保存復元")
