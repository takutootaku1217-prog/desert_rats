class_name SkillDB
extends RefCounted
## スキルの表（プロトタイプ用の仮データ）。効果の種類（kind）:
##   field_eff : 特定分野の作業効率 +value（key = 分野）
##   time_cut  : 作業時間 -value（key = 仕事。key なしなら全ての仕事）
##   yield_up  : 回収した資源が +1 個増える確率 +value
##   atk / def : 戦闘時の攻撃力 / 防御力 +value
##   all_eff   : 全分野の作業効率 +value（汎用）
## "home" はそのスキルが関連する分野（個体の得意分野に近いスキルが出やすくなる。-1 = 汎用）。
## "weight" は出やすさ。

const SKILLS := {
	"keen_eye": {"name": "目利き", "kind": "field_eff", "key": GameData.Field.GATHERER, "value": 0.15,
		"home": GameData.Field.GATHERER, "weight": 3.0},
	"sturdy_legs": {"name": "健脚", "kind": "time_cut", "key": GameData.Job.HAUL, "value": 0.15,
		"home": GameData.Field.GATHERER, "weight": 3.0},
	"scavenger": {"name": "拾い上手", "kind": "yield_up", "value": 0.15,
		"home": GameData.Field.GATHERER, "weight": 2.0},
	"weapon_design": {"name": "武器設計", "kind": "field_eff", "key": GameData.Field.DEV, "value": 0.15,
		"home": GameData.Field.DEV, "weight": 3.0},
	"armor_work": {"name": "装甲加工", "kind": "time_cut", "key": GameData.Job.PROCESS, "value": 0.15,
		"home": GameData.Field.DEV, "weight": 3.0},
	"quick_hands": {"name": "早業", "kind": "time_cut", "value": 0.08,
		"home": GameData.Field.DEV, "weight": 1.5},
	"survivor": {"name": "生還率", "kind": "def", "value": 0.15,
		"home": GameData.Field.COMBAT, "weight": 2.0},
	"spoils": {"name": "戦果", "kind": "atk", "value": 0.15,
		"home": GameData.Field.COMBAT, "weight": 2.0},
	"iron_fist": {"name": "鉄拳", "kind": "field_eff", "key": GameData.Field.COMBAT, "value": 0.15,
		"home": GameData.Field.COMBAT, "weight": 2.0},
	"preserve": {"name": "保存食", "kind": "field_eff", "key": GameData.Field.COOK, "value": 0.15,
		"home": GameData.Field.COOK, "weight": 3.0},
	"first_aid": {"name": "応急処置", "kind": "field_eff", "key": GameData.Field.MEDIC, "value": 0.15,
		"home": GameData.Field.MEDIC, "weight": 3.0},
	"all_rounder": {"name": "万能型", "kind": "all_eff", "value": 0.06,
		"home": -1, "weight": 1.5},
}


static func skill_name(id: String) -> String:
	return SKILLS[id]["name"] if SKILLS.has(id) else id


## ids のうち kind が一致し、key が合うスキルの効果量の合計。
## key を持たないスキルは常に対象になる（例: 全ての仕事の時間短縮）。
static func total(ids: Array, kind: String, key: int = -1) -> float:
	var sum := 0.0
	for id in ids:
		var s: Dictionary = SKILLS.get(id, {})
		if s.get("kind", "") != kind:
			continue
		if s.has("key") and s["key"] != key:
			continue
		sum += float(s["value"])
	return sum


static func describe(id: String) -> String:
	var s: Dictionary = SKILLS.get(id, {})
	if s.is_empty():
		return ""
	var pct := int(round(float(s["value"]) * 100.0))
	match s["kind"]:
		"field_eff":
			return "%sの作業効率 +%d%%" % [GameData.FIELD_NAMES[s["key"]], pct]
		"time_cut":
			var what: String = "全ての作業" if not s.has("key") else GameData.JOB_NAMES[s["key"]]
			return "%sの作業時間 -%d%%" % [what, pct]
		"yield_up":
			return "回収で資源が1個増える確率 +%d%%" % pct
		"atk":
			return "戦闘の攻撃力 +%d%%" % pct
		"def":
			return "戦闘の防御力 +%d%%" % pct
		"all_eff":
			return "全分野の作業効率 +%d%%" % pct
	return ""


## 個体に持たせるスキルを count 個選ぶ。ranks（分野→ランク）の高い分野に近いスキルが出やすい。
static func pick_for(ranks: Dictionary, count: int) -> Array:
	var pool: Array = SKILLS.keys()
	var top := 0
	for f in ranks:
		top = maxi(top, ranks[f])
	var chosen: Array = []
	for n in count:
		if pool.is_empty():
			break
		var weights: Array = []
		for id in pool:
			var s: Dictionary = SKILLS[id]
			var w: float = s["weight"]
			var home: int = s["home"]
			if home >= 0 and ranks.get(home, 0) >= top:
				w *= Balance.SKILL_HOME_BIAS
			weights.append(w)
		var i := Balance.weighted_pick(weights)
		chosen.append(pool[i])
		pool.remove_at(i)
	return chosen
