extends "res://tools/test_field_operations.gd"
func ready_worker(w):
 for other in main.workers:
  other.stop_work();other.ai._set_state(CharacterAI.State.SEARCH);other.floor_i=1;other.position=Vector2(700,GameData.LO_Y);other._climb_dest=null
 w.floor_i=0;w.position=Vector2(700,680);w.hp=100;w.hunger=100;w.fatigue=0;w.stress=0
 w.ai.retreating=false;w.ai.danger_hold=false;w.ai.safe_after=0
func advance(w,e,seconds:float):
 for i in int(seconds/0.1):
  main.director.elapsed+=0.1
  w._process(0.1)
  if is_instance_valid(e) and not e.dead:e._tick_ecology(0.1)
func home(w):
 for i in 1200:
  w.ai.tick(0.1)
  if main.operations.returned(w):return true
 return false
func _initialize():
 await fresh()
 SaveGame.disabled=false
 for index in 3:
  var w=main.workers[index]
  for stance in ["normal","alert"]:
   for kind in ["sand_stalker","hull_breaker","dust_guard","paraceratherium","dune_horn"]:
    clear_enemies();ready_worker(w);main.operations.set_stance(stance)
    var e=enemy_at(kind,730)
    var before:float=e.hp
    check(w.ai.order_attack(e),"仲間%d %s %s 明示攻撃受理"%[index,stance,kind])
    advance(w,e,1.2)
    check(e.hp<before and w.ai.manual_attack and not w.ai.retreating,"仲間%d %s %s 初撃後も継続"%[index,stance,kind])
    if e.behavior()=="neutral":check(e.provoked_index==index and w.hp<100,"中立の反撃は指示した本人へ")
 clear_enemies();var w=main.workers[0];ready_worker(w);main.operations.set_stance("normal")
 var e=enemy_at("paraceratherium",730);var other=enemy_at("sand_stalker",740)
 for i in 5:check(w.ai.order_attack(e),"同じ命令の連打を受理")
 advance(w,e,1.0)
 check(w.ai.enemy==e and w.ai.manual_attack and not w.ai.retreating,"別の危険敵がいても明示対象を維持")
 check(w.ai.order_attack(other) and w.ai.enemy==other,"明示対象を変更")
 var d:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://combat.json",true) and SaveGame.apply(main,SaveGame.read("user://combat.json")) and SaveGame.capture(main)==d,"攻撃中の命令・対象を保存復元")
 other=main.enemies_root.get_child(1);var old_hp:float=other.hp
 advance(w,other,1.0)
 check(other.hp<old_hp and w.ai.manual_attack,"読込後も明示攻撃が継続")
 main.operations.set_stance("alert")
 check(not w.ai.order_attack(other),"後退命令直後は攻撃連打で帰還を取消さない")
 check(home(w) and not w.ai.manual_attack and w.ai.danger_hold,"後退命令で帰還して危険待機")
 for i in 100:other._tick_ecology(0.1)
 check(other.target_index==-1 and other.provoked_index==-1,"屋内帰還後は敵の追跡を打切る")
 main.operations.set_stance("normal");w.ai.tick(0.1)
 check(not w.ai.danger_hold and not w.ai.retreating,"帰還後の通常再開で待機解除")
 for reason in ["recall","injury","hunger"]:
  clear_enemies();ready_worker(w);main.operations.set_stance("normal");e=enemy_at("paraceratherium",730)
  w.ai.order_attack(e);advance(w,e,0.5)
  if reason=="recall":main.operations.set_stance("recall")
  elif reason=="injury":w.hp=FieldOperations.RECOVER_HP-1
  else:w.hunger=0
  w.ai.tick(0.1)
  check(not w.ai.manual_attack and home(w),reason+" で攻撃中断・拠点帰還")
  if reason=="injury":check(not w.ai.order_attack(e),"HP75未満では再攻撃を拒否")
 # 屋外方針・旧保存の互換。未挑発中立は自動仕事の候補にしない。
 clear_enemies();ready_worker(w);main.operations.set_stance("normal");e=enemy_at("dune_horn",730)
 check(not w.ai._try_start(GameData.Job.COMBAT) and e.provoked_index==-1,"未挑発中立へ自発攻撃しない")
 main.operations.set_stance("recall")
 check(not w.ai.order_attack(e),"呼戻し態勢は明示攻撃を拒否")
 d=SaveGame.capture(main)
 for row in d.crew:row.ai.erase("manual_attack")
 check(SaveGame.apply(main,d) and main.workers.all(func(x):return not x.ai.manual_attack),"旧保存の省略命令は自動戦闘として互換復元")
 # Viewportから製品の右クリック入口へ。OS入力ではない。
 for kind in ["sand_stalker","paraceratherium","dune_horn"]:
  clear_enemies();ready_worker(w);main.operations.set_stance("normal");e=enemy_at(kind,730)
  main.follow_target=w
  main.process_mode=Node.PROCESS_MODE_ALWAYS;main.set_process(false)
  for child in main.get_children():child.process_mode=Node.PROCESS_MODE_DISABLED
  var point:Vector2=e.position+e.body_rect().get_center()
  for down in [true,false]:
   var ev:=InputEventMouseButton.new();ev.button_index=MOUSE_BUTTON_RIGHT;ev.pressed=down
   ev.position=main.get_canvas_transform()*point;ev.global_position=ev.position
   root.push_input(ev,true);await process_frame
  check(w.ai.manual_attack and w.ai.enemy==e,kind+" Viewport右クリックで描画範囲を指定")
  old_hp=e.hp;advance(w,e,1.2)
  check(e.hp<old_hp and w.ai.manual_attack,kind+" 右クリック受理後に実ダメージ・継続")
  main.process_mode=Node.PROCESS_MODE_DISABLED
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
