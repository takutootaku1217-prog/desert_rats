extends "res://tools/test_clarity_ui.gd"
func roundtrip(label: String):
 var d:=SaveGame.capture(main)
 check(SaveGame.write(main,"user://packing-test.json",true),label+" 保存 "+SaveGame.last_error)
 check(SaveGame.apply(main,SaveGame.read("user://packing-test.json")) and SaveGame.capture(main)==d,label+" 数量・設備・効果状態を復元")
 for w in main.workers: w.set_process(false) # 復元は通常どおりAIを再開するため、境界fixtureだけ再停止。
func install(id: String):
 check(main.request_build(id),"完成品の設置依頼 "+id)
 var r:Dictionary=main._next_build_recipe()
 check(r.get("build")==id and r["in"]=={FacilityDB.packed_item_of(id):1} and r.time==0.0 and r.station=="","再製作材料・作業台・製作時間なし "+id)
 check(main.storage.take_set(r["in"]),"未設置品を1個だけ取り出す "+id)
 main.claim_build(id); main.processor.receive(r); main.processor.work(0.01,func(_f):return 1.0)
 check(main.base.facility_count(id)==1,"再設置で1台に戻る "+id)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); await frames()
 main.set_process(false); main.director.enabled=false
 for w in main.workers: w.stop_work(); w.ai.state=CharacterAI.State.IDLE; w.set_process(false)
 main.storage.inventory.counts.clear()
 for id in FacilityDB.ids(): main.finish_build(id)
 var initial:=SaveGame.capture(main)
 for id in ["bed","cargo_rack","supply_cache","workbench"]:
  var item:=FacilityDB.packed_item_of(id)
  var raw:Dictionary=main.storage.inventory.counts.duplicate(true)
  var buff:float=main.room_effect("drain_cut")
  var cap:int=main.storage.max_weight()
  var token:Dictionary=main.facility_pack_request(id,0)
  check(not token.is_empty() and main.pack_facility(token),"1台を完成品として撤去 "+id)
  check(main.base.facility_count(id)==0 and main.storage.count_of(item)==1,"1台と1個の一対一交換 "+id)
  check(not main.pack_facility(token) and main.storage.count_of(item)==1,"連打で二重返却しない "+id)
  raw[item]=1
  check(main.storage.inventory.counts==raw,"原材料や副産物を別途返さない "+id)
  if id=="supply_cache": check(is_equal_approx(main.room_effect("drain_cut"),buff-0.08),"物資庫の疲労軽減が撤去中だけ消える")
  if id=="cargo_rack": check(main.storage.max_weight()==cap-60,"箱撤去で容量が60減る")
  roundtrip("撤去後 "+id)
  install(id)
  check(main.storage.count_of(item)==0,"再設置は完成品を消費 "+id)
  if id=="supply_cache": check(is_equal_approx(main.room_effect("drain_cut"),buff),"物資庫の効果が再設置で戻る")
  if id=="cargo_rack": check(main.storage.max_weight()==cap,"箱の容量が再設置で戻る")
  check(not main.request_build(id) or id in ["bed","cargo_rack"],"1台上限を維持 "+id)
  main.build_queue.clear()
 # 倉庫満載・加工予約・採取予約・確認後変化。
 main.storage.inventory.counts={GameData.Item.BONE:360}
 check(main.facility_pack_reason("cargo_rack",0).contains("容量不足"),"容量減60＋箱重量42で満載撤去を拒否")
 main.storage.inventory.counts={GameData.Item.BONE:318}
 check(main.facility_pack_reason("cargo_rack",0)=="","容量ぴったり318+42=360は許可")
 var node:=ResourceNode.new(); node.game=main; node.item=GameData.Item.BONE; node.claimed_by=main.workers[0]; node.reserved=1; main.resources_root.add_child(node)
 check(main.facility_pack_reason("cargo_rack",0).contains("予約1"),"未取得の採取予約も容量へ算入")
 node.claimed_by=null; main.resources_root.remove_child(node); node.queue_free()
 var r:=GameData.recipe_by_id("cook").duplicate(true)
 # 正味重量が増える既存料理レシピで予約境界を確認。
 if r.is_empty(): r=GameData.RECIPES[0].duplicate(true)
 main.processor.orders=[r]
 var reserve:int=main.storage.processing_reserve()
 main.storage.inventory.counts={GameData.Item.BONE:main.storage.max_weight()-60-42-main.storage.workshop_weight()-reserve+1}
 check(main.facility_pack_reason("cargo_rack",0).contains("容量不足"),"加工材料・出力増量予約を含め容量超過を拒否")
 main.processor.orders.clear(); main.storage.inventory.counts.clear()
 var snapshot:Dictionary=main.facility_pack_request("cargo_rack",0)
 main.storage.inventory.add(GameData.Item.BONE,1)
 check(not main.pack_facility(snapshot) and main.base.facility_count("cargo_rack")==1,"確認後の重量変更は撤去を拒否")
 main.storage.inventory.counts.clear()
 main.base.beds[0]=main.workers[0]
 check(main.facility_pack_reason("bed",0).contains("休息"),"使用・予約中の寝床は拒否")
 main.base.beds[0]=null
 main.workers[0].carrying=GameData.Item.WOOD
 check(main.facility_pack_reason("workbench",0).contains("運搬"),"持帰り中の撤去を拒否")
 main.workers[0].carrying=-1
 main.processor.current=GameData.recipe_by_id("bed_pack").duplicate(true)
 check(main.facility_pack_reason("workbench",0).contains("加工"),"使用中の作業台を拒否")
 main.processor.current={}
 main.processor.incoming=[GameData.recipe_by_id("bed_pack").duplicate(true)]
 check(main.facility_pack_reason("workbench",0).contains("予約"),"運搬予約に依存する作業台を拒否")
 main.processor.incoming.clear()
 main.build_queue=["bed"]
 check(main.facility_pack_reason("workbench",0).contains("建設依頼"),"依存する建設待ちを拒否")
 main.build_queue.clear(); main.craft_queue=[{"id":"bed_pack","n":1}]
 check(main.facility_pack_reason("workbench",0).contains("製作依頼"),"依存する製作待ちを拒否")
 main.craft_queue.clear()
 # 作業台なしでも全完成品を再設置できる。依存設備を連鎖削除しない。
 snapshot=main.facility_pack_request("workbench",0)
 check(main.pack_facility(snapshot) and main.base.facility_count("bed")==1 and main.base.facility_count("supply_cache")==1,"作業台撤去で他設備を連鎖削除しない")
 snapshot=main.facility_pack_request("supply_cache",0); check(main.pack_facility(snapshot),"作業台なしで物資庫を撤去")
 install("supply_cache")
 var room:String=main.base.room_slot("workshop")
 main.room_layout[room]="empty"
 check(main.build_blocked_reason("workbench").contains("必要"),"完成品でも設置先の部屋が必要")
 main.room_layout[room]="workshop"
 install("workbench")
 main.finish_build("bed"); main.base.beds[0]=main.workers[0]
 check(main.facility_pack_reason("bed",0)!="" and main.facility_pack_reason("bed",1)=="","使用中の寝床と空き寝床を枠ごとに判定")
 snapshot=main.facility_pack_request("bed",1)
 check(main.pack_facility(snapshot) and main.base.built.bed==[0] and main.base.beds[0]==main.workers[0],"選んだ空き枠だけ撤去し別枠の休息予約を保持")
 main.base.beds[0]=null
 snapshot=main.facility_pack_request("bed",0)
 roundtrip("撤去確認中に保存復元")
 check(not main.pack_facility(snapshot),"ロードで未実行の撤去確認を失効")
 # 以前のv3の作業中レシピは変更せず読める。
 var legacy:=FacilityDB.installation_recipe("bed"); legacy.station="workbench"
 check(SaveGame.recipe(legacy) and SaveGame.recipe(FacilityDB.recipe_of("workbench")) and SaveGame.recipe(FacilityDB.recipe_of("supply_cache")),"従来の設置・新規建設レシピも保存互換")
 # 実入力: 確認、Esc取消、1回だけ実行。
 main.build_ui.open(); await frames()
 await click(main.build_ui._fac_rows.workbench.pack)
 check(main.build_ui._pack_dialog.visible and main.build_ui._pack_info.text.contains("原材料は別途返しません"),"実入力で完成品返却の確認")
 await key(KEY_ESCAPE)
 check(main.has_facility("workbench") and main.storage.count_of(GameData.Item.WORKBENCH_PACK)==0,"Escで撤去せず保全")
 await click(main.build_ui._fac_rows.workbench.pack); await click(main.build_ui._pack_yes)
 check(not main.has_facility("workbench") and main.storage.count_of(GameData.Item.WORKBENCH_PACK)==1,"実入力で1台だけ撤去")
 await click(main.build_ui._pack_yes)
 check(main.storage.count_of(GameData.Item.WORKBENCH_PACK)==1,"確認ボタン連打で増殖なし")
 await click(main.build_ui._pack_no)
 await click(main.build_ui._fac_rows.workbench.build)
 check(main.build_queue.count("workbench")==1,"実入力で作業台なしの再設置を依頼")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails)); quit(1 if fails else 0)
