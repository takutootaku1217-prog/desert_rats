class_name TownDB
extends RefCounted
## 全数値は中央都市の最小試作。Notionの確定バランスではない。
const BUY := {GameData.Item.FOOD:4, GameData.Item.FUEL:8, GameData.Item.REPAIR_KIT:8}
const SELL := {GameData.Item.WOOD:2, GameData.Item.STONE:2, GameData.Item.IRON_ORE:3, GameData.Item.MEAT:2, GameData.Item.HIDE:2, GameData.Item.BONE:2, GameData.Item.FAT:2}
const SERVICE_UNIT := 25.0
const SERVICE_PRICE := 8 # 最大25の回復。端数は実回復量で切上げ課金。
const SUPPLY_ITEM := GameData.Item.WOOD
const SUPPLY_COUNT := 3
const SUPPLY_REWARD := 9
const DELIVERY_TO := "south_oasis"
const DELIVERY_REWARD := 20
const HELP_SECONDS := 30.0
const HELP_REWARD := 24

## 分類は進行の役割。共通プレイヤーLv/経験値やメインの解放条件を作らない。
const MISSION_CATEGORIES := {
 "main":{"name":"メインクエスト","role":"ストーリー進行。内容は準備中"},
 "sub":{"name":"サブクエスト","role":"お金・物資・装備・仲間などの強化でメイン攻略を楽にする。全達成は必須ではない"},
}
const MISSIONS := {
 "supply":{"category":"sub","name":"木材の納品","repeatable":true},
 "delivery":{"category":"sub","name":"村への書状配達","repeatable":true},
 "help":{"category":"sub","name":"都市の荷札整理","repeatable":true},
}
