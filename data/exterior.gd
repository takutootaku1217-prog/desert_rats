class_name ExteriorDB
extends RefCounted
## 外装（外から見た移動拠点）のパーツの表（プロトタイプの仮データ）。「今後の順番 2」の続き。
##
## 考え方:
##  - 外装は「1枚の完成した車両の絵」ではなく、車体（body.png）＋ 外装パーツの組み合わせ。パーツを足すだけで見た目が育つ。
##  - 絵と置き場所は、絵を作る tools/art_exterior.py が assets/base/exterior/<系統>/parts.json に書き出す（＝絵とゲームが食い違わない）。
##    ここには「どのパーツを、どの層に、いつ見せるか」だけを書く。系統（Rooms.STYLE）を変えれば別の外装の絵にできる。
##  - 屋根の上の物（layer "roof"）は、外装でも、内装の断面図の上でも、同じ絵を重ねる（同じ車両を中から見ても屋根は同じ）。
##    壁・装甲（layer "wall" / "armor"）は外から見たときだけ。
##  - 外装・内装は同じ拠点のデータ（部屋の配置・建てた設備・走行距離）を読むだけで、別々の状態は持たない。
##
## パーツの書き方（PARTS。上から順に描く。後のものが手前）:
##   id: parts.json の名前 / sheet: 絵の詰め合わせ（roof_parts・wall_parts・armor）/ layer: roof・wall・armor
##   unlock: 見える条件（下の UNLOCK_KEYS。すべて満たすと見える。書かなければ最初から）
##   replaces: 見えるようになると、隠れるパーツ（アンテナが立派なものに替わる、など）
##   kind: "fixed"（決まった場所）／"slot"（room の部屋がある区画ごと）／"fuel_port"（機関室の壁。ないときは別の場所）
## 将来のパーツ（装甲の強化・タレット・外部収納・通信設備など）は、絵を tools/art_exterior.py に足して、ここに1行足すだけ。

const DIR := "res://assets/base/exterior/%s/"
const WHEEL_SHEET := "res://assets/base/wheels.png"
const RAMP_SHEET := "res://assets/base/ramp.png"

## 見える条件のキー:
##   distance: 走行距離（px。Director.distance）がこれ以上 / facility: その設備を建てた / beds: ベッドがこの数以上 / room: その部屋がある
## 「ゲームの進み具合」による成長の段階（走行距離）。数値は仮。速度の設定で進み方が変わる（速度60で 6000px ≒ 100秒）。
const STAGE_SMALL := 6000.0      # 荷物が増える
const STAGE_MID := 12000.0       # 屋根の設備（アンテナ・水タンク）
const STAGE_RACK := 20000.0      # 外部収納（後ろの荷台）
const STAGE_TANK := 30000.0      # 燃料タンク
const STAGE_LATE := 45000.0      # 装甲・通信設備

const PARTS := [
	# ---- 壁（外から見たときだけ）----
	{"id": "tool_rack", "sheet": "wall_parts", "layer": "wall", "unlock": {"facility": "workbench"}},          # 作業道具（ワークベンチができたら）
	{"id": "wash_line", "sheet": "wall_parts", "layer": "wall", "unlock": {"beds": 2}},                        # 物干し（ベッドが2つ以上）
	{"id": "sign_cross", "sheet": "wall_parts", "layer": "wall", "kind": "slot", "room": "infirmary"},        # 医務室の看板（部屋の配置で増える）
	{"id": "rear_rack", "sheet": "wall_parts", "layer": "wall", "unlock": {"distance": STAGE_RACK}},          # 後ろの荷台（外部収納）
	{"id": "fuel_port", "sheet": "wall_parts", "layer": "wall", "kind": "fuel_port"},                          # 燃料の口（機関室の壁）
	# ---- 装甲（後半。外から見たときだけ）----
	{"id": "armor_side", "sheet": "armor", "layer": "armor", "unlock": {"distance": STAGE_LATE}},
	{"id": "armor_front", "sheet": "armor", "layer": "armor", "unlock": {"distance": STAGE_LATE}},
	# ---- 屋根の上（外装でも内装の断面図の上でも同じ）----
	{"id": "deck_rail", "sheet": "roof_parts", "layer": "roof"},                                              # 屋上デッキの柵
	{"id": "stack_a", "sheet": "roof_parts", "layer": "roof"},                                                # 排気管（煙の出る位置）
	{"id": "stack_b", "sheet": "roof_parts", "layer": "roof"},
	{"id": "flag", "sheet": "roof_parts", "layer": "roof"},
	{"id": "antenna_small", "sheet": "roof_parts", "layer": "roof"},                                          # 最初は簡素なアンテナ
	{"id": "antenna_mast", "sheet": "roof_parts", "layer": "roof", "unlock": {"distance": STAGE_MID}, "replaces": "antenna_small"},
	{"id": "antenna_comm", "sheet": "roof_parts", "layer": "roof", "unlock": {"distance": STAGE_LATE}, "replaces": "antenna_mast"},
	{"id": "crates_small", "sheet": "roof_parts", "layer": "roof"},                                            # 最低限の荷物
	{"id": "crates_big", "sheet": "roof_parts", "layer": "roof", "unlock": {"distance": STAGE_SMALL}, "replaces": "crates_small"},
	{"id": "cloth_roll", "sheet": "roof_parts", "layer": "roof"},
	{"id": "water_tank", "sheet": "roof_parts", "layer": "roof", "unlock": {"distance": STAGE_MID}, "replaces": "cloth_roll"},
	{"id": "canopy", "sheet": "roof_parts", "layer": "roof", "unlock": {"beds": 1}},                          # 屋根の布（ベッドができたら）
	{"id": "roof_vent", "sheet": "roof_parts", "layer": "roof", "kind": "slot", "room": "mess"},              # 食堂の換気管
	{"id": "fuel_tank_roof", "sheet": "roof_parts", "layer": "roof", "unlock": {"distance": STAGE_TANK}},
]

## 窓のガラスの色（区画の部屋の種類で変わる。外から見て、どんな部屋か少し分かる）
const GLASS := {
	"workshop": Color("f0a050"), "bedroom": Color("f6d890"), "storage": Color("7a6a58"), "engine": Color("e06a30"),
	"infirmary": Color("a8dcc8"), "mess": Color("f6d070"), "training": Color("8aa0c8"), "empty": Color("2a2622"),
}
const GLASS_COCKPIT := Color("f4c986")

static var _geo := {}
static var _geo_style := ""


# ------------------------------------------------------------------
# 絵と置き場所（parts.json）
# ------------------------------------------------------------------
static func dir() -> String:
	return DIR % Rooms.STYLE


## parts.json（絵を作るときに書き出された、切り出し位置・置き場所・窓の位置）
static func geo() -> Dictionary:
	if _geo.is_empty() or _geo_style != Rooms.STYLE:
		var txt := FileAccess.get_file_as_string(dir() + "parts.json")
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("外装の parts.json を読めません: " + dir())
			return {}
		_geo = parsed
		_geo_style = Rooms.STYLE
	return _geo


static func sheet_tex(sheet: String) -> Texture2D:
	return GameData.tex(dir() + String(geo()["sheets"][sheet]["file"]))


static func body_tex() -> Texture2D:
	return GameData.tex(dir() + "body.png")


static func windows_tex() -> Texture2D:
	return GameData.tex(dir() + String(geo()["sheets"]["windows"]["file"]))


## パーツの切り出し範囲（絵の詰め合わせの中）
static func frame_of(part: Dictionary) -> Rect2i:
	var f: Array = geo()["sheets"][part["sheet"]]["frames"][part["id"]]
	return Rect2i(int(f[0]), int(f[1]), int(f[2]), int(f[3]))


static func window_rect(slot: String) -> Rect2i:
	var w: Array = geo()["windows"][slot]
	return Rect2i(int(w[0]), int(w[1]), int(w[2]), int(w[3]))


static func cab_rect() -> Rect2i:
	var w: Array = geo()["cab_side"]
	return Rect2i(int(w[0]), int(w[1]), int(w[2]), int(w[3]))


## 外装の車体の絵の左上（HULL_POS。内装の断面図と同じ）からの位置（ドット）。slot は "slot" の種類のパーツの区画。
## fuel_port は、機関室のある区画の壁（なければ搬入口のそば）。
static func at_of(part: Dictionary, slot: String = "", engine_dot_x := -1.0) -> Vector2i:
	var g := geo()
	var f := frame_of(part)
	match String(part.get("kind", "fixed")):
		"slot":
			if part["id"] == "roof_vent":
				return Vector2i(int(g["roof_vent_x"][slot]), int(g["foot_row"]) + 1 - f.size.y)
			var w := window_rect(slot)
			var off: Array = g["slot_offsets"][part["id"]]
			return Vector2i(w.position.x + int(off[0]), w.position.y + int(off[1]))
		"fuel_port":
			if engine_dot_x >= 0.0:
				return Vector2i(int(round(engine_dot_x)) - f.size.x / 2, int(g["fuel_port_row"]))
			return Vector2i(int(g["fuel_port_fallback_x"]), int(g["fuel_port_row"]))
	var a: Array = g["at"][part["id"]]
	return Vector2i(int(a[0]), int(a[1]))


# ------------------------------------------------------------------
# いつ見えるか
# ------------------------------------------------------------------
## 見える条件（unlock）を、いまの拠点が満たしているか。知らないキーは満たさない扱い（間違って出さない）。
static func unlocked(rule: Dictionary, game) -> bool:
	for k in rule:
		match k:
			"distance":
				if game.director.distance < float(rule[k]):
					return false
			"facility":
				if not game.base.has_facility(String(rule[k])):
					return false
			"beds":
				if game.base.facility_count("bed") < int(rule[k]):
					return false
			"room":
				if game.base.room_slot(String(rule[k])) == "":
					return false
			_:
				return false
	return true


## いま見えるパーツ（描く順）。layers に含まれる層だけ。"slot" の種類は区画ごとに1つずつ {part, slot}、それ以外は {part, slot: ""}。
## 条件を満たしていても、ほかのパーツに置き換えられたもの（replaces）は含まない。
static func visible_parts(game, layers: Array) -> Array:
	var ok := {}
	for p in PARTS:
		if unlocked(p.get("unlock", {}), game):
			ok[p["id"]] = true
	var hidden := {}
	for p in PARTS:
		if ok.has(p["id"]) and p.has("replaces"):
			hidden[p["replaces"]] = true
	var out: Array = []
	for p in PARTS:
		if not (p["layer"] in layers) or not ok.has(p["id"]) or hidden.has(p["id"]):
			continue
		if String(p.get("kind", "fixed")) == "slot":
			for s in Rooms.SLOT_ORDER:
				if game.room_layout.get(s, "") == p["room"]:
					out.append({"part": p, "slot": s})
		else:
			out.append({"part": p, "slot": ""})
	return out


static func visible_ids(game, layers: Array) -> Array:
	var l: Array = []
	for e in visible_parts(game, layers):
		l.append(e["part"]["id"] + (":" + e["slot"] if e["slot"] != "" else ""))
	return l


## 窓のガラスの色（区画の部屋の種類で決まる）
static func glass_color(rtype: String) -> Color:
	return GLASS.get(rtype, GLASS["empty"])
