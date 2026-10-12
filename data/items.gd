class_name ItemDB
extends RefCounted
## アイテムの情報（名前・分類・色・使い道・入手先）。アイコンの絵は GameData.item_tex（assets/resources。差し替えられる素材）。
## 数量は Inventory（倉庫）・BaseProcessor.stock（作業場）が持つ。ここは「アイテムとは何か」だけ。
## 装備品・特殊アイテム・個体差のあるアイテムを足すときは、ItemStack の data（個体ごとの情報）を使う（scripts/item_stack.gd）。
## 使い道と入手先は、加工のレシピ（GameData.RECIPES）と設備の材料（FacilityDB）から自動で数える（説明の文章を別に書かない）。

## 分類（インベントリの並び順・色。増減してよい）
const CATEGORIES := ["素材", "加工品", "食料", "燃料", "道具", "武器", "仕事補助"]
const CATEGORY_COLORS := {
	"仕事補助": Color("c9b68b"),
	"武器": Color("c9a6f2"), "素材": Color("d9b36b"), "加工品": Color("9fb8de"), "食料": Color("8fd68f"), "燃料": Color("f29a56"), "道具": Color("c9a6f2"),
}
## インベントリに並べる順（分類の順）
const ORDER := [
	GameData.Item.MEAT, GameData.Item.HIDE, GameData.Item.BONE, GameData.Item.FAT, GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE,
	GameData.Item.IRON, GameData.Item.REPAIR_KIT, GameData.Item.BED_PACK, GameData.Item.STORAGE_BOX, GameData.Item.WORKBENCH_PACK, GameData.Item.SUPPLY_CACHE_PACK, GameData.Item.FOOD, GameData.Item.FUEL,
	GameData.Item.HAMMER, GameData.Item.PICKAXE, GameData.Item.ADV_PICK, GameData.Item.AXE, GameData.Item.IRON_AXE, GameData.Item.SIMPLE_SPEAR, GameData.Item.HAUL_FRAME,
]


## インベントリに出るアイテム（獲物 CARCASS は運搬中の物で、倉庫には入らない）
static func all() -> Array:
	return ORDER.duplicate()


static func name_of(item: int) -> String:
	return GameData.ITEM_NAMES.get(item, "?")


static func tex(item: int) -> Texture2D:
	return GameData.item_tex(item)


static func category_of(item: int) -> String:
	if item in GameData.SUPPORT_ITEMS: return "仕事補助"
	if item in GameData.WEAPON_ITEMS:
		return "武器"
	if item in GameData.TOOL_ITEMS:
		return "道具"
	if item == GameData.Item.FOOD:
		return "食料"
	if item == GameData.Item.FUEL:
		return "燃料"
	if item in GameData.PRODUCT_ITEMS:
		return "加工品"
	return "素材"


static func color_of(item: int) -> Color:
	return CATEGORY_COLORS[category_of(item)]


## 並び順の番号（小さいほど前）。表にないアイテムは最後
static func order_of(item: int) -> int:
	var i := ORDER.find(item)
	return i if i >= 0 else ORDER.size() + item


## そのアイテムを材料に使うもの [{"kind": "recipe" | "build", "id": …, "name": …, "out": 作るアイテム（建設は -1）}]
static func uses_of(item: int) -> Array:
	var l: Array = []
	for r in GameData.RECIPES:
		if r["in"].has(item):
			l.append({"kind": "recipe", "id": r["id"], "name": r["name"], "out": int(r["out"])})
	for id in FacilityDB.ids():
		if FacilityDB.def(id)["cost"].has(item) or FacilityDB.packed_item_of(id) == item:
			l.append({"kind": "build", "id": id, "name": "%sの建設" % FacilityDB.name_of(id), "out": -1})
	return l


## そのアイテムを作るレシピ（加工で作れる物）
static func makers_of(item: int) -> Array:
	var l: Array = []
	for r in GameData.RECIPES:
		if int(r["out"]) == item:
			l.append(r)
	return l


## 入手先の短い言葉のリスト（"採取"・"狩猟"・"加工"）
static func sources_of(item: int) -> Array:
	var l: Array = []
	if item in GameData.PACKED_ITEMS: l.append("設備の撤去（完成品）")
	if item in GameData.GROUND_ITEMS:
		l.append("採取")
	if item in GameData.CREATURE_ITEMS:
		l.append("狩猟")
	if not makers_of(item).is_empty():
		l.append("加工")
	return l

## 選択詳細用。効果値は実処理と同じ定義から読み、平常HUDには増やさない。
static func effect_text(item: int) -> String:
	match item:
		GameData.Item.HAUL_FRAME:
			return "Cの仕事補助枠で装備。採取袋・倉庫⇄作業場の1便を%d→%d個にします（調整用）。今の荷物・予約は保持し、次の便から反映。拠点容量は増えません。重量%dは装備中も計上。" % [GatherDB.CARRY_MAX, GameData.HAUL_FRAME_LIMIT, CargoDB.size_of(item)]
		GameData.Item.WORKBENCH_PACK:
			return "撤去した完成品。Bで材料・作業台なしで再設置できます。未設置重量%d、設置後は重量対象外。設置枠・加工室は必要です。" % CargoDB.size_of(item)
		GameData.Item.SUPPLY_CACHE_PACK:
			return "撤去した完成品。Bで材料・作業台なしで再設置できます。設置時だけ疲労蓄積−8%%。未設置重量%d。応急修理板を別途取り出すことはできません。" % CargoDB.size_of(item)
		GameData.Item.BED_PACK:
			return "設置後に1人が眠れます（最大%d台）。基礎回復は疲労−%.1f/秒・HP＋%.1f/秒。簡易休憩はその%d%%。部屋の補正が加わり、拠点HP%d未満では疲労回復が半減します。未設置は重量%d、設置後は重量対象外。" % [FacilityDB.max_of("bed"), CrewStatusDB.FATIGUE_REST_RATE, CrewStatusDB.HP_REST_RATE, roundi(CrewStatusDB.REST_IN_PLACE_RATE*100), GameData.PART_BAD, CargoDB.size_of(item)]
		GameData.Item.STORAGE_BOX:
			return "設置1個で積載容量＋%d（最大%d個）。未設置は重量%dで、容量は増えません。設置後は重量対象外。" % [FacilityDB.def("cargo_rack")["capacity_bonus"], FacilityDB.max_of("cargo_rack"), CargoDB.size_of(item)]
		GameData.Item.SIMPLE_SPEAR:
			return "Cの個体情報で装備すると、本人の迎撃攻撃＋%d%%。狩猟や他の仲間には加算されません。重量%dは装備中も計上します。" % [roundi((GameData.SIMPLE_WEAPON_MULT-1.0)*100), CargoDB.size_of(item)]
		GameData.Item.REPAIR_KIT:
			return "1枚で部位の耐久＋%.1f（上限100）。右上の使用ボタンは、居住区・走行装置・加工設備のうち最も傷んだ未予約部位を自動選択。燃料・仲間HPは回復しません。" % GameData.REPAIR_AMOUNT
	return ""
