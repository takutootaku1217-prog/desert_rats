extends "res://tools/test_manual_combat.gd"
func _initialize():
 await fresh();clear_enemies()
 var w=main.workers[0];ready_worker(w);main.operations.set_stance("normal")
 var e=enemy_at("paraceratherium",730)
 w.hp=76
 w.ai.order_attack(e)
 for i in 300:
  advance(w,e,0.1)
  if w.ai.retreating:break
 print("NATURAL_RETALIATE hp=",w.hp," enemy_hp=",e.hp," retreat=",w.ai.retreating," manual=",w.ai.manual_attack)
 check(w.hp<FieldOperations.RECOVER_HP and not w.ai.manual_attack and w.ai.retreating,"反撃の実ダメージで既存負傷基準に達し帰還")
 var d:=SaveGame.capture(main)
 check(SaveGame.apply(main,d) and SaveGame.capture(main)==d,"負傷帰還途中の保存復元")
 e=main.enemies_root.get_child(0)
 check(home(w),"負傷した仲間が拠点に戻る")
 for i in 100:e._tick_ecology(0.1)
 check(e.target_index==-1 and e.provoked_index==-1,"中立大型は帰還後に追跡解除")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
