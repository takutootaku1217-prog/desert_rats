class_name FirstRegionCompletion
extends RefCounted
## Adopted: boss + primary route. Concrete encounter/HP/route are provisional.
## Separate from the legacy three-enemy outpost and from rewards.
const VERSION := 1
const ENCOUNTER_ID := "c_quarry_boss_v1"
const BOSS_ID := "boss:quarry_master"
const BOSS_NAME := "採石場の主"
const BOSS_KIND := "sand_stalker"
const BOSS_HP := 72.0
const BOSS_HOME := Vector2(842,326)
const BOSS_LANE := "採石場の主・独立挑戦"
const ENEMY_KEYS := ["id","kind","lane","home_x","home_y","x","y","hp","max_hp","attack_left","target","engager","dead"]

static func empty() -> Dictionary:
	return {"version":VERSION,"encounters":{},"completed":false}

static func boss_returned(progress: Dictionary) -> bool:
	return bool(progress.get("encounters",{}).get(ENCOUNTER_ID,{}).get("cleared",false))

static func route_connected(region: Dictionary) -> bool:
	return bool(region.get("roads",{}).get("bd",{}).get("cleared",false))

static func enemy_record_valid(record: Variant, crew_count: int) -> bool:
	if not record is Dictionary or record.size()!=2 or not record.get("cleared") is bool or not record.get("enemies") is Dictionary: return false
	if record.enemies.size()!=1 or not record.enemies.get(BOSS_ID) is Dictionary: return false
	var e:Dictionary=record.enemies[BOSS_ID]
	if e.size()!=ENEMY_KEYS.size(): return false
	for key in ENEMY_KEYS:
		if not e.has(key): return false
	if e.id!=BOSS_ID or e.kind!=BOSS_KIND or e.lane!=BOSS_LANE: return false
	for key in ["home_x","home_y","x","y","hp","max_hp","attack_left"]:
		if typeof(e[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(e[key])): return false
	if e.home_x!=BOSS_HOME.x or e.home_y!=BOSS_HOME.y or e.max_hp!=BOSS_HP: return false
	if e.hp<0.0 or e.hp>BOSS_HP or not e.dead is bool or e.dead!=(e.hp==0.0) or record.cleared!=e.dead: return false
	for key in ["target","engager"]:
		if not e[key] is String: return false
		if e[key]=="": continue
		if not e[key].begins_with("worker:") or not e[key].trim_prefix("worker:").is_valid_int(): return false
		var i:=int(e[key].trim_prefix("worker:"))
		if i<0 or i>=crew_count or e[key]!="worker:"+str(i): return false
	return true

static func valid(progress: Variant, region: Dictionary, first: bool, crew_count: int) -> bool:
	if not progress is Dictionary: return false
	if not first: return progress.is_empty()
	if progress.size()!=3 or not progress.get("version") is int or progress.version!=VERSION or not progress.get("encounters") is Dictionary or not progress.get("completed") is bool: return false
	if progress.encounters.size()>1: return false
	if not progress.encounters.is_empty() and (not progress.encounters.has(ENCOUNTER_ID) or not enemy_record_valid(progress.encounters[ENCOUNTER_ID],crew_count)): return false
	return progress.completed==(boss_returned(progress) and route_connected(region))

static func snapshot(progress: Dictionary, region: Dictionary) -> Dictionary:
	var boss:=boss_returned(progress)
	var road:=route_connected(region)
	var complete:=bool(progress.get("completed",false))
	return {"boss_returned":boss,"route_connected":road,"completed":complete,
		"title":"第1地域突破" if complete else "第1地域の目標",
		"text":"%s：%s撃破・帰還確定 / %s：B–D再接続" % ["達成" if boss else "未達",BOSS_NAME,"達成" if road else "未達"],
		"detail":"Dから次地域入口・旧緑道へ往復できます。停車して採取し、売買・補給はAへ。手動保存で続きから再開できます。次地域の奥地・終幕は未実装です。" if complete else "Cの独立挑戦で撃破し、全員と荷物を帰還確定。BまたはDで倒木を処理。全舗装・全建設は不要です。"}
