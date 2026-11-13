class_name RecoveryRouteConnectionSession
extends RefCounted
## A地域の横視点と固定クォータービューの間だけに存在する接続台帳。
## 本編 Worker / BaseStorage / WorldTrip を置き換えず、現地の一時状態だけを一元化する。

const SCHEMA_VERSION := 11
const ResourceGrowth = preload("res://bridge/c_resource_regeneration.gd")
const RescueLedger = preload("res://bridge/c_quarry_rescue_ledger.gd")
const MineRescueTraces = preload("res://bridge/c_quarry_mine_rescue_traces.gd")
const ExpiredRecovery = preload("res://bridge/c_quarry_expired_recovery.gd")
const RescueApproach = preload("res://bridge/c_quarry_rescue_approach.gd")
const SITE_ID := "c_quarry"
const SOURCE_KEY := "region:c_quarry"
const TEST_ROOT_URI := "res://prototypes/recovery_map_lab/results/route_connection_runtime"
const GUI_STATE_FILE := "gui_route_session.json"
const WORK_SECONDS := 0.75
const DOCK_SECONDS := 0.35
const MOVE_SPEED := 230.0

## Opt-in C-quarry vertical-slice timing.  These are deliberately session-only
## knobs so the later map/vehicle art pass can tune them without changing the
## normal WorldTrip or save schema.
const PARKING_ENTRY := "entry"
const PARKING_RELAY := "relay"
const VERTICAL_ENTRY_ONE_WAY_SECONDS := 24.0
const VERTICAL_RELAY_ONE_WAY_SECONDS := 14.0
const VERTICAL_MAINTENANCE_SECONDS := 3.0
const VERTICAL_REPOSITION_SECONDS := 2.0
const UNLIMITED_FIELD_WEIGHT := 1000000000

## v18 is intentionally a one-slot, small-tool proof rather than a second
## inventory UI.  These values are data-like constants so the later loadout
## pass can change the representative pair without changing the transaction.
const FIELD_TOOL_KIT_ROLE := "harvest"
const FIELD_TOOL_KIT_SLOT := "mine"
const FIELD_TOOL_KIT_ENTRY_ITEM := GameData.Item.HAMMER
const FIELD_TOOL_KIT_CARRIED_ITEM := GameData.Item.PICKAXE
const FIELD_TOOL_KIT_MAX_SLOTS := 1
const FIELD_TOOL_MIN_DURATION_FACTOR := 0.5
const FIELD_TOOL_MAX_DURATION_FACTOR := 2.0

const BASE := Vector2(150, 535)
const RELAY := Vector2(490, 405)
const GATE := Vector2(700, 325)
const BYPASS := Vector2(700, 535)
const RESOURCE := Vector2(1030, 235)
## One C-quarry route-engineering proof. These session-authoritative waypoints
## are mirrored by CanyonTerrain but never selected there.
const MINE_PATH_STEP := Vector2(430, 335)
const MINE_PATH_CART_DETOUR_ENTRY := Vector2(270, 650)
const MINE_PATH_CART_DETOUR := Vector2(650, 650)
const MINE_PATH_CART_SHORTCUT := Vector2(500, 445)
const MINE_PATH_RUBBLE := Vector2(500, 445)
## 前哨地は既存の砂漠敵定義を固定配置するだけの最小検証範囲。
## 新しい敵種、戦利品、戦闘数値は作らない。
const OUTPOST_KIND := WorldTrip.C_OUTPOST_KIND
const OUTPOST_COVER := Vector2(810, 430)

var session_id := ""
var phase := "local" # local / recall / ready_to_exit / committed
var elapsed := 0.0
var life_clock_paid := 0.0
var life_clock_token := ""
var entry_director_elapsed := 0.0
var actors := {} # bridge id -> JSON-safe actor state
## Live rescue movement and entrance treatment handoff; normal AI waits for commit.
var rescue_ledger := RescueLedger.new()
var rescue_approach := RescueApproach.new()
var expired_recovery := ExpiredRecovery.new()
var mine_rescue_traces := MineRescueTraces.new()
var resources := {} # WorldTrip entity id -> {item, initial, remaining, reservation}
var relay_stock := {}
var depot_stock := {}
var dock_queue: Array = []
var dock_busy := {}
var reservations := {}
var dock_count := 1
var gate_closed := false
var all_routes_closed := false
var route_revision := 0
var path_requests := 0
var committed := false
var commit_summary := {}
var event_log: Array = []
var encounter_id := "" # Empty keeps the original optional three-enemy outpost.
var encounter_entry := {} # Return baseline: a stale sortie cannot overwrite newer progress.
var outpost_enabled := false
var outpost_enemies := {} # Local combat; only successful return copies it to WorldTrip.
var outpost_cleared := true
var outpost_retreats := 0
## Explicit verification-only workflow.  The normal harvest/carry/escort
## assignment remains the default; this mode lets one real actor use the
## existing resource and dock authority end-to-end for a readable demo.
var single_worker_demo := false
var single_worker_actor_id := ""
## Narrow normal-C proof: fixed base, backpack step route, cart detour, then
## a cart-only shortcut after an explicit rubble-clearing job.
var mine_path_engineering := false
## The vertical slice keeps its parking/cargo accounting inside the bridge
## session.  Nothing here writes the player's BaseStorage until commit.
var vertical_slice := false
var parking_slot := PARKING_ENTRY
var intermediate_access := "blocked" # blocked / clearing / cleared
var maintenance_actor_id := ""
var reposition_target_slot := ""
var reposition_seconds_left := 0.0
var _commit_in_progress := false
const NORMAL_CAPACITY_WAIT := "積載予算不足。帰還して売却・補給してください"
var field_capacity_limit_weight := UNLIMITED_FIELD_WEIGHT
var capacity_paused := false
## A real existing Haul Frame can change hands inside the isolated C session.
## It never changes BaseStorage until the later safe return commit.
var field_frame_exchange := {}
## A depot-only Handcart is never created in the field.  The player may only
## reserve its exchange; commit performs it after the whole crew has returned.
var return_handcart_exchange := {}
## A real small tool is removed from BaseStorage only at vertical-session
## entry.  The record is a same-actor swap request; it never authorizes a
## cross-worker tool handoff or a live Main worker mutation.
var field_tool_swap := {}

## Current prototype boundary, not a permanent equipment rule: the boss
## approach has no authenticated handcart return. Only active escorts take it.
static func boss_loadout_reason(game) -> String:
	for index in game.workers.size():
		var worker = game.workers[index]
		if index % 3 == 2 and not worker.down and worker.hp > FieldOperations.RETREAT_HP and worker.work_support == GameData.Item.HANDCART:
			return "このボス接近経路では手押し車の安全帰路が未対応です。参加する護衛の手押し車を外して再試行してください。通常採掘では使用できます。"
	return ""

static func create_from_game(game, id: String, options: Dictionary = {}) -> Dictionary:
	if game == null or game.world == null or game.storage == null or game.director == null:
		return {"ok": false, "reason": "本編の仲間・倉庫・時間・WorldTripを取得できません"}
	if not game.world.first_region() or game.world.region != SITE_ID or game.world.phase != "stopped":
		return {"ok": false, "reason": "A地域C 古い採石場に停車してから入場してください"}
	if not game.world.ready_reason().is_empty():
		return {"ok": false, "reason": game.world.ready_reason()}
	if game.world.regeneration_owner != null and not game.world.regeneration_owner.committed:
		return {"ok":false,"reason":"C resource source already has an active owner"}
	var result := new()
	result.session_id = id
	result.entry_director_elapsed = float(game.director.elapsed)
	result.encounter_id = str(options.get("encounter_id", ""))
	if result.encounter_id not in ["",FirstRegionCompletion.ENCOUNTER_ID]:
		return {"ok":false,"reason":"未知の挑戦です"}
	if result.is_region_boss():
		var loadout_reason := boss_loadout_reason(game)
		if not loadout_reason.is_empty():
			return {"ok":false,"reason":loadout_reason}
		if FirstRegionCompletion.boss_returned(game.world.region_completion):
			return {"ok":false,"reason":"採石場の主は撃破・帰還確定済みです。通常の採掘を続けられます。"}
	if result.is_region_boss() or bool(options.get("outpost_enabled", false)):
		var ready_escort := false
		for index in game.workers.size():
			if index % 3 == 2 and not game.workers[index].down and game.workers[index].hp > FieldOperations.RETREAT_HP:
				ready_escort = true
		if not ready_escort:
			return {"ok":false,"reason":"挑戦できる護衛がいません。負傷した護衛は拠点で休憩し、HP30を超えてから再挑戦してください。"}
	result.outpost_enabled = bool(options.get("outpost_enabled", false)) or result.is_region_boss()
	result.single_worker_demo = bool(options.get("single_worker_demo", false))
	result.vertical_slice = bool(options.get("vertical_slice", false))
	result.mine_path_engineering = bool(options.get("mine_path_engineering", false)) or result.is_region_boss()
	if result.vertical_slice and (result.outpost_enabled or result.single_worker_demo):
		return {"ok": false, "reason": "中継停車の縦切りは前哨地・単独追跡を同時に開始できません"}
	if result.single_worker_demo and result.outpost_enabled:
		return {"ok": false, "reason": "単独追跡検証は前哨地なしのC資源で開始してください"}
	if result.mine_path_engineering and (result.vertical_slice or (result.outpost_enabled and not result.is_region_boss()) or result.single_worker_demo):
		return {"ok": false, "reason": "Mine path engineering cannot combine with the vertical, outpost, or solo fixture."}
	if result.mine_path_engineering:
		result.intermediate_access = "cleared" if bool(options.get("cart_shortcut_cleared", false)) else "blocked"
	if result.single_worker_demo and game.workers.is_empty():
		return {"ok": false, "reason": "単独追跡検証に必要な既存仲間がいません"}
	result.single_worker_actor_id = "worker:0" if result.single_worker_demo else ""
	# The focused proof must traverse the visibly modeled short bridge; normal
	# role sessions retain their caller-selected gate state.
	result.gate_closed = result.single_worker_demo
	result.outpost_cleared = not result.outpost_enabled
	if result.outpost_enabled:
		result._setup_outpost()
		if not result._restore_committed_outpost_state(game):
			return {"ok":false,"reason":"保存された前哨地状態を検証できません"}
	for index in game.workers.size():
		var worker = game.workers[index]
		# Do not suspend an existing normal rescue/recovery owner by assigning
		# this person a fresh C role. Reentry is available once that owner ends.
		if game.operations != null and (game.operations.rescue_cases.has(str(index)) or not game.operations.rescue_carrier_phase(worker).is_empty()):
			return {"ok": false, "reason": "本編の救助・治療中の仲間は、回復してから採石場へ入場してください"}
		# A downed companion cannot move, clear rubble, or complete a recall.
		# Refuse entry before the bridge takes ownership instead of creating an
		# unrecoverable engineering session with a frozen escort.
		if bool(worker.down):
			return {"ok": false, "reason": "A downed companion must recover before entering the quarry."}
		if worker.carrying >= 0 or not worker.carry_bonus.is_empty() or worker.away:
			return {"ok": false, "reason": "仲間の手持ち・予約・遠征を解消してから入場してください"}
		var key := "worker:%d" % index
		var single_demo_actor := result.single_worker_demo and key == result.single_worker_actor_id
		var role: String = "solo" if single_demo_actor else ["harvest", "carry", "escort"][index % 3]
		var initial_state := "to_resource" if role in ["harvest", "solo"] else ("wait_relay" if role == "carry" else "escort")
		# The engineering proof starts the carrier with a physical base-to-relay
		# leg, so it cannot pick up relay cargo without traversing the corridor.
		if result.mine_path_engineering and role == "carry":
			initial_state = "to_relay"
		if result.single_worker_demo and not single_demo_actor:
			initial_state = "idle"
		if result.outpost_enabled and role == "harvest":
			initial_state = "outpost_wait"
		elif result.outpost_enabled and role == "escort":
			initial_state = "injured_return" if worker.hp <= FieldOperations.RETREAT_HP else "outpost_move"
		result.actors[key] = {
			"worker_index": index,
			"name": str(worker.char_name),
			"role": role,
			"weapon": int(worker.weapon),
			"entry_weapon": int(worker.weapon),
			"work_support": int(worker.work_support),
			"entry_work_support": int(worker.work_support),
			"tools": worker.tools.duplicate(true),
			"entry_tools": worker.tools.duplicate(true),
			"field_tool_kit": {},
			"entry_field_tool_kit": {},
			"entry_gather_rank": int(worker.ranks.get(GameData.Field.GATHERER, 0)),
			"entry_gather_ability": float(worker.field_mult(GameData.Field.GATHERER)),
			"carry_limit": maxi(1, int(worker.carry_limit())),
			"entry_hp": float(worker.hp),
			"entry_fatigue": float(worker.fatigue),
			"entry_stress": float(worker.stress),
			"hp": float(worker.hp),
			"fatigue": float(worker.fatigue),
			"hunger": float(worker.hunger),
			"calm": float(worker.calm),
			"mental": int(worker.mental),
			"stress": float(worker.stress),
			"down": bool(worker.down),
			"attack_per_second": float(CharacterAI.ATTACK_DPS * worker.skill_mult(GameData.Job.COMBAT) * worker.weapon_mult()),
			"weapon_range": float(worker.weapon_range()),
			"x": BASE.x + float(index) * 28.0,
			"y": BASE.y + float(index % 2) * 20.0,
			"state": initial_state,
			"path": [],
			"path_index": 0,
			"seen_route_revision": -1,
			"carry_item": -1,
			"carry_n": 0,
			"resource_id": "",
			"work_left": 0.0,
			"wait_reason": "",
			"resume_state": "",
			"combat_target": "",
			"route": "",
			"direct_depot_loop": single_demo_actor,
			"presentation_hidden": result.single_worker_demo and not single_demo_actor,
		}
	if not game.world.locations.get(SOURCE_KEY,{}).is_empty():game.world.sync()
	var source: Dictionary = game.world.locations.get(SOURCE_KEY, {})
	for entity_id in source:
		var row: Dictionary = source[entity_id]
		if row.get("type", "") != "gather":
			continue
		var data: Dictionary = row.get("data", {})
		var remaining := int(data.get("remaining", 0))
		var item := int(data.get("item", -1))
		if entity_id is String and item >= 0 and (remaining > 0 or row.has("regeneration")):
			result.resources[entity_id] = {
				"item": item,
				"kind": str(data.get("kind", "")),
				"initial": remaining,
				"remaining": remaining,
				"reservation": "",
			}
			ResourceGrowth.add_metadata(result.resources[entity_id],row)
	# Depleted ordinary IDs remain available for regeneration. A truly missing
	# source ledger cannot be reseeded by entry; the old cleared inspection
	# exception remains a cargo-free inspection.
	if result.resources.is_empty() and not (result.mine_path_engineering and result.intermediate_access == "cleared"):
		return {"ok": false, "reason": "C 古い採石場に搬出可能な有限資源がありません"}
	result._log("C 古い採石場へ既存仲間%d人で入場" % result.actors.size())
	if result.mine_path_engineering:
		result._capture_field_capacity(game)
	if result.vertical_slice:
		result._capture_field_capacity(game)
		result._stage_default_field_tool_kit(game)
		result._log("縦切り: 入口停車、資源地まで%.0f秒基準。小障害物整備で中継停車を解放" % VERTICAL_ENTRY_ONE_WAY_SECONDS)
	for actor_id in result.actors:
		if result.is_region_boss() and result.actors[actor_id].state=="outpost_move":
			result.actors[actor_id].combat_target=result._claim_outpost_enemy(actor_id)
		result._refresh_actor_path(actor_id)
		if result.mine_path_engineering: result.mine_rescue_traces.anchor_actor(result, actor_id)
	return {"ok": true, "session": result}

func is_vertical_slice() -> bool:
	return vertical_slice

func is_mine_path_engineering() -> bool:
	return mine_path_engineering

## Read-only overhead-guide data for the one-quarry route comparison.  Route
## selection and rubble work remain owned by the normal actor/session methods.
func mine_path_guide_snapshot() -> Dictionary:
	var access := intermediate_access if mine_path_engineering else "unavailable"
	var shortcut_open := access == "cleared"
	return {
		"fixed_entry": mine_path_engineering,
		"backpack_step": mine_path_engineering,
		"cart_detour": mine_path_engineering,
		"cart_shortcut": shortcut_open,
		"cart_route": "shortcut" if shortcut_open else "detour",
		"rubble": access,
		"entry": _point_array(BASE),
		"resource": _point_array(RESOURCE),
		"backpack_step_point": _point_array(MINE_PATH_STEP),
		"cart_detour_entry": _point_array(MINE_PATH_CART_DETOUR_ENTRY),
		"cart_detour_point": _point_array(MINE_PATH_CART_DETOUR),
		"cart_shortcut_point": _point_array(MINE_PATH_CART_SHORTCUT),
		"rubble_point": _point_array(MINE_PATH_RUBBLE),
	}

func parking_anchor() -> Vector2:
	return BASE

func vertical_slice_profile() -> Dictionary:
	var active_seconds := VERTICAL_ENTRY_ONE_WAY_SECONDS
	return {
		"parking_slot": parking_slot,
		"parking_anchor": _point_array(parking_anchor()),
		"entry_one_way_seconds": VERTICAL_ENTRY_ONE_WAY_SECONDS,
		"relay_one_way_seconds": VERTICAL_ENTRY_ONE_WAY_SECONDS,
		"relocation_enabled": false,
		"active_one_way_seconds": active_seconds,
		"maintenance_seconds": VERTICAL_MAINTENANCE_SECONDS,
		"reposition_seconds": VERTICAL_REPOSITION_SECONDS,
		"intermediate_access": intermediate_access,
		"capacity_limit_weight": field_capacity_limit_weight,
		"capacity_used_weight": _field_payload_weight(),
		"capacity_paused": capacity_paused,
	}

## Read-only command state for the compact field HUD.  It deliberately does
## not expose Main inventory or mutate actor/session authority.
func equipment_status() -> Dictionary:
	var field_row := {"status": "none"}
	if not field_frame_exchange.is_empty():
		field_row = field_frame_exchange.duplicate(true)
	var return_row := {"status": "none"}
	if not return_handcart_exchange.is_empty():
		return_row = return_handcart_exchange.duplicate(true)
	return {"field_frame": field_row, "return_handcart": return_row, "field_tool": field_tool_status()}


## The departure loadout is deliberately small and explicit: the harvest actor
## may take one real existing PICKAXE only when already wearing the paired
## HAMMER.  Missing stock is a readable no-kit state, not a creation failure or
## a remote item grant.
func _stage_default_field_tool_kit(game) -> Dictionary:
	if not vertical_slice:
		return {"ok": true, "staged": false}
	var actor_id := _first_actor_with_role(FIELD_TOOL_KIT_ROLE)
	if actor_id.is_empty() or not actors.has(actor_id):
		return {"ok": false, "reason": "携行採掘具を持つ採掘役がいません"}
	var actor: Dictionary = actors[actor_id]
	var tools: Dictionary = Dictionary(actor.get("tools", {}))
	if int(tools.get(FIELD_TOOL_KIT_SLOT, -1)) != FIELD_TOOL_KIT_ENTRY_ITEM:
		return {"ok": true, "staged": false, "reason": "採掘役が石のハンマーを装備していないため予備ピッケルを積みません"}
	if game == null or game.storage == null or not game.storage.has_method("take_item") or not game.storage.has_method("count_of"):
		return {"ok": false, "reason": "基地倉庫を確認できないため予備採掘具を積めません"}
	if int(game.storage.count_of(FIELD_TOOL_KIT_CARRIED_ITEM)) <= 0:
		return {"ok": true, "staged": false, "reason": "基地に携行可能な鉄製ピッケルがありません"}
	if not bool(game.storage.take_item(FIELD_TOOL_KIT_CARRIED_ITEM)):
		return {"ok": false, "reason": "基地から予備採掘具を取り出せません"}
	actor["field_tool_kit"] = {FIELD_TOOL_KIT_SLOT: FIELD_TOOL_KIT_CARRIED_ITEM}
	actor["entry_field_tool_kit"] = {FIELD_TOOL_KIT_SLOT: FIELD_TOOL_KIT_CARRIED_ITEM}
	_log("%s が基地在庫の鉄製ピッケル1本を予備携行" % actor_id)
	return {"ok": true, "staged": true, "actor_id": actor_id, "item": FIELD_TOOL_KIT_CARRIED_ITEM}


## Read-only row for the compact vertical HUD.  It reads actor snapshots, not
## hidden Main workers, so the identity guard remains valid during field play.
func field_tool_status() -> Dictionary:
	var actor_id := _first_actor_with_role(FIELD_TOOL_KIT_ROLE)
	var row := {"status": "none", "actor_id": actor_id, "slot": FIELD_TOOL_KIT_SLOT, "equipped_item": -1, "carried_item": -1, "reason": ""}
	if actor_id.is_empty() or not actors.has(actor_id):
		row["reason"] = "採掘役がいません"
		return row
	var actor: Dictionary = actors[actor_id]
	row["equipped_item"] = int(Dictionary(actor.get("tools", {})).get(FIELD_TOOL_KIT_SLOT, -1))
	row["carried_item"] = int(Dictionary(actor.get("field_tool_kit", {})).get(FIELD_TOOL_KIT_SLOT, -1))
	if not field_tool_swap.is_empty():
		row = field_tool_swap.duplicate(true)
		row["equipped_item"] = int(Dictionary(actor.get("tools", {})).get(FIELD_TOOL_KIT_SLOT, -1))
		row["carried_item"] = int(Dictionary(actor.get("field_tool_kit", {})).get(FIELD_TOOL_KIT_SLOT, -1))
		return row
	row["reason"] = _field_tool_swap_reason(actor_id)
	return row


## Field UI requests a same-actor tool transaction.  Work and cargo continue
## until the harvest role has reached the relay and deposited its current bag.
func request_field_tool_swap() -> Dictionary:
	if not field_tool_swap.is_empty() and str(field_tool_swap.get("status", "")) == "scheduled":
		return {"ok": true, "already_scheduled": true, "actor_id": str(field_tool_swap.get("actor_id", ""))}
	if not field_tool_swap.is_empty() and (not _field_tool_swap_valid() or not _field_tool_maps_authorized()):
		return {"ok": false, "reason": "携行採掘具の所有者記録が一致しません"}
	var actor_id := _first_actor_with_role(FIELD_TOOL_KIT_ROLE)
	var reason := _field_tool_swap_reason(actor_id)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	_record_field_tool_state(actor_id, "scheduled")
	_log("%s の携行採掘具を次の中継・空荷時に交換予約" % actor_id)
	return {"ok": true, "actor_id": actor_id}


func cancel_field_tool_swap() -> Dictionary:
	if field_tool_swap.is_empty() or str(field_tool_swap.get("status", "")) != "scheduled":
		return {"ok": false, "reason": "取消できる携行採掘具交換予約がありません"}
	_cancel_field_tool_swap("プレイヤーが携行採掘具交換を取消")
	return {"ok": true}


func _cancel_field_tool_swap(note: String) -> void:
	if field_tool_swap.is_empty() or str(field_tool_swap.get("status", "")) != "scheduled":
		return
	var actor_id := str(field_tool_swap.get("actor_id", ""))
	if actor_id.is_empty() or not actors.has(actor_id) or _field_tool_pair_is_entry(Dictionary(actors[actor_id])):
		field_tool_swap.clear()
	else:
		# A later reverse request may be cancelled while the actor still has the
		# first completed change.  Preserve that legitimate ownership state rather
		# than clearing its authorization record.
		_record_field_tool_state(actor_id, "completed")
	_log(note)


## The adapter normally leaves the field only through commit.  If a field view
## is destroyed before that boundary, return the staged real tools to the same
## BaseStorage while the live Workers still retain their entry tools.  This is
## a cleanup transaction, not a second way to equip tools in the field.
func release_uncommitted_field_tool_kits(game) -> Dictionary:
	if committed:
		return {"ok": true, "already_committed": true}
	if game == null or game.storage == null or not game.storage.has_method("store_owned"):
		return {"ok": false, "reason": "未確定の携行採掘具を返す基地倉庫を確認できません"}
	var returned := {}
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		# Current kit contents may be the actor's entry Hammer after a completed
		# field swap.  The only external item that this uncommitted session owns is
		# its immutable departure kit (the staged Pickaxe), while the live Worker
		# still owns its entry tool.  Return that departure kit, not the mutable
		# current pocket, so abandoning the field cannot duplicate the Hammer or
		# lose the staged Pickaxe.
		var kit: Dictionary = Dictionary(actor.get("entry_field_tool_kit", {}))
		for slot in kit:
			var item := int(kit[slot])
			returned[item] = int(returned.get(item, 0)) + 1
		actor["field_tool_kit"] = {}
		actor["entry_field_tool_kit"] = {}
	field_tool_swap.clear()
	for item in returned:
		game.storage.store_owned(int(item), int(returned[item]), Inventory.SOURCE_TRANSFER)
	if not returned.is_empty():
		_log("未確定の携行採掘具を基地倉庫へ返却")
	return {"ok": true, "returned": returned.duplicate(true)}


func has_reserved_field_tool_kits() -> bool:
	for actor_id in actors:
		if not Dictionary(actors[actor_id].get("field_tool_kit", {})).is_empty():
			return true
	return false


func _field_tool_swap_reason(actor_id: String) -> String:
	if not vertical_slice:
		return "携行採掘具の現地交換は中継停車縦切りでのみ利用できます"
	if phase != "local":
		return "移動・撤退中は携行採掘具を交換できません"
	if capacity_paused:
		return "満載の保持貨物を先に収納してください"
	if actor_id.is_empty() or not actors.has(actor_id):
		return "採掘役がいません"
	var actor: Dictionary = actors[actor_id]
	if bool(actor.get("down", false)) or (rescue_approach.owns(actor_id) or expired_recovery.owns(actor_id)):
		return "戦闘不能または救助中の採掘役は装備を交換できません"
	var equipped_item := int(Dictionary(actor.get("tools", {})).get(FIELD_TOOL_KIT_SLOT, -1))
	var carried_item := int(Dictionary(actor.get("field_tool_kit", {})).get(FIELD_TOOL_KIT_SLOT, -1))
	if not _field_tool_pair_supported(equipped_item, carried_item):
		return "採掘役の装備と携行が交換可能な石のハンマー／鉄製ピッケルではありません"
	return ""


func _field_tool_pair_supported(equipped_item: int, carried_item: int) -> bool:
	return (equipped_item == FIELD_TOOL_KIT_ENTRY_ITEM and carried_item == FIELD_TOOL_KIT_CARRIED_ITEM) or (equipped_item == FIELD_TOOL_KIT_CARRIED_ITEM and carried_item == FIELD_TOOL_KIT_ENTRY_ITEM)


func _field_tool_pair_is_entry(actor: Dictionary) -> bool:
	return int(Dictionary(actor.get("tools", {})).get(FIELD_TOOL_KIT_SLOT, -1)) == FIELD_TOOL_KIT_ENTRY_ITEM and int(Dictionary(actor.get("field_tool_kit", {})).get(FIELD_TOOL_KIT_SLOT, -1)) == FIELD_TOOL_KIT_CARRIED_ITEM


func _record_field_tool_state(actor_id: String, status: String) -> void:
	if actor_id.is_empty() or not actors.has(actor_id):
		field_tool_swap.clear()
		return
	var actor: Dictionary = actors[actor_id]
	field_tool_swap = {
		"status": status,
		"actor_id": actor_id,
		"slot": FIELD_TOOL_KIT_SLOT,
		"equipped_item": int(Dictionary(actor.get("tools", {})).get(FIELD_TOOL_KIT_SLOT, -1)),
		"carried_item": int(Dictionary(actor.get("field_tool_kit", {})).get(FIELD_TOOL_KIT_SLOT, -1)),
	}


func _field_tool_swap_waiting_for(actor_id: String) -> bool:
	return not field_tool_swap.is_empty() and str(field_tool_swap.get("status", "")) == "scheduled" and str(field_tool_swap.get("actor_id", "")) == actor_id


func _complete_field_tool_swap_at_relay(actor_id: String) -> bool:
	if not _field_tool_swap_waiting_for(actor_id) or phase != "local" or capacity_paused or not actors.has(actor_id):
		return false
	var actor: Dictionary = actors[actor_id]
	if int(actor.get("carry_n", 0)) > 0 or not str(actor.get("resource_id", "")).is_empty() or bool(actor.get("down", false)):
		return false
	var reason := _field_tool_swap_reason(actor_id)
	if not reason.is_empty() or not _field_tool_swap_valid():
		_cancel_field_tool_swap("中継で携行採掘具を確認できないため予約を取消")
		return false
	var tools: Dictionary = Dictionary(actor.get("tools", {})).duplicate(true)
	var kit: Dictionary = Dictionary(actor.get("field_tool_kit", {})).duplicate(true)
	var equipped_item := int(tools.get(FIELD_TOOL_KIT_SLOT, -1))
	var carried_item := int(kit.get(FIELD_TOOL_KIT_SLOT, -1))
	tools[FIELD_TOOL_KIT_SLOT] = carried_item
	kit[FIELD_TOOL_KIT_SLOT] = equipped_item
	actor["tools"] = tools
	actor["field_tool_kit"] = kit
	_record_field_tool_state(actor_id, "completed")
	_log("中継で%s本人が%s→%sへ携行採掘具を交換" % [actor_id, str(GameData.ITEM_NAMES.get(equipped_item, "採掘具")), str(GameData.ITEM_NAMES.get(carried_item, "採掘具"))])
	return true

## The initial field path is deliberately role-specific: the escort carries
## an existing frame to relay, then hands it to the unladen harvest role.
## This produces a visible next-harvest 3→5 effect without inventing a second
## field inventory or rewriting C-quarry gathering rules.
func request_field_frame_to_harvest() -> Dictionary:
	if not vertical_slice:
		return {"ok": false, "reason": "現地装備引渡しは中継停車縦切りでのみ利用できます"}
	if phase != "local":
		return {"ok": false, "reason": "停め直し・帰還中は現地装備を引渡せません"}
	if capacity_paused:
		return {"ok": false, "reason": "満載の保持貨物を先に収納してください"}
	if intermediate_access == "clearing":
		return {"ok": false, "reason": "小障害物を整備中のため現地フレーム引渡しを予約できません"}
	if _source_depleted():
		return {"ok": false, "reason": "指定鉱床が枯渇しているため現地引渡しを開始しません"}
	if not field_frame_exchange.is_empty():
		if str(field_frame_exchange.get("status", "")) == "scheduled":
			return {"ok": true, "already_scheduled": true}
		return {"ok": false, "reason": "この出撃では背負いフレームを既に引渡しました"}
	var source_id := _first_actor_with_role("escort")
	var target_id := _first_actor_with_role("harvest")
	if source_id.is_empty() or target_id.is_empty() or not actors.has(source_id) or not actors.has(target_id):
		return {"ok": false, "reason": "護衛役と採取役の既存編成が必要です"}
	var source: Dictionary = actors[source_id]
	var target: Dictionary = actors[target_id]
	if bool(source.get("down", false)) or bool(target.get("down", false)) or (rescue_approach.owns(source_id) or expired_recovery.owns(source_id)) or (rescue_approach.owns(target_id) or expired_recovery.owns(target_id)):
		return {"ok": false, "reason": "戦闘不能または救助中の仲間は装備を引渡せません"}
	if int(source.get("work_support", -1)) != GameData.Item.HAUL_FRAME:
		return {"ok": false, "reason": "護衛役が携行済みの背負いフレームを持っていません"}
	if int(target.get("work_support", -1)) >= 0:
		return {"ok": false, "reason": "採取役は既に仕事補助を装備しています"}
	field_frame_exchange = {
		"status": "scheduled",
		"source_id": source_id,
		"target_id": target_id,
		"support": GameData.Item.HAUL_FRAME,
	}
	source["state"] = "field_exchange_move"
	source["wait_reason"] = "背負いフレームを中継へ携行中"
	_refresh_actor_path(source_id)
	_log("%s の背負いフレームを次の中継で%sへ引渡し予約" % [source_id, target_id])
	return {"ok": true, "source_id": source_id, "target_id": target_id}

func cancel_field_frame_exchange() -> Dictionary:
	if field_frame_exchange.is_empty() or str(field_frame_exchange.get("status", "")) != "scheduled":
		return {"ok": false, "reason": "取消できる現地フレーム引渡しがありません"}
	_cancel_field_frame_exchange("プレイヤーが現地フレーム引渡しを取消")
	return {"ok": true}


## 重い手押し車は基地保管品として扱う。ここでは実在を確認して
## 帰還後の交換だけを予約し、在庫・actor・本編 Worker を変えない。
func request_return_handcart_exchange(game) -> Dictionary:
	if not vertical_slice:
		return {"ok": false, "reason": "帰還時の手押し車交換は中継停車縦切りでのみ利用できます"}
	if phase != "local":
		return {"ok": false, "reason": "移動・撤退中は手押し車交換を予約できません"}
	if capacity_paused:
		return {"ok": false, "reason": "満載の保持貨物を先に収納してください"}
	if not return_handcart_exchange.is_empty():
		if str(return_handcart_exchange.get("status", "")) == "reserved":
			return {"ok": true, "already_reserved": true}
		return {"ok": false, "reason": "この出撃では手押し車交換を既に確定しました"}
	if game == null or game.storage == null or not "workers" in game:
		return {"ok": false, "reason": "基地倉庫を確認できないため手押し車を予約できません"}
	var target_id := _first_actor_with_role("carry")
	if target_id.is_empty() or not actors.has(target_id):
		return {"ok": false, "reason": "手押し車を帰還交換する運搬役がいません"}
	var target: Dictionary = actors[target_id]
	if bool(target.get("down", false)) or (rescue_approach.owns(target_id) or expired_recovery.owns(target_id)):
		return {"ok": false, "reason": "戦闘不能または救助中の運搬役の手押し車交換は予約しません"}
	var worker_index := int(target.get("worker_index", -1))
	if worker_index < 0 or worker_index >= game.workers.size():
		return {"ok": false, "reason": "運搬役の本編仲間を確認できません"}
	if int(target.get("work_support", -1)) == GameData.Item.HANDCART:
		return {"ok": true, "already_equipped": true}
	if not game.has_method("work_support_swap_reason"):
		return {"ok": false, "reason": "基地の仕事補助交換APIを確認できません"}
	var reason := str(game.work_support_swap_reason(game.workers[worker_index], GameData.Item.HANDCART))
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	return_handcart_exchange = {
		"status": "reserved",
		"target_id": target_id,
		"item": GameData.Item.HANDCART,
	}
	_log("%s の手押し車を帰還後に基地交換予約" % target_id)
	return {"ok": true, "target_id": target_id}


func cancel_return_handcart_exchange() -> Dictionary:
	if return_handcart_exchange.is_empty() or str(return_handcart_exchange.get("status", "")) != "reserved":
		return {"ok": false, "reason": "取消できる手押し車交換予約がありません"}
	_cancel_return_handcart_exchange("プレイヤーが手押し車の帰還交換予約を取消")
	return {"ok": true}


func _cancel_return_handcart_exchange(note: String) -> void:
	if return_handcart_exchange.is_empty() or str(return_handcart_exchange.get("status", "")) != "reserved":
		return
	return_handcart_exchange.clear()
	_log(note)

func _cancel_field_frame_exchange(note: String) -> void:
	if field_frame_exchange.is_empty() or str(field_frame_exchange.get("status", "")) != "scheduled":
		return
	var source_id := str(field_frame_exchange.get("source_id", ""))
	var target_id := str(field_frame_exchange.get("target_id", ""))
	field_frame_exchange.clear()
	for actor_id in [source_id, target_id]:
		if actor_id.is_empty() or not actors.has(actor_id):
			continue
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("state", "")) not in ["field_exchange_move", "field_exchange_wait"]:
			continue
		var role := str(actor.get("role", ""))
		actor["wait_reason"] = ""
		if capacity_paused:
			actor["state"] = "capacity_idle" if role != "harvest" else "to_base_empty"
		elif role == "harvest":
			actor["state"] = "to_base_empty" if _source_depleted() else "to_resource"
		elif role == "carry":
			actor["state"] = "wait_relay"
		else:
			actor["state"] = "escort"
		_refresh_actor_path(actor_id)
	_log(note)

func _field_frame_exchange_waiting_for(actor_id: String) -> bool:
	return not field_frame_exchange.is_empty() and str(field_frame_exchange.get("status", "")) == "scheduled" and str(field_frame_exchange.get("target_id", "")) == actor_id

func _update_field_frame_exchange() -> void:
	if field_frame_exchange.is_empty() or str(field_frame_exchange.get("status", "")) != "scheduled":
		return
	if phase != "local" or capacity_paused:
		_cancel_field_frame_exchange("帰還・停め直し・容量停止を優先して現地フレーム引渡しを取消")
		return
	var source_id := str(field_frame_exchange.get("source_id", ""))
	var target_id := str(field_frame_exchange.get("target_id", ""))
	if source_id.is_empty() or target_id.is_empty() or not actors.has(source_id) or not actors.has(target_id):
		_cancel_field_frame_exchange("引渡し対象を確認できないため現地フレーム予約を取消")
		return
	var source: Dictionary = actors[source_id]
	var target: Dictionary = actors[target_id]
	if bool(source.get("down", false)) or bool(target.get("down", false)):
		_cancel_field_frame_exchange("戦闘不能を優先して現地フレーム予約を取消")
		return
	if str(source.get("state", "")) != "field_exchange_wait" or str(target.get("state", "")) != "field_exchange_wait":
		return
	if int(source.get("carry_n", 0)) > 0 or int(target.get("carry_n", 0)) > 0 or not str(source.get("resource_id", "")).is_empty() or not str(target.get("resource_id", "")).is_empty():
		return
	if int(source.get("work_support", -1)) != GameData.Item.HAUL_FRAME or int(target.get("work_support", -1)) >= 0:
		_cancel_field_frame_exchange("引渡し時の既存装備が一致しないため現地フレーム予約を取消")
		return
	source["work_support"] = -1
	source["carry_limit"] = GatherDB.CARRY_MAX
	target["work_support"] = GameData.Item.HAUL_FRAME
	target["carry_limit"] = GameData.HAUL_FRAME_LIMIT
	field_frame_exchange["status"] = "completed"
	source["state"] = "escort"
	source["wait_reason"] = ""
	target["state"] = "to_resource"
	target["wait_reason"] = ""
	_refresh_actor_path(source_id)
	_refresh_actor_path(target_id)
	_log("中継で背負いフレームを%sから%sへ引渡し。採取便3→5" % [source_id, target_id])

## Read-only player-facing context for the opt-in parking slice.  Cargo and
## routing remain authority-owned elsewhere; this only explains the next
## decision using the same state that drives the session.
func vertical_slice_brief() -> Dictionary:
	var brief := {
		"available": vertical_slice,
		"kind": "not_vertical",
		"next_action": "",
		"reason": "",
		"parking_slot": parking_slot,
		"active_one_way_seconds": _active_one_way_seconds(),
		"entry_one_way_seconds": VERTICAL_ENTRY_ONE_WAY_SECONDS,
		"relay_one_way_seconds": VERTICAL_ENTRY_ONE_WAY_SECONDS,
		"relocation_enabled": false,
		"saved_one_way_seconds": 0.0,
		"haul_frame": {
			"base_limit": GatherDB.CARRY_MAX,
			"limit": GameData.HAUL_FRAME_LIMIT,
			"requirements": {
				GameData.Item.WOOD: 2,
				GameData.Item.HIDE: 1,
				GameData.Item.IRON: 1,
			},
		},
	}
	if not vertical_slice:
		return brief
	if capacity_paused:
		brief.kind = "capacity_hold"
		brief.next_action = "容量更新後に保持貨物を荷下ろし"
		brief.reason = _first_actor_wait_reason("拠点が満載のため新規採取を停止")
	elif phase == "ready_to_exit":
		brief.kind = "ready_to_exit"
		brief.next_action = "帰還を確定"
		brief.reason = "貨物は一度だけ本編倉庫へ確定できます"
	elif all_routes_closed:
		brief.kind = "all_routes_closed"
		brief.next_action = "再開を待つ（帰還も再開後）"
		brief.reason = "主路と迂回路が閉鎖中"
	elif phase == "reposition_recall":
		brief.kind = "reposition_recall"
		brief.next_action = "現在の貨物だけ帰還して停め直す"
		brief.reason = "地面の未回収資源は残す"
	elif phase == "reposition_travel":
		brief.kind = "reposition_travel"
		brief.next_action = "停め直し中"
		brief.reason = "移動完了まで新規採取を再開しない"
	elif phase == "recall":
		brief.kind = "recall"
		brief.next_action = "手持ち・relay・搬入口を帰還処理"
		brief.reason = _first_actor_wait_reason("帰還処理中")
	elif _source_depleted():
		brief.kind = "depleted"
		brief.next_action = "採取済み貨物を帰還"
		brief.reason = "指定鉱床は枯渇。別鉱床へは移動しない"
	elif gate_closed:
		brief.kind = "bypass"
		brief.next_action = "迂回路で回収を継続"
		brief.reason = "主路閉鎖"
	elif intermediate_access == "clearing":
		brief.kind = "maintenance"
		brief.next_action = "通路の小障害物を整備中"
		brief.reason = _first_actor_wait_reason("拠点は入口固定。通路の整備を実行中")
	elif intermediate_access == "blocked":
		brief.kind = "maintenance"
		brief.next_action = "必要に応じて通路の小障害物を整備"
		brief.reason = "拠点は入口固定。整備による停車変更はありません"
	elif parking_slot == PARKING_RELAY:
		brief.kind = "relay_parked"
		brief.next_action = "中継停車から通常分業を継続"
		brief.reason = "片道14秒（入口より10秒短縮）"
	else:
		brief.kind = "collect"
		brief.next_action = "既存の採掘・運搬・護衛を継続"
		brief.reason = "入口停車から片道24秒"
	return brief

func _first_actor_wait_reason(fallback: String) -> String:
	var actor_ids: Array[String] = []
	for raw_actor_id in actors:
		actor_ids.append(str(raw_actor_id))
	actor_ids.sort()
	for actor_id in actor_ids:
		var reason := str(Dictionary(actors.get(actor_id, {})).get("wait_reason", ""))
		if not reason.is_empty():
			return reason
	return fallback

func _active_one_way_seconds() -> float:
	return VERTICAL_ENTRY_ONE_WAY_SECONDS

func _storage_raw_free_weight(game) -> int:
	if game == null or game.storage == null or not game.storage.limits_active():
		return UNLIMITED_FIELD_WEIGHT
	return int(game.storage.max_weight() - game.storage.current_weight() - game.storage.processing_reserve())

func _storage_free_weight(game) -> int:
	return maxi(0, _storage_raw_free_weight(game))

func _carried_weight() -> int:
	var total := 0
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		total += CargoDB.size_of(int(actor.get("carry_item", -1))) * int(actor.get("carry_n", 0))
	return total

func _depot_weight() -> int:
	var total := 0
	for item in depot_stock:
		total += CargoDB.size_of(int(item)) * int(depot_stock[item])
	return total

func _field_payload_weight() -> int:
	return _carried_weight() + _depot_weight()

func _capture_field_capacity(game) -> void:
	if mine_path_engineering:
		refresh_capacity_from_game(game)
		return
	if not vertical_slice:
		return
	field_capacity_limit_weight = _storage_free_weight(game)
	capacity_paused = field_capacity_limit_weight < UNLIMITED_FIELD_WEIGHT and _field_payload_weight() >= field_capacity_limit_weight

## This is deliberately an explicit event, not a frame-by-frame BaseStorage
## poll.  Projected worker hands already appear in BaseStorage.current_weight,
## while bridge depot cargo does not; adding the bridge hand weight restores
## the true field allowance without double-counting either side.
func refresh_capacity_from_game(game) -> Dictionary:
	if mine_path_engineering:
		var free := _storage_raw_free_weight(game)
		field_capacity_limit_weight = UNLIMITED_FIELD_WEIGHT if free >= UNLIMITED_FIELD_WEIGHT else maxi(0, free + _carried_weight())
		if phase == "local":
			for id in actors:
				var a: Dictionary = actors[id]
				if a.state == "idle" and a.get("wait_reason") == NORMAL_CAPACITY_WAIT and not a.down and a.hp > FieldOperations.RETREAT_HP and a.role == "harvest" and rescue_ledger.case_for(id).is_empty() and not expired_recovery.owns(id) and not rescue_approach.has_mine_return(id):
					for r in resources.values():
						if r.remaining > 0 and normal_collection_room_for(int(r.item)) > 0:
							a.state = "to_resource"; a.wait_reason = ""; _refresh_actor_path(id); break
		return {"ok":true,"limit_weight":field_capacity_limit_weight}
	if not vertical_slice:
		return {"ok": false, "reason": "中継停車縦切りではないため容量を更新しません"}
	var raw_free := _storage_raw_free_weight(game)
	field_capacity_limit_weight = UNLIMITED_FIELD_WEIGHT if raw_free >= UNLIMITED_FIELD_WEIGHT else maxi(0, raw_free + _carried_weight())
	_log("縦切りの拠点容量を明示更新（許容重量%d / 現地%d）" % [field_capacity_limit_weight, _field_payload_weight()])
	if _capacity_is_full():
		_pause_new_collection("拠点容量の変化で新規採取を停止して保持貨物を帰還")
	else:
		_resume_capacity_if_possible()
	return {"ok": true, "limit_weight": field_capacity_limit_weight, "used_weight": _field_payload_weight(), "capacity_paused": capacity_paused}

## Ordinary collection owns ground-depleted cargo in all three locations.
## Unlike the vertical prototype, it never blocks docking already-owned cargo.
func normal_collection_room_for(item: int) -> int:
	if not mine_path_engineering or field_capacity_limit_weight >= UNLIMITED_FIELD_WEIGHT: return UNLIMITED_FIELD_WEIGHT
	var weight := CargoDB.size_of(item)
	var used := _field_payload_weight()
	for relay_item in relay_stock: used += CargoDB.size_of(int(relay_item)) * int(relay_stock[relay_item])
	return maxi(0, floori(float(field_capacity_limit_weight - used) / float(maxi(1, weight))))

func _capacity_is_full() -> bool:
	return vertical_slice and field_capacity_limit_weight < UNLIMITED_FIELD_WEIGHT and _field_payload_weight() >= field_capacity_limit_weight

func _depot_room_for(item: int) -> int:
	if field_capacity_limit_weight >= UNLIMITED_FIELD_WEIGHT:
		return UNLIMITED_FIELD_WEIGHT
	var weight := CargoDB.size_of(item)
	if weight <= 0:
		return UNLIMITED_FIELD_WEIGHT
	return maxi(0, floori(float(field_capacity_limit_weight - _depot_weight()) / float(weight)))

func _pause_new_collection(reason: String) -> void:
	if not vertical_slice:
		return
	_cancel_field_frame_exchange("満載の保持貨物を優先して現地フレーム引渡しを取消")
	_cancel_field_tool_swap("満載の保持貨物を優先して携行採掘具交換を取消")
	capacity_paused = true
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if bool(actor.get("down", false)):
			continue
		var state := str(actor.get("state", ""))
		if state == "to_resource":
			_release_actor_reservation(actor)
			actor["state"] = "to_base_empty"
			actor["wait_reason"] = reason
			_refresh_actor_path(str(actor_id))
		elif state == "idle":
			actor["state"] = "capacity_idle"
			actor["wait_reason"] = reason
		elif state == "escort":
			actor["state"] = "to_base_empty"
			actor["wait_reason"] = reason
			_refresh_actor_path(str(actor_id))

func _resume_capacity_if_possible() -> void:
	if not vertical_slice or not capacity_paused:
		return
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("state", "")) == "capacity_wait" and int(actor.get("carry_n", 0)) > 0:
			_enqueue_dock(str(actor_id))
	if not dock_queue.is_empty() or not dock_busy.is_empty():
		return
	if _capacity_is_full():
		return
	capacity_paused = false
	_log("容量に空きが戻ったため、保持貨物の収納後に元の役割を再開")
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("state", "")) != "capacity_idle":
			continue
		var role := str(actor.get("role", ""))
		actor["wait_reason"] = ""
		actor["state"] = "idle" if _returning_to_parking() else ("to_resource" if role == "harvest" else ("wait_relay" if role == "carry" else "escort"))
		_refresh_actor_path(str(actor_id))

func _log(text: String) -> void:
	event_log.append({"at": elapsed, "text": text})
	if event_log.size() > 30:
		event_log.pop_front()

func is_region_boss() -> bool:
	return encounter_id == FirstRegionCompletion.ENCOUNTER_ID

func _setup_outpost() -> void:
	var spec: Dictionary = EventDB.ENEMIES.get(OUTPOST_KIND, {})
	if spec.is_empty():
		outpost_enabled = false
		outpost_cleared = true
		_log("既存敵定義がないため前哨地を開始しません")
		return
	var layout:Array = [{"id":FirstRegionCompletion.BOSS_ID,"position":FirstRegionCompletion.BOSS_HOME,"lane":FirstRegionCompletion.BOSS_LANE}] if is_region_boss() else WorldTrip.C_OUTPOST_LAYOUT
	for row in layout:
		var enemy_id := str(row.id)
		var position: Vector2 = row.position
		outpost_enemies[enemy_id] = {
			"id": enemy_id,
			"kind": OUTPOST_KIND,
			"lane": str(row.lane),
			"home_x": position.x,
			"home_y": position.y,
			"x": position.x,
			"y": position.y,
			"hp": FirstRegionCompletion.BOSS_HP if is_region_boss() else float(spec.get("hp", 0.0)),
			"max_hp": FirstRegionCompletion.BOSS_HP if is_region_boss() else float(spec.get("hp", 0.0)),
			"attack_left": 1.0,
			"target": "",
			"engager": "",
			"dead": false,
		}
	_log("独立挑戦: "+FirstRegionCompletion.BOSS_NAME+"（HP72は暫定）" if is_region_boss() else "C 古い採石場の前哨地に既存%sを%d体配置" % [str(spec.get("name", OUTPOST_KIND)), outpost_enemies.size()])

func _restore_committed_outpost_state(game) -> bool:
	if is_region_boss():
		if not FirstRegionCompletion.valid(game.world.region_completion,game.world.region_state,true,game.workers.size()):return false
		encounter_entry=game.world.region_completion.encounters.get(encounter_id,{}).duplicate(true)
		if not encounter_entry.is_empty():
			outpost_enemies=encounter_entry.enemies.duplicate(true)
			outpost_cleared=encounter_entry.cleared
		return true
	if not WorldTrip.outpost_states_valid(game.world.outpost_states,game.workers.size()):return false
	if not game.world.outpost_states.has(SITE_ID):return true
	var stored:Dictionary=game.world.outpost_states[SITE_ID]
	outpost_enemies=stored.enemies.duplicate(true)
	outpost_cleared=stored.cleared
	_log("帰還確定済みの前哨地状態を復元（残敵%d）" % outpost_remaining())
	return true

func outpost_remaining() -> int:
	var remaining := 0
	for enemy_id in outpost_enemies:
		if not bool(outpost_enemies[enemy_id].get("dead", false)):
			remaining += 1
	return remaining

func outpost_enemy_total() -> int:
	return outpost_enemies.size()

func request_rescue(target_id: String, carrier_id: String, expected_session_id: String) -> Dictionary:
	return rescue_approach.request(self, target_id, carrier_id, expected_session_id)

func request_rescue_return(target_id: String, expected_session_id: String) -> Dictionary:
	return rescue_approach.request_return(self, target_id, expected_session_id)

func cancel_rescue(target_id: String, expected_session_id: String) -> Dictionary:
	return rescue_approach.cancel(self, target_id, expected_session_id)

func tick(delta: float, explicitly_paused := false) -> void:
	if explicitly_paused or committed or phase == "ready_to_exit" or not is_finite(delta) or delta <= 0.0:
		return
	elapsed += delta
	ResourceGrowth.tick(self)
	# Existing cases advance once; a new down later this frame starts at 90.
	# Never tick normal FieldOperations here: its Worker authority is suspended.
	rescue_approach.sync(self)
	rescue_ledger.tick(delta, actors, false, not all_routes_closed)
	rescue_approach.sync(self)
	if phase == "reposition_travel":
		reposition_seconds_left = maxf(0.0, reposition_seconds_left - delta)
		if reposition_seconds_left <= 0.0:
			_finish_reposition()
		return
	for actor_id in actors.keys():
		var trace_step: Dictionary = mine_rescue_traces.begin_step(self, actor_id) if mine_path_engineering else {}
		var transported_target: String = str(rescue_approach._owned.get(actor_id,""))
		_update_actor(actor_id, delta)
		if mine_path_engineering:
			mine_rescue_traces.end_step(self, actor_id, trace_step)
			for target_id in actors:
				var row: Dictionary = rescue_ledger.case_for(target_id)
				if (row.get("phase") == "carried" and row.get("carrier") == actor_id) or (target_id == transported_target and rescue_approach.treatment_pending(target_id)):
					# The final arrival erases the carried ledger before end_step.
					# Share that actual last movement after the carrier trace settles.
					mine_rescue_traces.share_carried(self, actor_id, target_id)
	_update_field_frame_exchange()
	if outpost_enabled and not outpost_cleared:
		_update_outpost_enemies(delta)
	rescue_approach.sync(self)
	_update_dock(delta)
	# Wake only after this frame movement: the delay is not retroactive travel.
	expired_recovery.consume_due(self)
	if phase == "recall" and _local_exit_ready():
		phase = "ready_to_exit"
		_log("現地の手持ち・予約・relay・入口列を解消。横視点への復帰待ち")
	elif phase == "reposition_recall" and _reposition_ready():
		phase = "reposition_travel"
		reposition_seconds_left = VERTICAL_REPOSITION_SECONDS
		_log("全員と貨物を回収。中継停車地点へ移動中")

func _returning_to_parking() -> bool:
	return phase in ["recall", "reposition_recall"]

func _reposition_ready() -> bool:
	if not vertical_slice or not reservations.is_empty() or not dock_queue.is_empty() or not dock_busy.is_empty() or _relay_total() > 0:
		return false
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if int(actor.get("carry_n", 0)) > 0 or str(actor.get("state", "")) not in ["idle", "safe_wait", "injured_wait"]:
			return false
	return true

func _finish_reposition() -> void:
	if not vertical_slice or reposition_target_slot not in [PARKING_ENTRY, PARKING_RELAY]:
		return
	parking_slot = reposition_target_slot
	reposition_target_slot = ""
	var anchor := parking_anchor()
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var index := int(actor.get("worker_index", 0))
		actor["x"] = anchor.x + float(index) * 28.0
		actor["y"] = anchor.y + float(index % 2) * 20.0
		actor["path"] = []
		actor["path_index"] = 0
		actor["wait_reason"] = ""
		if bool(actor.get("down", false)):
			continue
		var role := str(actor.get("role", ""))
		actor["state"] = "capacity_idle" if capacity_paused else ("to_resource" if role == "harvest" else ("wait_relay" if role == "carry" else "escort"))
		if str(actor.get("state", "")) == "to_resource":
			_refresh_actor_path(str(actor_id))
	phase = "local"
	_log("%s停車へ到達。資源地まで%.0f秒基準で通常分業を再開" % ["中継" if parking_slot == PARKING_RELAY else "入口", _active_one_way_seconds()])

func _update_actor(actor_id: String, delta: float) -> void:
	if not actors.has(actor_id):
		return
	var actor: Dictionary = actors[actor_id]
	if float(actor.get("hp", 0.0)) <= 0.0 and not bool(actor.get("down", false)):
		_begin_outpost_down(actor_id, actor)
		return
	var state := str(actor.get("state", ""))
	if bool(actor.get("down", false)):
		rescue_ledger.observe_down(actor_id, actors)
		return
	if expired_recovery.owns(actor_id):
		expired_recovery.update_actor(self, actor_id, delta)
		return
	if rescue_approach.has_mine_return(actor_id):
		rescue_approach.update_mine_return(self, actor_id, delta)
		return
	if state == "rescue_treatment":
		rescue_approach.update_treatment(self, actor_id)
		return
	if state in ["rescue_move", "rescue_hold", "rescue_return"]:
		rescue_approach.update_actor(self, actor_id, delta)
		return
	if state == "maintenance_move":
		if _advance(actor, delta):
			actor["state"] = "maintenance_work"
			actor["work_left"] = VERTICAL_MAINTENANCE_SECONDS
		return
	if state == "maintenance_work" and mine_path_engineering:
		actor["work_left"] = float(actor.get("work_left", 0.0)) - delta
		if float(actor.get("work_left", 0.0)) <= 0.0:
			intermediate_access = "cleared"
			maintenance_actor_id = ""
			actor["state"] = "escort"
			actor["wait_reason"] = "Rubble cleared; cart shortcut opens on the next leg."
			actor["path"] = []
			actor["path_index"] = 0
			_mine_path_route_changed("Rubble cleared; cart shortcut opens on the next leg.")
		return
	if state == "maintenance_work":
		actor["work_left"] = float(actor.get("work_left", 0.0)) - delta
		if float(actor.get("work_left", 0.0)) <= 0.0:
			intermediate_access = "cleared"
			maintenance_actor_id = ""
			actor["state"] = "to_base_empty"
			actor["wait_reason"] = "中継路の小障害物を整備完了"
			_refresh_actor_path(actor_id)
			_log("通路の小障害物整備完了")
		return
	if state == "capacity_idle" or state == "capacity_wait":
		return
	if state == "outpost_wait":
		if _returning_to_parking():
			actor["state"] = "to_base_empty"
			_refresh_actor_path(actor_id)
		elif outpost_cleared:
			actor["state"] = "to_resource"
			actor["wait_reason"] = ""
			_refresh_actor_path(actor_id)
		return
	if state == "outpost_move":
		_update_outpost_move(actor_id, actor, delta)
		return
	if state == "combat":
		_update_outpost_combat(actor_id, actor, delta)
		return
	if state == "injured_return":
		if _advance(actor, delta):
			actor["state"] = "injured_wait"
			actor["wait_reason"] = "負傷のため駐車基地で撤退待ち"
		return
	if state == "injured_wait":
		return
	if state == "field_exchange_move":
		if _advance(actor, delta):
			actor["state"] = "field_exchange_wait"
			actor["wait_reason"] = "中継で背負いフレーム引渡し待ち"
		return
	if state == "field_exchange_wait":
		return
	if state == "escort":
		_update_escort(actor_id, actor, delta)
		return
	if state == "safe_wait":
		if not all_routes_closed:
			actor["wait_reason"] = ""
			var role := str(actor.get("role", ""))
			var resume_state := str(actor.get("resume_state", ""))
			if _returning_to_parking() and resume_state != "injured_return":
				if int(actor.get("carry_n", 0)) > 0:
					resume_state = "to_relay" if role == "harvest" else "to_base"
				else:
					resume_state = "to_base_empty"
			elif resume_state.is_empty():
				resume_state = "to_resource" if role in ["harvest", "solo"] else "wait_relay"
				if not _returning_to_parking() and outpost_enabled and not outpost_cleared and role == "harvest":
					resume_state = "outpost_wait"
				elif not _returning_to_parking() and outpost_enabled and not outpost_cleared and role == "escort":
					resume_state = "outpost_move"
			actor["state"] = resume_state
			actor["resume_state"] = ""
			_refresh_actor_path(actor_id)
		return
	if state == "to_resource":
		if vertical_slice and capacity_paused:
			actor["state"] = "to_base_empty"
			actor["wait_reason"] = "拠点が満載のため新規採取を停止"
			_refresh_actor_path(actor_id)
		elif vertical_slice and _source_depleted():
			actor["state"] = "to_base_empty"
			actor["wait_reason"] = "鉱床枯渇。採取済み貨物の帰還待ち"
			_refresh_actor_path(actor_id)
		elif _returning_to_parking():
			actor["state"] = "to_base_empty"
			_refresh_actor_path(actor_id)
		elif outpost_enabled and not outpost_cleared:
			actor["state"] = "outpost_wait"
			actor["wait_reason"] = "護衛が前哨地を対処中"
		elif all_routes_closed:
			_safe_wait(actor, "主経路と迂回路が閉鎖中", "to_resource")
		elif _advance(actor, delta):
			var resource_id := _reserve_resource(actor_id)
			if resource_id.is_empty():
				actor["state"] = "to_base_empty" if _returning_to_parking() or capacity_paused or (vertical_slice and _source_depleted()) else "idle"
				if actor.state == "idle": actor.wait_reason = NORMAL_CAPACITY_WAIT if mine_path_engineering and total_source_remaining() > 0 else ResourceGrowth.WAIT_REASON
				_refresh_actor_path(actor_id)
			else:
				actor["resource_id"] = resource_id
				actor["state"] = "harvesting"
				actor["work_left"] = _harvest_work_seconds(actor, resource_id)
				actor["wait_reason"] = ""
		return
	if state == "harvesting":
		actor["work_left"] = float(actor.get("work_left", 0.0)) - delta
		if float(actor["work_left"]) <= 0.0:
			_take_reserved_resource(actor_id)
			actor["state"] = "to_base" if bool(actor.get("direct_depot_loop", false)) else "to_relay"
			_refresh_actor_path(actor_id)
		return
	if state == "to_relay":
		if all_routes_closed and str(actor.get("role", "")) == "harvest":
			_safe_wait(actor, "主経路と迂回路が閉鎖中", "to_relay")
		elif _advance(actor, delta):
			_deposit_at_relay(actor)
			_complete_field_tool_swap_at_relay(actor_id)
			if _field_frame_exchange_waiting_for(actor_id):
				actor["state"] = "field_exchange_wait"
				actor["wait_reason"] = "中継で背負いフレームを受け取り待ち"
			elif _returning_to_parking() or (vertical_slice and (capacity_paused or _source_depleted())):
				actor["state"] = "to_base_empty"
			else:
				actor["state"] = "to_resource" if str(actor.get("role", "")) == "harvest" else "wait_relay"
			_refresh_actor_path(actor_id)
		return
	if state == "wait_relay":
		if _relay_total() > 0:
			_pickup_from_relay(actor)
			actor["state"] = "to_base"
			_refresh_actor_path(actor_id)
		elif (_returning_to_parking() and not _has_pending_relay_delivery()) or (vertical_slice and _source_depleted() and not _has_pending_relay_delivery()):
			actor["state"] = "to_base_empty"
			_refresh_actor_path(actor_id)
		return
	if state == "to_base":
		if _advance(actor, delta):
			_enqueue_dock(actor_id)
		return
	if state == "to_base_empty":
		if _advance(actor, delta):
			actor["state"] = "capacity_idle" if vertical_slice and capacity_paused and not _returning_to_parking() else "idle"
			if not capacity_paused:
				actor["wait_reason"] = ""
		return

func _update_escort(actor_id: String, actor: Dictionary, delta: float) -> void:
	if outpost_enabled and not outpost_cleared and not _returning_to_parking():
		actor["state"] = "outpost_move"
		_refresh_actor_path(actor_id)
		return
	var target := _first_actor_with_role("harvest")
	if target.is_empty() or _returning_to_parking() or (vertical_slice and (capacity_paused or _source_depleted())):
		var p := parking_anchor()
		var speed := _local_travel_speed()
		actor["x"] = move_toward(float(actor.get("x", p.x)), p.x, speed * delta)
		actor["y"] = move_toward(float(actor.get("y", p.y)), p.y, speed * delta)
		if Vector2(float(actor["x"]), float(actor["y"])).distance_to(p) < 1.0:
			actor["state"] = "idle" if _returning_to_parking() or _source_depleted() else ("capacity_idle" if capacity_paused else "escort")
		return
	var target_actor: Dictionary = actors[target]
	var desired := Vector2(float(target_actor.get("x", BASE.x)) - 34.0, float(target_actor.get("y", BASE.y)) + 20.0)
	var here := Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y)))
	var next := here.move_toward(desired, _local_travel_speed() * delta)
	actor["x"] = next.x
	actor["y"] = next.y

func _update_outpost_move(actor_id: String, actor: Dictionary, delta: float) -> void:
	if phase == "recall":
		_release_enemy_claim(actor_id, str(actor.get("combat_target", "")))
		actor["combat_target"] = ""
		actor["state"] = "to_base_empty"
		_refresh_actor_path(actor_id)
		return
	var enemy_id := _claim_outpost_enemy(actor_id)
	if enemy_id.is_empty():
		actor["combat_target"] = ""
		if outpost_cleared:
			actor["state"] = "escort"
		else:
			actor["state"] = "safe_wait"
			actor["wait_reason"] = "前哨地の護衛対象を待機"
		return
	if str(actor.get("combat_target", "")) != enemy_id:
		actor["combat_target"] = enemy_id
		_refresh_actor_path(actor_id)
	if _advance(actor, delta):
		actor["state"] = "combat"
		actor["wait_reason"] = "既存装備で前哨地を対処中"

func _update_outpost_combat(actor_id: String, actor: Dictionary, delta: float) -> void:
	if phase == "recall":
		_release_enemy_claim(actor_id, str(actor.get("combat_target", "")))
		actor["combat_target"] = ""
		actor["state"] = "to_base_empty"
		actor["wait_reason"] = ""
		_refresh_actor_path(actor_id)
		return
	var enemy_id := str(actor.get("combat_target", ""))
	if not _outpost_enemy_alive(enemy_id):
		_release_enemy_claim(actor_id, enemy_id)
		actor["combat_target"] = ""
		actor["state"] = "outpost_move" if not outpost_cleared else "escort"
		_refresh_actor_path(actor_id)
		return
	var enemy: Dictionary = outpost_enemies[enemy_id]
	var here := Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y)))
	var target := Vector2(float(enemy.get("x", RESOURCE.x)), float(enemy.get("y", RESOURCE.y)))
	var weapon_range := maxf(1.0, float(actor.get("weapon_range", 1.0)))
	if here.distance_to(target) > weapon_range:
		actor["state"] = "outpost_move"
		_refresh_actor_path(actor_id)
		return
	var damage := maxf(0.0, float(actor.get("attack_per_second", 0.0))) * delta
	enemy["hp"] = maxf(0.0, float(enemy.get("hp", 0.0)) - damage)
	actor["fatigue"] = minf(CrewStatusDB.MAX_FATIGUE, float(actor.get("fatigue", 0.0)) + CrewStatusDB.FATIGUE_COMBAT_GAIN * delta)
	if float(enemy.get("hp", 0.0)) <= 0.0:
		enemy["dead"] = true
		enemy["target"] = ""
		enemy["engager"] = ""
		actor["combat_target"] = ""
		actor["wait_reason"] = ""
		_log("%s が%sを撃破（帰還して確定・追加戦利品なし）" % [actor_id, FirstRegionCompletion.BOSS_NAME if is_region_boss() else str(EventDB.ENEMIES.get(str(enemy.get("kind", OUTPOST_KIND)), {}).get("name", OUTPOST_KIND))])
		if outpost_remaining() == 0:
			_finish_outpost()
		else:
			actor["state"] = "outpost_move"
			_refresh_actor_path(actor_id)

func _claim_outpost_enemy(actor_id: String) -> String:
	if not actors.has(actor_id):
		return ""
	var actor: Dictionary = actors[actor_id]
	var active := str(actor.get("combat_target", ""))
	if _outpost_enemy_alive(active):
		var current: Dictionary = outpost_enemies[active]
		if str(current.get("engager", "")).is_empty() or str(current.get("engager", "")) == actor_id:
			current["engager"] = actor_id
			return active
	var here := Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y)))
	var selected := ""
	var selected_distance := INF
	for enemy_id in outpost_enemies:
		var enemy: Dictionary = outpost_enemies[enemy_id]
		if bool(enemy.get("dead", false)):
			continue
		var engager := str(enemy.get("engager", ""))
		if not engager.is_empty() and engager != actor_id:
			continue
		var position := Vector2(float(enemy.get("x", RESOURCE.x)), float(enemy.get("y", RESOURCE.y)))
		var distance := here.distance_to(position)
		if distance < selected_distance:
			selected = str(enemy_id)
			selected_distance = distance
	if not selected.is_empty():
		outpost_enemies[selected]["engager"] = actor_id
	return selected

func _release_enemy_claim(actor_id: String, enemy_id: String) -> void:
	if not outpost_enemies.has(enemy_id):
		return
	var enemy: Dictionary = outpost_enemies[enemy_id]
	if str(enemy.get("engager", "")) == actor_id:
		enemy["engager"] = ""
	if str(enemy.get("target", "")) == actor_id:
		enemy["target"] = ""

func _outpost_enemy_alive(enemy_id: String) -> bool:
	return outpost_enemies.has(enemy_id) and not bool(outpost_enemies[enemy_id].get("dead", false))

func _update_outpost_enemies(delta: float) -> void:
	for enemy_id in outpost_enemies.keys():
		var enemy: Dictionary = outpost_enemies[enemy_id]
		if bool(enemy.get("dead", false)):
			continue
		var target_id := _outpost_enemy_target(enemy)
		if target_id.is_empty():
			enemy["target"] = ""
			var home := Vector2(float(enemy.get("home_x", RESOURCE.x)), float(enemy.get("home_y", RESOURCE.y)))
			var resting := Vector2(float(enemy.get("x", home.x)), float(enemy.get("y", home.y)))
			var kind: String = str(enemy.get("kind", OUTPOST_KIND))
			enemy["x"] = resting.move_toward(home, float(EventDB.ENEMIES.get(kind, {}).get("run", 0.0)) * delta).x
			enemy["y"] = resting.move_toward(home, float(EventDB.ENEMIES.get(kind, {}).get("run", 0.0)) * delta).y
			continue
		enemy["target"] = target_id
		var actor: Dictionary = actors[target_id]
		var here := Vector2(float(enemy.get("x", RESOURCE.x)), float(enemy.get("y", RESOURCE.y)))
		var target := Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y)))
		var kind: String = str(enemy.get("kind", OUTPOST_KIND))
		var spec: Dictionary = EventDB.ENEMIES.get(kind, {})
		if here.distance_to(Vector2(float(enemy.get("home_x", here.x)), float(enemy.get("home_y", here.y)))) > Enemy.TERRITORY:
			enemy["target"] = ""
			continue
		if here.distance_to(target) > Enemy.HIT_REACH:
			var next := here.move_toward(target, float(spec.get("run", 0.0)) * delta)
			enemy["x"] = next.x
			enemy["y"] = next.y
			here = next
		enemy["attack_left"] = float(enemy.get("attack_left", 1.0)) - delta
		if here.distance_to(target) <= float(spec.get("hit_reach", Enemy.HIT_REACH)) and float(enemy.get("attack_left", 0.0)) <= 0.0:
			enemy["attack_left"] = 1.0 # Enemy._tick_ecology() と同じ1秒周期。
			_apply_outpost_hit(target_id, enemy_id)
	if outpost_remaining() == 0:
		_finish_outpost()

func _outpost_enemy_target(enemy: Dictionary) -> String:
	var current := str(enemy.get("target", ""))
	if _outpost_actor_can_be_targeted(current, enemy):
		return current
	var enemy_position := Vector2(float(enemy.get("x", RESOURCE.x)), float(enemy.get("y", RESOURCE.y)))
	var selected := ""
	var selected_distance := INF
	for actor_id in actors:
		if not _outpost_actor_can_be_targeted(str(actor_id), enemy):
			continue
		var actor: Dictionary = actors[actor_id]
		var distance := enemy_position.distance_to(Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y))))
		if distance < selected_distance:
			selected = str(actor_id)
			selected_distance = distance
	return selected

## HP30 starts retreat, not immunity. Existing medical/expiry owners and
## actors who have physically reached parking are outside this combat owner.
func _outpost_actor_exposed(actor_id: String) -> bool:
	if not actors.has(actor_id):
		return false
	var actor: Dictionary = actors[actor_id]
	if bool(actor.get("down", false)) or float(actor.get("hp", 0.0)) <= 0.0 or expired_recovery.owns(actor_id) or rescue_approach.treatment_pending(actor_id):
		return false
	if Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y))).distance_to(parking_anchor()) <= 0.1:
		return false
	var state := str(actor.get("state", ""))
	if state == "safe_wait":
		state = str(actor.get("resume_state", ""))
	return state in ["rescue_move", "rescue_hold", "rescue_return", "injured_return"] or (state == "to_base_empty" and rescue_approach.has_mine_return(actor_id)) or (str(actor.get("role", "")) == "escort" and state in ["outpost_move", "combat", "to_base_empty"])

func _outpost_actor_can_be_targeted(actor_id: String, enemy: Dictionary) -> bool:
	if not _outpost_actor_exposed(actor_id):
		return false
	var actor: Dictionary = actors[actor_id]
	var enemy_position := Vector2(float(enemy.get("x", RESOURCE.x)), float(enemy.get("y", RESOURCE.y)))
	var home := Vector2(float(enemy.get("home_x", enemy_position.x)), float(enemy.get("home_y", enemy_position.y)))
	var actor_position := Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y)))
	# Both sides remain inside the existing home territory. An enemy already
	# outside returns through the normal no-target branch instead of sticking.
	return enemy_position.distance_to(actor_position) <= Enemy.SIGHT and actor_position.distance_to(home) <= Enemy.TERRITORY and enemy_position.distance_to(home) <= Enemy.TERRITORY

func _apply_outpost_hit(actor_id: String, enemy_id: String) -> void:
	if not _outpost_actor_exposed(actor_id):
		return
	var actor: Dictionary = actors[actor_id]
	var previous_hp := float(actor.get("hp", 0.0))
	actor["hp"] = maxf(0.0, float(actor.get("hp", 0.0)) - CrewStatusDB.RAID_HIT_HP)
	actor["stress"] = maxf(0.0, float(actor.get("stress", 0.0)) + CrewStatusDB.RAID_HIT_STRESS)
	_log("%s が%sから既存の負傷値を受けた" % [actor_id, enemy_id])
	if float(actor.get("hp", 0.0)) <= 0.0:
		_begin_outpost_down(actor_id, actor)
		return
	if previous_hp > FieldOperations.RETREAT_HP and float(actor.get("hp", 0.0)) <= FieldOperations.RETREAT_HP:
		_begin_injured_return(actor_id, actor)

func _begin_outpost_down(actor_id: String, actor: Dictionary) -> void:
	if bool(actor.get("down", false)):
		return
	_release_actor_reservation(actor)
	_release_enemy_claim(actor_id, str(actor.get("combat_target", "")))
	expired_recovery.observe_down(actor_id, actor)
	actor["hp"] = 0.0
	actor["down"] = true
	actor["combat_target"] = ""
	actor["state"] = "down"
	if mine_path_engineering and maintenance_actor_id == actor_id:
		_cancel_mine_path_clearance(false)
	rescue_ledger.observe_down(actor_id, actors)
	actor["wait_reason"] = "HP0: 手動救助待ち。未帰還の負傷者がいるため帰還確定不可"
	_log("%s はHP0で戦闘不能。固定画面の確定を安全に拒否" % actor_id)

func _begin_injured_return(actor_id: String, actor: Dictionary) -> void:
	_release_actor_reservation(actor)
	_release_enemy_claim(actor_id, str(actor.get("combat_target", "")))
	actor["combat_target"] = ""
	actor["state"] = "injured_return"
	actor["wait_reason"] = "HP%d: 既存の負傷時撤退閾値で帰還" % int(actor.get("hp", 0.0))
	outpost_retreats += 1
	if not rescue_approach.begin_boss_return(self, actor_id, "injured_return"):
		_refresh_actor_path(actor_id)
	_log("%s はHP%dで前哨地の追撃を中断し撤退" % [actor_id, int(actor.get("hp", 0.0))])

func _finish_outpost() -> void:
	if outpost_cleared:
		return
	outpost_cleared = true
	_log("採石場の主を撃破。全員と荷物を帰還して確定してください" if is_region_boss() else "前哨地の既存敵を全て対処。既存C有限資源の回収を再開")
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("state", "")) == "outpost_wait":
			actor["state"] = "to_resource"
			actor["wait_reason"] = ""
			_refresh_actor_path(str(actor_id))

## The obstacle is a small local maintenance task, not a new combat or drill
## system.  It only unlocks the already-walkable RELAY anchor for this session.
func request_mine_path_clearance() -> Dictionary:
	if not mine_path_engineering:
		return {"ok": false, "reason": "Mine path engineering is not active."}
	return request_intermediate_clearance()

func request_intermediate_clearance() -> Dictionary:
	if not vertical_slice and not mine_path_engineering:
		return {"ok": false, "reason": "中継停車は縦切り検証でのみ利用できます"}
	if phase != "local":
		return {"ok": false, "reason": "移動・撤退中は小障害物を整備できません"}
	if intermediate_access == "cleared":
		return {"ok": true, "already_cleared": true}
	if is_region_boss() and not outpost_cleared:
		return {"ok":false,"reason":"ボスへの挑戦中は護衛を整備へ移せません。撃破後または通常採掘で整備してください。"}
	if intermediate_access == "clearing":
		return {"ok": false, "reason": "小障害物を整備中です"}
	if capacity_paused:
		return {"ok": false, "reason": "容量不足の保持貨物を先に収納してください"}
	if not field_frame_exchange.is_empty() and str(field_frame_exchange.get("status", "")) == "scheduled":
		return {"ok": false, "reason": "現地フレーム引渡しの完了または取消後に整備してください"}
	var escort_id := _first_operational_actor_with_role("escort")
	if escort_id.is_empty() or not actors.has(escort_id) or (rescue_approach.owns(escort_id) or expired_recovery.owns(escort_id)):
		return {"ok": false, "reason": "整備に回せる既存護衛がいません"}
	intermediate_access = "clearing"
	maintenance_actor_id = escort_id
	var escort: Dictionary = actors[escort_id]
	if str(escort.get("state", "")) == "harvesting":
		_release_actor_reservation(escort)
	escort["state"] = "maintenance_move"
	escort["wait_reason"] = "通路の小障害物を整備中"
	_refresh_actor_path(escort_id)
	_log("%s が中継路の小障害物を整備開始" % escort_id)
	return {"ok": true, "actor_id": escort_id}

func cancel_mine_path_clearance() -> Dictionary:
	if not mine_path_engineering:
		return {"ok": false, "reason": "Mine path engineering is not active."}
	return _cancel_mine_path_clearance(true)

func _cancel_mine_path_clearance(announce := false) -> Dictionary:
	if intermediate_access != "clearing":
		return {"ok": false, "reason": "No rubble-clearance job is active."}
	var actor_id := maintenance_actor_id
	if not actor_id.is_empty() and actors.has(actor_id):
		var actor: Dictionary = actors[actor_id]
		actor["work_left"] = 0.0
		actor["path"] = []
		actor["path_index"] = 0
		if not bool(actor.get("down", false)):
			actor["state"] = "escort" if phase == "local" else "to_base_empty"
			actor["wait_reason"] = ""
			if phase != "local":
				_refresh_actor_path(actor_id)
	maintenance_actor_id = ""
	intermediate_access = "blocked"
	if announce:
		_log("Rubble-clearance order cancelled; cart shortcut remains blocked.")
	return {"ok": true}

## Field parking is fixed. Keep API for old callers without mutating inventory or actors.
func request_reposition(_slot: String) -> Dictionary:
	return {"ok": false, "reason": "現地の移動拠点は入口に固定停車します"}

func cancel_reposition() -> Dictionary:
	if not vertical_slice:
		return {"ok": false, "reason": "中継停車は縦切り検証でのみ利用できます"}
	if phase not in ["reposition_recall", "reposition_travel"]:
		return {"ok": false, "reason": "取消できる停め直しがありません"}
	phase = "local"
	reposition_target_slot = ""
	reposition_seconds_left = 0.0
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if bool(actor.get("down", false)) or str(actor.get("state", "")) in ["dock_wait", "capacity_wait"]:
			continue
		var role := str(actor.get("role", ""))
		if int(actor.get("carry_n", 0)) > 0:
			actor["state"] = "to_relay" if role == "harvest" else "to_base"
		elif role == "harvest":
			actor["state"] = "to_base_empty" if _source_depleted() or capacity_paused else "to_resource"
		elif role == "carry":
			actor["state"] = "wait_relay"
		else:
			actor["state"] = "capacity_idle" if capacity_paused else "escort"
		actor["wait_reason"] = ""
		_refresh_actor_path(str(actor_id))
	_log("停め直しを取消。入口停車の通常分業へ戻る")
	return {"ok": true, "parking_slot": parking_slot}

func _first_actor_with_role(role: String) -> String:
	for actor_id in actors:
		if str(actors[actor_id].get("role", "")) == role:
			return actor_id
	return ""


## Clearance has to select a worker that can actually walk and work. Other
## feature lookups retain their historical role-only behavior; this narrowly
## protects the mine engineering command from a downed escort.
func _first_operational_actor_with_role(role: String) -> String:
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("role", "")) == role and not bool(actor.get("down", false)) and float(actor.get("hp", 0.0)) > 0.0:
			return actor_id
	return ""

func _safe_wait(actor: Dictionary, reason: String, resume_state := "") -> void:
	_release_actor_reservation(actor)
	actor["state"] = "safe_wait"
	actor["wait_reason"] = reason
	actor["resume_state"] = resume_state

func _refresh_actor_path(actor_id: String) -> void:
	if expired_recovery.owns(actor_id):
		expired_recovery.repath(self, actor_id)
		return
	if not actors.has(actor_id):
		return
	if rescue_approach.has_mine_return(actor_id):
		rescue_approach.repath_mine_return(self, actor_id)
		return
	var actor: Dictionary = actors[actor_id]
	var state := str(actor.get("state", ""))
	var target := Vector2.ZERO
	var crosses_gate := false
	match state:
		"to_resource":
			target = RESOURCE
			crosses_gate = true
		"maintenance_move":
			target = MINE_PATH_RUBBLE if mine_path_engineering else RELAY
		"to_relay":
			target = RELAY
			crosses_gate = str(actor.get("role", "")) == "harvest"
		"field_exchange_move":
			target = RELAY
			crosses_gate = float(actor.get("x", BASE.x)) > GATE.x
		"outpost_move":
			var enemy_id := str(actor.get("combat_target", ""))
			if not _outpost_enemy_alive(enemy_id):
				actor["path"] = []
				actor["path_index"] = 0
				return
			var enemy: Dictionary = outpost_enemies[enemy_id]
			target = Vector2(float(enemy.get("x", RESOURCE.x)), float(enemy.get("y", RESOURCE.y)))
			crosses_gate = true
		"injured_return":
			target = parking_anchor()
			crosses_gate = float(actor.get("x", BASE.x)) > GATE.x
		"to_base", "to_base_empty":
			target = parking_anchor()
			crosses_gate = float(actor.get("x", BASE.x)) > GATE.x
		_:
			actor["path"] = []
			actor["path_index"] = 0
			return
	if mine_path_engineering and state in ["to_resource", "to_relay", "to_base", "to_base_empty"]:
		if all_routes_closed:
			_safe_wait(actor, "All mine routes are closed.", state)
			return
		var cart := int(actor.get("work_support", -1)) == GameData.Item.HANDCART
		var route_kind := "backpack_step"
		var corridor_points: Array = [MINE_PATH_STEP]
		if cart:
			route_kind = "cart_shortcut" if intermediate_access == "cleared" else "cart_detour"
			corridor_points = [MINE_PATH_CART_SHORTCUT] if intermediate_access == "cleared" else [MINE_PATH_CART_DETOUR_ENTRY, MINE_PATH_CART_DETOUR]
		var engineering_points: Array = []
		if state == "to_resource":
			for corridor in corridor_points:
				engineering_points.append(_point_array(corridor))
			engineering_points.append(_point_array(GATE))
		elif state == "to_relay":
			# Only harvesters approach relay from the ore side. Carry workers begin
			# at the entrance and must first traverse the real corridor to relay.
			if str(actor.get("role", "")) == "harvest":
				engineering_points.append(_point_array(GATE))
				var return_corridor_points: Array = corridor_points.duplicate()
				return_corridor_points.reverse()
				for corridor in return_corridor_points:
					engineering_points.append(_point_array(corridor))
			else:
				for corridor in corridor_points:
					engineering_points.append(_point_array(corridor))
		elif state in ["to_base", "to_base_empty"]:
			var base_corridor_points: Array = corridor_points.duplicate()
			base_corridor_points.reverse()
			for corridor in base_corridor_points:
				engineering_points.append(_point_array(corridor))
		engineering_points.append(_point_array(target))
		actor["path"] = engineering_points
		actor["path_index"] = 0
		actor["path_speed"] = MOVE_SPEED
		actor["seen_route_revision"] = route_revision
		actor["route"] = route_kind
		mine_rescue_traces.witness_plan(self, actor_id, actor)
		path_requests += 1
		return
	if crosses_gate and all_routes_closed:
		_safe_wait(actor, "主経路と迂回路が閉鎖中", state)
		return
	var points: Array = []
	if crosses_gate:
		points.append(_point_array(BYPASS if gate_closed else GATE))
		if state == "outpost_move":
			points.append(_point_array(OUTPOST_COVER))
	points.append(_point_array(target))
	actor["path"] = points
	actor["path_index"] = 0
	actor["path_speed"] = _local_travel_speed() if vertical_slice else MOVE_SPEED
	actor["seen_route_revision"] = route_revision
	actor["route"] = "bypass" if crosses_gate and gate_closed else ("main" if crosses_gate else "local")
	if mine_path_engineering: mine_rescue_traces.witness_plan(self, actor_id, actor)
	path_requests += 1

func _local_travel_speed() -> float:
	if not vertical_slice:
		return MOVE_SPEED
	var start := parking_anchor()
	var route_point := BYPASS if gate_closed else GATE
	var total := start.distance_to(route_point) + route_point.distance_to(RESOURCE)
	return maxf(1.0, total / _active_one_way_seconds())

func _advance(actor: Dictionary, delta: float) -> bool:
	var points: Array = Array(actor.get("path", []))
	var index := int(actor.get("path_index", 0))
	if points.is_empty() or index >= points.size():
		return true
	var target_data: Array = points[index]
	if target_data.size() != 2:
		return true
	var target := Vector2(float(target_data[0]), float(target_data[1]))
	var here := Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y)))
	var speed := maxf(1.0, float(actor.get("path_speed", MOVE_SPEED))) * float(actor.get("life_move_mult", 1.0))
	var next := here.move_toward(target, speed * delta)
	actor["x"] = next.x
	actor["y"] = next.y
	if next.distance_to(target) > 0.1:
		return false
	actor["path_index"] = index + 1
	return int(actor["path_index"]) >= points.size()

func _reserve_resource(actor_id: String) -> String:
	if vertical_slice and capacity_paused:
		return ""
	for resource_id in resources:
		var resource: Dictionary = resources[resource_id]
		if int(resource.get("remaining", 0)) > 0 and str(resource.get("reservation", "")).is_empty() and normal_collection_room_for(int(resource.item)) > 0:
			resource["reservation"] = actor_id
			reservations[resource_id] = actor_id
			return resource_id
	return ""


## The C session retains its original fixed work time unless the v18 field kit
## has actually changed this actor's mine tool.  In that narrow case, reuse
## GatherDB's existing rate calculation as a relative factor.  The resource
## unit, finite amount, bag limit and bonus handling remain untouched.
func _harvest_work_seconds(actor: Dictionary, resource_id: String) -> float:
	if resource_id.is_empty() or not resources.has(resource_id):
		return WORK_SECONDS
	var resource: Dictionary = resources[resource_id]
	var kind := str(resource.get("kind", ""))
	if kind not in ["rock", "vein"]:
		return WORK_SECONDS
	var current_tool := int(Dictionary(actor.get("tools", {})).get(FIELD_TOOL_KIT_SLOT, -1))
	var entry_tool := int(Dictionary(actor.get("entry_tools", {})).get(FIELD_TOOL_KIT_SLOT, -1))
	if current_tool == entry_tool:
		return WORK_SECONDS
	var rank := maxi(0, int(actor.get("entry_gather_rank", 0)))
	var ability := maxf(0.05, float(actor.get("entry_gather_ability", 1.0)))
	var entry_eval: Dictionary = GatherDB.evaluate(kind, entry_tool, rank, ability)
	var current_eval: Dictionary = GatherDB.evaluate(kind, current_tool, rank, ability)
	var entry_rate := float(entry_eval.get("eff", 0.0)) / maxf(0.05, float(entry_eval.get("seconds", 1.0)))
	var current_rate := float(current_eval.get("eff", 0.0)) / maxf(0.05, float(current_eval.get("seconds", 1.0)))
	if entry_rate <= 0.0 or current_rate <= 0.0:
		return WORK_SECONDS
	return clampf(WORK_SECONDS * entry_rate / current_rate, WORK_SECONDS * FIELD_TOOL_MIN_DURATION_FACTOR, WORK_SECONDS * FIELD_TOOL_MAX_DURATION_FACTOR)

func _take_reserved_resource(actor_id: String) -> void:
	if not actors.has(actor_id):
		return
	var actor: Dictionary = actors[actor_id]
	var resource_id := str(actor.get("resource_id", ""))
	if not resources.has(resource_id):
		actor["resource_id"] = ""
		return
	var resource: Dictionary = resources[resource_id]
	if str(resource.get("reservation", "")) != actor_id or int(resource.get("remaining", 0)) <= 0:
		actor["resource_id"] = ""
		return
	var moved := mini(mini(maxi(1, int(actor.get("carry_limit", 1))), int(resource.remaining)), normal_collection_room_for(int(resource.item)))
	resource["remaining"] = int(resource.remaining) - moved
	resource["reservation"] = ""
	reservations.erase(resource_id)
	actor["carry_item"] = int(resource.item) if moved > 0 else -1
	actor["carry_n"] = moved
	actor["resource_id"] = ""
	_log("%s が有限資源を%d個回収" % [actor_id, moved])
	if vertical_slice and _capacity_is_full():
		_pause_new_collection("拠点容量が満載のため、新規採取を停止して保持貨物を帰還")

func _release_actor_reservation(actor: Dictionary) -> void:
	var resource_id := str(actor.get("resource_id", ""))
	if resources.has(resource_id) and str(resources[resource_id].get("reservation", "")) != "":
		resources[resource_id]["reservation"] = ""
		reservations.erase(resource_id)
	actor["resource_id"] = ""
	actor["work_left"] = 0.0

func _deposit_at_relay(actor: Dictionary) -> void:
	var item := int(actor.get("carry_item", -1))
	var count := int(actor.get("carry_n", 0))
	if item >= 0 and count > 0:
		relay_stock[item] = int(relay_stock.get(item, 0)) + count
	actor["carry_item"] = -1
	actor["carry_n"] = 0

func _pickup_from_relay(actor: Dictionary) -> void:
	for item in relay_stock.keys():
		var count := int(relay_stock[item])
		if count <= 0:
			continue
		var moved := mini(count, maxi(1, int(actor.get("carry_limit", 1))))
		relay_stock[item] = count - moved
		if int(relay_stock[item]) <= 0:
			relay_stock.erase(item)
		actor["carry_item"] = int(item)
		actor["carry_n"] = moved
		return

func _enqueue_dock(actor_id: String) -> void:
	if expired_recovery.owns(actor_id) and not expired_recovery.dock_ready(self, actor_id): return
	if not dock_queue.has(actor_id) and not dock_busy.has(actor_id):
		dock_queue.append(actor_id)
		actors[actor_id]["state"] = "rescue_treatment" if rescue_approach.treatment_pending(actor_id) else "dock_wait"
		actors[actor_id]["wait_reason"] = "搬入口の順番待ち"

func _update_dock(delta: float) -> void:
	while dock_busy.size() < dock_count and not dock_queue.is_empty():
		var actor_id: String = str(dock_queue.pop_front())
		if actors.has(actor_id):
			dock_busy[actor_id] = DOCK_SECONDS
	for actor_id in dock_busy.keys():
		if expired_recovery.owns(actor_id) and not expired_recovery.dock_ready(self, actor_id):
			dock_busy.erase(actor_id)
			continue
		dock_busy[actor_id] = float(dock_busy[actor_id]) - delta
		if float(dock_busy[actor_id]) > 0.0:
			continue
		dock_busy.erase(actor_id)
		if not actors.has(actor_id):
			continue
		var actor: Dictionary = actors[actor_id]
		var item := int(actor.get("carry_item", -1))
		var count := int(actor.get("carry_n", 0))
		if vertical_slice and item >= 0 and count > 0:
			var accepted := mini(count, _depot_room_for(item))
			if accepted > 0:
				depot_stock[item] = int(depot_stock.get(item, 0)) + accepted
			var retained := count - accepted
			if retained > 0:
				actor["carry_item"] = item
				actor["carry_n"] = retained
				actor["state"] = "rescue_treatment" if rescue_approach.treatment_pending(actor_id) else "capacity_wait"
				actor["wait_reason"] = "拠点容量不足。入りきらない貨物を保持"
				_pause_new_collection("拠点容量が満載のため、新規採取を停止して保持貨物を帰還")
				continue
		elif item >= 0 and count > 0:
			depot_stock[item] = int(depot_stock.get(item, 0)) + count
		actor["carry_item"] = -1
		actor["carry_n"] = 0
		if expired_recovery.owns(actor_id):
			expired_recovery.finish_dock(self, actor_id)
			if vertical_slice and capacity_paused: _resume_capacity_if_possible()
			continue
		if rescue_approach.treatment_pending(actor_id):
			actor["state"] = "rescue_treatment"
			actor["wait_reason"] = "入口で応急手当済み。帰還確定後に治療・待機"
			continue
		if vertical_slice and _capacity_is_full():
			_pause_new_collection("拠点容量が満載のため、新規採取を停止して保持貨物を帰還")
			actor["state"] = "capacity_idle"
			actor["wait_reason"] = "拠点容量が満載"
			continue
		if vertical_slice and capacity_paused:
			_resume_capacity_if_possible()
		actor["wait_reason"] = ""
		if vertical_slice and _source_depleted():
			actor["state"] = "to_base_empty"
		else:
			actor["state"] = "to_resource" if phase == "local" and bool(actor.get("direct_depot_loop", false)) else ("to_relay" if phase == "local" else "to_base_empty")
		_refresh_actor_path(actor_id)

func _relay_total() -> int:
	return _stock_total(relay_stock)

func _stock_total(stock: Dictionary) -> int:
	var total := 0
	for item in stock:
		total += int(stock[item])
	return total

func _local_exit_ready() -> bool:
	if not expired_recovery.exit_ready(self): return false
	for actor_id in actors:
		if rescue_approach.has_mine_return(str(actor_id)): return false
	if not reservations.is_empty() or not dock_queue.is_empty() or not dock_busy.is_empty() or _relay_total() > 0:
		return false
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("state", "")) == "safe_wait" and str(actor.get("resume_state", "")) in ["injured_return", "to_base_empty"] and Vector2(float(actor.get("x", BASE.x)), float(actor.get("y", BASE.y))).distance_to(parking_anchor()) > 0.1:
			return false
		if int(actor.get("carry_n", 0)) > 0 or str(actor.get("state", "")) not in ["idle", "safe_wait", "injured_wait", "rescue_treatment"]:
			return false
	return true

func request_recall() -> void:
	if committed or phase == "ready_to_exit":
		return
	if mine_path_engineering and intermediate_access == "clearing":
		_cancel_mine_path_clearance(false)
	_cancel_field_frame_exchange("撤退を優先して現地フレーム引渡しを取消")
	_cancel_field_tool_swap("撤退を優先して携行採掘具交換を取消")
	reposition_target_slot = ""
	reposition_seconds_left = 0.0
	maintenance_actor_id = ""
	phase = "recall"
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if bool(actor.get("down", false)) or (rescue_approach.owns(str(actor_id)) or expired_recovery.owns(str(actor_id))) or rescue_approach.treatment_pending(str(actor_id)):
			continue
		if str(actor.get("state", "")) == "harvesting":
			_release_actor_reservation(actor)
		var state := str(actor.get("state", ""))
		if state in ["injured_wait", "injured_return"] or (state == "safe_wait" and str(actor.get("resume_state", "")) == "injured_return"):
			continue
		var combat_return := is_region_boss() and str(actor.get("role", "")) == "escort" and (state in ["outpost_move", "combat"] or (state == "safe_wait" and str(actor.get("resume_state", "")) == "outpost_move"))
		if str(actor.get("role", "")) == "escort":
			_release_enemy_claim(str(actor_id), str(actor.get("combat_target", "")))
			actor["combat_target"] = ""
			actor["state"] = "to_base_empty"
		elif int(actor.get("carry_n", 0)) > 0:
			actor["state"] = "to_relay" if str(actor.get("role", "")) == "harvest" else "to_base"
		elif str(actor.get("role", "")) == "carry":
			actor["state"] = "wait_relay"
		else:
			actor["state"] = "to_base_empty"
		if not combat_return or not rescue_approach.begin_boss_return(self, str(actor_id), "to_base_empty"):
			_refresh_actor_path(actor_id)
	_log("全班に現地帰還を指示")

func set_gate_closed(closed: bool) -> void:
	if single_worker_demo and not closed:
		_log("単独追跡検証は橋を通る迂回経路を固定")
		return
	if gate_closed == closed:
		return
	gate_closed = closed
	_route_changed("主経路を閉鎖。迂回路を使用" if closed else "主経路を開放")

func set_all_routes_closed(closed: bool) -> void:
	if all_routes_closed == closed:
		return
	all_routes_closed = closed
	_route_changed("全経路を閉鎖。到達不能は安全待機" if closed else "迂回路を再開")

func set_dock_count(count: int) -> void:
	dock_count = clampi(count, 1, 2)

func _route_changed(note: String) -> void:
	rescue_approach.sync(self)
	route_revision += 1
	_log(note)
	for actor_id in actors:
		var state := str(actors[actor_id].get("state", ""))
		if state in ["rescue_move", "rescue_return"]:
			rescue_approach.repath(self, str(actor_id))
		if state in ["to_resource", "to_relay", "to_base", "to_base_empty", "safe_wait", "outpost_move", "injured_return", "maintenance_move", "field_exchange_move"]:
			_refresh_actor_path(actor_id)

func _mine_path_route_changed(note: String) -> void:
	# Clearing affects the next leg only. Rebuilding an active path here would let
	# a worker cut across rubble midway through a detour.
	route_revision += 1
	_log(note)

func total_source_remaining() -> int:
	var total := 0
	for resource_id in resources:
		total += int(resources[resource_id].get("remaining", 0))
	return total

func _source_depleted() -> bool:
	return total_source_remaining() <= 0 and reservations.is_empty()

func _has_pending_relay_delivery() -> bool:
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("role", "")) == "harvest" and (int(actor.get("carry_n", 0)) > 0 or str(actor.get("state", "")) in ["harvesting", "to_relay"]):
			return true
	return false

func carried_total() -> int:
	var total := 0
	for actor_id in actors:
		total += int(actors[actor_id].get("carry_n", 0))
	return total

func initial_total() -> int:
	var total := 0
	for resource_id in resources:
		total += int(resources[resource_id].get("initial", 0))
	return total

func conservation_ok() -> bool:
	return initial_total() + ResourceGrowth.total(self) == total_source_remaining() + carried_total() + _stock_total(relay_stock) + _stock_total(depot_stock)

## Read-only item-level view of the existing session authority. Reservations
## remain in `ground` until pickup; no new stock or transfer path is created.
func resource_ledger_by_item() -> Dictionary:
	var ledger := {}
	for resource_id in resources:
		var resource: Dictionary = resources[resource_id]
		var item := int(resource.get("item", -1))
		_add_resource_ledger_amount(ledger, item, "initial", int(resource.get("initial", 0)))
		_add_resource_ledger_amount(ledger, item, "regenerated", int(resource.get("regenerated", 0)))
		_add_resource_ledger_amount(ledger, item, "ground", int(resource.get("remaining", 0)))
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		_add_resource_ledger_amount(ledger, int(actor.get("carry_item", -1)), "carried", int(actor.get("carry_n", 0)))
	for raw_item in relay_stock:
		_add_resource_ledger_amount(ledger, int(raw_item), "relay", int(relay_stock[raw_item]))
	for raw_item in depot_stock:
		_add_resource_ledger_amount(ledger, int(raw_item), "depot", int(depot_stock[raw_item]))
	for item in ledger:
		var row: Dictionary = ledger[item]
		row["accounted"] = int(row.ground) + int(row.carried) + int(row.relay) + int(row.depot)
		row["conservation_ok"] = int(row.initial) + int(row.regenerated) == int(row.accounted)
	return ledger

func _add_resource_ledger_amount(ledger: Dictionary, item: int, key: String, amount: int) -> void:
	if item < 0 or amount <= 0:
		return
	if not ledger.has(item):
		ledger[item] = {"initial": 0, "regenerated": 0, "ground": 0, "carried": 0, "relay": 0, "depot": 0, "accounted": 0, "conservation_ok": false}
	var row: Dictionary = ledger[item]
	row[key] = int(row.get(key, 0)) + amount

func state_summary() -> Dictionary:
	return {
		"phase": phase,
		"source_remaining": total_source_remaining(),
		"relay": _stock_total(relay_stock),
		"depot": _stock_total(depot_stock),
		"carried": carried_total(),
		"reservations": reservations.size(),
		"dock_queue": dock_queue.size() + dock_busy.size(),
		"path_requests": path_requests,
		"encounter_id": encounter_id,
		"encounter_entry": encounter_entry.duplicate(true),
		"outpost_enabled": outpost_enabled,
		"outpost_total": outpost_enemy_total(),
		"outpost_remaining": outpost_remaining(),
		"outpost_cleared": outpost_cleared,
		"outpost_retreats": outpost_retreats,
		"workflow_mode": "single_worker_demo" if single_worker_demo else "normal_roles",
		"tracked_worker_id": tracked_worker_id(),
		"mine_path_engineering": mine_path_engineering,
		"vertical_slice": vertical_slice,
		"parking_slot": parking_slot,
		"intermediate_access": intermediate_access,
		"reposition_target_slot": reposition_target_slot,
		"reposition_seconds_left": reposition_seconds_left,
		"capacity_limit_weight": field_capacity_limit_weight,
		"capacity_used_weight": _field_payload_weight(),
		"capacity_paused": capacity_paused,
		"conservation_ok": conservation_ok(),
	}

func is_single_worker_demo() -> bool:
	return single_worker_demo

func tracked_worker_id() -> String:
	return single_worker_actor_id if single_worker_demo else ""

func apply_projection_to_workers(game) -> Dictionary:
	var identity := _workers_match(game)
	if not bool(identity.get("ok", false)):
		return identity
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var worker = game.workers[int(actor.worker_index)]
		worker.position = Vector2(float(actor.x), float(actor.y))
		worker.carrying = int(actor.carry_item)
		worker.carry_n = maxi(1, int(actor.carry_n))
		worker.carry_source = Inventory.SOURCE_TRANSFER
		worker.hp = clampf(float(actor.get("hp", worker.hp)), 0.0, CrewStatusDB.MAX_HP)
		worker.fatigue = clampf(float(actor.get("fatigue", worker.fatigue)), 0.0, CrewStatusDB.MAX_FATIGUE)
		worker.hunger = clampf(float(actor.get("hunger", worker.hunger)), 0.0, CrewStatusDB.MAX_HUNGER)
		worker.calm = maxf(0.0, float(actor.get("calm", worker.calm)))
		worker.mental = int(actor.get("mental", worker.mental))
		worker.stress = maxf(0.0, float(actor.get("stress", worker.stress)))
		worker.down = bool(actor.get("down", false))
		worker.attacking = str(actor.get("state", "")) == "combat"
	return {"ok": true}

func _workers_match(game) -> Dictionary:
	if game == null or not "workers" in game:
		return {"ok": false, "reason": "本編仲間集合がありません"}
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var index := int(actor.get("worker_index", -1))
		if index < 0 or index >= game.workers.size():
			return {"ok": false, "reason": "仲間数または順序が入場時と一致しません"}
		var worker = game.workers[index]
		var entry_weapon := int(actor.get("entry_weapon", actor.get("weapon", -1)))
		var entry_support := int(actor.get("entry_work_support", actor.get("work_support", -1)))
		var entry_tools := Dictionary(actor.get("entry_tools", actor.get("tools", {})))
		if str(worker.char_name) != str(actor.get("name", "")):
			return {"ok": false, "reason": "仲間の名前または装備が入場時と一致しません（名前）"}
		if int(worker.weapon) != entry_weapon:
			return {"ok": false, "reason": "仲間の名前または装備が入場時と一致しません（武器）"}
		if int(worker.work_support) != entry_support:
			return {"ok": false, "reason": "仲間の名前または装備が入場時と一致しません（仕事補助）"}
		if worker.tools != entry_tools:
			return {"ok": false, "reason": "仲間の名前または装備が入場時と一致しません（採取道具）"}
	return {"ok": true}


## 現地フレーム引渡しは所有者だけを変える。帰還確定前に装備品の
## 個数を作ったり消したりしていないことを、入場時snapshotと照合する。
func _session_supports_match_entry_multiset() -> bool:
	var entry_counts := {}
	var current_counts := {}
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var entry_support := int(actor.get("entry_work_support", actor.get("work_support", -1)))
		var current_support := int(actor.get("work_support", -1))
		if entry_support >= 0:
			if entry_support not in GameData.SUPPORT_ITEMS:
				return false
			entry_counts[entry_support] = int(entry_counts.get(entry_support, 0)) + 1
		if current_support >= 0:
			if current_support not in GameData.SUPPORT_ITEMS:
				return false
			current_counts[current_support] = int(current_counts.get(current_support, 0)) + 1
	return entry_counts == current_counts


## 全ての外部状態を触る前に、session 内で完結する現地交換と
## 基地での手押し車交換予約を検証する。ここは在庫を動かさない。
func _equipment_commit_preflight(game) -> Dictionary:
	if not field_frame_exchange.is_empty() and str(field_frame_exchange.get("status", "")) == "scheduled":
		return {"ok": false, "reason": "現地フレーム引渡しが完了していないため帰還確定を拒否しました"}
	if not field_tool_swap.is_empty() and str(field_tool_swap.get("status", "")) == "scheduled":
		return {"ok": false, "reason": "携行採掘具交換が完了していないため帰還確定を拒否しました"}
	if not _equipment_support_map_authorized():
		return {"ok": false, "reason": "現地装備の所有者記録が入場時snapshotと一致しないため帰還確定を拒否しました"}
	if not _session_supports_match_entry_multiset():
		return {"ok": false, "reason": "現地装備の個数が入場時と一致しないため帰還確定を拒否しました"}
	if not _field_tool_swap_valid() or not _field_tool_maps_authorized():
		return {"ok": false, "reason": "携行採掘具の所有者記録が入場時snapshotと一致しないため帰還確定を拒否しました"}
	var kit_return_count := 0
	for actor_id in actors:
		kit_return_count += Dictionary(actors[actor_id].get("field_tool_kit", {})).size()
	if kit_return_count > 0 and (game == null or game.storage == null or not game.storage.has_method("store_owned")):
		return {"ok": false, "reason": "携行採掘具を基地倉庫へ返すAPIを確認できません"}
	if return_handcart_exchange.is_empty():
		return {"ok": true, "return_target_id": "", "kit_return_count": kit_return_count}
	if str(return_handcart_exchange.get("status", "")) != "reserved":
		return {"ok": false, "reason": "手押し車交換予約の状態が帰還確定に利用できません"}
	if not _return_handcart_exchange_valid():
		return {"ok": false, "reason": "手押し車交換予約の対象が一致しません"}
	if game == null or not game.has_method("swap_work_support") or not game.has_method("work_support_swap_reason"):
		return {"ok": false, "reason": "基地の仕事補助交換APIを確認できません"}
	var target_id := str(return_handcart_exchange.get("target_id", ""))
	var target: Dictionary = actors[target_id]
	var worker_index := int(target.get("worker_index", -1))
	if worker_index < 0 or worker_index >= game.workers.size():
		return {"ok": false, "reason": "手押し車交換対象の本編仲間を確認できません"}
	var reason := str(game.work_support_swap_reason(game.workers[worker_index], GameData.Item.HANDCART))
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	return {"ok": true, "return_target_id": target_id, "kit_return_count": kit_return_count}


## 本編への帰還確定だけが、session 内の実在するフレーム所有者を
## Worker へ反映する。予約済み手押し車はこの後に既存倉庫で一回交換する。
func _apply_equipment_commit(game, plan: Dictionary) -> Dictionary:
	var previous_supports := {}
	var previous_tools := {}
	var support_map_changed := false
	var tool_map_changed := false
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var worker_index := int(actor.get("worker_index", -1))
		if worker_index < 0 or worker_index >= game.workers.size():
			return {"ok": false, "reason": "現地装備を反映する本編仲間を確認できません"}
		previous_supports[worker_index] = int(game.workers[worker_index].work_support)
		previous_tools[worker_index] = Dictionary(game.workers[worker_index].tools).duplicate(true)
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var worker = game.workers[int(actor.get("worker_index", -1))]
		var support := int(actor.get("work_support", -1))
		support_map_changed = support_map_changed or int(worker.work_support) != support
		worker.work_support = support
		var tools: Dictionary = Dictionary(actor.get("tools", {})).duplicate(true)
		tool_map_changed = tool_map_changed or worker.tools != tools
		worker.tools = tools
	var target_id := str(plan.get("return_target_id", ""))
	var result := {"ok": true}
	if not target_id.is_empty():
		var target: Dictionary = actors[target_id]
		var worker = game.workers[int(target.get("worker_index", -1))]
		result = game.swap_work_support(worker, GameData.Item.HANDCART)
		if not bool(result.get("ok", false)):
			for worker_index in previous_supports:
				game.workers[int(worker_index)].work_support = int(previous_supports[worker_index])
				game.workers[int(worker_index)].tools = Dictionary(previous_tools[worker_index]).duplicate(true)
			return {"ok": false, "reason": str(result.get("reason", "基地で手押し車を交換できませんでした"))}
		target["work_support"] = GameData.Item.HANDCART
		target["carry_limit"] = GameData.HANDCART_LIMIT
		return_handcart_exchange["status"] = "completed"
		return_handcart_exchange["old_item"] = int(result.get("old_item", -1))
		result = {"ok": true, "handcart_exchange": true, "old_item": int(result.get("old_item", -1))}
	var returned_tools := {}
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var kit: Dictionary = Dictionary(actor.get("field_tool_kit", {}))
		for slot in kit:
			var item := int(kit[slot])
			returned_tools[item] = int(returned_tools.get(item, 0)) + 1
	for item in returned_tools:
		game.storage.store_owned(int(item), int(returned_tools[item]), Inventory.SOURCE_TRANSFER)
	if (support_map_changed or tool_map_changed) and returned_tools.is_empty() and game.storage != null and game.storage.inventory != null:
		game.storage.inventory.changed.emit()
	result["field_tool_returned"] = returned_tools.duplicate(true)
	result["field_tool_swapped"] = not field_tool_swap.is_empty() and str(field_tool_swap.get("status", "")) == "completed"
	return result


## Exact, read-only preview. Approval is tied to this session and shared weight,
## not a free-form quantity supplied by the UI. Normal default return still refuses overflow.
func return_cargo_plan(game) -> Dictionary:
	if not mine_path_engineering or game == null or game.world == null or not game.world.active or game.world.region != SITE_ID or game.world.phase != "stopped" or game.quarry.state != "road": return {}
	var room := _storage_free_weight(game)
	var available := room
	var loaded := {}
	var outside := {}
	var items := depot_stock.keys(); items.sort()
	for item in items:
		var count := int(depot_stock[item])
		var weight := int(game.storage.item_weight(int(item)))
		var accepted := count if weight <= 0 else mini(count, maxi(0, floori(float(room) / float(weight))))
		if accepted > 0: loaded[item] = accepted
		if accepted < count: outside[item] = count - accepted
		room -= accepted * weight
	return {"session_id":session_id,"life_clock_token":life_clock_token,"available_weight":available,"deposited":loaded,"left_outside":outside}

func commit_to_game(game, approved_plan: Dictionary = {}) -> Dictionary:
	if _commit_in_progress: return {"ok":false,"reason":"帰還確定を処理中です"}
	if committed:
		return {"ok": true, "already_committed": true, "summary": commit_summary.duplicate(true)}
	if not life_clock_token.is_empty():
		if game == null or str(game.get_meta("field_life_generation", "")) != life_clock_token:
			return {"ok": false, "reason": "生命時計: 通常読込または別実行で失効した現地状態は確定できません"}
		if game.world.regeneration_owner != self:
			return {"ok":false,"reason":"生命時計: C resource lease belongs to a different live session"}
		var paid_ledger: Dictionary = game.get_meta("field_life_paid", {})
		var completed_ledger: Dictionary = game.get_meta("field_life_committed", {})
		if life_clock_paid + 0.00001 < float(paid_ledger.get(session_id, 0.0)) or completed_ledger.has(session_id):
			return {"ok": false, "reason": "生命時計: 古い現地状態または確定済みsessionは再確定できません"}
	for actor_id in actors:
		if bool(actors[actor_id].get("down", false)):
			return {"ok": false, "reason": "戦闘不能の仲間がいるため、この最小前哨地試作では横視点救助へ引き渡せません"}
	if phase != "ready_to_exit" or not _local_exit_ready():
		return {"ok": false, "reason": "現地の予約・手持ち・搬入口列を解消してから帰還してください"}
	var match := _workers_match(game)
	if not bool(match.get("ok", false)):
		return match
	if game == null or game.world == null or game.world.region != SITE_ID or game.world.phase != "stopped":
		return {"ok": false, "reason": "C 古い採石場の横視点へ戻ってから確定してください"}
	var durable_outpost:Dictionary={"enemies":outpost_enemies.duplicate(true),"cleared":outpost_cleared} if outpost_enabled else {}
	var valid_encounter:bool=FirstRegionCompletion.enemy_record_valid(durable_outpost,game.workers.size()) if is_region_boss() else WorldTrip.outpost_states_valid({SITE_ID:durable_outpost},game.workers.size())
	if is_region_boss() and (not FirstRegionCompletion.valid(game.world.region_completion,game.world.region_state,true,game.workers.size()) or game.world.region_completion.encounters.get(encounter_id,{})!=encounter_entry):
		return {"ok":false,"reason":"挑戦の帰還記録が入場時から変わったため確定を拒否しました"}
	if outpost_enabled and (not game.world.first_region() or not valid_encounter):
		return {"ok":false,"reason":"前哨地の帰還記録を検証できません"}
	var cargo_plan := return_cargo_plan(game)
	if not approved_plan.is_empty() and (cargo_plan.is_empty() or approved_plan != cargo_plan):
		return {"ok":false,"reason":"積載量が変わりました。搬入・残置の個数を確認し直してください","plan_changed":true}
	var required_weight := 0
	for item in depot_stock:
		required_weight += int(game.storage.item_weight(int(item), int(depot_stock[item])))
	if approved_plan.is_empty() and game.storage.limits_active() and required_weight > maxi(0, game.storage.max_weight() - game.storage.current_weight() - game.storage.processing_reserve()):
		return {"ok": false, "reason": "拠点が満載のため搬入を確定できません", "summary": state_summary()}
	if not conservation_ok(): return {"ok":false,"reason":"Resource conservation changed before return"}
	for ledger in resource_ledger_by_item().values():
		if not ledger.conservation_ok:return {"ok":false,"reason":"Resource item conservation changed before return"}
	var world_source: Dictionary = game.world.locations.get(SOURCE_KEY, {})
	for resource_id in resources:
		if not world_source.has(resource_id):
			return {"ok": false, "reason": "本編の有限資源IDが一致しません"}
		var expected: Dictionary = resources[resource_id]
		var row: Dictionary = world_source[resource_id]
		if not ResourceGrowth.valid_resource(expected,entry_director_elapsed+elapsed) or not ResourceGrowth.matches_entry(expected,row):
			return {"ok":false,"reason":"Resource regeneration entry changed before return"}
		var live: Dictionary = row.get("data", {})
		if int(live.get("item", -1)) != int(expected.get("item", -1)) or int(live.get("remaining", -1)) != int(expected.get("initial", -1)):
			return {"ok": false, "reason": "本編の有限資源が入場時から変化したため安全に確定を拒否しました"}
	var treatment_plan: Dictionary = rescue_approach.commit_preflight(self, game)
	if not treatment_plan.get("ok", false):
		return treatment_plan
	var equipment_plan := _equipment_commit_preflight(game)
	if not bool(equipment_plan.get("ok", false)):
		return equipment_plan
	var commit_mine_shortcut := mine_path_engineering and intermediate_access == "cleared"
	if commit_mine_shortcut and (not game.world.has_method("set_c_quarry_cart_shortcut_cleared") or not game.world.has_method("c_quarry_cart_shortcut_cleared")):
		return {"ok": false, "reason": "C mine route state cannot be committed safely."}
	_commit_in_progress = true
	var equipment_result := _apply_equipment_commit(game, equipment_plan)
	if not bool(equipment_result.get("ok", false)):
		_commit_in_progress = false
		return equipment_result
	for resource_id in resources:
		var target_row: Dictionary = world_source[resource_id]
		target_row["data"]["remaining"] = int(resources[resource_id].remaining)
		target_row["spent"] = int(resources[resource_id].remaining) <= 0
		if resources[resource_id].has("regeneration"):target_row["regeneration"]=resources[resource_id].regeneration.duplicate(true)
	for child in game.resources_root.get_children():
		if resources.has(str(child.world_id)):
			child.remaining = int(resources[str(child.world_id)].remaining)
	var deposited: Dictionary = depot_stock.duplicate(true) if approved_plan.is_empty() else Dictionary(cargo_plan.deposited).duplicate(true)
	var left_outside: Dictionary = {} if approved_plan.is_empty() else Dictionary(cargo_plan.left_outside).duplicate(true)
	for item in deposited:
		game.storage.store_owned(int(item), int(deposited[item]), Inventory.SOURCE_TRANSFER)
	if commit_mine_shortcut and not bool(game.world.call("set_c_quarry_cart_shortcut_cleared", true)):
		_commit_in_progress = false
		return {"ok": false, "reason": "C mine route state could not be committed."}
	game.director.elapsed = maxf(float(game.director.elapsed), entry_director_elapsed) + maxf(0.0, elapsed - life_clock_paid)
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var worker = game.workers[int(actor.worker_index)]
		worker.carrying = -1
		worker.carry_n = 1
		worker.carry_bonus.clear()
		worker.hp = clampf(float(actor.get("hp", worker.hp)), 0.0, CrewStatusDB.MAX_HP)
		worker.fatigue = clampf(float(actor.get("fatigue", worker.fatigue)), 0.0, CrewStatusDB.MAX_FATIGUE)
		worker.hunger = clampf(float(actor.get("hunger", worker.hunger)), 0.0, CrewStatusDB.MAX_HUNGER)
		worker.calm = maxf(0.0, float(actor.get("calm", worker.calm)))
		worker.mental = int(actor.get("mental", worker.mental))
		worker.stress = maxf(0.0, float(actor.get("stress", worker.stress)))
		worker.down = false
		worker.attacking = false
		CrewStatus._tick_mental(worker, 0.0)
		if worker.hp <= FieldOperations.RETREAT_HP:
			worker.ai.begin_low_hp_retreat()
	rescue_approach.apply_commit(self, game, treatment_plan)
	if is_region_boss():
		game.world.region_completion.encounters[encounter_id]=durable_outpost
	elif outpost_enabled:
		game.world.outpost_states[SITE_ID]=durable_outpost
	committed = true
	game.world.release_regeneration(self)
	# A source lease forbids ledger writes until committed. Persist ordinary
	# loose nodes only after release, before returning success to the adapter.
	for item in left_outside:
		game.keep_outside(int(item), int(left_outside[item]), GameData.RAMP_FOOT)
	if not left_outside.is_empty(): game.world.sync()
	if not life_clock_token.is_empty():
		var completed_ledger: Dictionary = game.get_meta("field_life_committed", {})
		completed_ledger[session_id] = true
		game.set_meta("field_life_committed", completed_ledger)
	phase = "committed"
	commit_summary = {"deposited": deposited, "left_outside": left_outside, "elapsed": elapsed, "conservation_ok": conservation_ok(), "outpost_cleared": outpost_cleared, "outpost_remaining": outpost_remaining(), "outpost_retreats": outpost_retreats, "mine_path_cleared": bool(game.world.call("c_quarry_cart_shortcut_cleared")) if game.world.has_method("c_quarry_cart_shortcut_cleared") else false, "equipment": equipment_result.duplicate(true)}
	game.world.refresh_region_completion()
	game.world.record_quarry_return(deposited)
	_commit_in_progress = false
	_log("本編正本へ一回だけ搬入を確定")
	return {"ok": true, "summary": commit_summary.duplicate(true)}

func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"session_id": session_id,
		"phase": phase,
		"elapsed": elapsed,
		"life_clock_paid": life_clock_paid,
		"life_clock_token": life_clock_token,
		"entry_director_elapsed": entry_director_elapsed,
		"actors": actors.duplicate(true),
		"rescue": rescue_ledger.to_dict(),
		"resources": resources.duplicate(true),
		"relay_stock": relay_stock.duplicate(true),
		"depot_stock": depot_stock.duplicate(true),
		"dock_queue": dock_queue.duplicate(true),
		"dock_busy": dock_busy.duplicate(true),
		"reservations": reservations.duplicate(true),
		"dock_count": dock_count,
		"gate_closed": gate_closed,
		"all_routes_closed": all_routes_closed,
		"route_revision": route_revision,
		"path_requests": path_requests,
		"committed": committed,
		"commit_summary": commit_summary.duplicate(true),
		"event_log": event_log.duplicate(true),
		"encounter_id": encounter_id,
		"encounter_entry": encounter_entry.duplicate(true),
		"outpost_enabled": outpost_enabled,
		"outpost_enemies": outpost_enemies.duplicate(true),
		"outpost_cleared": outpost_cleared,
		"outpost_retreats": outpost_retreats,
		"single_worker_demo": single_worker_demo,
		"single_worker_actor_id": single_worker_actor_id,
		"mine_path_engineering": mine_path_engineering,
		"vertical_slice": vertical_slice,
		"parking_slot": parking_slot,
		"intermediate_access": intermediate_access,
		"maintenance_actor_id": maintenance_actor_id,
		"reposition_target_slot": reposition_target_slot,
		"reposition_seconds_left": reposition_seconds_left,
		"field_capacity_limit_weight": field_capacity_limit_weight,
		"capacity_paused": capacity_paused,
		"field_frame_exchange": field_frame_exchange.duplicate(true),
		"return_handcart_exchange": return_handcart_exchange.duplicate(true),
		"field_tool_swap": field_tool_swap.duplicate(true),
	}

static func from_dict(data: Variant) -> Dictionary:
	var source_schema := int(data.get("schema", -1)) if data is Dictionary else -1
	if not data is Dictionary or source_schema not in [2, 3, 4, 5, 6, 7, 8, 9, 10, SCHEMA_VERSION]:
		return {"ok": false, "reason": "接続セッションのschemaが一致しません"}
	if not data.get("session_id", "") is String or not data.get("actors", {}) is Dictionary or not data.get("resources", {}) is Dictionary:
		return {"ok": false, "reason": "接続セッションの必須項目が不正です"}
	var result := new()
	result.session_id = str(data.session_id)
	result.phase = str(data.get("phase", "local"))
	if result.phase not in ["local", "recall", "reposition_recall", "reposition_travel", "ready_to_exit", "committed"]:
		return {"ok": false, "reason": "接続セッションのphaseが不正です"}
	result.elapsed = float(data.get("elapsed", 0.0))
	result.life_clock_paid = float(data.get("life_clock_paid", 0.0))
	result.life_clock_token = str(data.get("life_clock_token", ""))
	if not is_finite(result.elapsed) or not is_finite(result.life_clock_paid) or result.elapsed < 0.0 or result.life_clock_paid < 0.0 or result.life_clock_paid > result.elapsed or (result.life_clock_paid > 0.0 and result.life_clock_token.is_empty()):
		return {"ok": false, "reason": "現地生命時計の保存値が不正です"}
	result.entry_director_elapsed = float(data.get("entry_director_elapsed", 0.0))
	result.actors = Dictionary(data.actors).duplicate(true)
	# HP0 is a down state, not a healthy legacy actor entitled to a new timer.
	# Validate before any bool/float coercion or rescue coverage/migration.
	for actor in result.actors.values():
		if not actor is Dictionary or not actor.get("down") is bool:
			return {"ok": false, "reason": "現地actorの戦闘不能状態が不正です"}
		if actor.has("expired_self_return") or actor.has("rescue_mine_return") or str(actor.get("state", "")) in ["rescue_move", "rescue_hold", "rescue_return", "rescue_treatment"] or str(actor.get("resume_state", "")) in ["rescue_move", "rescue_hold", "rescue_return", "rescue_treatment"]:
			return {"ok": false, "reason": "C現地の救助中snapshot復元はまだ接続されていません"}
		var hp: Variant = actor.get("hp")
		if not (hp is int or hp is float) or not is_finite(float(hp)) or float(hp) < 0.0 or bool(actor.down) != (float(hp) == 0.0):
			return {"ok": false, "reason": "現地actorのHPと戦闘不能状態が一致しません"}
	result.resources = Dictionary(data.resources).duplicate(true)
	if not ResourceGrowth.normalize_fixture_resources(result.resources):return {"ok":false,"reason":"Resource regeneration fixture integer is invalid"}
	for resource in result.resources.values():
		if not resource is Dictionary or not ResourceGrowth.valid_resource(resource,result.entry_director_elapsed+result.elapsed):return {"ok":false,"reason":"Resource regeneration data is invalid"}
	result.relay_stock = Dictionary(data.get("relay_stock", {})).duplicate(true)
	result.depot_stock = Dictionary(data.get("depot_stock", {})).duplicate(true)
	result.dock_queue = Array(data.get("dock_queue", [])).duplicate(true)
	result.dock_busy = Dictionary(data.get("dock_busy", {})).duplicate(true)
	result.reservations = Dictionary(data.get("reservations", {})).duplicate(true)
	result.dock_count = clampi(int(data.get("dock_count", 1)), 1, 2)
	result.gate_closed = bool(data.get("gate_closed", false))
	result.all_routes_closed = bool(data.get("all_routes_closed", false))
	result.route_revision = int(data.get("route_revision", 0))
	result.path_requests = int(data.get("path_requests", 0))
	result.committed = bool(data.get("committed", false))
	result.commit_summary = Dictionary(data.get("commit_summary", {})).duplicate(true)
	result.event_log = Array(data.get("event_log", [])).duplicate(true)
	result.encounter_id = str(data.get("encounter_id", ""))
	result.encounter_entry = Dictionary(data.get("encounter_entry", {})).duplicate(true)
	result.outpost_enabled = bool(data.get("outpost_enabled", false))
	result.outpost_enemies = Dictionary(data.get("outpost_enemies", {})).duplicate(true)
	result.outpost_cleared = bool(data.get("outpost_cleared", not result.outpost_enabled))
	result.outpost_retreats = maxi(0, int(data.get("outpost_retreats", 0)))
	result.single_worker_demo = bool(data.get("single_worker_demo", false))
	result.single_worker_actor_id = str(data.get("single_worker_actor_id", "worker:0" if result.single_worker_demo else ""))
	result.mine_path_engineering = bool(data.get("mine_path_engineering", false))
	result.vertical_slice = bool(data.get("vertical_slice", false))
	result.parking_slot = str(data.get("parking_slot", PARKING_ENTRY))
	result.intermediate_access = str(data.get("intermediate_access", "blocked"))
	result.maintenance_actor_id = str(data.get("maintenance_actor_id", ""))
	result.reposition_target_slot = str(data.get("reposition_target_slot", ""))
	result.reposition_seconds_left = maxf(0.0, float(data.get("reposition_seconds_left", 0.0)))
	result.field_capacity_limit_weight = maxi(0, int(data.get("field_capacity_limit_weight", UNLIMITED_FIELD_WEIGHT)))
	result.capacity_paused = bool(data.get("capacity_paused", false))
	result.field_frame_exchange = Dictionary(data.get("field_frame_exchange", {})).duplicate(true)
	result.return_handcart_exchange = Dictionary(data.get("return_handcart_exchange", {})).duplicate(true)
	result.field_tool_swap = Dictionary(data.get("field_tool_swap", {})).duplicate(true)
	if not result._migrate_legacy_entry_equipment(source_schema):
		return {"ok": false, "reason": "旧接続sessionの装備snapshotを安全に補完できません"}
	if result.session_id.is_empty() or result.actors.is_empty() or result.resources.is_empty() or not result.conservation_ok():
		return {"ok": false, "reason": "接続セッションの数量保存則または仲間情報が不正です"}
	if not result._outpost_state_valid():
		return {"ok": false, "reason": "前哨地の敵状態が不正です"}
	if not result._single_worker_mode_valid():
		return {"ok": false, "reason": "単独追跡検証の仲間状態が不正です"}
	if not result._vertical_slice_valid():
		return {"ok": false, "reason": "中継停車縦切りの状態が不正です"}
	if not result._mine_path_engineering_valid():
		return {"ok": false, "reason": "Mine path engineering state is invalid."}
	for actor in result.actors.values():
		if source_schema >= 7 and not result.life_clock_token.is_empty() and (not actor.has("hunger") or not actor.has("calm") or not actor.has("mental")):
			return {"ok": false, "reason": "現地の生命状態が欠けています"}
		if actor.has("mental"):
			var mental_value = actor.mental
			if not (mental_value is int or mental_value is float) or not is_finite(float(mental_value)) or float(mental_value) != float(int(mental_value)) or int(mental_value) < 0 or int(mental_value) > CrewStatusDB.Mental.LIMIT:
				return {"ok": false, "reason": "現地の精神状態が不正です"}
			actor.mental = int(mental_value)
		if actor.has("life_move_mult") and (not (actor.life_move_mult is float or actor.life_move_mult is int) or not is_finite(float(actor.life_move_mult)) or float(actor.life_move_mult) <= 0.0 or float(actor.life_move_mult) > 1.0):
			return {"ok": false, "reason": "現地移動係数が不正です"}
		for key in ["hunger", "calm"]:
			if actor.has(key) and (not (actor[key] is float or actor[key] is int) or not is_finite(float(actor[key])) or float(actor[key]) < 0.0):
				return {"ok": false, "reason": "現地の生命状態が不正です"}
		if actor.has("hunger") and float(actor.hunger) > CrewStatusDB.MAX_HUNGER:
			return {"ok": false, "reason": "現地の空腹値が不正です"}
	if source_schema < 9:
		# Old snapshots have no reliable down-time. Do not grant a fresh deadline.
		if data.has("rescue") or result.actors.values().any(func(actor): return bool(actor.get("down", false))):
			return {"ok": false, "reason": "旧現地snapshotの救助残秒を安全に復元できません"}
	else:
		var rescue_result: Dictionary = RescueLedger.from_dict(data.get("rescue"), result.actors)
		if not rescue_result.get("ok", false):
			return rescue_result
		result.rescue_ledger = rescue_result.ledger
		for actor_id in result.actors:
			var row: Dictionary = result.rescue_ledger.case_for(actor_id)
			if bool(result.actors[actor_id].get("down", false)) and row.is_empty():
				return {"ok": false, "reason": "戦闘不能actorの救助残秒が欠けています"}
			# Active movement restoration needs path/ownership validation in a later unit.
			if row.get("phase", "") in ["assigned", "carried"]:
				return {"ok": false, "reason": "C現地の救助中snapshot復元はまだ接続されていません"}
	result._normalize_fixed_parking()
	return {"ok": true, "session": result}

## Legacy relay snapshots: preserve cargo, ownership and actor coordinates, repath returns.
## No save file is overwritten by loading. Completed ledger entries stay completed.
func _normalize_fixed_parking() -> void:
	var changed := parking_slot != PARKING_ENTRY or phase in ["reposition_recall", "reposition_travel"]
	parking_slot = PARKING_ENTRY
	if phase in ["reposition_recall", "reposition_travel"]:
		cancel_reposition()
	reposition_target_slot = ""
	reposition_seconds_left = 0.0
	if not changed:
		return
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if str(actor.get("state", "")) in ["dock_wait", "capacity_wait"]:
			# Cargo still belongs to this actor until docking completes at the entrance.
			actor["state"] = "to_base" if int(actor.get("carry_n", 0)) > 0 else "to_base_empty"
			actor["wait_reason"] = "入口の固定停車位置へ帰還"
		_refresh_actor_path(str(actor_id))
	dock_queue.clear()
	dock_busy.clear()
	_log("旧停車設定を入口固定へ移行。仲間位置と貨物は保持し帰還経路を更新")

func _vertical_slice_valid() -> bool:
	if not vertical_slice:
		return field_frame_exchange.is_empty() and return_handcart_exchange.is_empty() and field_tool_swap.is_empty() and _equipment_support_map_authorized() and _field_tool_maps_authorized()
	if outpost_enabled or single_worker_demo or parking_slot not in [PARKING_ENTRY, PARKING_RELAY] or intermediate_access not in ["blocked", "clearing", "cleared"]:
		return false
	if reposition_target_slot not in ["", PARKING_ENTRY, PARKING_RELAY] or field_capacity_limit_weight < 0:
		return false
	if phase in ["reposition_recall", "reposition_travel"] and reposition_target_slot.is_empty():
		return false
	return _field_frame_exchange_valid() and _return_handcart_exchange_valid() and _field_tool_swap_valid() and _equipment_support_map_authorized() and _field_tool_maps_authorized()

func _mine_path_engineering_valid() -> bool:
	if not mine_path_engineering:
		# Pre-mine saves may be active vertical-slice sessions. Their existing
		# clearance state legitimately uses clearing/cleared and is validated by
		# _vertical_slice_valid(), not by this mine-only invariant.
		return true if vertical_slice else intermediate_access == "blocked" and maintenance_actor_id.is_empty()
	if vertical_slice or (outpost_enabled and not is_region_boss()) or single_worker_demo:
		return false
	for actor in actors.values():
		if bool(actor.get("down", false)) or float(actor.get("hp", 0.0)) <= 0.0:
			return false
	if intermediate_access not in ["blocked", "clearing", "cleared"]:
		return false
	if intermediate_access == "clearing":
		if maintenance_actor_id.is_empty() or not actors.has(maintenance_actor_id):
			return false
		var worker: Dictionary = actors[maintenance_actor_id]
		return str(worker.get("role", "")) == "escort" and str(worker.get("state", "")) in ["maintenance_move", "maintenance_work"]
	return maintenance_actor_id.is_empty()


## v2〜v5 の通常sessionには v18 の携行採掘具 snapshot がない。
## それらは現地装備交換を記録していない場合に限り、現在の入場装備から安全に補う。
## 引渡し記録があるのに snapshot が欠ける入力は、所有者を再構成できないため拒否する。
func _migrate_legacy_entry_equipment(source_schema: int) -> bool:
	if source_schema >= 6:
		for actor_id in actors:
			if not _normalize_actor_tool_snapshots(actors[actor_id]):
				return false
		return true
	if not field_tool_swap.is_empty():
		return false
	var has_field_record := not field_frame_exchange.is_empty()
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		var has_all_entries := actor.has("entry_weapon") and actor.has("entry_work_support") and actor.has("entry_tools")
		if not has_all_entries:
			if has_field_record:
				return false
			actor["entry_weapon"] = int(actor.get("weapon", -1))
			actor["entry_work_support"] = int(actor.get("work_support", -1))
			actor["entry_tools"] = Dictionary(actor.get("tools", {})).duplicate(true)
		actor["field_tool_kit"] = {}
		actor["entry_field_tool_kit"] = {}
		actor["entry_gather_rank"] = maxi(0, int(actor.get("entry_gather_rank", 0)))
		actor["entry_gather_ability"] = maxf(0.05, float(actor.get("entry_gather_ability", 1.0)))
		if not _normalize_actor_tool_snapshots(actor):
			return false
	return true


## JSON restores numeric item IDs as generic numbers.  Normalize all actor
## tool maps before identity comparison so a real Worker `int` tool and its
## semantically identical fixture snapshot cannot disagree by Variant type.
func _normalize_actor_tool_snapshots(actor: Dictionary) -> bool:
	for field_name in ["tools", "entry_tools", "field_tool_kit", "entry_field_tool_kit"]:
		var raw: Variant = actor.get(field_name, null)
		if not raw is Dictionary:
			return false
		var normalized := {}
		for raw_slot in raw:
			normalized[str(raw_slot)] = int(raw[raw_slot])
		actor[field_name] = normalized
	actor["entry_gather_rank"] = maxi(0, int(actor.get("entry_gather_rank", 0)))
	actor["entry_gather_ability"] = maxf(0.05, float(actor.get("entry_gather_ability", 1.0)))
	return true


## A restored session may only change support ownership through the recorded
## escort→harvest frame handoff, followed by the recorded post-return cart
## exchange.  Matching a multiset alone would allow a tampered actor map to
## apply a real item to the wrong worker at commit.
func _equipment_support_map_authorized() -> bool:
	var expected := {}
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if not actor.has("entry_work_support"):
			return false
		var entry_support := int(actor.get("entry_work_support", -1))
		if entry_support >= 0 and entry_support not in GameData.SUPPORT_ITEMS:
			return false
		expected[actor_id] = entry_support
	if not field_frame_exchange.is_empty() and str(field_frame_exchange.get("status", "")) == "completed":
		var source_id := str(field_frame_exchange.get("source_id", ""))
		var target_id := str(field_frame_exchange.get("target_id", ""))
		if source_id.is_empty() or target_id.is_empty() or not expected.has(source_id) or not expected.has(target_id) or int(expected[source_id]) != GameData.Item.HAUL_FRAME or int(expected[target_id]) >= 0:
			return false
		expected[source_id] = -1
		expected[target_id] = GameData.Item.HAUL_FRAME
	if not return_handcart_exchange.is_empty() and str(return_handcart_exchange.get("status", "")) == "completed":
		var return_target_id := str(return_handcart_exchange.get("target_id", ""))
		if not committed or phase != "committed" or return_target_id.is_empty() or not expected.has(return_target_id) or int(return_handcart_exchange.get("old_item", -999)) != int(expected[return_target_id]):
			return false
		expected[return_target_id] = GameData.Item.HANDCART
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if int(actor.get("work_support", -1)) != int(expected.get(actor_id, -999)):
			return false
	return true


func _tool_map_valid(tool_map: Dictionary) -> bool:
	for raw_slot in tool_map:
		var slot := str(raw_slot)
		var item := int(tool_map[raw_slot])
		if not GatherDB.SLOTS.has(slot) or not GatherDB.is_tool_item(item) or GatherDB.slot_of_tool(item) != slot:
			return false
	return true


func _field_tool_kit_valid(kit: Dictionary) -> bool:
	if kit.size() > FIELD_TOOL_KIT_MAX_SLOTS:
		return false
	for raw_slot in kit:
		var slot := str(raw_slot)
		var item := int(kit[raw_slot])
		if slot != FIELD_TOOL_KIT_SLOT or item not in [FIELD_TOOL_KIT_ENTRY_ITEM, FIELD_TOOL_KIT_CARRIED_ITEM] or not GatherDB.is_tool_item(item) or GatherDB.slot_of_tool(item) != slot:
			return false
	return true


## Tool ownership is more restrictive than a multiset: a saved actor map may
## only differ from its own entry map through the recorded same-actor pair
## swap.  The harvest actor may toggle its own HAMMER/PICKAXE pair at safe
## relay boundaries, but the pair can never move to another hidden Worker.
func _field_tool_maps_authorized() -> bool:
	var recorded_target_id := ""
	if not field_tool_swap.is_empty():
		recorded_target_id = str(field_tool_swap.get("actor_id", ""))
		if recorded_target_id.is_empty() or not actors.has(recorded_target_id) or str(field_tool_swap.get("status", "")) not in ["scheduled", "completed"]:
			return false
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if not actor.has("tools") or not actor.has("entry_tools") or not actor.has("field_tool_kit") or not actor.has("entry_field_tool_kit") or not actor.has("entry_gather_rank") or not actor.has("entry_gather_ability"):
			return false
		var current_tools: Dictionary = Dictionary(actor.get("tools", {}))
		var entry_tools: Dictionary = Dictionary(actor.get("entry_tools", {}))
		var current_kit: Dictionary = Dictionary(actor.get("field_tool_kit", {}))
		var entry_kit: Dictionary = Dictionary(actor.get("entry_field_tool_kit", {}))
		if not _tool_map_valid(current_tools) or not _tool_map_valid(entry_tools) or not _field_tool_kit_valid(current_kit) or not _field_tool_kit_valid(entry_kit):
			return false
		if int(actor.get("entry_gather_rank", -1)) < 0 or float(actor.get("entry_gather_ability", 0.0)) <= 0.0:
			return false
		var expected_tools := entry_tools.duplicate(true)
		var expected_kit := entry_kit.duplicate(true)
		if not entry_kit.is_empty():
			if str(actor.get("role", "")) != FIELD_TOOL_KIT_ROLE or int(entry_tools.get(FIELD_TOOL_KIT_SLOT, -1)) != FIELD_TOOL_KIT_ENTRY_ITEM or int(entry_kit.get(FIELD_TOOL_KIT_SLOT, -1)) != FIELD_TOOL_KIT_CARRIED_ITEM:
				return false
		if str(actor_id) == recorded_target_id:
			if entry_kit.is_empty():
				return false
			var equipped_item := int(current_tools.get(FIELD_TOOL_KIT_SLOT, -1))
			var carried_item := int(current_kit.get(FIELD_TOOL_KIT_SLOT, -1))
			if not _field_tool_pair_supported(equipped_item, carried_item):
				return false
			expected_tools[FIELD_TOOL_KIT_SLOT] = equipped_item
			expected_kit[FIELD_TOOL_KIT_SLOT] = carried_item
		if current_tools != expected_tools or current_kit != expected_kit:
			return false
	return true


func _field_tool_swap_valid() -> bool:
	if field_tool_swap.is_empty():
		return true
	var status := str(field_tool_swap.get("status", ""))
	var actor_id := str(field_tool_swap.get("actor_id", ""))
	var recorded_equipped_item := int(field_tool_swap.get("equipped_item", -1))
	var recorded_carried_item := int(field_tool_swap.get("carried_item", -1))
	if status not in ["scheduled", "completed"] or actor_id.is_empty() or not actors.has(actor_id) or str(field_tool_swap.get("slot", "")) != FIELD_TOOL_KIT_SLOT or not _field_tool_pair_supported(recorded_equipped_item, recorded_carried_item):
		return false
	var actor: Dictionary = actors[actor_id]
	if str(actor.get("role", "")) != FIELD_TOOL_KIT_ROLE:
		return false
	var entry_tools: Dictionary = Dictionary(actor.get("entry_tools", {}))
	var entry_kit: Dictionary = Dictionary(actor.get("entry_field_tool_kit", {}))
	var current_tools: Dictionary = Dictionary(actor.get("tools", {}))
	var current_kit: Dictionary = Dictionary(actor.get("field_tool_kit", {}))
	if int(entry_tools.get(FIELD_TOOL_KIT_SLOT, -1)) != FIELD_TOOL_KIT_ENTRY_ITEM or int(entry_kit.get(FIELD_TOOL_KIT_SLOT, -1)) != FIELD_TOOL_KIT_CARRIED_ITEM:
		return false
	var current_equipped_item := int(current_tools.get(FIELD_TOOL_KIT_SLOT, -1))
	var current_carried_item := int(current_kit.get(FIELD_TOOL_KIT_SLOT, -1))
	if not _field_tool_pair_supported(current_equipped_item, current_carried_item):
		return false
	# v18 schema-6 sessions recorded the pre-swap pair for a completed exchange.
	# The completed state itself is safe in either orientation, while a scheduled
	# request must still match its current actor pair exactly before it can run.
	if status == "scheduled":
		return current_equipped_item == recorded_equipped_item and current_carried_item == recorded_carried_item
	return true

func _field_frame_exchange_valid() -> bool:
	if field_frame_exchange.is_empty():
		return true
	var status := str(field_frame_exchange.get("status", ""))
	var source_id := str(field_frame_exchange.get("source_id", ""))
	var target_id := str(field_frame_exchange.get("target_id", ""))
	if status not in ["scheduled", "completed"] or int(field_frame_exchange.get("support", -1)) != GameData.Item.HAUL_FRAME or source_id.is_empty() or target_id.is_empty() or source_id == target_id or not actors.has(source_id) or not actors.has(target_id):
		return false
	var source: Dictionary = actors[source_id]
	var target: Dictionary = actors[target_id]
	if str(source.get("role", "")) != "escort" or str(target.get("role", "")) != "harvest":
		return false
	if status == "scheduled":
		return int(source.get("work_support", -1)) == GameData.Item.HAUL_FRAME and int(target.get("work_support", -1)) < 0
	return int(source.get("work_support", -1)) < 0 and int(target.get("work_support", -1)) == GameData.Item.HAUL_FRAME and int(source.get("carry_limit", 0)) == GatherDB.CARRY_MAX and int(target.get("carry_limit", 0)) == GameData.HAUL_FRAME_LIMIT


func _return_handcart_exchange_valid() -> bool:
	if return_handcart_exchange.is_empty():
		return true
	var status := str(return_handcart_exchange.get("status", ""))
	var target_id := str(return_handcart_exchange.get("target_id", ""))
	if status not in ["reserved", "completed"] or int(return_handcart_exchange.get("item", -1)) != GameData.Item.HANDCART or target_id.is_empty() or not actors.has(target_id):
		return false
	var target: Dictionary = actors[target_id]
	if str(target.get("role", "")) != "carry":
		return false
	if status == "completed":
		return int(target.get("work_support", -1)) == GameData.Item.HANDCART and int(target.get("carry_limit", 0)) == GameData.HANDCART_LIMIT
	return int(target.get("work_support", -1)) != GameData.Item.HANDCART

func _single_worker_mode_valid() -> bool:
	if not single_worker_demo:
		if not single_worker_actor_id.is_empty():
			return false
		for actor_id in actors:
			var normal_actor: Dictionary = actors[actor_id]
			if bool(normal_actor.get("direct_depot_loop", false)) or bool(normal_actor.get("presentation_hidden", false)):
				return false
		return true
	# This mode is an explicit, isolated verification workflow: it never shares
	# the normal combat/outpost setup, and exactly one existing worker is allowed
	# to bypass the normal relay hand-off.
	if outpost_enabled or single_worker_actor_id != "worker:0" or not actors.has(single_worker_actor_id):
		return false
	var actor: Dictionary = actors[single_worker_actor_id]
	if str(actor.get("role", "")) != "solo" or not bool(actor.get("direct_depot_loop", false)) or bool(actor.get("presentation_hidden", false)):
		return false
	var allowed_support_states := ["idle"]
	if phase in ["recall", "ready_to_exit", "committed"]:
		# request_recall legitimately walks the hidden supporting crew home.  They
		# remain invisible and cannot pick up cargo or use the direct depot loop.
		allowed_support_states = ["idle", "wait_relay", "to_base_empty", "safe_wait", "injured_wait"]
	for actor_id in actors:
		if str(actor_id) == single_worker_actor_id:
			continue
		var support_actor: Dictionary = actors[actor_id]
		if bool(support_actor.get("direct_depot_loop", false)) or not bool(support_actor.get("presentation_hidden", false)) or str(support_actor.get("state", "")) not in allowed_support_states:
			return false
	return true

func _outpost_state_valid() -> bool:
	if encounter_id not in ["",FirstRegionCompletion.ENCOUNTER_ID]:return false
	if is_region_boss():
		return outpost_enabled and mine_path_engineering and FirstRegionCompletion.enemy_record_valid({"enemies":outpost_enemies,"cleared":outpost_cleared},actors.size()) and (encounter_entry.is_empty() or FirstRegionCompletion.enemy_record_valid(encounter_entry,actors.size()))
	if not encounter_entry.is_empty():return false
	if not outpost_enabled:
		return outpost_enemies.is_empty() and outpost_cleared
	if outpost_enemies.is_empty():
		return false
	for enemy_id in outpost_enemies:
		var enemy: Dictionary = outpost_enemies[enemy_id]
		if str(enemy.get("id", "")) != str(enemy_id) or str(enemy.get("kind", "")) != OUTPOST_KIND:
			return false
		if not is_finite(float(enemy.get("hp", -1.0))) or not is_finite(float(enemy.get("max_hp", -1.0))) or float(enemy.get("hp", -1.0)) < 0.0 or float(enemy.get("max_hp", -1.0)) <= 0.0:
			return false
	return outpost_cleared == (outpost_remaining() == 0)

static func project_fixture_path(file_name: String) -> String:
	if file_name.is_empty() or file_name.get_file() != file_name:
		return ""
	var root_path := ProjectSettings.globalize_path(TEST_ROOT_URI).simplify_path().replace("\\", "/")
	var candidate := ProjectSettings.globalize_path(TEST_ROOT_URI.path_join(file_name)).simplify_path().replace("\\", "/")
	return candidate if candidate.to_lower().begins_with(root_path.to_lower() + "/") else ""

func save_project_fixture(file_name := GUI_STATE_FILE) -> Dictionary:
	var path := project_fixture_path(file_name)
	if path.is_empty():
		return {"ok": false, "reason": "検証用保存先の名前が不正です"}
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return {"ok": false, "reason": "検証用保存先を作成できません: %s" % error}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "検証用保存を開けません: %s" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return {"ok": true, "path": path}

static func load_project_fixture(file_name := GUI_STATE_FILE) -> Dictionary:
	var path := project_fixture_path(file_name)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "reason": "検証用保存がありません"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "検証用保存を読めません: %s" % FileAccess.get_open_error()}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {"ok": false, "reason": "検証用保存JSONが不正です"}
	return from_dict(parser.data)

static func _point_array(point: Vector2) -> Array:
	return [point.x, point.y]
