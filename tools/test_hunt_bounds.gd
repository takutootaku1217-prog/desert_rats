extends "res://tools/test_quarry.gd"
func _initialize():
 await fresh()
 main.scroll_speed=0
 var w=main.workers[0]
 var c:=Creature.new();c.setup(main,"hare");c.position=Vector2(1100,680);main.creatures_root.add_child(c)
 w.floor_i=0;w.position=Vector2(1050,680);w.ai.prey=c;c.hunted_by=w;w.ai._set_state(CharacterAI.State.HUNT_MOVE)
 check(w.ai._prey_valid(),"通常画面内の生存個体を追跡可能")
 c._process(0.2)
 check(c._fleeing and c._flee_speed==150.0 and c.hp==16.0,"小型生物の逃走速度と体力を維持")
 c.position.x=1250
 var hp:float=c.hp
 w.ai.tick(0.2)
 check(w.ai.state==CharacterAI.State.SEARCH and w.ai.prey==null and c.hunted_by==null,"停車中に距離が縮まらない逃走相手の追跡と予約を解除")
 check(c.hp==hp and not c.dead and c._fleeing,"追跡終了で敵を殺さず・減速せず・逃走継続")
 c.position.x=1250;w.ai.prey=c;c.hunted_by=w;w.ai._set_state(CharacterAI.State.HUNT_ATTACK)
 w.ai.tick(0.2)
 check(w.ai.state==CharacterAI.State.SEARCH and c.hp==hp,"攻撃中に逃げられ追いつけなくなった場合も終了")
 c.position.x=1150;main.hunt_policy["hare"]=true
 for other in main.creatures_root.get_children():
  if other!=c:other.queue_free()
 await process_frame
 for i in 300:
  check(not w.ai._try_start(GameData.Job.HUNT),"追いつけない逃走個体を候補から除外")
 check(w.ai.prey==null and c.hunted_by==null and c._fleeing,"5秒相当の再選択でも予約・逃走を変更しない")
 c.position.x=900
 check(w.ai._try_start(GameData.Job.HUNT),"同じ生存個体が範囲内へ戻れば既存条件で再挑戦")
 c._fleeing=true;c.position.x=w.position.x+120
 main.scroll_speed=60
 check(w.ai._prey_valid(),"移動中に距離を詰められるなら狩猟を継続")
 main.scroll_speed=0;c._flee_speed=70
 check(w.ai._prey_valid(),"追いつける遅い生物は停車中も継続")
 c._flee_speed=150;c.position.x=w.position.x-120
 check(w.ai._prey_valid(),"こちらへ走る相手を待ち受けられる場合は終了しない")
 c.position.x=w.position.x;w.ai._set_state(CharacterAI.State.HUNT_ATTACK);w.ai.tick(0.1)
 check(c.hp<hp,"範囲内で追いつけた狩猟の攻撃は維持")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
