class_name Unlocks
extends RefCounted
## 部署レベルで解放される機能（プロトタイプの仮データ）。「今後の順番 1」。
## 各分野のレベルが上がると、ここに並べた条件を満たすたびに1段ずつ解放される。
## kind（効果の種類）:
##   hopper_cap    : 加工設備に同時に置ける素材の数 +value（加算）
##   process_speed : 加工にかかる時間 ×value（1未満で短縮。乗算）
##   bone_rate     : 骨の出現しやすさ +value（加算。SPAWN_WEIGHTS に足す）
##   spawn_speed   : 資源が出現する間隔 ×value（1未満で短縮。乗算）
##   bed_cap       : ベッド +value（加算）
##   crew_cap      : 拠点の収容人数 +value（加算）
##   atk_bonus     : 戦闘部に配置した個体の攻撃力 +value（加算。戦闘解禁後に効く）
const TIERS := {
	GameData.Field.GATHERER: [
		{"level": 2, "kind": "bone_rate", "value": 1.0,
			"title": "骨の目利き", "desc": "骨（レアな素材）が出やすくなる"},
		{"level": 4, "kind": "spawn_speed", "value": 0.85,
			"title": "広域捜索", "desc": "資源が出現する間隔が短くなる"},
		{"level": 6, "kind": "spawn_speed", "value": 0.85,
			"title": "地形図の共有", "desc": "資源が出現する間隔がさらに短くなる"},
	],
	GameData.Field.DEV: [
		{"level": 2, "kind": "hopper_cap", "value": 2,
			"title": "増設ホッパー", "desc": "加工設備に置ける素材が2個増える"},
		{"level": 4, "kind": "process_speed", "value": 0.85,
			"title": "高速加工ライン", "desc": "加工にかかる時間が短くなる"},
		{"level": 6, "kind": "hopper_cap", "value": 2,
			"title": "増設ホッパーII", "desc": "加工設備に置ける素材がさらに2個増える"},
	],
	GameData.Field.MEDIC: [
		{"level": 2, "kind": "bed_cap", "value": 1,
			"title": "簡易寝床", "desc": "ベッドが1つ増える"},
		{"level": 5, "kind": "bed_cap", "value": 1,
			"title": "増設寝室", "desc": "ベッドがさらに1つ増える"},
	],
	GameData.Field.COOK: [
		{"level": 2, "kind": "crew_cap", "value": 1,
			"title": "配給改善", "desc": "拠点の収容人数が1増える"},
		{"level": 5, "kind": "crew_cap", "value": 1,
			"title": "非常食備蓄", "desc": "拠点の収容人数がさらに1増える"},
	],
	GameData.Field.COMBAT: [
		{"level": 2, "kind": "atk_bonus", "value": 0.15,
			"title": "武装強化", "desc": "戦闘部の攻撃力が上がる（戦闘解禁後に有効）"},
		{"level": 5, "kind": "atk_bonus", "value": 0.15,
			"title": "特別装甲", "desc": "戦闘部の攻撃力がさらに上がる（戦闘解禁後に有効）"},
	],
}


## field の解放段のうち、レベル level で解放済みのもの。
static func unlocked(field: int, level: int) -> Array:
	var out: Array = []
	for t in TIERS.get(field, []):
		if level >= t["level"]:
			out.append(t)
	return out


## field の次に解放される段（なければ null）。
static func next_tier(field: int, level: int):
	for t in TIERS.get(field, []):
		if level < t["level"]:
			return t
	return null


## 全分野の解放段のうち kind が一致するものの value 合計（加算系）。
## depts は Main.depts と同じ形（{分野 -> {level, ...}}）。
static func total(kind: String, depts: Dictionary) -> float:
	var sum := 0.0
	for f in TIERS:
		var lv: int = depts[f]["level"] if depts.has(f) else 1
		for t in unlocked(f, lv):
			if t["kind"] == kind:
				sum += float(t["value"])
	return sum


## 全分野の解放段のうち kind が一致するものの value 積（乗算系。短縮などに使う）。
static func mult(kind: String, depts: Dictionary) -> float:
	var m := 1.0
	for f in TIERS:
		var lv: int = depts[f]["level"] if depts.has(f) else 1
		for t in unlocked(f, lv):
			if t["kind"] == kind:
				m *= float(t["value"])
	return m
