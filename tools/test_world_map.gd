extends "res://tools/test_clarity_ui.gd"
func _initialize():
 main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); await main.ready
 paused=true
 if OS.get_cmdline_user_args().has("restart"):
  var data:=SaveGame.read("user://world-test.json")
  check(SaveGame.apply(main,data),"別プロセスで道中セーブ復元")
  check(SaveGame.capture(main)==data,"道路座標・全地域資源・所有物が再起動後も一致")
  finish(); return
 main.director.enabled=false
 for w in main.workers:
  w.stop_work(); w.ai.state=CharacterAI.State.IDLE; w.set_process(false)
 main.world.tick(0)
 check(main.world.active and main.world.region=="south_oasis","新規ゲームは村・地図が既定")
 check(WorldMapDB.REGIONS.size()==10 and WorldMapDB.ROADS.size()==12,"正本10地域12道路")
 check(not main.world.request("old_mine") and not main.world.request("west_salt"),"直通なし・未公開地域を拒否")
 await click(button_named(main.map_ui,"地図 / 行先 (M)"))
 check(main.map_ui.is_open() and paused,"画面ボタンで地図・一時停止")
 check(main.map_ui._roads.keys()==["01","03","04","06"],"画面の4道路は正本の公開接続だけ")
 check(main.map_ui._marker.position==WorldMapDB.REGIONS.south_oasis.pos+Vector2(45,-18),"現在地マーカーは村")
 for rid in main.map_ui._roads:
  var ends:Array=WorldMapDB.ROADS[rid]
  var line:Line2D=main.map_ui._roads[rid]
  check(line.points[0]==WorldMapDB.REGIONS[ends[0]].pos+Vector2(40,20) and line.points[1]==WorldMapDB.REGIONS[ends[1]].pos+Vector2(40,20),"描画道路と接続先が一致 "+rid)
 await click(main.map_ui._nodes["east_sands"])
 check(main.map_ui._info.text.contains("東部砂原") and not main.map_ui._confirm.disabled,"隣接地域を実入力で選択")
 await click(main.map_ui._confirm)
 paused=true
 check(main.world.phase=="departing","選択して出発準備")
 check(main.world.cancel_or_return() and main.world.region=="south_oasis","出発前取消は移動・再配布なし")
 check(main.world.request("east_sands"),"正規道路01を選択")
 var w=main.workers[0]
 w.floor_i=0; w.position=GameData.RAMP_FOOT
 var pos:Vector2=w.position
 main.world.tick(0)
 check(main.world.phase=="departing" and w.position==pos,"屋外仲間は瞬間移動せず帰還を待つ")
 for i in 400:
  w._process(0.05)
  if w.floor_i>0 and w._climb_dest==null: break
 w.ai.res=null; w.ai.prey=null; w.ai.enemy=null
 main.world.tick(0)
 check(main.world.phase=="travel","実際に歩いて帰還後に走行開始")
 var before_fuel:float=main.base.fuel
 var before_distance:float=main.director.distance
 for i in 5: main._process(1.0)
 check(main.world.progress>0 and main.base.fuel<before_fuel and main.director.distance>before_distance,"走行量で進捗・燃料・距離が同時更新")
 main.map_ui.open(); await frames()
 var ends:Array=WorldMapDB.ROADS[main.world.road]
 var expected:Vector2=(WorldMapDB.REGIONS[ends[0]].pos+Vector2(45,24)).lerp(WorldMapDB.REGIONS[ends[1]].pos+Vector2(45,24),main.world.progress/WorldMapDB.LENGTH)
 check(main.map_ui._marker.position.is_equal_approx(expected) and main.map_ui._info.text.contains(WorldMapDB.name_of(main.world.destination)),"道中の現在地と目的地が走行状態に一致")
 main.map_ui.close(); paused=true
 var roadkey:String=main.world.key()
 var p
 for n in main.resources_root.get_children():
  if n is GatherPoint: p=n; break
 check(p!=null,"道路の固定資源が出現")
 p.remaining-=1; p.work=0.35
 var id:String=p.world_id
 main.world.sync()
 var remaining:int=p.remaining
 var count:int=main.world.locations[roadkey].size()
 var coord:float=main.world.progress
 for i in 6:
  check(main.world.cancel_or_return(),"途中引返し要求 %d"%i)
  main.world.tick(0)
  check(main.world.progress==coord,"引返しで道路進捗を0へ戻さない")
 check(main.world.locations[roadkey].size()==count and main.world.locations[roadkey][id].data.remaining==remaining and main.world.locations[roadkey][id].data.work==0.35,"無限切替で資源数・残量・採取進捗を増減しない")
 var d:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://world-test.json",true),"道中保存 "+SaveGame.last_error)
 check(SaveGame.apply(main,SaveGame.read("user://world-test.json")) and SaveGame.capture(main)==d,"道中ロードで全状態一致")
 var output:=[]
 var result:=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"-s","res://tools/test_world_map.gd","--","restart"],output,true)
 for line in output: print(line)
 check(result==0,"別プロセス再開成功")
 # 全員を屋内に保つ境界fixture。時間/消費は通常Main処理で進める。
 for worker in main.workers: worker.set_process(false)
 for i in 100:
  main._process(1.0)
  if main.world.phase=="stopped": break
 check(main.world.region=="east_sands" and main.world.phase=="stopped","東部砂原に到着")
 check(main.world.request("south_oasis"),"復路も同じ道路01")
 main.world.tick(0)
 check(main.world.locations[roadkey].size()==count and main.world.locations[roadkey][id].data.remaining==remaining,"再訪で道路の資源再抽選なし")
 # 旧形式の内容を作り、変換前には自動で地域を割り当てない。
 main.world.active=false; main.world.phase="stopped"
 var old:=SaveGame.capture(main); old.erase("world"); old.version=2
 for row in old.resources: row.resource.erase("world_id")
 for row in old.creatures+old.enemies: row.erase("world_id")
 var bytes:=var_to_bytes(old)
 var hash:=HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
 var file:=FileAccess.open("user://old-world.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"version":2,"payload":Marshalls.raw_to_base64(bytes),"sha256":hash.finish().hex_encode()})); file.close()
 var original:=FileAccess.get_file_as_bytes("user://old-world.json")
 check(SaveGame.read("user://old-world.json").is_empty() and FileAccess.get_file_as_bytes("user://old-world.json")==original,"旧v2は無確認で読込・書換しない")
 main.world.active=true
 main.save_ui.path="user://old-world.json"
 main.save_ui.open()
 main.save_ui.ask("load"); main.save_ui.execute()
 check(main.save_ui._legacy.visible,"旧保存の明示移行ボタンを表示")
 await frames() # 新たに表示したContainer子の座標確定を待って実入力する。
 await click(main.save_ui._legacy)
 check(main.save_ui._action=="migrate" and main.save_ui._confirm.visible,"移行は別の確認操作を要求")
 var before_cancel:=SaveGame.capture(main)
 await key(KEY_ESCAPE)
 check(SaveGame.capture(main)==before_cancel and FileAccess.get_file_as_bytes("user://old-world.json")==original,"移行確認の取消は進行も旧ファイルも保全")
 main.save_ui.open(); await frames()
 await click(button_named(main.save_ui,"続きから")); await click(main.save_ui._confirm)
 await click(main.save_ui._legacy)
 check(main.world.active,"確認実行前は地域状態を変更しない")
 await click(main.save_ui._confirm)
 check(main.save_ui._text.text.begins_with("旧保存を読み込みました"),"実入力の確認実行で移行完了")
 check(not main.world.active and FileAccess.get_file_as_bytes("user://old-world.json")==original,"明示移行後も旧ファイルは変更しない")
 main.save_ui.close(); paused=true
 var migrated:=SaveGame.migrate_v2(old,main)
 check(not migrated.is_empty() and not migrated.world.active,"旧街道は地域未配置で移行")
 check(SaveGame.apply(main,migrated),"旧街道の在庫・時間・鉱床残量を復元")
 var qty:Dictionary=main.storage.inventory.counts.duplicate()
 check(main.world.request_legacy_region(),"村への割当を明示的に要求")
 main.world.tick(0)
 check(main.world.active and main.world.region=="south_oasis" and main.storage.inventory.counts==qty,"同意後だけ村へ割当・初期物資の再配布なし")
 check(SaveGame.write(main,"user://old-world.json",true),"移行後に明示的に新形式保存")
 check(FileAccess.get_file_as_bytes("user://old-world.json.legacy-v2")==original,"旧v2の元バイト列を別ファイルに保全")
 var preserved:=FileAccess.get_file_as_bytes("user://old-world.json.legacy-v2")
 # 異なる旧v2を後で持ち込んでも以前の保全を上書きしない。
 old.main.wave+=1
 bytes=var_to_bytes(old); hash=HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
 file=FileAccess.open("user://old-world.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"version":2,"payload":Marshalls.raw_to_base64(bytes),"sha256":hash.finish().hex_encode()})); file.close()
 var second_old:=FileAccess.get_file_as_bytes("user://old-world.json")
 var digest:=FileAccess.get_sha256("user://old-world.json")
 file=FileAccess.open("user://old-world.json.bak",FileAccess.WRITE); file.store_buffer(original); file.close()
 check(SaveGame.write(main,"user://old-world.json",true),"異なる旧v2の上書きも保全して保存")
 check(FileAccess.get_file_as_bytes("user://old-world.json.legacy-v2")==preserved and FileAccess.get_file_as_bytes("user://old-world.json.legacy-v2."+digest)==second_old and FileAccess.get_file_as_bytes("user://old-world.json.bak")==original,"以前の旧版・今回の旧版・既存バックアップを全て保持")
 old.creatures={}
 var current:=SaveGame.capture(main)
 check(SaveGame.migrate_v2(old,main).is_empty() and SaveGame.capture(main)==current,"壊れた旧版の配列を例外なく拒否し現在進行を保持")
 finish()
func finish():
 print("== 結果: %s ==" % ("すべて成功" if fails==0 else "%d 件失敗"%fails))
 quit(1 if fails else 0)
