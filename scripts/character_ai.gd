class_name CharacterAI
extends RefCounted
## キャラクターの状態機械。
## SEARCH で「優先度の高い仕事から順に」できる仕事を探し、対応する状態列に入る。
##   狩猟: HUNT_MOVE -> HUNT_ATTACK -> (倒すと獲物) MOVE_TO_RESOURCE -> GATHER -> MOVE_TO_STORAGE -> STORE(解体)
##   採取: NOTICE -> MOVE_TO_RESOURCE -> GATHER -> MOVE_TO_STORAGE -> STORE
##   運搬: 燃料補給 REFUEL_TAKE -> REFUEL_MOVE -> REFUEL
##         材料運び HAUL_TAKE(材料一式) -> HAUL_MOVE(加工設備へ)
##   加工: MOVE_TO_MACHINE -> PROCESS -> MOVE_TO_STORAGE -> STORE
##   修理: REPAIR_TAKE(修理資材) -> REPAIR_MOVE -> REPAIR
## 新しい仕事は _try_start() に分岐を足し、状態を増やすだけで拡張できる。

enum State {
	IDLE, SEARCH, NOTICE, MOVE_TO_RESOURCE, GATHER, MOVE_TO_STORAGE, STORE,
	HAUL_TAKE, HAUL_MOVE, MOVE_TO_MACHINE, PROCESS,
	COMBAT_MOVE, COMBAT, REPAIR_TAKE, REPAIR_MOVE, REPAIR,
	REST_MOVE, REST,
	REFUEL_TAKE, REFUEL_MOVE, REFUEL,
	HUNT_MOVE, HUNT_ATTACK,
}

const STATE_TEXT := {
	State.IDLE: "待機中",
	State.SEARCH: "探し中…",
	State.NOTICE: "資源を発見！",
	State.MOVE_TO_RESOURCE: "資源へ移動",
	State.GATHER: "採取中",
	State.MOVE_TO_STORAGE: "倉庫へ運搬",
	State.STORE: "収納中",
	State.HAUL_TAKE: "材料を取りに行く",
	State.HAUL_MOVE: "加工設備へ運搬",
	State.MOVE_TO_MACHINE: "加工設備へ移動",
	State.PROCESS: "加工中",
	State.COMBAT_MOVE: "敵へ向かう",
	State.COMBAT: "攻撃中！",
	State.REPAIR_TAKE: "修理資材を取りに行く",
	State.REPAIR_MOVE: "修理へ向かう",
	State.REPAIR: "修理中",
	State.REST_MOVE: "ベッドへ向かう",
	State.REST: "休憩中",
	State.REFUEL_TAKE: "燃料を取りに行く",
	State.REFUEL_MOVE: "機関室へ運搬",
	State.REFUEL: "燃料を補給中",
	State.HUNT_MOVE: "獲物を追う",
	State.HUNT_ATTACK: "狩り中！",
}

var ch      # Worker
var game    # Main
var state: int = State.IDLE
var timer := 0.0
var res = null          # 対象の ResourceNode
var haul_item := -1
var haul_recipe := {}   # 運搬中のレシピ
var repair_part := -1
var enemy = null        # 対象の Enemy（戦闘用・現段階では未使用）
var prey = null         # 狩りの対象の Creature
const ATTACK_DPS := 14.0
const HUNT_DPS := 16.0
const HUNT_REACH := 44.0
const REPAIR_TIME := 1.2
const REFUEL_TIME := 0.6
const REST_START_BELOW := 70.0    # 元気がこれ未満なら休憩に入れる
const REST_UNTIL := 98.0
const TIRED_BELOW := 25.0         # これ未満なら最優先で休憩する
var current_job := -1


func setup(worker, g) -> void:
	ch = worker
	game = g
	_set_state(State.SEARCH)


func status_text() -> String:
	return STATE_TEXT[state]


func _set_state(s: int) -> void:
	state = s
	ch.state_changed.emit()


func tick(delta: float) -> void:
	match state:
		State.IDLE:
			ch.move_to_target(delta)
			timer -= delta
			if timer <= 0.0:
				_set_state(State.SEARCH)
		State.SEARCH:
			_search()
		State.NOTICE:
			timer -= delta
			if not _res_valid():
				_release_task()
				_set_state(State.SEARCH)
			elif timer <= 0.0:
				_set_state(State.MOVE_TO_RESOURCE)
		State.MOVE_TO_RESOURCE:
			if not _res_valid():
				_release_task()
				_set_state(State.SEARCH)
				return
			ch.target = _res_target()
			if ch.move_to_target(delta):
				_set_state(State.GATHER)
		State.GATHER:
			if not _res_valid():
				_release_task()
				_set_state(State.SEARCH)
				return
			ch.target = _res_target()
			ch.move_to_target(delta)   # 流れる資源に付いていく
			ch.pose = "pick"
			res.gather_progress += delta * ch.skill_mult(GameData.Job.GATHER) * game.director.outdoor_mult()
			if res.gather_progress >= ResourceNode.GATHER_TIME:
				ch.carrying = res.item
				ch.carrying_species = res.species
				game.total_gathered += 1
				res.queue_free()
				res = null
				_go_storage()
		State.MOVE_TO_STORAGE:
			ch.target = game.storage.access_point() + ch.slot_offset
			if ch.move_to_target(delta):
				timer = 0.35
				_set_state(State.STORE)
		State.STORE:
			timer -= delta
			if timer <= 0.0:
				if ch.carrying == GameData.Item.CARCASS:
					game.storage.butcher(ch.carrying_species)       # 獲物は倉庫で解体
				else:
					game.storage.add_item(ch.carrying)
				ch.carrying = -1
				ch.carrying_species = ""
				_set_state(State.SEARCH)

		# ---- 狩猟 ----
		State.HUNT_MOVE:
			if not _prey_valid():
				_release_task()
				_set_state(State.SEARCH)
				return
			ch.target = _prey_target()
			ch.move_to_target(delta)
			if ch.position.distance_to(prey.position) <= HUNT_REACH:
				_set_state(State.HUNT_ATTACK)
		State.HUNT_ATTACK:
			if not _prey_valid():
				_release_task()
				_set_state(State.SEARCH)
				return
			ch.target = _prey_target()
			ch.move_to_target(delta)
			if ch.position.distance_to(prey.position) > HUNT_REACH + 16.0:
				_set_state(State.HUNT_MOVE)
				return
			ch.attacking = true
			var p = prey
			p.take_damage(HUNT_DPS * ch.skill_mult(GameData.Job.HUNT) * game.director.outdoor_mult() * delta)
			if p.dead:
				# 倒した獲物は、そのまま自分で拠点へ運ぶ
				prey = null
				res = game.last_carcass
				if _res_valid():
					res.claimed_by = ch
					_set_state(State.MOVE_TO_RESOURCE)
				else:
					res = null
					_set_state(State.SEARCH)

		# ---- 運搬: 材料を加工設備へ ----
		State.HAUL_TAKE:
			ch.target = game.storage.access_point() + ch.slot_offset
			if ch.move_to_target(delta):
				if game.storage.take_set(haul_recipe["in"]):
					ch.carrying = haul_recipe["in"].keys()[0]
					_set_state(State.HAUL_MOVE)
				else:
					game.processor.cancel_reservation(haul_recipe)
					haul_recipe = {}
					_set_state(State.SEARCH)
		State.HAUL_MOVE:
			ch.target = game.processor.access_point() + ch.slot_offset
			if ch.move_to_target(delta):
				game.processor.receive(haul_recipe)
				haul_recipe = {}
				ch.carrying = -1
				_set_state(State.SEARCH)

		# ---- 運搬: 燃料の補給 ----
		State.REFUEL_TAKE:
			ch.target = game.storage.access_point() + ch.slot_offset
			if ch.move_to_target(delta):
				if game.storage.take_item(haul_item):
					ch.carrying = haul_item
					_set_state(State.REFUEL_MOVE)
				else:
					game.base.refuel_reserved = false
					_set_state(State.SEARCH)
		State.REFUEL_MOVE:
			ch.target = game.base.engine_point() + ch.slot_offset
			if ch.move_to_target(delta):
				timer = REFUEL_TIME
				_set_state(State.REFUEL)
		State.REFUEL:
			timer -= delta
			ch.pose = "work"
			if timer <= 0.0:
				game.base.add_fuel(ch.carrying)
				game.base.refuel_reserved = false
				ch.carrying = -1
				_set_state(State.SEARCH)

		# ---- 加工 ----
		State.MOVE_TO_MACHINE:
			ch.target = game.processor.access_point() + ch.slot_offset
			if ch.move_to_target(delta):
				_set_state(State.PROCESS)
		State.PROCESS:
			var p: BaseProcessor = game.processor
			if not p.output.is_empty():
				ch.carrying = p.take_output()
				p.worker = null
				_go_storage()
			elif not p.current.is_empty() or (not p.orders.is_empty() and not p.only_blocked()):
				p.work(delta, func(f): return ch.field_mult(f))
				ch.pose = "work"
			else:
				p.worker = null
				_set_state(State.SEARCH)

		# ---- 修理 ----
		State.REPAIR_TAKE:
			ch.target = game.storage.access_point() + ch.slot_offset
			if ch.move_to_target(delta):
				if game.storage.take_item(GameData.Item.REPAIR_KIT):
					ch.carrying = GameData.Item.REPAIR_KIT
					_set_state(State.REPAIR_MOVE)
				else:
					game.base.repair_reserved.erase(repair_part)
					repair_part = -1
					_set_state(State.SEARCH)
		State.REPAIR_MOVE:
			ch.target = game.base.part_point(repair_part) + ch.slot_offset
			if ch.move_to_target(delta):
				timer = REPAIR_TIME
				_set_state(State.REPAIR)
		State.REPAIR:
			timer -= delta
			ch.pose = "work"
			if timer <= 0.0:
				game.base.repair(repair_part)
				repair_part = -1
				ch.carrying = -1
				_set_state(State.SEARCH)

		# ---- 戦闘（現段階では未使用） ----
		State.COMBAT_MOVE:
			if not _enemy_valid():
				_release_task()
				_set_state(State.SEARCH)
				return
			ch.target = enemy.position + Vector2(-30, 0)
			if ch.move_to_target(delta):
				_set_state(State.COMBAT)
		State.COMBAT:
			if not _enemy_valid():
				_release_task()
				_set_state(State.SEARCH)
				return
			ch.target = enemy.position + Vector2(-30, 0)
			ch.move_to_target(delta)
			ch.attacking = true
			enemy.take_damage(ATTACK_DPS * ch.skill_mult(GameData.Job.COMBAT) * delta)
			ch.energy = maxf(0.0, ch.energy - 0.5 * delta)     # 戦うと疲れる

		# ---- 休憩 ----
		State.REST_MOVE:
			ch.target = game.base.bed_point(ch.bed_index)
			if ch.move_to_target(delta):
				_set_state(State.REST)
		State.REST:
			ch.sleeping = true
			ch.target = game.base.bed_point(ch.bed_index)
			if ch.energy >= REST_UNTIL:
				_release_task()
				_set_state(State.SEARCH)


func _res_target() -> Vector2:
	# 資源の少し手前（拠点側）。地面の範囲に収める。
	var p: Vector2 = res.position + Vector2(-40, 0)
	p.y = clampf(p.y, GameData.GROUND_Y_MIN, GameData.GROUND_Y_MAX)
	return p


func _prey_target() -> Vector2:
	var p: Vector2 = prey.position + Vector2(-30, 0)
	p.y = clampf(p.y, GameData.GROUND_Y_MIN, GameData.GROUND_Y_MAX)
	return p


func _enemy_valid() -> bool:
	return enemy != null and is_instance_valid(enemy) and not enemy.dead


func _prey_valid() -> bool:
	return prey != null and is_instance_valid(prey) and not prey.dead and not game.director.outdoor_blocked()


func _go_storage() -> void:
	_set_state(State.MOVE_TO_STORAGE)


func _res_valid() -> bool:
	return res != null and is_instance_valid(res) and res.position.x > 30.0 and not game.director.outdoor_blocked()


## 優先度の高い仕事から順に、着手できるものを探す。
func _search() -> void:
	var jobs: Array = GameData.job_list()
	jobs.sort_custom(func(a, b):
		var pa: int = ch.priorities.get(a, 0)
		var pb: int = ch.priorities.get(b, 0)
		if pa != pb:
			return pa > pb
		return a < b)
	# とても疲れていたら（休憩が0でなければ）まず休む
	if ch.energy < TIRED_BELOW and ch.priorities.get(GameData.Job.REST, 0) > 0 and _try_start(GameData.Job.REST):
		current_job = GameData.Job.REST
		return
	# 拠点の部位が壊れかけていたら（修理が0でなければ）まず直す
	if ch.priorities.get(GameData.Job.REPAIR, 0) > 0 and game.base.has_critical_part() and _try_start(GameData.Job.REPAIR):
		current_job = GameData.Job.REPAIR
		return
	# 敵が拠点を攻撃している間は、戦闘の優先度が0でない仲間は、まず迎え撃つ（戦闘が0なら非戦闘員）
	if ch.priorities.get(GameData.Job.COMBAT, 0) > 0 and game.director.raid_pressing() and _try_start(GameData.Job.COMBAT):
		current_job = GameData.Job.COMBAT
		return
	for j in jobs:
		if ch.priorities.get(j, 0) <= 0:
			continue
		if _try_start(j):
			current_job = j
			return
	current_job = -1
	timer = 0.8
	ch.target = Vector2(randf_range(540.0, 860.0), GameData.LO_Y)
	_set_state(State.IDLE)


func _try_start(job: int) -> bool:
	match job:
		GameData.Job.HUNT:
			if game.director.outdoor_blocked():
				return false               # 天候で屋外に出られない
			var best = null
			var best_d := INF
			for c in game.creatures_root.get_children():
				if c.dead or c.hunted_by != null or c.position.x < 60.0 or c.position.x > 1180.0:
					continue
				if not game.hunt_allowed(c.species):
					continue
				var d: float = c.position.distance_to(ch.position)
				if d < best_d:
					best_d = d
					best = c
			if best == null:
				return false
			prey = best
			prey.hunted_by = ch
			_set_state(State.HUNT_MOVE)
			return true
		GameData.Job.GATHER:
			if game.director.outdoor_blocked():
				return false               # 天候で屋外に出られない
			# 回収の方針（★）が高いほど、遠くても優先する。★0 の資源は拾わない。獲物は常に拾う。
			var best = null
			var best_score := 0.0
			for r in game.resources_root.get_children():
				if r.claimed_by != null or r.position.x < 60.0 or r.position.x > 1250.0:
					continue
				var w: float = game.gather_weight(r.item)
				if w <= 0.0:
					continue
				var score: float = w / (120.0 + r.position.distance_to(ch.position))
				if score > best_score:
					best_score = score
					best = r
			if best == null:
				return false
			res = best
			res.claimed_by = ch
			timer = 0.4
			_set_state(State.NOTICE)
			return true
		GameData.Job.HAUL:
			# 1) 燃料の補給（倉庫の燃料 → 機関室）。拠点を動かし続けるため最優先。
			for fi in GameData.FUEL_ITEMS:
				if game.storage.count_of(fi) > 0 and game.base.wants_fuel(fi):
					haul_item = fi
					game.base.refuel_reserved = true
					_set_state(State.REFUEL_TAKE)
					return true
			# 2) 加工の方針に従って、材料一式を加工設備へ
			var p: BaseProcessor = game.processor
			if p.free_slots() <= 0:
				return false
			var r: Dictionary = game.choose_recipe()
			if r.is_empty():
				return false
			haul_recipe = r
			p.reserve(r)
			_set_state(State.HAUL_TAKE)
			return true
		GameData.Job.PROCESS:
			var p: BaseProcessor = game.processor
			if p.has_work_for_worker():
				p.worker = ch
				_set_state(State.MOVE_TO_MACHINE)
				return true
			return false
		GameData.Job.REPAIR:
			if game.storage.count_of(GameData.Item.REPAIR_KIT) <= 0:
				return false
			var part: int = game.base.part_to_repair()
			if part < 0:
				return false
			repair_part = part
			game.base.repair_reserved[part] = ch
			_set_state(State.REPAIR_TAKE)
			return true
		GameData.Job.REST:
			if ch.energy >= REST_START_BELOW:
				return false
			var bi: int = game.base.claim_bed(ch)
			if bi < 0:
				return false
			ch.bed_index = bi
			_set_state(State.REST_MOVE)
			return true
		GameData.Job.COMBAT:
			var best = null
			var best_d := INF
			for e in game.enemies_root.get_children():
				if e.dead or e.position.x > 1270.0:
					continue
				var d: float = e.position.distance_to(ch.position)
				if d < best_d:
					best_d = d
					best = e
			if best == null:
				return false
			enemy = best
			_set_state(State.COMBAT_MOVE)
			return true
	return false


## 途中の仕事を破棄して予約を解放する（荷物を持っていない時のみ呼ぶ）。
func _release_task() -> void:
	if res != null and is_instance_valid(res) and res.claimed_by == ch:
		res.claimed_by = null
		res.gather_progress = 0.0
	res = null
	if prey != null and is_instance_valid(prey) and prey.hunted_by == ch:
		prey.hunted_by = null
	prey = null
	enemy = null
	game.base.release_bed(ch)
	ch.bed_index = -1
	if state == State.HAUL_TAKE and not haul_recipe.is_empty():
		game.processor.cancel_reservation(haul_recipe)
		haul_recipe = {}
	if state == State.REFUEL_TAKE:
		game.base.refuel_reserved = false
	if state == State.REPAIR_TAKE and repair_part >= 0:
		game.base.repair_reserved.erase(repair_part)
		repair_part = -1
	if game.processor.worker == ch:
		game.processor.worker = null


## プレイヤーが優先度を変えたとき、荷物を持っていなければ即座に選び直す。
func on_priority_changed() -> void:
	if ch.carrying >= 0:
		return
	if state in [State.IDLE, State.SEARCH]:
		_set_state(State.SEARCH)
		return
	_release_task()
	_set_state(State.SEARCH)
