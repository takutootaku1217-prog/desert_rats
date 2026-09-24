class_name Rooms
extends RefCounted
## 車体の区画（スロット）と部屋の種類の表（プロトタイプの仮データ）。「今後の順番 2」。
## 部屋の効果・費用・置ける階・必要な拠点レベルはここに書く。見た目は tools/art_base.py で作る重ね絵
## （assets/base/rooms/<系統>/room_<区画>_<種類>.png）で、区画の位置は tools/art_base.py の SLOTS と同じ値にする。
##
## 仕組み: 車体の絵 hull.png は初期配置の部屋が焼き込まれている。入れ替え可能な4つの区画には、
## 部屋の種類ごとの重ね絵を上から描いて見た目を変える。加工設備・倉庫・ベッドの位置も区画から決まる。
## コックピット（上階・右）と搬入口（下階・右）は入れ替えできない（斜路・動線の要のため）。

const PX := GameData.PX
const STYLE := "desert"        # 見た目の系統。将来サイバーパンクなどを足すときはここを切り替える

## 入れ替え可能な区画。x0..x1 = 部屋の内側の列、top/feet = 部屋の上端行と床の行（hull.png のドット座標）。
## floor は GameData の階（2=上 1=下）、side は "u"/"l"（部屋の "floors" と対応）。
const SLOTS := {
	"u1": {"name": "上階・左", "side": "u", "floor": 2, "x0": 8, "x1": 71, "top": 16, "feet": 40},
	"u2": {"name": "上階・右", "side": "u", "floor": 2, "x0": 82, "x1": 137, "top": 16, "feet": 40},
	"l1": {"name": "下階・左", "side": "l", "floor": 1, "x0": 8, "x1": 71, "top": 43, "feet": 72},
	"l2": {"name": "下階・右", "side": "l", "floor": 1, "x0": 82, "x1": 149, "top": 43, "feet": 72},
}
const SLOT_ORDER := ["u1", "u2", "l1", "l2"]
const DEFAULT_LAYOUT := {"u1": "workshop", "u2": "bedroom", "l1": "engine", "l2": "storage"}

## 固定の部屋（表示用）
const FIXED := [
	{"name": "操縦室", "side": "u"},
	{"name": "搬入口", "side": "l"},
]

## 部屋の種類。
##  floors: 置ける階（u=上 l=下）  cost: 建てる費用  min_base_level: 必要な拠点レベル
##  unique: 拠点に1つだけ（別の区画に建てると、元の区画は空き部屋になる＝移設）
##  required: 最低1つは必要（最後の1つは壊せない）
##  effects: [{kind, value}]  kind は host_processor / host_storage / beds / rest_rate / drain_cut / train_xp
const TYPES := {
	"workshop": {"name": "加工室", "floors": "ul", "unique": true, "required": true, "min_base_level": 1,
		"cost": {GameData.Item.METAL: 3, GameData.Item.PLANK: 2},
		"desc": "加工設備が置かれる。素材を加工品にする。",
		"effects": [{"kind": "host_processor", "value": 1}]},
	"bedroom": {"name": "寝室", "floors": "ul", "unique": false, "required": true, "min_base_level": 1,
		"cost": {GameData.Item.FABRIC: 3, GameData.Item.PLANK: 2},
		"desc": "ベッドが3つ。増やすと同時に休める人数が増える。",
		"effects": [{"kind": "beds", "value": 3}]},
	"storage": {"name": "倉庫", "floors": "l", "unique": true, "required": true, "min_base_level": 1,
		"cost": {GameData.Item.PLANK: 4, GameData.Item.METAL: 1},
		"desc": "素材と加工品の棚。",
		"effects": [{"kind": "host_storage", "value": 1}]},
	"engine": {"name": "機関室", "floors": "l", "unique": false, "required": false, "min_base_level": 1,
		"cost": {GameData.Item.METAL: 4, GameData.Item.BONE_PROD: 1},
		"desc": "ボイラーと歯車。今は飾り（将来は動力・進行速度に関わる）。",
		"effects": []},
	"infirmary": {"name": "医務室", "floors": "ul", "unique": false, "required": false, "min_base_level": 1,
		"cost": {GameData.Item.FABRIC: 3, GameData.Item.BONE_PROD: 2},
		"desc": "休憩中の元気の回復が早くなる（1室ごとに +25%）。",
		"effects": [{"kind": "rest_rate", "value": 0.25}]},
	"mess": {"name": "食堂", "floors": "ul", "unique": false, "required": false, "min_base_level": 1,
		"cost": {GameData.Item.FOOD: 3, GameData.Item.PLANK: 2},
		"desc": "仲間の元気が減りにくくなる（1室ごとに -12%）。",
		"effects": [{"kind": "drain_cut", "value": 0.12}]},
	"training": {"name": "訓練室", "floors": "ul", "unique": false, "required": false, "min_base_level": 2,
		"cost": {GameData.Item.METAL: 2, GameData.Item.BONE_PROD: 3},
		"desc": "「訓練」で得られる経験値が増える（1室ごとに +50%）。",
		"effects": [{"kind": "train_xp", "value": 0.5}]},
	"empty": {"name": "空き部屋", "floors": "ul", "unique": false, "required": false, "min_base_level": 1,
		"cost": {},
		"desc": "何も置いていない部屋。あとで別の部屋に建て替えられる。",
		"effects": []},
}
## 一覧に並べる順番
const TYPE_ORDER := ["workshop", "bedroom", "storage", "engine", "infirmary", "mess", "training", "empty"]

const CAP_DRAIN_CUT := 0.5            # 食堂で元気の消耗を減らせる上限

## 医務部の解放（Unlocks の bed_cap）で増えるベッドは、hull.png に描かれた寝室とは別に、
## 操縦室の床に簡易の敷物として置く。
const EXTRA_BED_POINTS := [Vector2(808.0, 354.0), Vector2(852.0, 354.0)]


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
# 位置（ワールド座標）。hull.png の左上 GameData.HULL_POS からのドット座標 × PX
# ------------------------------------------------------------------
static func slot_feet_y(slot: String) -> float:
	return GameData.HULL_POS.y + float(SLOTS[slot]["feet"]) * PX


## 区画に重ねる絵の描画範囲（天井の吊り金具のぶん、上に2行広い）
static func overlay_rect(slot: String) -> Rect2:
	var s: Dictionary = SLOTS[slot]
	var pos := Vector2(GameData.HULL_POS.x + float(s["x0"]) * PX, GameData.HULL_POS.y + float(s["top"] - 2) * PX)
	var size := Vector2(float(s["x1"] - s["x0"] + 1), float(s["feet"] - s["top"] + 2)) * PX
	return Rect2(pos, size)


static func overlay_path(slot: String, rtype: String) -> String:
	return "res://assets/base/rooms/%s/room_%s_%s.png" % [STYLE, slot, rtype]


## 加工設備を置く位置（加工室の床。機械の中心は区画の左から33ドット）
static func processor_pos(slot: String) -> Vector2:
	return Vector2(GameData.HULL_POS.x + float(SLOTS[slot]["x0"] + 33) * PX, slot_feet_y(slot))


## 倉庫の中心（棚の中心は区画の左から34ドット）
static func storage_pos(slot: String) -> Vector2:
	return Vector2(GameData.HULL_POS.x + float(SLOTS[slot]["x0"] + 34) * PX, slot_feet_y(slot))


## 寝室のベッドの位置（3つ。区画の左から 9・24・39 ドット）
static func bed_points_of(slot: String) -> Array:
	var l: Array = []
	for i in 3:
		l.append(Vector2(GameData.HULL_POS.x + float(SLOTS[slot]["x0"] + 9 + 15 * i) * PX, slot_feet_y(slot)))
	return l
