class_name EventDB
extends RefCounted
## 旅の出来事の表（プロトタイプの仮データ）。数値の調整はここだけでよい。
##
## 出来事は Director（scripts/director.gd）が一定間隔で起こす。種類:
##   weather … 天候。予報（warn 秒前）が出て、しばらく続く。対処方針（stances）を選べる。
##   attack  … 襲撃。予報のあと敵が現れる。対処方針（迎え撃つ・振り切る・防備を固める）を選べる。
##   trouble … 突発のトラブル（故障など）。予兆なし。仲間の修理・備蓄で対処する。
##   chance  … 好機（生物の群れ・漂流物）。狩猟・回収の方針で稼ぐ。
##
## 対処方針（stances）の各項目は「倍率」で、書かなかった項目は 1.0（変化なし）:
##   speed  … 進む速さ（0 = 停止）      wear   … 部位の傷み {Part: 倍率}
##   energy … 仲間の疲れやすさ          food   … 食料の減り
##   burn   … 走行の燃料の減り          heat   … 暖房などの燃料消費（1秒あたり）
##   spawn  … 資源・生物の出現（0 = 出ない）  outdoor … 屋外作業の速さ（0 = 屋外に出ない）
##   hull_dmg … 敵から車体が受ける被害  work … 仲間の作業全体の速さ
##   flee   … true なら、一定時間で襲撃を振り切れる

const FIRST_DELAY := 75.0          # ゲーム開始から最初の出来事まで（秒）
const GAP_MIN := 70.0              # 次の出来事までの間隔（秒）
const GAP_MAX := 130.0
const LOG_KEEP := 6                # 表示する記録の数
const FLEE_SECONDS := 9.0          # 「振り切る」を選び続けて、襲撃を振り切るまでの秒数
const MAX_ENEMIES := 6

## 敵の種類。hp・dmg（1秒あたりの車体への被害）・run（近づく速さ）・scale（大きさ）・drops（倒したときの戦利品と確率）
const ENEMIES := {
	"scorpion": {"name": "サソリ", "hp": 36.0, "dmg": 1.4, "run": 55.0, "scale": 1.0, "color": "8b2e2e",
		"drops": {GameData.Item.MEAT: 1.0, GameData.Item.HIDE: 0.4, GameData.Item.IRON_ORE: 0.25}},
	"big_scorpion": {"name": "大サソリ", "hp": 120.0, "dmg": 3.5, "run": 42.0, "scale": 1.6, "color": "55305f",
		"drops": {GameData.Item.MEAT: 2.0, GameData.Item.HIDE: 1.0, GameData.Item.IRON_ORE: 0.9}},
}

## 襲撃の対処方針（サソリ系で共通）
const RAID_STANCES := [
	{"id": "fight", "name": "迎え撃つ", "speed": 0.5,
		"note": "戦闘担当が戦う。進みは遅くなる。戦闘担当がいないと車体が削られる"},
	{"id": "flee", "name": "振り切る", "speed": 1.6, "burn": 1.8, "wear": {GameData.Part.DRIVE: 1.8}, "flee": true,
		"note": "全速で逃げる。燃料と走行装置を使うが、しばらくすると振り切れる"},
	{"id": "guard", "name": "防備を固める", "speed": 0.0, "hull_dmg": 0.4, "work": 0.7, "spawn": 0.0,
		"note": "停止して車体を守る。被害は小さいが、作業が遅くなり、進めない"},
]

const EVENTS := {
	"sandstorm": {
		"name": "砂嵐", "kind": "weather", "weight": 3.0, "warn": 25.0, "dur": [45.0, 70.0], "default": "slow",
		"warn_text": "砂嵐が近づいている", "start_text": "砂嵐が来た！", "end_text": "砂嵐が過ぎ去った",
		"stances": [
			{"id": "push", "name": "突っ切る", "speed": 1.0, "wear": {GameData.Part.HULL: 2.6, GameData.Part.DRIVE: 2.6},
				"energy": 1.35, "outdoor": 0.55, "spawn": 0.5,
				"note": "進み続けるが、車体と走行装置がひどく傷む"},
			{"id": "slow", "name": "減速して進む", "speed": 0.5, "wear": {GameData.Part.HULL: 1.3, GameData.Part.DRIVE: 1.2},
				"energy": 1.1, "outdoor": 0.75, "spawn": 0.7,
				"note": "傷みを抑えつつ、ゆっくり進む"},
			{"id": "halt", "name": "停止して耐える", "speed": 0.0, "wear": {GameData.Part.HULL: 0.5, GameData.Part.DRIVE: 0.0},
				"outdoor": 0.0, "spawn": 0.0,
				"note": "ほとんど傷まないが、進めず資源も来ない。屋外作業は不可"},
		],
	},
	"heatwave": {
		"name": "酷暑", "kind": "weather", "weight": 2.5, "warn": 30.0, "dur": [55.0, 80.0], "default": "ease",
		"warn_text": "気温が上がってきた", "start_text": "酷暑が始まった！", "end_text": "暑さが和らいだ",
		"stances": [
			{"id": "run", "name": "走り続ける", "speed": 1.0, "wear": {GameData.Part.MACHINE: 1.8, GameData.Part.DRIVE: 1.2},
				"energy": 1.7, "burn": 1.1,
				"note": "進み続けるが、仲間がひどく疲れ、加工設備が傷む"},
			{"id": "ease", "name": "速度を落とす", "speed": 0.6, "wear": {GameData.Part.MACHINE: 1.4},
				"energy": 1.25, "burn": 0.95,
				"note": "疲れと傷みを抑えつつ進む"},
			{"id": "shade", "name": "日陰で休む（停止）", "speed": 0.0, "wear": {GameData.Part.MACHINE: 0.6},
				"energy": 0.8, "burn": 0.0, "spawn": 0.0,
				"note": "仲間が疲れにくいが、進めず資源も来ない"},
		],
	},
	"coldsnap": {
		"name": "寒波", "kind": "weather", "weight": 2.0, "warn": 30.0, "dur": [60.0, 90.0], "default": "ease",
		"warn_text": "急に冷え込んできた", "start_text": "寒波が来た！", "end_text": "寒さが和らいだ",
		"stances": [
			{"id": "run", "name": "走り続ける", "speed": 1.0, "food": 1.5, "heat": 0.30, "energy": 1.15, "burn": 1.05,
				"note": "進み続けるが、食料と暖房の燃料をたくさん使う"},
			{"id": "ease", "name": "速度を落とす", "speed": 0.6, "food": 1.4, "heat": 0.22, "energy": 1.05,
				"note": "消費を抑えつつ進む"},
			{"id": "huddle", "name": "身を寄せ合う（停止）", "speed": 0.0, "food": 1.25, "heat": 0.14,
				"energy": 0.9, "burn": 0.0, "spawn": 0.0,
				"note": "消費は最小だが、進めず資源も来ない"},
		],
	},
	"raid_scorpion": {
		"name": "サソリの襲撃", "kind": "attack", "weight": 2.5, "warn": 14.0, "dur": [55.0, 75.0], "default": "fight",
		"min_distance": 6000.0, "enemy": "scorpion", "count": [1, 2], "count_per_distance": 25000.0,
		"warn_text": "地面が震えている…何かが近づいてくる", "start_text": "サソリの群れが襲ってきた！",
		"end_text": "襲撃が収まった", "stances": RAID_STANCES,
	},
	"raid_big": {
		"name": "大サソリの襲撃", "kind": "attack", "weight": 1.0, "warn": 18.0, "dur": [70.0, 90.0], "default": "fight",
		"min_distance": 16000.0, "enemy": "big_scorpion", "count": [1, 1], "count_per_distance": 999999.0,
		"warn_text": "巨大な影が地平線に見える…", "start_text": "大サソリが襲ってきた！",
		"end_text": "襲撃が収まった", "stances": RAID_STANCES,
	},
	"breakdown": {
		"name": "故障", "kind": "trouble", "weight": 3.0,
		"parts": {GameData.Part.DRIVE: 0.4, GameData.Part.HULL: 0.3, GameData.Part.MACHINE: 0.3}, "damage": [22.0, 38.0],
		"text": {GameData.Part.DRIVE: "車軸に亀裂が入った！走行装置が損傷", GameData.Part.HULL: "車体の外板が裂けた！車体が損傷",
			GameData.Part.MACHINE: "加工設備から火花が出た！加工設備が損傷"},
	},
	"herd": {
		"name": "生物の群れ", "kind": "chance", "weight": 2.0, "species": "hare", "count": [5, 8],
		"text": "スナウサギの群れを見つけた！ 狩りの好機",
	},
	"salvage": {
		"name": "漂流物", "kind": "chance", "weight": 1.5, "count": [4, 6],
		"items": {GameData.Item.IRON_ORE: 3.0, GameData.Item.WOOD: 2.0, GameData.Item.STONE: 1.0},
		"text": "打ち捨てられた残骸を見つけた！ 資源が散らばっている",
	},
}

## 予報のあと、時間のあいだ続き、対処方針を選べる出来事の種類
const TIMED_KINDS := ["weather", "attack"]


static func def(id: String) -> Dictionary:
	return EVENTS.get(id, {})


static func is_timed(id: String) -> bool:
	return def(id).get("kind", "") in TIMED_KINDS


static func stance_of(id: String, stance_id: String) -> Dictionary:
	for s in EVENTS.get(id, {}).get("stances", []):
		if s["id"] == stance_id:
			return s
	return {}


## 対処方針の効果を短い文にする（画面表示用）。
static func stance_summary(s: Dictionary) -> String:
	var parts: Array = []
	if s.has("speed"):
		parts.append("停止" if s["speed"] <= 0.0 else "速度×%.1f" % s["speed"])
	if s.has("wear"):
		var m := 0.0
		for p in s["wear"]:
			m = maxf(m, s["wear"][p])
		parts.append("傷み×%.1f" % m if m > 0.0 else "傷みなし")
	if s.has("energy"):
		parts.append("疲れ×%.2f" % s["energy"])
	if s.has("food"):
		parts.append("食料×%.2f" % s["food"])
	if s.has("heat"):
		parts.append("暖房燃料+%.2f/秒" % s["heat"])
	if s.has("burn") and s.get("speed", 1.0) > 0.0:
		parts.append("走行燃料×%.2f" % s["burn"])
	if s.has("outdoor"):
		parts.append("屋外作業不可" if s["outdoor"] <= 0.0 else "屋外作業×%.2f" % s["outdoor"])
	if s.has("spawn"):
		parts.append("資源出現なし" if s["spawn"] <= 0.0 else "資源出現×%.1f" % s["spawn"])
	if s.has("hull_dmg"):
		parts.append("車体の被害×%.1f" % s["hull_dmg"])
	if s.has("work"):
		parts.append("作業×%.1f" % s["work"])
	if s.get("flee", false):
		parts.append("%d秒で振り切れる" % int(FLEE_SECONDS))
	return "　".join(PackedStringArray(parts))
