class_name CargoDB
extends RefCounted
## 積載量（倉庫の容量）の表。ARK風の「総重量」方式（実装指示書 2026-09-30: スタック制・総重量制・木製荷台・道具棚）。
##
## 考え方:
##  - 素材棚・加工品置き場という区画ごとの容量、アイテムごとの個数の枠（quota）は廃止した。
##  - 収納の制限は、移動拠点全体の「いまの重さ（現在重量）/ 最大の重さ（最大重量）」の1本だけ。
##  - 現在重量は、倉庫の在庫だけでなく、作業場の材料・加工設備に投入済みの材料・完成して取り出し待ちの物・
##    仲間が装備している道具・倉庫と作業場の間を運搬中のアイテムも含めた、拠点全体の合計（Main.total_weight）。
##  - 獲物（CARCASS）は運搬途中の一時データなので、重量には含めない（倉庫に入らない）。
##  - 最大重量は、基本値（BASE_MAX_WEIGHT）に、建てた設備の効果（例: 木製荷台 +100）を足したもの。
##    増えた分を別の変数に二重保存せず、そのつど FacilityDB の建設数から計算する（scripts/storage.gd の max_weight）。

## 1個あたりの重さ（整数）。ここに無い（かつ CARCASS でない）アイテムの重さを尋ねると、item_weight() が
## 警告を出し、明らかに大きい値を返す（黙って0にしない。開発中に登録漏れへ気づけるように）。
const WEIGHTS := {
	GameData.Item.FOOD: 1, GameData.Item.MEAT: 1, GameData.Item.HIDE: 1, GameData.Item.BONE: 1, GameData.Item.FAT: 1,
	GameData.Item.WOOD: 2, GameData.Item.STONE: 3, GameData.Item.IRON_ORE: 4, GameData.Item.IRON: 3,
	GameData.Item.FUEL: 2, GameData.Item.REPAIR_KIT: 2,
	GameData.Item.HAMMER: 4, GameData.Item.AXE: 4, GameData.Item.PICKAXE: 6, GameData.Item.IRON_AXE: 6, GameData.Item.ADV_PICK: 8,
}
const UNKNOWN_WEIGHT := 999999        # 重さが登録されていないアイテム（バグ）に使う、明らかに大きい値
const BASE_MAX_WEIGHT := 200          # 拠点の基本の最大重量（設備の効果を足す前）
const STACK_LIMIT := 100              # 通常アイテムの1スタックの最大数（道具は ItemDB.stack_limit で1）
const WARN_RATIO := 0.75              # 積載率がこの割合を超えたら注意色
const DANGER_RATIO := 0.90            # 積載率がこの割合を超えたら警告色（100%で満載）
const MIN_DROP_FIT := 0.5             # 獲物の素材のうち、これ以上の重さが入らないなら狩り・運搬をしない


## item 1個の重さ。CARCASS や、登録のないアイテムを渡すのはバグ（開発中に気づけるよう警告して大きな値を返す）。
static func item_weight(item: int) -> int:
	if WEIGHTS.has(item):
		return int(WEIGHTS[item])
	push_error("CargoDB: 重さが登録されていないアイテム(%d)" % item)
	return UNKNOWN_WEIGHT


## n個ぶんの重さ
static func weight_of(item: int, n: int) -> int:
	return item_weight(item) * n


## 登録漏れがないかの検査（診断ツール用）。GameData.Item のうち CARCASS 以外は、すべて重さを持つべき。
static func missing_weights() -> Array:
	var l: Array = []
	for it in GameData.Item.values():
		if it == GameData.Item.CARCASS:
			continue
		if not WEIGHTS.has(it):
			l.append(it)
	return l
