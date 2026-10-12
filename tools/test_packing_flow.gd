extends "res://tools/test_world_flow.gd"
func _initialize():
 seed(501) # 地域の初回資源生成より前に固定する。
 main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); await main.ready
 seed(501); Engine.time_scale=12
 print("PACKING_FLOW 初期物資・既定出来事・仲間の正規行動で建設→撤去→保存再開→再設置。数量注入なし。")
 var prior_hunt:int=main.workers[0].priorities[GameData.Job.HUNT]
 for id in ["workbench","bed","cargo_rack","supply_cache"]:
  if not main.request_build(id): fail("建設依頼拒否 "+id); finish(); return
  if id=="bed":
   main.workers[0].set_priority(GameData.Job.HUNT,5) # Cの優先度操作と同じAPIで必要素材を確保。
   print("ACTION 1人の狩猟優先度を5へ")
   # 寝床の既存材料（皮/骨）を未訪問地域の既存生物から確保する。
   if not await go("east_sands"): finish(); return
   if not await go("central_trade"): finish(); return
  if id=="cargo_rack":
   if not await go("old_mine"): finish(); return
   if not main.quarry.select(): fail("鉱床選択拒否"); finish(); return
   if not await wait_for("鉱床到着",func():return main.quarry.state=="parked",300): finish(); return
   if not await wait_for("近場12単位を採取",func():return main.quarry.group_left("近場")==0,900): finish(); return
   main.quarry.request_departure()
   if not await wait_for("鉱床帰還",func():return main.quarry.crew_ready_to_leave(),300): finish(); return
   if main.quarry.loose.is_empty(): main.quarry.leave()
   else: main.quarry.discard_and_leave(main.quarry.loose.duplicate())
   if not await wait_for("鉱山入口へ復帰",func():return main.quarry.state=="road",300): finish(); return
  if id=="supply_cache":
   # 鉱山入口は木材がないため、未走行の都市→村の街道で補充する。
   if not await go("central_trade"): finish(); return
   if not main.world.request("south_oasis"): fail("村への行先拒否"); finish(); return
   if not await wait_for("木材採取のため街道中ほどへ",func():return main.world.phase=="travel" and main.world.progress<WorldMapDB.LENGTH*0.55,300): finish(); return
   var speed:float=main.target_speed; main.target_speed=0
   print("ACTION 街道で停車し、物資庫に必要な木材を採る")
   if not await wait_for("街道で物資庫完成",func():return main.has_facility("supply_cache"),600): finish(); return
   main.target_speed=speed
   if not await wait_for("村へ到着",func():return main.world.phase=="stopped" and main.world.region=="south_oasis",300): finish(); return
  if not await wait_for("建設 "+id,func():return main.base.facility_count(id)==1,600): finish(); return
  for repeat in 2:
   if not await wait_for("使用と運搬完了 "+id,func():return main.facility_pack_reason(id,0)=="",600): finish(); return
   var token:Dictionary=main.facility_pack_request(id,0)
   if not main.pack_facility(token): fail("撤去拒否 "+id); finish(); return
   var data:=SaveGame.capture(main)
   if not SaveGame.write(main,"user://packing-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://packing-flow.json")) or SaveGame.capture(main)!=data:
    fail("撤去状態の保存復元 "+SaveGame.last_error); finish(); return
   if not main.request_build(id): fail("再設置依頼拒否 "+id); finish(); return
   if not await wait_for("再設置 %s %d"%[id,repeat],func():return main.base.facility_count(id)==1,300): finish(); return
   if main.storage.count_of(FacilityDB.packed_item_of(id))!=0: fail("再設置後に完成品が残る"); finish(); return
  if id=="bed": main.workers[0].set_priority(GameData.Job.HUNT,prior_hunt)
 finish()
