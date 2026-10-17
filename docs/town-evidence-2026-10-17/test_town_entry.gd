extends "res://tools/test_equipment_ui.gd"
func _initialize():
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.world.sync();main.world._archive();main.world.region="central_trade";main.world.phase="stopped";main.world._ensure_location()
 main.director.enabled=false
 for w in main.workers:w.stop_work();w.floor_i=1;w.position=Vector2(700,GameData.LO_Y);w._climb_dest=null
 var worker=main.workers[0]
 worker.floor_i=0;worker.position=GameData.RAMP_FOOT;worker.ai._set_state(CharacterAI.State.SEARCH)
 main.town_ui.request_open()
 check(main.town_ui._waiting and not main.town_ui.is_open() and not paused,"屋外仲間がいる間は街を開かず帰還待ち")
 Engine.time_scale=10
 var start:float=main.director.elapsed
 while not main.town_ui.is_open() and main.director.elapsed-start<120:await process_frame
 check(main.town_ui.is_open() and paused and main.world.ready_reason()=="","荷物と仲間の帰還後に初めて入場・停止")
 check(main.operations.stance=="recall","街では帰還状態維持")
 main.town_ui.close()
 check(not paused and main.operations.stance=="normal","閉じると元の屋外方針と時間へ戻す")
 Engine.time_scale=1
 print("ENTRY_WAIT seconds=",main.director.elapsed-start)
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
