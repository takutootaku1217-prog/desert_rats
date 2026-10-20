class_name VehicleLoadout
extends RefCounted
## Large mobile-base prototype data. Values are intentionally easy to tune.

const PARTS := {
	"chassis": [
		{"id":"large", "name":"大型・縦増築フレーム", "weight":0, "capacity":180, "defense":0, "materials":{"iron":18,"hide":6}, "desc":"3層の生活空間を持つ大型車体。部屋・設備は重量0。"},
		{"id":"reinforced_large", "name":"大型・補強フレーム", "weight":16, "capacity":220, "defense":1, "materials":{"iron":30,"hide":8}, "desc":"積載を増やし、車体骨組みで被害を1軽減。"},
	],
	"drive": [
		{"id":"wheels", "name":"走行：長距離ホイール", "weight":8, "speed":100, "fuel_mult":0.9, "materials":{"iron":6}, "desc":"最高速100、燃料消費0.9倍。"},
		{"id":"tracks", "name":"走行：砂漠履帯", "weight":18, "speed":70, "fuel_mult":1.1, "materials":{"iron":14,"hide":2}, "desc":"最高速70、重量と引き換えに安定した大型用履帯。"},
	],
	"power": [
		{"id":"diesel", "name":"動力：巡航ディーゼル", "weight":12, "speed_bonus":0, "fuel_mult":1.0, "materials":{"iron":10}, "desc":"標準の燃料消費。"},
		{"id":"turbo", "name":"動力：補助ターボ", "weight":20, "speed_bonus":25, "fuel_mult":1.35, "materials":{"iron":18,"hide":2}, "desc":"最高速+25、燃料消費1.35倍。"},
	],
	"primary": [
		{"id":"none", "name":"未装備", "weight":0, "damage":0, "ammo":0, "materials":{}, "desc":"主砲スロットを空ける"},
		{"id":"cannon", "name":"主砲：砂漠砲", "weight":28, "damage":30, "ammo":2, "materials":{"iron":8,"hide":2}, "desc":"単発高威力。発射ごとに弾薬2。"},
	],
	"secondary": [
		{"id":"none", "name":"未装備", "weight":0, "damage":0, "ammo":0, "materials":{}, "desc":"補助武装スロットを空ける"},
		{"id":"machine_gun", "name":"補助：連装機銃", "weight":12, "damage":11, "ammo":1, "materials":{"iron":4}, "desc":"軽量。発射ごとに弾薬1。"},
	],
	"armor": [
		{"id":"none", "name":"外装なし", "weight":0, "defense":0, "materials":{}, "desc":"防御補正なし。"},
		{"id":"plate", "name":"装甲：鉄板装甲", "weight":20, "defense":4, "materials":{"iron":10,"hide":2}, "desc":"敵の一撃を4軽減。"},
		{"id":"composite", "name":"装甲：積層装甲", "weight":30, "defense":7, "materials":{"iron":16,"hide":4}, "desc":"敵の一撃を7軽減。"},
	],
}

## Existing saves already support 360 cargo. Large must expand that baseline.
const LARGE_CAPACITY := 520
const MEDIUM_CAPACITY := 360

static func default_state() -> Dictionary:
	return {"chassis":"large", "drive":"wheels", "power":"diesel", "primary":"cannon", "secondary":"machine_gun", "armor":"plate", "ammo":12, "last_damage":0.0, "last_note":"試作装備を搭載"}

static func initial_state() -> Dictionary:
	var state := default_state()
	state["chassis"] = "medium"
	state["drive"] = "none"
	state["power"] = "none"
	state["primary"] = "none"
	state["secondary"] = "none"
	state["armor"] = "none"
	return state

static func part(slot: String, id: String) -> Dictionary:
	if slot == "chassis" and id == "medium":
		return {"id":"medium", "name":"�����t���[��", "weight":0, "capacity":360, "defense":0, "materials":{}, "desc":"���݂̕W���̎ԑ́B"}
	if id == "none" and slot in ["drive", "power"]:
		return {"id":"none", "name":"������", "weight":0, "speed":100 if slot == "drive" else 0, "speed_bonus":0, "fuel_mult":1.0, "materials":{}, "desc":"���p���b�g���󂯂�"}
	for row in PARTS.get(slot, []):
		if row.id == id:
			var result: Dictionary = row.duplicate(true)
			# Keep values centralized here while this remains prototype data. The
			# original mobile-base cargo limit was 360, so a large chassis never
			# reduces an existing save's capacity.
			if slot == "chassis": result["capacity"] = 620 if id == "reinforced_large" else 520
			return result
	return {}

static func selected(state: Dictionary, slot: String) -> Dictionary:
	return part(slot, str(state.get(slot, "none")))

static func equipment_weight(state: Dictionary) -> int:
	var total := 0
	for slot in ["chassis", "drive", "power", "primary", "secondary", "armor"]:
		total += int(selected(state, slot).get("weight", 0))
	return total

static func defense(state: Dictionary) -> float:
	return float(selected(state, "armor").get("defense", 0)) + float(selected(state, "chassis").get("defense", 0))

static func capacity(state: Dictionary) -> int:
	return int(selected(state, "chassis").get("capacity", LARGE_CAPACITY))

static func speed_limit(state: Dictionary) -> float:
	return float(selected(state, "drive").get("speed", 100)) + float(selected(state, "power").get("speed_bonus", 0))

static func fuel_mult(state: Dictionary) -> float:
	return float(selected(state, "drive").get("fuel_mult", 1.0)) * float(selected(state, "power").get("fuel_mult", 1.0))

static func valid(state) -> bool:
	if not state is Dictionary:
		return false
	if state.get("chassis") not in ["large", "reinforced_large", "medium"]:
		return false
	for slot in ["chassis", "drive", "power", "primary", "secondary", "armor"]:
		if part(slot, str(state.get(slot, ""))).is_empty():
			return false
	if typeof(state.get("ammo")) != TYPE_INT or state.ammo < 0 or state.ammo > 999:
		return false
	if typeof(state.get("last_damage")) not in [TYPE_FLOAT, TYPE_INT] or state.last_damage < 0:
		return false
	return state.get("last_note") is String
