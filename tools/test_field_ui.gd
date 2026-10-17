extends "res://tools/test_clarity_ui.gd"
## UI用fixture。通常進行の資材取得はtest_first_cycle_flowで別検証。
func shot(label:String):
 await frames()
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--screenshots="):
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(arg.trim_prefix("--screenshots=").path_join(label+".png"))
func named(node:Node,text:String):
 if node is Button and node.text==text:return node
 for c in node.get_children():
  var result=named(c,text)
  if result!=null:return result
 return null
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.set_process(false)
 for w in main.workers:w.stop_work();w.set_process(false)
 main.navigation.activate("探索");await frames()
 await click(named(main.navigation.groups["探索"],"後退（警戒）"))
 check(main.operations.stance=="alert","画面ボタンで近場優先の警戒へ")
 await click(named(main.navigation.groups["探索"],"撤退・呼戻し"))
 check(main.operations.stance=="recall","画面ボタンで呼戻しへ")
 main.operations.last_report={"items":{GameData.Item.WOOD:8,GameData.Item.IRON_ORE:3},"seconds":96.0,"food":1,"fuel":3.0,"refuel":0,"repair":0}
 await shot("field-controls")
 await click(named(main.navigation.groups["探索"],"通常・再開"))
 check(main.operations.stance=="normal","画面ボタンで通常再開")
 main.world.active=true;main.world.region=TownDB.RECOVERY_TO;main.world.phase="stopped";main.quarry.state="road";main.town.recovery="site";main.town.recovery_worker=-1;main.town.observe();await frames()
 check(main.navigation.mission_status.text.contains("回収待ち") and main.navigation.recovery_cancel.visible and not main.navigation.recovery_cancel.disabled,"現地の探索パネルで回収待ちと断念して帰還を確認できる")
 main.town.recovery="idle";main.town.delivery="outbound";main.world.region=TownDB.DELIVERY_TO;main.world.phase="arriving";main.world.road="03";main.world.origin="central_trade";main.world.destination=TownDB.DELIVERY_TO;main.world.progress=WorldMapDB.LENGTH;await frames()
 check(main.navigation.mission_status.text.contains("停車して引渡し"),"交易村の到着中は現地パネルで停車引渡し必要を表示")
 await shot("mission-status")
 main.town.delivery="idle";main.world.region="south_oasis";main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination=""
 main.navigation.close()
 for id in ["workbench","cargo_rack","storage_upgrade","parallel_bench"]:main.finish_build(id)
 main.build_ui.open();await shot("cycle-upgrades")
 main.build_ui.close()
 main.storage.store_owned(GameData.Item.HANDCART)
 main.detail.open_worker(main.workers[0])
 await frames()
 # 手押し車は用途別の「装備・荷物」に置く。実クリックでカテゴリを開いてから操作する。
 await click(main.detail._tab_btns[1])
 await frames()
 main.detail._scroll.ensure_control_visible(main.detail._live.handcart)
 await frames()
 await click(main.detail._live.handcart)
 check(main.workers[0].work_support==GameData.Item.HANDCART,"画面ボタンで一人用手押し車を装備")
 await shot("handcart-equipment")
 main.detail.close()
 for i in 3:
  var e:=Enemy.new();e.setup_kind(main,["sand_stalker","hull_breaker","dust_guard"][i]);e.ecological=true;e.home_x=350.0+i*150.0;e.position=Vector2(e.home_x,660);main.enemies_root.add_child(e);e.set_process(false)
 await shot("three-creatures")
 var neutral=main.enemies_root.get_child(2)
 var worker=main.workers[0]
 worker.floor_i=0;worker.position=neutral.position+Vector2(-40,0);worker.hp=100
 worker.carrying=-1;worker.ai.retreating=false;worker.ai.danger_hold=false
 main.follow_target=worker
 await frames()
 var body:Vector2=neutral.position+Vector2(0,-52.0*neutral.body_scale)
 await mouse(root.get_canvas_transform()*body,MOUSE_BUTTON_RIGHT)
 check(worker.ai.enemy==neutral and worker.ai.state==CharacterAI.State.COMBAT_MOVE,"近くの中立の描画位置を右クリックして明示攻撃要求")
 main.operations.set_stance("recall")
 worker.ai._release_task();worker.ai._set_state(CharacterAI.State.SEARCH)
 await mouse(root.get_canvas_transform()*body,MOUSE_BUTTON_RIGHT)
 check(worker.ai.enemy==null,"呼戻し中は右クリック攻撃要求も拒否")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
