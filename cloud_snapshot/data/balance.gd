class_name Balance
extends RefCounted
## プロトタイプ用の仮の数値表。バランス調整はここだけを触ればよい。
## ランク関連の表は GameData.RANKS（E〜SSS+ の12段階）と同じ並び・同じ長さにすること。
##   並び: E D C B A A+ S S+ SS SS+ SSS SSS+

# ------------------------------------------------------------------
# ランク（才能・適性）
# ------------------------------------------------------------------
## ランクごとの能力値の土台（レベル1・才能1.0のとき）
const RANK_POWER := [10.0, 14.0, 19.0, 25.0, 32.0, 38.0, 46.0, 54.0, 64.0, 74.0, 86.0, 100.0]
## ランクごとの、部署ポイントへの加算（高ランクがいると部署が伸びやすい）
const RANK_DEPT_POINTS := [0.0, 0.0, 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 10.0, 13.0]
## 個体生成時の出現しやすさ（得意分野のランク）。現段階は E〜S を中心に、S+ 以上は 0（出ない）。
const RANK_SPAWN_WEIGHTS := [22.0, 24.0, 22.0, 14.0, 9.0, 5.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## 得意分野以外のランクは、得意分野のランクから 0〜4 段下がる。この配列は 0段〜4段下がる重み。
## （0段が出ると、複数の分野が同じ最高ランクになる）
const OTHER_RANK_DROP_WEIGHTS := [1.0, 3.0, 3.0, 2.0, 1.0]

# ------------------------------------------------------------------
# 個体の能力値・レベル・経験値
# ------------------------------------------------------------------
## 能力値 = RANK_POWER[ランク] × 才能(分野ごとの個体差) × (1 + 成長率 × (レベル-1))
const TALENT_MIN := 0.85
const TALENT_MAX := 1.15
const GROWTH_MIN := 0.04            # 1レベルごとの能力の伸び（個体差あり）
const GROWTH_MAX := 0.08
const DEFAULT_TALENT := 1.0
const DEFAULT_GROWTH := 0.06

const MAX_LEVEL := 20
const XP_BASE := 20.0               # Lv1→2 に必要な経験値
const XP_STEP := 10.0               # レベルが1上がるごとの増加分
## 経験値の入手（仕事を1回終えるごと）
const XP_GATHER := 4.0
const XP_HAUL := 2.0
const XP_PROCESS := 4.0
## 訓練: 加工品を使って経験値を得る（今は使い道のない加工品の使い道）
const TRAIN_XP := 12.0

# ------------------------------------------------------------------
# 仕事の速さ
# ------------------------------------------------------------------
## 仕事の速さ = WORK_BASE + 能力値 / WORK_DIV（さらにスキル・配置・部署の倍率が掛かる）
const WORK_BASE := 0.5
const WORK_DIV := 50.0

# ------------------------------------------------------------------
# 部署（分野ごとに1つ。個体を配置して発展させる）
# ------------------------------------------------------------------
const BASE_MAX_CREW := 6            # 拠点に置ける人数（収容人数の初期値。料理部の解放・拠点レベルで増える）
## 拠点レベル = 1 + (全部署の「レベル-1」の合計) ÷ BASE_LEVEL_DIV（切り捨て）。部署を育てるほど上がる。
const BASE_LEVEL_DIV := 6.0
const MAX_BASE_LEVEL := 10
const CREW_CAP_PER_BASE_LEVEL := 1   # 拠点レベルが1上がるごとの収容人数の増加
const DEPT_CAPACITY := 3            # 1部署に置ける人数
const DEPT_MAX_LEVEL := 10
## 部署ポイント = Σ(人数 1.0 + 能力値/10 + ランク加算) + スキルの相乗
const DEPT_MEMBER_POINT := 1.0
const DEPT_ABILITY_POINT := 10.0
const DEPT_SYNERGY_POINT := 1.5     # 同じスキルが2人以上いるとき、超過1人につき加算
## 部署レベル L に必要なポイント = DEPT_POINTS_DIV × (L-1)^2
const DEPT_POINTS_DIV := 2.0
## 部署の効率 = 1 + レベル分 + 最高ランク分
const DEPT_EFF_PER_LEVEL := 0.06
const DEPT_TOP_RANK_EFF := 0.03     # 部署内の最高ランクが B を超えた段数ごと
const DEPT_TOP_RANK_BASE := 3       # B = 3
## 配置の効果（その分野の仕事の速さに掛かる）
const ASSIGN_BONUS := 1.25          # 自分の分野の部署に配置
const OFF_DEPT_PENALTY := 0.9       # 別の分野の部署に配置（専念していない）
const OWN_DEPT_JOB_BIAS := 0.5      # 仕事選びで同じ優先度なら自分の部署の仕事を選びやすい

# ------------------------------------------------------------------
# スキル
# ------------------------------------------------------------------
## 個体が持つスキル数の重み（index = 個数）
const SKILL_COUNT_WEIGHTS := [0.0, 6.0, 3.0, 1.0]
## 個体のランクが高い分野に関連するスキルほど出やすい倍率
const SKILL_HOME_BIAS := 3.0
const SKILL_CAP_TIME_CUT := 0.5     # 作業時間短縮の上限
const SKILL_CAP_YIELD := 0.9        # 追加資源の確率の上限

# ------------------------------------------------------------------
# 拠点全体の効果
# ------------------------------------------------------------------
const REST_RATE := 9.0              # 睡眠中の元気回復/秒（医務部の効率が掛かる）
const DRAIN_WORK := 0.7             # 作業中の元気の消耗/秒（料理部の効率で軽くなる）
const DRAIN_IDLE := 0.25

# ------------------------------------------------------------------
# 個体の募集
# ------------------------------------------------------------------
const RECRUIT_COST := {GameData.Item.FOOD: 2}
const TRAIN_COST := {GameData.Item.FABRIC: 1}
## 新しいゲームを始めたときの倉庫の中身（加工品の使い道を試せるように）
const START_ITEMS := {GameData.Item.FOOD: 4, GameData.Item.FABRIC: 2}

# ------------------------------------------------------------------
# 進行速度・資源の出現（速度を落としても資源が溜まりすぎないようにする）
# ------------------------------------------------------------------
const SCROLL_SPEED_MIN := 20.0      # これ未満にはしない（0だと資源が画面から流れず無限に溜まる）
const SCROLL_SPEED_MAX := 200.0
const SCROLL_SPEED_STEP := 10.0
const SCROLL_SPEED_DEFAULT := 60.0
## 資源の出現間隔は、この速度のときが基準（速度が半分なら間隔はおよそ2倍にして、
## 画面上にいる資源の数がだいたい同じになるようにする）。
const SPAWN_REF_SPEED := SCROLL_SPEED_DEFAULT
const SPAWN_INTERVAL_MIN := 1.8
const SPAWN_INTERVAL_MAX := 3.2
## 速度による間隔の倍率の上限・下限（極端に間延び／連発しないための歯止め）
const SPAWN_INTERVAL_MULT_MIN := 0.6
const SPAWN_INTERVAL_MULT_MAX := 3.0
## 資源が万一とても長く画面に残ったときの保険（回収作業中のものは消さない）
const RESOURCE_MAX_AGE := 90.0

# ------------------------------------------------------------------
# セーブ
# ------------------------------------------------------------------
const AUTOSAVE_SEC := 20.0
const SAVE_PATH := "user://save.json"


## 進行速度を許される範囲に収める（古いセーブが今の下限より遅い速度を持っていても大丈夫なように）
static func clamp_scroll_speed(v: float) -> float:
	return clampf(v, SCROLL_SPEED_MIN, SCROLL_SPEED_MAX)


## Lv → 次のレベルに必要な経験値
static func xp_needed(level: int) -> float:
	return XP_BASE + XP_STEP * float(level - 1)


static func weighted_pick(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return 0
	var r := randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1
