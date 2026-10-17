extends "res://tools/test_equipment_ui.gd"
## 画面操作はViewport上の自動入力。人間のOS操作・Windows実機確認ではない。
const EVIDENCE_DIR := "res://docs/evidence/2026-10-17-subquests/gui"

func find_button(text_:String, occurrence:int=0) -> Button:
 var found:=0
 for b in main.town_ui.find_children("*","Button",true,false):
  if b.text==text_ and b.is_visible_in_tree():
   if found==occurrence:return b
   found+=1
 return null
func shot(name_:String) -> void:
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 var path:=ProjectSettings.globalize_path(EVIDENCE_DIR)
 DirAccess.make_dir_recursive_absolute(path)
 root.get_texture().get_image().save_png(path.path_join(name_+".png"))
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
 await click(find_button("交易所 / ミッション"));await frames();await shot("04-missions")
 await click(find_button("木材で受注"));await frames()
 check(ui._confirm.get_global_rect().end.y<=720 and ui._confirm.disabled==false,"調達の確認ボタンが画面内で有効")
 await click(ui._confirm);await frames();await shot("05-supply-accepted")
 check(main.town.supply=="accepted" and find_button("納品・受領")!=null,"調達の受注状態・納品導線を表示")
 await click(find_button("取消"));await click(ui._confirm);await frames()
 check(main.town.supply=="idle","取消の確認操作で調達だけを解除")
 # 一番目の「受注」は配達、二番目は遺失物回収。名称を共通にしても行の順で誤操作しない。
 await click(find_button("受注",0));await click(ui._confirm);await frames();await shot("06-delivery-accepted")
 check(main.town.delivery=="outbound" and main.town.delivery_cargo,"配達の積載中状態を表示")
 await click(find_button("取消",1));await click(ui._confirm);await frames()
 await click(find_button("受注",1));await click(ui._confirm);await frames();await shot("07-recovery-accepted")
 check(main.town.recovery=="outbound" and ui._confirm.get_global_rect().end.y<=720,"回収受注と全操作欄の画面内配置")
 var data:=SaveGame.capture(main);check(SaveGame.apply(main,data),"街で受注中の回収依頼を保存復元")
 ui.show_facility("missions");await frames()
 check(find_button("報酬受領",1)!=null and find_button("取消",2)!=null,"ロード後も進捗・受領・取消を区別して表示")
 ui.close();await frames();check(not paused,"街を閉じて元の進行状態へ")
 paused=true;ui.open();ui.close();check(paused,"既存の一時停止は街開閉後も維持")
 paused=false;ui.open();main.save_ui.open();await frames()
 check(main.save_ui.is_open() and paused and not ui.is_open(),"街から保存画面へ安全に遷移")
 main.save_ui.close();check(not paused,"保存画面を閉じると街の停止状態を残さない")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
