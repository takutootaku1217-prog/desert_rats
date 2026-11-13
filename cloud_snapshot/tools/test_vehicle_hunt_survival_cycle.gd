extends SceneTree
## v3.2 three continuous laps, normal director, no stock/money/kill injection.
## Repairs are conditional on real existing damage, never manufactured for a pass.
## System/API input witness, NOT GUI/Windows validation. No C quarter-view hunt.
const STEP := 0.2
var main
var failures := 0
var seconds := 0.0
var hunt_meat := 0
var purchases := 0
var sold_meat := 0
var earned := 0
var spent := 0
var repair_spent := 0
var fuel_spent := 0
var meals_observed := 0
var vehicle_cargo_seen := false
var foot_work_seen := false
var kill_rows: Array = []
var ledger: Array = []
var initial_food := 0
var initial_meat := 0
var previous_kills := {}

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print(("ok " if ok else "FAIL ") + message)
	if not ok: failures += 1

func _added(item: int, amount: int, source: String) -> void:
	if item == GameData.Item.MEAT and source == Inventory.SOURCE_HUNT:
		hunt_meat += amount
		print("HUNT_MEAT " + JSON.stringify({"time":seconds,"amount":amount,"road":main.world.road,"phase":main.world.phase}))

func _snapshot(stage: String) -> void:
	var hunger: Array = []
	for w in main.workers: hunger.append(snappedf(w.hunger,0.01))
	var row := {"stage":stage,"seconds":seconds,"director_seconds":main.director.elapsed,"region":main.world.region,"phase":main.world.phase,"fuel":main.base.fuel,"parts":main.base.parts.duplicate(),"game_over":main.game_over,"credits":main.town.credits,"hunt_meat":hunt_meat,"hunted":main.total_hunted,"meat":main.storage.count_of(GameData.Item.MEAT),"food":main.storage.count_of(GameData.Item.FOOD),"eaten":main.total_eaten,"hunger":hunger,"events":main.director.log.duplicate(true),"event_stats":main.director.stats.duplicate(true),"total_repairs":main.base.total_repair,"earned":earned,"spent":spent,"repair_spent":repair_spent,"fuel_spent":fuel_spent,"vehicle":main.vehicle_hunt.status()}
	ledger.append(row)
	print("LEDGER " + JSON.stringify(row))

func _step() -> void:
	var living := {}
	for id in main.world.locations.get(main.world.key(),{}):
		var row: Dictionary = main.world.locations[main.world.key()][id]
		if row.get("type","") == "creature" and not row.get("spent",false):
			living[id] = {"species":row.data.species,"road":main.world.road,"time":main.director.elapsed}
	var old_hunted: int = main.total_hunted
	var travel_before: bool = main.world.phase == "travel"
	main._process(STEP)
	for c in main.creatures_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion(): c._process(STEP)
	for e in main.enemies_root.get_children():
		if is_instance_valid(e) and not e.is_queued_for_deletion(): e._process(STEP)
	for w in main.workers:
		var hunger_before: float = w.hunger
		var eaten_before: int = main.total_eaten
		w._process(STEP)
		if main.total_eaten > eaten_before and w.hunger > hunger_before:
			meals_observed += 1
			print("MEAL " + JSON.stringify({"seconds":seconds,"region":main.world.region,"hunger_before":hunger_before,"hunger_after":w.hunger,"eaten":main.total_eaten}))
		if main.world.phase == "travel" and w.ai.state in [CharacterAI.State.HUNT_MOVE,CharacterAI.State.HUNT_ATTACK,CharacterAI.State.MOVE_TO_RESOURCE,CharacterAI.State.GATHER]: foot_work_seen = true
	vehicle_cargo_seen = vehicle_cargo_seen or not main.vehicle_hunt.cargo.is_empty()
	if main.total_hunted > old_hunted:
		_check(travel_before,"kill occurred during travel")
		for id in living:
			var row: Dictionary = main.world.locations.get(main.world.key(),{}).get(id,{})
			if not row.get("spent",false): continue
			var k: Dictionary = living[id].duplicate()
			k["id"] = id
			k["respawn_at"] = row.get("respawn_at",-1)
			if previous_kills.has(id): _check(float(k.time)-float(previous_kills[id]) >= GameData.creature_respawn_seconds(k.species),"same entity respected respawn delay")
			previous_kills[id] = k.time
			kill_rows.append(k)
			print("KILL " + JSON.stringify(k))
	seconds += STEP

func _wait(duration: float, retreat_on_damage: bool = false) -> void:
	for frame in ceili(duration/STEP):
		_step()
		if frame % 100 == 0: await process_frame
		if main.game_over: return
		if retreat_on_damage and main.base.parts[GameData.Part.HULL] < 50.0:
			print("DECISION leave unsafe site: hull below 50")
			return

func _leg(destination: String, hunt: bool = true) -> bool:
	main.cancel_hunt("dodo")
	if not main.world.request(destination):
		print("BLOCK departure " + main.world.ready_reason())
		return false
	var requested := false
	var before: int = main.total_hunted
	for frame in 3000:
		if hunt and not requested and main.world.phase == "travel":
			requested = main.request_hunt("dodo",1)
		_step()
		if main.game_over: break
		if main.world.phase == "stopped" and main.world.region == destination:
			main.cancel_hunt("dodo")
			if not hunt: _check(main.total_hunted == before,"no request means no neutral hunt")
			_snapshot("arrive_" + destination)
			return true
		if frame % 100 == 0: await process_frame
	main.cancel_hunt("dodo")
	_snapshot("leg_blocked_" + destination)
	return false

func _trade(action: String,item: int,n: int = 1) -> bool:
	var q: Dictionary = main.town.quote(action,item,n)
	if not q.get("ok",false):
		print("TRADE_BLOCK " + JSON.stringify(q))
		return false
	var cr: int = main.town.credits
	if not main.town.execute(q): return false
	var delta: int = main.town.credits-cr
	if delta > 0: earned += delta
	else: spent -= delta
	if action == "repair_cash": repair_spent -= delta
	if action == "fuel_cash": fuel_spent -= delta
	if action == "buy" and item == GameData.Item.FOOD: purchases += n
	if action == "sell" and item == GameData.Item.MEAT: sold_meat += n
	print("TRADE " + JSON.stringify({"action":action,"item":item,"n":n,"credits_before":cr,"credits_after":main.town.credits,"fuel":main.base.fuel}))
	return true

func _market() -> bool:
	for item in [GameData.Item.HIDE,GameData.Item.BONE]:
		var available: int = main.town.available(item)
		if available > 0 and not _trade("sell",item,available): return false
	# Revenue is from actual hunted byproducts, never seeded currency.
	if purchases == 0 and not _trade("buy",GameData.Item.FOOD): return false
	# Keep scarce money for repairs once food stocks are healthy.
	var fuel_before: float = main.base.fuel
	if not _trade("fuel_cash",-1): return false
	_check(main.base.fuel > fuel_before,"sale revenue funds actual town refuelling")
	if main.base.parts[GameData.Part.HULL] < 90.0:
		if not _trade("repair_cash",GameData.Part.HULL): return false
	return true

func _owned(item: int) -> int:
	var n: int = main.storage.count_of(item) + main.processor.stock.count(item)
	for p in main.processor.lanes():
		for o in p.output:
			if o == item: n += 1
	for w in main.workers:
		if w.carrying == item: n += maxi(1,w.carry_n)
	return n

func _run() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed",104729)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	if main.get("vehicle_hunt") == null:
		_check(false,"vehicle_hunt API not implemented yet (expected RED)")
		main.free()
		quit(1)
		return
	main.target_speed = 60.0
	main.refill_settings = {GameData.Item.FOOD:{"enabled":true,"target":30}}
	for w in main.workers:
		w.stop_work()
		w.set_priority(GameData.Job.GATHER,0)
	main.storage.inventory.item_added.connect(_added)
	initial_food = _owned(GameData.Item.FOOD)
	initial_meat = _owned(GameData.Item.MEAT)
	_check(main.director.enabled,"normal director enabled")
	_snapshot("normal_start")
	_check(await _leg("b_forest",false),"unrequested outbound control")
	_check(await _leg("a_start",false),"unrequested reverse control")
	var completed := 0
	for lap in 3:
		var lap_before := {"credits":main.town.credits,"parts":main.base.parts.duplicate(),"earned":earned,"spent":spent,"repair_spent":repair_spent,"fuel_spent":fuel_spent,"hunted":main.total_hunted,"eaten":main.total_eaten}
		var ok := await _leg("b_forest")
		if not ok: break
		# Normal unsafe-site time permits cooking, events, respawn and natural hunger.
		await _wait(400.0,true)
		if main.game_over: break
		for destination in ["c_quarry","d_yard","a_start"]:
			if not await _leg(destination):
				ok = false
				break
		if not ok: break
		_snapshot("lap_%d_before_market" % (lap+1))
		var before_repair: Dictionary = main.base.parts.duplicate()
		if not _market(): break
		completed += 1
		print("LAP_BALANCE " + JSON.stringify({"lap":completed,"before":lap_before,"parts_before_repair":before_repair,"parts_after_repair":main.base.parts.duplicate(),"income":earned-int(lap_before.earned),"cost":spent-int(lap_before.spent),"repair_cost":repair_spent-int(lap_before.repair_spent),"fuel_cost":fuel_spent-int(lap_before.fuel_spent),"net":main.town.credits-int(lap_before.credits),"hunted":main.total_hunted-int(lap_before.hunted),"eaten":main.total_eaten-int(lap_before.eaten)}))
		_snapshot("lap_%d_complete" % completed)
	if completed == 3 and seconds < 1250.0:
		print("DECISION wait for normal meal in safe town; director world clock pauses here")
		await _wait(1250.0-seconds)
	_check(completed == 3,"three consecutive laps without reset")
	if completed == 3:
		if main.base.parts[GameData.Part.DRIVE] < 90.0:
			_check(_trade("repair_cash",GameData.Part.DRIVE),"repair actual damaged running gear before departure")
		else:
			print("DECISION running gear undamaged: no repair purchase or invented damage")
		_snapshot("before_next_departure")
		_check(await _leg("b_forest"),"next departure after three ordinary laps")
	_check(seconds >= 1200.0,"at least 1200 seconds normal simulation")
	_check(main.director.enabled,"director was not disabled")
	if int(main.director.stats.get("attack",0))==0:
		_check(main.base.parts.values().all(func(v):return is_equal_approx(float(v),100.0)),"no attack: travel/idle/processing/weather caused no durability loss")
		_check(repair_spent==0 and main.base.total_repair==0,"no attack: no repair expense or repair action manufactured")
	_check(meals_observed > 0,"natural hunger meal with hunger restoration")
	_check(vehicle_cargo_seen and hunt_meat > 0,"actual vehicle cargo becomes hunt-source meat")
	_check(not foot_work_seen,"no pedestrian hunting or gathering while driving")
	_check(kill_rows.size() == main.total_hunted,"every kill has a stable world-entity witness")
	_check(main.town.credits == earned-spent,"currency ledger balances")
	var unprocessed: int = _owned(GameData.Item.MEAT) + int(main.processor.committed_inputs().get(GameData.Item.MEAT,0))
	var cooked: int = initial_meat+hunt_meat-unprocessed-sold_meat
	var food_owned := _owned(GameData.Item.FOOD)
	_check(food_owned+main.total_eaten == initial_food+2*cooked+purchases,"food balance includes all locations, cooking, purchase and meals")
	_snapshot("final")
	print("BALANCE " + JSON.stringify({"initial_food":initial_food,"hunt_meat":hunt_meat,"unprocessed_meat":unprocessed,"cooked_meat":cooked,"purchased_food":purchases,"sold_meat":sold_meat,"food_owned":food_owned,"eaten":main.total_eaten,"earned":earned,"spent":spent,"kills":kill_rows}))
	print("SCOPE deterministic ordinary-director API simulation, not GUI/Windows; no C quarter-view hunting or infinite sustainability claim")
	main.free()
	SaveGame.disabled = false
	quit(1 if failures else 0)
