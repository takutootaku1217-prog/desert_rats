extends "res://tools/test_quarry.gd"
func enemy_at(kind: String,x: float):
 var e:=Enemy.new();e.setup_kind(main,kind);e.ecological=true;e.position=Vector2(x,680);e.home_x=x;main.enemies_root.add_child(e);return e
func clear_enemies():
 for e in main.enemies_root.get_children():main.enemies_root.remove_child(e);e.free()
func snapshot_ok()->bool:
 var d:=SaveGame.capture(main)
 return SaveGame.write(main,"user://field-check.json",true) and SaveGame.apply(main,SaveGame.read("user://field-check.json")) and SaveGame.capture(main)==d
func _initialize():
 await fresh();main.target_speed=0;main.tool_auto=false
 var w=main.workers[0];var ops=main.operations
 check(ops.set_stance("alert"),"後退は警戒態勢として受理")
 check(ops.can_depart(w,Vector2(1080,680)) and not ops.can_depart(w,Vector2(350,680)),"警戒でも近場採取可、遠い新規往復不可")
 var point:=GatherPoint.new();point.setup(main,"tree");point.position=Vector2(1080,680);point.remaining=10;point.work=0.43;main.resources_root.add_child(point)
 w.floor_i=0;w.position=point.position;w.carrying=GameData.Item.WOOD;w.carry_n=2;w.carry_source=Inventory.SOURCE_ENVIRONMENT
 w.ai.res=point;point.claimed_by=w;w.ai.state=CharacterAI.State.GATHER
 ops.start_outing();ops.outside_seen=true
 var before:int=main.storage.count_of(GameData.Item.WOOD)
 ops.set_stance("recall");w.ai.tick(0.2)
 check(point.remaining==10 and is_equal_approx(point.work,0.43) and w.carry_n==2,"撤退で採取残量・未完進捗・取得済み袋を保全")
 check(snapshot_ok(),"撤退中の袋と進捗を保存復元")
 check(await until(func():return ops.returned_count()==3,180),"全員と荷物が帰還し置去りなし")
 ops.tick()
 check(main.storage.count_of(GameData.Item.WOOD)==before+2 and ops.last_report.items.get(GameData.Item.WOOD,0)==2,"持帰りは倉庫到着した実取得2個だけ")
 ops.start_outing();ops.outside_seen=true
 main.storage.store_owned(GameData.Item.WOOD,1,Inventory.SOURCE_TRANSFER);main.storage.store_owned(GameData.Item.FOOD,2,Inventory.SOURCE_PROCESSING)
 main.total_eaten+=1;main.base.consume_fuel(3.0);main.base.total_repair+=1;ops.tick()
 check(ops.last_report.items.is_empty() and ops.last_report.food==1 and ops.last_report.fuel==3.0 and ops.last_report.repair==1,"内部運搬/加工品を外部成果に数えず消費を別集計")
 ops.set_stance("normal");w.hp=50;w.ai.danger_hold=true
 check(not ops.can_depart(w,Vector2(1080,680)),"負傷直後の再出撃を止める")
 w.hp=100;ops.set_stance("normal")
 for worker in main.workers:worker.floor_i=1;worker.position=Vector2(700,GameData.LO_Y)
 w.floor_i=0;w.position=Vector2(700,680)
 var stalk=enemy_at("sand_stalker",730)
 var hull:float=main.base.parts[GameData.Part.HULL]
 stalk._tick_ecology(1.1)
 check(stalk.target_index==0 and w.hp<100 and main.base.parts[GameData.Part.HULL]==hull,"追跡種は仲間を攻撃し車体は無傷")
 w.ai.tick(0.1)
 check(w.ai.retreating and w.ai.danger_hold,"目視距離の危険を感知し帰還優先")
 w.floor_i=1;w.position=Vector2(700,GameData.LO_Y)
 for i in 30:stalk._tick_ecology(0.5)
 check(stalk.target_index==-1 and stalk.search_left==0 and main.base.parts[GameData.Part.HULL]==hull,"車内の仲間だけで敵意を延長せず短い探索後解除")
 main.director.elapsed+=100
 check(not ops.can_depart(w,Vector2(1080,680)),"待機時間が過ぎても同じ敵へ自動再出撃しない")
 w.hp=100;clear_enemies();ops.set_stance("normal")
 check(not w.ai.danger_hold,"プレイヤーの通常・再開で危険待機解除")
 var ground_threat=enemy_at("sand_stalker",730)
 w.ai.retreating=false;w.ai.danger_hold=false;w.floor_i=1;w.position=Vector2(700,GameData.LO_Y)
 var deck_route_ok:bool=ground_threat.threatens(w) and ops.can_depart(w,Vector2(1080,GameData.GROUND_Y_MIN+64.0))
 w.floor_i=0;w.position=Vector2(700,680)
 check(deck_route_ok and not ops.can_depart(w,Vector2(1080,GameData.GROUND_Y_MIN+64.0)),"地上敵は甲板の回収役を止めず、地上へ降りた担当者だけを止める")
 clear_enemies()
 var breaker=enemy_at("hull_breaker",980);hull=main.base.parts[GameData.Part.HULL]
 breaker._tick_ecology(1.1)
 check(main.base.parts[GameData.Part.HULL]<hull,"穿孔種は車体も攻撃する")
 clear_enemies();var neutral=enemy_at("dust_guard",730)
 w.floor_i=0;w.position=Vector2(700,680);w.hp=100;w.ai.retreating=false
 hull=main.base.parts[GameData.Part.HULL];neutral._tick_ecology(1.1)
 check(w.hp==100 and main.base.parts[GameData.Part.HULL]==hull and not neutral.threatens(w),"中立は近くにいるだけで攻撃しない")
 check(not w.ai._try_start(GameData.Job.COMBAT),"自衛AIは無抵抗の中立を勝手に狙わない")
 neutral.take_damage(1.0,w);neutral._tick_ecology(1.1)
 check(w.hp<100 and neutral.threatens(w) and main.base.parts[GameData.Part.HULL]==hull,"中立は攻撃されると本人へ反撃、車体は攻撃しない")
 check(snapshot_ok(),"敵の標的・反撃・警戒状態を保存復元")
 neutral=main.enemies_root.get_child(0)
 w.position=Vector2(1200,680)
 for i in 20:neutral._tick_ecology(0.5)
 check(neutral.target_index==-1 and neutral.provoked_index==-1,"縄張り外/見失いで追跡と反撃を終了")
 clear_enemies()
 var valid:=SaveGame.capture(main)
 var original:=valid.duplicate(true)
 check(SaveGame.apply(main,valid) and valid==original,"復元が入力snapshotを書き換えない")
 var invalid:=valid.duplicate(true)
 invalid.operations.last_report={"items":{},"seconds":"bad","food":0,"fuel":0,"refuel":0,"repair":0}
 check(not SaveGame.apply(main,invalid) and SaveGame.capture(main)==original,"不正な結果時刻を現在状態を変えず拒否")
 invalid=valid.duplicate(true);invalid.operations.outing=true;invalid.operations.baseline={"time":0,"food":-1,"fuel":0,"refuel":0,"repair":0}
 check(not SaveGame.validate(invalid,main),"不正な往復消費基準を拒否")
 # 旧v3省略項目は無装備・1枠・通常態勢として読む。
 var old:=SaveGame.capture(main);old.erase("processor_extra");old.erase("operations");old.world.erase("ecosystem_epoch")
 for row in old.crew:
  for k in ["process_slot","safe_after","retreating","danger_hold"]:row.ai.erase(k)
 check(SaveGame.validate(old,main) and SaveGame.apply(main,old),"旧v3の追加状態省略を互換読込")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
