extends "res://tools/test_clarity_ui.gd"
## 境界専用fixture。通常進行はtest_world_flowで別に実行。
func old_format(d: Dictionary) -> Dictionary:
 var old:=d.duplicate(true); old.erase("world"); old.version=2
 for r in old.resources: r.resource.erase("world_id")
 for r in old.creatures+old.enemies: r.erase("world_id")
 return old
func roundtrip(label: String) -> void:
 var d:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://world-boundary.json",true),label+" 保存 "+SaveGame.last_error)
 check(SaveGame.apply(main,SaveGame.read("user://world-boundary.json")),label+" 復元 "+SaveGame.last_error)
 check(SaveGame.capture(main)==d,label+" 全持続状態一致")
func _initialize():
 main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); await main.ready
 paused=true; main.director.enabled=false
 for w in main.workers:
  w.stop_work(); w.ai.state=CharacterAI.State.IDLE; w.set_process(false)
 main.world.tick(0)
 var initial:=SaveGame.capture(main)
 # 空き枠を持たない運搬者も通常の収納で帰還できる。加工・装備も同居。
 main.base.add_facility("workbench",true)
 main.processor.current=GameData.recipe_by_id("smelt").duplicate(true)
 main.processor.progress=1.25
 main.processor.output=[GameData.Item.FOOD]
 var worker=main.workers[0]
 worker.carrying=GameData.Item.IRON_ORE; worker.carry_n=1; worker.carry_source=Inventory.SOURCE_ENVIRONMENT
 worker.floor_i=0; worker.position=GameData.RAMP_FOOT; worker.ai.state=CharacterAI.State.MOVE_TO_STORAGE
 worker.weapon=GameData.Item.SIMPLE_SPEAR
 main.storage.inventory.counts.clear()
 main.storage.inventory.add(GameData.Item.BONE,main.storage.max_weight()-main.storage.current_weight()-main.storage.processing_reserve())
 check(main.storage.free_for(GameData.Item.IRON_ORE)==0,"保有物・運搬・加工予約込み満載fixture")
 check(main.world.request("east_sands"),"満載でも出発要求は受理して帰還待ち")
 main.world.tick(0)
 check(main.world.phase=="departing","荷物を消さず帰還待ち")
 roundtrip("満載の帰還待ち・加工中・完成品・装備")
 for i in 1600:
  worker._process(0.05)
  if worker.carrying<0 and worker.floor_i>0 and worker._climb_dest==null: break
 check(worker.carrying<0 and main.storage.count_of(GameData.Item.IRON_ORE)==1,"満載の保有運搬物を通常収納して帰還")
 var material:Dictionary=main.processor.current.duplicate(true)
 var stock:Dictionary=main.storage.inventory.counts.duplicate(true)
 main.world.tick(0)
 check(main.world.phase=="travel" and main.storage.inventory.counts==stock and main.processor.current==material and main.processor.progress==1.25 and worker.weapon==GameData.Item.SIMPLE_SPEAR,"地域切替で材料・加工進捗・装備・保有数量を保持")
 # 加工の増量予約は切替でも変えない。倉庫廃棄で空きを作れる。
 var reserved:int=main.storage.processing_reserve()
 var snap:Dictionary=main.warehouse_discard_snapshot(GameData.Item.BONE,8)
 check(main.discard_warehouse(snap) and not main.discard_warehouse(snap),"正規の倉庫廃棄で満載解除・二重確定拒否")
 check(main.storage.processing_reserve()==reserved and main.storage.free_for(GameData.Item.IRON_ORE)>=1,"廃棄でも加工予約を維持し回収余地を回復")
 # 単品消費は墓標を残し、引返し/保存で復活しない。
 var item:=ResourceNode.new(); item.game=main; item.item=GameData.Item.WOOD; item.position=Vector2(1100,650); main.resources_root.add_child(item)
 main.world.sync(); var consumed:String=item.world_id
 main.world.consume(item); main.resources_root.remove_child(item); item.queue_free()
 var roadkey:String=main.world.key()
 for i in 4:
  main.world.cancel_or_return(); main.world.tick(0)
 check(main.world.locations[roadkey][consumed].spent,"方向変更後も消費済み単品を保持")
 for n in main.resources_root.get_children(): check(n.world_id!=consumed,"消費済み単品の実体を再生成しない")
 roundtrip("消費済み台帳")
 var live:=ResourceNode.new(); live.game=main; live.item=GameData.Item.STONE; live.position=Vector2(1100,650); main.resources_root.add_child(live)
 var good:=SaveGame.capture(main)
 var bad:=good.duplicate(true)
 bad.world.locations[roadkey][consumed].spent=false
 # 既存実体と台帳の相違・重複IDを適用前に拒否する。
 if not good.resources.is_empty():
  var id:String=good.resources[0].resource.world_id
  bad=good.duplicate(true); bad.world.locations[roadkey][id].spent=true
  check(not SaveGame.apply(main,bad) and SaveGame.capture(main)==good,"消費済み台帳と生存実体の矛盾を拒否・現状保全")
  bad=good.duplicate(true); bad.resources.append(bad.resources[0].duplicate(true))
  check(not SaveGame.apply(main,bad) and SaveGame.capture(main)==good,"実体IDの複製を拒否")
 check(SaveGame.apply(main,initial),"独立した旧版移行ケースへ初期fixture復元")
 # 旧v2の鉱床へ向かう途中/滞在/帰還待ち/帰路。場所不明の途中は自動割当しない。
 main.world._archive(); main.world.region="old_mine"; main.world.locations.clear(); main.world._ensure_location()
 check(main.quarry.select(),"地図の大鉱山入口から既存鉱床を選択")
 var approach:=SaveGame.capture(main)
 var migrated:=SaveGame.migrate_v2(old_format(approach),main)
 check(not migrated.is_empty() and not migrated.world.active,"旧接近中は地域未確定として保全")
 check(SaveGame.apply(main,migrated) and not main.world.request_legacy_region(),"旧接近中の位置割当は拒否")
 main.quarry.left=0; main.quarry.tick(0)
 check(main.world.request_legacy_region() and main.world.region=="old_mine","鉱床へ到着してから既知の入口へ明示移行")
 roundtrip("鉱床滞在")
 var parked:=SaveGame.capture(main)
 for phase in ["parked","recall"]:
  var old:=old_format(parked); old.quarry.state=phase
  migrated=SaveGame.migrate_v2(old,main)
  check(not migrated.is_empty() and migrated.world.active and migrated.world.region=="old_mine","旧鉱床の既知位置を対応付け "+phase)
  check(SaveGame.apply(main,migrated),"旧鉱床を復元 "+phase)
  roundtrip("旧鉱床移行後 "+phase)
 # 満載の残置品は取消で保全、数量確認して放棄後に出発。
 for w in main.workers:
  w.stop_work(); w.floor_i=1; w.ai.state=CharacterAI.State.RETURN_BASE; w.set_process(false)
 main.storage.inventory.counts.clear(); main.storage.inventory.add(GameData.Item.IRON_ORE,45)
 main.quarry.keep_overflow(GameData.Item.IRON_ORE,2)
 main.set_process(false); paused=false # 採取UIは通常の非停止中入力。時間のfixtureだけ停止。
 main.quarry_ui.open(); await frames()
 await click(main.quarry_ui._discard)
 check(main.quarry_ui._confirm.visible,"地図モードの残置放棄確認を実入力で開く")
 await click(main.quarry_ui._confirm_no)
 check(main.quarry.loose.get(GameData.Item.IRON_ORE)==2 and main.quarry.state=="recall","地図モードの残置放棄取消で荷物保全")
 await click(main.quarry_ui._discard); await click(main.quarry_ui._confirm_yes)
 check(main.quarry.state=="returning" and main.quarry.loose.is_empty() and main.storage.count_of(GameData.Item.IRON_ORE)==45,"地図モードでも正規確認で残置だけ放棄し満載帰還")
 main.quarry_ui.close(); paused=true
 migrated=SaveGame.migrate_v2(old_format(SaveGame.capture(main)),main)
 check(not migrated.is_empty() and not migrated.world.active,"旧帰路は地域未確定で保持")
 check(SaveGame.apply(main,migrated) and not main.world.request_legacy_region(),"旧帰路の途中に推測割当しない")
 main.quarry.left=0; main.quarry.tick(0)
 check(main.world.request_legacy_region(),"旧帰路完了後に明示割当を要求")
 main.world.tick(0)
 check(main.world.active and main.world.region=="south_oasis","同意後だけ旧街道を村へ対応付け")
 roundtrip("旧帰路移行後")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails)); quit(1 if fails else 0)
