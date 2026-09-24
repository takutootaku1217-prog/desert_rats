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

# ---- プレイヤーの方針（運営の方針画面で変更する） ----
var recipe_priority := GameData.DEFAULT_RECIPE_PRIORITY.duplicate()   # レシピid -> ★0〜5
var gather_policy := {GameData.Item.WOOD: 3, GameData.Item.STONE: 3, GameData.Item.IRON_ORE: 3}  # ★0〜5
var hunt_policy := {"hare": true, "lizard": true, "hump": true}

# ---- 維持の状態 ----
var hungry := false               # 食料が尽きている
var _food_clock := 0.0

# ---- 確認用の累計 ----
var total_gathered := 0
var total_hunted := 0
var total_eaten := 0
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
	var bg := WorldScroll.new()
	bg.game = self
	add_child(bg)

	base = MobileBase.new()
	base.game = self
	add_child(base)
	storage = base.storage
	processor = base.processor
	# 最初の蓄え（すぐに詰まないよう、少しだけ持って出発する）
	storage.add_item(GameData.Item.FOOD, 8)
	storage.add_item(GameData.Item.FUEL, 2)
	storage.add_item(GameData.Item.REPAIR_KIT, 2)

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
	_eat(delta)
	# 地面の資源と生物は、進んだ距離に応じて現れる（天候で出にくくなる）
	_spawn_dist -= dist * director.spawn_mult()
	if _spawn_dist <= 0.0:
		_spawn_ground_resource()
		_spawn_dist = randf_range(GameData.SPAWN_DIST_MIN, GameData.SPAWN_DIST_MAX)
	_creature_dist -= dist * director.spawn_mult()
	if _creature_dist <= 0.0:
		_spawn_creature()
		_creature_dist = randf_range(GameData.CREATURE_DIST_MIN, GameData.CREATURE_DIST_MAX)


## 仲間は時間とともに倉庫の食料を食べる。食料が尽きると空腹になる。
func _eat(delta: float) -> void:
	_food_clock += delta * workers.size() * director.food_mult()
	while _food_clock >= GameData.FOOD_INTERVAL:
		_food_clock -= GameData.FOOD_INTERVAL
		if storage.take_item(GameData.Item.FOOD):
			total_eaten += 1
			hungry = false
		else:
			hungry = true
	if hungry and storage.count_of(GameData.Item.FOOD) > 0:
		# 食料が入ったらすぐ食べて空腹を解消する
		storage.take_item(GameData.Item.FOOD)
		total_eaten += 1
		hungry = false


# ---------------------------------------------------------------- 方針
## 回収の方針。獲物は常に拾う（★5相当）。
func gather_weight(item: int) -> float:
	if item == GameData.Item.CARCASS:
		return 5.0
	return float(gather_policy.get(item, 0))


func hunt_allowed(species: String) -> bool:
	return hunt_policy.get(species, false)


## 加工の方針に従って、次に作るレシピを選ぶ（材料が揃っていて、作り置きが足りないもの）。
## ★が高いものから。同じ★なら、在庫の少ない加工品を優先する。
func choose_recipe() -> Dictionary:
	var best := {}
	var best_key := -1.0
	for r in GameData.RECIPES:
		var pr: int = recipe_priority.get(r["id"], 0)
		if pr <= 0:
			continue
		if not storage.has_set(r["in"]):
			continue
		# 炉を使うレシピは、タンクの燃料に余裕があるときだけ（移動用の燃料を守る）
		if r["tank_fuel"] > 0.0 and base.fuel < 25.0:
			continue
		var have: int = storage.count_of(r["out"]) + processor.pending_of(r["out"])
		var target: int = GameData.STOCK_TARGET.get(r["out"], 5)
		if have >= target:
			continue
		var key: float = pr * 10.0 + (1.0 - float(have) / float(target))
		if key > best_key:
			best_key = key
			best = r
	return best


# ---------------------------------------------------------------- 出現
func _spawn_ground_resource() -> void:
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
