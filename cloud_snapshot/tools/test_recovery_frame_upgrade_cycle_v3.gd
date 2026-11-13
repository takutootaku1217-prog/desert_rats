extends SceneTree
## v3.2 real resource acquisition -> town craft/equip -> next C visit.
## Attack-only durability policy: record hull without assuming wear savings.
## Normal director on roads and FieldSurvivalClock on C; hunger/fuel/wear advance.
## Comparison Main copies are never committed to the original; actual next outing runs separately.
const Session = preload("res://bridge/route_connection_session.gd")
const LifeClock = preload("res://bridge/field_survival_clock.gd")
var actual_clocks := {}
const DT := 0.2
var main
var failures := 0
var seconds := 0.0
var c_seconds := 0.0
var harvested_wood := 0
var hunt_hide := 0
var initial_ore := 0

func _init() -> void: call_deferred("_run")
func _check(ok: bool, note: String) -> bool:
	print(("ok " if ok else "FAIL ")+note)
	if not ok: failures += 1
	return ok
func _added(item: int, n: int, source: String) -> void:
	if item == GameData.Item.WOOD and source == Inventory.SOURCE_ENVIRONMENT: harvested_wood += n
	if item == GameData.Item.HIDE and source == Inventory.SOURCE_HUNT: hunt_hide += n
func _snapshot(stage: String) -> void:
	print("LEDGER "+JSON.stringify({"stage":stage,"seconds":seconds,"c_session_seconds":c_seconds,"director":main.director.elapsed,"active_events":main.director.active.duplicate(true),"hunger":main.workers.map(func(w):return w.hunger),"fatigue":main.workers.map(func(w):return w.fatigue),"region":main.world.region,"credits":main.town.credits,"fuel":main.base.fuel,"parts":main.base.parts,"inventory":main.storage.inventory.counts,"workshop":main.processor.stock.counts,"wood_acquired":harvested_wood,"hunt_hide":hunt_hide,"workbench":main.has_facility("workbench"),"supports":main.workers.map(func(w):return w.work_support),"support":main.workers[0].work_support,"carry_limit":main.workers[0].carry_limit()}))
func _step() -> void:
	main._process(DT)
	for root_node in [main.creatures_root, main.enemies_root, main.resources_root]:
		for n in root_node.get_children():
			if is_instance_valid(n) and not n.is_queued_for_deletion() and n.has_method("_process"): n._process(DT)
	for w in main.workers: w._process(DT)
	seconds += DT
func _until(pred: Callable, limit: float) -> bool:
	for frame in ceili(limit/DT):
		_step()
		if pred.call(): return true
		if main.game_over: return false
		if frame%100 == 0: await process_frame
	return pred.call()
func _leg(dest: String, hunt: bool = false) -> bool:
	main.cancel_hunt("dodo")
	if not main.world.request(dest): return false
	var requested := false
	for frame in 2400:
		if hunt and not requested and main.world.phase == "travel": requested = main.request_hunt("dodo",1)
		_step()
		if main.world.phase == "stopped" and main.world.region == dest:
			main.cancel_hunt("dodo")
			return true
		if main.game_over: return false
		if frame%100 == 0: await process_frame
	return false
func _button(node: Node,text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _button(child,text)
		if found != null: return found
	return null
func _town_craft_entry() -> bool:
	main.town_ui.request_open()
	main.town_ui.show_building_intro("growth")
	main.town_ui.enter_building()
	var b := _button(main.town_ui,"制作・施設を開く")
	if b == null: return false
	b.pressed.emit()
	print("UI_SIGNAL town growth -> craft pressed (not OS mouse)")
	main.craft_ui.close()
	return true
func _session_until(s,pred:Callable,limit:float) -> bool:
	if not actual_clocks.has(s.get_instance_id()):
		var clock = LifeClock.new()
		if not _check(clock.setup(main,s).get("ok",false),"bind actual C survival clock"):return false
		actual_clocks[s.get_instance_id()]=clock
	for i in ceili(limit/DT):
		actual_clocks[s.get_instance_id()].tick(DT)
		c_seconds += DT
		if not s.conservation_ok(): return false
		var projection: Dictionary = s.apply_projection_to_workers(main)
		if not projection.get("ok",false): return false
		if pred.call(): return true
		if i%100 == 0: await process_frame
	return pred.call()
func _first_recovery() -> bool:
	var created: Dictionary = Session.create_from_game(main,"v3-first-recovery",{})
	if not created.get("ok",false):
		print("BLOCK "+str(created)); return false
	var s = created.session
	if not await _session_until(s,func():return int(s.depot_stock.get(GameData.Item.IRON_ORE,0))>=1,500): return false
	s.request_recall()
	if not await _session_until(s,func():return s.phase=="ready_to_exit",200): return false
	var expected: Dictionary = s.depot_stock.duplicate()
	var ore_before: int = main.storage.count_of(GameData.Item.IRON_ORE)
	var clock_before_commit: float = main.director.elapsed
	var r: Dictionary = s.commit_to_game(main)
	_check(is_equal_approx(main.director.elapsed,clock_before_commit),"first live-clock commit does not charge elapsed twice")
	if not r.get("ok",false): print("BLOCK "+str(r)); return false
	_check(main.storage.count_of(GameData.Item.IRON_ORE)==ore_before+int(expected.get(GameData.Item.IRON_ORE,0)),"C ore committed once into real storage")
	_check(s.commit_to_game(main).get("already_committed",false),"duplicate C commit does not duplicate stock")
	print("FIRST_C "+JSON.stringify({"depot":expected,"remaining":s.total_source_remaining(),"elapsed":s.elapsed}))
	return true
func _measure(s,clock,target: int) -> Dictionary:
	var pickups := 0
	var relay_pickups := 0
	var deliveries := 0
	var max_bag := 0
	var old_depot := 0
	for i in 4000:
		var before: Dictionary = s.actors.duplicate(true)
		clock.tick(DT)
		for id in s.actors:
			var a: Dictionary = s.actors[id]
			if int(a.carry_n)>int(before[id].carry_n):
				if a.role == "harvest": pickups += 1
				if a.role == "carry": relay_pickups += 1
			max_bag=maxi(max_bag,int(a.carry_n))
		var depot: int = s._stock_total(s.depot_stock)
		if depot>old_depot: deliveries+=1
		old_depot=depot
		if not s.conservation_ok(): return {"ok":false,"reason":"conservation"}
		if depot>=target:return {"ok":true,"seconds":s.elapsed,"depot":s.depot_stock.duplicate(),"deposited":depot,"harvest_pickups":pickups,"relay_pickups":relay_pickups,"delivery_events":deliveries,"max_bag":max_bag,"harvest_limit":s.actors["worker:0"].carry_limit,"carry_limit":s.actors["worker:1"].carry_limit,"hunger":clock.game.workers.map(func(w):return w.hunger),"fatigue":clock.game.workers.map(func(w):return w.fatigue),"director":clock.game.director.elapsed,"active_events":clock.game.director.active.duplicate(true),"fuel":clock.game.base.fuel,"hull":clock.game.base.parts[GameData.Part.HULL]}
	return {"ok":false,"reason":"timeout","summary":s.state_summary()}
func _cycle() -> bool:
	SaveGame.disabled = true
	main=load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot=true
	main.set_meta("diagnostic_seed",104729)
	root.add_child(main)
	await process_frame
	main.process_mode=Node.PROCESS_MODE_DISABLED
	main.target_speed=60.0
	main.refill_settings={}
	main.storage.inventory.item_added.connect(_added)
	initial_ore=main.storage.count_of(GameData.Item.IRON_ORE)
	_snapshot("initial")
	if not _check(await _leg("b_forest",true),"A -> B with explicit vehicle hunt"):return false
	for w in main.workers:
		w.set_priority(GameData.Job.GATHER,5)
		main.set_gather_focus(w,GameData.Item.WOOD)
	main.set_procurement(GameData.Item.WOOD,7)
	if not _check(await _until(func():return main.storage.count_of(GameData.Item.WOOD)>=7,350),"B normal gathering delivers wood7"):return false
	_check(harvested_wood>=7 and hunt_hide>=1,"wood and hide have actual acquisition provenance")
	main.set_procurement(GameData.Item.WOOD,0)
	for w in main.workers: w.set_priority(GameData.Job.GATHER,0)
	if not _check(await _leg("c_quarry",true),"B -> C with second explicit hide hunt"):return false
	if not _check(await _first_recovery(),"first C mineral collection/transport/return"):return false
	_check(hunt_hide==2,"two actual vehicle hunts supplied frame hides")
	_snapshot("first_C_committed")
	if not _check(await _leg("b_forest") and await _leg("a_start"),"return to town"):return false
	if not _check(_town_craft_entry(),"town craft UI signal entry"):return false
	var craft_before := {"wood":main.storage.count_of(GameData.Item.WOOD),"hide":main.storage.count_of(GameData.Item.HIDE),"ore":main.storage.count_of(GameData.Item.IRON_ORE)}
	if not main.has_facility("workbench"):
		if not _check(main.request_build("workbench"),"request workbench using real wood"):return false
		if not _check(await _until(func():return main.has_facility("workbench"),300),"workbench completed"):return false
	if not _check(main.request_order("smelt",2)==2,"order C ore smelting"):return false
	if not _check(await _until(func():return main.storage.count_of(GameData.Item.IRON)>=2,300),"C ore becomes real iron"):return false
	if not _check(main.request_order("haul_frame",2)==2,"order two frames with wood4/hide2/iron2"):return false
	if not _check(await _until(func():return main.storage.count_of(GameData.Item.HAUL_FRAME)>=2,300),"frame crafted and stored"):return false
	_check(main.storage.count_of(GameData.Item.WOOD)==int(craft_before.wood)-7,"workbench3 plus frames4 wood actually consumed")
	_check(main.storage.count_of(GameData.Item.HIDE)==int(craft_before.hide)-2,"two actual hunted hides consumed")
	_check(main.storage.count_of(GameData.Item.IRON_ORE)==int(craft_before.ore)-2 and main.storage.count_of(GameData.Item.IRON)==0,"two recovered ores smelted and both iron consumed")
	_snapshot("frame_crafted")
	for w in [main.workers[0],main.workers[1]]:
		main.detail.open_worker(w)
		var equipment_tab := _button(main.detail,"装備・荷物")
		if equipment_tab == null:return false
		equipment_tab.pressed.emit()
		var equip := _button(main.detail,"背負いフレームを装備")
		if not _check(equip!=null,"existing crew equip button exists"):return false
		equip.pressed.emit()
		main.detail.close()
		if not _check(w.carry_limit()==5,"normal equipment button applies capacity3 -> 5"):return false
	if not _check(await _leg("b_forest") and await _leg("c_quarry"),"upgrade -> real next C visit"):return false
	_snapshot("second_C_entry")
	# Save snapshot is the shared immutable pre-comparison state. Each branch has
	# its own Main, inventory, director and life token, not a restored live session.
	var departure: Dictionary = SaveGame.capture(main)
	var original_inventory: Dictionary = main.storage.inventory.counts.duplicate()
	var actual: Dictionary = Session.create_from_game(main,"v3-second-actual",{})
	if not actual.get("ok",false):return false
	var all_remaining: int = actual.session.total_source_remaining()
	for target in [6,10,all_remaining]:
		var results := {}
		for name in ["baseline","harvest_only","both"]:
			var branch = load("res://scenes/main.tscn").instantiate()
			branch.first_region_a_pilot=true
			branch.set_meta("diagnostic_seed",271828)
			root.add_child(branch)
			await process_frame
			branch.process_mode=Node.PROCESS_MODE_DISABLED
			if not _check(SaveGame.apply(branch,departure.duplicate(true)),"restore independent branch Main"):branch.free();return false
			branch.process_mode=Node.PROCESS_MODE_DISABLED
			for w in [branch.workers[0],branch.workers[1]]:
				if not branch.unequip_work_support(w):branch.free();return false
			if name in ["harvest_only","both"]:
				if not branch.equip_work_support(branch.workers[0]):branch.free();return false
			if name=="both":
				if not branch.equip_work_support(branch.workers[1]):branch.free();return false
			var created: Dictionary=Session.create_from_game(branch,"v3-"+name+"-"+str(target),{})
			if not created.get("ok",false):branch.free();return false
			_check(created.session.resources==actual.session.resources,"branch finite resources match actual next visit")
			var clock=LifeClock.new()
			if not clock.setup(branch,created.session).get("ok",false):branch.free();return false
			seed(271828) # same future event RNG start; save format does not serialize global RNG
			results[name]=_measure(created.session,clock,target)
			branch.free()
			if not results[name].get("ok",false):return false
		print("COMPARISON "+JSON.stringify({"target_at_least":target,"all_remaining_primary":target==all_remaining,"results":results,"method":"independent Main copies from identical SaveGame.capture; normal 3 roles; live hunger/director/fuel; common future RNG seed271828; batch overshoot shown; no comparison commits"}))
	_check(main.storage.inventory.counts==original_inventory,"all comparison branches leave real inventory unchanged")
	# Execute the selected upgraded outing afresh on the real Main.
	var actual_clock=LifeClock.new()
	if not actual_clock.setup(main,actual.session).get("ok",false):return false
	actual_clocks[actual.session.get_instance_id()]=actual_clock
	seed(271828)
	var real_result: Dictionary=_measure(actual.session,actual_clock,all_remaining)
	if not real_result.get("ok",false):return false
	print("ACTUAL_SECOND_MEASURE "+JSON.stringify(real_result))
	c_seconds += actual.session.elapsed
	var ucopy: Dictionary=actual
	ucopy.session.request_recall()
	if not await _session_until(ucopy.session,func():return ucopy.session.phase=="ready_to_exit",200): return false
	var actual_depot: Dictionary = ucopy.session.depot_stock.duplicate()
	var ore_before: int = main.storage.count_of(GameData.Item.IRON_ORE)
	var clock_before_commit: float = main.director.elapsed
	var actual_commit: Dictionary = ucopy.session.commit_to_game(main)
	_check(is_equal_approx(main.director.elapsed,clock_before_commit),"second live-clock commit does not charge elapsed twice")
	if not _check(bool(actual_commit.get("ok",false)),"upgraded real second outing commits successfully"):return false
	_check(main.storage.count_of(GameData.Item.IRON_ORE)==ore_before+int(actual_depot.get(GameData.Item.IRON_ORE,0)),"only upgraded branch deposits actual second recovered ore")
	print("SECOND_C "+JSON.stringify({"depot":actual_depot,"remaining":ucopy.session.total_source_remaining(),"elapsed":ucopy.session.elapsed}))
	return true
func _run() -> void:
	var ok: bool = await _cycle()
	_check(ok,"recovery -> town craft/equip -> next C comparison")
	if main != null:
		_snapshot("end")
		main.free()
	print("SCOPE headless API/Button.pressed signals, not OS mouse or Windows; normal road and C survival director/hunger/fuel; comparisons in independent Main copies; real upgraded branch returned and committed")
	quit(1 if failures else 0)
