class_name PrototypeTownLoop
extends RefCounted
## Small, disposable policy for the first-town verification loop.
##
## Keep temporary scope in one place. This is deliberately a profile adapter,
## not a new progression, quest, pricing, or vehicle-upgrade system.

const FIRST_TOWN_REGION := "a_start"
const NOTICE := "[検証用] 価格・依頼数・サービス範囲は仮です。既存の実取引だけを接続しています。"
const UNAVAILABLE_MISSION_NOTICE := "[未接続] 配送・救助は砂漠用の行き先しかないため、第一地域では受注できません。"
const UNAVAILABLE_VEHICLE_NOTICE := "装甲は製作した装甲キットを確定時に消費して装着します。その他の車両換装は素材非消費の試作です。"
const UNAVAILABLE_TRAINING_NOTICE := "[未接続] 共通レベルや訓練XPは追加しません。仲間は既存の休息・装備・ランク表示を使います。"
const TOWN_BUILDINGS := {
	"missions": {
		"label": "依頼所",
		"speaker": "受付係（仮）",
		"dialogue": "まずはこの街で完結する供給依頼を試してください。配送と救助の行き先はまだ接続していません。",
		"facility": "missions",
	},
	"market": {
		"label": "購買店",
		"speaker": "店主（仮）",
		"dialogue": "資源を売って必要品を買えます。表示中の価格は検証用で、取引は既存の在庫・通貨処理を使います。",
		"facility": "market",
	},
	"service": {
		"label": "車両ヤード",
		"speaker": "整備士（仮）",
		"dialogue": "燃料補給と部位修理を受け付けます。装甲は作成画面でキットを製作し、車両換装で比較して確定すると装着できます。装甲以外の換装は素材非消費の試作です。",
		"facility": "service",
	},
	"growth": {
		"label": "工房・休憩所",
		"speaker": "作業長（仮）",
		"dialogue": "既存の制作、施設建設、仲間の休息・装備をここから試せます。共通レベルは追加しません。",
		"facility": "growth",
	},
}

static func is_first_town_profile(game) -> bool:
	return game != null and game.world != null and game.world.first_region()

static func is_town_hub(game) -> bool:
	if game == null or game.world == null:
		return false
	if is_first_town_profile(game):
		return game.world.region == FIRST_TOWN_REGION
	return game.world.region == "central_trade"

static func is_safe_town(game) -> bool:
	return is_first_town_profile(game) and game.world.active and game.world.region == FIRST_TOWN_REGION and game.world.phase == "stopped" and game.quarry.state == "road"

static func mission_enabled(game, mission: String) -> bool:
	return mission == "supply" if is_first_town_profile(game) else true

static func town_building(id: String) -> Dictionary:
	return Dictionary(TOWN_BUILDINGS.get(id, {})).duplicate(true)
