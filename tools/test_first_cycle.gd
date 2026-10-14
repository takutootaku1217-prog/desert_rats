extends "res://tools/test_batch_crafting.gd"
func _initialize():
 await setup()
 var p=main.processor; var st=main.storage
 main.finish_build("workbench");main.finish_build("cargo_rack")
 var cap:int=st.max_weight()
 main.finish_build("storage_upgrade")
 check(st.max_weight()==cap+120,"収納強化は一段階+120")
 check(not main.request_build("storage_upgrade"),"二段階目を作らない")
 st.store_owned(GameData.Item.HAUL_FRAME);st.store_owned(GameData.Item.WOOD,2);st.store_owned(GameData.Item.IRON,2)
 var cart:=GameData.recipe_by_id("handcart").duplicate(true)
 var mass:int=st.current_weight()
 check(st.take_set(cart["in"]),"手押し車はフレームと木2鉄2を消費")
 p.receive_manual(cart);p.work(6.0,func(_f):return 1.0)
 check(st.current_weight()==mass,"加工で手押し車と材料の重量が一致")
 st.store_owned(p.take_output())
 var w=main.workers[0]
 check(main.equip_work_support(w,GameData.Item.HANDCART) and w.carry_limit()==8 and st.current_weight()==mass,"一人用8個、装備時も重量不変")
 check(roundtrip() and w.carry_limit()==8,"手押し車装備と収納強化を保存復元")
 main.finish_build("parallel_bench")
 p.stock.add(GameData.Item.IRON_ORE,2)
 check(main.request_craft("smelt",2)==2,"二回分を通常依頼")
 main._feed_crafts()
 var fuel:float=main.base.fuel
 p.work(1.0,func(_f):return 1.0);p.second.work(1.0,func(_f):return 1.0)
 check(p.active_recipes().size()==2 and is_equal_approx(fuel-main.base.fuel,6.0),"二枠に別の材料、一度ずつ燃料3を消費")
 check(p.progress==1.0 and p.second.progress==1.0 and p.committed_inputs().get(GameData.Item.IRON_ORE)==2,"独立進捗と二枠の材料重量")
 check(roundtrip(),"二枠加工中のディスク保存復元")
 check(main.cancel_manual_craft("smelt")==0 and p.active_recipes().size()==2,"取消で加工中の二枠を破棄しない")
 check(main.facility_pack_reason("parallel_bench",0)!="","使用中の増設枠は撤去不可")
 p.work(2.5,func(_f):return 1.0)
 check(p.second.progress==1.0 and p.all_output().size()==1,"第一担当だけ進めても第二枠は進まない")
 p.second.work(2.5,func(_f):return 1.0)
 check(p.all_output().size()==2 and p.active_recipes().is_empty() and main.base.fuel==fuel-6,"二回完成、時間燃料を二重課金しない")
 check(roundtrip(),"二枠出力待ちの保存復元")
 # 同じ作業量、能力、資材。現物を入れる境界fixtureと通常進行は別診断。
 var results:=[]
 for parallel in [false,true]:
  await setup();p=main.processor
  if parallel:main.finish_build("parallel_bench")
  p.stock.add(GameData.Item.MEAT,20)
  main.request_craft("cook",20)
  for worker in main.workers:
   worker.priorities[GameData.Job.PROCESS]=5
  var start:float=main.director.elapsed
  var simultaneous:=false
  for i in 3000:
   await step()
   if p.worker!=null and p.second.worker!=null:
    if not simultaneous:
     check(p.worker!=p.second.worker,"同時加工は別の二人")
     check(roundtrip(),"別の二人の担当枠と移動・加工進捗を保存復元")
    simultaneous=true
   if main.storage.count_of(GameData.Item.FOOD)==40:break
  check(main.storage.count_of(GameData.Item.FOOD)==40 and p.total_done==20,"実AIで20材料→40食料を全回収")
  results.append(main.director.elapsed-start)
  check(simultaneous==parallel,"増設時だけ二人が同時加工")
 print("PARALLEL_COMPARE 1枠/2枠 seconds=",results)
 check(results[1]<results[0],"同材料・能力で二枠が速い")
 var trips:=[]
 for support in [-1,GameData.Item.HAUL_FRAME,GameData.Item.HANDCART]:
  await setup();trips_in=0;trips_out=0;last_state=-1;max_load=0
  var worker=main.workers[0]
  main.storage.store_owned(GameData.Item.WOOD,24)
  if support>=0:
   main.storage.store_owned(support);main.equip_work_support(worker,support)
  worker.priorities[GameData.Job.HAUL]=5
  var start:float=main.director.elapsed
  main.request_transfer(GameData.Item.WOOD,24,"to_workshop")
  check(await wait_tick(func():return main.workshop_count(GameData.Item.WOOD)==24),"同じ24木材を実運搬")
  trips.append(trips_in)
  print("CART_COMPARE support=",support," trips=",trips_in," seconds=",main.director.elapsed-start," max_load=",max_load)
  check(max_load<=worker.carry_limit(),"各便は本人の上限内")
 check(trips==[8,5,3],"通常/フレーム/手押し車は8/5/3便、同じ24成果")
 await setup();main.finish_build("parallel_bench")
 main.processor.second.output=[GameData.Item.FOOD]
 main.workers[0].priorities[GameData.Job.PROCESS]=5
 check(await until(func():return main.storage.count_of(GameData.Item.FOOD)==1,90),"第二枠の完成品だけが残った場合も正しい加工台へ移動して回収")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
