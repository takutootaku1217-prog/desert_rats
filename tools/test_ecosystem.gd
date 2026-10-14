extends "res://tools/test_world_fauna.gd"
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await main.ready
 paused=true
 location("south_oasis")
 var ore:=0;var wood:=0
 for row in main.world.locations[main.world.key()].values():
  if row.type=="gather":
   if row.data.kind=="vein":ore+=row.data.remaining
   if row.data.kind=="tree":wood+=row.data.remaining
 check(ore==4 and wood==36,"村の初回木36・鉄鉱石4は有限、基本鉄2種の準備用")
 var rows:Dictionary=main.world.locations[main.world.key()]
 for row in rows.values():
  if row.type=="gather":row.data.remaining=0;row.data.work=0.3
 var exhausted:Dictionary=rows.duplicate(true)
 location("east_sands");location("south_oasis")
 check(main.world.locations[main.world.key()]==exhausted,"安全側も枯渇と端数を保持、再訪で補充しない")
 location("old_mine");main.world._spawn_visible()
 var pool:Dictionary=main.world.locations[main.world.key()]
 check(pool.values().filter(func(r):return r.type=="enemy").size()==3,"鉱山は3性質の固定個体群")
 var id_count:int=main.world.next_id
 var before:Dictionary=pool.duplicate(true)
 main.world._ensure_location();main.world._spawn_visible()
 check(main.world.next_id==id_count and main.world.locations[main.world.key()]==before,"出入りや再表示は即リロールしない")
 main.director.elapsed=121.0;main.world._update_ecosystem();main.world.sync()
 var after:Dictionary=pool.duplicate(true)
 check(after!=before and main.world.next_id==id_count,"120秒更新で生存個体の位置/滞在数だけ変わる、増殖なし")
 var victim=main.enemies_root.get_child(0);var id:String=victim.world_id
 victim.take_damage(9999.0);await process_frame
 check(pool[id].spent,"死亡個体は消費済み記録")
 main.director.elapsed=241.0;main.world._update_ecosystem();main.world._spawn_visible()
 check(pool[id].spent and not main.enemies_root.get_children().any(func(e):return e.world_id==id),"次の時刻更新でも死亡した個体は補充しない")
 var d:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://eco.json",true) and SaveGame.apply(main,SaveGame.read("user://eco.json")) and SaveGame.capture(main)==d,"時刻・固定個体・死亡・資源残量の保存復元")
 check(main.quarry.remaining.values().reduce(func(a,b):return a+b,0)==84,"鉱山の資源84を維持")
 var allowed:=true
 for i in 100:
  if EventDB.def(main.director._pick()).get("kind","") in ["attack","chance"]:allowed=false
 check(allowed,"通常マップでは時刻だけの襲撃・生物/資源補充を抽選しない")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
