extends "res://tools/test_quarry.gd"
var trips_in:=0
var trips_out:=0
var last_state:=-1
var max_load:=0
func setup():
 await fresh();main.target_speed=0
 main.storage.inventory.counts.clear();main.processor.stock.counts.clear()
 for setting in main.refill_settings.values():setting.enabled=false
 main.base.parts[GameData.Part.MACHINE]=100.0
func roundtrip() -> bool:
 var d:=SaveGame.capture(main);SaveGame.disabled=false
 return SaveGame.write(main,"user://batch-test.json",true) and SaveGame.apply(main,SaveGame.read("user://batch-test.json")) and SaveGame.capture(main)==d
func tick():
 await step()
 var w=main.workers[0]
 if w.ai.state!=last_state:
  if w.ai.state==CharacterAI.State.XFER_MOVE:trips_in+=1
  if w.ai.state==CharacterAI.State.MOVE_TO_STORAGE and w.carry_source==Inventory.SOURCE_PROCESSING:trips_out+=1
 last_state=w.ai.state
 if w.carrying>=0:max_load=maxi(max_load,w.carry_n)
func wait_tick(done: Callable):
 for i in 4000:
  if done.call():return true
  await tick()
 return done.call()
func comparison(batch: bool, framed: bool) -> Dictionary:
 await setup();trips_in=0;trips_out=0;last_state=-1;max_load=0
 main.storage.store_owned(GameData.Item.MEAT,6)
 if framed:
  main.storage.store_owned(GameData.Item.HAUL_FRAME,1);main.equip_work_support(main.workers[0])
 var w=main.workers[0];w.priorities[GameData.Job.HAUL]=5;w.priorities[GameData.Job.PROCESS]=5
 var unit:=6 if batch else 1
 for repeat in (1 if batch else 6):
  check(main.request_transfer(GameData.Item.MEAT,unit,"to_workshop")==unit,"材料運搬の依頼")
  check(await wait_tick(func():return main.processor.stock.count(GameData.Item.MEAT)>=unit),"材料を作業場へ実運搬")
  check(main.request_craft("cook",unit)==unit,"同じ材料と単位時間の注文")
  if batch:check(roundtrip(),"複数回未投入予約の保存復元")
  check(await wait_tick(func():return main.storage.count_of(GameData.Item.FOOD)==(12 if batch else (repeat+1)*2)),"全成果を実AIで回収")
 check(main.processor.total_done==6 and main.total_crafted_by_hand==6 and main.storage.count_of(GameData.Item.MEAT)==0 and main.processor.stock.count(GameData.Item.MEAT)==0,"6単位加工・12成果・6材料を過不足なく計上")
 check(max_load<=w.carry_limit(),"投入/回収の全便で本人の3/5個上限内")
 var result:Dictionary={"in":trips_in,"out":trips_out,"max_load":max_load,"seconds":main.director.elapsed,"crafted":main.total_crafted_by_hand}
 print("BATCH_COMPARE batch=",batch," framed=",framed," ",result)
 return result
func _initialize():
 var single:=await comparison(false,false)
 var batch:=await comparison(true,false)
 var framed:=await comparison(true,true)
 check(single["in"]==6 and single["out"]==12 and batch["in"]==2 and batch["out"]<single["out"] and framed["out"]<=batch["out"],"同材料・同成果で投入と回収の両往復が減る")
 await setup()
 var p=main.processor;var st=main.storage
 p.stock.add(GameData.Item.MEAT,2)
 var shortage:=CraftDB.evaluate(CraftDB.entry_of("cook"),main,5)
 check(shortage.state=="short" and shortage.max_qty==2,"材料不足5回を表示し、可能な単発注文へ戻せる")
 main.request_craft("cook",1);main.request_craft("cook",1);main._feed_crafts()
 check(p.orders.size()==2 and p.orders.all(func(r):return not r.get("batch",false)),"単発注文を連打しても明示的まとめ注文へ変換しない")
 p.work(2.5,func(_f):return 1.0)
 check(not p.batch_output and not p.continue_batch(5) and p.take_output_stack(5).n==1,"単発はフレーム上限5でも従来1個ずつ回収")
 check(roundtrip() and not p.batch_output and p.take_output_stack(5).n==1,"単発出力の保存復元も1個ずつ")
 await setup();p=main.processor;st=main.storage
 p.stock.add(GameData.Item.FAT,3)
 st.store_owned(GameData.Item.FOOD,343) # 合計346、余裕14。3回の増量21は不可。
 var ev:=CraftDB.evaluate(CraftDB.entry_of("tallow"),main,3)
 check(ev.state=="blocked" and ev.max_qty==2 and ev.hint.contains("1回"),"全3回の容量不足を表示し少量へ戻せる")
 check(main.request_craft("tallow",2)==2 and st.processing_reserve()==14,"受付時に全2回の正味増量14を予約")
 check(main.request_craft("tallow",1)==0 and st.free_for(GameData.Item.FOOD)==0,"連打/外部取得は増量予約を奪わない")
 check(main.request_transfer(GameData.Item.FAT,3,"to_storage")==1,"まとめ注文の2材料は予約され、余り1個しか移動依頼できない")
 main.cancel_transfers()
 check(roundtrip() and st.processing_reserve()==14,"開始前の容量予約も保存再開")
 check(main.cancel_manual_craft("tallow")==2 and st.processing_reserve()==0,"全量予約を正規取消して容量予約を解放")
 check(main.request_craft("tallow",1)==1 and main.cancel_manual_craft("tallow")==1,"全量が入らない時も単発の正規注文へ戻せる")
 check(st.current_weight()==346 and p.stock.count(GameData.Item.FAT)==3,"取消/少量切替でstock移動による容量回避なし")
 main.request_craft("tallow",2)
 main._feed_crafts()
 check(p.orders.size()==2 and st.processing_reserve()==14 and st.current_weight()==346,"未投入→投入済でも二重予約/二重重量なし")
 p.work(1.0,func(_f):return 1.0)
 var progress:float=p.progress
 check(p.output.is_empty() and progress==1.0 and roundtrip() and p.progress==progress,"途中保存は単位時間の進捗を保持・即完成しない")
 check(main.cancel_manual_craft("tallow")==1 and main.cancel_manual_craft("tallow")==0,"未着手1回だけ返却・取消連打で無増殖")
 check(p.stock.count(GameData.Item.FAT)==2 and p.progress==1.0 and not p.current.is_empty(),"現在1回は保持、投入済未着手分だけ材料返却")
 p.work(1.49,func(_f):return 1.0);check(p.output.is_empty(),"取消/保存で残り1.5秒を短縮しない")
 p.work(0.02,func(_f):return 1.0)
 check(p.output.size()==2 and p.total_done==1 and p.stock.count(GameData.Item.FAT)==2,"1回だけ完了し2成果・未使用2材料")
 check(st.current_weight()==353 and st.processing_reserve()==0,"完了時だけ正味7増加して予約解放")
 var weight:int=st.current_weight();st.store_owned(GameData.Item.FOOD,7)
 check(st.current_weight()==360,"完成品含む満載境界")
 main.workers[0].priorities[GameData.Job.PROCESS]=5
 check(await until(func():return st.count_of(GameData.Item.FUEL)==2,100),"満載でも保有済み2成果を失わず回収")
 check(st.current_weight()==360,"回収は内部移動なので重量不変")
 await setup();p=main.processor
 p.stock.add(GameData.Item.MEAT,5);main.request_craft("cook",5);main._feed_crafts()
 p.work(2.5,func(_f):return 1.0);main._feed_crafts()
 p.work(1.0,func(_f):return 1.0)
 check(p.batch_output and p.output.size()==2 and p.progress==1.0 and roundtrip() and p.batch_output,"完成済2個＋次の単位の仕掛品を分離して保存")
 check(main.cancel_manual_craft("cook")==3 and p.output.size()==2 and p.stock.count(GameData.Item.MEAT)==3,"部分完了後の取消で未着手3材料だけ返す")
 p.work(1.5,func(_f):return 1.0)
 check(p.output.size()==4 and p.stock.count(GameData.Item.MEAT)==3 and p.total_done==2,"取消後の現行1回が完了し、合計4成果と3材料を保持")
 await setup();p=main.processor
 p.stock.add(GameData.Item.IRON_ORE,3);main.base.fuel=100.0
 check(main.request_craft("smelt",3)==3,"燃料付き3回を予約")
 main._feed_crafts()
 for i in 3:
  p.work(3.49,func(_f):return 1.0)
  check(p.total_done==i,"各単位の3.5秒より前は未完成")
  check(roundtrip(),"単位ごとの燃料消費・進捗を保存")
  p.work(0.02,func(_f):return 1.0)
 check(p.total_done==3 and p.output.size()==3 and is_equal_approx(main.base.fuel,91.0),"単位時間3.5×3・材料3・鉄3・燃料3×3を維持")
 await setup();p=main.processor;main.base.add_facility("workbench",true)
 p.stock.add(GameData.Item.WOOD,2);p.stock.add(GameData.Item.IRON,2)
 check(main.request_craft("simple_spear",2)==2,"作業台依存のまとめ製作")
 check(not main.facility_pack_reason("workbench",0).is_empty(),"未投入でも作業台撤去を拒否")
 main._feed_crafts();p.work(1.0,func(_f):return 1.0)
 check(not main.facility_pack_reason("workbench",0).is_empty(),"投入/加工中でも作業台撤去を拒否")
 var w=main.workers[0];w.priorities[GameData.Job.PROCESS]=5
 w.ai._set_state(CharacterAI.State.PROCESS);p.worker=w
 w.set_priority(GameData.Job.PROCESS,0);w.stop_work()
 check(p.progress==1.0 and not p.current.is_empty() and roundtrip(),"担当変更/中断でも投入済と進捗保持")
 p.stock.add(GameData.Item.MEAT,1);main.request_craft("cook",1)
 check(main.cancel_manual_craft("simple_spear")==1 and main.craft_queue.any(func(q):return q.id=="cook"),"レシピ別取消は別品目/現在1回を残す")
 check(p.progress==1.0 and not main.facility_pack_reason("workbench",0).is_empty(),"取消後も進行中設備の依存を保護")
 # 旧形式にbatchタグがなくても単位レシピは再開可能。
 var old:=SaveGame.capture(main)
 old.processor.erase("batch_output")
 old.processor.current.erase("batch")
 for r in old.processor.orders:r.erase("batch")
 for q in old.main.craft_queue:q.erase("batch")
 check(SaveGame.validate(old,main) and SaveGame.apply(main,old),"既存saveのbatch省略を互換維持")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
