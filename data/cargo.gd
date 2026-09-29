class_name CargoDB
extends RefCounted
## 積載量（倉庫の容量）の表（プロトタイプの仮の数値）。数値の調整はここだけでよい。
##
## 考え方（2026-09-30 に、ARK風の「重量制」へ作り替えた。ユーザーの指示）:
##  - 素材ごとに「重さ」（SIZES）がある。倉庫は、素材ごとの個数上限ではなく、
##    拠点全体の「いまの重さ合計 / 最大の重さ」という**1本の積載量**で管理する。
##  - 重い素材（石・鉄鉱石など）を積みすぎると、ほかの物（食料・燃料など）が入らなくなる。
##    以前あった「素材棚・加工品置き場」を分けた個別の上限や、素材ごとに枠を割り当てる画面（運営の方針の
##    旧「積載の割り当て」ページ）は廃止した。Bay（RAW/PRODUCT）は、いまは表示のグループ分け（倉庫の棚と床の
##    どちらに描くか・ツールチップの内訳）だけに使う。積載の上限には関係ない。
##  - 置き場がいっぱい（残りの重さが足りない）素材は、回収・狩猟・加工の対象から外れる（無駄足を防ぐ）。
##    それでも入りきらない分（同時に運んでいた物・遠征の戦利品など）は捨てる。
##  - 道具（GameData.TOOL_ITEMS）は、これまでどおり積載量の対象外（重さを持たない）。
## 将来: 拠点の強化・設備（荷台の増設。data/facilities.gd）で最大の重さを増やす（BaseStorage.capacity_bonus）。

enum Bay { RAW, PRODUCT }

const BAY_NAMES := {Bay.RAW: "素材棚", Bay.PRODUCT: "加工品置き場"}

## 拠点全体の最大の重さ（プレイヤーの強化なしの基本値）。**仮の値**:
## 旧「素材棚60・加工品置き場48（枠の個数の合計）」を、下の SIZES の重さで数え直した合計（約362）に近い、切りのよい数。
const CAPACITY := 360

## 素材1個あたりの重さ（プロトタイプの仮の数値）。ユーザー提示の例（食料0.5・皮/骨/脂肪0.5・生肉1・木材2・石3・
## 鉄鉱石4・鉄3・燃料2・修理資材2）を、整数のまま扱うため**2倍**にした（食料=1 を基準の重さとする）。
## 書いていない物は 1（旧来の「全部1」の名残。今は主要な素材はすべてここに書いてある）。
const SIZES := {
	GameData.Item.FOOD: 1, GameData.Item.HIDE: 1, GameData.Item.BONE: 1, GameData.Item.FAT: 1,
	GameData.Item.MEAT: 2,
	GameData.Item.WOOD: 4, GameData.Item.FUEL: 4, GameData.Item.REPAIR_KIT: 4,
	GameData.Item.STONE: 6, GameData.Item.IRON: 6,
	GameData.Item.IRON_ORE: 8,
}

const WARN_RATIO := 0.8                  # 積載率がこの割合を超えたら、表示を警告色にする
const MIN_DROP_FIT := 0.5                # 獲物の素材のうち、これ以上の割合が入らないなら狩り・運搬をしない


static func items_of(bay: int) -> Array:
	return GameData.RAW_ITEMS if bay == Bay.RAW else GameData.PRODUCT_ITEMS


## 素材・加工品のどちらのグループか（表示だけに使う。積載の上限には関係ない）。倉庫に置かない物（獲物など）は -1。
static func bay_of(item: int) -> int:
	if item in GameData.RAW_ITEMS:
		return Bay.RAW
	if item in GameData.PRODUCT_ITEMS:
		return Bay.PRODUCT
	return -1


static func size_of(item: int) -> int:
	return int(SIZES.get(item, 1))
