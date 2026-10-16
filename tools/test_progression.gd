extends SceneTree
## 既定出来事・初期物資・設備なし。段階ごとのユーザー要求APIだけで進める。
## 在庫/容量/優先度/耐久/イベントを成功状態へ書き換えない。seedのみ初期固定。
var main
var fails := 0
var stages: Array[String] = []
var phase := "開始"
func fail(message: String):
	fails += 1
	print("FAIL ",message)
func wait_for(label: String, condition: Callable, seconds: float) -> bool:
	phase=label
	var end: float=main.director.elapsed+seconds
	while not condition.call() and not main.game_over and main.director.elapsed<end:
		await process_frame
		if main.storage.current_weight()+main.storage.processing_reserve()>main.storage.max_weight():
			fail("保有重量＋加工増量予約が容量超過")
			return false
	if not condition.call():
		fail("未達: "+label)
		return false
	stages.append(label)
	print("STAGE %.1fs %s" % [main.director.elapsed,label])
	return true
func finish():
	Engine.time_scale=1
	paused=false
	print("PROGRESSION ",JSON.stringify({"phase":phase,"stages":stages,"seconds":main.director.elapsed,"game_over":main.game_over,"events":main.director.stats,"inventory":main.storage.inventory.counts,"weight":main.storage.current_weight(),"capacity":main.storage.max_weight(),"build_queue":main.build_queue,"quarry":main.quarry.state,"report":main.quarry.last_report}))
	print("== 結果: %s ==" % ("すべて成功" if fails==0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
func _initialize():
	FacilityDB.start_all=false
	main=load("res://scenes/main.tscn").instantiate()
	main.set_meta("diagnostic_seed",501)
	root.add_child(main)
	if not main.is_node_ready(): await main.ready
	Engine.time_scale=12
	print("操作方針: Bで作業台→寝床/箱を製作設置、Gで近場を採取し帰還。残置は数量確認して放棄。Fで槍を製作、Cで本人へ装備、Bで2個目の箱。出来事・各優先度は既定。")
	if not main.director.enabled: fail("出来事が無効"); finish(); return
	if not main.request_build("workbench"): fail("作業台の依頼拒否"); finish(); return
	if not await wait_for("作業台完成",func():return main.has_facility("workbench"),600): finish(); return
	if not main.request_build("bed") or not main.request_build("cargo_rack"): fail("寝床/箱の依頼拒否");finish();return
	if not await wait_for("寝床1台と箱1個を設置",func():return main.base.facility_count("bed")>=1 and main.base.facility_count("cargo_rack")>=1,900): finish();return
	if not main.quarry.select(): fail("鉱床選択拒否");finish();return
	if not await wait_for("鉱床へ到着",func():return main.quarry.state=="parked",300): finish();return
	if not await wait_for("近場12単位を採取",func():return main.quarry.group_left("近場")==0,600): finish();return
	if not main.quarry.request_departure():fail("帰還拒否");finish();return
	if not await wait_for("全員帰還",func():return main.quarry.crew_ready_to_leave(),300): finish();return
	if main.quarry.loose.is_empty():
		if not main.quarry.leave():fail("出発拒否");finish();return
	else:
		var shown: Dictionary=main.quarry.loose.duplicate()
		print("USER CONFIRM DISCARD ",JSON.stringify(shown))
		if not main.quarry.discard_and_leave(shown):fail("確認後の出発拒否");finish();return
	if main.quarry.last_report["generated"].get(GameData.Item.IRON_ORE,0)!=12:fail("対象鉱床の生成数が近場残量12と不一致");finish();return
	if not await wait_for("街道へ復帰",func():return main.quarry.state=="road",300):finish();return
	for item in [GameData.Item.WOOD,GameData.Item.IRON]:
		if not await wait_for("槍の材料を確保: "+GameData.ITEM_NAMES[item],func():return main.storage.count_of(item)>0,600):finish();return
		if main.request_transfer(item,1,"to_workshop")!=1:fail("素材運搬拒否");finish();return
		if not await wait_for("作業場へ材料運搬: "+GameData.ITEM_NAMES[item],func():return main.processor.stock.count(item)>0,180):finish();return
	if main.request_craft("simple_spear",1)!=1:fail("槍製作拒否");finish();return
	if not await wait_for("槍を製作し倉庫へ収納",func():return main.storage.count_of(GameData.Item.SIMPLE_SPEAR)>0,300):finish();return
	if not await wait_for("本人が装備可能",func():return main.weapon_change_reason(main.workers[0],true)=="",180):finish();return
	if not main.equip_weapon(main.workers[0]):fail("本人へ槍装備拒否");finish();return
	stages.append("槍を本人に装備")
	if not main.request_build("cargo_rack"):fail("次の箱依頼拒否");finish();return
	if not await wait_for("帰還後の次強化: 箱2個目を製作設置",func():return main.base.facility_count("cargo_rack")==2,900):finish();return
	finish()
