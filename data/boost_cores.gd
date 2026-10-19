class_name BoostCores
extends RefCounted
## プレイヤー操作用の走行ブースト試作。負荷は 0=休止直後、100=連続使用限界。
## 数値と構成名をここに集め、燃料・設備・電力網とは接続しない。

const SUSTAINED := "sustained"
const BURST := "burst"
const SPEED_MULTIPLIER := 1.5
const MAX_LOAD := 100.0

const PROFILES := {
	SUSTAINED: {
		"name": "持続型コア",
		"active_seconds": 8.0,
		"recover_seconds": 24.0,
		"summary": "8秒連続 / 24秒で負荷解消",
	},
	BURST: {
		"name": "短時間型コア",
		"active_seconds": 2.0,
		"recover_seconds": 6.0,
		"summary": "2秒連続 / 6秒で負荷解消",
	},
}


static func valid_id(id: String) -> bool:
	return PROFILES.has(id)


static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, PROFILES[SUSTAINED]).duplicate(true)


static func load_per_second(id: String) -> float:
	return MAX_LOAD / float(profile(id)["active_seconds"])


static func recovery_per_second(id: String) -> float:
	return MAX_LOAD / float(profile(id)["recover_seconds"])
