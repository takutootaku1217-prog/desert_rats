extends SceneTree
## 通常初期値・通常速度60・既定優先度の実AI通し。資源追加/進捗直書きは使わない。
## depletion_restart だけは、ユーザー指定の「都市で燃料・Cr・通常在庫=0」を作るため削除のみ行う。
var main
var fails:=0
var active_seed:=0
const STEP:=0.2
const CASH_ROUTE_REGIONS := ["central_trade","south_oasis","east_sands"]
const CASH_ROUTE_ROADS := ["03","04"]
const ORDINARY_FIELD_ITEMS := [GameData.Item.WOOD,GameData.Item.STONE,GameData.Item.IRON_ORE,GameData.Item.MEAT,GameData.Item.HIDE,GameData.Item.BONE,GameData.Item.FAT]

func check(ok:bool,msg:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",msg])
 if not ok:fails+=1
func boot(seed_id:int)->void:
 if main!=null:
  root.remove_child(main);main.queue_free();await process_frame;await process_frame
 SaveGame.disabled=true;active_seed=seed_id;seed(seed_id)
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",seed_id);root.add_child(main);main.process_mode=Node.PROCESS_MODE_DISABLED
 await process_frame
 # 自動_processを止め、同じ通常値のまま0.2秒ずつ明示的に進める（実時間ではなくゲーム内秒）。
func tick()->void:
 main._process(STEP)
 for r in main.resources_root.get_children():if not r.is_queued_for_deletion():r._process(STEP)
 for c in main.creatures_root.get_children():if not c.is_queued_for_deletion():c._process(STEP)
 for e in main.enemies_root.get_children():if not e.is_queued_for_deletion():e._process(STEP)
 for w in main.workers:w._process(STEP)
 await process_frame
func until(done:Callable,seconds:float)->bool:
 for i in ceili(seconds/STEP):
  if done.call():return true
  await tick()
 return done.call()
func action(a:String,item:int=-1,n:int=1)->bool:
 return main.town.execute(main.town.quote(a,item,n))
func city_ready(seconds:float=80.0)->bool:
 return await until(func():return main.town.entry_reason()=="",seconds)
func travel(to:String,seconds:float=420.0)->bool:
 if not main.world.request(to):return false
 return await until(func():return main.world.region==to and main.world.phase=="stopped",seconds)
func counts()->Dictionary:
 return {"cr":main.town.credits,"fuel":snappedf(main.base.fuel,0.01),"parts":parts_snapshot(),"speed_limit":snappedf(main.base.speed_limit(),0.01),"food":main.storage.count_of(GameData.Item.FOOD),"wood":main.storage.count_of(GameData.Item.WOOD),"stone":main.storage.count_of(GameData.Item.STONE),"elapsed":snappedf(main.director.elapsed,0.1)}
func parts_snapshot()->Dictionary:
 return {"hull":snappedf(main.base.parts[GameData.Part.HULL],0.01),"drive":snappedf(main.base.parts[GameData.Part.DRIVE],0.01),"machine":snappedf(main.base.parts[GameData.Part.MACHINE],0.01)}
func all_parts_full()->bool:
 return GameData.Part.values().all(func(part):return main.base.parts[part]>=99.99)
func tree_left()->int:
 main.world.sync()
 for row in main.world.locations.get("region:south_oasis",{}).values():
  if row.type=="gather" and row.data.kind=="tree":return int(row.data.remaining)
 return -1
func log_run(kind:String,before:Dictionary,extra:Dictionary={})->void:
 var after:=counts()
 print("SUBQUEST_FLOW kind=",kind," seed=",active_seed," game_seconds=",after.elapsed," before=",before," after=",after," extra=",extra)

## 枯渇用fixture: 中央→村（03）と中央→砂原（04）の通常採取台帳を全てspentにする。
## 依頼の移動、燃焼、回収AI、天候、報酬はこの後に通常処理で実行する。素材は追加しない。
func deplete_cash_route() -> void:
 main.world._archive()
 for region in CASH_ROUTE_REGIONS:
  main.world.region=region;main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination="";main.world.progress=0.0
  main.world._ensure_location()
 for road in CASH_ROUTE_ROADS:
  var ends:Array=WorldMapDB.ROADS[road]
  main.world.region=ends[0];main.world.phase="travel";main.world.road=road;main.world.origin=ends[0];main.world.destination=ends[1];main.world.direction=1;main.world.progress=0.0
  main.world._ensure_location()
 for key in main.world.locations:
  var rows:Dictionary=main.world.locations[key]
  for id in rows:
   var row:Dictionary=rows[id]
   if row.type in ["gather","resource"]:
    row.spent=true
    if row.type=="gather":row.data.remaining=0;row.data.work=0.0
 main.world.region="central_trade";main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination="";main.world.progress=0.0
func cash_route_depleted() -> bool:
 for region in CASH_ROUTE_REGIONS:
  if not _location_depleted("region:"+region):return false
 for road in CASH_ROUTE_ROADS:
  if not _location_depleted("road:"+road):return false
 return true
func _location_depleted(key:String) -> bool:
 var rows:Dictionary=main.world.locations.get(key,{})
 var seen:=0
 for id in rows:
  var row:Dictionary=rows[id]
  if row.type not in ["gather","resource"]:continue
  seen+=1
  if not row.spent:return false
  if row.type=="gather" and int(row.data.remaining)!=0:return false
 return seen>0
func ordinary_field_total() -> int:
 var n:=0
 for item in ORDINARY_FIELD_ITEMS:n+=main.storage.count_of(item)
 return n
func setup_cash_only_city() -> void:
 deplete_cash_route()
 main.storage.inventory.counts.clear();main.processor.stock.counts.clear();main.town.credits=0;main.base.fuel=0.0
 for species in main.hunt_policy:main.hunt_policy[species]=false
 for w in main.workers:
  w.stop_work();w.floor_i=1;w.position=Vector2(700,GameData.LO_Y);w._climb_dest=null
  w.priorities[GameData.Job.GATHER]=0;w.priorities[GameData.Job.HUNT]=0
  # 食料を報酬で買って実際に食べるかを見るための、悪化だけを行う検証設定。
  w.hunger=20.0
 # 報酬金から実際に全3部位を直せるかを測る。813のみ走行装置0=最低速15を再現する。
 main.base.parts[GameData.Part.HULL]=75.0
 main.base.parts[GameData.Part.DRIVE]=0.0 if active_seed==813 else 75.0
 main.base.parts[GameData.Part.MACHINE]=75.0
 main.world._ensure_location()
 # �͊��t�B�N�X�`���̍�z���Ɏ������g�����Ƀf�f���[�v�̕���񐔗���ōč�������B
 seed(active_seed)
func repair_all_to_full() -> Dictionary:
 var before:=parts_snapshot()
 var paid:=0
 var spent:=0
 var by_part:Dictionary={}
 for part in GameData.Part.values():
  while main.base.parts[part]<99.99:
   var credits_before:int=main.town.credits
   if not action("repair_cash",part):break
   paid+=1;spent+=credits_before-main.town.credits
   by_part[str(part)]=int(by_part.get(str(part),0))+1
 return {"before":before,"after":parts_snapshot(),"paid":paid,"spent":spent,"by_part":by_part}
func repair_hull_to_full() -> int:
 var paid:=0
 while main.base.parts[GameData.Part.HULL]<100.0:
  if not action("repair_cash",GameData.Part.HULL):break
  paid+=1
 return paid
func repair_part_to_full(part:int) -> int:
 var paid:=0
 while main.base.parts[part]<99.99:
  if not action("repair_cash",part):break
  paid+=1
 return paid

## 全通常採取場所を枯渇させ、採取/狩猟を無効にしたまま、報酬だけで3配達+3回収を回す。
func cash_only_repeat(seed_id:int) -> Dictionary:
 await boot(seed_id);setup_cash_only_city()
 var t=main.town
 var before:=counts()
 if active_seed==813:check(is_equal_approx(main.base.speed_limit(),GameData.CRAWL_SPEED),"cash-only seed 813: drive=0 records the 15-speed crawl before repair")
 check(cash_route_depleted() and ordinary_field_total()==0 and main.total_gathered==0 and main.total_hunted==0,"cash-only seed %d: 対象3地域・道路03/04の木石鉱を全枯渇、通常素材0"%seed_id)
 check(main.workers.all(func(w):return w.priorities[GameData.Job.GATHER]==0 and w.priorities[GameData.Job.HUNT]==0),"cash-only seed %d: 採取・狩猟の通常素材取得を除外"%seed_id)
 var ate_before:int=main.total_eaten
 var weather_seen:=false
 for lap in 3:
  if lap>0:repair_hull_to_full() # 前周の回収報酬も、次の出発前整備へ使う。
  var before_delivery:int=t.credits
  check(await city_ready() and action("accept_delivery") and t.delivery_cargo,"cash-only %d周目: 前渡し付き配達を受注"%[lap+1])
  check(await travel("south_oasis") and await travel("central_trade") and await city_ready() and action("claim_delivery") and t.credits==before_delivery+TownDB.DELIVERY_REWARD,"cash-only %d周目: 素材なしで配達報酬32 Crを受領"%[lap+1])
  var food_n:=3 if lap==0 else 1
  var bought_maintenance:bool=action("buy",GameData.Item.FOOD,food_n) and action("fuel_cash")
  var paid_repairs:int=repair_hull_to_full()
  check(bought_maintenance and paid_repairs>0,"cash-only %d周目: 報酬金で食料・修理・燃料を実購入"%[lap+1])
  if lap==0:check(await until(func():return main.total_eaten>=ate_before+3 and main.workers.all(func(w):return w.hunger>=CrewStatusDB.EAT_BELOW),120.0),"cash-only: 購入食料を3人が実際に消費して回復")
  var before_recovery:int=t.credits
  check(action("accept_recovery") and await travel("east_sands") and await until(func():return t.recovery=="return",240.0),"cash-only %d周目: 通常素材なしで仲間が遺失物を回収"%[lap+1])
  check(await travel("central_trade") and await city_ready() and action("claim_recovery") and t.credits==before_recovery+TownDB.RECOVERY_REWARD,"cash-only %d周目: 回収報酬38 Crを受領"%[lap+1])
  if lap==0:
   var drive_paid:int=repair_part_to_full(GameData.Part.DRIVE)
   check(drive_paid>0 and main.base.speed_limit()>GameData.CRAWL_SPEED,"cash-only seed %d: first reward repairs the disabled drive and restores speed"%seed_id)
  weather_seen=weather_seen or int(main.director.stats.get("weather",0))>0
  check(ordinary_field_total()==0 and main.total_gathered==0 and main.total_hunted==0,"cash-only %d周目: 採取・狩猟の通常素材収入なし"%[lap+1])
 repair_hull_to_full()
 var final_repair:Dictionary=repair_all_to_full()
 check(final_repair.paid>0 and final_repair.spent>0 and all_parts_full() and main.base.speed_limit()>GameData.CRAWL_SPEED,"cash-only seed %d: rewards purchase every required part repair and restore speed"%seed_id)
 print("SUBQUEST_REPAIR seed=",active_seed," final=",final_repair," speed_limit=",main.base.speed_limit())
 check(not main.game_over and main.base.parts[GameData.Part.HULL]>=75.0 and main.storage.count_of(GameData.Item.FOOD)>=0 and t.claimed.delivery==3 and t.claimed.recovery==3,"cash-only seed %d: 購入品で3配達+3回収を維持"%seed_id)
 log_run("cash_only_repeat",before,{"claimed":t.claimed.duplicate(true),"ordinary_total":ordinary_field_total(),"gathered":main.total_gathered,"hunted":main.total_hunted,"eaten":main.total_eaten,"weather":main.director.stats.get("weather",0),"route_depleted":cash_route_depleted()})
 return {"weather":weather_seen,"credits":t.credits,"fuel":snappedf(main.base.fuel,0.01),"parts":parts_snapshot(),"speed_limit":snappedf(main.base.speed_limit(),0.01),"eaten":main.total_eaten,"claimed":t.claimed.duplicate(true)}

func cash_only_suite(seeds:Array,label:String) -> Dictionary:
 var results:Dictionary={}
 for seed_id in seeds:
  results[str(seed_id)]=await cash_only_repeat(int(seed_id))
 print("SUBQUEST_ORDER label=",label," results=",results)
 return results
func cash_only_same_result(a:Dictionary,b:Dictionary) -> bool:
 return a.credits==b.credits and is_equal_approx(a.fuel,b.fuel) and a.parts==b.parts and is_equal_approx(a.speed_limit,b.speed_limit) and a.eaten==b.eaten and a.claimed==b.claimed

## 前渡しを使った未受領依頼を取り消した場合も、燃料を増やして再受注できないことを確認する。
func advance_cancel_case() -> void:
 await boot(851);setup_cash_only_city()
 var t=main.town
 check(await city_ready() and action("accept_delivery"),"前渡し取消ケース: 配達を受注")
 check(await travel("south_oasis") and await travel("central_trade") and await city_ready() and t.delivery=="ready","前渡し取消ケース: 前渡し燃料だけで往復")
 var fuel_before:float=main.base.fuel
 check(action("cancel_delivery") and action("accept_delivery") and is_equal_approx(main.base.fuel,fuel_before),"前渡し取消ケース: 未受領取消→再受注で燃料を再発行しない")
 check(main.world.request("south_oasis") and main.world.phase=="departing","前渡しを使い切っても既存の低速走行では出発要求自体は可能（保証を過大化しない）")
 main.world.cancel_or_return()
 log_run("advance_cancel",{"fuel":snappedf(fuel_before,0.01)},{"fuel_after_reaccept":snappedf(main.base.fuel,0.01),"crawl_speed":GameData.CRAWL_SPEED})

## 既存の寒波（暖房燃料を消費、速度低下）を明示発生させ、前渡し10だけの最初の往復を観測する。
## 前渡しだけで通常速度を保証する試験ではなく、燃料切れ後も既存の低速走行で都市へ戻れるかを確認する。
func cold_advance_case() -> void:
 await boot(852);setup_cash_only_city()
 var t=main.town
 main.director.trigger("coldsnap",false)
 main.director.set_stance("coldsnap","run") # 暖房燃料を実際に消費する既存の「走り続ける」を選ぶ。
 var cold_started:bool=main.director.active.any(func(a):return a.id=="coldsnap")
 check(cold_started and await city_ready() and action("accept_delivery"),"寒波ケース: 暖房消費・悪天候中に前渡し配達を受注")
 check(await travel("south_oasis") and await travel("central_trade") and await city_ready() and action("claim_delivery") and t.credits==TownDB.DELIVERY_REWARD,"寒波ケース: 前渡し後に燃料切れ低速を含んでも都市へ往復して32 Crを受領")
 check(ordinary_field_total()==0 and main.total_gathered==0 and main.total_hunted==0,"寒波ケース: 通常素材取得なし")
 log_run("cold_advance",{"fuel":0.0},{"fuel_after":snappedf(main.base.fuel,0.01),"weather":main.director.stats.get("weather",0),"log":main.director.log.duplicate(true)})

func normal_cycle(seed_id:int)->void:
 await boot(seed_id)
 var t=main.town
 check(is_equal_approx(main.target_speed,60.0) and main.workers[0].priorities[GameData.Job.GATHER]==5 and main.workers[1].priorities[GameData.Job.GATHER]==3 and main.workers[2].priorities[GameData.Job.GATHER]==1,"seed %d: 通常速度・既定優先度を維持"%seed_id)
 var initial:=counts()
 check(await travel("central_trade") and await city_ready(),"seed %d: 初期オアシスから実走行で中央都市へ"%seed_id)
 var delivery_before:=counts()
 check(action("accept_delivery") and t.delivery=="outbound" and t.delivery_cargo,"配達を受注（通常素材は増やさず専用荷物だけ積載）")
 check(await travel(TownDB.DELIVERY_TO) and t.delivery=="return","配達先へ実走行して専用荷物を引渡し")
 check(await travel("central_trade") and await city_ready() and t.delivery=="ready","配達後に仲間・荷物を戻して都市へ実帰還")
 check(action("claim_delivery") and t.credits==int(delivery_before.cr)+TownDB.DELIVERY_REWARD,"配達報酬を都市で一度受領")
 log_run("delivery",delivery_before,{"mission_weight":TownDB.DELIVERY_PARCEL_WEIGHT})
 var supply_before:=counts()
 check(action("accept_supply",GameData.Item.WOOD),"木材6個の調達納品を受注")
 check(await travel("south_oasis"),"納品素材を求めて通常ルートを実走行")
 var got_wood:bool=await until(func():return main.storage.count_of(GameData.Item.WOOD)>=TownDB.SUPPLY_OFFERS[GameData.Item.WOOD].count,260.0)
 check(got_wood,"既定優先度の仲間が有限採取場から木材6個を実採取")
 check(await travel("central_trade") and await city_ready(),"採取物を持ち帰り中央都市へ実帰還")
 check(action("claim_supply") and t.claimed.supply==1,"予約外の手持ち木材だけを納品し調達報酬を受領")
 log_run("supply",supply_before,{"gathered_wood":TownDB.SUPPLY_OFFERS[GameData.Item.WOOD].count,"initial":initial})
 var recovery_before:=counts()
 check(action("accept_recovery") and t.recovery=="outbound","遺失物回収を受注")
 check(await travel(TownDB.RECOVERY_TO),"回収地点へ実走行")
 var reached_loading:bool=await until(func():return t.recovery=="loading",90.0)
 check(reached_loading,"画面上の仲間が既存の警戒判定を通って遺失物へ歩き出す")
 var saved:=SaveGame.capture(main)
 check(SaveGame.apply(main,saved),"遺失物へ向かう途中の通常保存/ロード")
 check(await until(func():return t.recovery=="return",140.0),"仲間が専用荷物を移動拠点へ実運搬")
 check(main.storage.count_of(GameData.Item.WOOD)>=0 and t.mission_cargo_weight()==TownDB.RECOVERY_PARCEL_WEIGHT,"回収荷物は通常素材を増やさず専用重量だけを保持")
 check(await travel("central_trade") and await city_ready() and t.recovery=="ready","回収荷物を積んで都市へ実帰還")
 check(action("claim_recovery") and t.claimed.recovery==1,"回収報酬を都市で一度受領")
 log_run("recovery",recovery_before,{"mission_weight":TownDB.RECOVERY_PARCEL_WEIGHT,"initial":initial})
 check(not main.game_over,"seed %d: 3種通し後もゲームオーバーなし"%seed_id)

func exhausted_restart()->void:
 await boot(701)
 # 通常初期配置のオアシスで、実AIに有限な木を全量採取させる。資源を補充しない。
 var before:=counts()
 check(await until(func():return tree_left()==0,420.0),"枯渇ケース: 初期オアシスの木材採取場を実AIで全枯渇")
 check(await travel("central_trade") and await city_ready(),"枯渇後も都市へ実帰還")
 check(action("accept_delivery") and await travel("south_oasis") and await travel("central_trade") and action("claim_delivery"),"枯渇後も配達だけで1周し報酬を得る")
 check(action("accept_recovery") and await travel("east_sands"),"枯渇後も通常素材なしで回収へ出発")
 check(await until(func():return main.town.recovery=="return",140.0) and await travel("central_trade") and action("claim_recovery"),"枯渇後も回収だけで1周し報酬を得る")
 log_run("exhausted_repeat",before,{"tree_left":tree_left(),"claimed":main.town.claimed.duplicate(true)})

func zero_city_restart()->void:
 await boot(801)
 # 検証専用の枯渇設定: 初期資源を追加せず、燃料・Cr・通常在庫を0にした中央都市停泊から開始する。
 # 以降は全て通常の経路要求、燃焼、AI、報酬処理で進む。
 main.world._archive();main.world.region="central_trade";main.world.phase="stopped";main.world.road="";main.world.origin="";main.world.destination="";main.world._ensure_location()
 main.storage.inventory.counts.clear();main.processor.stock.counts.clear();main.town.credits=0;main.base.fuel=0.0
 for w in main.workers:w.stop_work();w.floor_i=1;w.position=Vector2(700,GameData.LO_Y);w._climb_dest=null
 var before:=counts()
 check(await city_ready() and action("accept_delivery") and is_equal_approx(main.base.fuel,TownDB.DELIVERY_FUEL_ADVANCE),"ゼロ資源都市: 前渡し燃料で配達を受注")
 check(await travel("south_oasis") and await travel("central_trade") and await city_ready() and action("claim_delivery") and main.town.credits==TownDB.DELIVERY_REWARD,"ゼロ資源都市: 実走行配達で32 Crを再取得")
 check(action("fuel_cash") and main.base.fuel>TownDB.DELIVERY_FUEL_ADVANCE,"配達報酬で次の活動用燃料を購入")
 check(action("accept_recovery") and await travel("east_sands") and await until(func():return main.town.recovery=="return",140.0),"燃料購入後に回収も実AIで完了")
 check(await travel("central_trade") and await city_ready() and action("claim_recovery") and main.town.credits>=TownDB.DELIVERY_REWARD-TownDB.SERVICE_PRICE+TownDB.RECOVERY_REWARD,"ゼロ資源都市: 配達→給油→回収で次の燃料・修理・食料の資金を確保")
 log_run("zero_city_restart",before,{"claim":main.town.claimed.duplicate(true),"depletion_fixture":true})

func _initialize()->void:
 var args:=OS.get_cmdline_user_args()
 for seed_id in [811,812,813]:
  if ("--cash-only-single-%d"%seed_id) in args:
   await cash_only_suite([seed_id],"single_%d"%seed_id)
   if main!=null:root.remove_child(main);main.queue_free()
   print("== result: %s =="%("all passed" if fails==0 else "%d failed"%fails));quit(1 if fails else 0)
   return
 if "--cash-only-reverse" in args:
  await cash_only_suite([813,812,811],"reverse")
  if main!=null:root.remove_child(main);main.queue_free()
  print("== result: %s =="%("all passed" if fails==0 else "%d failed"%fails));quit(1 if fails else 0)
  return
 if "--cash-only" in OS.get_cmdline_user_args():
  var weather_any:=false
  var forward:Dictionary={}
  for seed_id in [811,812,813]:
   var result:Dictionary=await cash_only_repeat(seed_id)
   forward[str(seed_id)]=result
   weather_any=weather_any or result.weather
  var reverse:Dictionary=await cash_only_suite([813,812,811],"reverse_after_batch")
  for seed_id in [811,812,813]:
   check(cash_only_same_result(forward[str(seed_id)],reverse[str(seed_id)]),"cash-only order independent seed %d: credits/fuel/parts/speed match"%seed_id)
  check(weather_any,"cash-only: 複数seedで悪天候を含む走行でも前渡し開始から報酬循環")
  await advance_cancel_case()
  await cold_advance_case()
  if main!=null:root.remove_child(main);main.queue_free()
  print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
  return
 if "--zero-only" in OS.get_cmdline_user_args():
  await zero_city_restart()
  if main!=null:root.remove_child(main);main.queue_free()
  print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
  return
 for seed_id in [501,502,503]:await normal_cycle(seed_id)
 await exhausted_restart()
 await zero_city_restart()
 var weather_any:=false
 var forward:Dictionary=await cash_only_suite([811,812,813],"forward_core")
 for seed_id in [811,812,813]:weather_any=weather_any or forward[str(seed_id)].weather
 var reverse:Dictionary=await cash_only_suite([813,812,811],"reverse_core")
 for seed_id in [811,812,813]:
  check(cash_only_same_result(forward[str(seed_id)],reverse[str(seed_id)]),"cash-only core order independent seed %d: credits/fuel/parts/speed match"%seed_id)
 check(weather_any,"cash-only: 複数seedで悪天候を含む走行でも前渡し開始から報酬循環")
 await advance_cancel_case()
 await cold_advance_case()
 if main!=null:root.remove_child(main);main.queue_free()
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
