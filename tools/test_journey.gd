extends "res://tools/test_batch_crafting.gd"
func ready_world(region:String="south_oasis") -> void:
 await setup();main.target_speed=60
 main.world.active=true;main.world._archive();main.world.region=region;main.world.phase="stopped";main.world._ensure_location()
 main.operations.stance="normal"
 for w in main.workers:
  w.stop_work();w.floor_i=1;w.position=Vector2(700,GameData.LO_Y);w._climb_dest=null
func advance(distance:float) -> void:
 main.world.tick(distance);main.town.observe()
func start_path(path:Array,stops:Array=[]) -> void:
 check(main.journey.plan(path,stops),"経路を受理 "+str(path));advance(0)
func _initialize():
 await ready_world()
 var j=main.journey;var w=main.world
 check(WorldMapDB.paths("south_oasis","old_mine").size()==2,"既存道路だけで最短・迂回の2経路")
 check(not j.plan(["old_mine"]) and not j.plan(["central_trade","south_oasis"]) and not j.plan(["west_salt"]),"直通なし・循環・未実装地点を拒否")
 await start_path(["central_trade","old_mine"])
 main.scroll_speed=60;w.progress=1800;j.tick(0)
 check(j.notice=="central_trade" and j.notice_count==1,"10秒前に1回だけ立ち寄り通知")
 check(roundtrip() and j.notice=="central_trade","通知と経路を保存復元")
 for i in 20:j.tick(0.1)
 check(j.notice_count==1,"停止再開・連続tick・ロードで通知連打なし")
 advance(600)
 check(w.region=="central_trade" and w.destination=="old_mine" and w.phase=="travel" and not main.town.location_ok(),"中間都市は通過・街に入れない")
 check(j.remaining==["old_mine"] and j.last_arrival.begins_with("通過"),"次の区間へ進み通過を区別")
 advance(2400)
 check(w.region=="old_mine" and w.phase=="stopped" and j.remaining.is_empty(),"最終目的地は必ず停車")
 check(main.quarry.select(),"最終停車から既存の鉱床へ進める")
 check(not j.plan(["central_trade"]),"鉱床接近中の地域移動は拒否")
 await ready_world();j=main.journey;w=main.world
 await start_path(["east_sands","central_trade","old_mine"],["central_trade"])
 advance(2400);check(w.destination=="central_trade" and w.phase=="travel","未予約の砂原を通過")
 advance(2400);check(w.region=="central_trade" and w.phase=="stopped" and j.remaining==["old_mine"],"予約した都市で停車")
 check(roundtrip() and j.resume(),"停車予約後の保存・明示再開")
 advance(0);advance(2400);check(w.region=="old_mine" and w.phase=="stopped","再開後も最終停車")
 await ready_world("central_trade");j=main.journey;w=main.world
 check(main.town.execute(main.town.quote("accept_delivery")),"配達ミッションを受注")
 await start_path(["south_oasis","east_sands"])
 advance(2400);check(main.town.delivery=="outbound","村の自動通過では配達完了しない")
 advance(2400)
 await start_path(["south_oasis","central_trade"],["south_oasis"])
 advance(2400);check(main.town.delivery=="return" and w.phase=="stopped","予約した村の停泊で配達成立")
 check(j.resume(),"村から再開");advance(0);advance(2400)
 check(main.town.delivery=="ready" and main.town.location_ok(),"最終都市停泊で報酬受領可能")
 await ready_world();j=main.journey;w=main.world;j.confirm_each=true
 await start_path(["east_sands","central_trade"])
 advance(2400);check(w.phase=="stopped" and w.region=="east_sands","確認モードでは各地点停車")
 main.target_speed=0
 check(not j.resume() and main.target_speed==0,"手動停車を経路再開で解除しない")
 main.target_speed=60;main.operations.stance="recall"
 check(not j.resume() and main.operations.stance=="recall","呼戻し方針を解除しない")
 main.operations.stance="normal";check(j.resume(),"方針を戻して明示再開");advance(0)
 j.cancel_route();advance(2400);check(w.phase=="stopped" and j.remaining.is_empty(),"経路取消は次の地点で停車")
 await ready_world();j=main.journey;w=main.world
 await start_path(["east_sands","central_trade"])
 w.progress=2100;main.scroll_speed=200;j.tick(0.1)
 check(j.set_stop(j.notice,true),"高速・短い残距離でも立ち寄りを受理")
 advance(300);check(w.phase=="stopped" and w.region=="east_sands","通知から追加した立ち寄りで停車")
 check(j.resume(),"再開");advance(0);advance(200)
 var before:float=w.progress
 check(j.plan(["old_mine"]) and w.progress==before and j.remaining==["central_trade","old_mine"],"走行中の変更は現在区間を保持して先だけ変更")
 check(roundtrip() and w.progress==before,"走行途中の経路変更を保存")
 check(w.cancel_or_return() and j.remaining.is_empty(),"引返しは先の経路を破棄して既存帰還へ")
 advance(0);check(w.phase=="travel","引返しは瞬間移動せず同じ道路")
 await ready_world();j=main.journey;w=main.world
 await start_path(["central_trade","old_mine"])
 w.progress=1800;main.scroll_speed=60;j.tick(0)
 var worker=main.workers[0]
 worker.carrying=GameData.Item.WOOD;worker.carry_n=2
 advance(600)
 check(w.phase=="arriving" and j.notice=="central_trade","荷卸し待ちでは到着を確定せず案内を保持")
 check(roundtrip() and worker.carry_n==2,"到着待ちの通知・運搬物を保存復元")
 worker=main.workers[0];worker.carrying=-1;worker.carry_n=0
 main.operations.stance="recall";advance(0)
 check(w.phase=="stopped" and j.remaining==["old_mine"],"到着時の呼戻し意思が自動通過に優先")
 main.operations.stance="normal";worker.ai.danger_hold=true
 check(not j.resume() and worker.ai.danger_hold,"危険待機を自動解除しない")
 worker.ai.danger_hold=false
 await ready_world();j=main.journey;w=main.world
 await start_path(["central_trade","old_mine"])
 w.progress=1800;main.scroll_speed=60;j.tick(0);j.notice=""
 check(roundtrip(),"通知を閉じた状態を保存")
 main.scroll_speed=0;j.tick(1);main.scroll_speed=60;j.tick(1)
 check(j.notice=="" and j.notice_count==1,"閉じた通知は停止再開・ロードで復活しない")
 var invalid:=SaveGame.capture(main);invalid.journey.stops=["old_mine","old_mine"]
 check(not SaveGame.apply(main,invalid),"重複停車予約の保存を拒否")
 var old:=SaveGame.capture(main);old.erase("journey")
 check(SaveGame.apply(main,old) and j.remaining.is_empty() and not j.confirm_each,"旧v3は単一区間・自動予約なし")
 var bad:=SaveGame.capture(main);bad.journey.remaining=["west_salt"]
 check(not SaveGame.apply(main,bad),"到達不能な保存経路を拒否")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
