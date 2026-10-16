extends "res://tools/test_world_flow.gd"
func _process(_delta: float) -> bool:
 if main!=null and main.is_node_ready():
  for event in main.director.focus_list():
   if EventDB.def(event["id"])["kind"]=="attack" and event["stance"]!="flee":
    print("ACTION 襲撃への対処を振り切るへ ",event["id"])
    main.director.set_stance(event["id"],"flee")
 return false
func _initialize():
 seed(diagnostic_seed()) # 地域の初回資源生成より前に固定する。
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed()); root.add_child(main); await main.ready
 seed(diagnostic_seed()); Engine.time_scale=12
 print("DIAGNOSTIC_SEED ",diagnostic_seed())
 print("PACKING_FLOW 初期物資・既定出来事・仲間の正規行動で建設→撤去→保存再開→再設置。数量注入なし。")
 for id in ["tool_wood_pick","tool_hammer","tool_wood_axe","tool_axe"]:main.request_order(id,1)
 main.request_order("smelt",12)
 var prior_gather:Dictionary=main.gather_policy.duplicate()
 var prior_hunt:int=main.workers[0].priorities[GameData.Job.HUNT]
 for id in ["workbench","bed","cargo_rack","supply_cache"]:
  if not main.request_build(id): fail("建設依頼拒否 "+id); finish(); return
  if id=="bed":
   for item in main.gather_policy:main.gather_policy[item]=0 # 獲物の持帰り枠を空け、原料の作り置きを止める
   main.refill_settings[GameData.Item.REPAIR_KIT].enabled=false # 寝床用の皮・骨を補充で使わないプレイヤー設定
   main.workers[0].set_priority(GameData.Job.HUNT,5) # Cの優先度操作と同じAPIで必要素材を確保。
   print("ACTION 1人の狩猟優先度を5へ")
   # 寝床の既存材料（皮/骨）を未訪問地域の既存生物から確保する。
   if not await go("east_sands"): finish(); return
   if not await go("central_trade"): finish(); return
   if not await wait_for("都市のコブ獣から皮を回収",func():return main.has_facility("bed") or main.storage.count_of(GameData.Item.HIDE)>=1,300):finish();return
   if not main.world.request("south_oasis"):fail("未走行街道への出発拒否");finish();return
   main.target_speed=60
   if not await wait_for("街道のコブ獣も狩り寝床完成",func():return main.has_facility("bed"),600):finish();return
   if not await wait_for("村到着",func():return main.world.phase=="stopped",300):finish();return
  if id=="cargo_rack":
   if not await go("central_trade"):finish();return
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
   # 鉱山入口は木材がないため、都市→村の街道に残った有限木材を回収する。
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
   while main.storage.current_weight()+main.storage.processing_reserve()+main.storage.item_weight(FacilityDB.packed_item_of(id)) > main.storage.max_weight()-int(FacilityDB.def(id).get("capacity_bonus",0)):
    var discarded:=false
    for item in [GameData.Item.WOOD,GameData.Item.STONE,GameData.Item.IRON_ORE]:
     if main.warehouse_discard_available(item)>8:
      var shown:Dictionary=main.warehouse_discard_snapshot(item,5)
      discarded=main.discard_warehouse(shown)
      if discarded:print("ACTION 撤去後容量のため確認付き廃棄 ",ItemDB.name_of(item)," x5")
      break
    if not discarded:fail("撤去容量を確保できない");finish();return
   if not await wait_for("使用と運搬完了 "+id,func():return main.facility_pack_reason(id,0)=="",600): finish(); return
   var token:Dictionary=main.facility_pack_request(id,0)
   if not main.pack_facility(token): fail("撤去拒否 "+id); finish(); return
   var data:=SaveGame.capture(main)
   if not SaveGame.write(main,"user://packing-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://packing-flow.json")) or SaveGame.capture(main)!=data:
    fail("撤去状態の保存復元 "+SaveGame.last_error); finish(); return
   if not main.request_build(id): fail("再設置依頼拒否 "+id); finish(); return
   if not await wait_for("再設置 %s %d"%[id,repeat],func():return main.base.facility_count(id)==1,300): finish(); return
   if main.storage.count_of(FacilityDB.packed_item_of(id))!=0: fail("再設置後に完成品が残る"); finish(); return
  if id=="bed":
   main.workers[0].set_priority(GameData.Job.HUNT,prior_hunt)
   main.gather_policy=prior_gather.duplicate()
   main.refill_settings[GameData.Item.REPAIR_KIT].enabled=true
 finish()
