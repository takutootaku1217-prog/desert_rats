extends "res://tools/test_world_fauna.gd"
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await main.ready
 main.process_mode=Node.PROCESS_MODE_DISABLED
 main.target_speed=0;main.scroll_speed=0
 for w in main.workers:w.stop_work()
 main.world._spawn_visible()
 var c=main.creatures_root.get_child(0)
 var id:String=c.world_id
 c.hp=9.0;c.position.x=main.camera_left()+1400;c._fleeing=true
 c._process(0.2);await process_frame
 var row:Dictionary=main.world.locations[main.world.key()][id]
 var due:float=row.return_at
 check(row.spent==false and row.data.hp==9 and main.creatures_root.get_child_count()==0,"生存退避は同一ID・傷を保存")
 for i in 5:
  main.world._archive();main.world._spawn_visible()
 check(main.creatures_root.get_child_count()==0 and row.return_at==due,"再訪連打で待機短縮や再抽選なし")
 SaveGame.disabled=false
 var before:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://return.json",true) and SaveGame.apply(main,SaveGame.read("user://return.json")) and SaveGame.capture(main)==before,"退避期限とHPをディスク保存復元")
 main.director.elapsed=due-0.1;main.world._spawn_visible()
 check(main.creatures_root.get_child_count()==0,"120秒未満は非表示")
 main.director.elapsed=due;main.world._spawn_visible()
 c=main.creatures_root.get_child(0)
 check(c.world_id==id and c.hp==9 and not c._fleeing,"120秒後に同一個体が逃走を解除して再遭遇")
 var hunter=main.workers[0];hunter.position=c.position+Vector2(-20,0);c.hunted_by=hunter
 var prior:float=c.position.x;c._process(0.1)
 check(c._fleeing and c.position.x>prior,"再遭遇後も既存小型は接近した狩人から逃げる")
 c.take_damage(999);await process_frame
 main.world._archive();main.director.elapsed+=600;main.world._spawn_visible()
 check(main.world.locations[main.world.key()][id].spent and main.creatures_root.get_child_count()==0,"討伐済みは時間経過・再訪でも復活しない")
 # メタデータがない旧保存の画面外個体。別地域滞在中の時間も有効。
 location("central_trade");main.world._spawn_visible()
 c=main.creatures_root.get_child(0);id=c.world_id;c.hp=21;c.position.x=main.camera_left()+1600;main.world.sync();main.world._archive()
 row=main.world.locations[main.world.key()][id];row.erase("home_anchor");row.erase("return_at")
 before=SaveGame.capture(main)
 check(SaveGame.write(main,"user://old-return.json",true) and SaveGame.apply(main,SaveGame.read("user://old-return.json")),"画面外生存個体の旧保存を読込")
 main.world._spawn_visible();row=main.world.locations[main.world.key()][id];due=row.return_at
 location("south_oasis");main.director.elapsed=due+1;location("central_trade");main.world._spawn_visible()
 c=main.creatures_root.get_child(0)
 check(c.world_id==id and c.hp==21 and not c.dead,"別地域で待機後の通常再訪でも旧個体ID・HPを保持")
 # 追加草食獣：中立、当人だけ反撃、追跡終了、当たり範囲、旧地域への追加なし。
 var ids:int=main.world.next_id
 main.world._archive();main.world._ensure_location();main.world._spawn_visible()
 check(main.world.next_id==ids,"生成済み地域への草食獣の追加・補充なし")
 for kind in ["paraceratherium","dune_horn"]:
  for e in main.enemies_root.get_children():main.enemies_root.remove_child(e);e.free()
  var e:=Enemy.new();e.setup_kind(main,kind);e.ecological=true;e.position=Vector2(650,680);e.home_x=650;main.enemies_root.add_child(e)
  var w=main.workers[0];var other=main.workers[1]
  w.floor_i=0;w.position=Vector2(620,680);w.hp=100;other.floor_i=0;other.position=Vector2(640,680);other.hp=100
  var hull:float=main.base.parts[GameData.Part.HULL]
  for i in 20:e._tick_ecology(0.2)
  check(w.hp==100 and other.hp==100 and e.target_index==-1 and not e.threatens(w),kind+" 未挑発は中立・自動標的にならない")
  check(e.hit_test(e.position+e.body_rect().get_center()) and not e.hit_test(e.position+Vector2(300,0)),kind+" 大小の描画範囲でクリック判定")
  e.take_damage(1,w)
  before=SaveGame.capture(main)
  check(SaveGame.apply(main,before) and SaveGame.capture(main)==before,kind+" 反撃中の対象とHPを保存復元")
  e=main.enemies_root.get_child(0)
  for i in 10:e._tick_ecology(0.2)
  check(w.hp<100 and other.hp==100 and e.provoked_index==0 and e.threatens(w),kind+" 攻撃者だけ反撃・他の仲間に転嫁なし")
  w.floor_i=1
  for i in 60:e._tick_ecology(0.2)
  check(e.target_index==-1 and e.provoked_index==-1 and e.search_left==0 and main.base.parts[GameData.Part.HULL]==hull,kind+" 車内へ追わず追跡終了・車体無傷")
  main.world.sync();id=e.world_id;var hp:float=e.hp
  before=SaveGame.capture(main)
  check(SaveGame.write(main,"user://grazer.json",true) and SaveGame.apply(main,SaveGame.read("user://grazer.json")) and SaveGame.capture(main)==before,kind+" 個体ID・HP・反撃状態を保存復元")
  e=main.enemies_root.get_child(0)
  check(e.world_id==id and e.hp==hp,kind+" 同一個体")
  e.take_damage(999);await process_frame;main.director.elapsed+=240;main.world._update_ecosystem();main.world._spawn_visible()
  check(not main.enemies_root.get_children().any(func(n):return n.world_id==id),kind+" 死亡後補充なし")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
