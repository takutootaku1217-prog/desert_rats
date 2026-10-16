extends "res://tools/test_progression.gd"
var _next_save:=20.0
func diagnostic_seed() -> int:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--diagnostic-seed="): return int(arg.get_slice("=",1))
 return 501
func wait_for(label: String, condition: Callable, seconds: float) -> bool:
 phase=label
 var end:float=main.director.elapsed+seconds
 while not condition.call() and not main.game_over and main.director.elapsed<end:
  await process_frame
  if main.director.elapsed>=_next_save:
   _next_save=main.director.elapsed+25.0
   var d:=SaveGame.capture(main)
   if not SaveGame.write(main,"user://world-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://world-flow.json")):
    fail("道中保存復元: "+SaveGame.last_error); return false
   if SaveGame.capture(main)!=d:
    fail("道中保存で持続状態が不一致"); return false
  if phase=="近場12単位を採取" and main.storage.free_for(GameData.Item.IRON_ORE)==0:
   for item in [GameData.Item.WOOD,GameData.Item.STONE]:
    var n:int=mini(5,main.warehouse_discard_available(item))
    if n>0:
     var snapshot:Dictionary=main.warehouse_discard_snapshot(item,n)
     if main.discard_warehouse(snapshot): print("ACTION 満載時に選択廃棄 ",ItemDB.name_of(item)," x",n)
     break
 if not condition.call(): fail("未達: "+label+" / "+main.world.status_text()); return false
 print("STAGE %.1fs %s"%[main.director.elapsed,label]); stages.append(label); return true
func go(to: String) -> bool:
 if not main.world.request(to): fail("行先選択拒否 "+to); return false
 return await wait_for("地域到着 "+to,func():return main.world.phase=="stopped" and main.world.region==to,600)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); await main.ready
 seed(501); Engine.time_scale=12
 print("MAP_FLOW 通常初期物資・既定出来事。作業台、地図4地域往復、鉱床12、保存再開。満載時のみ既存の選択廃棄を利用。")
 if not main.world.active: fail("地図既定が無効"); finish(); return
 main.request_build("workbench")
 # 新仕様: プレイヤーが必要な道具・精錬回数を有限注文する。
 for id in ["tool_wood_pick","tool_hammer","tool_wood_axe","tool_axe"]: main.request_order(id,1)
 main.request_order("smelt",12)
 if not await wait_for("村で作業台完成",func():return main.has_facility("workbench"),600): finish(); return
 if not await go("east_sands"): finish(); return
 if not await go("central_trade"): finish(); return
 if not await go("old_mine"): finish(); return
 if not main.quarry.select(): fail("鉱床選択拒否"); finish(); return
 if not await wait_for("鉱床へ到着",func():return main.quarry.state=="parked",240): finish(); return
 if not await wait_for("近場12単位を採取",func():return main.quarry.group_left("近場")==0,900): finish(); return
 main.quarry.request_departure()
 if not await wait_for("全員帰還",func():return main.quarry.crew_ready_to_leave(),300): finish(); return
 if not main.quarry.loose.is_empty(): main.quarry.discard_and_leave(main.quarry.loose.duplicate())
 else: main.quarry.leave()
 if not await wait_for("鉱山入口へ復帰",func():return main.quarry.state=="road",240): finish(); return
 if not await go("central_trade"): finish(); return
 if not await go("south_oasis"): finish(); return
 if main.quarry.remaining["near"]!=0: fail("再訪用の鉱床残量が復活")
 print("MAP_FINAL ",main.world.region," roads=",main.world.locations.keys()," distance=",main.director.distance)
 finish()
