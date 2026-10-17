extends "res://tools/test_equipment_ui.gd"
func find_button(text_:String) -> Button:
 for b in main.town_ui.find_children("*","Button",true,false):
  if b.text==text_ and b.is_visible_in_tree():return b
 return null
func shot(name_:String) -> void:
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 var path:="/tmp/town-gui"
 DirAccess.make_dir_recursive_absolute(path)
 root.get_texture().get_image().save_png(path+"/"+name_+".png")
func _initialize():
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.set_process(false)
 for w in main.workers:
  w.set_process(false);w.stop_work();w.position=Vector2(700,GameData.LO_Y);w.floor_i=1;w._climb_dest=null
 main.town_ui.open();check(not main.town_ui.is_open(),"村から街を開けない")
 main.world._archive()
 main.world.region="central_trade";main.world.phase="stopped";main.world.active=true;main.quarry.state="road"
 main.world._ensure_location()
 main.town.credits=32;main.base.fuel=50;main.base.parts[0]=65
 var ui=main.town_ui
 ui.open();await frames()
 check(ui.is_open() and paused and not main.navigation.bar.visible,"都市で街を開く・時間停止・背後入口を隠す")
 await shot("01-town")
 await click(find_button("市場 / 売買"));await frames()
 check(ui._selection=="market","背景の市場をクリック")
 await click(find_button("買う：食料 4 Cr"));await frames();await shot("02-market")
 var n:int=main.storage.count_of(GameData.Item.FOOD)
 await click(ui._confirm)
 check(main.storage.count_of(GameData.Item.FOOD)==n+1 and main.town.credits==28,"表示を確認し実入力で購入")
 await click(ui._confirm);check(main.town.credits==28,"実行連打で二重購入しない")
 await click(find_button("街へ戻る"));await click(find_button("整備ヤード / 給油・修理"))
 await click(find_button("クレジットで給油"));await shot("03-service")
 await click(ui._confirm);check(main.base.fuel==75 and main.town.credits==20,"有料給油を入力で実行")
 await key(KEY_ESCAPE);check(ui.is_open() and not ui._panel.visible and paused,"施設を閉じると街・時間停止を継続")
 await click(find_button("交易所 / ミッション"));await click(find_button("引き受ける"));await shot("04-missions")
 check(ui._confirm.get_global_rect().end.y<=720,"ミッションの実行ボタンが画面内")
 await click(ui._confirm);await frames()
 check(ui._confirm.get_global_rect().end.y<=720,"受注後もミッションパネルが画面内")
 await shot("04b-mission-active")
 await click(find_button("街パネルを閉じて勤務を開始 / 再開"));await frames();await shot("05-shift")
 var left:float=main.town.help_left
 await frames();check(main.town.help_left<left and paused,"勤務表示だけ進行・世界は停止")
 await click(find_button("勤務を一時中断して街へ"));left=main.town.help_left
 await frames();check(main.town.help_left==left,"中断中は勤務時間を増やさない")
 ui.close();await frames();check(not paused,"街を閉じて元の進行状態へ")
 paused=true;ui.open();ui.close();check(paused,"既存の一時停止は街開閉後も維持")
 paused=false;ui.open();main.save_ui.open();await frames()
 check(main.save_ui.is_open() and paused and not ui.is_open(),"街から保存画面へ安全に遷移")
 var data:=SaveGame.capture(main);check(SaveGame.apply(main,data),"街で中断した勤務進捗の保存復元")
 main.save_ui.close();check(not paused and not ui._running,"ロード後に勤務は勝手に進行しない")
 ui.open();ui.show_facility("missions");await frames()
 check(find_button("街パネルを閉じて勤務を開始 / 再開")!=null,"ロード後に明示再開可能")
 ui.close()
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
