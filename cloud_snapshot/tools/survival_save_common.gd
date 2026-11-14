extends SceneTree
## Shared helpers for the two-process survival save/restart QA (not a test by itself).
## Reuses the stepping of test_vehicle_hunt_survival_cycle: normal director, no injected supplies,
## main._process + creatures/enemies/workers _process per step (the world clock runs outside the safe town).
const STEP := 0.2
const SAVE_PATH := "user://survival-save-test.json"
const LEDGER_PATH := "user://survival-save-ledger.json"
var main
var failures := 0
var checks := 0
var seconds := 0.0
var hunt_meat := 0
var sold_meat := 0
var purchases := 0
var earned := 0
var spent := 0
var witness_kills := 0            # deaths observed independently on the world entity ledger (not derived from total_hunted)
var witness_ids: Array = []
var meals := 0
func _check(ok: bool, message: String) -> void:
	checks += 1
	print(("ok " if ok else "FAIL ") + message)
	if not ok: failures += 1
func _added(item: int, amount: int, source: String) -> void:
	if item == GameData.Item.MEAT and source == Inventory.SOURCE_HUNT: hunt_meat += amount
func _owned(item: int) -> int:
	var n: int = main.storage.count_of(item) + main.processor.stock.count(item)
	for p in main.processor.lanes():
		for o in p.output:
			if o == item: n += 1
	for w in main.workers:
		if w.carrying == item: n += maxi(1,w.carry_n)
	return n
func _ledger() -> Dictionary:
	var hunger: Array = []
	for w in main.workers: hunger.append(w.hunger)
	return {"food":_owned(GameData.Item.FOOD),"meat":_owned(GameData.Item.MEAT),"hide":_owned(GameData.Item.HIDE),"bone":_owned(GameData.Item.BONE),
		"fuel_item":_owned(GameData.Item.FUEL),"kit":_owned(GameData.Item.REPAIR_KIT),"credits":int(main.town.credits),"fuel":main.base.fuel,
		"parts":main.base.parts.values(),"eaten":main.total_eaten,"hunted":main.total_hunted,"elapsed":main.director.elapsed,"hunger":hunger,
		"repair_reserved":main.base.repair_reserved.size(),"region":main.world.region,"phase":main.world.phase,
		"away":main.workers.map(func(x):return x.away),"exp_state":main.expedition.state}
func _fresh() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed",int(OS.get_environment("SURVIVAL_SEED")) if OS.get_environment("SURVIVAL_SEED") != "" else 104729) # default seed is the one of the existing survival test
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
func _setup_fixture() -> void:
	# Same fixture as test_vehicle_hunt_survival_cycle: speed, food refill target, crew stops gathering. No stock is injected.
	main.target_speed = 60.0
	main.refill_settings = {GameData.Item.FOOD:{"enabled":true,"target":30}}
	for w in main.workers:
		w.stop_work()
		w.set_priority(GameData.Job.GATHER,0)
	main.storage.inventory.item_added.connect(_added)
func _living() -> Dictionary:
	var living := {}
	for id in main.world.locations.get(main.world.key(),{}):
		var row: Dictionary = main.world.locations[main.world.key()][id]
		if row.get("type","") == "creature" and not row.get("spent",false): living[id] = main.world.key()
	return living
func _step() -> void:
	# Independent witness (same idea as test_vehicle_hunt_survival_cycle): a creature row of the world ledger that was
	# alive before the step and is spent after it is one death. This does not read total_hunted.
	var living := _living()
	main._process(STEP)
	for c in main.creatures_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion(): c._process(STEP)
	for e in main.enemies_root.get_children():
		if is_instance_valid(e) and not e.is_queued_for_deletion(): e._process(STEP)
	for w in main.workers:
		var hunger_before: float = w.hunger
		var eaten_before: int = main.total_eaten
		w._process(STEP)
		if main.total_eaten > eaten_before and w.hunger > hunger_before: meals += 1
	for id in living:
		var row: Dictionary = main.world.locations.get(living[id],{}).get(id,{})
		if row.get("spent",false):
			witness_kills += 1
			witness_ids.append(id)
	seconds += STEP
func _wait(duration: float, retreat_on_damage: bool = false) -> void:
	for frame in ceili(duration/STEP):
		_step()
		if frame % 100 == 0: await process_frame
		if main.game_over: return
		if retreat_on_damage and main.base.parts[GameData.Part.HULL] < 50.0: return
func _leg(destination: String, hunt: bool = true) -> bool:
	main.cancel_hunt("dodo")
	if not main.world.request(destination):
		print("BLOCK departure " + main.world.ready_reason())
		return false
	var requested := false
	for frame in 3000:
		if hunt and not requested and main.world.phase == "travel":
			requested = main.request_hunt("dodo",1)
		_step()
		if main.game_over: break
		if main.world.phase == "stopped" and main.world.region == destination:
			main.cancel_hunt("dodo")
			return true
		if frame % 100 == 0: await process_frame
	main.cancel_hunt("dodo")
	return false
func _trade(action: String, item: int, n: int = 1) -> bool:
	var q: Dictionary = main.town.quote(action,item,n)
	if not q.get("ok",false): return false
	var cr: int = main.town.credits
	if not main.town.execute(q): return false
	var delta: int = main.town.credits - cr
	if delta > 0: earned += delta
	else: spent -= delta
	if action == "buy" and item == GameData.Item.FOOD: purchases += n
	if action == "sell" and item == GameData.Item.MEAT: sold_meat += n
	return true
## Real owner/release check of the reservations (not just a range check). Returns "" when consistent.
func _reservation_issue() -> String:
	var repair_states := [CharacterAI.State.REPAIR_TAKE,CharacterAI.State.REPAIR_MOVE,CharacterAI.State.REPAIR]
	for part in main.base.repair_reserved:
		var w = main.base.repair_reserved[part]
		if not is_instance_valid(w) or not main.workers.has(w): return "repair reservation of part %s has no valid owner" % part
		if w.ai.state not in repair_states or w.ai.repair_part != part: return "repair reservation of part %s is held by a worker that is not repairing it" % part
	for w in main.workers:
		if w.ai.state in repair_states and main.base.repair_reserved.get(w.ai.repair_part) != w: return "%s is repairing without owning the reservation" % w.char_name
	var refuel_states := [CharacterAI.State.REFUEL_TAKE,CharacterAI.State.REFUEL_MOVE,CharacterAI.State.REFUEL]
	var refuelers: int = main.workers.filter(func(x): return x.ai.state in refuel_states).size()
	if bool(main.base.refuel_reserved) != (refuelers > 0): return "refuel reservation flag (%s) does not match the refuelling workers (%d)" % [main.base.refuel_reserved,refuelers]
	return ""
## Live carcass nodes (ResourceNode with item CARCASS under resources_root), independent of the vehicle hunt state.
func _carcass_nodes() -> int:
	var n := 0
	for r in main.resources_root.get_children():
		if is_instance_valid(r) and not r.is_queued_for_deletion() and r.get("item") == GameData.Item.CARCASS: n += 1
	return n
## Carcass rows of the world ledger over all locations: [unspent, spent].
func _carcass_rows() -> Array:
	var unspent := 0
	var spent := 0
	for key in main.world.locations:
		for id in main.world.locations[key]:
			var row: Dictionary = main.world.locations[key][id]
			if row.get("type","") == "resource" and row.get("data",{}).get("item",-1) == GameData.Item.CARCASS:
				if row.get("spent",false): spent += 1
				else: unspent += 1
	return [unspent,spent]
## Natural market actions only: sell real hunted byproducts, buy food and refuel if the earned credits allow it.
func _market() -> void:
	for item in [GameData.Item.HIDE,GameData.Item.BONE]:
		var available: int = main.town.available(item)
		if available > 0: _trade("sell",item,available)
	if _owned(GameData.Item.FOOD) < 12: _trade("buy",GameData.Item.FOOD)
	_trade("fuel_cash",-1)
