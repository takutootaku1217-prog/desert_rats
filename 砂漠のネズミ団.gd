extends Node2D
## ゲーム全体の入口。背景・拠点・仲間・資源と生物の出現・拠点の維持・UIを組み立てる。
##
## 第1段階のループ:
##   移動 → 生物・資源が現れる → 狩猟・採取 → 倉庫へ（獲物は解体）→ 加工（食料・燃料・鉄・修理資材）
##   → 消費（仲間が食べる・移動と炉で燃料・時間と移動と加工で傷む）→ 補給・修理で維持 → 移動

var target_speed := 60.0          # プレイヤーが決める目標速度（↑↓キー）
var scroll_speed := 60.0          # 実際の速度。燃料切れ・走行装置の故障で遅くなる
var storage: BaseStorage
var processor: BaseProcessor
var base: MobileBase
var resources_root: Node2D
var creatures_root: Node2D
var enemies_root: Node2D
var workers: Array = []
var blueprints := {}              # 入手した設計図（id -> true）。入手の仕組みは今後
var ui: WorkPriorityUI
var detail: CrewDetailUI
var policy: PolicyUI
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

# ---- 部屋（車体の区画。data/rooms.gd） ----
var room_layout: Dictionary = Rooms.default_layout()   # 区画 -> 部屋の種類。初期配置は、これまでのゲームと同じ
var total_rooms_built := 0                              # 部屋を建てた・移した・空けた回数（確認用）

# ---- プレイヤーの方針（運営の方針画面で変更する） ----
var recipe_priority := GameData.DEFAULT_RECIPE_PRIORITY.duplicate()   # レシピid -> ★0〜5
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
	randomize()
	director = Director.new()       # 出来事（base や仲間より先に作る。倍率を読まれるため）
	director.setup(self)
	expedition = Expedition.new()
	expedition.setup(self)
	var bg := WorldScroll.new()
	bg.game = self
	add_child(bg)

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
	storage.add_item(GameData.Item.HAMMER, 1)      # 採取の道具の初期セット（あとは加工で作る）
	storage.add_item(GameData.Item.AXE, 1)
	if not FacilityDB.start_all:                   # 設備なしで始めるとき: 最初のワークベンチに要る鉄（data/facilities.gd）
		for it in FacilityDB.START_STOCK:
			storage.add_item(it, FacilityDB.START_STOCK[it])

	resources_root = Node2D.new()
	resources_root.name = "Resources"
	add_child(resources_root)

	creatures_root = Node2D.new()
	creatures_root.name = "Creatures"
	add_child(creatures_root)

	enemies_root = Node2D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	var workers_root := Node2D.new()
	workers_root.name = "Workers"
	add_child(workers_root)
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
	ui.worker_selected.connect(_select)
	status = StatusPanel.new()
	status.game = self
	add_child(status)
	detail = CrewDetailUI.new()
	detail.game = self
	add_child(detail)
	policy = PolicyUI.new()
	policy.game = self
	add_child(policy)
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


func _process(delta: float) -> void:
	if game_over:
		return
	if GameData.ENABLE_COMBAT and base.hp <= 0.0:
		_game_over()
		return
	if GameData.ENABLE_RAIDS and base.parts[GameData.Part.HULL] <= 0.0:
		_game_over()                   # 車体が壊れきった（襲撃・嵐・放置）
		return
	if GameData.ENABLE_COMBAT:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_spawn_wave()
			_wave_timer = 22.0
	# 移動: 燃料切れや走行装置の故障で遅くなる（完全には止めない。止まると資源が来なくなるため）
	scroll_speed = minf(target_speed, base.speed_limit())
	if not base.has_fuel():
		scroll_speed = minf(scroll_speed, GameData.CRAWL_SPEED)
	scroll_speed *= director.speed_mult()      # 天候の対処方針（減速・停止）
	var dist := scroll_speed * delta
	base.burn(dist)
	base.wear_by(delta, dist)
	director.tick(delta, dist)                 # 出来事の進行（予報・発生・終了）
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
		can = storage.count_of(item) - _queued_transfer(item, "to_workshop")
	elif dir == "to_storage":
		can = mini(workshop_available(item), storage.free_for(item) - _queued_transfer(item, "to_storage"))
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
func begin_transfer_trip(item: int, dir: String) -> int:
	var t := _find_transfer(item, dir)
	if t.is_empty():
		return 0
	var src_inv: Inventory = storage.inventory if dir == "to_workshop" else processor.stock
	var got := src_inv.take_n(item, mini(int(t["n"]), CraftDB.TRANSFER_TRIP))
	t["n"] -= got
	if got == 0 or int(t["n"]) <= 0:
		transfer_queue.erase(t)
	return got


## 運搬の1回分が届いた（仲間が行き先に着いたとき）
func finish_transfer_trip(item: int, dir: String, n: int) -> void:
	if dir == "to_workshop":
		processor.stock.add(item, n, Inventory.SOURCE_TRANSFER)
	else:
		var stored := storage.add_item(item, n, Inventory.SOURCE_TRANSFER)
		if stored < n:
			processor.stock.add(item, n - stored, Inventory.SOURCE_TRANSFER)      # 倉庫に入りきらない分は、作業場に残す（捨てない）
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
		if q["id"] == id:
			q["n"] += give
			return give
	craft_queue.append({"id": id, "n": give})
	return give


## 待ちの制作を1つ取り消す（材料は作業場に残る）
func cancel_craft(index: int) -> void:
	if index >= 0 and index < craft_queue.size():
		craft_queue.remove_at(index)


## 手動の制作を、作業場の材料で加工設備の注文にする（材料がそろっていて、注文の空きがあるとき）
func _feed_crafts() -> void:
	while not craft_queue.is_empty() and processor.free_slots() > 0:
		var started := false
		for q in craft_queue:
			var r: Dictionary = GameData.recipe_by_id(q["id"])
			if r.is_empty():
				craft_queue.erase(q)
				started = true
				break
			if not has_facility(GameData.recipe_station(r)) or not processor.stock.has_set(r["in"]):
				continue
			processor.stock.take_set(r["in"])
			processor.receive_manual(r.duplicate())
			q["n"] -= 1
			if int(q["n"]) <= 0:
				craft_queue.erase(q)
			started = true
			break
		if not started:
			break

# ---------------------------------------------------------------- 積載量（data/cargo.gd）
## いま倉庫へ向かっている物の数（回収に向かっている・運んでいる）。空き枠から引いて、入りきらない無駄足を防ぐ。
func gather_room() -> Dictionary:
	var inflight := {}
	for r in resources_root.get_children():
		if r.claimed_by != null and r.item != GameData.Item.CARCASS:
			inflight[r.item] = inflight.get(r.item, 0) + r.reserved         # 採取ポイントは袋の大きさぶん
	for w in workers:
		if w.carrying >= 0 and w.carrying != GameData.Item.CARCASS \
				and w.ai.state in [CharacterAI.State.MOVE_TO_STORAGE, CharacterAI.State.STORE]:
			inflight[w.carrying] = inflight.get(w.carrying, 0) + w.carry_n
	return inflight


## 資源 r を回収してよいか（倉庫に置き場があるか）。inflight は gather_room() の結果。
func has_room_for(r, inflight: Dictionary) -> bool:
	if r.item == GameData.Item.CARCASS:
		return storage.drop_fit(r.species) >= CargoDB.MIN_DROP_FIT
	return storage.free_for(r.item) - int(inflight.get(r.item, 0)) > 0


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


## 倉庫の道具を仲間に持たせる。すでに同じ枠の道具を持っていれば、それは倉庫に戻る。
func equip_tool(w, item: int) -> bool:
	if not GatherDB.is_tool_item(item) or not storage.take_item(item):
		return false
	var slot := GatherDB.slot_of_tool(item)
	var old: int = int(w.tools.get(slot, -1))
	w.tools[slot] = item
	if old >= 0:
		storage.add_item(old)
	return true


## 持っている道具を外して倉庫に戻す。
func unequip_tool(w, slot: String) -> void:
	var old: int = int(w.tools.get(slot, -1))
	if old >= 0:
		w.tools.erase(slot)
		storage.add_item(old)


## その道具を作る意味があるか（もう1つ増えると、全員の総合点が上がり、予備も作りかけもない）。加工の選択（choose_recipe）で使う。
func tool_wanted(item: int) -> bool:
	if storage.count_of(item) + processor.pending_of(item) > 0:
		return false
	var slot := GatherDB.slot_of_tool(item)
	var without: Dictionary = _assign_tools(slot)
	var with_it: Dictionary = _assign_tools(slot, [item])
	return float(with_it["total"]) - float(without["total"]) > GatherDB.TOOL_MIN_GAIN


## 作る意味のある道具で、鉄が足りなくて作れない物があるか（あれば精錬を優先する。鉄は修理部品にもすぐ使われて溜まらないため）
func _tools_need_iron() -> bool:
	var iron_have: int = storage.count_of(GameData.Item.IRON) + processor.pending_of(GameData.Item.IRON)
	for r in GameData.RECIPES:
		if not (r["out"] in GameData.TOOL_ITEMS) or not r["in"].has(GameData.Item.IRON):
			continue
		if not has_facility(GameData.recipe_station(r)):
			continue                                                     # 必要設備がまだない道具は、鉄があっても作れない
		if recipe_priority.get(r["id"], 0) > 0 and iron_have < int(r["in"][GameData.Item.IRON]) and tool_wanted(r["out"]):
			return true
	return false


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
	return has_facility(FacilityDB.def(id)["requires"])


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
func _next_build_recipe() -> Dictionary:
	for id in build_queue:
		var d: Dictionary = FacilityDB.def(id)
		if has_facility(d["requires"]) and storage.has_set(d["cost"]):
			return FacilityDB.recipe_of(id)
	return {}


## 建設の依頼のために取っておく材料 {Item: 個数}（待ちの依頼と、材料を取りに向かっている依頼のぶん。倉庫にある量まで）。
## 取り置きがないと、材料が集まるそばから薪や修理部品に使われて、いつまでも建てられない。
func reserved_for_builds() -> Dictionary:
	var need := {}
	var costs: Array = []
	for id in build_queue:
		costs.append(FacilityDB.def(id)["cost"])
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


## 建設の取り置きを避けて、レシピ r の材料が取れるか。燃料の在庫が0でタンクも尽きかけているときだけは、
## 拠点が止まらないよう、取り置きに構わず燃料を作る（薪＝木材は建設の材料と重なるため）。
func _spares_for(r: Dictionary, reserved: Dictionary) -> bool:
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


## 部屋の効果の合計（休憩の回復・元気の消耗など。Worker が読む）。元気の消耗を減らす食堂は、上限まで。
func room_effect(kind: String) -> float:
	var v := Rooms.total(room_layout, kind)
	return minf(v, Rooms.CAP_DRAIN_CUT) if kind == "drain_cut" else v


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
	for p in [build_ui, room_ui, policy, detail, expedition_ui, inventory_ui, craft_ui]:
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
	var build := _next_build_recipe()
	if not build.is_empty():
		return build
	var reserved := reserved_for_builds()
	var best := {}
	var best_key := -1.0
	# 道具・建設に使う鉄が足りないときは精錬を優先する。ただし食料に余裕があるときだけ（調理が後回しになって空腹になるのを防ぐ）
	var smelt_boost := not hungry and storage.count_of(GameData.Item.FOOD) >= GameData.TOOL_IRON_FOOD_MIN \
			and (_builds_need_iron() or _tools_need_iron())
	for r in GameData.RECIPES:
		var pr: int = recipe_priority.get(r["id"], 0)
		if pr <= 0:
			continue
		if not has_facility(GameData.recipe_station(r)):
			continue                                                        # 必要設備（ワークベンチなど）がまだない
		if smelt_boost and r["id"] == "smelt":
			pr = maxi(pr, 4)
		if not storage.has_set(r["in"]) or not _spares_for(r, reserved):
			continue                                                        # 材料がない、または建設のために取ってある
		# 炉を使うレシピは、タンクの燃料に余裕があるときだけ（移動用の燃料を守る）
		if r["tank_fuel"] > 0.0 and base.fuel < 25.0:
			continue
		if r["out"] in GameData.TOOL_ITEMS and not tool_wanted(r["out"]):
			continue                                                        # 誰の道具の更新にもならない道具は作らない
		var have: int = storage.count_of(r["out"]) + processor.pending_of(r["out"])
		var room: int = storage.quota_of(r["out"])                          # 積載量の枠。作り置きの上限も枠を超えない
		var target: int = mini(GameData.STOCK_TARGET.get(r["out"], 5), room)
		if have >= target or have + int(r["n"]) > room:
			continue                                                        # 作り足りている、または置き場に入りきらない
		var key: float = pr * 10.0 + (1.0 - float(have) / float(target))
		if key > best_key:
			best_key = key
			best = r
	return best


# ---------------------------------------------------------------- 出現
func _spawn_ground_resource() -> void:
	if GameData.ENABLE_GATHER_POINTS:
		# 木材・石・鉄鉱石は、落ちている物ではなく採取ポイント（岩場・鉱床・枯れ木）から採る
		var pt := GatherPoint.new()
		pt.setup(self, GatherDB.pick_kind())
		pt.position = Vector2(SPAWN_X, randf_range(SPAWN_Y_MIN + 6.0, SPAWN_Y_MAX - 6.0))
		resources_root.add_child(pt)
		return
	var r := ResourceNode.new()
	r.game = self
	r.item = _random_ground_item()
	r.position = Vector2(SPAWN_X, randf_range(SPAWN_Y_MIN, SPAWN_Y_MAX))
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
	c.position = Vector2(SPAWN_X, randf_range(SPAWN_Y_MIN + 20.0, SPAWN_Y_MAX - 10.0))
	creatures_root.add_child(c)


## 生物を倒すと、その場に「獲物」が残る（倉庫へ運ぶと解体されて素材になる）。
func on_creature_killed(c) -> void:
	total_hunted += 1
	var r := ResourceNode.new()
	r.game = self
	r.item = GameData.Item.CARCASS
	r.species = c.species
	r.position = c.position
	resources_root.add_child(r)
	last_carcass = r


## テスト用の購入（ショップや経済は第1段階では作らない）。獲物を倉庫で解体したのと同じ扱い。
func test_purchase(species: String) -> void:
	storage.butcher(species, Inventory.SOURCE_PURCHASE)


# ---------------------------------------------------------------- 戦闘（現段階では未使用）
func _spawn_wave() -> void:
	wave += 1
	var n := mini(1 + int(wave / 2.0), 5)
	for i in n:
		var e := Enemy.new()
		e.setup(self, 36.0 + wave * 6.0)
		e.position = Vector2(SPAWN_X + i * 70.0, randf_range(SPAWN_Y_MIN, SPAWN_Y_MAX))
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
	var l := GameData.make_label("拠点が動かなくなった…\n走行 %.1f km ・ 撃破 %d ・ 撃退 %d\n\nクリックでやり直し" % [
			director.distance / 2500.0, kills, director.stats["repelled"]], 36)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_layer.add_child(l)
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			get_tree().paused = false
			get_tree().reload_current_scene())
	get_tree().paused = true


# ---------------------------------------------------------------- 入力
func _select(w) -> void:
	for x in workers:
		x.selected = (x == w)
	ui.set_selected(w)
	if detail != null:
		detail.show_worker(w)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best = null
		var best_d := 34.0
		for w in workers:
			var d: float = w.position.distance_to(event.position)
			if d < best_d:
				best_d = d
				best = w
		if best != null:
			_select(best)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			target_speed = minf(target_speed + 10.0, 200.0)
		elif event.keycode == KEY_DOWN:
			target_speed = maxf(target_speed - 10.0, 0.0)
