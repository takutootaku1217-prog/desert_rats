extends "res://tools/test_world_flow.gd"
func backdrop() -> WorldScroll:
 for n in main.get_children():
  if n is WorldScroll:return n
 return null
func check(ok:bool,label:String):
 if not ok:fail(label)
 else:print("OK ",label)
func picture(label:String):
 for arg in OS.get_cmdline_user_args():
  if not arg.begins_with("--screenshots="):continue
  paused=true
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(arg.trim_prefix("--screenshots=").path_join(label+".png"))
  print("SCREENSHOT ",label," region=",main.world.region," phase=",main.world.phase," progress=",main.world.progress," seconds=",main.director.elapsed)
  paused=false
func verify_stop(id:String):
 check(backdrop().scenery_weights()=={id:1.0},id+" 停車時は現在地域の背景")
 var d:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://scenery.json",true) and SaveGame.apply(main,SaveGame.read("user://scenery.json")) and SaveGame.capture(main)==d,"停車保存で全状態を保持 "+id)
 check(backdrop().scenery_weights()=={id:1.0},"ロード後の背景 "+id)
 await picture(id)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",501);root.add_child(main);await main.ready
 Engine.time_scale=12
 for i in 4:await process_frame
 await verify_stop("south_oasis")
 check(main.world.request("east_sands"),"地図の正規行先を選択")
 check(backdrop().scenery_weights()=={"south_oasis":1.0},"出発準備中は出発地の背景")
 if not await wait_for("村から走り出す",func():return main.world.phase=="travel" and main.world.progress>WorldMapDB.LENGTH*0.05,120):finish();return
 var weights:=backdrop().scenery_weights()
 check(weights.south_oasis>0 and weights.south_oasis<1 and weights.east_sands==0,"出発地が徐々に遠ざかる")
 var d:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://scenery-road.json",true) and SaveGame.apply(main,SaveGame.read("user://scenery-road.json")) and backdrop().scenery_weights()==weights,"移動中ロードでも背景進捗一致")
 if not await wait_for("街道中ほど",func():return main.world.phase=="travel" and main.world.progress>WorldMapDB.LENGTH*0.45,120):finish();return
 check(backdrop().scenery_weights().values().all(func(v):return v==0),"街道中ほどは街並みのない既存砂漠")
 await picture("travelling")
 if not await wait_for("砂原に停車",func():return main.world.phase=="stopped" and main.world.region=="east_sands",120):finish();return
 await verify_stop("east_sands")
 if not await go("central_trade"):finish();return
 await verify_stop("central_trade")
 if not await go("old_mine"):finish();return
 await verify_stop("old_mine")
 if not main.world.request("central_trade"):fail("帰路要求");finish();return
 if not await wait_for("鉱山から帰路",func():return main.world.phase=="travel" and main.world.progress<WorldMapDB.LENGTH*0.95,120):finish();return
 weights=backdrop().scenery_weights()
 check(weights.old_mine>0 and weights.central_trade==0,"逆向き移動でも鉱山から遠ざかる")
 if not await wait_for("都市に再停車",func():return main.world.phase=="stopped",180):finish();return
 await verify_stop("central_trade")
 main.map_ui.open();paused=true
 for id in ["south_oasis","east_sands","central_trade","old_mine"]:
  # 地点はアイコンボタン＋常時表示ラベル。名前が実際に見えることを検査する。
  var labels:Array=[]
  if main.map_ui._nodes.has(id):labels=main.map_ui._nodes[id].find_children("*","Label",true,false)
  check(labels.any(func(label):return label.text==WorldMapDB.name_of(id) and label.is_visible_in_tree() and label.get_global_rect().position.x>=0 and label.get_global_rect().end.x<=1280 and label.get_global_rect().end.y<=720),"地図上の名前を保持 "+id)
 await picture("map")
 main.map_ui.close();paused=false
 finish()
