class_name GatherDB
extends RefCounted
## 採取ポイント（岩場・鉱床・枯れ木）と、採取の道具の表（プロトタイプの仮の数値）。数値・計算式の調整はここだけでよい。
##
## 採取の結果は「採取ポイント × 道具 × 仲間の能力」で決まる（evaluate()）:
##  - 採取ポイント（POINTS）: 何が取れるか・残量（掘り出せる量）・1単位を掘る基準時間・どの枠の道具を使うか。
##  - 道具（TOOLS）: 採取ポイントの種類ごとの「取れる割合」eff（1.0 なら掘り出した分がすべて手に入る。残りは砕けて失われる）、
##    速さ、副産物（bonus）、扱うのに必要な回収ランク（need_rank）。道具がないときは素手（HANDS）。
##  - 仲間: 回収ランクが道具の必要ランクに届かないと、取れる割合が下がる（適性 fit）。回収の能力値（Worker.field_mult）は
##    速さに効き、取れる割合にも少し効く。
##      取れる割合 = 道具の相性 × 適性 × (1 + ABILITY_YIELD × (能力値 - 1))
##      1単位を掘る時間 = 採取ポイントの基準時間 ÷ (道具の速さ × 能力値)
##  例（鉱床。残量10）: 素手 → 約1個、簡易ハンマー → 約3個、鉄製ピッケル → 約7個、高性能ピッケル → 10個＋副産物。
##
## 流れ: 採取ポイントは砂漠に現れて後ろへ流れる。仲間が近づいて掘り、袋（CARRY_MAX 個）がいっぱいか残量が尽きたら倉庫へ運ぶ。
## 道具は加工でつくり（GameData.RECIPES）、倉庫から仲間へ持たせる（自動または個体情報で手動。Main.manage_tools / equip_tool）。
## 道具の耐久度は実装しない（ユーザーの決定。壊れる→作る→持たせる、の管理の手間が増えるため）。
## 将来（ユーザーの指示があるまで着手しない）: 植物・特殊素材の採取ポイントと道具、地域ごとの採取ポイント。

const SLOTS := {"mine": "採掘", "chop": "伐採"}       # 道具の枠。仲間は枠ごとに1つ持てる

## 採取ポイントの種類。amount = 残量の範囲、seconds = 1単位を掘る基準時間、weight = 現れやすさ、size = 絵の大きさ(px)
const POINTS := {
	"rock": {"name": "岩場", "item": GameData.Item.STONE, "amount": [10, 14], "seconds": 0.9, "weight": 3.0,
		"slot": "mine", "size": Vector2i(20, 12)},
	"vein": {"name": "鉱床", "item": GameData.Item.IRON_ORE, "amount": [6, 9], "seconds": 1.4, "weight": 1.5,
		"slot": "mine", "size": Vector2i(20, 13)},
	"tree": {"name": "枯れ木", "item": GameData.Item.WOOD, "amount": [8, 12], "seconds": 0.9, "weight": 4.0,
		"slot": "chop", "size": Vector2i(16, 24)},
}

## 素手（道具がないとき）。tier は道具の格（0 = なし）
const HANDS := {"name": "素手", "tier": 0, "slot": "", "eff": {"rock": 0.35, "vein": 0.10, "tree": 0.40},
	"speed": 0.8, "need_rank": 0, "bonus": {}}

## 道具。tier = 格、slot = 使う枠、eff = 種類ごとの取れる割合、speed = 速さ、need_rank = 必要な回収ランク（0=E …）、
## bonus = 副産物 {種類: {Item: 1個あたりの確率}}
const TOOLS := {
	GameData.Item.HAMMER: {"name": "簡易ハンマー", "tier": 1, "slot": "mine",
		"eff": {"rock": 0.70, "vein": 0.30}, "speed": 1.0, "need_rank": 0, "bonus": {}},
	GameData.Item.PICKAXE: {"name": "鉄製ピッケル", "tier": 2, "slot": "mine",
		"eff": {"rock": 1.00, "vein": 0.70}, "speed": 1.2, "need_rank": 2, "bonus": {}},
	GameData.Item.ADV_PICK: {"name": "高性能ピッケル", "tier": 3, "slot": "mine",
		"eff": {"rock": 1.00, "vein": 1.00}, "speed": 1.5, "need_rank": 4,
		"bonus": {"vein": {GameData.Item.STONE: 0.5}, "rock": {GameData.Item.IRON_ORE: 0.2}}},
	GameData.Item.AXE: {"name": "簡易の斧", "tier": 1, "slot": "chop",
		"eff": {"tree": 0.70}, "speed": 1.0, "need_rank": 0, "bonus": {}},
	GameData.Item.IRON_AXE: {"name": "鉄の斧", "tier": 2, "slot": "chop",
		"eff": {"tree": 1.00}, "speed": 1.3, "need_rank": 2, "bonus": {}},
}

# ---- 採取ポイントの出現・袋 ----
const SPAWN_DIST_MIN := 380.0            # 採取ポイントが現れる間隔（進んだ距離 px）。従来の落とし物（110〜190）より大きな塊が少ない間隔で
const SPAWN_DIST_MAX := 640.0
const CARRY_MAX := 3                     # 1回に運べる個数（袋）
const MIN_EFF := 0.15                    # 取れる割合がこれ未満なら、仲間はそのポイントを採らない（無駄になる）
const WORN_RATIO := 0.4                  # 残りがこの割合以下になると「減った」絵になる
# ---- 仲間の能力 ----
const FIT_STEP := 0.12                   # 回収ランクが必要ランクより1つ低いごとに、取れる割合が下がる量
const FIT_MIN := 0.5                     # 適性の下限
const ABILITY_YIELD := 0.30              # 能力値が1.0より高いぶんが、取れる割合に効く度合い
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
## eff = 取れる割合、seconds = 1単位を掘る時間、fit = 適性、bonus = 副産物 {Item: 確率}
static func evaluate(kind: String, tool_item: int, rank: int, ability: float) -> Dictionary:
	var p: Dictionary = POINTS[kind]
	var t: Dictionary = tool_def(tool_item)
	var tool_eff: float = float(t["eff"].get(kind, HANDS["eff"].get(kind, 0.0)))
	var fit := clampf(1.0 - FIT_STEP * maxf(0.0, float(int(t["need_rank"]) - rank)), FIT_MIN, 1.0)
	var eff := tool_eff * fit * (1.0 + ABILITY_YIELD * (ability - 1.0))
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
