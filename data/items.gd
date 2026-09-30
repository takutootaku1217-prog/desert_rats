class_name ItemDB
extends RefCounted
## アイテムの情報（名前・分類・色・使い道・入手先）。アイコンの絵は GameData.item_tex（assets/resources。差し替えられる素材）。
## 数量は Inventory（倉庫）・BaseProcessor.stock（作業場）が持つ。ここは「アイテムとは何か」だけ。
## 装備品・特殊アイテム・個体差のあるアイテムを足すときは、ItemStack の data（個体ごとの情報）を使う（scripts/item_stack.gd）。
## 使い道と入手先は、加工のレシピ（GameData.RECIPES）と設備の材料（FacilityDB）から自動で数える（説明の文章を別に書かない）。

## 分類（インベントリの並び順・色。増減してよい）
const CATEGORIES := ["素材", "加工品", "食料", "燃料", "道具"]
const CATEGORY_COLORS := {
	"素材": Color("d9b36b"), "加工品": Color("9fb8de"), "食料": Color("8fd68f"), "燃料": Color("f29a56"), "道具": Color("c9a6f2"),
}
## インベントリに並べる順（分類の順）
const ORDER := [
	GameData.Item.MEAT, GameData.Item.HIDE, GameData.Item.BONE, GameData.Item.FAT, GameData.Item.WOOD, GameData.Item.STONE, GameData.Item.IRON_ORE,
	GameData.Item.IRON, GameData.Item.REPAIR_KIT, GameData.Item.FOOD, GameData.Item.FUEL,
	GameData.Item.HAMMER, GameData.Item.PICKAXE, GameData.Item.ADV_PICK, GameData.Item.AXE, GameData.Item.IRON_AXE,
]


## インベントリに出るアイテム（獲物 CARCASS は運搬中の物で、倉庫には入らない）
static func all() -> Array:
	return ORDER.duplicate()


static func name_of(item: int) -> String:
	return GameData.ITEM_NAMES.get(item, "?")


static func tex(item: int) -> Texture2D:
	return GameData.item_tex(item)


static func category_of(item: int) -> String:
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


## 1スタックの最大数（実装指示書: 通常アイテムは100、道具は1）。
static func stack_limit(item: int) -> int:
	return 1 if item in GameData.TOOL_ITEMS else 100


## そのアイテムを材料に使うもの [{"kind": "recipe" | "build", "id": …, "name": …, "out": 作るアイテム（建設は -1）}]
static func uses_of(item: int) -> Array:
	var l: Array = []
	for r in GameData.RECIPES:
		if r["in"].has(item):
			l.append({"kind": "recipe", "id": r["id"], "name": r["name"], "out": int(r["out"])})
	for id in FacilityDB.ids():
		if FacilityDB.def(id)["cost"].has(item):
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
	if item in GameData.GROUND_ITEMS:
		l.append("採取")
	if item in GameData.CREATURE_ITEMS:
		l.append("狩猟")
	if not makers_of(item).is_empty():
		l.append("加工")
	return l