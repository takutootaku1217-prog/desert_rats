class_name SaveGame
extends RefCounted
## 現行モデル専用。ObjectをデコードしないVariant payload + SHA256付きJSON。
## UIの停止中、またはフレーム内の同期呼出しでsnapshot。自動保存はしない。
const VERSION := 3
const PATH := "user://save.json"
## An immutable retry snapshot, intentionally separate from the player's manual
## progress slot and its backup.
const CHECKPOINT_PATH := "user://predeparture-checkpoint.json"
const FIRST_REGION_SAVE_PATH := "user://first-region-a-pilot-save.json"
const FIRST_REGION_CHECKPOINT_PATH := "user://first-region-a-pilot-checkpoint.json"
const CHECKPOINT_CREDIT_RATIO := 0.10
static var last_error := ""
static var disabled := false
const FieldSnapshot = preload("res://bridge/c_field_snapshot.gd")
const MAIN := ["target_speed", "scroll_speed", "room_layout", "total_rooms_built", "recipe_priority", "gather_policy", "hunt_policy", "hunt_requests", "blueprints", "total_gathered", "total_hunted", "total_eaten", "tool_auto", "_tool_clock", "build_queue", "total_built", "total_wasted", "_waste_note_at", "_spawn_dist", "_creature_dist", "wave", "kills", "_wave_timer", "transfer_queue", "craft_queue", "total_transferred", "total_crafted_by_hand", "_feed_clock"]
const WORKER := ["char_name", "palette", "priorities", "carrying", "carcass_cargo", "carrying_species", "carry_source", "carry_n", "carry_bonus", "weapon", "work_support", "tools", "gather_focus_item", "speed", "target", "position", "slot_offset", "hp", "hunger", "fatigue", "stress", "calm", "mental", "down", "floor_i", "facing", "level", "gender", "ranks", "skills", "dept", "away", "bed_index", "_climb_dest", "_climb_floor", "_climb_kind"]
const AI := ["state", "timer", "haul_item", "haul_recipe", "repair_part", "gather_ev", "bag_limit", "bag_frac", "eat_wait", "xfer_item", "xfer_dir", "current_job", "life_request", "process_slot", "safe_after", "retreating", "danger_hold", "manual_attack", "return_request", "manual_job", "low_hp_retreat"]
const BASE := ["built", "max_hp", "hp", "fuel", "parts", "rear_engine_damage", "total_refuel", "total_repair", "vehicle_loadout"]
const PROCESSOR := ["orders", "current", "progress", "output", "batch_output", "total_done", "waiting_fuel"]
const DIRECTOR := ["active", "forecast", "default_stance", "log", "elapsed", "distance", "stats", "enabled", "_next_in"]
const QUARRY := ["state", "left", "near_only", "remaining", "progress", "visit_generated", "visit_nearby", "visit_discarded", "last_report", "_food_start", "discarded", "loose", "saved_speed", "visits"]
const EXPEDITION := ["state", "site_id", "offer_left", "approach_id", "kit", "steps", "step_i", "step_left", "step_time", "loot", "lost", "blueprint", "ok_count", "ng_count", "kit_used", "retreated", "log", "result_left", "stats"]
const RESOURCE := ["world_id","position", "item", "species", "gather_progress", "age"]
const GATHER := ["kind", "remaining", "max_amount", "work"]
const CREATURE := ["world_id","position", "species", "max_hp", "hp", "dead", "capturable", "_flee_speed", "_wander", "_wander_t", "_fleeing", "_facing"]
const ENEMY := ["world_id","position", "kind", "max_hp", "hp", "dead", "hold_x", "run_speed", "damage", "body_scale", "_body", "_atk_timer", "ecological", "present", "home_x", "target_index", "provoked_index", "lost_for", "search_left", "peaceful_until"]

static func fields(obj, names: Array) -> Dictionary:
	var d := {}
	for k in names: d[k] = obj.get(k)
	return d.duplicate(true)

static func put(obj, d: Dictionary, names: Array) -> void:
	for k in names: obj.set(k, d[k].duplicate(true) if d[k] is Dictionary or d[k] is Array else d[k])

static func live_children(node: Node) -> Array:
	return node.get_children().filter(func(n): return not n.is_queued_for_deletion())

static func capture(g) -> Dictionary:
	g.world.sync()
	var resources := live_children(g.resources_root)
	var creatures := live_children(g.creatures_root)
	var enemies := live_children(g.enemies_root)
	var d := {"version": VERSION, "world": fields(g.world,WorldTrip.FIELDS), "main": fields(g, MAIN), "base": fields(g.base, BASE),
		"processor": fields(g.processor, PROCESSOR), "stock": g.processor.stock.counts.duplicate(true),
		"inventory": g.storage.inventory.counts.duplicate(true), "wasted": g.storage.wasted.duplicate(true),
		"butchered": g.storage.total_butchered, "capacity": g.storage.capacity_bonus, "weight": g.storage.current_weight(),
		"director": fields(g.director, DIRECTOR), "quarry": fields(g.quarry, QUARRY), "expedition": fields(g.expedition, EXPEDITION),
		"party": [], "crew": [], "resources": [], "creatures": [], "enemies": [],
		"camera": g.camera.position, "follow": g.workers.find(g.follow_target), "scroll": 0.0}
	d["vehicle_hunt"] = g.vehicle_hunt.snapshot()
	d["journey"] = g.journey.snapshot()
	d["town"] = g.town.snapshot()
	d["production"] = {"orders":g.production_orders.duplicate(true),"refill":g.refill_settings.duplicate(true),"goals":g.procurement_goals.duplicate(true)}
	d["operations"] = fields(g.operations,FieldOperations.FIELDS)
	d["processor_extra"] = fields(g.processor.second,PROCESSOR)
	d.processor_extra.orders = [] # 共有キューは主枠で一度だけ保存
	for node in g.get_children():
		if node is WorldScroll: d.scroll = node.scroll_x
	for w in g.expedition.party: d.party.append(g.workers.find(w))
	for w in g.workers:
		d.crew.append({"worker": fields(w, WORKER), "ai": fields(w.ai, AI), "res": resources.find(w.ai.res), "prey": creatures.find(w.ai.prey), "enemy": enemies.find(w.ai.enemy)})
		# 対象がこのフレームで消えた直後の状態は、ロード時と同じ再開状態に正規化。
		# ライブのAI/荷物には触れず、失効参照を保存して復元時だけ値が変わるのを防ぐ。
		var row: Dictionary = d.crew.back()
		var S = CharacterAI.State
		if (row.ai.state in [S.NOTICE,S.MOVE_TO_RESOURCE,S.GATHER] and row.res < 0) or (row.ai.state in [S.HUNT_MOVE,S.HUNT_ATTACK] and row.prey < 0) or (row.ai.state in [S.COMBAT_MOVE,S.COMBAT] and row.enemy < 0):
			row.ai.state = S.MOVE_TO_STORAGE if row.worker.carrying >= 0 else S.SEARCH
			row.ai.manual_attack = false
	for r in resources:
		var row := {"resource": fields(r, RESOURCE), "gather": {}, "quarry_id": "", "quarry_group": ""}
		if r is GatherPoint: row.gather = fields(r, GATHER)
		if r.has_meta("quarry_id"):
			row.quarry_id = r.get_meta("quarry_id")
			row.quarry_group = r.get_meta("quarry_group")
			d.quarry.remaining[row.quarry_id] = r.remaining
			d.quarry.progress[row.quarry_id] = r.work
		d.resources.append(row)
	for c in creatures: d.creatures.append(fields(c, CREATURE))
	for e in enemies: d.enemies.append(fields(e, ENEMY))
	if g.mine_arrival_gate != null and g.mine_arrival_gate.field != null:
		d["field_snapshot"] = FieldSnapshot.capture(g, g.mine_arrival_gate.field)
		if not d.field_snapshot.is_empty():
			for i in d.crew.size():
				d.crew[i].worker.position = d.field_snapshot.workers[i].position
	return d

## フィールド名と型を許可リストで検査。Object/Callable/RIDは保存しない。
static func safe(value, depth := 0) -> bool:
	if depth > 32: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_VECTOR2: return value.is_finite()
		TYPE_COLOR: return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY:
			if value.size() > 10000: return false
			for x in value:
				if not safe(x, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 10000: return false
			for k in value:
				if typeof(k) not in [TYPE_STRING, TYPE_INT] or not safe(value[k], depth + 1): return false
			return true
	return false

static func shape(d, obj, names: Array) -> bool:
	if not d is Dictionary or d.size() != names.size(): return false
	for k in names:
		if not d.has(k): return false
		if k == "_climb_dest":
			if typeof(d[k]) not in [TYPE_NIL, TYPE_VECTOR2]: return false
		elif typeof(d[k]) != typeof(obj.get(k)): return false
	return true

static func counts(d) -> bool:
	if not d is Dictionary: return false
	for it in d:
		if not it is int or it not in GameData.Item.values() or not d[it] is int or d[it] < 0: return false
	return true

static func recipe(r) -> bool:
	if not r is Dictionary: return false
	if r.has("automatic") and not r.automatic is bool: return false
	if r.has("player_order") and not r.player_order is bool: return false
	if r.has("build_request") and not r.build_request is bool: return false
	if r.is_empty(): return true
	if r.has("batch") and (not r.batch is bool or r.has("build")): return false
	for k in ["id", "in", "out", "n", "time", "field", "tank_fuel"]:
		if not r.has(k): return false
	if not counts(r["in"]) or not r.id is String: return false
	var canonical: Dictionary
	if r.has("build"):
		if not r.build is String or not FacilityDB.has(r.build): return false
		canonical = FacilityDB.installation_recipe(r.build) if r["in"]=={FacilityDB.packed_item_of(r.build):1} else FacilityDB.recipe_of(r.build)
		# 既存v2/v3に記録済みの寝床/箱設置レシピもそのまま再開する。
		if canonical.time==0.0 and r.get("station","")==FacilityDB.def(r.build)["requires"]:
			canonical["station"]=r.get("station","")
	else:
		canonical = GameData.recipe_by_id(r.id)
	if canonical.is_empty(): return false
	# この変更以前に投入した材料と進捗を保持する。新規注文は現行レシピのみ。
	canonical = canonical.duplicate(true)
	if r.id == "build:workbench" and r["in"] == {GameData.Item.WOOD:3, GameData.Item.IRON:1}:
		canonical["in"] = r["in"].duplicate()
	if r.id in ["tool_hammer", "tool_axe"] and r.get("station", "") == "":
		canonical.erase("station")
	for k in ["in", "out", "n", "time", "field", "tank_fuel", "station"]:
		if r.get(k, "" if k == "station" else null) != canonical.get(k, "" if k == "station" else null): return false
	return true

## 旧v2/v3の省略項目だけ補完。呼出し側のsnapshotや元ファイルは変更しない。
static func worker_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("work_support"): result["work_support"] = -1
	if not result.has("gather_focus_item"): result["gather_focus_item"] = -1
	return result


## New survival-loop request state must not reject an older valid save merely
## because it had no explicit-hunt ledger yet.
static func main_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("hunt_requests"): result["hunt_requests"] = {}
	return result

static func processor_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("batch_output"): result["batch_output"] = false
	return result

static func enemy_data(row: Dictionary) -> Dictionary:
	var result:=row.duplicate(true)
	var defaults:={"ecological":false,"present":true,"home_x":0.0,"target_index":-1,"provoked_index":-1,"lost_for":0.0,"search_left":0.0,"peaceful_until":0.0}
	for k in defaults:
		if not result.has(k):result[k]=defaults[k]
	return result

static func ai_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("process_slot"): result.process_slot = 0
	if not result.has("safe_after"): result.safe_after = 0.0
	if not result.has("retreating"): result.retreating = false
	if not result.has("danger_hold"): result.danger_hold = false
	if not result.has("manual_attack"): result.manual_attack = false
	if not result.has("return_request"): result.return_request = false
	if not result.has("manual_job"): result.manual_job = -1
	if not result.has("low_hp_retreat"): result.low_hp_retreat = false
	return result


## Rescue was added to the version-3 field pilot without changing any legacy
## semantics. Old v3 saves receive an empty rescue ledger rather than failing the
## strict shape check; externally malformed ledgers are still rejected below.
## The brief former "expired" state is normalized before strict validation. It
## had no durable gameplay outcome; keeping its saved row as a temporary
## incapacitation countdown makes an in-progress old save safe to resume.
static func operation_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("rescue_cases"):
		result.rescue_cases = {}
	elif result.rescue_cases is Dictionary:
		for key in result.rescue_cases:
			var rescue_case = result.rescue_cases[key]
			if rescue_case is Dictionary and String(rescue_case.get("phase", "")) == "expired":
				rescue_case["phase"] = "incapacitated"
				rescue_case["carrier"] = -1
				rescue_case["left"] = FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS
				result.rescue_cases[key] = rescue_case
	return result


## 旧セーブには、通常の DRIVE 損傷と分離した後部被弾蓄積がない。
## 0 を補完して、単に DRIVE が低い旧セーブを燃料漏れ扱いにしない。
static func base_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("rear_engine_damage"): result.rear_engine_damage = 0.0
	if not result.has("vehicle_loadout"): result.vehicle_loadout = VehicleLoadout.initial_state()
	return result

static func extra_data(d: Dictionary) -> Dictionary:
	return d.get("processor_extra", {"orders":[],"current":{},"progress":0.0,"output":[],"batch_output":false,"total_done":0,"waiting_fuel":false})

static func operation_totals(row: Dictionary, time_key: String) -> bool:
	for k in [time_key,"food","fuel","refuel","repair"]:
		if typeof(row.get(k)) not in [TYPE_INT,TYPE_FLOAT] or row[k]<0: return false
	return true

static func validate(d, g) -> bool:
	if not d is Dictionary or not VehicleHunt.valid_snapshot(d.get("vehicle_hunt",{})):return false
	if not d is Dictionary or not safe(d) or d.get("version") != VERSION: return false
	if not TownEconomy.valid(d.get("town",{}),g.workers.size()): return false
	if not ProductionPlan.valid(d.get("production",{})): return false
	# 旧v3保存には今回追加したprofile/土地利用/地点在庫の列がない。
	# WorldTripとJourneyPlanには同じ正規化済み行を渡し、検証だけが生の旧行を
	# 読んで落ちることを防ぐ。元payloadはここで書き換えない。
	if not d.get("world") is Dictionary or not d.get("director") is Dictionary or not ResourceRegeneration.number(d.director.get("elapsed")): return false
	var world_row:Dictionary=WorldTrip.normalized(d.world,float(d.director.elapsed))
	if not WorldTrip.valid(world_row,g): return false
	for rows in world_row.locations.values():
		for row in rows.values():
			if row.has("regeneration") and not ResourceRegeneration.valid(row.regeneration,int(row.data.remaining),float(d.director.elapsed)): return false
	if not JourneyPlan.valid(d.get("journey",{}),world_row): return false
	for k in ["main", "base", "processor", "stock", "inventory", "wasted", "butchered", "capacity", "weight", "director", "quarry", "expedition", "party", "crew", "resources", "creatures", "enemies", "camera", "follow", "scroll"]:
		if not d.has(k): return false
	var main_row: Dictionary = main_data(d.main) if d.main is Dictionary else {}
	for row in [[main_row,g,MAIN],[base_data(d.base) if d.base is Dictionary else d.base,g.base,BASE],[processor_data(d.processor) if d.processor is Dictionary else d.processor,g.processor,PROCESSOR],[d.director,g.director,DIRECTOR],[d.quarry,g.quarry,QUARRY],[d.expedition,g.expedition,EXPEDITION]]:
		if not shape(row[0],row[1],row[2]): return false
	var base_row: Dictionary = base_data(d.base)
	for k in ["party", "crew", "resources", "creatures", "enemies"]:
		if not d[k] is Array: return false
	if d.crew.size() != g.workers.size() or not d.camera is Vector2 or not d.follow is int or d.follow < -1 or d.follow >= d.crew.size(): return false
	if not d.scroll is float: return false
	for key in main_row.recipe_priority:
		if not key is String or GameData.recipe_by_id(key).is_empty() or not main_row.recipe_priority[key] is int or main_row.recipe_priority[key] < 0 or main_row.recipe_priority[key] > 5: return false
	for key in main_row.gather_policy:
		if key not in GameData.Item.values() or not main_row.gather_policy[key] is int or main_row.gather_policy[key] < 0 or main_row.gather_policy[key] > 5: return false
	for key in main_row.hunt_policy:
		if not GameData.CREATURES.has(key) or not main_row.hunt_policy[key] is bool: return false
	for key in main_row.hunt_requests:
		if not GameData.CREATURES.has(key) or not main_row.hunt_requests[key] is int or main_row.hunt_requests[key] < 1 or main_row.hunt_requests[key] > 99: return false
	for k in ["weight", "capacity", "butchered"]:
		if not d[k] is int or d[k] < 0: return false
	for v in [d.inventory,d.stock,d.wasted,d.quarry.loose,d.quarry.discarded,d.quarry.visit_generated,d.quarry.visit_nearby,d.quarry.visit_discarded,d.expedition.loot,d.expedition.lost]:
		if not counts(v): return false
	if Rooms.sanitize(main_row.room_layout) != main_row.room_layout: return false
	var capacity := 0
	for id in base_row.built:
		if not FacilityDB.has(id) or not base_row.built[id] is Array: return false
		var seen := []
		for slot in base_row.built[id]:
			if not slot is int or slot < 0 or slot >= FacilityDB.max_of(id) or slot in seen: return false
			seen.append(slot)
		capacity += seen.size() * int(FacilityDB.def(id).get("capacity_bonus",0))
	if d.capacity != capacity or base_row.fuel < 0 or base_row.fuel > GameData.FUEL_CAP: return false
	if base_row.parts.size() != GameData.Part.size(): return false
	for k in base_row.parts:
		if k not in GameData.Part.values() or typeof(base_row.parts[k]) not in [TYPE_FLOAT,TYPE_INT] or base_row.parts[k] < 0 or base_row.parts[k] > 100: return false
	if typeof(base_row.rear_engine_damage) not in [TYPE_FLOAT,TYPE_INT] or base_row.rear_engine_damage < 0 or base_row.rear_engine_damage > 100: return false
	if not VehicleLoadout.valid(base_row.vehicle_loadout): return false
	if d.has("operations"):
		var operations_row: Dictionary = operation_data(d.operations) if d.operations is Dictionary else {}
		if not shape(operations_row,g.operations,FieldOperations.FIELDS) or operations_row.stance not in ["normal","alert","recall"] or operations_row.fuel_spent<0: return false
		if not counts(operations_row.delivered) or not FieldOperations.rescue_cases_valid(operations_row.rescue_cases, d.crew.size()): return false
		if operations_row.outing and not operation_totals(operations_row.baseline,"time"): return false
		if not operations_row.last_report.is_empty():
			if not operation_totals(operations_row.last_report,"seconds") or not counts(operations_row.last_report.get("items")): return false
	var extra := extra_data(d)
	if not shape(extra,g.processor.second,PROCESSOR) or not extra.orders.is_empty(): return false
	if not recipe(extra.current) or extra.progress < 0: return false
	for it in extra.output:
		if not it is int or it not in ItemDB.ORDER: return false
	if (not extra.current.is_empty() or not extra.output.is_empty()) and d.base.built.get("parallel_bench",[]).is_empty(): return false
	for r in d.processor.orders:
		if not recipe(r) or r.is_empty(): return false
	if not recipe(d.processor.current): return false
	if d.processor.progress < 0: return false
	for it in d.processor.output:
		if not it is int or it not in ItemDB.ORDER: return false
	for id in main_row.build_queue:
		if not id is String or not FacilityDB.has(id): return false
	for t in main_row.transfer_queue:
		if not t is Dictionary or not t.get("item") is int or t.item not in ItemDB.ORDER or not t.get("n") is int or t.n <= 0 or t.get("dir") not in ["to_workshop","to_storage"]: return false
	for c in main_row.craft_queue:
		if c is Dictionary and c.has("batch") and not c.batch is bool: return false
		if not c is Dictionary or not c.get("id") is String or GameData.recipe_by_id(c.id).is_empty() or not c.get("n") is int or c.n <= 0: return false
	if d.quarry.state not in ["road","approach","parked","recall","returning"]: return false
	for p in QuarryDB.POINTS:
		if not d.quarry.remaining.get(p.id) is int or d.quarry.remaining[p.id] < 0 or d.quarry.remaining[p.id] > p.amount: return false
	for k in d.quarry.progress:
		if typeof(d.quarry.progress[k]) not in [TYPE_FLOAT,TYPE_INT] or d.quarry.progress[k] < 0: return false
	var resource := ResourceNode.new()
	var gather := GatherPoint.new()
	var creature := Creature.new()
	var enemy := Enemy.new()
	var valid := _entities_valid(d, resource, gather, creature, enemy)
	resource.free(); gather.free(); creature.free(); enemy.free()
	if not valid or not WorldTrip.live_valid(d): return false
	var used := {"res":[],"prey":[],"bed":[],"repair":[]}
	var processor_slots := []
	var transfer_count := 0
	var fuel_count := 0
	var recovery_move_count := 0
	var recovery_return_count := 0
	var rescue_targets := {}
	var rescue_carriers := {}
	var rescue_row: Dictionary = operation_data(d.operations) if d.has("operations") and d.operations is Dictionary else {"rescue_cases": {}}
	for rescue_key in rescue_row.rescue_cases:
		var rescue_case: Dictionary = rescue_row.rescue_cases[rescue_key]
		rescue_targets[int(rescue_case.target)] = rescue_case
		if int(rescue_case.carrier) >= 0:
			rescue_carriers[int(rescue_case.carrier)] = rescue_case
	var town_state:Dictionary = TownEconomy.normalized(d.get("town",{}))
	for i in d.crew.size():
		var row = d.crew[i]
		if not row is Dictionary or not row.get("worker") is Dictionary or not shape(worker_data(row.worker),g.workers[i],WORKER) or not shape(ai_data(row.ai) if row.get("ai") is Dictionary else row.get("ai"),g.workers[i].ai,AI): return false
		var w: Dictionary = worker_data(row.worker)
		var a: Dictionary = ai_data(row.ai)
		if a.state not in CharacterAI.State.values() or w.floor_i not in [0,1,2] or w._climb_floor not in [0,1,2]: return false
		if a.manual_job not in [-1, GameData.Job.REPAIR]: return false
		if not a.low_hp_retreat is bool: return false
		if w.hp < 0 or w.hp > 100 or w.hunger < 0 or w.hunger > 100 or w.fatigue < 0 or w.fatigue > 100: return false
		if w.palette not in ["grey","tan","pink"] or (w.weapon != -1 and w.weapon not in GameData.WEAPON_ITEMS): return false
		if w.work_support != -1 and w.work_support not in GameData.SUPPORT_ITEMS: return false
		if w.carrying != -1 and w.carrying not in GameData.Item.values(): return false
		if w.gather_focus_item != -1 and w.gather_focus_item not in GameData.GROUND_ITEMS: return false
		if w.carry_n < 1 or not counts(w.carry_bonus) or not counts(w.carcass_cargo) or not recipe(a.haul_recipe): return false
		for key in w.priorities:
			if key not in GameData.Job.values() or not w.priorities[key] is int or w.priorities[key] < 0 or w.priorities[key] > GameData.MAX_PRIORITY: return false
		for key in w.ranks:
			if key not in GameData.Field.values() or not w.ranks[key] is int or w.ranks[key] < 0 or w.ranks[key] > 7: return false
		for key in w.tools:
			if key not in GatherDB.SLOTS or not w.tools[key] is int or not GatherDB.TOOLS.has(w.tools[key]) or GatherDB.TOOLS[w.tools[key]].slot != key: return false
		for key in ["res","prey","enemy"]:
			var pool: Array = d.resources if key == "res" else (d.creatures if key == "prey" else d.enemies)
			if not row.get(key) is int or row[key] < -1 or row[key] >= pool.size(): return false
			if key != "enemy" and row[key] >= 0:
				if row[key] in used[key]: return false
				used[key].append(row[key])
		if a.state in [CharacterAI.State.HAUL_TAKE,CharacterAI.State.HAUL_MOVE] and a.haul_recipe.is_empty(): return false
		if a.state in [CharacterAI.State.REST,CharacterAI.State.REST_MOVE]:
			if w.bed_index not in d.base.built.get("bed",[]) or w.bed_index in used.bed: return false
			used.bed.append(w.bed_index)
		if a.state in [CharacterAI.State.REPAIR_TAKE,CharacterAI.State.REPAIR_MOVE,CharacterAI.State.REPAIR]:
			if a.repair_part not in GameData.Part.values() or a.repair_part in used.repair: return false
			used.repair.append(a.repair_part)
		if a.process_slot not in [0,1]: return false
		if a.state in [CharacterAI.State.PROCESS,CharacterAI.State.MOVE_TO_MACHINE]:
			if a.process_slot in processor_slots: return false
			if a.process_slot == 1 and d.base.built.get("parallel_bench",[]).is_empty(): return false
			processor_slots.append(a.process_slot)
		if a.state in [CharacterAI.State.XFER_TAKE,CharacterAI.State.XFER_MOVE]:
			transfer_count += 1
			if a.xfer_item not in ItemDB.ORDER or a.xfer_dir not in ["to_workshop","to_storage"]: return false
		if a.state in [CharacterAI.State.REFUEL_TAKE,CharacterAI.State.REFUEL_MOVE,CharacterAI.State.REFUEL]:
			fuel_count += 1
			if a.haul_item not in GameData.FUEL_ITEMS: return false
		if a.state in [CharacterAI.State.MISSION_RECOVERY_MOVE,CharacterAI.State.MISSION_RECOVERY_LOAD]:
			recovery_move_count += 1
			if town_state.recovery != "loading" or town_state.recovery_worker != i: return false
		if a.state == CharacterAI.State.MISSION_RECOVERY_RETURN:
			recovery_return_count += 1
			if town_state.recovery != "carried" or town_state.recovery_worker != i: return false
		if a.state in [CharacterAI.State.HAUL_MOVE,CharacterAI.State.REPAIR_MOVE,CharacterAI.State.REPAIR,CharacterAI.State.REFUEL_MOVE,CharacterAI.State.REFUEL,CharacterAI.State.EAT,CharacterAI.State.XFER_MOVE] and w.carrying < 0: return false
		var rescue_target: Dictionary = rescue_targets.get(i, {})
		var rescue_carrier: Dictionary = rescue_carriers.get(i, {})
		if not rescue_target.is_empty():
			var rescue_phase := String(rescue_target.phase)
			if rescue_phase in ["waiting", "assigned", "carried", "incapacitated"] and (not w.down or a.state != CharacterAI.State.DOWN): return false
			if rescue_phase == "recovering" and (w.down or a.state != CharacterAI.State.RESCUE_RECOVER): return false
		if not rescue_carrier.is_empty():
			var carrier_phase := String(rescue_carrier.phase)
			if carrier_phase == "assigned" and a.state not in [CharacterAI.State.RESCUE_MOVE, CharacterAI.State.RESCUE_LIFT]: return false
			if carrier_phase == "carried" and a.state != CharacterAI.State.RESCUE_RETURN: return false
		if a.state in [CharacterAI.State.RESCUE_MOVE, CharacterAI.State.RESCUE_LIFT, CharacterAI.State.RESCUE_RETURN] and rescue_carrier.is_empty(): return false
		if a.state == CharacterAI.State.RESCUE_RECOVER and rescue_target.is_empty(): return false
		if w.level < 1 or w.gender not in [0,1] or w.dept not in GameData.Field.values(): return false
		if not a.gather_ev.is_empty():
			for key in ["eff","seconds"]:
				if typeof(a.gather_ev.get(key)) not in [TYPE_FLOAT,TYPE_INT]: return false
	if transfer_count > 1 or fuel_count > 1 or recovery_move_count > 1 or recovery_return_count > 1: return false
	if town_state.recovery == "loading" and recovery_move_count != 1: return false
	if town_state.recovery == "carried" and recovery_return_count != 1: return false
	var party_seen := []
	for i in d.party:
		if not i is int or i < 0 or i >= d.crew.size() or i in party_seen: return false
		party_seen.append(i)
	if d.expedition.state not in ["idle","offered","running","done"]: return false
	if d.expedition.state != "idle" and not ExpeditionDB.SITES.has(d.expedition.site_id): return false
	for k in d.expedition.steps:
		if not ExpeditionDB.STEPS.has(k): return false
	if d.expedition.step_i < 0 or d.expedition.step_i > d.expedition.steps.size() or d.expedition.step_time <= 0: return false
	for row in d.director.active + d.director.forecast:
		if not row is Dictionary or not row.get("id") is String or EventDB.def(row.id).is_empty() or typeof(row.get("left")) not in [TYPE_FLOAT,TYPE_INT]: return false
	for row in d.director.active:
		if not row.get("stance") is String or not row.get("spawned") is int: return false
		for k in ["total","flee_t"]:
			if typeof(row.get(k)) not in [TYPE_FLOAT,TYPE_INT]: return false
	for key in ["weather","attack","trouble","chance","repelled","escaped","kills"]:
		if not d.director.stats.get(key) is int or d.director.stats[key] < 0: return false
	for key in ["trips","steps_ok","steps_ng","blueprints","retreats"]:
		if not d.expedition.stats.get(key) is int or d.expedition.stats[key] < 0: return false
	for row in d.director.log:
		if not row is Dictionary or not row.get("text") is String or typeof(row.get("at")) not in [TYPE_FLOAT,TYPE_INT]: return false
	for line in d.expedition.log:
		if not line is String: return false
	for i in d.crew.size():
		if d.crew[i].worker.away != (d.expedition.state == "running" and i in d.party): return false
	return saved_weight(d) == d.weight and (not d.has("field_snapshot") or not FieldSnapshot.prepare(d).is_empty())

static func _entities_valid(d, resource, gather, creature, enemy) -> bool:
	var quarry_ids := []
	for row in d.resources:
		if not row is Dictionary or not shape(row.get("resource"),resource,RESOURCE) or not row.get("gather") is Dictionary: return false
		if row.resource.item not in GameData.Item.values(): return false
		if row.resource.item == GameData.Item.CARCASS and not GameData.CREATURES.has(row.resource.species): return false
		if not row.gather.is_empty():
			if not shape(row.gather,gather,GATHER) or not GatherDB.POINTS.has(row.gather.kind) or row.gather.remaining < 0 or row.gather.remaining > row.gather.max_amount or row.gather.work < 0: return false
		if not row.get("quarry_id") is String or not row.get("quarry_group") is String: return false
		if row.quarry_id != "":
			if row.gather.is_empty() or row.quarry_id in quarry_ids: return false
			var found := false
			for p in QuarryDB.POINTS:
				if p.id == row.quarry_id and p.group == row.quarry_group and row.gather.remaining == d.quarry.remaining[p.id] and row.gather.work == d.quarry.progress.get(p.id,0.0): found = true
			if not found: return false
			quarry_ids.append(row.quarry_id)
	if d.quarry.state in ["parked","recall"] and quarry_ids.size() != QuarryDB.POINTS.size(): return false
	if d.quarry.state not in ["parked","recall"] and not quarry_ids.is_empty(): return false
	for row in d.creatures:
		if not shape(row,creature,CREATURE) or not GameData.CREATURES.has(row.species): return false
	for row in d.enemies:
		if not shape(enemy_data(row),enemy,ENEMY) or not EventDB.ENEMIES.has(row.kind): return false
	return true

## 検査済みsnapshotのみ。予約は空から作り直し、プロセス内のObject参照を使い回さない。
static func apply(g, d: Dictionary) -> bool:
	if not validate(d,g):
		last_error = "保存内容の形式・数量・参照を検証できません。現在の進行は変更しません。"
		return false
	var prepared := FieldSnapshot.prepare(d) if d.has("field_snapshot") else {}
	g.base.cancel_armor_preview()
	if g.mine_arrival_gate != null:
		g.mine_arrival_gate.discard_field_for_load()
	if g.mine_arrival_gate != null and g.mine_arrival_gate.has_method("cancel_pending_entry"):
		g.mine_arrival_gate.cancel_pending_entry()
	FieldSurvivalClock.reset_runtime(g)
	g.vehicle_hunt.restore(d.get("vehicle_hunt",{}))
	g.journey.restore(d.get("journey",{}))
	g.town.restore(d.get("town",{}))
	var plan:Dictionary=d.get("production",{})
	g.production_orders=plan.get("orders",[]).duplicate(true)
	var main_row: Dictionary = main_data(d.main)
	g.refill_settings=ProductionPlan.defaults() if d.has("production") else ProductionPlan.legacy_settings(main_row.recipe_priority)
	g.refill_settings.merge(plan.get("refill",{}),true)
	g.procurement_goals=plan.get("goals",{}).duplicate(true)
	g.cancel_facility_pack()
	g.world.npc_service.cancel_quote()
	put(g.world,WorldTrip.normalized(d.world,float(d.director.elapsed)),WorldTrip.FIELDS)
	put(g.operations,operation_data(d.get("operations",fields(FieldOperations.new(),FieldOperations.FIELDS))),FieldOperations.FIELDS)
	put(g,main_row,MAIN); put(g.base,base_data(d.base),BASE); put(g.processor,processor_data(d.processor),PROCESSOR)
	g.storage.inventory.counts = d.inventory.duplicate(true)
	g.storage.wasted = d.wasted.duplicate(true)
	g.storage.total_butchered = d.butchered
	g.storage.capacity_bonus = d.capacity
	g.processor.stock.counts = d.stock.duplicate(true)
	g.processor.incoming.clear(); g.processor.worker = null
	put(g.processor.second,extra_data(d),PROCESSOR)
	g.processor.second.worker = null
	g.processor.share_queues()
	g.processor._out_times.clear(); g.processor._drops.clear()
	g.base.beds = [null,null,null]; g.base.refuel_reserved = false; g.base.repair_reserved.clear()
	g.base.apply_layout()
	put(g.director,d.director,DIRECTOR); put(g.quarry,d.quarry,QUARRY); put(g.expedition,d.expedition,EXPEDITION)
	g.quarry.points.clear(); g.expedition.party.clear()
	g.food_claims = 0; g.transfer_worker = null; g.last_carcass = null
	for parent in [g.resources_root,g.creatures_root,g.enemies_root]:
		for node in parent.get_children():
			parent.remove_child(node)
			node.queue_free()
	var resources := []; var creatures := []; var enemies := []
	for row in d.resources:
		var r = ResourceNode.new() if row.gather.is_empty() else GatherPoint.new()
		r.game = g
		put(r,row.resource,RESOURCE)
		if not row.gather.is_empty(): put(r,row.gather,GATHER)
		if row.quarry_id != "":
			r.set_meta("quarry_id",row.quarry_id); r.set_meta("quarry_group",row.quarry_group)
			g.quarry.points.append(r)
		g.resources_root.add_child(r); resources.append(r)
	for row in d.creatures:
		var c := Creature.new(); c.game = g; put(c,row,CREATURE)
		g.creatures_root.add_child(c); creatures.append(c)
	for row in d.enemies:
		var e := Enemy.new(); e.game = g; put(e,enemy_data(row),ENEMY)
		g.enemies_root.add_child(e); enemies.append(e)
	for i in d.crew.size():
		var w = g.workers[i]; var row: Dictionary = d.crew[i]
		put(w,worker_data(row.worker),WORKER); put(w.ai,ai_data(row.ai),AI)
		w._sheet = GameData.tex("res://assets/characters/mouse_%s.png" % w.palette)
		w.visible = not w.away; w.set_process(not w.away)
		w.sleeping = false; w.resting = false
		var a = w.ai
		a.res = resources[row.res] if row.res >= 0 else null
		a.prey = creatures[row.prey] if row.prey >= 0 else null
		a.enemy = enemies[row.enemy] if row.enemy >= 0 else null
		if a.res != null: a.res.claimed_by = w; a.res.reserved = a.bag_limit if a.res is GatherPoint else 1
		if a.prey != null: a.prey.hunted_by = w
		var S = CharacterAI.State
		# 消滅済み対象だけ再選択。保有品を瞬間移動させず、現在位置から倉庫へ運ぶ。
		if (a.state in [S.NOTICE,S.MOVE_TO_RESOURCE,S.GATHER] and a.res == null) or (a.state in [S.HUNT_MOVE,S.HUNT_ATTACK] and a.prey == null) or (a.state in [S.COMBAT_MOVE,S.COMBAT] and a.enemy == null):
			a.state = S.MOVE_TO_STORAGE if w.carrying >= 0 else S.SEARCH
			a.manual_attack = false
		if a.state in [S.HAUL_TAKE,S.HAUL_MOVE]: g.processor.incoming.append(a.haul_recipe)
		if a.state in [S.MOVE_TO_MACHINE,S.PROCESS]: g.processor.lane(a.process_slot).worker = w
		if a.state in [S.REST_MOVE,S.REST]: g.base.beds[w.bed_index] = w
		if a.state in [S.REFUEL_TAKE,S.REFUEL_MOVE,S.REFUEL]: g.base.refuel_reserved = true
		if a.state in [S.REPAIR_TAKE,S.REPAIR_MOVE,S.REPAIR]: g.base.repair_reserved[a.repair_part] = w
		if a.state in [S.XFER_TAKE,S.XFER_MOVE]: g.transfer_worker = w
		a._eat_claimed = a.state == S.EAT_TAKE
		if a._eat_claimed: g.food_claims += 1
	for i in d.party: g.expedition.party.append(g.workers[i])
	# Worker Object references did not travel through the save. Reattach carried and
	# recovery roles only after every worker has been populated and validated.
	g.operations.restore_rescue_state()
	g.camera.position = d.camera; g.camera.reset_smoothing()
	g.follow_target = g.workers[d.follow] if d.follow >= 0 else null
	for node in g.get_children():
		if node is WorldScroll: node.scroll_x = d.scroll
	g.storage.queue_redraw(); g.base.queue_redraw()
	if g.region_clear_ui != null: g.region_clear_ui.reset_for_loaded_game()
	if not prepared.is_empty():
		g.mine_arrival_gate.install_saved_field(prepared)
		g.get_tree().paused = true
	last_error = ""
	return true

static func item_mass(item: int, n := 1) -> int:
	return CargoDB.size_of(item) * n if CargoDB.bay_of(item) >= 0 else 0

static func mass(items: Dictionary) -> int:
	var n := 0
	for it in items: n += item_mass(it,items[it])
	return n

static func saved_weight(d: Dictionary) -> int:
	var n := mass(d.inventory) + mass(d.stock) + mass(d.get("vehicle_hunt",{}).get("cargo",{}))
	for r in d.processor.orders + [d.processor.current]: n += mass(r.get("in",{}))
	for it in d.processor.output: n += item_mass(it)
	n += mass(extra_data(d).current.get("in",{}))
	for it in extra_data(d).output: n += item_mass(it)
	for row in d.crew:
		var w: Dictionary = worker_data(row.worker)
		if row.ai.state == CharacterAI.State.HAUL_MOVE:
			n += mass(row.ai.haul_recipe["in"])
		elif w.carrying == GameData.Item.CARCASS:
			n += mass(w.carcass_cargo)
		elif w.carrying >= 0: n += item_mass(w.carrying,w.carry_n)
		n += mass(w.carry_bonus)
		if w.weapon >= 0: n += item_mass(w.weapon)
		if w.work_support >= 0: n += item_mass(w.work_support)
	if d.expedition.state == "running" and d.expedition.kit and not d.expedition.kit_used: n += item_mass(GameData.Item.REPAIR_KIT)
	n += VehicleLoadout.equipment_weight(base_data(d.base).vehicle_loadout)
	var town:Dictionary = TownEconomy.normalized(d.get("town",{}))
	if town.get("delivery","")=="outbound" and town.get("delivery_cargo",false): n += TownDB.DELIVERY_PARCEL_WEIGHT
	if town.get("recovery","") in ["carried","return","ready"]: n += TownDB.RECOVERY_PARCEL_WEIGHT
	return n

static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)

static func checkpoint_loss(credits: int) -> int:
	return maxi(0,floori(float(maxi(0,credits))*CHECKPOINT_CREDIT_RATIO))

## Disabled diagnostic fixtures retain their state-machine coverage without a
## disk side effect. Player runs still use the same verified atomic envelope as
## a manual save, at an independent path.
static func write_checkpoint(g, overwrite := true) -> bool:
	if disabled:
		last_error = ""
		return true
	var path:String=g.save_ui.checkpoint_path
	var other:String=CHECKPOINT_PATH if g.world.first_region() else FIRST_REGION_CHECKPOINT_PATH
	var absolute:String=ProjectSettings.globalize_path(path).simplify_path()
	# The atomic writer also owns .tmp/.bak/.damaged siblings. Protect both
	# directions so a checkpoint backup cannot overwrite a manual slot.
	for protected in [g.save_ui.path,PATH,FIRST_REGION_SAVE_PATH,other]:
		var reserved:String=ProjectSettings.globalize_path(str(protected)).simplify_path()
		if absolute==reserved or absolute.begins_with(reserved+".") or reserved.begins_with(absolute+"."):
			last_error="checkpointの保存先が手動保存または別地域の保存先と重なっています。"
			return false
	return write(g,path,overwrite)

## Restore a fresh copy of the frozen checkpoint, then charge exactly once in
## memory. The file is never rewritten, so retries cannot compound the 10% fee;
## ordinary SaveGame.apply remains fee-free.
static func restore_checkpoint(g, path: String = CHECKPOINT_PATH) -> bool:
	var d:=read(path)
	if d.is_empty(): return false
	if not validate(d,g):
		last_error="checkpointの形式・数量・参照を検証できません。現在の進行は変更しません。"
		return false
	var restored:Dictionary=d.duplicate(true)
	var town_state:Dictionary=TownEconomy.normalized(restored.get("town",{}))
	if town_state.is_empty():
		last_error="checkpointの街データを検証できません。現在の進行は変更しません。"
		return false
	town_state.credits=maxi(0,int(town_state.credits)-checkpoint_loss(int(town_state.credits)))
	restored.town=town_state
	return apply(g,restored)

static func read(path: String = PATH, allow_legacy := false) -> Dictionary:
	last_error = ""
	if not exists(path):
		last_error = "セーブがありません。"
		return {}
	if FileAccess.get_file_as_bytes(path).size() > 8000000:
		last_error = "セーブが大きすぎます。"
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(path))
	var envelope = parser.data if parse_error == OK else null
	if envelope is Dictionary and envelope.get("version")==2 and not allow_legacy:
		last_error="旧version2です。地域移行の確認が必要です。元ファイルは変更しません。"
		return {}
	if not envelope is Dictionary or (envelope.get("version") != VERSION and not (allow_legacy and envelope.get("version") == 2)) or not envelope.get("payload") is String or not envelope.get("sha256") is String:
		last_error = "破損または未対応の旧形式です。元のファイルは変更しません。"
		return {}
	var bytes := Marshalls.base64_to_raw(envelope.payload)
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	if hash.finish().hex_encode() != envelope.sha256:
		last_error = "セーブの整合性検査に失敗しました。"
		return {}
	var d = bytes_to_var(bytes) # allow_objects=false。コード・Objectは復元しない。
	if not d is Dictionary or not safe(d):
		last_error = "セーブ内容を読めません。"
		return {}
	return d

static func write(g, path: String = PATH, overwrite := false) -> bool:
	if g.game_over: last_error = "ゲーム終了状態は保存できません。"; return false
	if disabled: last_error = "検証モードではプレイヤーの保存は無効です。"; return false
	var paused: bool = g.get_tree().paused
	g.get_tree().paused = true
	var d := capture(g)
	var valid := validate(d,g)
	g.get_tree().paused = paused
	if not valid: last_error = "保存状態を検証できません。既存の保存は変更しません。"; return false
	return _write_validated(g,d,path,overwrite)

## Explicit manual field save. Unsupported contexts fail before any file write.
static func write_field(g, path: String, overwrite := false) -> bool:
	var gate = g.mine_arrival_gate
	if g.game_over or gate == null or gate.field == null or not gate._save_override_active or gate._save_was_disabled:
		last_error = "現在の現地保存は利用できません。"
		return false
	var was_paused: bool = g.get_tree().paused
	g.get_tree().paused = true
	var d := capture(g)
	var valid := validate(d,g)
	g.get_tree().paused = was_paused
	if not valid:
		last_error = "この現地状態の完全な復元にはまだ対応していません。"
		return false
	return _write_validated(g,d,path,overwrite)

static func _write_validated(g, d: Dictionary, path: String, overwrite: bool) -> bool:
	if exists(path) and not overwrite: last_error = "上書きの確認が必要です。"; return false
	var bytes := var_to_bytes(d)
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	var envelope := {"version": VERSION, "payload": Marshalls.raw_to_base64(bytes), "sha256": hash.finish().hex_encode()}
	var temp := path + ".tmp"
	var f := FileAccess.open(temp,FileAccess.WRITE)
	if f == null: last_error = "一時ファイルを書けません。既存の保存は変更しません。"; return false
	f.store_string(JSON.stringify(envelope)); f.flush()
	var err := f.get_error(); f.close()
	if err != OK or read(temp) != d:
		last_error = "一時ファイルの検証に失敗。既存の保存は変更しません。"
		return false
	if exists(path):
		var previous := read(path,true)
		var backup := path + (".legacy-v2" if previous.get("version")==2 else (".bak" if not previous.is_empty() and validate(previous,g) else ".damaged"))
		if previous.get("version")==2 and FileAccess.file_exists(backup) and FileAccess.get_file_as_bytes(backup)!=FileAccess.get_file_as_bytes(path):
			# 過去に保全した別の旧セーブも失わない。
			backup += "." + FileAccess.get_sha256(path)
		# バックアップも一時ファイルを経由。主保存の切替が失敗しても主保存は残る。
		if DirAccess.dir_exists_absolute(backup + ".tmp") or DirAccess.dir_exists_absolute(backup) or DirAccess.copy_absolute(path,backup + ".tmp") != OK or DirAccess.rename_absolute(backup + ".tmp",backup) != OK:
			last_error = "バックアップを保全できないため保存を中止しました。"
			return false
	if DirAccess.rename_absolute(temp,path) != OK:
		last_error = "保存の切替に失敗しました。元の保存は残っています。"
		return false
	last_error = ""
	return true


## 明示確認後だけ呼ぶ。旧街道には地域を推測で与えない。
static func migrate_v2(raw: Dictionary, g) -> Dictionary:
	if raw.get("version")!=2: last_error="移行対象のversion2ではありません。"; return {}
	if not safe(raw): last_error="旧保存に不正な値があります。"; return {}
	for key in ["resources","creatures","enemies"]:
		if not raw.get(key) is Array: last_error="旧保存の屋外データ形式が不正です。"; return {}
	var d:=raw.duplicate(true)
	d.version=VERSION
	var world:=WorldTrip.new()
	world.active=false
	if not d.get("quarry") is Dictionary: return {}
	if d.quarry.get("state") in ["parked","recall"]:
		world.active=true; world.region="old_mine"
	d["world"]=fields(world,WorldTrip.FIELDS)
	for row in d.get("resources",[]):
		if not row is Dictionary or not row.get("resource") is Dictionary: return {}
		row.resource["world_id"]=""
	for row in d.get("creatures",[])+d.get("enemies",[]):
		if not row is Dictionary: return {}
		row["world_id"]=""
	if not validate(d,g): last_error="旧保存を安全に移行できません。元ファイルは保持します。"; return {}
	return d
