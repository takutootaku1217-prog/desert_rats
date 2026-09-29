class_name CrewStatusDB
extends RefCounted
## 仲間のステータス（HP・満腹度・疲労度・精神状態）の設定（プロトタイプの仮の数値）。**調整はここだけ**でよい。
##
## 仲間1人ごとに持つ:
##   hp（HP）… 身体の耐久力。0 で戦闘不能（死亡ではない）。休憩で回復（医務室でさらに早い）。
##   hunger（満腹度）… 100 = 満腹、0 = 完全な空腹。時間で減り、食料を食べて回復（仲間ごとに個別。全員共通の空腹は廃止）。
##   fatigue（疲労度）… 仕事・移動を続けた結果として蓄積する疲れ。**数値が高いほど悪い**。休憩で徐々に下がる。
##   精神状態 … 数値ではなく、疲労度を中心に、満腹度・HP・危険な出来事（stress）から**計算される状態**（好調・普通・不安・不調・限界）。
## 悪い状態は「少し効率が落ちる」を基本にし、完全に止まる条件はHP 0に限る。
## 複数のステータスが悪くても、効率は掛け算せず「いちばん悪いもの」で決める。精神状態は小さな補正だけ加える。
## 計算は scripts/crew_status.gd（CrewStatus）、データは Worker、表示は ui/（データを読むだけ）。
##
## 「悪い側」の向き: HP・満腹度は低いほど悪い（low_is_bad）。疲労度は高いほど悪い（high_is_bad）。

const STATS := ["hp", "hunger", "fatigue"]
const STAT_NAMES := {"hp": "HP", "hunger": "満腹度", "fatigue": "疲労度"}
const ICON_FILES := {"hp": "hp", "hunger": "hunger", "fatigue": "fatigue"}      # assets/ui/<名前>.png と <名前>_mask.png
## 精神状態の顔の絵（Mental の並び順。assets/ui/<名前>.png。白っぽく描いてあり、MENTAL_COLORS で染める）
const MENTAL_ICON_FILES := ["mental_good", "mental_normal", "mental_anxious", "mental_bad", "mental_limit"]

enum Mental { GOOD, NORMAL, ANXIOUS, BAD, LIMIT }
const MENTAL_NAMES := ["好調", "普通", "不安", "不調", "限界"]
## 精神状態ごとの作業速度の補正（速度の補正は「いちばん悪い状態」で決め、精神状態はそれより悪いときだけ効く。好調だけは他が良好なら上乗せ）
const MENTAL_WORK := [1.05, 1.0, 0.95, 0.85, 0.70]

# ------------------------------------------------------------------
# 最大値・初期値（0〜100）
# ------------------------------------------------------------------
const MAX_HP := 100.0
const MAX_HUNGER := 100.0
const MAX_FATIGUE := 100.0
const MAX_STAT := {"hp": MAX_HP, "hunger": MAX_HUNGER, "fatigue": MAX_FATIGUE}
## 新しく加入した仲間・いまの3人の初期値（精神状態は「普通」から。好調は、落ち着いた時間が続くと上がる）
const START_HP := 100.0
const START_HUNGER := 100.0
const START_FATIGUE := 0.0

# ------------------------------------------------------------------
# 状態による速度補正: 段階 = [基準の値, 作業速度の倍率, 移動速度の倍率]
#   low_is_bad（HP・満腹度）: 値 < 基準 の最初の段階（小さい基準から並べる）。どれにも当たらなければ 100%。
#   high_is_bad（疲労度）: 値 >= 基準 の最初の段階（大きい基準から並べる）。
# ------------------------------------------------------------------
const _LOW_STEPS := [[15.0, 0.5, 0.6], [25.0, 0.7, 0.8], [50.0, 0.9, 0.95]]
const EFFECTS := {
	"hp": {"dir": "low_is_bad", "steps": _LOW_STEPS},
	"hunger": {"dir": "low_is_bad", "steps": _LOW_STEPS},
	"fatigue": {"dir": "high_is_bad", "steps": [[90.0, 0.5, 0.6], [75.0, 0.7, 0.8], [50.0, 0.875, 0.9], [25.0, 0.95, 0.95]]},
}

# ------------------------------------------------------------------
# 満腹度・食事
# ------------------------------------------------------------------
## （旧方式の「全員共通の空腹」＝倉庫の食料を時間で自動的に食べ、尽きると全員が 0.65 倍、は撤去した。仲間ごとの満腹度・食事・速度への影響に置き換わっている）
const HUNGER_DECAY_PER_MIN := 4.0          # 1分あたりの減り（初期案は 3〜5。天候の「食料の減り」の倍率が掛かる）
const EAT_BELOW := 25.0                    # これ未満になったら、自分から食事を優先する
const EAT_URGENT_BELOW := 15.0             # これ未満なら、休憩や仕事より先に食べに行く
const EAT_SECONDS := 1.2                   # 食べている時間
const EAT_RETRY_SECONDS := 6.0             # 食料が取れなかったあと、食べに行き直すまでの待ち（AIが食事のループにならないように）
## 食料1個の回復。将来、食料の種類（粗末・普通・高級・特殊）で回復量や追加効果を変えられるように、アイテムごとの表にしてある
const FOOD_EFFECTS := {
	GameData.Item.FOOD: {"hunger": 30.0, "fatigue": -6.0, "stress": -12.0},
}

# ------------------------------------------------------------------
# 疲労度
# ------------------------------------------------------------------
const FATIGUE_GAIN_ACTIVE := 0.20          # 動いている間の上昇/秒（仕事・移動）。待機中は上がらない
## 上がりやすくなる倍率（悪い状態で動き続けたとき）: [基準の値, 倍率]。値 < 基準 の最初の行を使う。満腹度とHPのうち、大きい倍率だけを使う（掛け算しない）
const FATIGUE_MULT_HUNGER := [[25.0, 1.5], [50.0, 1.2]]
const FATIGUE_MULT_HP := [[25.0, 1.6], [50.0, 1.3]]
const FATIGUE_REST_RATE := 1.2             # 眠っている間の低下/秒（医務室で早くなる）
const FATIGUE_DOWN_RATE := 0.5             # 戦闘不能で倒れている間の低下/秒

# ------------------------------------------------------------------
# HP
# ------------------------------------------------------------------
const HP_REST_RATE := 0.7                  # 眠っている間の回復/秒
const HP_DOWN_RATE := 0.35                 # 戦闘不能で倒れている間の回復/秒（放っておいても、いつか起き上がる）
const HP_REVIVE_AT := 20.0                 # 戦闘不能から起き上がるHP
## 危険な出来事・負傷
const RAID_HIT_HP := 1.5                   # 敵の攻撃1回（近くの仲間）で失うHP（敵の大きさの倍率が掛かる）
const RAID_HIT_STRESS := 8.0               # 攻撃を受けたときのストレス
const RAID_START_STRESS := 10.0            # 襲撃が始まったときの、全員のストレス
## 狩猟の事故: 獲物を倒したとき、[事故の確率, 失うHPの最小, 最大]
const HUNT_INJURY := {"hare": [0.03, 4.0, 8.0], "lizard": [0.08, 6.0, 12.0], "hump": [0.15, 8.0, 18.0]}

# ------------------------------------------------------------------
# 精神状態の判定（疲労度を中心に。上から順に、最初に当たったもの）
#   限界: 疲労度>=90 / HP<15 / 満腹度<15 / ストレス>=60    不調: 疲労度>=75 / 満腹度<25 / HP<25 / ストレス>=35
#   不安: 疲労度>=50 / 満腹度<50 / HP<50 / ストレス>=15
#   好調: 疲労度<25 かつ 満腹度>=50 かつ HP>=50 かつ ストレスが小さく、落ち着いた時間が CALM_SECONDS 続いた
#   普通: それ以外
# ------------------------------------------------------------------
const MENTAL_LIMIT := {"fatigue": 90.0, "hp": 15.0, "hunger": 15.0, "stress": 60.0}
const MENTAL_BAD := {"fatigue": 75.0, "hp": 25.0, "hunger": 25.0, "stress": 35.0}
const MENTAL_ANXIOUS := {"fatigue": 50.0, "hp": 50.0, "hunger": 50.0, "stress": 15.0}
const MENTAL_GOOD := {"fatigue": 25.0, "hp": 50.0, "hunger": 50.0, "stress": 5.0}
const CALM_SECONDS := 60.0                 # 好調になるのに要る、落ち着いた（疲れていない・空腹でない・健康な）時間
const STRESS_DECAY := 0.6                  # ストレスの減り/秒（安全な時間で消える）

# ------------------------------------------------------------------
# 自動行動（生活行動）の基準。仕事の優先度（★0〜5）はそのまま。ここは「仕事より先に休む・食べる」線
# ------------------------------------------------------------------
const REST_HP_URGENT := 25.0               # HPがこれ未満: 休憩・治療を優先
const REST_HP_CRITICAL := 15.0             # 危険。基本的に仕事を続けない
const REST_FATIGUE_URGENT := 75.0          # 疲労度がこれ以上: 休憩を優先
const REST_FATIGUE_CRITICAL := 90.0        # 極度の疲労。基本的に仕事を中断
const REST_STRESS_URGENT := 60.0           # ストレスがこれ以上: 休憩・安全確保
## 仕事の1つとしての休憩（優先度★の中で選ばれる）を始めてよい状態
const REST_JOB_FATIGUE_ABOVE := 50.0
const REST_JOB_HP_BELOW := 50.0
## ベッドが使えない（建てていない・すべて使用中）とき、本当に休みが必要な状態（上の「急ぎ」の線）なら、その場で簡易休憩する。
## 回復は、ベッドで眠るときの何割か（疲労度・HPに掛かる）。
## 休憩の優先度が★0の仲間は、これも休まない。ベッドが空いたら、そちらへ移る。
const REST_IN_PLACE_RATE := 0.33
## 休憩をやめてよい状態
const REST_END_FATIGUE := 20.0
const REST_END_HP := 80.0

# ------------------------------------------------------------------
# 表示（ui/）: アイコンの色・点滅・頭上の警告
# ------------------------------------------------------------------
## 色の段階: [「良い側の残量の割合」の上限, 色]（小さい順。IconGauge.stage_color）。疲労度は 残量 = 100 - 疲労度
const COLOR_GOOD := Color("7be07b")
const COLOR_CAUTION := Color("f0c040")
const COLOR_WARN := Color("e8892a")
const COLOR_DANGER := Color("e0533d")
const GAUGE_STAGES := {
	"hp": [[0.25, COLOR_DANGER], [0.5, COLOR_CAUTION], [1.01, COLOR_GOOD]],
	"hunger": [[0.25, COLOR_DANGER], [0.5, COLOR_CAUTION], [1.01, COLOR_GOOD]],
	"fatigue": [[0.25, COLOR_DANGER], [0.5, COLOR_WARN], [0.75, COLOR_CAUTION], [1.01, COLOR_GOOD]],
}
## 点滅する線（そのアイコンだけが点滅する）。HP・満腹度は 値 < この値、疲労度は 値 >= この値
const BLINK_LINE := {"hp": 15.0, "hunger": 15.0, "fatigue": 75.0}
## 精神状態のアイコンの色（好調・普通は緑、不安は黄、不調はだいだい、限界は赤）
const MENTAL_COLORS := [COLOR_GOOD, COLOR_GOOD, COLOR_CAUTION, COLOR_WARN, COLOR_DANGER]
## 頭上の警告（吹き出し）。危険ラインに達したステータスのうち、いちばん危険なものを1つだけ出す（優先順位は上から）。
## HP・満腹度は 値 < line、疲労度は 値 >= line、精神状態は「限界」のとき。blink はより強い警告（点滅）
const WARN_ORDER := ["hp", "hunger", "fatigue", "mental"]
const WARN_LINE := {"hp": 25.0, "hunger": 25.0, "fatigue": 75.0}
const WARN_STRONG := {"hp": 15.0, "hunger": 15.0, "fatigue": 90.0}     # ここまで悪いと点滅
const WARN_BUBBLE_SECONDS := 0.0           # 将来: 警告を出す時間（0 = 危険な間ずっと）。クールダウンを足せる場所

# ------------------------------------------------------------------
# 引き出し
# ------------------------------------------------------------------
static func max_of(stat: String) -> float:
	return float(MAX_STAT[stat])


## 悪い側の向き
static func is_high_bad(stat: String) -> bool:
	return String(EFFECTS[stat]["dir"]) == "high_is_bad"
