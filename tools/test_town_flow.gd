extends "res://tools/test_quarry.gd"
func city_fixture(hull:float=100.0) -> void:
 await fresh()
 main.world.active=true;main.world.region="central_trade";main.world.phase="stopped"
 main.target_speed=60;main.storage.inventory.counts.clear();main.processor.stock.counts.clear();main.base.fuel=0
 for s in main.refill_settings.values():s.enabled=false
 for w in main.workers:w.stop_work();w.floor_i=1;w.position=Vector2(700,GameData.LO_Y);w._climb_dest=null
 main.base.parts[0]=hull;main.world._ensure_location()
func act(a:String,it:int=-1,n:int=1) -> bool:return main.town.execute(main.town.quote(a,it,n))
func travel(to:String) -> bool:
 if not main.world.request(to):return false
 return await until(func():return main.world.region==to and main.world.phase=="stopped",400)
func _initialize():
 await city_fixture()
 var t=main.town
 check(t.credits==0 and main.storage.inventory.counts.is_empty(),"無資金・無資源・無燃料から開始")
 # 3周は同じ有限地図。道具なしでも拾える木材の正規採取を使う。
 for lap in 3:
  var before:int=t.credits
  var food0:int=main.total_eaten
  var hull0:float=main.base.parts[0]
  var hunger0:float=main.workers[0].hunger
  check(act("accept_help"),"勤務受注 %d"%lap)
  main.town_ui.open();main.town_ui.run_shift()
  for i in 300:main.town_ui._process(0.1)
  main.town_ui.stop_clock()
  check(t.help=="ready" and is_equal_approx(main.workers[0].hunger,hunger0) and main.total_eaten==food0 and main.base.parts[0]==hull0,"勤務30秒・維持費0・通常加工停止")
  check(act("claim_help") and t.credits==before+24,"勤務実効収入24")
  main.town_ui.close()
  if lap<2:check(act("accept_delivery"),"近距離配達を受注")
  check(act("buy",GameData.Item.FOOD,2) and act("fuel_cash"),"勤務報酬で食料・燃料を補給")
  if main.base.parts[0]<100:check(act("repair_cash",0),"有料修理")
  check(await travel("south_oasis"),"依頼不要の自由探索で村へ")
  main.operations.set_stance("normal")
  for w in main.workers:w.priorities[GameData.Job.GATHER]=5
  main.gather_policy={GameData.Item.WOOD:5,GameData.Item.STONE:0,GameData.Item.IRON_ORE:0}
  var wood0:int=main.storage.count_of(GameData.Item.WOOD)
  check(await until(func():return main.storage.count_of(GameData.Item.WOOD)>=wood0+3,180),"有限地点から木材3個を正規採取")
  main.operations.set_stance("recall")
  check(await travel("central_trade"),"荷物と仲間を帰還して都市へ")
  for w in main.workers:w.priorities[GameData.Job.GATHER]=0
  if lap<2:check(t.delivery=="ready" and act("claim_delivery"),"実走行の配達報酬を受領")
  check(act("sell",GameData.Item.WOOD,3),"余剰3個売却")
  print("TOWN_LAP ",lap," credits ",before," -> ",t.credits," food_used=",main.total_eaten-food0," fuel=",main.base.fuel," hull=",main.base.parts[0]," time=",main.director.elapsed)
  check(SaveGame.apply(main,SaveGame.capture(main)),"周回ごとの保存復元")
 # 低速帰還は健全車体では可能だが、損傷車体の帰還保証にはならない。
 for hull in [100.0,5.0]:
  await city_fixture(hull)
  main.world.region="south_oasis";main.world._ensure_location()
  var arrived:bool=await travel("central_trade")
  print("EMPTY_RETURN hull_start=",hull," arrived=",arrived," defeat=",main.game_over," elapsed=",main.director.elapsed," hull=",main.base.parts[0])
  check(arrived if hull==100 else main.game_over and not arrived,"空タンク帰還境界 %s"%hull)
  paused=false
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
