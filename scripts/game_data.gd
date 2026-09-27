class_name GameData
extends RefCounted
## 共通定義（仕事・アイテム・レシピ・座標レイアウト・描画ヘルパー）。
## 新しい仕事や素材を足すときはまずここに追加する。

# ------------------------------------------------------------------
# 設定
# ------------------------------------------------------------------
## 戦闘・敵AI・敵ドロップ・修理は現段階では無効（コードは残してある）。
const ENABLE_COMBAT := false
## 襲撃（出来事の一種。scripts/director.gd）で戦う。ENABLE_COMBAT（一定間隔で敵が湧く旧方式）とは別。
const ENABLE_RAIDS := true
## 木材・石・鉄鉱石を「採取ポイント」（岩場・鉱床・枯れ木。data/gathering.gd）から道具で採る。
## false なら、従来の「地面に落ちている物を1個ずつ拾う」方式に戻る（敵の落とし物・漂流物・獲物はどちらでも落ちている物として拾う）。
static var ENABLE_GATHER_POINTS := true         # 実行中に切り替えられる（tools/sim_gather.gd が従来方式と比べるため）

## 論理ユニット1つ（基準の長さ。今の絵の「1ドット」と同じ大きさ）を、画面の何pxで描くか。定義は ArtSpec.UNIT_PX（ここは同じ値の別名）。
## 絵の細かさ（1ユニットを何ドットで描いているか）とは関係がない。詳しくは data/art_spec.gd。
const PX := ArtSpec.UNIT_PX

# ------------------------------------------------------------------
# 仕事
# ------------------------------------------------------------------
enum Job { GATHER, HAUL, PROCESS, REST, COMBAT, REPAIR, HUNT }
const JOB_NAMES := {
	Job.GATHER: "回収",
	Job.HAUL: "運搬",
	Job.PROCESS: "加工",
	Job.REST: "休憩",
	Job.COMBAT: "戦闘",
	Job.REPAIR: "修理",
	Job.HUNT: "狩猟",
}
const MAX_PRIORITY := 5


# ------------------------------------------------------------------
# 仲間の分野・ランク・性別（分野は後から足せる）
# ------------------------------------------------------------------
enum Field { DEV, COMBAT, COOK, MEDIC, GATHERER }
const FIELD_NAMES := {
	Field.DEV: "開発者", Field.COMBAT: "戦闘員", Field.COOK: "料理人",
	Field.MEDIC: "保健", Field.GATHERER: "回収",
}
const RANKS := ["E", "D", "C", "B", "A", "S", "SS", "SSS"]
const GENDER_NAMES := ["男", "女", "ジェンダーレス"]
## 分野ごとの専門スキル（将来ここに効果を結びつける）
const FIELD_SKILLS := {
	Field.DEV: ["武器設計", "装甲加工"],
	Field.COMBAT: ["生還率", "戦果"],
	Field.COOK: ["保存食", "栄養管理"],
	Field.MEDIC: ["応急処置", "保健指導"],
	Field.GATHERER: ["目利き", "健脚"],
}
## 仕事がどの分野の実力を使うか
const JOB_FIELD := {
	Job.GATHER: Field.GATHERER, Job.HAUL: Field.GATHERER, Job.PROCESS: Field.DEV,
	Job.REST: Field.MEDIC, Job.COMBAT: Field.COMBAT, Job.REPAIR: Field.DEV, Job.HUNT: Field.COMBAT,
}


## 部署Lvによる解放（データ駆動）。恩恵の中身は検討中なので、今は「表示」だけを扱う。
##  - need_level: 部署Lvがこれ以上で解放
##  - blueprint: true なら、Lvに届いても設計図を入手するまで詳細は見えない
##  - teaser: Lvが足りない間も見せる「こういうものがある」の説明
## ※ここにある項目は仮のサンプル。内容は今後ユーザーと詰める。
const UNLOCKS := [
	{"id": "dev_alloy", "field": Field.DEV, "need_level": 2, "blueprint": false,
		"name": "強化金属板（仮）", "teaser": "金属板を上位素材にする加工", "detail": "金属板をさらに鍛えた上位素材。装甲や武器の材料になる。"},
	{"id": "dev_armor", "field": Field.DEV, "need_level": 4, "blueprint": true,
		"name": "装甲パネル（仮）", "teaser": "拠点の外装を強化する部品", "detail": "拠点の耐久を上げる外装パネル。設計図の入手が必要。"},
	{"id": "dev_special", "field": Field.DEV, "need_level": 6, "blueprint": true,
		"name": "特殊装甲（仮）", "teaser": "特別な技術が必要な装甲", "detail": "特殊な技術を持つ技術者が作れる装甲。"},
]

const UNLOCK_LOCKED := 0          # 部署Lvが足りない
const UNLOCK_NEED_BLUEPRINT := 1  # Lvは足りているが設計図がない
const UNLOCK_OPEN := 2            # 解放済み


static func unlocks_of(field: int) -> Array:
	var l: Array = []
	for u in UNLOCKS:
		if u["field"] == field:
			l.append(u)
	return l


static func unlock_state(workers: Array, blueprints: Dictionary, u: Dictionary) -> int:
	if field_level(workers, u["field"]) < u["need_level"]:
		return UNLOCK_LOCKED
	if u["blueprint"] and not blueprints.has(u["id"]):
		return UNLOCK_NEED_BLUEPRINT
	return UNLOCK_OPEN


## 拠点の分野レベル（部署のレベル）。その部署に配属された人数と、その分野のランクの高さで上がる。
## 高いレベルほどその分野の仕事が速くなり、将来は高度な開発などを解放する。
static func field_points(workers: Array, field: int) -> int:
	var pts := 0
	for w in workers:
		if w.dept == field:
			var r: int = w.ranks.get(field, 0)
			pts += 1 + r * 2 + (3 if field in w.best_fields() else 0)
	return pts


static func field_level(workers: Array, field: int) -> int:
	return 1 + int(sqrt(float(field_points(workers, field))))


static func job_list() -> Array:
	# 狩猟は無害な生物が相手なので戦闘フラグとは別。修理は拠点の維持に使う。
	var l := [Job.HUNT, Job.GATHER, Job.HAUL, Job.PROCESS, Job.REPAIR, Job.REST]
	if ENABLE_COMBAT or ENABLE_RAIDS:
		l.append(Job.COMBAT)
	return l


# ------------------------------------------------------------------
# アイテム（第1段階: 生物資源と基本資源）
# 狩猟・採取・購入・捕獲・探索の持ち帰りは、すべて同じ Item / Inventory に集約する。
# ------------------------------------------------------------------
enum Item { MEAT, HIDE, BONE, FAT, WOOD, STONE, IRON_ORE, IRON, FOOD, FUEL, REPAIR_KIT, CARCASS,
		HAMMER, PICKAXE, ADV_PICK, AXE, IRON_AXE }        # 後ろの5つは採取の道具（data/gathering.gd）。倉庫の積載量の対象外
const TOOL_ITEMS := [Item.HAMMER, Item.PICKAXE, Item.ADV_PICK, Item.AXE, Item.IRON_AXE]
const CREATURE_ITEMS := [Item.MEAT, Item.HIDE, Item.BONE, Item.FAT]   # 生物から取れる素材
const GROUND_ITEMS := [Item.WOOD, Item.STONE, Item.IRON_ORE]          # 地面で採取する基本資源
const RAW_ITEMS := [Item.MEAT, Item.HIDE, Item.BONE, Item.FAT, Item.WOOD, Item.STONE, Item.IRON_ORE]
const PRODUCT_ITEMS := [Item.IRON, Item.FOOD, Item.FUEL, Item.REPAIR_KIT]
const ITEM_NAMES := {
	Item.MEAT: "生肉", Item.HIDE: "皮", Item.BONE: "骨", Item.FAT: "脂肪",
	Item.WOOD: "木材", Item.STONE: "石", Item.IRON_ORE: "鉄鉱石",
	Item.IRON: "鉄", Item.FOOD: "食料", Item.FUEL: "燃料", Item.REPAIR_KIT: "修理資材",
	Item.CARCASS: "獲物",
	Item.HAMMER: "簡易ハンマー", Item.PICKAXE: "鉄製ピッケル", Item.ADV_PICK: "高性能ピッケル",
	Item.AXE: "簡易の斧", Item.IRON_AXE: "鉄の斧",
}
const ITEM_FILES := {
	Item.MEAT: "meat", Item.HIDE: "hide", Item.BONE: "bone", Item.FAT: "fat",
	Item.WOOD: "wood", Item.STONE: "stone", Item.IRON_ORE: "iron_ore",
	Item.IRON: "iron", Item.FOOD: "ration", Item.FUEL: "fuel", Item.REPAIR_KIT: "repair_kit",
	Item.CARCASS: "meat",
	Item.HAMMER: "hammer", Item.PICKAXE: "pickaxe", Item.ADV_PICK: "adv_pick", Item.AXE: "axe", Item.IRON_AXE: "iron_axe",
}
## 地面の資源の出やすさ（木材は多く、鉄鉱石は少ない）
const GROUND_WEIGHTS := {Item.WOOD: 4.0, Item.STONE: 3.0, Item.IRON_ORE: 1.5}

## 加工レシピ。1回の加工で in を消費して out を n 個作る。
##  - tank_fuel: 加工中に拠点の燃料タンクから使う量（炉を使う精錬など）
##  - field: 作業の速さに使う分野ランク
##  - station: 必要設備（data/facilities.gd の設備の id）。書かなければ手作業（加工設備）でできる。
##    その設備が拠点にないうちは作られず、あるときは仲間がその設備の場所で作る。
## 設備の建設もレシピの形で流れる（FacilityDB.recipe_of。"out" が -1、"build" に設備の id）。
const RECIPES := [
	{"id": "cook", "name": "調理（食料）", "in": {Item.MEAT: 1}, "out": Item.FOOD, "n": 2, "time": 2.5,
		"tank_fuel": 0.0, "field": Field.COOK},
	{"id": "tallow", "name": "油脂の燃料", "in": {Item.FAT: 1}, "out": Item.FUEL, "n": 2, "time": 2.5,
		"tank_fuel": 0.0, "field": Field.DEV},
	{"id": "firewood", "name": "薪の燃料", "in": {Item.WOOD: 1}, "out": Item.FUEL, "n": 1, "time": 2.0,
		"tank_fuel": 0.0, "field": Field.DEV},
	{"id": "smelt", "name": "精錬（鉄）", "in": {Item.IRON_ORE: 1}, "out": Item.IRON, "n": 1, "time": 3.5,
		"tank_fuel": 3.0, "field": Field.DEV},
	{"id": "repair_iron", "name": "修理部品（鉄＋木材）", "in": {Item.IRON: 1, Item.WOOD: 1}, "out": Item.REPAIR_KIT, "n": 2,
		"time": 3.0, "tank_fuel": 0.0, "field": Field.DEV, "station": "workbench"},
	{"id": "repair_stone", "name": "修理資材（石＋木材）", "in": {Item.STONE: 1, Item.WOOD: 1}, "out": Item.REPAIR_KIT, "n": 1,
		"time": 3.0, "tank_fuel": 0.0, "field": Field.DEV},
	{"id": "repair_hide", "name": "簡易修理（皮＋骨）", "in": {Item.HIDE: 1, Item.BONE: 1}, "out": Item.REPAIR_KIT, "n": 1,
		"time": 3.0, "tank_fuel": 0.0, "field": Field.DEV},
	# ---- 採取の道具（data/gathering.gd）。誰かの道具の更新になるときだけ作る（Main.tool_wanted）----
	{"id": "tool_hammer", "name": "簡易ハンマー", "in": {Item.STONE: 2, Item.WOOD: 1}, "out": Item.HAMMER, "n": 1,
		"time": 3.0, "tank_fuel": 0.0, "field": Field.DEV},
	{"id": "tool_axe", "name": "簡易の斧", "in": {Item.STONE: 1, Item.WOOD: 2}, "out": Item.AXE, "n": 1,
		"time": 3.0, "tank_fuel": 0.0, "field": Field.DEV},
	# 鉄は修理部品（鉄＋木材）にもすぐ使われて溜まらないので、道具に要る鉄は1個にしてある（修理資材や木材で高価さを出す）
	{"id": "tool_pick", "name": "鉄製ピッケル", "in": {Item.IRON: 1, Item.WOOD: 2}, "out": Item.PICKAXE, "n": 1,
		"time": 4.0, "tank_fuel": 0.0, "field": Field.DEV, "station": "workbench"},
	{"id": "tool_iron_axe", "name": "鉄の斧", "in": {Item.IRON: 1, Item.WOOD: 2}, "out": Item.IRON_AXE, "n": 1,
		"time": 4.0, "tank_fuel": 0.0, "field": Field.DEV, "station": "workbench"},
	{"id": "tool_adv_pick", "name": "高性能ピッケル", "in": {Item.IRON: 1, Item.REPAIR_KIT: 3}, "out": Item.ADV_PICK, "n": 1,
		"time": 6.0, "tank_fuel": 0.0, "field": Field.DEV, "station": "workbench"},
]
## 道具に使う鉄を精錬で優先するのは、倉庫の食料がこの個数以上あるときだけ（調理を後回しにして空腹にならないように）
const TOOL_IRON_FOOD_MIN := 4
## 加工品をどこまで作り置きするか（これ以上あれば、そのレシピは作らない）
const STOCK_TARGET := {Item.FOOD: 12, Item.FUEL: 8, Item.REPAIR_KIT: 6, Item.IRON: 4,
	Item.HAMMER: 1, Item.PICKAXE: 1, Item.ADV_PICK: 1, Item.AXE: 1, Item.IRON_AXE: 1}
## 最初の加工方針（★0〜5。0 = 作らない）。道具は、誰かの更新になるときだけ作られる（Main.tool_wanted）ので、
## 食料・燃料・修理と同じ★3にしてある（同点なら、在庫の少ない物＝道具のほうが先になるが、食料が0のときなど、同点で先に並んでいる物が勝つ）。
## 高性能ピッケルは、修理資材を3個使うので★2。
const DEFAULT_RECIPE_PRIORITY := {
	"cook": 3, "tallow": 3, "firewood": 3, "smelt": 2, "repair_iron": 3, "repair_stone": 3, "repair_hide": 3,
	"tool_hammer": 3, "tool_axe": 3, "tool_pick": 3, "tool_iron_axe": 3, "tool_adv_pick": 2,
}


static func recipe_by_id(id: String) -> Dictionary:
	for r in RECIPES:
		if r["id"] == id:
			return r
	return {}


## そのレシピの必要設備（"" = 手作業）
static func recipe_station(r: Dictionary) -> String:
	return r.get("station", "")


static func recipe_text(r: Dictionary) -> String:
	var parts: Array = []
	for it in r["in"]:
		parts.append("%s×%d" % [ITEM_NAMES[it], r["in"][it]])
	return "%s → %s×%d" % ["＋".join(PackedStringArray(parts)), ITEM_NAMES[r["out"]], r["n"]]


# ------------------------------------------------------------------
# 生物（第1段階はすべて無害。追われると逃げる）
# drops は倉庫で「解体」したときに得られる素材。
# ------------------------------------------------------------------
const CREATURES := {
	"hare": {"name": "スナウサギ", "hp": 16.0, "flee": 150.0, "size": Vector2(14, 12), "weight": 5.0,
		"drops": {Item.MEAT: 1, Item.HIDE: 1}},
	"lizard": {"name": "トゲトカゲ", "hp": 26.0, "flee": 115.0, "size": Vector2(18, 9), "weight": 3.0,
		"drops": {Item.MEAT: 1, Item.HIDE: 1, Item.BONE: 1}},
	"hump": {"name": "コブ獣", "hp": 50.0, "flee": 70.0, "size": Vector2(22, 16), "weight": 1.6,
		"drops": {Item.MEAT: 2, Item.FAT: 2, Item.HIDE: 1, Item.BONE: 1}},
}


static func drops_text(species: String) -> String:
	var parts: Array = []
	var d: Dictionary = CREATURES[species]["drops"]
	for it in d:
		parts.append("%s×%d" % [ITEM_NAMES[it], d[it]])
	return "・".join(PackedStringArray(parts))


# ------------------------------------------------------------------
# 拠点の維持（食料・燃料・耐久度）
# ------------------------------------------------------------------
const FUEL_CAP := 100.0
## 燃料1個でタンクに入る量
const FUEL_ITEMS := {Item.FUEL: 25.0}
const FUEL_PER_PX := 1.0 / 170.0            # 1px進むごとの消費（速度60で毎秒約0.35）
const CRAWL_SPEED := 15.0                   # 燃料切れのときの低速走行（止まると資源が来なくなるため）
const SPAWN_DIST_MIN := 110.0               # 地面の資源は「進んだ距離」ごとに流れてくる
const SPAWN_DIST_MAX := 190.0
const CREATURE_DIST_MIN := 520.0            # 生物が現れる間隔（距離）
const CREATURE_DIST_MAX := 820.0

## 食料: 仲間1人が何秒ごとに1個食べるか。なくなると空腹で作業と移動が遅くなる。

## 耐久度（0〜100）。下がると不調になり、修理資材1個で REPAIR_AMOUNT 回復する。
enum Part { HULL, DRIVE, MACHINE }
const PART_NAMES := {Part.HULL: "車体", Part.DRIVE: "走行装置", Part.MACHINE: "加工設備"}
const HULL_WEAR_PER_SEC := 0.07             # 車体: 時間とともに傷む
const DRIVE_WEAR_PER_PX := 1.0 / 450.0      # 走行装置: 進んだ距離で傷む
const MACHINE_WEAR_PER_SEC := 0.35          # 加工設備: 加工している間だけ傷む
const PART_BAD := 30.0                      # これ未満で不調（効果が半分）
const REPAIR_BELOW := 75.0                  # これ未満なら修理に向かう
const REPAIR_AMOUNT := 25.0


# ------------------------------------------------------------------
# 拠点のレイアウト（ワールド座標）。hull.png の座標と対応している。
# ------------------------------------------------------------------
const HULL_POS := Vector2(176, 194)        # hull.png の左上
const UP_Y := 354.0                         # 上の階の床（足元）
const LO_Y := 482.0                         # 下の階の床（足元）
const LADDER_X := 484.0
const RAMP_TOP := Vector2(904, 484)
const RAMP_FOOT := Vector2(992, 548)
const GROUND_Y_MIN := 556.0
const GROUND_Y_MAX := 700.0
## 以下は、部屋の初期配置（data/rooms.gd の DEFAULT_LAYOUT）での位置。実際の位置は部屋の変更で動くので、
## ゲームは Rooms の位置（processor_pos / storage_pos / engine_pos / floor_pos）を使う。ここは基準の値と、最初の仲間の位置にだけ使う。
const MACHINE_X := 340.0                    # 加工設備（上の階）
const STORAGE_X := 640.0                    # 倉庫（下の階）
const BED_X := [540.0, 600.0, 660.0]        # ベッド（上の階）
const ENGINE_X := 352.0                     # 機関室の燃料投入口（下の階）
const STORAGE_SLOTS_X := [556.0, 600.0, 644.0, 688.0, 732.0]


## 足元のy座標からどの階かを返す（0=地面 1=下の階 2=上の階）
static func floor_of_y(y: float) -> int:
	if y >= 520.0:
		return 0
	if y >= 420.0:
		return 1
	return 2


static func deck_y(floor_i: int) -> float:
	return LO_Y if floor_i == 1 else UP_Y


## 階をまたぐ移動の1区間。approach まで歩き、dest まで登り降りして dest_floor になる。
static func route_leg(from_floor: int, to_floor: int) -> Dictionary:
	if to_floor > from_floor:
		if from_floor == 0:
			return {"approach": RAMP_FOOT, "dest": RAMP_TOP, "floor": 1, "kind": "ramp"}
		return {"approach": Vector2(LADDER_X, LO_Y), "dest": Vector2(LADDER_X, UP_Y), "floor": 2, "kind": "ladder"}
	if from_floor == 2:
		return {"approach": Vector2(LADDER_X, UP_Y), "dest": Vector2(LADDER_X, LO_Y), "floor": 1, "kind": "ladder"}
	return {"approach": RAMP_TOP, "dest": RAMP_FOOT, "floor": 0, "kind": "ramp"}


# ------------------------------------------------------------------
# 画像とフォント
# ------------------------------------------------------------------
static var _tex_cache := {}
static var _font: SystemFont = null


## 画像のキャッシュを捨てる（絵の置き場所を差し替えたとき。ArtSpec.set_root_override）
static func clear_tex_cache() -> void:
	_tex_cache.clear()


## PNGを直接読み込む（インポート前でも動くようにするため）。
## テスト用に、絵の置き場所を差し替えられる（ArtSpec.root_override。高精細な絵に替えたときの動作確認）。
static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	var alt := ArtSpec.overridden(path)
	if alt != "":
		var ob := FileAccess.get_file_as_bytes(alt)
		var oimg := Image.new()
		if not ob.is_empty() and oimg.load_png_from_buffer(ob) == OK:
			t = ImageTexture.create_from_image(oimg)
	elif ResourceLoader.exists(path):
		t = load(path)                       # インポート済みならこちら（書き出しにも対応）
	else:
		# エディタがまだインポートしていない場合でも動くよう、PNGを直接読む
		var bytes := FileAccess.get_file_as_bytes(path)
		var img := Image.new()
		if not bytes.is_empty() and img.load_png_from_buffer(bytes) == OK:
			t = ImageTexture.create_from_image(img)
	if t == null:
		push_warning("画像を読み込めません: " + path)
		var e := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		e.fill(Color(1, 0, 1))
		t = ImageTexture.create_from_image(e)
	_tex_cache[path] = t
	return t


static func item_tex(item: int) -> Texture2D:
	return tex("res://assets/resources/item_%s.png" % ITEM_FILES[item])


static func font() -> Font:
	# 日本語を表示するためOSのフォントを使う
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray([
			"Noto Sans CJK JP", "Noto Sans JP", "Yu Gothic UI", "Yu Gothic",
			"Meiryo", "Hiragino Sans", "Hiragino Kaku Gothic ProN", "MS Gothic", "sans-serif",
		])
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	return _font


static func make_label(text: String, size: int = 16, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.04, 0.9))
	return l


## canvas の _draw() の中から呼ぶこと。
static func draw_text(canvas: CanvasItem, pos: Vector2, text: String, size: int = 14,
		color: Color = Color.WHITE, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := font()
	if align == HORIZONTAL_ALIGNMENT_CENTER and width > 0.0:
		pos.x -= width / 2.0   # 幅の中央が pos.x に来るようにする
	canvas.draw_string_outline(f, pos, text, align, width, size, 4, Color(0.1, 0.06, 0.04, 0.9))
	canvas.draw_string(f, pos, text, align, width, size, color)


## 生物の絵の基準（ユニット。1コマの大きさは CREATURES の "size"）。絵の細かさ（dpu）は、絵の幅から自動で決まる。
static func creature_spec(species: String) -> Dictionary:
	var sz: Vector2 = CREATURES[species]["size"]
	return ArtSpec.spec_of(Vector2i(int(sz.x), int(sz.y)), ArtSpec.CREATURE_FRAMES)


## 生物の絵1コマの、画面上の高さ（px。絵の細かさに依存しない）。名前や体力を出す位置の基準。
static func creature_height_px(species: String) -> float:
	return float(CREATURES[species]["size"].y) * float(PX)


## 生物を描く。feet = 足元の位置。dead なら仰向け（獲物）で描く。
## 画面上の大きさは、基準の大きさ（CREATURES の size ユニット）× PX。絵の細かさ（1ユニットのドット数）は絵から自動で決まる。
static func draw_creature(canvas: CanvasItem, species: String, frame: int, feet: Vector2, facing: float = 1.0,
		dead: bool = false, s: float = 1.0, modulate: Color = Color.WHITE) -> void:
	var sz: Vector2 = CREATURES[species]["size"]
	var size := sz * PX * s
	var t := tex("res://assets/creatures/%s.png" % species)
	var spec := creature_spec(species)
	if dead:
		canvas.draw_set_transform(feet + Vector2(0, -size.y / 2.0), 0.0, Vector2(facing, -1.0))
		canvas.draw_texture_rect_region(t, Rect2(-size / 2.0, size), ArtSpec.frame_src(t, spec, 2), modulate)
	else:
		canvas.draw_set_transform(feet, 0.0, Vector2(facing, 1.0))
		canvas.draw_texture_rect_region(t, Rect2(Vector2(-size.x / 2.0, -size.y), size), ArtSpec.frame_src(t, spec, frame), modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## アイテムのアイコンを中心 pos に描く。s=1 で 基準の大きさ（ArtSpec.ITEM）× PX、s=0.5 で半分。絵全体を描くので、絵の細かさには依存しない。
## canvas の _draw() の中から呼ぶこと。
static func draw_item(canvas: CanvasItem, item: int, pos: Vector2, s: float = 1.0) -> void:
	var size := ArtSpec.px_size(ArtSpec.ITEM) * s
	canvas.draw_texture_rect(item_tex(item), Rect2(pos - size / 2.0, size), false)


## アイテムのアイコンを「ゲージ」として描く（アイコンそのものが進み具合を表す）。下から ratio（0〜1）の分だけ明るく、残りは暗い。
## 画面上の大きさは、基準の大きさ（ArtSpec.ITEM）× s。絵の細かさに依存しない。加工の進みなどに使う。
static func draw_item_fill(canvas: CanvasItem, item: int, pos: Vector2, s: float, ratio: float, tint: Color = Color.WHITE) -> void:
	var size := ArtSpec.px_size(ArtSpec.ITEM) * s
	var tx := item_tex(item)
	var rect := Rect2(pos - size / 2.0, size)
	canvas.draw_texture_rect(tx, rect, false, Color(0.2, 0.2, 0.26, 0.9))
	var r := clampf(ratio, 0.0, 1.0)
	if r > 0.0:
		var h := size.y * r
		var src_h := float(tx.get_height()) * r
		canvas.draw_texture_rect_region(tx, Rect2(rect.position.x, rect.end.y - h, size.x, h), Rect2(0.0, float(tx.get_height()) - src_h, float(tx.get_width()), src_h), tint)
