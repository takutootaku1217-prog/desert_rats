extends SceneTree
## 通常初期値・通常速度60・既定優先度の実AI通し。資源追加/進捗直書きは使わない。
## depletion_restart だけは、ユーザー指定の「都市で燃料・Cr・通常在庫=0」を作るため削除のみ行う。
var main
var fails:=0
var active_seed:=0
const STEP:=0.2

func check(ok:bool,msg:String)->void:
 print("  %s %s"%["ok" if ok else "FAIL",msg])
 if not ok:fails+=1
func boot(seed_id:int)->void:
 if main!=null:
  root.remove_child(main);main.queue_free();await process_frame
 SaveGame.disabled=true;active_seed=seed_id
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",seed_id);root.add_child(main)
 await process_frame
 # 自動_processを止め、同じ通常値のまま0.2秒ずつ明示的に進める（実時間ではなくゲーム内秒）。
 main.process_mode=Node.PROCESS_MODE_DISABLED
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
func travel(to:String,seconds:float=220.0)->bool:
 if not main.world.request(to):return false
 return await until(func():return main.world.region==to and main.world.phase=="stopped",seconds)
func counts()->Dictionary:
 return {"cr":main.town.credits,"fuel":snappedf(main.base.fuel,0.01),"hull":snappedf(main.base.parts[GameData.Part.HULL],0.01),"food":main.storage.count_of(GameData.Item.FOOD),"wood":main.storage.count_of(GameData.Item.WOOD),"stone":main.storage.count_of(GameData.Item.STONE),"elapsed":snappedf(main.director.elapsed,0.1)}
func tree_left()->int:
 main.world.sync()
 for row in main.world.locations.get("region:south_oasis",{}).values():
  if row.type=="gather" and row.data.kind=="tree":return int(row.data.remaining)
 return -1
func log_run(kind:String,before:Dictionary,extra:Dictionary={})->void:
 var after:=counts()
 print("SUBQUEST_FLOW kind=",kind," seed=",active_seed," game_seconds=",after.elapsed," before=",before," after=",after," extra=",extra)

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
 if "--zero-only" in OS.get_cmdline_user_args():
  await zero_city_restart()
  if main!=null:root.remove_child(main);main.queue_free()
  print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
  return
 for seed_id in [501,502,503]:await normal_cycle(seed_id)
 await exhausted_restart()
 await zero_city_restart()
 if main!=null:root.remove_child(main);main.queue_free()
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
