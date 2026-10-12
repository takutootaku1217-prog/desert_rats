extends "res://tools/test_quarry.gd"
const ITEM = GameData.Item.HAUL_FRAME
func roundtrip() -> bool:
 var d := SaveGame.capture(main)
 SaveGame.disabled=false
 return SaveGame.write(main,"user://haul-test.json",true) and SaveGame.apply(main,SaveGame.read("user://haul-test.json")) and SaveGame.capture(main)==d
func _initialize():
 await fresh()
 check(FileAccess.file_exists("res://assets/resources/item_haul_frame.png"),"専用画像ファイルが存在（代替画像ではない）")
 main.target_speed=0
 main.base.add_facility("workbench",true)
 for k in main.recipe_priority: main.recipe_priority[k]=0
 for it in GameData.recipe_by_id("haul_frame")["in"]: main.processor.stock.add(it,GameData.recipe_by_id("haul_frame")["in"][it])
 for w in main.workers:
  w.priorities[GameData.Job.PROCESS]=5; w.priorities[GameData.Job.HAUL]=5
 check(main.request_craft("haul_frame",1)==1,"製作注文を受理")
 check(await until(func():return main.storage.count_of(ITEM)==1,180),"実AIで材料消費→時間加工→完成品を倉庫へ")
 for w in main.workers: w.stop_work(); w.priorities[GameData.Job.PROCESS]=0; w.priorities[GameData.Job.HAUL]=0
 var a=main.workers[0]; var b=main.workers[1]
 var weight:int=main.storage.current_weight(); var cap:int=main.storage.max_weight()
 var prior_tools:Dictionary=a.tools.duplicate(); var prior_weapon:int=a.weapon
 check(main.equip_work_support(a) and a.carry_limit()==5,"仕事補助へ装備し3→5")
 check(main.storage.current_weight()==weight and main.storage.max_weight()==cap and a.tools==prior_tools and a.weapon==prior_weapon,"重量不変・拠点容量/武器/道具と独立")
 check(not main.equip_work_support(a) and not main.equip_work_support(b),"連打・在庫0は複製しない")
 check(roundtrip() and a.work_support==ITEM,"装備の保存/ファイル読込/再開")
 main.storage.inventory.counts.clear(); main.processor.stock.counts.clear()
 main.storage.inventory.counts[GameData.Item.FOOD]=cap-CargoDB.size_of(ITEM)
 check(main.storage.current_weight()==cap and main.unequip_work_support(a),"満載でも同重量の倉庫へ解除")
 check(not main.unequip_work_support(a) and main.equip_work_support(b) and main.storage.current_weight()==cap,"解除連打拒否・別個体へ持替え")
 b.set_priority(GameData.Job.HAUL,5); b.stop_work()
 check(b.work_support==ITEM,"仕事切替/中断で保持")
 b.away=true; check(not main.unequip_work_support(b),"遠征中は変更拒否"); b.away=false
 CrewStatus.damage(b,1000)
 check(b.down and b.work_support==ITEM and not main.unequip_work_support(b),"戦闘不能でも保持・変更拒否")
 CrewStatus._tick_hp(b,1000); check(not b.down and b.work_support==ITEM,"復帰で同一装備保持（死亡削除なし）")
 check(main.unequip_work_support(b),"復帰後に解除")
 var old:=SaveGame.capture(main)
 for row in old.crew: row.worker.erase("work_support")
 check(SaveGame.validate(old,main) and SaveGame.apply(main,old) and a.work_support==-1,"旧saveの省略項目は未装備で復元")
 check(not old.crew[0].worker.has("work_support"),"旧snapshotは無改変")
 var bad:=SaveGame.capture(main);bad.crew[0].worker.work_support=GameData.Item.WOOD
 check(not SaveGame.apply(main,bad),"不正装備IDは状態変更前に拒否")
 main.storage.inventory.counts.clear();main.storage.store_owned(ITEM,1)
 check(main.request_transfer(ITEM,1,"to_workshop")==1 and not main.equip_work_support(a),"運搬注文が予約した在庫を装備で奪わない")
 main.cancel_transfers();check(main.equip_work_support(a),"予約取消後だけ装備")
 # 最大荷物を抱えたままの仕事変更・取消・戦闘不能を確認。
 main.storage.inventory.counts.clear();main.processor.stock.counts.clear()
 main.storage.store_owned(GameData.Item.WOOD,10)
 a.priorities[GameData.Job.HAUL]=5; b.priorities[GameData.Job.HAUL]=0
 main.request_transfer(GameData.Item.WOOD,10,"to_workshop")
 check(await until(func():return a.ai.state==CharacterAI.State.XFER_MOVE,60),"5個を積んで運搬開始")
 weight=main.storage.current_weight()
 a.set_priority(GameData.Job.HAUL,0);main.cancel_transfers()
 check(a.carry_n==5 and a.work_support==ITEM,"優先度変更/残注文取消でも現在の5個保持")
 CrewStatus.damage(a,1000)
 check(a.down and a.work_support==ITEM and main.storage.count_of(GameData.Item.WOOD)==10 and main.storage.current_weight()==weight,"運搬中戦闘不能でも10個全量と装備重量を保全")
 CrewStatus._tick_hp(a,1000)
 check(not a.down and a.work_support==ITEM and roundtrip(),"戦闘不能から復帰・保存再開で装備を保持")
 var bare:int=await compare_transfer(false,false)
 var armed:int=await compare_transfer(true,false)
 var changed:int=await compare_transfer(true,true)
 check(bare==5 and armed==3 and changed==5,"同じ15個の実運搬: 基本5便→装備3便。1便目5個で解除後は次から3個")
 print("BENEFIT 15 wood: bare=",bare," framed=",armed," midtrip_off=",changed)
 await fresh()
 main.target_speed=0; park_fixture()
 a=main.workers[0];main.storage.store_owned(ITEM,1);main.equip_work_support(a)
 a.priorities[GameData.Job.GATHER]=5
 check(await until(func():return a.ai.res is GatherPoint,50),"実AIで採取予約")
 var limit:int=a.ai.bag_limit
 check(limit==5 and a.ai.res.reserved==5,"採取予約は装備者5個")
 check(main.unequip_work_support(a) and a.ai.bag_limit==limit and a.ai.res.reserved==limit,"採取中解除でも現便の予約を縮めない")
 check(roundtrip() and a.ai.bag_limit==limit and a.ai.res.reserved==limit,"解除後の採取予約も保存再開")
 check(await until(func():return a.carrying>=0 and a.carry_n==5,160),"解除直後も予約した5個を積める")
 check(await until(func():return a.carrying<0,160),"積荷を切捨てず荷卸し")
 check(await until(func():return a.ai.res is GatherPoint,100) and a.ai.bag_limit==3,"次の採取便から基本3個へ")
 print("== 結果: %s ==" % ("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
func compare_transfer(equip: bool, remove_mid: bool) -> int:
 await fresh();main.target_speed=0
 main.storage.inventory.counts.clear();main.processor.stock.counts.clear()
 for k in main.recipe_priority: main.recipe_priority[k]=0
 main.storage.store_owned(ITEM,1);main.storage.store_owned(GameData.Item.WOOD,15)
 var w=main.workers[0]
 if equip: main.equip_work_support(w)
 w.priorities[GameData.Job.HAUL]=5
 main.request_transfer(GameData.Item.WOOD,15,"to_workshop")
 var trips:=0;var last:=-1;var done:=false;var weight:int=main.storage.current_weight()
 for tick in 2500:
  await step()
  if w.ai.state==CharacterAI.State.XFER_MOVE and last!=CharacterAI.State.XFER_MOVE:
   trips+=1
   if remove_mid and trips==1:
    check(w.carry_n==5 and main.unequip_work_support(w) and w.carry_n==5,"途中解除でも運搬中の5個保持")
    check(roundtrip() and w.carry_n==5,"5個運搬途中・未装備状態の保存復元")
  last=w.ai.state
  if main.processor.stock.count(GameData.Item.WOOD)==15: done=true;break
 check(done and main.storage.count_of(GameData.Item.WOOD)==0 and main.storage.current_weight()==weight,"15個の到着/単一所有/重量保存")
 return trips
