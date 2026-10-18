class_name TownDB
extends RefCounted
## 全数値は中央都市の最小試作。Notionの確定バランスではない。
const BUY := {GameData.Item.FOOD:4, GameData.Item.FUEL:8, GameData.Item.REPAIR_KIT:8}
const SELL := {GameData.Item.WOOD:2, GameData.Item.STONE:2, GameData.Item.IRON_ORE:3, GameData.Item.MEAT:2, GameData.Item.HIDE:2, GameData.Item.BONE:2, GameData.Item.FAT:2}
const SERVICE_UNIT := 25.0
const SERVICE_PRICE := 8 # 最大25の回復。端数は実回復量で切上げ課金。
## 納品はプレイヤーの通常在庫だけを使う。製作注文・運搬予約は TownEconomy.available で除外する。
const SUPPLY_OFFERS := {
 GameData.Item.WOOD:{"count":6,"reward":24},
 GameData.Item.STONE:{"count":6,"reward":24},
}
const REVIVAL_COST := 48 # Two ordinary 24 Cr supply rewards.
const DELIVERY_TO := "south_oasis"
const DELIVERY_REWARD := 32
const DELIVERY_PARCEL_WEIGHT := 12
## 都市で燃料・所持金とも0でも出発できる一度だけの前渡し。取消しても再発行しない。
const DELIVERY_FUEL_ADVANCE := 10.0
const RECOVERY_TO := "east_sands"
const RECOVERY_REWARD := 38
const RECOVERY_PARCEL_WEIGHT := 16
## 遺失荷物は下層デッキ上（LO_Y=482）ではなく、既存スロープの先の地上に置く。
## floor_of_y が 0 になる y=520 以上を使うので、移動は RAMP_TOP/RAMP_FOOT を経由する。
const RECOVERY_POINT := Vector2(1080.0, GameData.GROUND_Y_MIN + 64.0)

## 分類は進行の役割。共通プレイヤーLv/経験値やメインの解放条件を作らない。
const MISSION_CATEGORIES := {
 "main":{"name":"メインクエスト","role":"ストーリー進行。内容は準備中"},
 "sub":{"name":"サブクエスト","role":"お金・物資・装備・仲間などの強化でメイン攻略を楽にする。全達成は必須ではない"},
}
const MISSIONS := {
 "supply":{"category":"sub","name":"素材の調達納品","repeatable":true},
 "delivery":{"category":"sub","name":"預かり荷物の配達","repeatable":true},
 "recovery":{"category":"sub","name":"遺失物の回収","repeatable":true},
}
