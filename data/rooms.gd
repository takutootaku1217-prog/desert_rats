class_name Rooms
extends RefCounted
## 車体の区画（スロット）と部屋の種類の表（プロトタイプの仮データ）。「今後の順番 2」。
## 部屋の効果・費用・置ける階・必要な拠点レベルはここに書く。見た目は tools/art_base.py で作る重ね絵
## （assets/base/rooms/<系統>/room_<区画>_<種類>.png）で、区画の位置は tools/art_base.py の SLOTS と同じ値にする。
##
## 仕組み: 車体の絵 hull.png は初期配置の部屋が焼き込まれている。入れ替え可能な4つの区画には、
## 部屋の種類ごとの重ね絵を上から描いて見た目を変える。加工設備・倉庫・ベッドの位置も区画から決まる。
## コックピット（上階・右）と搬入口（下階・右）は入れ替えできない（斜路・動線の要のため）。
##
## 建設（data/facilities.gd。ワークベンチ・ベッド）との役割分担:
##   部屋の変更 = 車体の区画そのものを、どの部屋にするか（この表。画面は ui/base_ui.gd の「部屋の変更 (R)」）
##   建設       = 部屋の中に設備を足す（FacilityDB。"room" が、どの部屋の中に置くか）。部屋を移すと、中の設備も一緒に動く。
## 現行ゲームの機能を持つ部屋（加工室・寝室・倉庫・機関室）は unique（拠点に1つ）。別の区画に建てると移設になり、
## 加工設備・倉庫・ベッド・ワークベンチも新しい区画へ移る（MobileBase.apply_layout / facility_spots）。
## 部屋の変更は、その場で倉庫の材料を使って行う（仲間の作業は要らない。建設のような取り置きもしない）。

## 座標の考え方（data/art_spec.gd）: この表の座標・大きさは、すべて「論理ユニット」（ゲームの基準の長さ。画面上は ×UNIT）で、
## 絵が何ドットで描かれているか（絵の細かさ）とは関係がない。絵を高精細にしても、この表は変えない。
##   ワールド座標（画面のpx）… 仲間・加工設備・倉庫の位置。下の processor_pos などが、ユニットから計算して返す。
##   部屋の中の論理座標 … 区画の左端・床からのユニット（dx・dy）。設備の位置（FacilityDB の "dx"）・ANCHORS がこれ。
##   絵のドット … 絵の画像のピクセル。描く側（ui・BaseExterior・MobileBase）が、絵ごとの細かさから計算する。
const UNIT := ArtSpec.UNIT_PX          # 論理ユニット1つ = 画面の何px（ユニット → ワールド座標）
const STYLE := "desert"        # 見た目の系統。将来サイバーパンクなどを足すときはここを切り替える

## 入れ替え可能な区画（論理ユニット。車体の左上 GameData.HULL_POS が原点）。x0..x1 = 部屋の内側の列、top/feet = 部屋の上端と床の行。
## floor は GameData の階（2=上 1=下）、side は "u"/"l"（部屋の "floors" と対応）。
## door_x = ハシゴの側（隣の区画へ抜ける）入口の列。今は仲間の経路には使っていない（区画の間は自由に歩ける）が、将来、入口を通る経路にするときの基準。
const SLOTS := {
	"u1": {"name": "上階・左", "side": "u", "floor": 2, "x0": 8, "x1": 71, "top": 16, "feet": 40, "door_x": 72},
	"u2": {"name": "上階・右", "side": "u", "floor": 2, "x0": 82, "x1": 137, "top": 16, "feet": 40, "door_x": 81},
	"l1": {"name": "下階・左", "side": "l", "floor": 1, "x0": 8, "x1": 71, "top": 43, "feet": 72, "door_x": 72},
	"l2": {"name": "下階・右", "side": "l", "floor": 1, "x0": 82, "x1": 149, "top": 43, "feet": 72, "door_x": 81},
}
const SLOT_ORDER := ["u1", "u2", "l1", "l2"]
const DEFAULT_LAYOUT := {"u1": "workshop", "u2": "bedroom", "l1": "engine", "l2": "storage"}

## 固定の部屋（入れ替えできない。表示用）。anchors = 部屋の中の決まった位置（車体の左端からのユニット）
const FIXED := [
	{"name": "操縦室", "side": "u"},
	{"name": "搬入口", "side": "l", "anchors": {"fuel": 165.0}},        # 機関室がないときの燃料の投入口
]

## 部屋の種類ごとの「部屋の中の決まった位置」（区画の左端からのユニット）。加工設備・倉庫・炉の口は、部屋の見た目ではなく、ここで決まる。
## 別の見た目（高精細・別の系統）の絵に替えても、機能の位置は変わらない。設備（ワークベンチ・ベッド）の位置は FacilityDB の "dx"。
const ANCHORS := {
	"workshop": {"processor": 33.0},       # 加工設備（機械の中心）
	"storage": {"storage": 34.0},          # 倉庫（棚の中心）
	"engine": {"furnace": 36.0},           # 燃料の投入口（炉の口）
}

## 部屋の種類。
##  floors: 置ける階（u=上 l=下）  cost: 建てる費用（現行の GameData.Item だけ。倉庫の枠に収まる量）  min_base_level: 必要な拠点レベル
##  unique: 拠点に1つだけ（別の区画に建てると、元の区画は空き部屋になる＝移設。中の設備も一緒に移る）
##  required: 最低1つは必要（最後の1つは壊せない）。加工室・寝室・倉庫は、なくなるとゲームが回らないので必須。
##    機関室は必須にしない（区画を空けるため）。ないときは、燃料を搬入口で補給する（MobileBase.engine_point）。
##  effects: [{kind, value}]  kind は host_processor / host_storage / rest_rate / drain_cut / train_xp
##    rest_rate（休憩の回復）と drain_cut（スタミナの消耗）は Worker が読む（Main.room_effect）。train_xp は訓練の仕組みがまだないので未使用。
## 費用は、旧版の素材を今の素材に置き換えたもの（金属→鉄、板材→木材、布→皮、骨の加工品→骨）を、今の素材の集まりやすさに合わせて調整した。
const TYPES := {
	"workshop": {"name": "加工室", "floors": "ul", "unique": true, "required": true, "min_base_level": 1,
		"cost": {GameData.Item.WOOD: 3, GameData.Item.IRON: 2},
		"desc": "加工設備とワークベンチを置く部屋。移すと中の物も一緒に動く。",
		"effects": [{"kind": "host_processor", "value": 1}]},
	"bedroom": {"name": "寝室", "floors": "ul", "unique": true, "required": true, "min_base_level": 1,
		"cost": {GameData.Item.HIDE: 3, GameData.Item.WOOD: 2},
		"desc": "ベッドを置く部屋（ベッドは 建設 (B) で最大3つ）。移すとベッドも一緒に動く。",
		"effects": []},
	"storage": {"name": "倉庫", "floors": "l", "unique": true, "required": true, "min_base_level": 1,
		"cost": {GameData.Item.WOOD: 4, GameData.Item.STONE: 3},
		"desc": "素材棚と加工品置き場。移すと中の物も一緒に動く。",
		"effects": [{"kind": "host_storage", "value": 1}]},
	"engine": {"name": "機関室", "floors": "l", "unique": true, "required": false, "min_base_level": 1,
		"cost": {GameData.Item.IRON: 2, GameData.Item.STONE: 2},
		"desc": "ボイラーと炉。燃料はここで補給する（ないときは搬入口で補給）。",
		"effects": []},
	"infirmary": {"name": "医務室", "floors": "ul", "unique": false, "required": false, "min_base_level": 1,
		"cost": {GameData.Item.HIDE: 3, GameData.Item.BONE: 2},
		"desc": "休憩中のスタミナの回復が早くなる（1室ごとに +25%）。",
		"effects": [{"kind": "rest_rate", "value": 0.25}]},
	"mess": {"name": "食堂", "floors": "ul", "unique": false, "required": false, "min_base_level": 1,
		"cost": {GameData.Item.FOOD: 3, GameData.Item.WOOD: 2},
		"desc": "仲間のスタミナが減りにくくなる（1室ごとに -12%。合計で最大 -50%）。",
		"effects": [{"kind": "drain_cut", "value": 0.12}]},
	"training": {"name": "訓練室", "floors": "ul", "unique": false, "required": false, "min_base_level": 2,
		"cost": {GameData.Item.IRON: 2, GameData.Item.BONE: 3},
		"desc": "「訓練」で得られる経験値が増える（1室ごとに +50%）。訓練の仕組みと拠点レベルは、まだない。",
		"effects": [{"kind": "train_xp", "value": 0.5}]},
	"empty": {"name": "空き部屋", "floors": "ul", "unique": false, "required": false, "min_base_level": 1,
		"cost": {},
		"desc": "何も置いていない部屋。あとで別の部屋に建て替えられる。",
		"effects": []},
}
## 一覧に並べる順番
const TYPE_ORDER := ["workshop", "bedroom", "storage", "engine", "infirmary", "mess", "training", "empty"]

const CAP_DRAIN_CUT := 0.5            # 食堂でスタミナの消耗を減らせる上限


# ------------------------------------------------------------------
# 配置の検査・更新（layout = {区画: 種類} を受け取って新しい layout を返すだけ。状態は持たない）
# ------------------------------------------------------------------
static func default_layout() -> Dictionary:
	return DEFAULT_LAYOUT.duplicate()


static func count(layout: Dictionary, rtype: String) -> int:
	var n := 0
	for s in SLOT_ORDER:
		if layout.get(s, "") == rtype:
			n += 1
	return n


## その種類の部屋がある区画（unique な部屋は1つだけ。複数あれば区画の順で最初。なければ ""）。
static func slot_of(layout: Dictionary, rtype: String) -> String:
	for s in SLOT_ORDER:
		if layout.get(s, "") == rtype:
			return s
	return ""


static func can_place(rtype: String, slot: String) -> bool:
	return TYPES.has(rtype) and SLOTS.has(slot) and TYPES[rtype]["floors"].contains(SLOTS[slot]["side"])


## 建てられない理由。建てられるなら ""（材料の不足は含めない）。
static func block_reason(layout: Dictionary, slot: String, rtype: String, base_level: int) -> String:
	if not can_place(rtype, slot):
		return "この階には置けない"
	var cur: String = layout.get(slot, "empty")
	if cur == rtype:
		return "すでに%sです" % TYPES[rtype]["name"]
	var t: Dictionary = TYPES[rtype]
	if base_level < t["min_base_level"]:
		return "拠点Lv%dで解放" % t["min_base_level"]
	# 今ある部屋を壊すと必要な部屋が無くなる場合は不可（同じ種類を移設するときは、新しい方を建てるので問題ない）
	var c: Dictionary = TYPES[cur]
	if c["required"] and count(layout, cur) <= 1:
		return "最後の%sは壊せない" % c["name"]
	return ""


## slot に rtype を建てた後の layout。unique な部屋が別の区画にあれば、そちらは空き部屋になる（移設）。
static func with_room(layout: Dictionary, slot: String, rtype: String) -> Dictionary:
	var out := layout.duplicate()
	if TYPES[rtype]["unique"]:
		for s in SLOT_ORDER:
			if s != slot and out.get(s, "") == rtype:
				out[s] = "empty"
	out[slot] = rtype
	return out


## 移設になるか（unique な部屋が別の区画に既にある）。
static func is_relocation(layout: Dictionary, slot: String, rtype: String) -> bool:
	if not TYPES[rtype]["unique"]:
		return false
	for s in SLOT_ORDER:
		if s != slot and layout.get(s, "") == rtype:
			return true
	return false


## セーブデータ等から読んだ配置を検査して直す。壊れていたら初期配置に戻す。
static func sanitize(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
		return default_layout()
	var out := {}
	for s in SLOT_ORDER:
		var t = raw.get(s, "")
		if not can_place(str(t), s):
			return default_layout()
		out[s] = str(t)
	for t in TYPES:
		if TYPES[t]["required"] and count(out, t) < 1:
			return default_layout()
		if TYPES[t]["unique"] and count(out, t) > 1:
			return default_layout()
	return out


## 全ての部屋の効果 kind の value 合計。
static func total(layout: Dictionary, kind: String) -> float:
	var sum := 0.0
	for s in SLOT_ORDER:
		var t: String = layout.get(s, "empty")
		for e in TYPES[t]["effects"]:
			if e["kind"] == kind:
				sum += float(e["value"])
	return sum


## その部屋（種類）の効果の説明。
static func effect_text(rtype: String) -> String:
	return TYPES[rtype]["desc"]


# ------------------------------------------------------------------
# 位置（ワールド座標）。車体の左上 GameData.HULL_POS からの論理ユニット × UNIT。絵の細かさとは関係がない
# ------------------------------------------------------------------
static func slot_feet_y(slot: String) -> float:
	return GameData.HULL_POS.y + float(SLOTS[slot]["feet"]) * UNIT


## 区画に重ねる絵の描画範囲（ワールド座標。天井の吊り金具のぶん、上に2ユニット広い。絵の細かさに依存しない）
static func overlay_rect(slot: String) -> Rect2:
	var s: Dictionary = SLOTS[slot]
	var pos := Vector2(GameData.HULL_POS.x + float(s["x0"]) * UNIT, GameData.HULL_POS.y + float(s["top"] - 2) * UNIT)
	return Rect2(pos, slot_size(slot) * float(UNIT))


static func overlay_path(slot: String, rtype: String) -> String:
	return "res://assets/base/rooms/%s/room_%s_%s.png" % [STYLE, slot, rtype]


## 部屋の中の論理座標 → ワールド座標。dx = 区画の左端からのユニット、dy = 床からのユニット（上が正）。
static func local_to_world(slot: String, dx: float, dy: float = 0.0) -> Vector2:
	return Vector2(GameData.HULL_POS.x + (float(SLOTS[slot]["x0"]) + dx) * UNIT, slot_feet_y(slot) - dy * UNIT)


## 区画の中の、足元の位置。dx = 区画の左端からのユニット（設備の中心。data/facilities.gd の "dx"）。
static func floor_pos(slot: String, dx: float) -> Vector2:
	return local_to_world(slot, dx)


## その区画にある部屋の決まった位置（ANCHORS）の、足元のワールド座標。
static func anchor_pos(slot: String, rtype: String, anchor: String) -> Vector2:
	return local_to_world(slot, float(ANCHORS[rtype][anchor]))


## 加工設備を置く位置（加工室の床。機械の中心）
static func processor_pos(slot: String) -> Vector2:
	return anchor_pos(slot, "workshop", "processor")


## 倉庫の中心（棚の中心）
static func storage_pos(slot: String) -> Vector2:
	return anchor_pos(slot, "storage", "storage")


## 機関室の燃料の投入口（炉の口）
static func engine_pos(slot: String) -> Vector2:
	return anchor_pos(slot, "engine", "furnace")


## 機関室がないときの燃料の投入口（下の階の搬入口の中。搬入口は入れ替えできない固定の部屋）
static func fallback_fuel_pos() -> Vector2:
	return Vector2(GameData.HULL_POS.x + float(FIXED[1]["anchors"]["fuel"]) * UNIT, GameData.LO_Y)


## 区画の大きさ（論理ユニット。幅・高さ）
static func slot_size(slot: String) -> Vector2:
	var s: Dictionary = SLOTS[slot]
	return Vector2(float(s["x1"] - s["x0"] + 1), float(s["feet"] - s["top"] + 2))
