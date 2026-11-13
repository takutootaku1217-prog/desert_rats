class_name GatherDB
extends RefCounted
## 採取ポイント（岩場・鉱床・枯れ木）と、採取の道具の表（プロトタイプの仮の数値）。数値・計算式の調整はここだけでよい。
##
## eff は同じ作業時間で採れる主素材量の倍率。残量1から主素材1を移す。
## 素手は木のみ、木製採掘具で石、石のハンマーで鉄鉱石を解放。
## 運搬・狩猟にはこの制限を適用しない。道具耐久は導入しない。

## 旧版の素手伐採の eff0.40×speed0.8 = 0.32 を基準速度として維持。
## 道具の1/2/3/4はこの基準に対する同時間の量比。絶対速度を約3倍へ跳ね上げない。
const BASE_YIELD_RATE := 0.32

const SLOTS := {"mine": "採掘", "chop": "伐採"}       # 道具の枠。仲間は枠ごとに1つ持てる

## 採取ポイントの種類。amount = 残量の範囲、seconds = 採取量倍率の基準時間、weight = 現れやすさ、size = 絵の大きさ(px)
const POINTS := {
	"rock": {"name": "岩場", "item": GameData.Item.STONE, "amount": [10, 14], "seconds": 0.9, "weight": 3.0,
		"slot": "mine", "size": Vector2i(20, 12)},
	"vein": {"name": "鉱床", "item": GameData.Item.IRON_ORE, "amount": [6, 9], "seconds": 1.4, "weight": 1.5,
		"slot": "mine", "size": Vector2i(20, 13)},
	"tree": {"name": "枯れ木", "item": GameData.Item.WOOD, "amount": [8, 12], "seconds": 0.9, "weight": 4.0,
		"slot": "chop", "size": Vector2i(16, 24)},
}

## 素手（道具がないとき）。tier は道具の格（0 = なし）
const HANDS := {"name": "素手", "tier": 0, "slot": "", "eff": {"rock": 0.0, "vein": 0.0, "tree": 1.0},
	"speed": 1.0, "need_rank": 0, "bonus": {}}

## 暫定倍率。基準時間は共通で、上位ほど同時間の採取数が増える。既存アイテムIDを維持。
const TOOLS := {
	GameData.Item.WOOD_PICK: {"name": "木製採掘具", "tier": 1, "slot": "mine",
		"eff": {"rock": 2.0, "vein": 0.0}, "speed": 1.0, "need_rank": 0, "bonus": {}},
	GameData.Item.WOOD_AXE: {"name": "木製の斧", "tier": 1, "slot": "chop",
		"eff": {"tree": 2.0}, "speed": 1.0, "need_rank": 0, "bonus": {}},
	GameData.Item.HAMMER: {"name": "石のハンマー", "tier": 2, "slot": "mine",
		"eff": {"rock": 3.0, "vein": 3.0}, "speed": 1.0, "need_rank": 0, "bonus": {}},
	GameData.Item.AXE: {"name": "石の斧", "tier": 2, "slot": "chop",
		"eff": {"tree": 3.0}, "speed": 1.0, "need_rank": 0, "bonus": {}},
	GameData.Item.PICKAXE: {"name": "鉄製ピッケル", "tier": 3, "slot": "mine",
		"eff": {"rock": 4.0, "vein": 4.0}, "speed": 1.0, "need_rank": 2, "bonus": {}},
	GameData.Item.IRON_AXE: {"name": "鉄の斧", "tier": 3, "slot": "chop",
		"eff": {"tree": 4.0}, "speed": 1.0, "need_rank": 2, "bonus": {}},
	GameData.Item.ADV_PICK: {"name": "高性能ピッケル", "tier": 4, "slot": "mine",
		"eff": {"rock": 5.0, "vein": 5.0}, "speed": 1.0, "need_rank": 4,
		"bonus": {"vein": {GameData.Item.STONE: 0.5}, "rock": {GameData.Item.IRON_ORE: 0.2}}},
}

# ---- 採取ポイントの出現・袋 ----
const SPAWN_DIST_MIN := 380.0            # 採取ポイントが現れる間隔（進んだ距離 px）。従来の落とし物（110〜190）より大きな塊が少ない間隔で
const SPAWN_DIST_MAX := 640.0
const CARRY_MAX := 3                     # 1回に運べる個数（袋）
const MIN_EFF := 0.15                    # 採取量倍率がこれ未満なら、仲間はそのポイントを採らない（無駄になる）
const WORN_RATIO := 0.4                  # 残りがこの割合以下になると「減った」絵になる
# ---- 仲間の能力 ----
const FIT_STEP := 0.12                   # 回収ランクが必要ランクより1つ低いごとに、採取量倍率が下がる量
const FIT_MIN := 0.5                     # 適性の下限
const ABILITY_YIELD := 0.30              # 能力値が1.0より高いぶんが、採取量倍率に効く度合い
# ---- 道具の自動割り当て ----
const TOOL_CHECK_SECONDS := 1.5          # 倉庫の道具を仲間に持たせ直す間隔
const TOOL_MIN_GAIN := 0.05              # これ以上よくなるときだけ持たせ替える（行ったり来たりを防ぐ）


static func tool_def(item: int) -> Dictionary:
	return TOOLS.get(item, HANDS)


static func is_tool_item(item: int) -> bool:
	return TOOLS.has(item)


static func tier_of(item: int) -> int:
	return int(tool_def(item)["tier"])


static func slot_of_tool(item: int) -> String:
	return String(TOOLS[item]["slot"]) if TOOLS.has(item) else ""


static func slot_of_point(kind: String) -> String:
	return String(POINTS[kind]["slot"])


## 出現する採取ポイントの種類を、重みでひとつ選ぶ
static func pick_kind() -> String:
	var total := 0.0
	for k in POINTS:
		total += float(POINTS[k]["weight"])
	var r := randf() * total
	for k in POINTS:
		r -= float(POINTS[k]["weight"])
		if r <= 0.0:
			return k
	return "tree"


## 採取ポイント kind を、道具 tool_item（-1 = 素手）・回収ランク rank・能力値 ability の仲間が掘るときの結果。
## eff = 基準時間あたりの主素材量、seconds = 基準時間、fit = 適性、bonus = 副産物 {Item: 確率}
static func evaluate(kind: String, tool_item: int, rank: int, ability: float) -> Dictionary:
	var p: Dictionary = POINTS[kind]
	var t: Dictionary = tool_def(tool_item)
	var tool_eff: float = float(t["eff"].get(kind, HANDS["eff"].get(kind, 0.0)))
	var fit := clampf(1.0 - FIT_STEP * maxf(0.0, float(int(t["need_rank"]) - rank)), FIT_MIN, 1.0)
	var eff := BASE_YIELD_RATE * tool_eff * fit * (1.0 + ABILITY_YIELD * (ability - 1.0))
	var seconds := float(p["seconds"]) / maxf(0.05, float(t["speed"]) * ability)
	return {"eff": maxf(0.0, eff), "seconds": seconds, "fit": fit, "tool_eff": tool_eff, "bonus": t["bonus"].get(kind, {}),
			"tool_name": t["name"]}


## 道具の枠 slot での、その道具の総合点（1秒あたりに手に入る量の目安。採取ポイントの出やすさで平均）。
## 道具を持たせ替えるかの判断と、道具を作る必要があるかの判断に使う。
static func tool_score(slot: String, tool_item: int, rank: int, ability: float) -> float:
	var total := 0.0
	var score := 0.0
	for k in POINTS:
		if POINTS[k]["slot"] != slot:
			continue
		var w := float(POINTS[k]["weight"])
		var ev := evaluate(k, tool_item, rank, ability)
		total += w
		score += w * float(ev["eff"]) / float(ev["seconds"])
	return score / maxf(0.001, total)


static func requirement(kind: String) -> String:
	return {"rock": "木製採掘具以上が必要", "vein": "石のハンマー以上が必要", "tree": "素手で採取可能"}.get(kind, "")

static func result_text(kind: String, item: int, rank: int, ability: float) -> String:
	var ev := evaluate(kind, item, rank, ability)
	if float(ev["eff"]) < MIN_EFF:
		return "%s：%s" % [POINTS[kind]["name"], requirement(kind)]
	return "%s：%.1f個/秒" % [POINTS[kind]["name"], float(ev["eff"]) / float(ev["seconds"])]
