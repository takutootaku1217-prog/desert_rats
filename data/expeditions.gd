class_name ExpeditionDB
extends RefCounted
## 遺跡の探索（調査隊の派遣）の表（プロトタイプの仮データ）。数値の調整はここだけでよい。
##
## 流れ: 遺跡が見つかる（旅の出来事 kind "site"）→ 仲間を最大 MAX_PARTY 人選んで派遣 → 関門を順に越える → 戻る。
## 関門（step）ごとに「分野の実力」で成否が決まる。メンバーの力は Worker.field_mult(分野)。
##   実力 = メンバーの平均 × (1 + PARTY_BONUS × (人数 - 1))   … 人数が多いほど強いが、増やすほど得とは限らない
##   成功率 = clamp(BASE_CHANCE + CHANCE_SLOPE × 実力 ÷ 難しさ + 進め方の補正, MIN_CHANCE, MAX_CHANCE)
##   難しさ = 遺跡の difficulty × (1 + STEP_GROWTH × 何番目の関門か)
## 失敗すると全員のスタミナが減る（0になったら力尽きて撤退）。修理資材を持たせると、最初の失敗の被害を防げる。

const MAX_PARTY := 3
const BASE_CHANCE := 0.15
const CHANCE_SLOPE := 0.40
const PARTY_BONUS := 0.30
const STEP_GROWTH := 0.12
const MIN_CHANCE := 0.10
const MAX_CHANCE := 0.95
const FOOD_PER_MEMBER := 1                # 派遣するとき、1人ごとに食料を持たせる
const COMPLETE_RATIO := 0.6               # 成功がこの割合以上なら「踏破」（おまけの戦利品と設計図のチャンス）
const RETURN_SECONDS := 6.0               # 結果を画面に出しておく時間（戻ってから）

## 関門の種類。field = 使う分野、penalty = 失敗したときに全員が失うスタミナ
const STEPS := {
	"explore": {"name": "探索", "field": GameData.Field.GATHERER, "penalty": 8.0, "loot": 2,
		"ok": "使えそうな物を見つけた", "ng": "めぼしい物は見つからなかった"},
	"trap": {"name": "罠", "field": GameData.Field.DEV, "penalty": 22.0, "loot": 1,
		"ok": "罠を解除した", "ng": "罠にかかってしまった"},
	"guardian": {"name": "守護者", "field": GameData.Field.COMBAT, "penalty": 28.0, "loot": 1,
		"ok": "守護者を倒した", "ng": "守護者に追い払われた"},
	"hazard": {"name": "危険地帯", "field": GameData.Field.MEDIC, "penalty": 16.0, "loot": 1,
		"ok": "危険をやり過ごした", "ng": "体調を崩した"},
}

## 進め方。chance = 成功率の補正、reward = 戦利品の量、time = 所要時間の倍率
const APPROACHES := [
	{"id": "careful", "name": "慎重に", "chance": 0.15, "reward": 0.7, "time": 1.4,
		"note": "成功しやすいが、戦利品が少なく時間がかかる"},
	{"id": "normal", "name": "標準", "chance": 0.0, "reward": 1.0, "time": 1.0,
		"note": "ふつうの進め方"},
	{"id": "bold", "name": "大胆に", "chance": -0.12, "reward": 1.5, "time": 0.8,
		"note": "失敗しやすいが、戦利品が多く早い"},
]

## 遺跡の種類。stay = 見つかってから調べられる秒数、duration = 探索の所要秒数（標準）、
## steps = 関門の数、step_weights = 関門の種類の出やすさ、loot = 戦利品 {Item: [重み, 最小個数, 最大個数]}、
## blueprint = 踏破したときに設計図が見つかる確率
const SITES := {
	"ruins_small": {"name": "崩れた見張り台", "difficulty": 1.3, "steps": 3, "duration": 45.0, "stay": 150.0,
		"step_weights": {"explore": 3.0, "trap": 1.0, "guardian": 1.0, "hazard": 1.0},
		"loot": {GameData.Item.IRON: [2.0, 1, 2], GameData.Item.REPAIR_KIT: [2.0, 1, 1],
			GameData.Item.FUEL: [2.0, 1, 2], GameData.Item.FOOD: [1.5, 2, 3]},
		"blueprint": 0.15},
	"ruins_large": {"name": "古代の遺跡", "difficulty": 2.0, "steps": 5, "duration": 80.0, "stay": 180.0,
		"step_weights": {"explore": 2.0, "trap": 2.0, "guardian": 2.0, "hazard": 1.5},
		"loot": {GameData.Item.IRON: [2.5, 2, 3], GameData.Item.REPAIR_KIT: [2.0, 1, 2],
			GameData.Item.FUEL: [2.0, 2, 3], GameData.Item.FOOD: [1.0, 3, 4]},
		"blueprint": 0.5},
}


static func approach(id: String) -> Dictionary:
	for a in APPROACHES:
		if a["id"] == id:
			return a
	return APPROACHES[1]


## 成功率（0.1〜0.95）
static func chance(power: float, difficulty: float, step_index: int, approach_id: String) -> float:
	var need := difficulty * (1.0 + STEP_GROWTH * step_index)
	return clampf(BASE_CHANCE + CHANCE_SLOPE * power / need + approach(approach_id)["chance"], MIN_CHANCE, MAX_CHANCE)
