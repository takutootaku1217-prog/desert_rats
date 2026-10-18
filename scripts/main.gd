extends Node2D
## ゲーム全体の入口。背景・拠点・仲間・資源と生物の出現・拠点の維持・UIを組み立てる。
##
## 第1段階のループ:
##   移動 → 生物・資源が現れる → 狩猟・採取 → 倉庫へ（獲物は解体）→ 加工（食料・燃料・鉄・修理資材）
##   → 消費（仲間が食べる・移動と炉で燃料・時間と移動と加工で傷む）→ 補給・修理で維持 → 移動

var journey := JourneyPlan.new()
var route_notice: RouteNotice
var town := TownEconomy.new()
var town_ui: TownUI
var world := WorldTrip.new()
var _pack_ticket := {}
var _pack_nonce := 0
var map_ui: WorldMapUI
var quarry := QuarryTrip.new()
var quarry_ui: QuarryUI
var save_ui: SaveUI

var target_speed := 60.0          # プレイヤーが決める目標速度（↑↓キー）
var scroll_speed := 60.0          # 実際の速度。燃料切れ・走行装置の故障で遅くなる
var storage: BaseStorage
var processor: BaseProcessor
var base: MobileBase
var ground_sort: Node2D           # 資源・生物・敵・仲間をまとめて、足元のY位置で前後判定させる共通の親（BG-04対策）
var resources_root: Node2D
var creatures_root: Node2D
var enemies_root: Node2D
var workers: Array = []
var blueprints := {}              # 入手した設計図（id -> true）。入手の仕組みは今後
var ui: WorkPriorityUI
var detail: CrewDetailUI
var policy: PolicyUI
var operations := FieldOperations.new()
var navigation: NavigationBar
var status: StatusPanel
var director: Director            # 旅の出来事（天候・トラブル・好機）。scripts/director.gd
var event_hud: EventHUD
var expedition: Expedition        # 遺跡の探索（調査隊）。scripts/expedition.gd
var expedition_ui: ExpeditionUI
var build_ui: BuildUI             # 建設の画面（Bキー）。ui/build_ui.gd
var room_ui: BaseUI               # 部屋の変更の画面（Rキー・右の「部屋の変更」ボタン）。ui/base_ui.gd
var inventory_ui: InventoryUI     # インベントリの画面（Tabキー・右の「インベントリ」ボタン）。ui/inventory_ui.gd
var craft_ui: CraftUI             # 制作の画面（Fキー・右の「制作」ボタン）。ui/craft_ui.gd
var base_view: BaseView           # 拠点の見え方（外装 ⇄ 内装）。scripts/base_view.gd
var view_switch: ViewSwitchUI     # 外装・内装の切り替えボタン（Oキー・Iキー）。ui/view_switch.gd

# ---- カメラ追従（個体管理タブとカメラ追従_仕様書のうち、カメラ追従の最小構成。2026-09-30） ----
# Camera2D は世界（背景・拠点・仲間・資源。CanvasLayer の外）だけを動かす。HUD は CanvasLayer なので触れない。
var camera: Camera2D
var follow_target = null          # 追従中の Worker（null なら追従なし）。main._select で設定される
var _follow_label: Label          # 仲間管理の入口の下に置く、1名分だけの追従状態
var crew_alerts: CrewAlertUI       # 不調の個体だけを番号・キャラ画像・症状で知らせる通常HUD
const FOLLOW_DEADZONE_HALF := 150.0   # 画面中央からこの範囲内に対象がいれば、カメラは動かさない（常に対象を追わない＝滑らかさ優先）
const FOLLOW_SMOOTH_SPEED := 6.0      # Camera2D の内蔵スムージングの速さ
const FOLLOW_SCREEN_CENTER_X := 640.0 # 1280x720 の画面中央x（カメラなしのときと同じ見え方の基準）

# ---- 部屋（車体の区画。data/rooms.gd） ----
var room_layout: Dictionary = Rooms.default_layout()   # 区画 -> 部屋の種類。初期配置は、これまでのゲームと同じ
var total_rooms_built := 0                              # 部屋を建てた・移した・空けた回数（確認用）

# ---- プレイヤーの方針（運営の方針画面で変更する） ----
var recipe_priority := GameData.DEFAULT_RECIPE_PRIORITY.duplicate()   # 旧保存の移行用。現在の補充は refill_settings
var gather_policy := {GameData.Item.WOOD: 3, GameData.Item.STONE: 3, GameData.Item.IRON_ORE: 3}  # ★0〜5
var hunt_policy := {"hare": true, "lizard": true, "hump": true}

# ---- 維持の状態 ----
var hungry := false               # 空腹の仲間がいる（仲間ごとの満腹度 Worker.hunger から毎フレーム決まる。表示・作業の判断用）
var food_claims := 0              # 食べに向かっている仲間の数（在庫から引く。1個の食料に2人が向かわないように）

# ---- 確認用の累計 ----
var total_gathered := 0
var total_hunted := 0
var total_eaten := 0
var tool_auto := true             # 採取の道具を、倉庫から自動で仲間に持たせる（方針の「道具」で切り替え）
var _tool_clock := 0.0
var build_queue: Array = []       # 建設の依頼（設備 id。待ち）。材料と必要設備がそろうと、仲間が材料を運んで作る（data/facilities.gd）
var total_built := 0              # 建設した設備の数（確認用）
var total_wasted := 0             # 倉庫に入りきらず捨てた数（積載量。data/cargo.gd）
var _waste_note_at := -999.0      # 最後に「捨てた」を記録へ出した時刻（記録が増えすぎないように）
var last_carcass = null           # 直前に倒した生物の獲物（倒した仲間がそのまま運ぶ）

var _spawn_dist := 40.0           # 次の地面の資源までの残り距離
var _creature_dist := 200.0       # 次の生物までの残り距離
var wave := 0
var kills := 0
var game_over := false
var _wave_timer := 14.0
var _over_layer: CanvasLayer

const SPAWN_X := 1330.0
const SPAWN_Y_MIN := GameData.GROUND_Y_MIN + 4.0
const SPAWN_Y_MAX := GameData.GROUND_Y_MAX - 4.0
## Optional south_oasis prototype: a shallow continuous strip with two readable
## front/back resting lanes. Normal maps and interior floors keep their existing coordinates.
## The optional south_oasis strip remains above the 720p navigation bar
## (which starts at y=650), while retaining a 55px continuous depth band.
const OUTDOOR_DEPTH_BACK_Y := 570.0
const OUTDOOR_DEPTH_FRONT_Y := 625.0

const WORKER_DEFS := [
	{"name": "ネズ吉", "palette": "grey",
		"profile": {"level": 3, "gender": 0, "ranks": {GameData.Field.GATHERER: 3, GameData.Field.COMBAT: 1, GameData.Field.DEV: 0},
			"skills": ["目利き"]},
		"prio": {GameData.Job.HUNT: 3, GameData.Job.GATHER: 5, GameData.Job.HAUL: 3, GameData.Job.PROCESS: 1,
			GameData.Job.REPAIR: 2, GameData.Job.REST: 3, GameData.Job.COMBAT: 3}},
	{"name": "チュー太", "palette": "tan",
		"profile": {"level": 4, "gender": 0, "ranks": {GameData.Field.COMBAT: 2, GameData.Field.GATHERER: 2, GameData.Field.COOK: 1},
			"skills": ["生還率", "健脚"]},
		"prio": {GameData.Job.HUNT: 5, GameData.Job.GATHER: 3, GameData.Job.HAUL: 4, GameData.Job.PROCESS: 2,
			GameData.Job.REPAIR: 2, GameData.Job.REST: 3, GameData.Job.COMBAT: 5}},
	{"name": "モモ", "palette": "pink",
		"profile": {"level": 2, "gender": 1, "ranks": {GameData.Field.DEV: 3, GameData.Field.MEDIC: 1, GameData.Field.COOK: 1},
			"skills": ["武器設計"]},
		"prio": {GameData.Job.HUNT: 1, GameData.Job.GATHER: 1, GameData.Job.HAUL: 3, GameData.Job.PROCESS: 5,
			GameData.Job.REPAIR: 4, GameData.Job.REST: 3, GameData.Job.COMBAT: 2}},
]


func _ready() -> void:
	# 診断が明示した場合だけ、初期生成から同じ乱数列を使う。通常起動は従来どおり。
	if has_meta("diagnostic_seed"):
		seed(int(get_meta("diagnostic_seed")))
	else:
		randomize()
	# This is an opt-in prototype. The normal map stays on its existing
	# one-line layout unless the comparison flag is supplied.
	if OS.get_cmdline_user_args().has("two-lane-depth-prototype"):
		set_meta("ground_depth_strip_config", {"enabled": true, "back_y": OUTDOOR_DEPTH_BACK_Y, "front_y": OUTDOOR_DEPTH_FRONT_Y, "location": "region:south_oasis"})
	director = Director.new()       # 出来事（base や仲間より先に作る。倍率を読まれるため）
	director.setup(self)
	quarry.setup(self)
	expedition = Expedition.new()
	expedition.setup(self)
	var bg := WorldScroll.new()
	bg.game = self
	add_child(bg)

	# カメラ（世界側だけを動かす。position=0 なら、これまでと画素まで同じ見え方）
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT   # position を「画面左上に来る世界座標」にする（中央基準だとカメラなしの見え方とズレる）
	camera.position_smoothing_enabled = true                   # 内蔵のスムージングで、滑らかに追う・滑らかに戻る
	camera.position_smoothing_speed = FOLLOW_SMOOTH_SPEED
	camera.position = Vector2(GameData.HULL_POS.x, 0.0)
	camera.zoom = Vector2.ONE                                  # 拡大縮小はしない（ドット絵がぼやけるのを避ける）
	add_child(camera)
	camera.make_current()

	base = MobileBase.new()
	base.game = self
	add_child(base)
	storage = base.storage
	storage.overflowed.connect(_on_overflow)
	processor = base.processor
	if FacilityDB.start_all:
		base.grant_all()            # 自己診断・放置比較ツール用。ゲームは設備なし（手作業）から始まる
	# 最初の蓄え（すぐに詰まないよう、少しだけ持って出発する）
	storage.add_item(GameData.Item.FOOD, 8)
	storage.add_item(GameData.Item.FUEL, 2)
	storage.add_item(GameData.Item.REPAIR_KIT, 2)
	if not FacilityDB.start_all:                   # 新規開始分のみ（ロード時は保存された資産を復元）
		for it in FacilityDB.START_STOCK:
			storage.add_item(it, FacilityDB.START_STOCK[it])

	# 地面の上の物（資源・生物・敵・仲間）を、木の順番ではなく足元のY位置で前後判定させる（BG-04: 仲間と採取ポイントの重なりが逆に見えていたのを直した）。
	# y_sort_enabled は、この親から資源・生物・敵・仲間まで全部の階層で true にしないと、個々の絵ではなく箱（Resources/Creatures/...）単位でしか揃わない。
	ground_sort = Node2D.new()
	ground_sort.name = "GroundSort"
	ground_sort.y_sort_enabled = true
	add_child(ground_sort)

	resources_root = Node2D.new()
	resources_root.name = "Resources"
	resources_root.y_sort_enabled = true
	ground_sort.add_child(resources_root)

	creatures_root = Node2D.new()
	creatures_root.name = "Creatures"
	creatures_root.y_sort_enabled = true
	ground_sort.add_child(creatures_root)

	enemies_root = Node2D.new()
	enemies_root.name = "Enemies"
	enemies_root.y_sort_enabled = true
	ground_sort.add_child(enemies_root)

	var workers_root := Node2D.new()
	workers_root.name = "Workers"
	workers_root.y_sort_enabled = true
	ground_sort.add_child(workers_root)
	for i in WORKER_DEFS.size():
		var d: Dictionary = WORKER_DEFS[i]
		var w := Worker.new()
		w.setup(self, d["name"], d["palette"], d["prio"], i, d["profile"])
		w.position = Vector2(GameData.STORAGE_X - 120.0 + i * 90.0, GameData.LO_Y)
		workers_root.add_child(w)
		workers.append(w)

	ui = WorkPriorityUI.new()
	add_child(ui)
	ui.build(workers)
	status = StatusPanel.new()
	status.game = self
	add_child(status)
	detail = CrewDetailUI.new()
	detail.game = self
	add_child(detail)
	ui.management_requested.connect(detail.toggle)
	crew_alerts = CrewAlertUI.new()
	crew_alerts.game = self
	add_child(crew_alerts)
	crew_alerts.build(workers)
	policy = PolicyUI.new()
	policy.game = self
	add_child(policy)
	var follow_layer := CanvasLayer.new()      # 仲間管理の入口直下。HUD なのでカメラの影響を受けない
	follow_layer.layer = 10
	add_child(follow_layer)
	_follow_label = GameData.make_label("", 14, Color("ffe9b0"))
	_follow_label.position = Vector2(10, 56)
	_follow_label.size = Vector2(320, 22)
	_follow_label.clip_text = true
	_follow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	follow_layer.add_child(_follow_label)
	_select(workers[0])
	# 出来事の見た目と画面（左下）
	var fx := WeatherFX.new()
	fx.game = self
	add_child(fx)
	event_hud = EventHUD.new()
	event_hud.game = self
	add_child(event_hud)
	expedition_ui = ExpeditionUI.new()
	expedition_ui.game = self
	add_child(expedition_ui)
	build_ui = BuildUI.new()
	build_ui.game = self
	add_child(build_ui)
	room_ui = BaseUI.new()
	room_ui.game = self
	add_child(room_ui)
	inventory_ui = InventoryUI.new()
	inventory_ui.game = self
	add_child(inventory_ui)
	craft_ui = CraftUI.new()
	craft_ui.game = self
	add_child(craft_ui)
	base_view = BaseView.new()                     # 外装 ⇄ 内装（仲間ができたあとに作る。仲間の見え方も決めるため）
	base_view.game = self
	add_child(base_view)
	view_switch = ViewSwitchUI.new()
	view_switch.game = self
	add_child(view_switch)
	quarry_ui = QuarryUI.new()
	quarry_ui.game = self
	add_child(quarry_ui)
	save_ui = SaveUI.new()
	save_ui.game = self
	add_child(save_ui)
	world.setup(self)
	map_ui = WorldMapUI.new()
	map_ui.game = self
	add_child(map_ui)
	journey.setup(self)
	route_notice=RouteNotice.new()
	route_notice.game=self
	add_child(route_notice)
	town.setup(self)
	town_ui=TownUI.new()
	town_ui.game=self
	add_child(town_ui)
	operations.setup(self)
	navigation = NavigationBar.new()
	navigation.game = self
	add_child(navigation)


func _process(delta: float) -> void:
	if game_over:
		return
	if GameData.ENABLE_COMBAT and base.hp <= 0.0:
		_game_over()
		return
	if GameData.ENABLE_RAIDS and base.parts[GameData.Part.HULL] <= 0.0:
		_game_over()                   # 車体が壊れきった（襲撃・嵐・放置）
		return
	if GameData.ENABLE_COMBAT and not quarry.sheltered():
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_spawn_wave()
			_wave_timer = 22.0
	# 移動: 燃料切れや走行装置の故障で遅くなる（完全には止めない。止まると資源が来なくなるため）
	scroll_speed = minf(target_speed, base.speed_limit())
	if not base.has_fuel():
		scroll_speed = minf(scroll_speed, GameData.CRAWL_SPEED)
	scroll_speed *= director.speed_mult()      # 天候の対処方針（減速・停止）
	scroll_speed = quarry.speed_limit(scroll_speed, delta)
	scroll_speed = world.speed_limit(scroll_speed, delta)
	var dist := scroll_speed * delta
	quarry.tick(dist)
	journey.tick(delta)
	world.tick(dist)
	town.observe()
	base.burn(dist)
	base.leak_fuel(delta, scroll_speed)
	base.wear_by(delta, dist)
	director.tick(delta, dist)                 # 出来事の進行（予報・発生・終了）
	operations.tick()
	expedition.tick(delta)                     # 調査隊の進行（遺跡の探索）
	_tool_clock += delta                       # 倉庫の道具を、仲間に持たせ直す（採取の道具）
	if _tool_clock >= GatherDB.TOOL_CHECK_SECONDS:
		_tool_clock = 0.0
		manage_tools()
	_update_hungry_flag()
	_feed_clock += delta                       # 手動の制作を、作業場の材料から加工設備の注文にする
	if _feed_clock >= CraftDB.FEED_SECONDS:
		_feed_clock = 0.0
		_feed_crafts()
	# 地面の資源と生物は、進んだ距離に応じて現れる（天候で出にくくなる）
	if world.active:
		_update_camera(delta)
		return # 地図の道中資源・生物は有限の道路記録から生成する
	_spawn_dist -= dist * director.spawn_mult()
	if _spawn_dist <= 0.0:
		_spawn_ground_resource()
		if GameData.ENABLE_GATHER_POINTS:
			_spawn_dist = randf_range(GatherDB.SPAWN_DIST_MIN, GatherDB.SPAWN_DIST_MAX)
		else:
			_spawn_dist = randf_range(GameData.SPAWN_DIST_MIN, GameData.SPAWN_DIST_MAX)
	_creature_dist -= dist * director.spawn_mult()
	if _creature_dist <= 0.0:
		_spawn_creature()
		_creature_dist = randf_range(GameData.CREATURE_DIST_MIN, GameData.CREATURE_DIST_MAX)
	_update_camera(delta)


## 食べに行ける食料の数（倉庫の在庫から、食べに向かっている仲間の分を引く）
func food_for_eating() -> int:
	return maxi(0, storage.count_of(GameData.Item.FOOD) - food_claims)


## 空腹の仲間がいるかを更新する（表示・建設の判断用）。食事そのものは、空腹になった仲間が自分で倉庫へ食べに行く（scripts/character_ai.gd）。
func _update_hungry_flag() -> void:
	hungry = false
	for w in workers:
		if not w.away and CrewStatus.wants_to_eat(w):
			hungry = true
			break


# ---------------------------------------------------------------- 方針
## 回収の方針。獲物は常に拾う（★5相当）。方針にない物（敵の落とした肉・皮など）は★3で拾う。
func gather_weight(item: int) -> float:
	update_procurement()
	if procurement_goals.has(item):
		if procurement_available(item)+procurement_transit(item)>=int(procurement_goals[item]): return 0.0
		return 30.0
	if item == GameData.Item.CARCASS:
		return 5.0
	var w := float(gather_policy.get(item, 3))
	if w > 0.0 and build_short_of(item):
		w *= FacilityDB.GATHER_BOOST               # 建設の依頼に足りない材料は、優先して集める
	return w


func hunt_allowed(species: String) -> bool:
	return hunt_policy.get(species, false)


# ---------------------------------------------------------------- 作業場と倉庫の運搬・手動の制作（アイテム・インベントリ・制作システム）
## 作業場 = 加工室（加工設備＋ワークベンチ）の材料置き場（BaseProcessor.stock）。倉庫とは別の置き場で、運ぶまで材料は移らない
## （倉庫に100個あっても、作業場から使えるのは、作業場にある分だけ）。
## 運搬の依頼（transfer_queue）: プレイヤーが決めた量を、仲間（運搬の仕事。同時に CraftDB.TRANSFER_WORKERS 人）が、倉庫 ⇄ 作業場で運ぶ。
## 手動の制作（craft_queue）: 作業場の材料を使って、加工設備の注文にする（材料が作業場にあるときだけ頼める）。
## 自動の加工（choose_recipe → 運搬 → 注文）は、これまでのまま（作業場の材料は使わない）。
var transfer_queue: Array = []    # 運搬の依頼 [{item, n, dir}]。dir = "to_workshop"（倉庫→作業場）／"to_storage"（作業場→倉庫）
var transfer_worker = null        # いま運搬の依頼を引き受けている仲間
var craft_queue: Array = []       # 手動の制作の待ち [{id, n}]（n = 作る回数）
var total_transferred := 0        # 運んだ個数（確認用）
var total_crafted_by_hand := 0    # 手動の制作で作った回数（確認用）
var _feed_clock := 0.0


## 作業場にある材料の数（注文になっていない分）
func workshop_count(item: int) -> int:
	return processor.stock.count(item)


## 作業場へ未到着の運搬分。素材運搬ボタンの連打で同じ不足分を重ねない。
func workshop_incoming(item: int) -> int:
	var n := _queued_transfer(item,"to_workshop")
	for w in workers:
		if w.ai.state == CharacterAI.State.XFER_MOVE and w.ai.xfer_dir == "to_workshop" and w.carrying == item:
			n += w.carry_n
	return n


## 手動の制作の待ちが使う予定の材料の数
func workshop_reserved(item: int) -> int:
	var n := 0
	for e in craft_queue:
		var r: Dictionary = GameData.recipe_by_id(e["id"])
		n += int(r.get("in", {}).get(item, 0)) * int(e["n"])
	return n


## 制作に使える作業場の材料（制作の待ちが使う予定の分と、倉庫へ戻す依頼の分を除く）
func workshop_available(item: int) -> int:
	return maxi(0, workshop_count(item) - workshop_reserved(item) - _queued_transfer(item, "to_storage"))


## 廃棄できるのは倉庫で未予約の物だけ。運び出した材料は倉庫にはない。
func warehouse_discard_available(item: int) -> int:
	var held := int(reserved_for_builds().get(item, 0)) + _queued_transfer(item, "to_workshop")
	for w in workers:
		var a = w.ai
		match a.state:
			CharacterAI.State.HAUL_TAKE:
				if not a.haul_recipe.has("build"):
					held += int(a.haul_recipe.get("in", {}).get(item, 0))
			CharacterAI.State.EAT_TAKE:
				if item == GameData.Item.FOOD: held += 1
			CharacterAI.State.REFUEL_TAKE:
				if item == a.haul_item: held += 1
			CharacterAI.State.REPAIR_TAKE:
				if item == GameData.Item.REPAIR_KIT: held += 1
	return maxi(0, storage.count_of(item) - held)


## 確認画面が承認する数量・在庫・予約・重量を固定する。
func warehouse_discard_snapshot(item: int, n: int) -> Dictionary:
	if game_over or not item in ItemDB.ORDER or n <= 0 or n > warehouse_discard_available(item): return {}
	return {"item": item, "n": n, "stock": storage.count_of(item),
		"available": warehouse_discard_available(item), "weight": storage.current_weight()}


func discard_warehouse(snapshot: Dictionary) -> bool:
	if snapshot.is_empty(): return false
	var item := int(snapshot.get("item", -1))
	var n := int(snapshot.get("n", 0))
	if warehouse_discard_snapshot(item, n) != snapshot: return false
	if storage.inventory.take_n(item, n) != n: return false
	storage.wasted[item] = int(storage.wasted.get(item, 0)) + n
	director.note("倉庫から廃棄: %s ×%d" % [ItemDB.name_of(item), n])
	return true


func _queued_transfer(item: int, dir: String) -> int:
	var n := 0
	for t in transfer_queue:
		if t["item"] == item and t["dir"] == dir:
			n += int(t["n"])
	return n


func _find_transfer(item: int, dir: String) -> Dictionary:
	for t in transfer_queue:
		if t["item"] == item and t["dir"] == dir:
			return t
	return {}


## 運搬を頼む。頼めた個数を返す（0 = 頼めない）。to_workshop は倉庫にある分まで、to_storage は作業場にある分・倉庫の空きまで。
func request_transfer(item: int, n: int, dir: String) -> int:
	if n <= 0 or not (item in ItemDB.ORDER):
		return 0
	var can := 0
	if dir == "to_workshop":
		can = AutoCraftGuard.available(self,item,null,true)
	elif dir == "to_storage":
		can = workshop_available(item)
	else:
		return 0
	var give := mini(n, can)
	if give <= 0:
		return 0
	var t := _find_transfer(item, dir)
	if t.is_empty():
		transfer_queue.append({"item": item, "n": give, "dir": dir})
	else:
		t["n"] += give
	return give


## 待っている運搬の依頼を取り消す（すでに運んでいる分は、そのまま届く）
func cancel_transfers() -> void:
	transfer_queue.clear()


## 次に運ぶ依頼（元にもう材料がない依頼は、ここで消す）。なければ空
func next_transfer() -> Dictionary:
	for t in transfer_queue.duplicate():
		var src: int = storage.count_of(t["item"]) if t["dir"] == "to_workshop" else processor.stock.count(t["item"])
		if src <= 0:
			transfer_queue.erase(t)
			continue
		return t
	return {}


## 運搬の1回分を始める（仲間が元の置き場に着いたとき）。依頼を減らし、元から取り出して、運ぶ個数を返す（0 なら何もなかった）。
func begin_transfer_trip(item: int, dir: String, worker = null) -> int:
	var t := _find_transfer(item, dir)
	if t.is_empty():
		return 0
	var src_inv: Inventory = storage.inventory if dir == "to_workshop" else processor.stock
	var got := src_inv.take_n(item, mini(int(t["n"]), worker.carry_limit() if is_instance_valid(worker) else CraftDB.TRANSFER_TRIP))
	t["n"] -= got
	if got == 0 or int(t["n"]) <= 0:
		transfer_queue.erase(t)
	return got


## 運搬の1回分が届いた（仲間が行き先に着いたとき）
func finish_transfer_trip(item: int, dir: String, n: int) -> void:
	if dir == "to_workshop":
		processor.stock.add(item, n, Inventory.SOURCE_TRANSFER)
	else:
		storage.store_owned(item, n)
	total_transferred += n


## 手動の制作を頼む（作る回数）。頼めた回数を返す（作業場の材料・置き場の空きの範囲まで。必要設備がなければ 0）。
func request_craft(id: String, n: int) -> int:
	var e := CraftDB.entry_of(id)
	if e.is_empty() or e["kind"] != "recipe" or n <= 0:
		return 0
	var ev: Dictionary = CraftDB.evaluate(e, self, 1)
	if ev["state"] == "locked":
		return 0
	var give := mini(n, int(ev["max_qty"]))
	if give <= 0:
		return 0
	for q in craft_queue:
		if q["id"] == id and bool(q.get("batch",false)) == (give > 1):
			q["n"] += give
			return give
	craft_queue.append({"id": id, "n": give, "batch": give > 1})
	return give


## 待ちの制作を1つ取り消す（材料は作業場に残る）
func cancel_craft(index: int) -> void:
	if index >= 0 and index < craft_queue.size():
		craft_queue.remove_at(index)


## 同じ品目の未着手分だけ取消。加工中の1回/完成品/運搬中は保持する。
func cancel_manual_craft(id: String) -> int:
	var cancelled := 0
	for q in production_orders.duplicate():
		if q.id==id:
			cancelled+=q.n
			production_orders.erase(q)
	for w in workers:
		if w.ai.state==CharacterAI.State.HAUL_TAKE and w.ai.haul_recipe.get("player_order",false) and w.ai.haul_recipe.id==id:
			w.ai.haul_recipe.erase("player_order")
			w.ai._release_task()
			w.ai._set_state(CharacterAI.State.SEARCH)
			cancelled+=1
	for q in craft_queue.duplicate():
		if q["id"] == id:
			cancelled += int(q["n"])
			craft_queue.erase(q)
	for r in processor.orders.duplicate():
		if r.get("manual", false) and r["id"] == id:
			processor.orders.erase(r)
			for it in r["in"]:
				if r.get("player_order",false): storage.store_owned(it,r["in"][it])
				else: processor.stock.add(it, r["in"][it], Inventory.SOURCE_TRANSFER)
			cancelled += 1
	return cancelled


## 注文後の素材移送も追跡し、材料がそろう保管先へ通常運搬で合流する。
func _reconcile_order_stock() -> void:
	for q in production_orders.duplicate():
		var r:=GameData.recipe_by_id(q.id)
		if not has_facility(GameData.recipe_station(r)):continue
		var complete:bool=r["in"].keys().all(func(it):return workshop_available(it)>=int(r["in"][it]))
		if complete and storage.transform_limit(r)>0:
			craft_queue.append({"id":q.id,"n":1,"batch":q.batch})
			claim_order(q.id)
			continue
		# 移送中は到着を待つ。部分在庫は実運搬で合流し、瞬間移動させない。
		if r["in"].keys().any(func(it):return workshop_incoming(it)>0):continue
		for it in r["in"]:
			var missing:=maxi(0,int(r["in"][it])-AutoCraftGuard.available(self,it))
			if missing>0:request_transfer(it,mini(missing,workshop_available(it)),"to_storage")


## 作業場で材料がそろった手動注文を加工設備へ投入する。
func _feed_crafts() -> void:
	_reconcile_order_stock()
	update_procurement()
	if quarry.recalling() or not ProductionPlan.refill(self,true).is_empty():
		return
	while not craft_queue.is_empty() and processor.free_slots() > 0:
		var started := false
		for q in craft_queue:
			var r: Dictionary = GameData.recipe_by_id(q["id"])
			if r.is_empty():
				craft_queue.erase(q)
				started = true
				break
			if not has_facility(GameData.recipe_station(r)) or not processor.stock.has_set(r["in"]) or storage.transform_limit(r, int(q["n"])) <= 0:
				continue
			processor.stock.take_set(r["in"])
			var unit := r.duplicate()
			unit["batch"] = q.get("batch", false)
			processor.receive_manual(unit)
			q["n"] -= 1
			if int(q["n"]) <= 0:
				craft_queue.erase(q)
			started = true
			break
		if not started:
			break

# ---------------------------------------------------------------- 積載量（data/cargo.gd）
## 新規取得の収納不能分は外に残す。保有重量にはまだ入れない。
func keep_outside(item: int, n: int, pos: Vector2) -> void:
	if quarry.sheltered():
		quarry.keep_overflow(item, n)
	else:
		var outdoor_pos := pos
		if world.depth_strip_active():
			outdoor_pos.y = world.clamp_outdoor_y(outdoor_pos.y)
		for i in n:
			var r := ResourceNode.new()
			r.game = self
			r.item = item
			r.position = outdoor_pos
			resources_root.add_child(r)
	director.note("積載上限: %s×%dを外に残しました" % [GameData.ITEM_NAMES[item], n])


## いま倉庫へ向かっている物の数（回収に向かっている・運んでいる）。空き枠から引いて、入りきらない無駄足を防ぐ。
func gather_room() -> Dictionary:
	var inflight := {}
	for r in resources_root.get_children():
		if not is_instance_valid(r.claimed_by): continue
		if r.item == GameData.Item.CARCASS:
			for it in GameData.CREATURES[r.species]["drops"]:
				inflight[it] = int(inflight.get(it, 0)) + int(GameData.CREATURES[r.species]["drops"][it])
		else:
			var held: int = r.claimed_by.carry_n if r.claimed_by.carrying == r.item else 0
			inflight[r.item] = int(inflight.get(r.item, 0)) + maxi(0, r.reserved - held)
	return inflight


## 資源 r を回収してよいか（倉庫に置き場があるか）。inflight は gather_room() の結果。
func has_room_for(r, inflight: Dictionary) -> bool:
	if r.item == GameData.Item.CARCASS:
		return storage.drop_fit(r.species) >= CargoDB.MIN_DROP_FIT
	return gather_free_for(r.item, inflight) > 0


## 他の回収予約を共有重量で差し引いた、item の残り個数。道具と制限なしは従来どおり。
func gather_free_for(item: int, inflight: Dictionary) -> int:
	if not storage.enforce or CargoDB.bay_of(item) < 0:
		return storage.free_for(item)
	var reserved_weight := 0
	for it in inflight:
		if CargoDB.bay_of(it) >= 0:
			reserved_weight += int(inflight[it]) * CargoDB.size_of(it)
	var room := storage.max_weight() - storage.current_weight() - storage.processing_reserve() - reserved_weight
	var space:=maxi(0, floori(float(room) / CargoDB.size_of(item)))
	if procurement_goals.has(item): space=mini(space,maxi(0,int(procurement_goals[item])-procurement_available(item)-procurement_transit(item)-int(inflight.get(item,0))))
	return space


## その生物を狩ってよいか（倒した獲物の素材が倉庫に入るか）
func hunt_has_room(species: String) -> bool:
	return storage.drop_fit(species) >= CargoDB.MIN_DROP_FIT


# ---------------------------------------------------------------- 採取の道具（data/gathering.gd）
## 仲間 w が、枠 slot の道具 tool_item（-1 = 素手）を持っているときの総合点（回収ランク・能力値で変わる）
func _tool_score(w, slot: String, tool_item: int) -> float:
	return GatherDB.tool_score(slot, tool_item, w.ranks.get(GameData.Field.GATHERER, 0), w.field_mult(GameData.Field.GATHERER))


## 道具を使う仲間か（回収の優先度が0でなく、遠征に出ていない）
func _uses_tools(w) -> bool:
	return not w.away and w.priorities.get(GameData.Job.GATHER, 0) > 0


## 枠 slot の道具の割り当てを考える。使える道具 = 倉庫の予備 ＋ 道具を使う仲間がいま持っている物 ＋ extra（作る予定の物など）。
## 「仲間 × 道具」の組み合わせを総合点の高い順に決めていく（いちばん腕のいい仲間に、いちばん相性のよい道具）。
## 回収ランクが低い仲間には、高性能な道具より扱いやすい道具のほうが総合点が高いことがある（適性）。
## 戻り値: {"target": {仲間: 道具}（素手は含まない）, "total": 全員の総合点, "users": 道具を使う仲間}
func _assign_tools(slot: String, extra: Array = []) -> Dictionary:
	var users: Array = []
	for w in workers:
		if _uses_tools(w):
			users.append(w)
	var pool: Array = extra.duplicate()
	for it in GameData.TOOL_ITEMS:
		if GatherDB.slot_of_tool(it) == slot:
			for _i in storage.count_of(it):
				pool.append(it)
	for w in users:
		var cur: int = int(w.tools.get(slot, -1))
		if cur >= 0:
			pool.append(cur)
	var target := {}
	var used := {}                                       # pool の番号 -> 割り当て済み
	for _round in users.size():
		var best_s := -1.0
		var best_w = null
		var best_j := -1
		for w in users:
			if target.has(w):
				continue
			var base: float = _tool_score(w, slot, -1)   # 素手のときの点。これより良くなる組み合わせだけ
			for j in pool.size():
				if used.has(j):
					continue
				var s: float = _tool_score(w, slot, int(pool[j]))
				if s > base + GatherDB.TOOL_MIN_GAIN and s > best_s:
					best_s = s
					best_w = w
					best_j = j
		if best_w == null:
			break
		target[best_w] = int(pool[best_j])
		used[best_j] = true
	var total := 0.0
	for w in users:
		total += _tool_score(w, slot, int(target.get(w, -1)))
	return {"target": target, "total": total, "users": users}


## 倉庫の道具を、総合点がいちばん高くなるように仲間へ持たせる（自動）。持っていた古い道具は倉庫に戻り、次の仲間へ回る。
## 割り当てが「いまより TOOL_MIN_GAIN 以上」よくなるときだけ持たせ替える（行ったり来たりを防ぐ）。
func manage_tools() -> void:
	if not tool_auto:
		return
	for slot in GatherDB.SLOTS:
		var a: Dictionary = _assign_tools(slot)
		var cur_total := 0.0
		for w in a["users"]:
			cur_total += _tool_score(w, slot, int(w.tools.get(slot, -1)))
		if float(a["total"]) - cur_total <= GatherDB.TOOL_MIN_GAIN:
			continue
		var changing: Array = []
		for w in a["users"]:
			if int(a["target"].get(w, -1)) != int(w.tools.get(slot, -1)):
				changing.append(w)
		for w in changing:                               # まず古い道具を倉庫へ戻し、そこから新しい道具を取る
			unequip_tool(w, slot)
		for w in changing:
			var t: int = int(a["target"].get(w, -1))
			if t >= 0:
				equip_tool(w, t)


## 自動割り当ても使う窓口。自動ONや遠征・行動不能による手動操作の制限はUI側で扱う。
func _tool_target_reason(w) -> String:
	if not is_instance_valid(w) or not (w is Worker) or not workers.has(w) or w.is_queued_for_deletion():
		return "この仲間の装備は変更できません。"
	if not is_instance_valid(storage):
		return "倉庫を利用できません。"
	return ""


## 道具を1個戻せるか。交換時は、先に倉庫から取り出す道具の重さも差し引く。
## 現在の採取道具は積載対象外。将来対象になっても、返却できない変更は先に断る。
func _tool_return_fits(item: int, outgoing := -1) -> bool:
	if item < 0 or not storage.enforce or CargoDB.bay_of(item) < 0:
		return true
	var after := storage.current_weight() + CargoDB.size_of(item)
	if outgoing >= 0 and CargoDB.bay_of(outgoing) >= 0:
		after -= CargoDB.size_of(outgoing)
	return after <= storage.max_weight()


## 持たせられない理由。可能なら空。現在と同じ道具は在庫を使わない。
func tool_equip_reason(w, item: int) -> String:
	var reason := _tool_target_reason(w)
	if not reason.is_empty():
		return reason
	if not GatherDB.is_tool_item(item):
		return "採取道具を選んでください。"
	var old: int = int(w.tools.get(GatherDB.slot_of_tool(item), -1))
	if old == item:
		return ""
	if storage.count_of(item) <= 0:
		return "倉庫にこの道具がありません。"
	if not _tool_return_fits(old, item):
		return "倉庫の積載量が足りず、今の道具を戻せません。"
	return ""


## 外せない理由。可能なら空。素手の枠を外す操作は何も変えない。
func tool_unequip_reason(w, slot: String) -> String:
	var reason := _tool_target_reason(w)
	if not reason.is_empty():
		return reason
	if not GatherDB.SLOTS.has(slot):
		return "採取道具の枠を選んでください。"
	if not _tool_return_fits(int(w.tools.get(slot, -1))):
		return "倉庫の積載量が足りず、道具を戻せません。"
	return ""


## 事前確認後、数量と装備を一緒に確定してから通知する。途中の状態や廃棄を発生させない。
func _change_tool(w, slot: String, item: int) -> void:
	var old: int = int(w.tools.get(slot, -1))
	var inv: Inventory = storage.inventory
	if item >= 0:
		inv.counts[item] = inv.count(item) - 1
		w.tools[slot] = item
	else:
		w.tools.erase(slot)
	if old >= 0:
		inv.counts[old] = inv.count(old) + 1
		inv.item_added.emit(old, 1, Inventory.SOURCE_TRANSFER)
	inv.changed.emit()


## 倉庫の道具を仲間に持たせる。旧道具を戻せない場合は、在庫も装備も変えない。
func equip_tool(w, item: int) -> bool:
	if not tool_equip_reason(w, item).is_empty():
		return false
	var slot := GatherDB.slot_of_tool(item)
	if int(w.tools.get(slot, -1)) != item:
		_change_tool(w, slot, item)
	return true


## 指定した枠だけを外して倉庫に戻す。もう一方の道具はそのまま。
func unequip_tool(w, slot: String) -> bool:
	if not tool_unequip_reason(w, slot).is_empty():
		return false
	if int(w.tools.get(slot, -1)) >= 0:
		_change_tool(w, slot, -1)
	return true


## その道具を作る意味があるか（もう1つ増えると、全員の総合点が上がり、予備も作りかけもない）。加工の選択（choose_recipe）で使う。
## 武器は手動1枠。遠征中・戦闘不能は変更しない。自動採取道具とは独立。
func weapon_change_reason(w, equip: bool) -> String:
	var reason := _tool_target_reason(w)
	if not reason.is_empty(): return reason
	if game_over: return "ゲーム終了中は変更できません。"
	if w.away: return "遠征中は武器を変更できません。"
	if w.down: return "戦闘不能の間は武器を保持します。"
	if equip:
		if w.weapon >= 0: return "すでに武器を装備しています。"
		if storage.count_of(GameData.Item.SIMPLE_SPEAR) < 1: return "倉庫に簡易槍がありません。"
	elif w.weapon < 0:
		return "武器を装備していません。"
	return ""


func equip_weapon(w) -> bool:
	if not weapon_change_reason(w, true).is_empty(): return false
	var inv: Inventory = storage.inventory
	# 装備と在庫を同時に移す。重量はその前後で不変。
	inv.counts[GameData.Item.SIMPLE_SPEAR] = inv.count(GameData.Item.SIMPLE_SPEAR) - 1
	w.weapon = GameData.Item.SIMPLE_SPEAR
	inv.changed.emit()
	return true


func unequip_weapon(w) -> bool:
	if not weapon_change_reason(w, false).is_empty(): return false
	var item: int = w.weapon
	var inv: Inventory = storage.inventory
	w.weapon = -1
	# 装備重量を既に計上しているので、満載でも同じ重量の倉庫へ戻せる。
	inv.counts[item] = inv.count(item) + 1
	inv.item_added.emit(item, 1, Inventory.SOURCE_TRANSFER)
	inv.changed.emit()
	return true


func work_support_change_reason(w, equip: bool, item := GameData.Item.HAUL_FRAME) -> String:
	if item not in GameData.SUPPORT_ITEMS: return "仕事補助ではありません。"
	var reason := _tool_target_reason(w)
	if not reason.is_empty(): return reason
	if game_over: return "ゲーム終了中は変更できません。"
	if w.away: return "遠征中は仕事補助を変更できません。"
	if w.down: return "戦闘不能の間は仕事補助を保持します。"
	if equip:
		if w.work_support >= 0: return "すでに仕事補助を装備しています。"
		if storage.count_of(item) - _queued_transfer(item, "to_workshop") < 1: return "倉庫に%sがありません。" % ItemDB.name_of(item)
	elif w.work_support < 0:
		return "仕事補助を装備していません。"
	return ""


func equip_work_support(w, item := GameData.Item.HAUL_FRAME) -> bool:
	if not work_support_change_reason(w, true, item).is_empty(): return false
	var inv: Inventory = storage.inventory
	# 装備と在庫を同時に移す。重量はその前後で不変。
	inv.counts[item] = inv.count(item) - 1
	w.work_support = item
	inv.changed.emit()
	return true


func unequip_work_support(w) -> bool:
	if not work_support_change_reason(w, false).is_empty(): return false
	var item: int = w.work_support
	var inv: Inventory = storage.inventory
	w.work_support = -1
	# 装備重量を既に計上しているので、満載でも同じ重量の倉庫へ戻せる。
	inv.counts[item] = inv.count(item) + 1
	inv.item_added.emit(item, 1, Inventory.SOURCE_TRANSFER)
	inv.changed.emit()
	return true


func tool_wanted(item: int) -> bool:
	if storage.count_of(item) + processor.pending_of(item) > 0:
		return false
	var slot := GatherDB.slot_of_tool(item)
	var without: Dictionary = _assign_tools(slot)
	var with_it: Dictionary = _assign_tools(slot, [item])
	return float(with_it["total"]) - float(without["total"]) > GatherDB.TOOL_MIN_GAIN


# ---------------------------------------------------------------- 建設・必要設備（data/facilities.gd）
## 流れ: プレイヤーが建設の画面で依頼 → build_queue（待ち）→ 材料と必要設備がそろうと、仲間が材料を運んで作る
## （加工と同じ仕組み。choose_recipe が建設のレシピを最優先で返す）→ 完成すると設備が拠点にできる（finish_build）。
## 待っている間は、その材料を、ほかの加工に使わせない（取り置き）。
func has_facility(id: String) -> bool:
	return base.has_facility(id)


## 設備を建てる依頼の数（待ち ＋ 運搬中・作業中）。建てすぎないための計算に使う。
func build_pending(id: String) -> int:
	return build_queue.count(id) + processor.pending_build(id)


## その設備の必要設備がそろっているか（建てられる状態か）
func facility_unlocked(id: String) -> bool:
	return storage.count_of(FacilityDB.packed_item_of(id)) > 0 or has_facility(FacilityDB.def(id)["requires"])


## 建設の依頼を出せない理由（出せるなら ""）
func build_blocked_reason(id: String) -> String:
	var d: Dictionary = FacilityDB.def(id)
	if base.room_slot(d["room"]) == "":
		return "%sが必要" % Rooms.TYPES[d["room"]]["name"]              # 設備は部屋の中に建てる（data/facilities.gd の "room"）
	if not facility_unlocked(id):
		return "%sが必要" % FacilityDB.name_of(d["requires"])
	if base.facility_count(id) >= int(d["max"]):
		return "完成"
	if base.facility_count(id) + build_pending(id) >= int(d["max"]):
		return "建設の依頼中"
	return ""


## 建設を依頼する。出せたら true。
func request_build(id: String) -> bool:
	if build_blocked_reason(id) != "":
		return false
	build_queue.append(id)
	return true


## 待ちの建設の依頼を1つ取り消す（材料を取りに向かった後は取り消せない）
func cancel_build(id: String) -> bool:
	var i := build_queue.rfind(id)
	if i < 0:
		return false
	build_queue.remove_at(i)
	return true


## 依頼を仲間が引き受けた（材料を取りに向かう）。待ちから外す。
func claim_build(id: String) -> void:
	var i := build_queue.find(id)
	if i >= 0:
		build_queue.remove_at(i)


## 運搬をやめた（Processor.cancel_reservation）。依頼を待ちの先頭に戻す。
func requeue_build(id: String) -> void:
	build_queue.push_front(id)


## 建設が終わった（Processor.work）。設備が拠点にできて、必要設備にしていた製作物・設備が作れるようになる。
func finish_build(id: String) -> void:
	if base.add_facility(id) < 0:
		return
	total_built += 1
	var bonus := int(FacilityDB.def(id).get("capacity_bonus", 0))
	if bonus > 0:
		storage.capacity_bonus += bonus                    # 荷台の増設など。積載できる最大の重さが増える（data/cargo.gd）
	director.note("%sができた" % FacilityDB.name_of(id))


## 材料と必要設備がそろっていて、いま始められる建設のレシピ（なければ空）。待ちの先頭から順に。
## 製作物があれば設置、なければ同じ製作レシピで1個ずつ準備する。
## 製作中に設置を取り消しても、完成品は倉庫へ残る。
func packed_in_transit(item: int) -> int:
	var n: int = processor.pending_of(item) + workshop_count(item)
	for w in workers:
		if w.carrying == item: n += w.carry_n
	return n


func build_cost(id: String) -> Dictionary:
	var d: Dictionary = FacilityDB.def(id)
	var item: int = FacilityDB.packed_item_of(id)
	if item >= 0 and storage.count_of(item) > 0:
		return {item: 1}
	return d["cost"]


func _next_build_recipe() -> Dictionary:
	for id in build_queue:
		var d: Dictionary = FacilityDB.def(id)
		var item: int = FacilityDB.packed_item_of(id)
		if item >= 0 and storage.count_of(item) > 0:
			return FacilityDB.installation_recipe(id)
		if not has_facility(d["requires"]): continue
		if item >= 0 and packed_in_transit(item) > 0: continue
		if d.has("pack_recipe"):
			var r := GameData.recipe_by_id(d["pack_recipe"])
			if storage.has_set(r["in"]):
				var unit:=r.duplicate(true)
				unit["build_request"]=true
				return unit
		elif storage.has_set(d["cost"]):
			return FacilityDB.recipe_of(id)
	return {}


func facility_pack_reason(id: String, slot: int) -> String:
	return FacilityPacking.reason(self,id,slot)

func facility_pack_request(id: String, slot: int) -> Dictionary:
	_pack_ticket.clear()
	if facility_pack_reason(id,slot)!="": return {}
	_pack_nonce+=1
	_pack_ticket=FacilityPacking.measure(self,id,slot)
	_pack_ticket["nonce"]=_pack_nonce
	return _pack_ticket.duplicate(true)

func cancel_facility_pack() -> void:
	_pack_ticket.clear()

func pack_facility(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or snapshot!=_pack_ticket: return false
	_pack_ticket.clear() # 失敗時も再確認。連打は一度だけ。
	var expected:=snapshot.duplicate(true); expected.erase("nonce")
	if facility_pack_reason(snapshot.id,snapshot.slot)!="" or FacilityPacking.measure(self,snapshot.id,snapshot.slot)!=expected: return false
	base.built[snapshot.id].erase(snapshot.slot)
	base.built_at.erase("%s:%d" % [snapshot.id,snapshot.slot])
	if snapshot.id=="bed": base.beds[snapshot.slot]=null
	storage.capacity_bonus-=int(FacilityDB.def(snapshot.id).get("capacity_bonus",0))
	storage.store_owned(snapshot.item,1)
	base.queue_redraw()
	director.note("%sを撤去し完成品1個を倉庫へ戻した" % FacilityDB.name_of(snapshot.id))
	return true


## 引受け済み・未搬出の建設材料だけを保護する。未着手の不足注文は取り置かない。
func reserved_for_builds() -> Dictionary:
	var need := {}
	var costs: Array = []
	# 未着手の建設は材料一式がそろうまで予約しない。
	for w in workers:
		if w.ai.state == CharacterAI.State.HAUL_TAKE and w.ai.haul_recipe.has("build"):
			costs.append(w.ai.haul_recipe["in"])                 # まだ倉庫にあって、これから取りに行く材料
	for c in costs:
		for it in c:
			need[it] = int(need.get(it, 0)) + int(c[it])
	var res := {}
	for it in need:
		res[it] = mini(int(need[it]), storage.count_of(it))
	return res


## 鉄を使う建設の取り置きで、その鉄を採る最初の道具まで塞がない。
## 既に誰かが採れる、または有効な道具が倉庫/加工中にあれば例外は終わる。
func build_needs_gather_tool(item: int, own_incoming: Dictionary = {}) -> bool:
	if item not in [GameData.Item.WOOD_PICK, GameData.Item.HAMMER] or not _builds_need_iron(): return false
	var kind := "rock" if item == GameData.Item.WOOD_PICK else "vein"
	for w in workers:
		if not _uses_tools(w): continue
		if float(w.gather_eval(kind)["eff"]) >= GatherDB.MIN_EFF: return false
		for tool in GameData.TOOL_ITEMS:
			if GatherDB.slot_of_tool(tool) != GatherDB.slot_of_point(kind): continue
			var pending: int = processor.pending_of(tool)
			# 搬出直前の再確認では、自分の未搬出予約を完成予定の別道具と数えない。
			if own_incoming.get("out",-1) == tool and processor.incoming.has(own_incoming): pending -= int(own_incoming.get("n",1))
			if storage.count_of(tool) + pending <= 0: continue
			if float(GatherDB.evaluate(kind,tool,w.ranks.get(GameData.Field.GATHERER,0),w.field_mult(GameData.Field.GATHERER))["eff"]) >= GatherDB.MIN_EFF: return false
	return true


## 建設の取り置きを避けて、レシピ r の材料が取れるか。燃料の在庫が0でタンクも尽きかけているときだけは、
## 拠点が止まらないよう、取り置きに構わず燃料を作る（薪＝木材は建設の材料と重なるため）。
func _spares_for(r: Dictionary, reserved: Dictionary) -> bool:
	if build_needs_gather_tool(int(r["out"])):
		return true
	if reserved.is_empty():
		return true
	if r["out"] == GameData.Item.FUEL and storage.count_of(GameData.Item.FUEL) == 0 and base.fuel < 30.0:
		return true
	for it in r["in"]:
		if storage.count_of(it) - int(reserved.get(it, 0)) < int(r["in"][it]):
			return false
	return true


## 建設の依頼の材料で、まだ足りない物か（回収の優先度を上げる）。鉄は鉄鉱石を精錬して作るので、鉄鉱石が1個もないときに足りない扱い。
func build_short_of(item: int) -> bool:
	if build_queue.is_empty():
		return false
	if item == GameData.Item.IRON_ORE:
		return _builds_need_iron() and storage.count_of(GameData.Item.IRON_ORE) == 0
	var need := 0
	for id in build_queue:
		need += int(FacilityDB.def(id)["cost"].get(item, 0))
	return need > storage.count_of(item)


## 建設の依頼の材料に鉄があり、倉庫と加工中の鉄を足しても足りないか（あれば精錬を優先する。道具の場合と同じ理由）
func _builds_need_iron() -> bool:
	var need := 0
	for id in build_queue:
		need += int(FacilityDB.def(id)["cost"].get(GameData.Item.IRON, 0))
	return need > storage.count_of(GameData.Item.IRON) + processor.pending_of(GameData.Item.IRON)


# ---------------------------------------------------------------- 部屋の変更（車体の区画。data/rooms.gd）
## 部屋の変更 = 車体の区画そのものを、どの部屋にするか（空き → 建てる → 別の部屋へ建て替える）。
## 建設（設備を部屋の中に足す）とは別のシステム。仲間の作業は要らず、プレイヤーが決めた瞬間に、倉庫の材料を使って建て替わる。
## 加工室・倉庫は移すと加工設備・倉庫が新しい区画へ移り、寝室は移すとベッドも一緒に動く。
## 拠点レベルは未実装（範囲外）なので、部屋の解放条件の判定には常に Lv1 を渡す（Lv2 が要る訓練室は建てられない）。
func base_level() -> int:
	return 1


## 応急修理板を1個即時使用。予約済み部位はAIに任せ、別の損傷部位を選ぶ。
func emergency_repair_target() -> int:
	if game_over: return -1
	var target := -1
	var low := 100.0
	for p in base.parts:
		if not base.repair_reserved.has(p) and float(base.parts[p]) < low:
			low = float(base.parts[p])
			target = p
	return target


func emergency_repair() -> bool:
	var target := emergency_repair_target()
	if target < 0 or not storage.take_item(GameData.Item.REPAIR_KIT): return false
	base.repair(target)
	director.note("応急修理板: %sの耐久+%d（上限100）。燃料や仲間HPは回復しない" % [GameData.PART_NAMES[target], GameData.REPAIR_AMOUNT])
	return true


## 部屋と設備の効果の合計（休憩の回復・元気の消耗など。Worker（CrewStatus）が読む）。設備の効果は data/facilities.gd の
## "effects"（部屋の効果と同じ kind・形。例: 物資庫の drain_cut）。元気の消耗を減らす分は、部屋＋設備の合計に上限をかける。
func repair_order_info() -> Dictionary:
	var assigned = null
	for w in workers:
		if is_instance_valid(w) and w.ai.manual_job == GameData.Job.REPAIR:
			assigned = w
			break
	var part := base.part_to_repair()
	var required := 1 if part >= 0 else 0
	var available := storage.count_of(GameData.Item.REPAIR_KIT)
	return {"part": part, "required": required, "available": available,
		"missing": maxi(0, required - available), "assigned": assigned}


func request_repair(worker = null) -> bool:
	var info := repair_order_info()
	if int(info["part"]) < 0 or int(info["missing"]) > 0 or info["assigned"] != null:
		return false
	var chosen = worker
	if chosen == null:
		var best_score := -INF
		for candidate in workers:
			if not is_instance_valid(candidate) or not candidate.ai.manual_repair_reason().is_empty():
				continue
			var score: float = candidate.skill_mult(GameData.Job.REPAIR) + float(candidate.priorities.get(GameData.Job.REPAIR, 0)) * 0.01
			if score > best_score:
				best_score = score
				chosen = candidate
	if chosen == null or not is_instance_valid(chosen) or not chosen.ai.request_manual_repair():
		return false
	director.note("修理依頼: %sが%sの修理に向かう" % [chosen.char_name, GameData.PART_NAMES[int(info["part"])]] )
	return true


func room_effect(kind: String) -> float:
	var v := Rooms.total(room_layout, kind) + facility_effect(kind)
	return minf(v, Rooms.CAP_DRAIN_CUT) if kind == "drain_cut" else v


## 建てた設備の効果の合計（同じ設備を複数建てていれば、建てた数ぶん重なる。data/facilities.gd の "effects"）。
func facility_effect(kind: String) -> float:
	var sum := 0.0
	for id in FacilityDB.ids():
		var n := base.facility_count(id)
		if n <= 0:
			continue
		for e in FacilityDB.def(id).get("effects", []):
			if e["kind"] == kind:
				sum += float(e["value"]) * n
	return sum


## 区画 slot に部屋 rtype を建てられない理由（材料の不足は含めない）。建てられるなら ""。
func room_block_reason(slot: String, rtype: String) -> String:
	return Rooms.block_reason(room_layout, slot, rtype, base_level())


func can_build_room(slot: String, rtype: String) -> bool:
	return room_block_reason(slot, rtype) == "" and storage.has_set(Rooms.TYPES[rtype]["cost"])


## 区画 slot を rtype にする（空き部屋にして壊す・建てる・建て替える・移設する）。材料は倉庫から使う。できたら true。
func build_room(slot: String, rtype: String) -> bool:
	if not can_build_room(slot, rtype):
		return false
	var cost: Dictionary = Rooms.TYPES[rtype]["cost"]
	if not storage.take_set(cost):
		return false
	var before: String = room_layout.get(slot, "empty")
	var moved_from := ""
	if Rooms.is_relocation(room_layout, slot, rtype):
		moved_from = Rooms.slot_of(room_layout, rtype)
	var bed_slot_before: String = base.room_slot("bedroom")
	room_layout = Rooms.with_room(room_layout, slot, rtype)
	var now := Time.get_ticks_msec()
	base.room_built_at[slot] = now
	if moved_from != "":
		base.room_built_at[moved_from] = now
	base.apply_layout()                                    # 加工設備・倉庫を、新しい部屋の位置へ
	if base.room_slot("bedroom") != bed_slot_before:
		for w in workers:
			w.ai.on_bedroom_moved()                        # 眠っていた仲間は、新しいベッドへ歩き直す
	total_rooms_built += 1
	var slot_name: String = Rooms.SLOTS[slot]["name"]
	var rname: String = Rooms.TYPES[rtype]["name"]
	if rtype == "empty":
		director.note("%sの%sを壊して空き部屋にした" % [slot_name, Rooms.TYPES[before]["name"]])
	elif moved_from != "":
		director.note("%sを%sへ移した" % [rname, slot_name])
	else:
		director.note("%sに%sができた" % [slot_name, rname])
	return true


## 別の画面を開くとき、ほかの管理画面を閉じる（重ならないように）。keep はいま開く画面。
func close_other_panels(keep) -> void:
	for p in [navigation, build_ui, room_ui, policy, detail, expedition_ui, inventory_ui, craft_ui, crew_alerts, quarry_ui, save_ui, map_ui, town_ui]:
		if p != null and p != keep and p.has_method("close"):
			p.close()


## 倉庫に入りきらず捨てたとき（記録には、他の出来事を押し出さないよう、60秒に1回だけ出す）
func _on_overflow(item: int, amount: int) -> void:
	total_wasted += amount
	var now: float = director.elapsed
	if now - _waste_note_at >= 60.0:
		_waste_note_at = now
		director.note("倉庫がいっぱいで捨てた（%s）" % GameData.ITEM_NAMES[item])


## 加工の方針に従って、次に作るレシピを選ぶ（材料が揃っていて、作り置きが足りないもの）。
## ★が高いものから。同じ★なら、在庫の少ない加工品を優先する。
## プレイヤーが依頼した建設は、方針より先（材料と必要設備がそろっていれば）。必要設備（recipe の station）がまだない物は選ばない。
## 選ぶだけで何も変えない（建設の依頼を待ちから外すのは、仲間が引き受けたとき claim_build）。
func choose_recipe() -> Dictionary:
	var refill := ProductionPlan.refill(self, true)
	if not refill.is_empty(): return refill
	var build := _next_build_recipe()
	if not build.is_empty() and AutoCraftGuard.allows(self,build): return build
	for q in production_orders:
		var r := GameData.recipe_by_id(q.id)
		if ProductionPlan.ready(self,r):
			var unit := r.duplicate(true)
			unit.merge({"manual":true,"player_order":true,"batch":q.batch})
			return unit
	return ProductionPlan.refill(self, false)

var production_orders: Array = []
var refill_settings: Dictionary = ProductionPlan.defaults()
var procurement_goals: Dictionary = {}

func request_order(id: String, n: int) -> int:
	if GameData.recipe_by_id(id).is_empty() or n<=0 or n>999: return 0
	var e:=CraftDB.entry_of(id)
	if int(CraftDB.evaluate(e,self,n).max_qty)>=n: return request_craft(id,n)
	# 旧保存等で作業場に分散した未予約材料は、既存運搬で倉庫へ戻して合流する。
	for it in e["in"]:
		var missing:=maxi(0,int(e["in"][it])*n-AutoCraftGuard.available(self,it,null,true))
		if missing>0:request_transfer(it,mini(missing,workshop_available(it)),"to_storage")
	for q in production_orders:
		if q.id==id:
			var accepted:=mini(n,999-int(q.n))
			q.n+=accepted
			return accepted
	production_orders.append({"id":id,"n":n,"batch":n>1})
	return n

func restore_order(r: Dictionary) -> void:
	for q in production_orders:
		if q.id==r.id and int(q.n)<999:
			q.n+=1
			return
	production_orders.append({"id":r.id,"n":1,"batch":r.get("batch",false)})

func claim_order(id: String) -> void:
	for q in production_orders:
		if q.id==id:
			q.n-=1
			if q.n<=0: production_orders.erase(q)
			return

func set_procurement(item: int, target: int) -> void:
	if item not in ItemDB.ORDER:return
	if target<=0: procurement_goals.erase(item)
	else: procurement_goals[item]=clampi(target,1,999)

func procurement_available(item: int) -> int:
	return AutoCraftGuard.available(self,item)+workshop_available(item)

func procurement_transit(item: int) -> int:
	# 内部移送の待ちは元在庫の利用可能数から引かれているため、ここで一度だけ計上。
	var n:=_queued_transfer(item,"to_workshop")+_queued_transfer(item,"to_storage")
	for w in workers:
		if w.ai.state in [CharacterAI.State.GATHER,CharacterAI.State.MOVE_TO_STORAGE,CharacterAI.State.STORE] or w.ai.state==CharacterAI.State.XFER_MOVE:
			if w.carrying==item:n+=w.carry_n
			n+=int(w.carry_bonus.get(item,0))
			if w.carrying==GameData.Item.CARCASS:n+=int(w.carcass_cargo.get(item,0))
	return n

func update_procurement() -> void:
	for it in procurement_goals.keys():
		if procurement_available(it)>=int(procurement_goals[it]): procurement_goals.erase(it)



# ---------------------------------------------------------------- 出現
func _spawn_ground_resource() -> void:
	if GameData.ENABLE_GATHER_POINTS:
		# 木材・石・鉄鉱石は、落ちている物ではなく採取ポイント（岩場・鉱床・枯れ木）から採る
		var pt := GatherPoint.new()
		pt.setup(self, GatherDB.pick_kind())
		pt.position = Vector2(spawn_x(), randf_range(SPAWN_Y_MIN + 6.0, SPAWN_Y_MAX - 6.0))
		resources_root.add_child(pt)
		return
	var r := ResourceNode.new()
	r.game = self
	r.item = _random_ground_item()
	r.position = Vector2(spawn_x(), randf_range(SPAWN_Y_MIN, SPAWN_Y_MAX))
	resources_root.add_child(r)


func _random_ground_item() -> int:
	var total := 0.0
	for it in GameData.GROUND_WEIGHTS:
		total += GameData.GROUND_WEIGHTS[it]
	var pick := randf() * total
	for it in GameData.GROUND_WEIGHTS:
		pick -= GameData.GROUND_WEIGHTS[it]
		if pick <= 0.0:
			return it
	return GameData.Item.WOOD


func _spawn_creature() -> void:
	var total := 0.0
	for sp in GameData.CREATURES:
		total += GameData.CREATURES[sp]["weight"]
	var pick := randf() * total
	var species := "hare"
	for sp in GameData.CREATURES:
		pick -= GameData.CREATURES[sp]["weight"]
		if pick <= 0.0:
			species = sp
			break
	var c := Creature.new()
	c.setup(self, species)
	c.position = Vector2(spawn_x(), randf_range(SPAWN_Y_MIN + 20.0, SPAWN_Y_MAX - 10.0))
	creatures_root.add_child(c)


## 生物を倒すと、その場に「獲物」が残る（倉庫へ運ぶと解体されて素材になる）。
func on_creature_killed(c) -> void:
	total_hunted += 1
	var r := ResourceNode.new()
	r.game = self
	r.item = GameData.Item.CARCASS
	r.species = c.species
	r.position = c.position
	if world.depth_strip_active():
		r.position.y = world.clamp_outdoor_y(r.position.y)
	resources_root.add_child(r)
	last_carcass = r


## テスト用の購入（ショップや経済は第1段階では作らない）。獲物を倉庫で解体したのと同じ扱い。
func developer_mode() -> bool:
	return OS.get_cmdline_user_args().has("--developer-mode")


func test_purchase(species: String) -> void:
	if developer_mode() and GameData.CREATURES.has(species):
		storage.butcher(species, Inventory.SOURCE_PURCHASE)


func test_add_tool(item: int) -> void:
	if developer_mode() and item in GameData.TOOL_ITEMS:
		storage.add_item(item, 1, Inventory.SOURCE_PURCHASE)
		manage_tools()


# ---------------------------------------------------------------- 戦闘（現段階では未使用）
func _spawn_wave() -> void:
	wave += 1
	var n := mini(1 + int(wave / 2.0), 5)
	for i in n:
		var e := Enemy.new()
		e.setup(self, 36.0 + wave * 6.0)
		e.position = Vector2(spawn_x() + i * 70.0, randf_range(SPAWN_Y_MIN, SPAWN_Y_MAX))
		enemies_root.add_child(e)


## 敵を倒すと素材を落とす（流れる資源として拾える）。
func on_enemy_killed(e) -> void:
	kills += 1
	director.enemy_killed(e)           # 戦利品は敵の種類ごと（data/events.gd の ENEMIES）


func _spawn_resource_at(item: int, pos: Vector2) -> void:
	var r := ResourceNode.new()
	r.game = self
	r.item = item
	r.position = pos
	if world.depth_strip_active():
		r.position.y = world.clamp_outdoor_y(r.position.y)
	resources_root.call_deferred("add_child", r)


func _game_over() -> void:
	game_over = true
	_over_layer = CanvasLayer.new()
	_over_layer.layer = 50
	_over_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_over_layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_layer.add_child(bg)
	var l := GameData.make_label("拠点が動かなくなった…\n走行 %.1f km ・ 撃破 %d ・ 撃退 %d\n\n画面をクリックして再開・ニューゲーム" % [
			director.distance / 2500.0, kills, director.stats["repelled"]], 36)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_layer.add_child(l)
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			save_ui.open())
	get_tree().paused = true


# ---------------------------------------------------------------- 入力
func _select(w) -> void:
	for x in workers:
		x.selected = (x == w)
	if detail != null:
		detail.show_worker(w)
	follow_target = w                          # 世界クリック・管理画面の明示選択から、カメラ追従を切り替える


## クリックした世界座標から、選ぶ仲間を1人だけ決める（_unhandled_input から分離。world_step を渡さず world 座標だけで決まるので、
## ヘッドレスの自己診断からも呼べる＝実際のマウス移動に頼らずに確認できる）。
func _pick_worker_at(click_world: Vector2):
	var best = null
	var best_d := INF
	for w in workers:
		if w.away or not w.visible:                    # 遠征中・拠点の中で見えない（外装表示）仲間は、見えている絵だけを選べるように対象から外す
			continue
		var local: Vector2 = click_world - w.position   # 絵の範囲（足元が原点。幅±32px・上に64px。scripts/character.gd の描画と同じ大きさ）
		if local.x < -32.0 or local.x > 32.0 or local.y < -64.0 or local.y > 6.0:
			continue                                    # 頭の上や胴体をクリックしても外れてしまっていたのを直した
		var d: float = w.position.distance_to(click_world)   # 絵の範囲内で重なっていれば、足元が近いほうを選ぶ
		if d < best_d:
			best_d = d
			best = w
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and not game_over:
		var attack_world: Vector2 = get_canvas_transform().affine_inverse() * event.position
		if is_instance_valid(follow_target):
			for e in enemies_root.get_children():
				if e.visible and e.hit_test(attack_world):
					follow_target.ai.order_attack(e)
					get_viewport().set_input_as_handled()
					return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Use this event's screen coordinate instead of the OS cursor.  This is
		# camera-aware and permits a real Viewport-input regression check.
		var best = _pick_worker_at(get_canvas_transform().affine_inverse() * event.position)
		if best != null:
			_select(best)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			target_speed = minf(target_speed + 10.0, 200.0)
		elif event.keycode == KEY_DOWN:
			target_speed = maxf(target_speed - 10.0, 0.0)
		elif event.keycode == KEY_ESCAPE:
			follow_target = null                # 追従の解除（選んだ仲間・優先度パネルの表示はそのまま。カメラだけ戻る）


## いまカメラに見えている世界座標の左端（カメラなし・position=0 のときは 0.0 で、これまでと同じ）。
## 背景の描画（world_scroll.gd）・資源や生物の出現位置・消える境界が、カメラの動きに合わせて正しくなるように、ここを共通の窓口にする。
func camera_left() -> float:
	return camera.position.x if camera != null else 0.0


## 画面の右端より少し外側（これまでの SPAWN_X と同じ余白）の、いまカメラから見た世界座標。ここに資源・生物・敵を出現させる。
func spawn_x() -> float:
	return camera_left() + SPAWN_X


## カメラ追従の更新（世界側だけを動かす。仲間の位置・AI・仕事には一切触れない）。
## 対象が居ない・遠征中・拠点の中で見えない（外装表示）ときは、無効な位置へ飛ばず、その場で止めて表示だけ変える。
func _update_camera(_delta: float) -> void:
	var target = follow_target
	var followable: bool = target != null and is_instance_valid(target) and not target.away and target.visible
	if followable:
		# 対象が画面中央付近（デッドゾーン）にいる間はカメラを動かさない。外れたら、必要な分だけ追いつく（常に中央固定にはしない）
		var lo: float = target.position.x - (FOLLOW_SCREEN_CENTER_X + FOLLOW_DEADZONE_HALF)
		var hi: float = target.position.x - (FOLLOW_SCREEN_CENTER_X - FOLLOW_DEADZONE_HALF)
		camera.position.x = clampf(camera.position.x, lo, hi)
		_follow_label.text = "◎ %s を追従中（Escキーで解除）" % target.char_name
	else:
		camera.position.x = GameData.HULL_POS.x # 通常の、拠点を見渡す構図に戻る
		if target == null:
			_follow_label.text = ""
		else:
			_follow_label.text = "△ %s を追従できません（%s）" % [target.char_name, "遠征中" if target.away else "拠点の中（外装表示）"]
