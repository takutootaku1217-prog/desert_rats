class_name SaveGame
extends RefCounted
## 現行モデル専用。ObjectをデコードしないVariant payload + SHA256付きJSON。
## UIの停止中、またはフレーム内の同期呼出しでsnapshot。自動保存はしない。
const VERSION := 3
const PATH := "user://save.json"
## v3 の単一セーブは読み取り専用の互換入口として残す。新規の書き込み先は用途別。
const PROGRESS_PATH := "user://progress.json"
const CHECKPOINT_PATH := "user://checkpoint.json"
const SLOT_PROGRESS := "progress"
const SLOT_CHECKPOINT := "checkpoint"
## 正式な損失量・対象は未決。再開処理はこの差し替え可能なポリシーだけを見る。
## 10% は承認済みテスト方針であり、正式バランス決定前にここを差し替える。
const DEFAULT_RESTART_LOSS := {"credits_ratio": 0.10, "credits_fixed": 0}
## 将来の救助タイマー用。現段階では AI を動かさず、保存形式だけを予約する。
const RESCUE_DEFAULT := {"version": 1, "incapacitated": {}, "all_down_elapsed": 0.0}
static var last_error := ""
static var disabled := false
static var new_run_requested := false
## The paired checkpoint selected by an explicit Continue.  It prevents another
## run's global checkpoint (or its backup) being used after a progress restore.
static var active_checkpoint := {}
## A normal boot with existing saves is neutral until the player explicitly
## Continues or restarts from a checkpoint.  Only then may its run ID be adopted.
static var run_selected := true
const MAIN := ["target_speed", "scroll_speed", "save_run_id", "room_layout", "total_rooms_built", "recipe_priority", "gather_policy", "hunt_policy", "blueprints", "total_gathered", "total_hunted", "total_eaten", "tool_auto", "_tool_clock", "build_queue", "total_built", "total_wasted", "_waste_note_at", "_spawn_dist", "_creature_dist", "wave", "kills", "_wave_timer", "transfer_queue", "craft_queue", "total_transferred", "total_crafted_by_hand", "_feed_clock"]
const WORKER := ["char_name", "palette", "priorities", "carrying", "carcass_cargo", "carrying_species", "carry_source", "carry_n", "carry_bonus", "weapon", "work_support", "tools", "speed", "target", "position", "slot_offset", "hp", "hunger", "fatigue", "stress", "calm", "mental", "down", "floor_i", "facing", "level", "gender", "ranks", "skills", "dept", "away", "bed_index", "_climb_dest", "_climb_floor", "_climb_kind"]
const AI := ["state", "timer", "haul_item", "haul_recipe", "repair_part", "gather_ev", "bag_limit", "bag_frac", "eat_wait", "xfer_item", "xfer_dir", "current_job", "life_request", "process_slot", "safe_after", "retreating", "danger_hold", "manual_attack", "return_request", "manual_job"]
const BASE := ["built", "max_hp", "hp", "fuel", "parts", "rear_engine_damage", "total_refuel", "total_repair"]
const PROCESSOR := ["orders", "current", "progress", "output", "batch_output", "total_done", "waiting_fuel"]
const DIRECTOR := ["active", "forecast", "default_stance", "log", "elapsed", "distance", "stats", "enabled", "_next_in"]
const QUARRY := ["state", "left", "near_only", "remaining", "progress", "visit_generated", "visit_nearby", "visit_discarded", "last_report", "_food_start", "discarded", "loose", "saved_speed", "visits", "reward_replenish_pending"]
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
		"party": [], "crew": [], "resources": [], "creatures": [], "enemies": [], "rescue": RESCUE_DEFAULT.duplicate(true),
		"camera": g.camera.position, "follow": g.workers.find(g.follow_target), "scroll": 0.0}
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
	return result

static func processor_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("batch_output"): result["batch_output"] = false
	return result

static func main_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("save_run_id"): result.save_run_id = "legacy"
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
	return result

## 試作ブランチで先行した報酬補充予約を、通常版の旧セーブでは false として補完する。
static func quarry_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("reward_replenish_pending"): result.reward_replenish_pending = false
	return result


## 旧セーブには、通常の DRIVE 損傷と分離した後部被弾蓄積がない。
## 0 を補完して、単に DRIVE が低い旧セーブを燃料漏れ扱いにしない。
static func base_data(row: Dictionary) -> Dictionary:
	var result := row.duplicate(true)
	if not result.has("rear_engine_damage"): result.rear_engine_damage = 0.0
	return result

static func extra_data(d: Dictionary) -> Dictionary:
	return d.get("processor_extra", {"orders":[],"current":{},"progress":0.0,"output":[],"batch_output":false,"total_done":0,"waiting_fuel":false})

static func operation_totals(row: Dictionary, time_key: String) -> bool:
	for k in [time_key,"food","fuel","refuel","repair"]:
		if typeof(row.get(k)) not in [TYPE_INT,TYPE_FLOAT] or row[k]<0: return false
	return true

static func rescue_data(d: Dictionary) -> Dictionary:
	var value: Variant = d.get("rescue", RESCUE_DEFAULT)
	return value.duplicate(true) if value is Dictionary else {}

static func rescue_valid(d: Dictionary) -> bool:
	if d.size() != RESCUE_DEFAULT.size() or d.get("version") != 1 or not d.get("incapacitated") is Dictionary:
		return false
	if typeof(d.get("all_down_elapsed")) not in [TYPE_FLOAT, TYPE_INT] or d.all_down_elapsed < 0.0:
		return false
	for crew_id in d.incapacitated:
		var timer: Variant = d.incapacitated[crew_id]
		if not crew_id is int or crew_id < 0 or not timer is Dictionary:
			return false
		for key in ["left", "carried"]:
			if not timer.has(key): return false
		if typeof(timer.left) not in [TYPE_FLOAT, TYPE_INT] or timer.left < 0.0 or not timer.carried is bool:
			return false
	return true

static func validate(d, g) -> bool:
	if not d is Dictionary or not safe(d) or d.get("version") != VERSION: return false
	if not rescue_valid(rescue_data(d)): return false
	if not TownEconomy.valid(d.get("town",{}),g.workers.size()): return false
	if not ProductionPlan.valid(d.get("production",{})): return false
	if not WorldTrip.valid(d.get("world"),g): return false
	if not JourneyPlan.valid(d.get("journey",{}),d.world): return false
	for k in ["main", "base", "processor", "stock", "inventory", "wasted", "butchered", "capacity", "weight", "director", "quarry", "expedition", "party", "crew", "resources", "creatures", "enemies", "camera", "follow", "scroll"]:
		if not d.has(k): return false
	for row in [[main_data(d.main) if d.main is Dictionary else d.main,g,MAIN],[base_data(d.base) if d.base is Dictionary else d.base,g.base,BASE],[processor_data(d.processor) if d.processor is Dictionary else d.processor,g.processor,PROCESSOR],[d.director,g.director,DIRECTOR],[quarry_data(d.quarry) if d.quarry is Dictionary else d.quarry,g.quarry,QUARRY],[d.expedition,g.expedition,EXPEDITION]]:
		if not shape(row[0],row[1],row[2]): return false
	var base_row: Dictionary = base_data(d.base)
	for k in ["party", "crew", "resources", "creatures", "enemies"]:
		if not d[k] is Array: return false
	if d.crew.size() != g.workers.size() or not d.camera is Vector2 or not d.follow is int or d.follow < -1 or d.follow >= d.crew.size(): return false
	if not d.scroll is float: return false
	for key in d.main.recipe_priority:
		if not key is String or GameData.recipe_by_id(key).is_empty() or not d.main.recipe_priority[key] is int or d.main.recipe_priority[key] < 0 or d.main.recipe_priority[key] > 5: return false
	for key in d.main.gather_policy:
		if key not in GameData.Item.values() or not d.main.gather_policy[key] is int or d.main.gather_policy[key] < 0 or d.main.gather_policy[key] > 5: return false
	for key in d.main.hunt_policy:
		if not GameData.CREATURES.has(key) or not d.main.hunt_policy[key] is bool: return false
	for k in ["weight", "capacity", "butchered"]:
		if not d[k] is int or d[k] < 0: return false
	for v in [d.inventory,d.stock,d.wasted,d.quarry.loose,d.quarry.discarded,d.quarry.visit_generated,d.quarry.visit_nearby,d.quarry.visit_discarded,d.expedition.loot,d.expedition.lost]:
		if not counts(v): return false
	if Rooms.sanitize(d.main.room_layout) != d.main.room_layout: return false
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
	if d.has("operations"):
		if not shape(d.operations,g.operations,FieldOperations.FIELDS) or d.operations.stance not in ["normal","alert","recall"] or d.operations.fuel_spent<0: return false
		if not counts(d.operations.delivered): return false
		if d.operations.outing and not operation_totals(d.operations.baseline,"time"): return false
		if not d.operations.last_report.is_empty():
			if not operation_totals(d.operations.last_report,"seconds") or not counts(d.operations.last_report.get("items")): return false
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
	for id in d.main.build_queue:
		if not id is String or not FacilityDB.has(id): return false
	for t in d.main.transfer_queue:
		if not t is Dictionary or not t.get("item") is int or t.item not in ItemDB.ORDER or not t.get("n") is int or t.n <= 0 or t.get("dir") not in ["to_workshop","to_storage"]: return false
	for c in d.main.craft_queue:
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
	var town_state:Dictionary = TownEconomy.normalized(d.get("town",{}))
	for i in d.crew.size():
		var row = d.crew[i]
		if not row is Dictionary or not row.get("worker") is Dictionary or not shape(worker_data(row.worker),g.workers[i],WORKER) or not shape(ai_data(row.ai) if row.get("ai") is Dictionary else row.get("ai"),g.workers[i].ai,AI): return false
		var w: Dictionary = worker_data(row.worker)
		var a: Dictionary = ai_data(row.ai)
		if a.state not in CharacterAI.State.values() or w.floor_i not in [0,1,2] or w._climb_floor not in [0,1,2]: return false
		if a.manual_job not in [-1, GameData.Job.REPAIR]: return false
		if w.hp < 0 or w.hp > 100 or w.hunger < 0 or w.hunger > 100 or w.fatigue < 0 or w.fatigue > 100: return false
		if w.palette not in ["grey","tan","pink"] or w.weapon not in [-1,GameData.Item.SIMPLE_SPEAR]: return false
		if w.work_support != -1 and w.work_support not in GameData.SUPPORT_ITEMS: return false
		if w.carrying != -1 and w.carrying not in GameData.Item.values(): return false
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
	return saved_weight(d) == d.weight

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
	g.journey.restore(d.get("journey",{}))
	g.town.restore(d.get("town",{}))
	var plan:Dictionary=d.get("production",{})
	g.production_orders=plan.get("orders",[]).duplicate(true)
	g.refill_settings=ProductionPlan.defaults() if d.has("production") else ProductionPlan.legacy_settings(d.main.recipe_priority)
	g.refill_settings.merge(plan.get("refill",{}),true)
	g.procurement_goals=plan.get("goals",{}).duplicate(true)
	g.cancel_facility_pack()
	put(g.world,WorldTrip.normalized(d.world),WorldTrip.FIELDS)
	put(g.operations,d.get("operations",fields(FieldOperations.new(),FieldOperations.FIELDS)),FieldOperations.FIELDS)
	put(g,main_data(d.main),MAIN); put(g.base,base_data(d.base),BASE); put(g.processor,processor_data(d.processor),PROCESSOR)
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
	put(g.director,d.director,DIRECTOR); put(g.quarry,quarry_data(d.quarry),QUARRY); put(g.expedition,d.expedition,EXPEDITION)
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
	g.camera.position = d.camera; g.camera.reset_smoothing()
	g.follow_target = g.workers[d.follow] if d.follow >= 0 else null
	for node in g.get_children():
		if node is WorldScroll: node.scroll_x = d.scroll
	g.storage.queue_redraw(); g.base.queue_redraw()
	last_error = ""
	return true

## チェックポイントは常にファイル上の元スナップショットから復元するため、同じ再開を
## 何度選んでも損失は積み上がらない。正式バランスは後で policy を差し替える。
static func restart_loss(credits: int, policy: Dictionary = DEFAULT_RESTART_LOSS) -> int:
	var ratio := float(policy.get("credits_ratio", 0.0))
	var fixed := int(policy.get("credits_fixed", 0))
	if credits < 0 or ratio < 0.0 or fixed < 0: return -1
	return mini(credits, int(floor(float(credits) * ratio)) + fixed)

static func snapshot_run_id(d: Dictionary) -> String:
	var value: Variant = d.get("main", {})
	if not value is Dictionary: return ""
	return str(main_data(value).get("save_run_id", "legacy"))

static func current_run_id(g) -> String:
	return str(g.get("save_run_id"))

static func checkpoint_for_current_run(g, path: String = CHECKPOINT_PATH, adopt_neutral := false) -> Dictionary:
	var run_id := current_run_id(g)
	var d := read_slot(path, SLOT_CHECKPOINT)
	if not run_selected:
		if d.is_empty(): return {}
		if not validate(d, g):
			last_error = "チェックポイントを検証できません。現在の進行は変更しません。"
			return {}
		if adopt_neutral:
			g.save_run_id = snapshot_run_id(d)
			run_selected = true
			active_checkpoint.clear()
		return d
	if not d.is_empty() and snapshot_run_id(d) == run_id: return d
	if active_checkpoint is Dictionary and not active_checkpoint.is_empty() and snapshot_run_id(active_checkpoint) == run_id:
		return active_checkpoint.duplicate(true)
	if not d.is_empty(): last_error = "別の出撃のチェックポイントは復元できません。途中から続ける場合は同じ出撃の保存を選んでください。"
	return {}

static func paired_checkpoint(d: Dictionary, g) -> Dictionary:
	var value: Variant = d.get("paired_checkpoint", {})
	if not value is Dictionary or value.is_empty(): return {}
	if snapshot_run_id(value) != snapshot_run_id(d) or not validate(value, g): return {}
	return value.duplicate(true)

static func continue_progress(g, d: Dictionary) -> bool:
	var paired := paired_checkpoint(d, g)
	if not apply(g, d): return false
	active_checkpoint = paired
	run_selected = true
	return true

static func restart_from_checkpoint(g, policy: Dictionary = DEFAULT_RESTART_LOSS, path: String = CHECKPOINT_PATH) -> bool:
	var d := checkpoint_for_current_run(g, path, true)
	if d.is_empty(): return false
	var restored := d.duplicate(true)
	var town_state: Dictionary = TownEconomy.normalized(restored.get("town", {}))
	var loss := restart_loss(int(town_state.credits), policy)
	if loss < 0:
		last_error = "再開ペナルティの指定が不正です。"
		return false
	town_state.credits = int(town_state.credits) - loss
	restored.town = town_state
	return apply(g, restored)

static func item_mass(item: int, n := 1) -> int:
	return CargoDB.size_of(item) * n if CargoDB.bay_of(item) >= 0 else 0

static func mass(items: Dictionary) -> int:
	var n := 0
	for it in items: n += item_mass(it,items[it])
	return n

static func saved_weight(d: Dictionary) -> int:
	var n := mass(d.inventory) + mass(d.stock)
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
	var town:Dictionary = TownEconomy.normalized(d.get("town",{}))
	if town.get("delivery","")=="outbound" and town.get("delivery_cargo",false): n += TownDB.DELIVERY_PARCEL_WEIGHT
	if town.get("recovery","") in ["carried","return","ready"]: n += TownDB.RECOVERY_PARCEL_WEIGHT
	return n

static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)

static func slot_path(slot: String) -> String:
	return CHECKPOINT_PATH if slot == SLOT_CHECKPOINT else PROGRESS_PATH

static func read_slot(path: String, slot: String) -> Dictionary:
	if (path == CHECKPOINT_PATH and slot != SLOT_CHECKPOINT) or (path == PROGRESS_PATH and slot != SLOT_PROGRESS):
		last_error = "別の保存枠のデータです。"
		return {}
	var d := read(path)
	if d.is_empty(): return {}
	return d

## 旧 user://save.json は途中経過として扱う。新スロットがまだ無い環境だけで使う。
static func read_progress() -> Dictionary:
	if exists(PROGRESS_PATH): return read_slot(PROGRESS_PATH, SLOT_PROGRESS)
	return read(PATH)

static func ensure_initial_checkpoint(g, force_new := false) -> bool:
	if disabled: return true
	if not force_new and (exists(CHECKPOINT_PATH) or exists(PROGRESS_PATH) or exists(PATH)): return true
	# 旧単一セーブは read_progress() から継続でき、元ファイルを変更しない。
	# 新しい checkpoint は現在起動中の初期状態から作る。
	return write_checkpoint(g, true)

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

static func write(g, path: String = PATH, overwrite := false, slot := "", snapshot: Variant = null) -> bool:
	if g.game_over: last_error = "ゲーム終了状態は保存できません。"; return false
	if disabled: last_error = "検証モードではプレイヤーの保存は無効です。"; return false
	var paused: bool = g.get_tree().paused
	g.get_tree().paused = true
	var d: Dictionary = capture(g) if snapshot == null else snapshot.duplicate(true)
	var valid := validate(d,g)
	g.get_tree().paused = paused
	if not valid: last_error = "保存状態を検証できません。既存の保存は変更しません。"; return false
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

static func write_progress(g, overwrite := false, path: String = PROGRESS_PATH) -> bool:
	var progress := capture(g)
	var paired := checkpoint_for_current_run(g)
	if not paired.is_empty() and snapshot_run_id(paired) == snapshot_run_id(progress): progress["paired_checkpoint"] = paired
	return write(g, path, overwrite, SLOT_PROGRESS, progress)

static func write_checkpoint(g, overwrite := true) -> bool:
	return write(g, CHECKPOINT_PATH, overwrite, SLOT_CHECKPOINT)


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
