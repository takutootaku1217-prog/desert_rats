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
##   食事: EAT_TAKE(倉庫の食料) -> EAT（満腹度が下がったとき、仕事より先に。scripts/crew_status.gd・data/crew_status.gd）
##   運搬の依頼（プレイヤーが頼んだ 倉庫 ⇄ 作業場）: XFER_TAKE(元の置き場) -> XFER_MOVE(行き先)。運搬の仕事（HAUL）の一部。同時に1人だけ（Main.transfer_worker）
## 新しい仕事は _try_start() に分岐を足し、状態を増やすだけで拡張できる。

enum State {
	IDLE, SEARCH, NOTICE, MOVE_TO_RESOURCE, GATHER, MOVE_TO_STORAGE, STORE,
	HAUL_TAKE, HAUL_MOVE, MOVE_TO_MACHINE, PROCESS,
	COMBAT_MOVE, COMBAT, REPAIR_TAKE, REPAIR_MOVE, REPAIR,
	REST_MOVE, REST,
	REFUEL_TAKE, REFUEL_MOVE, REFUEL,
	HUNT_MOVE, HUNT_ATTACK,
	EAT_TAKE, EAT, DOWN, REST_HERE, XFER_TAKE, XFER_MOVE,
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
	State.EAT_TAKE: "食料を取りに行く",
	State.EAT: "食事中",
	State.DOWN: "倒れている",
	State.REST_HERE: "その場で休憩",
	State.XFER_TAKE: "素材を取りに行く（運搬の依頼）",
	State.XFER_MOVE: "素材を運ぶ（運搬の依頼）",
}

var ch      # Worker
var game    # Main
var state: int = State.IDLE
var timer := 0.0
var res = null          # 対象の ResourceNode
var haul_item := -1
var haul_recipe := {}   # 運搬中のレシピ
var repair_part := -1
var gather_ev := {}     # 採取ポイントを掘っている間の結果（GatherDB.evaluate。1回の袋ごとに決める）
var bag_limit := 1      # この袋に入れる最大の個数（倉庫の空き枠と袋の大きさで決まる）
var bag_frac := 0.0     # 取れる割合の端数（1.0 たまるごとに1個）
var enemy = null        # 対象の Enemy（戦闘用・現段階では未使用）
var prey = null         # 狩りの対象の Creature
const ATTACK_DPS := 14.0
const HUNT_DPS := 16.0
const HUNT_REACH := 44.0
const REPAIR_TIME := 1.2
const REFUEL_TIME := 0.6
## 休憩の基準は data/crew_status.gd（CrewStatusDB）にまとめてある（スタミナ・疲労度・HP）
var eat_wait := 0.0      # 食料が取れなかったあと、食べに行き直すまでの待ち（食事のループにならないように）
var xfer_item := -1      # 運搬の依頼で運んでいるアイテムと向き（Main.request_transfer）
var xfer_dir := ""
var _eat_claimed := false   # 食料の在庫を1つ取り置いている（食べに向かっている間）
var current_job := -1


func setup(worker, g) -> void:
	ch = worker
	game = g
	_set_state(State.SEARCH)


func status_text() -> String:
	if ch.away:
		return "遠征中"
	return STATE_TEXT[state]


func _set_state(s: int) -> void:
	state = s
	ch.state_changed.emit()


func tick(delta: float) -> void:
	if eat_wait > 0.0:
		eat_wait -= delta
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
				if is_instance_valid(res) and res is GatherPoint and ch.carrying >= 0:    # res が消えている（流れ去って解放された等）ときは、is で調べようとしない
					_finish_trip()             # 天候などで中断しても、掘った分は倉庫へ運ぶ
					return
				_release_task()
				_set_state(State.SEARCH)
				return
			if res is GatherPoint and ch.priorities.get(GameData.Job.COMBAT, 0) > 0 and game.director.raid_pressing():
				# 敵が拠点を攻撃している間、戦闘担当は採取を切り上げる（掘った分は倉庫へ。何もなければすぐ迎撃へ）
				if ch.carrying >= 0:
					_finish_trip()
				else:
					_release_task()
					_set_state(State.SEARCH)
				return
			ch.target = _res_target()
			ch.move_to_target(delta)   # 流れる資源に付いていく
			ch.pose = "pick"
			if res is GatherPoint:
				_work_point(delta)         # 採取ポイント: 道具と能力で掘る（data/gathering.gd）
				return
			res.gather_progress += delta * ch.skill_mult(GameData.Job.GATHER) * game.director.outdoor_mult()
			if res.gather_progress >= ResourceNode.GATHER_TIME:
				ch.carrying = res.item
				ch.carrying_species = res.species
				ch.carry_n = 1
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
					game.storage.add_item(ch.carrying, ch.carry_n)
					for it in ch.carry_bonus:                       # 採取の副産物も一緒に入れる
						game.storage.add_item(it, ch.carry_bonus[it])
				ch.carrying = -1
				ch.carrying_species = ""
				ch.carry_n = 1
				ch.carry_bonus = {}
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
				prey = null
				CrewStatus.hunt_injury(ch, p.species)                 # 狩りの事故（確率で少しケガをする。HP が尽きたら倒れる）
				if ch.down:
					return                                            # 獲物は落ちたまま。ほかの仲間が拾う
				# 倒した獲物は、そのまま自分で拠点へ運ぶ
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
			ch.target = game.processor.station_point(haul_recipe) + ch.slot_offset   # そのレシピの設備（加工設備／ワークベンチ）へ
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
			ch.target = game.processor.work_point() + ch.slot_offset      # 次に作る物の設備（加工設備／ワークベンチ）へ
			if ch.move_to_target(delta):
				_set_state(State.PROCESS)
		State.PROCESS:
			var p: BaseProcessor = game.processor
			if _urgent_life_need():
				p.worker = null                                       # 食事・休憩が急ぎなら加工を中断する（途中経過は設備に残り、次の人が続ける）
				_set_state(State.SEARCH)
				return
			if not p.output.is_empty():
				ch.carrying = p.take_output()
				p.worker = null
				_go_storage()
			elif not p.current.is_empty() or (not p.orders.is_empty() and not p.only_blocked()):
				ch.target = p.work_point() + ch.slot_offset               # 設備が変わったら（加工設備 ⇄ ワークベンチ）そこへ歩く
				if ch.move_to_target(delta):
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

		# ---- 食事 ----
		State.EAT_TAKE:
			ch.target = game.storage.access_point() + ch.slot_offset
			if ch.move_to_target(delta):
				_release_eat_claim()
				if game.storage.take_item(GameData.Item.FOOD):
					ch.carrying = GameData.Item.FOOD
					timer = CrewStatusDB.EAT_SECONDS
					_set_state(State.EAT)
				else:
					eat_wait = CrewStatusDB.EAT_RETRY_SECONDS       # 取り合いで食料がなくなっていた。しばらく仕事を続ける
					_set_state(State.SEARCH)
		State.EAT:
			timer -= delta                                          # 食料を持って、しばらく食べる（手に食料が見える）
			if timer <= 0.0:
				CrewStatus.eat(ch, ch.carrying)
				game.total_eaten += 1
				ch.carrying = -1
				_set_state(State.SEARCH)

		# ---- 運搬の依頼（倉庫 ⇄ 作業場）----
		State.XFER_TAKE:
			ch.target = _xfer_point(true) + ch.slot_offset
			if ch.move_to_target(delta):
				var got: int = game.begin_transfer_trip(xfer_item, xfer_dir)
				if got > 0:
					ch.carrying = xfer_item
					ch.carry_n = got
					ch.carry_bonus = {}
					_set_state(State.XFER_MOVE)
				else:
					_release_task()                                    # 元にもう材料がなかった
					_set_state(State.SEARCH)
		State.XFER_MOVE:
			ch.target = _xfer_point(false) + ch.slot_offset
			if ch.move_to_target(delta):
				game.finish_transfer_trip(xfer_item, xfer_dir, ch.carry_n)
				ch.carrying = -1
				ch.carry_n = 1
				_release_task()
				_set_state(State.SEARCH)

		# ---- ベッドが使えないときの簡易休憩（その場で休む。回復は遅い）----
		State.REST_HERE:
			ch.resting = true
			if ch.priorities.get(GameData.Job.REST, 0) > 0 and game.base.has_free_bed() and _try_start(GameData.Job.REST):
				current_job = GameData.Job.REST                     # ベッドが空いたら、ベッドで休む
				return
			if CrewStatus.rest_done(ch) or (CrewStatus.needs_to_eat_now(ch) and _wants_to_eat()):
				_release_task()
				_set_state(State.SEARCH)

		# ---- 戦闘不能（HP 0）。倒れて動けない。HP が戻ると起き上がる ----
		State.DOWN:
			if not ch.down:
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
			ch.stamina = maxf(0.0, ch.stamina - 0.5 * delta)     # 戦うと疲れる

		# ---- 休憩 ----
		State.REST_MOVE:
			ch.target = game.base.bed_point(ch.bed_index)
			if ch.move_to_target(delta):
				_set_state(State.REST)
		State.REST:
			ch.sleeping = true
			ch.target = game.base.bed_point(ch.bed_index)
			if CrewStatus.rest_done(ch) or (CrewStatus.needs_to_eat_now(ch) and _wants_to_eat()):
				_release_task()                                     # 回復しきった（スタミナ・疲労度・HP）。とても空腹なら、先に食べに行く
				_set_state(State.SEARCH)


## 採取ポイントを掘る（1フレームぶん）。掘るたびに残量が減り、取れる割合ぶんだけ袋に入る。
## 袋がいっぱい・残量が尽きたら倉庫へ運ぶ。1単位を掘る時間・取れる割合は 採取ポイント × 道具 × 自分の能力（data/gathering.gd）。
func _work_point(delta: float) -> void:
	var pt: GatherPoint = res
	if gather_ev.is_empty():
		gather_ev = ch.gather_eval(pt.kind)
	pt.work += delta * game.director.outdoor_mult() / maxf(0.05, float(gather_ev["seconds"]))
	while pt.work >= 1.0 and pt.remaining > 0 and _bag_n() < bag_limit:
		pt.work -= 1.0
		pt.remaining -= 1                                        # 1単位を掘り出した
		bag_frac += float(gather_ev["eff"])                      # そのうち手に入る割合ぶんが袋に入る
		while bag_frac >= 1.0 and _bag_n() < bag_limit:
			bag_frac -= 1.0
			if ch.carrying < 0:
				ch.carrying = pt.item
				ch.carry_n = 1
			else:
				ch.carry_n += 1
			for it in gather_ev["bonus"]:                       # 副産物（道具によっては見つかる）
				if randf() < float(gather_ev["bonus"][it]):
					ch.carry_bonus[it] = ch.carry_bonus.get(it, 0) + 1
	if _bag_n() >= bag_limit or (pt.remaining <= 0 and _bag_n() > 0):
		_finish_trip()
	elif pt.remaining <= 0:
		_release_task()                                          # 掘り尽くしたが、1個も取れなかった
		_set_state(State.SEARCH)


## いま袋に入っている個数（何も持っていなければ 0）
func _bag_n() -> int:
	return ch.carry_n if ch.carrying >= 0 else 0


## 掘るのを終えて、袋の中身を倉庫へ運ぶ。
func _finish_trip() -> void:
	game.total_gathered += ch.carry_n
	if res != null and is_instance_valid(res) and res.claimed_by == ch:
		res.claimed_by = null
		res.reserved = 1
		if res is GatherPoint:
			res.work = 0.0
	res = null
	gather_ev = {}
	bag_frac = 0.0
	_go_storage()


## 流れていく資源 r に、画面の外へ出る前に追いつけるか。資源は scroll_speed で左へ流れ、仲間は current_speed で追う。
## 資源が自分より左にあるときは、追いつく速さ＝仲間の速さ − 流れる速さ（速度が速いと追いつけない）。
## 拠点の中にいるときは、斜路の下（地面への出口）まで歩く時間も数える。追いつけない資源を選ぶと、
## 「見つけては取り消す」を繰り返して、何も回収できない（特に速度を上げたとき）。
func _can_reach(r) -> bool:
	var vs: float = game.scroll_speed
	if vs <= 1.0:
		return true
	var vw: float = maxf(1.0, ch.current_speed())
	var start: Vector2 = ch.position
	var t0 := 0.0
	if ch.floor_i != 0:
		start = GameData.RAMP_FOOT
		t0 = ch.position.distance_to(GameData.RAMP_FOOT) / vw          # 出口まで歩く間にも資源は流れる
	var to := Vector2(r.position.x - 40.0 - vs * t0, r.position.y)     # 仲間が向かう位置（資源の少し手前）
	var closing: float = vw + vs if to.x > start.x else vw - vs
	if closing < vw * 0.2:
		return false
	var t_reach: float = t0 + start.distance_to(to) / closing
	var work := 1.5                                                    # 拾う・掘り始めるのに要る時間の目安
	return t_reach + work < (r.position.x - 60.0) / vs


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
	# 生活の必要（休む・食べる）を、仕事より先に見る。行けないもの（食料がない・ベッドがない・休憩が★0）は飛ばして、仕事を続ける
	if _try_life_need():
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


## 生活の必要（CrewStatus.life_needs の順）のうち、いま実際に行けるものを始める。始めたら true
func _try_life_need() -> bool:
	for need in CrewStatus.life_needs(ch):
		if need == "eat":
			if _try_start_eat():
				return true
		elif _can_start_rest():
			if game.base.has_free_bed() and _try_start(GameData.Job.REST):
				current_job = GameData.Job.REST                     # ベッドで休む
			else:
				_start_rest_here()                                  # ベッドが使えないときは、その場で簡易休憩
			return true
	return false


## 休憩を始められるか（休憩の優先度が0でなく、休むべき状態）。ベッドがなくても、その場で簡易休憩できる
func _can_start_rest() -> bool:
	return ch.priorities.get(GameData.Job.REST, 0) > 0 and CrewStatus.can_rest(ch)


## その場で簡易休憩を始める（ベッドが使えないとき。回復はベッドより遅い: CrewStatusDB.REST_IN_PLACE_RATE）
func _start_rest_here() -> void:
	current_job = GameData.Job.REST
	_set_state(State.REST_HERE)


## 運搬の依頼の、元の置き場（from_source = true）／行き先（false）の位置。倉庫 → 作業場（to_workshop）または 作業場 → 倉庫（to_storage）
func _xfer_point(from_source: bool) -> Vector2:
	var to_workshop: bool = xfer_dir == "to_workshop"
	if to_workshop == from_source:
		return game.storage.access_point()
	return game.processor.access_point()


## HP が 0 になった（戦闘不能）。仕事を中断して（荷物は倉庫へ戻し、予約は解放して）、その場に倒れる。
func on_down() -> void:
	ch.stop_work()
	_set_state(State.DOWN)


## 食べに行けるか（空腹で、食べられる食料が倉庫にあり、食べに行き直す待ちでもない）
func _wants_to_eat() -> bool:
	return CrewStatus.wants_to_eat(ch) and eat_wait <= 0.0 and game.food_for_eating() > 0


## 食事に向かう。食料の在庫を1つ取り置く（同じ1個に2人が向かわない）。
func _try_start_eat() -> bool:
	if not _wants_to_eat():
		return false
	game.food_claims += 1
	_eat_claimed = true
	_set_state(State.EAT_TAKE)
	return true


func _release_eat_claim() -> void:
	if _eat_claimed:
		_eat_claimed = false
		game.food_claims = maxi(0, game.food_claims - 1)


## 加工などの途中でも、先に済ませるべき生活の必要があるか（とても空腹で食べられる食料がある／休みが危険なほど必要）
func _urgent_life_need() -> bool:
	if CrewStatus.needs_to_eat_now(ch) and _wants_to_eat():
		return true
	return CrewStatus.rest_critical(ch) and _can_start_rest()


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
				if not game.hunt_allowed(c.species) or not game.hunt_has_room(c.species):
					continue                   # 見逃す設定、または倒しても素材が倉庫に入らない
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
			var inflight: Dictionary = game.gather_room()
			for r in game.resources_root.get_children():
				if r.claimed_by != null or r.position.x < 60.0 or r.position.x > 1250.0:
					continue
				var w: float = game.gather_weight(r.item)
				if w <= 0.0:
					continue
				if not game.has_room_for(r, inflight):
					continue               # 倉庫の枠がいっぱい（積載量）。拾っても置き場がない
				if not _can_reach(r):
					continue               # 画面の外へ流れ去る前に追いつけない（追っては取り消す往復を防ぐ）
				if r is GatherPoint:
					# 採取ポイント: 掘り尽くされていない・自分の道具と能力で取れる割合が低すぎない（無駄になる）こと。
					# 取れる割合が高いポイントほど優先（道具や能力に合った仕事を選ぶ）
					if not r.available():
						continue
					var eff: float = ch.gather_eval(r.kind)["eff"]
					if eff < GatherDB.MIN_EFF:
						continue
					w *= clampf(eff, 0.3, 1.3)
				var score: float = w / (120.0 + r.position.distance_to(ch.position))
				if score > best_score:
					best_score = score
					best = r
			if best == null:
				return false
			res = best
			res.claimed_by = ch
			if res is GatherPoint:
				# 袋の大きさ: 倉庫の空き枠（ほかの人が運んでいる分を除く）と袋の上限のうち小さいほう
				bag_limit = clampi(game.storage.free_for(res.item) - int(inflight.get(res.item, 0)), 1, GatherDB.CARRY_MAX)
				res.reserved = bag_limit
				gather_ev = {}
				bag_frac = 0.0
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
			# 2) プレイヤーが頼んだ運搬（倉庫 ⇄ 作業場）。同時に CraftDB.TRANSFER_WORKERS 人だけ引き受ける（ほかの仲間は、これまでの仕事を続ける）
			var xf: Dictionary = game.next_transfer()
			if not xf.is_empty() and (game.transfer_worker == null or game.transfer_worker == ch):
				xfer_item = int(xf["item"])
				xfer_dir = String(xf["dir"])
				game.transfer_worker = ch
				_set_state(State.XFER_TAKE)
				return true
			# 3) 加工の方針に従って、材料一式を加工設備へ
			var p: BaseProcessor = game.processor
			if p.free_slots() <= 0:
				return false
			var r: Dictionary = game.choose_recipe()
			if r.is_empty():
				return false
			if r.has("build"):
				game.claim_build(r["build"])       # 建設の依頼を待ちから外す（運搬をやめたら Processor.cancel_reservation が戻す）
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
			if not CrewStatus.can_rest(ch):
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
		res.reserved = 1
		if res is GatherPoint:
			res.work = 0.0
	res = null
	gather_ev = {}
	bag_frac = 0.0
	if prey != null and is_instance_valid(prey) and prey.hunted_by == ch:
		prey.hunted_by = null
	prey = null
	enemy = null
	game.base.release_bed(ch)
	ch.bed_index = -1
	_release_eat_claim()
	if game.transfer_worker == ch:
		game.transfer_worker = null                                     # 運搬の依頼の取り置き（同時に1人だけ）を返す
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


## 寝室が別の区画へ移ったとき（部屋の変更）。眠っていた仲間は、新しいベッドの位置へ歩き直す。
func on_bedroom_moved() -> void:
	if state == State.REST:
		_set_state(State.REST_MOVE)


## プレイヤーが優先度を変えたとき、荷物を持っていなければ即座に選び直す。
func on_priority_changed() -> void:
	if ch.carrying >= 0 or ch.down:
		return
	if state in [State.IDLE, State.SEARCH]:
		_set_state(State.SEARCH)
		return
	_release_task()
	_set_state(State.SEARCH)
