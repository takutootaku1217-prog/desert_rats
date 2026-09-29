class_name FacilityDB
extends RefCounted
## 拠点の設備（建設できるもの）の表（プロトタイプの仮の数値）。設備を増やすときは、ここに足すだけでよい。
##
## 進行の考え方（素材 → 製作物 → 設備 → 新しい製作物）:
##  - 最初は「手作業」（加工設備）でできる簡単なものだけ。ベッドもまだない。
##  - 建設で設備を建てると、その設備を「必要設備」にしている製作物・設備が作れるようになる。
##      手作業 → ワークベンチ → ベッドなど → （将来）上位の製作設備 → 専門設備 …
##  - 何を建てるかはプレイヤーが決める（建設の画面 / Bキー）。材料の運搬と組み立ては仲間が自動で行う（加工と同じ仕組み）。
##
## 「必要設備」の書き方:
##  - 製作物: GameData.RECIPES の "station"（書かなければ手作業でできる）。
##  - 設備:   ここの "requires"（"" なら手作業でできる）。
##  - "station": true の設備は、その場所に仲間が行って作業する（製作物の必要設備に指定できる）。

## true なら、最初から全設備がある。自己診断・放置比較ツール用（ゲームでは false）。
static var start_all := false

const BASE_STATION_NAME := "手作業（加工設備）"
## 設備なしで始めるとき、最初の蓄えに足す物。最初のワークベンチ（木材＋鉄）を確実に建てられるようにする。
## 鉄鉱石は鉱床（岩場より後回し）から採り、精錬もしなければ鉄にならず、ベッドがないと元気が約2.5分で尽きて
## 加工が回らなくなるため、鉄がなくてワークベンチが建たない悪循環になる（自己診断 test_build.gd の通しで確認）。
const START_STOCK := {GameData.Item.IRON: 1}

## 建設の依頼に足りない材料（木材・石・鉄鉱石）は、回収の優先度をこの倍率で上げる（プレイヤーが★0にした素材は除く）。
## 上げないと、鉄鉱石のように得点の低い素材（鉱床は岩場より後回し）は、材料が集まらず建設が進まない。
const GATHER_BOOST := 3.0

## id -> 定義。
##  - name / desc: 画面に出す名前と説明
##  - cost: 材料 {Item: 個数}（倉庫から取り出す）。積載の枠（data/cargo.gd）より多くしないこと（集められなくなる）
##  - time: 組み立てにかかる基準の秒数（作業者の腕で変わる）  / field: その作業の分野
##  - max: 建てられる数  / requires: 必要設備（"" = 手作業）  / station: その設備で製作できるか
##  - room / dx: どの部屋（data/rooms.gd の種類）の中に置くか / 置き場所（max 個ぶん）の、部屋の左端からのドット数（設備の中心）。
##    設備は部屋の中に建つ。部屋を別の区画へ移すと、設備も一緒に動く（実際の位置は MobileBase.facility_spots）。仲間はそこへ行って作る
##  - sprite / frame / stride / frames: 絵（見た目は差し替えやすいようにここに集める）。sprite の %d は置き場所の番号。
##    frame = 1コマの基準の大きさ（ユニット。画面上は ×ArtSpec.UNIT_PX。絵を高精細にしても変えない）、stride = コマの間隔（ユニット。
##    横に並べた絵のとき。1枚絵は 0）、frames = コマ数。絵の細かさ（1ユニットのドット数）は、絵の幅から自動で決まる（data/art_spec.gd）
##  - capacity_bonus: 完成すると BaseStorage.capacity_bonus に足す量（積載できる最大の重さが増える。data/cargo.gd）。
##    書いていない設備は 0（積載量には関係ない）。Main.finish_build がここを読んで足す。
##  - effects: [{kind, value}]（仲間の休憩・消耗に効く。data/rooms.gd の部屋の効果と同じ形・同じ kind（rest_rate / drain_cut）で、
##    Main.room_effect が部屋の分とまとめて合計する。CrewStatus は room_effect を呼ぶだけなので変更不要。書いていない設備は []。
const FACILITIES := {
	"workbench": {
		"name": "ワークベンチ", "desc": "手作業では作れない道具・設備をつくる作業台",
		"cost": {GameData.Item.WOOD: 3, GameData.Item.IRON: 1}, "time": 6.0, "field": GameData.Field.DEV,
		"max": 1, "requires": "", "station": true,
		"room": "workshop", "dx": [9.0],
		"sprite": "res://assets/base/workbench.png", "frame": Vector2i(16, 9), "stride": 18, "frames": 3,
		"effects": [],
	},
	"bed": {
		"name": "ベッド", "desc": "仲間が休める。多いほど同時に休める人数が増える",
		"cost": {GameData.Item.HIDE: 2, GameData.Item.BONE: 1}, "time": 4.0, "field": GameData.Field.DEV,
		"max": 3, "requires": "workbench", "station": false,
		"room": "bedroom", "dx": [9.0, 24.0, 39.0],
		"sprite": "res://assets/base/bed_%d.png", "frame": Vector2i(14, 9), "stride": 0, "frames": 1,
		"effects": [],
	},
	"cargo_rack": {
		"name": "荷台の増設", "desc": "倉庫の脇に荷台を組む。拠点全体の積載できる重さが増える（1つ+60）",
		"cost": {GameData.Item.WOOD: 6, GameData.Item.IRON: 3}, "time": 5.0, "field": GameData.Field.DEV,
		"max": 3, "requires": "workbench", "station": false,
		"room": "storage", "dx": [38.0, 47.0, 56.0],
		"sprite": "res://assets/base/cargo_rack_%d.png", "frame": Vector2i(12, 9), "stride": 0, "frames": 1,
		"capacity_bonus": 60, "effects": [],
	},
	"supply_cache": {
		"name": "物資庫", "desc": "修理資材を使い、消耗品の蓄えを整える棚。仲間のスタミナが減りにくくなる（-8%）",
		"cost": {GameData.Item.REPAIR_KIT: 3, GameData.Item.WOOD: 2}, "time": 5.0, "field": GameData.Field.DEV,
		"max": 1, "requires": "workbench", "station": false,
		"room": "workshop", "dx": [51.0],
		"sprite": "res://assets/base/supply_cache.png", "frame": Vector2i(8, 10), "stride": 0, "frames": 1,
		"effects": [{"kind": "drain_cut", "value": 0.08}],
	},
}


static func has(id: String) -> bool:
	return FACILITIES.has(id)


static func def(id: String) -> Dictionary:
	return FACILITIES.get(id, {})


static func ids() -> Array:
	return FACILITIES.keys()


static func name_of(id: String) -> String:
	return FACILITIES[id]["name"] if FACILITIES.has(id) else BASE_STATION_NAME


static func max_of(id: String) -> int:
	return int(FACILITIES[id]["max"])


## その設備の置き場所（足元のワールド座標）を、部屋が slot にあるときの位置で返す。
static func spots_in(id: String, slot: String) -> Array:
	var l: Array = []
	for dx in FACILITIES[id]["dx"]:
		l.append(Rooms.floor_pos(slot, float(dx)))
	return l


## その設備を置く部屋の種類
static func room_of(id: String) -> String:
	return FACILITIES[id]["room"]


static func sprite_path(id: String, slot: int) -> String:
	return String(FACILITIES[id]["sprite"]).replace("%d", str(slot))


## 絵の切り出しの基準（ArtSpec.frame_src に渡す。コマの大きさ・間隔・コマ数。ユニット）
static func sprite_spec(id: String) -> Dictionary:
	var d: Dictionary = FACILITIES[id]
	return {"cell": d["frame"], "stride": d["stride"], "frames": d["frames"]}


## 建設を「レシピ」にしたもの。加工と同じ仕組み（運搬 → 加工設備／ワークベンチで作業）に流せる。
## "out" は -1（アイテムを作らない）、"build" に設備の id を持つ。作業する場所は "station"（＝必要設備）。
static func recipe_of(id: String) -> Dictionary:
	var d: Dictionary = FACILITIES[id]
	return {"id": "build:" + id, "name": "%sの建設" % d["name"], "in": d["cost"].duplicate(), "out": -1, "n": 0,
		"time": d["time"], "tank_fuel": 0.0, "field": d["field"], "station": d["requires"], "build": id}


static func cost_text(id: String) -> String:
	var parts: Array = []
	var c: Dictionary = FACILITIES[id]["cost"]
	for it in c:
		parts.append("%s×%d" % [GameData.ITEM_NAMES[it], c[it]])
	return "＋".join(PackedStringArray(parts))
