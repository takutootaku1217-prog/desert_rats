extends "res://tools/test_clarity_ui.gd"
func location(region: String,road: String="") -> void:
 main.world._archive()
 main.world.region=region; main.world.road=road; main.world.progress=0.0; main.world.direction=1
 main.world.phase="stopped" if road=="" else "travel"
 main.world.origin="" if road=="" else WorldMapDB.ROADS[road][0]
 main.world.destination="" if road=="" else WorldMapDB.ROADS[road][1]
 main.world._ensure_location()
func _initialize():
 main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); await main.ready
 paused=true
 for id in WorldMapDB.REGIONS:
  if WorldMapDB.public_region(id): location(id)
 for road in WorldMapDB.ROADS:
  if WorldMapDB.public_road(road): location(WorldMapDB.ROADS[road][0],road)
 var count:=0; var bones:=0; var species:={}
 for key in main.world.locations:
  var animals:=0
  for row in main.world.locations[key].values():
   if row.type!="creature": continue
   animals+=1; count+=1
   bones+=int(GameData.CREATURES[row.data.species].drops.get(GameData.Item.BONE,0))
   species[key]=row.data.species
  check(animals==(0 if key=="region:old_mine" else 1),"地点ごとの生物数を増やさない "+key)
 check(count==7 and bones==6,"初回生物7枠のうち6枠だけを既存の骨供給種へ変更")
 check(species["region:south_oasis"]=="hare" and species["road:01"]=="lizard" and species["region:east_sands"]=="lizard","村を変えず初期の村→砂原経路に骨の供給源")
 check(species["region:central_trade"]=="hump" and species["road:03"]=="hump" and species["road:04"]=="lizard" and species["road:06"]=="hump","変更箇所は2地域・4道路の計6枠")
 # 旧地図版ですべて生成済みのセーブを再現。生物・残量を勝手に置換しない。
 for key in main.world.locations:
  for id in main.world.locations[key]:
   var row:Dictionary=main.world.locations[key][id]
   if row.type=="creature":
    var c:=Creature.new(); c.setup(main,"hare"); c.world_id=id; c.position=row.data.position
    row.data=SaveGame.fields(c,SaveGame.CREATURE); c.free()
 location("south_oasis")
 var old:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://old-fauna.json",true) and SaveGame.apply(main,SaveGame.read("user://old-fauna.json")),"全域生成済みの旧生物配置も保存復元可能")
 for id in WorldMapDB.REGIONS:
  if WorldMapDB.public_region(id): location(id)
 for road in WorldMapDB.ROADS:
  if WorldMapDB.public_road(road): location(WorldMapDB.ROADS[road][0],road)
 check(main.world.locations==old.world.locations,"全地点を再訪しても旧生物・採取残量の台帳を一切変更しない")
 bones=0
 for records in main.world.locations.values():
  for row in records.values():
   if row.type=="creature": bones+=int(GameData.CREATURES[row.data.species].drops.get(GameData.Item.BONE,0))
 check(bones==0 and main.storage.count_of(GameData.Item.BONE)==0,"旧版で全域生成済み・骨なしの場合は供給行き止まりが残る（無断補填なし）")
 var before:Dictionary=main.world.locations.duplicate(true)
 # 未生成部分が一つ残っていた場合だけ、そこへ新しい初回配置を適用。
 main.world.locations.erase("region:east_sands"); before.erase("region:east_sands")
 location("east_sands")
 var after:Dictionary=main.world.locations.duplicate(true)
 var fresh:Dictionary=after["region:east_sands"]; after.erase("region:east_sands")
 check(after==before and fresh.values().any(func(r):return r.type=="creature" and r.data.species=="lizard"),"未生成地域だけに補修後の配置を適用し既存地域は保持")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails)); quit(1 if fails else 0)
