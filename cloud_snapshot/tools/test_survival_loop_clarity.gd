extends SceneTree
## Contract for the changeable survival-loop clarity prototype.
## This uses a real Main scene and world ledger, but stops the director so no
## unrelated travel/event timing influences the assertions.

const STEP := 0.2
const NEW_FAUNA := ["dodo", "sand_paca", "mossback"]

var main
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _fresh() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 311031)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false


func _first_region_fauna() -> Array:
	var out: Array = []
	for row in main.world.locations.get("region:a_start", {}).values():
		if row.get("type", "") == "creature":
			out.append(String(row.get("data", {}).get("species", "")))
	return out


func _run() -> void:
	await _fresh()
	for species in NEW_FAUNA:
		_check(GameData.CREATURES.has(species), "%s is prototype wildlife data" % species)
	var fauna := _first_region_fauna()
	var local_hide_sources: Array = CraftUI.local_hunt_sources(main, GameData.creature_sources_for(GameData.Item.HIDE))
	_check(local_hide_sources == NEW_FAUNA, "craft hunt requests only list wildlife in the current first-region ledger")
	_check(not "hare" in local_hide_sources and not "lizard" in local_hide_sources and not "hump" in local_hide_sources, "craft hunt requests exclude absent legacy species")
	for species in NEW_FAUNA:
		_check(species in fauna, "First Region includes %s in its normal wildlife roster" % species)
	_check(GameData.CREATURES.get("dodo", {}).get("drops", {}).has(GameData.Item.BONE), "initial wildlife makes the existing bed bone reachable")
	var ledger: Dictionary = main.world.locations.get("region:a_start", {})
	var ledger_size: int = ledger.size()
	var respawn_id := ""
	for id in ledger:
		if ledger[id].get("type", "") == "creature" and ledger[id].get("data", {}).get("species", "") == "dodo":
			respawn_id = String(id)
			break
	_check(not respawn_id.is_empty(), "prototype wildlife keeps a stable world-ledger identity")
	if not respawn_id.is_empty():
		var original_elapsed: float = main.director.elapsed
		var respawn_row: Dictionary = ledger[respawn_id]
		respawn_row["spent"] = true
		respawn_row["respawn_at"] = original_elapsed + 5.0
		ledger[respawn_id] = respawn_row
		for w in main.workers:
			w.position = Vector2(-1000, -1000)
		main.world._return_fauna({})
		_check(ledger[respawn_id].spent, "wildlife does not respawn before its scheduled delay")
		main.director.elapsed = original_elapsed + 5.1
		main.world._return_fauna({})
		_check(not ledger[respawn_id].spent and not ledger[respawn_id].has("respawn_at"), "wildlife restores its original ledger row after delay")
		_check(ledger.size() == ledger_size, "wildlife recovery does not allocate a duplicate ledger row")
	_check(not main.hunt_allowed("hare"), "existing neutral wildlife is not hunted before an explicit request")
	main.set_procurement(GameData.Item.MEAT, 2)
	_check(not main.hunt_allowed("hare"), "a generic meat collection goal never enables hunting")
	var worker = main.workers[0]
	_check(main.has_method("request_hunt"), "Main exposes an explicit species hunt request API")
	if main.has_method("request_hunt"):
		var dodo := Creature.new()
		dodo.setup(main, "dodo")
		dodo.position = Vector2(420, 680)
		main.creatures_root.add_child(dodo)
		_check(main.request_hunt("dodo", 1), "explicit dodo request is accepted")
		_check(main.hunt_allowed("dodo"), "explicit dodo request enables only that hunt")
		dodo.hunted_by = worker
		worker.ai.prey = dodo
		main.cancel_hunt("dodo")
		_check(dodo.hunted_by == null, "cancelling an explicit hunt releases the reserved creature immediately")
		_check(not worker.ai._prey_valid(), "cancelling an explicit hunt stops an in-progress hunter before damage")
		_check(main.request_hunt("dodo", 1), "a cancelled species can receive a new explicit request")
		var before_hunts: int = main.total_hunted
		main.on_creature_killed(dodo)
		_check(main.total_hunted == before_hunts + 1, "one killed creature produces one normal hunt record")
		_check(not main.hunt_allowed("dodo"), "completed one-kill request stops the hunt")
		_check(main.last_carcass != null and main.last_carcass.species == "dodo", "normal kill produces a dodo carcass rather than direct resource injection")
	_check(worker.get("gather_focus_item") == GameData.Item.WOOD or worker.get("gather_focus_item") == -1, "worker exposes an optional material focus field")
	_check(main.has_method("set_gather_focus"), "Main exposes a worker material-focus API")
	if main.has_method("set_gather_focus"):
		main.set_gather_focus(worker, GameData.Item.STONE)
		_check(worker.get("gather_focus_item") == GameData.Item.STONE, "worker focus can prefer stone without changing global policy")
		_check(main.set_gather_focus(worker, -1) and worker.gather_focus_item == -1, "worker focus can return to the global setting")
		main.set_gather_focus(worker, GameData.Item.STONE)
		var snapshot: Dictionary = SaveGame.capture(main)
		_check(snapshot["crew"][0]["worker"].get("gather_focus_item", -1) == GameData.Item.STONE, "worker focus is captured for save/load")
		_check(SaveGame.validate(snapshot, main), "new hunt and worker-focus state keeps a save valid")
		worker.gather_focus_item = -1
		_check(SaveGame.apply(main, snapshot), "new hunt and worker-focus state applies to the live scene")
		await process_frame
		worker = main.workers[0]
		_check(worker.gather_focus_item == GameData.Item.STONE, "worker material focus survives save/load")
	var map_api = load("res://data/world_map.gd")
	_check(map_api.has_method("known_regions_for_item"), "world map exposes a pure known-source lookup")
	if map_api.has_method("known_regions_for_item"):
		var wood_regions: Array = map_api.call("known_regions_for_item", main.world.map_profile, GameData.Item.WOOD)
		var ore_regions: Array = map_api.call("known_regions_for_item", main.world.map_profile, GameData.Item.IRON_ORE)
		_check("a_start" in wood_regions and "c_quarry" in ore_regions, "map source lookup derives locations from existing point data")
		var desert_wood: Array = map_api.call("known_regions_for_item", WorldMapDB.DESERT, GameData.Item.WOOD)
		var all_public := true
		for region_id in desert_wood:
			all_public = all_public and bool(map_api.call("public_region", String(region_id), WorldMapDB.DESERT))
		_check(all_public, "source lookup does not list unrevealed desert regions")
		_check(map_api.call("fauna_of", "old_mine", WorldMapDB.DESERT).is_empty(), "regions without a wildlife roster do not inherit a fictional hare")
	var point = null
	for resource in main.resources_root.get_children():
		if resource is GatherPoint:
			point = resource
			break
	if point == null:
		# Save/load may project the ledger off-screen.  Use the same concrete
		# GatherPoint class as a focused fixture rather than a mock dictionary.
		point = GatherPoint.new()
		point.setup(main, "tree")
		point.position = Vector2(760, 650)
		main.resources_root.add_child(point)
	_check(point != null, "clarity test has a real gather point")
	if point != null:
		point.claimed_by = null
		main.procurement_goals.erase(point.item)
		var old_priority: int = int(main.gather_policy.get(point.item, 3))
		main.gather_policy[point.item] = 0
		_check(main.gather_point_hint(point) == "全体の採取優先が0", "visible gather hint reports the same zero-priority block as AI")
		main.gather_policy[point.item] = old_priority
	var rock := GatherPoint.new()
	rock.setup(main, "rock")
	rock.position = worker.position + Vector2(24, 0)
	main.resources_root.add_child(rock)
	for other in main.workers:
		other.priorities[GameData.Job.GATHER] = 0
		other.ai.return_request = false
	worker.priorities[GameData.Job.GATHER] = 1
	worker.tools.erase(GatherDB.slot_of_point("rock"))
	main.scroll_speed = 0.0
	_check(main.gather_point_hint(rock) == GatherDB.requirement("rock"), "a rock without a qualified worker shows its missing-tool requirement")
	worker.tools[GatherDB.slot_of_point("rock")] = GameData.Item.WOOD_PICK
	var capable_rock_hint: String = main.gather_point_hint(rock)
	_check(capable_rock_hint.begins_with("採取可"), "a qualified worker makes the rock hint affirm that gathering is possible")
	_check(capable_rock_hint != GatherDB.requirement("rock"), "a gatherable rock never repeats its missing-tool requirement")
	main.set_procurement(rock.item, 2)
	var global_rock_hint: String = main.gather_point_hint(rock)
	_check(global_rock_hint.begins_with("採取可") and global_rock_hint.contains("全体"), "a qualified global request still affirms gatherability before showing its target")
	main.set_procurement(rock.item, 0)
	_check(GatherDB.requirement("tree") != "", "tree requirement has a compact source-of-truth label")
	_check(GatherDB.requirement("rock") != "", "rock requirement has a compact source-of-truth label")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	SaveGame.disabled = false
	quit(1 if failures > 0 else 0)
