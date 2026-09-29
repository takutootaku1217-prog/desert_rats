class_name CargoDB
extends RefCounted
## 積載量（倉庫の容量）の表（プロトタイプの仮の数値）。数値の調整はここだけでよい。
##
## 考え方:
##  - 倉庫は2つの区画（素材棚・加工品置き場）に分かれ、区画ごとに「積載量」がある。
##    区画を分けるのは、素材で棚が埋まって食料・燃料の置き場がなくなる（詰み）のを防ぐため。
##  - プレイヤーは積載量を、素材ごとの「枠（いくつまで置くか）」に割り当てる（運営の方針 → 積載の割り当て）。
##    枠の合計は積載量まで。ある素材を増やしたければ、別の素材の枠を減らす。
##  - 枠がいっぱいの素材は、回収・狩猟・加工の対象から外れる（無駄足を防ぐ）。
##    それでも入りきらない分（同時に運んでいた物など）は捨てる。
##  - 最初の割り当ては、放置でも回るように決めてある（枠の合計 = 積載量）。
## 将来: 拠点の強化や部屋で積載量を増やす（BaseStorage.capacity_bonus）。SIZES で重い物ほど場所を取るようにする。

enum Bay { RAW, PRODUCT }

const BAY_NAMES := {Bay.RAW: "素材棚", Bay.PRODUCT: "加工品置き場"}
const CAPACITY := {Bay.RAW: 60, Bay.PRODUCT: 48}                  # 区画ごとの積載量

## 最初の割り当て（個数）。素材棚の合計 60、加工品置き場の合計 48。
const DEFAULT_QUOTA := {
	GameData.Item.MEAT: 10, GameData.Item.HIDE: 6, GameData.Item.BONE: 6, GameData.Item.FAT: 8,
	GameData.Item.WOOD: 14, GameData.Item.STONE: 8, GameData.Item.IRON_ORE: 8,
	GameData.Item.FOOD: 18, GameData.Item.FUEL: 12, GameData.Item.REPAIR_KIT: 10, GameData.Item.IRON: 8,
}

## 1個あたりの大きさ（枠の合計の計算に使う）。書いていない物は 1。
const SIZES := {}

const QUOTA_STEP := 2                    # 画面の＋／－で増減する量
const WARN_RATIO := 0.8                  # 枠のこの割合を超えたら、表示を警告色にする
const MIN_DROP_FIT := 0.5                # 獲物の素材のうち、これ以上の割合が入らないなら狩り・運搬をしない


static func items_of(bay: int) -> Array:
	return GameData.RAW_ITEMS if bay == Bay.RAW else GameData.PRODUCT_ITEMS


## 素材・加工品の区画。倉庫に置かない物（獲物など）は -1。
static func bay_of(item: int) -> int:
	if item in GameData.RAW_ITEMS:
		return Bay.RAW
	if item in GameData.PRODUCT_ITEMS:
		return Bay.PRODUCT
	return -1


static func size_of(item: int) -> int:
	return int(SIZES.get(item, 1))


static func default_quota() -> Dictionary:
	return DEFAULT_QUOTA.duplicate()
