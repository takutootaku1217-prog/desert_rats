extends "res://tools/test_equipment_ui.gd"
func shot(name_:String) -> void:
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute("/tmp/routes-gui")
 root.get_texture().get_image().save_png("/tmp/routes-gui/"+name_+".png")
func _initialize():
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.set_process(false)
 for w in main.workers:
  w.set_process(false);w.stop_work();w.position=Vector2(700,GameData.LO_Y);w.floor_i=1;w._climb_dest=null
 var ui=main.map_ui
 await key(KEY_M)
 check(ui.is_open() and paused,"M入力で地図を開き時間停止")
 await click(ui._nodes.old_mine)
 check(ui._path==["central_trade","old_mine"],"遠い鉱山を実クリックで選択")
 await shot("01-route-preview")
 await click(ui._route_options)
 check(ui._path==["east_sands","central_trade","old_mine"],"実入力で砂原経由の迂回経路")
 await click(ui._stop_box.get_child(0))
 check("east_sands" in ui._reserved,"実入力で途中の砂原に予約停車")
 await click(ui._check_each);check(main.journey.confirm_each,"各点確認を実入力で有効")
 await click(ui._check_each)
 await shot("02-reserved-route")
 check(ui._confirm.get_global_rect().end.y<720 and ui._confirm.get_global_rect().end.x<=1280,"長い経路でも出発ボタンは画面内")
 await click(ui._confirm)
 check(not paused and not ui.is_open() and main.journey.remaining.size()==3,"出発で閉じて通常画面に戻る")
 main.world.tick(0);main.world.progress=1200
 await key(KEY_M)
 var ends:Array=WorldMapDB.ROADS[main.world.road]
 var expected:Vector2=(WorldMapDB.REGIONS[ends[0]].pos+Vector2(45,24)).lerp(WorldMapDB.REGIONS[ends[1]].pos+Vector2(45,24),0.5)
 check(ui._marker.position.is_equal_approx(expected),"車体マーカーは実走行の中間位置")
 await shot("03-moving-marker");await key(KEY_M)
 main.journey.set_stop("east_sands",false);main.world.progress=1800;main.scroll_speed=60;main.journey.tick(0);await frames()
 check(main.route_notice.panel.visible and not paused,"10秒前案内は世界を止めない")
 var progress:float=main.world.progress
 main.set_process(true);await frames();main.set_process(false)
 check(main.world.progress>progress and main.route_notice.panel.visible,"案内表示中も通常Main処理で走行が進む")
 await shot("04-arrival-notice")
 var count:int=main.journey.notice_count
 var b:Button=main.route_notice.panel.get_child(0).get_child(1).get_child(0)
 await click(b)
 check("east_sands" in main.journey.stops and main.journey.notice=="","立ち寄る実入力で予約追加")
 main.journey.tick(0);check(main.journey.notice_count==count,"案内を押した後に再通知しない")
 main.world.tick(600);await frames()
 check(main.world.phase=="stopped" and main.world.region=="east_sands","通知で選んだ地点に実際に停車")
 await key(KEY_M);await shot("05-stop-and-resume")
 await click(ui._resume);check(not paused and main.world.phase=="departing","予約経路を実クリックで再開")
 paused=true;ui.open();ui.close();check(paused,"地図開閉は既存一時停止を保持")
 paused=false
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
