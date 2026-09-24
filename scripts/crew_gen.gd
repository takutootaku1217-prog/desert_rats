class_name CrewGen
extends RefCounted
## 個体（仲間）の生成。出現率・能力の幅は data/balance.gd。
## 返す Dictionary は Worker.setup() にそのまま渡せる形（Worker.to_dict() と同じキー）。

const NAMES := ["ミナ", "ポコ", "コムギ", "ミル", "チビ", "サビ", "ヒゲ", "ドロ", "カリン", "ゴマ",
	"ソラ", "トト", "ナツメ", "マメ", "ピーナ", "ルル", "クルミ", "タネ", "モチ", "ノラ",
	"リョウ", "カイ", "ユイ", "ソウ", "アカリ", "テツ", "ミオ", "レン", "ハル", "イオ"]
## 見た目の種類（tools/art_chars.py の PALETTES と同じ。grey / tan / pink はセーブに入っているので名前を変えない）
const PALETTES := ["grey", "tan", "pink", "blue", "green", "red"]
## 仲間がネズミだった頃の初期メンバーの名前。古いセーブを読むときに人間の名前へ直す。
const LEGACY_NAMES := {"ネズ吉": "ハヤト", "チュー太": "ダイ"}


## 古い名前（ネズミだった頃）を今の名前に直す。それ以外はそのまま返す。
static func renamed(name: String) -> String:
	return LEGACY_NAMES.get(name, name)

## 得意分野を1つ決め、その分野のランクを出現率から引く。ほかの分野は少し低くなる。
static func generate(used_names: Array = []) -> Dictionary:
	var fields: Array = GameData.Field.values()
	var main_field: int = fields[randi() % fields.size()]
	var main_rank := Balance.weighted_pick(Balance.RANK_SPAWN_WEIGHTS)
	var ranks := {}
	var talent := {}
	var growth := {}
	for f in fields:
		if f == main_field:
			ranks[f] = main_rank
		else:
			var drop := Balance.weighted_pick(Balance.OTHER_RANK_DROP_WEIGHTS)
			ranks[f] = maxi(0, main_rank - drop)
		talent[f] = snappedf(randf_range(Balance.TALENT_MIN, Balance.TALENT_MAX), 0.01)
		growth[f] = snappedf(randf_range(Balance.GROWTH_MIN, Balance.GROWTH_MAX), 0.005)
	var n_skills := Balance.weighted_pick(Balance.SKILL_COUNT_WEIGHTS)
	var d := {
		"name": _pick_name(used_names),
		"palette": PALETTES[randi() % PALETTES.size()],
		"tint": _random_tint(),
		"level": 1,
		"xp": 0.0,
		"gender": randi() % GameData.GENDER_NAMES.size(),
		"ranks": ranks,
		"talent": talent,
		"growth": growth,
		"skills": SkillDB.pick_for(ranks, n_skills),
		"dept": -1,
		"energy": 100.0,
	}
	d["priorities"] = default_priorities(ranks, main_field)
	return d


## 得意分野に関わる仕事の優先度を高めにする。
static func default_priorities(ranks: Dictionary, main_field: int) -> Dictionary:
	var p := {
		GameData.Job.GATHER: 3, GameData.Job.HAUL: 3, GameData.Job.PROCESS: 3,
		GameData.Job.REST: 3, GameData.Job.COMBAT: 2, GameData.Job.REPAIR: 2,
	}
	for job in GameData.JOB_FIELD:
		if GameData.JOB_FIELD[job] == main_field and job != GameData.Job.REST:
			p[job] = mini(GameData.MAX_PRIORITY, p[job] + 2)
	return p


static func _pick_name(used: Array) -> String:
	var free: Array = []
	for n in NAMES:
		if not used.has(n):
			free.append(n)
	if not free.is_empty():
		return free[randi() % free.size()]
	var base: String = NAMES[randi() % NAMES.size()]
	var i := 2
	while used.has("%s%d" % [base, i]):
		i += 1
	return "%s%d" % [base, i]


## 同じ配色の個体を見分けやすくするための、ごくわずかな色のずらし。
static func _random_tint() -> String:
	var k := randf_range(0.86, 1.0)
	var c := Color(k + randf_range(-0.03, 0.03), k + randf_range(-0.03, 0.03), k + randf_range(-0.03, 0.03))
	return c.to_html(false)
