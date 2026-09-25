class_name Worker
extends Node2D
## 仲間のネズミ。移動（階をまたぐ移動含む）・ドット絵の描画・疲労を持ち、判断は CharacterAI に任せる。

const PX := GameData.PX
# mouse_*.png のコマ番号
const F_IDLE0 := 0
const F_IDLE1 := 1
const F_WALK0 := 2       # 2..5
const F_PICK := 6
const F_WORK0 := 7       # 7..8
const F_CLIMB0 := 9      # 9..10
const F_SLEEP := 11
const F_CARRY := 12

var game
var char_name := "ネズミ"
var palette := "grey"
var priorities := {}          # Job -> 0..MAX_PRIORITY（0 = やらない）
var carrying := -1            # 持っている Item（-1 = なし）
var carrying_species := ""   # 獲物を運んでいるときの生物の種類
var carry_n := 1              # 持っている個数（採取ポイントでは袋いっぱいまで。それ以外は1）
var carry_bonus := {}         # 採取の副産物 {Item: 個数}（倉庫に運ぶとき一緒に入れる）
var tools := {}               # 持っている採取の道具 {枠: Item}（data/gathering.gd。持たない枠は素手）
var speed := 120.0
var target := Vector2.ZERO
var slot_offset := Vector2.ZERO   # 作業場所で重ならないようにするずらし
var selected := false
var energy := 100.0               # 元気（休憩で回復する）
var floor_i := 1                  # 今いる階（0=地面 1=下の階 2=上の階）
var facing := 1.0
var ai: CharacterAI
# 仲間のプロフィール
var level := 1
var gender := 0                   # GameData.GENDER_NAMES の番号
var ranks := {}                   # Field -> 0..7（0=E, 7=SSS）
var skills: Array = []
var dept := -1                    # 配属している部署（GameData.Field）
var away := false                 # 調査隊として拠点を離れている（scripts/expedition.gd）

# 毎フレーム ai が設定する描画用の状態
var moving := false
var pose := ""                # "pick" / "work" / ""
var attacking := false        # 戦闘用（work と同じ見た目）
var sleeping := false
var bed_index := -1

var _climb_dest = null        # 階をまたぐ移動の途中（Vector2）
var _climb_floor := 1
var _climb_kind := ""
var _t := 0.0
var _sheet: Texture2D

signal state_changed


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(g, cname: String, pal: String, prios: Dictionary, slot: int, profile: Dictionary = {}) -> void:
	game = g
	char_name = cname
	palette = pal
	priorities = prios.duplicate()
	level = profile.get("level", 1)
	gender = profile.get("gender", 0)
	ranks = profile.get("ranks", {}).duplicate()
	skills = profile.get("skills", []).duplicate()
	dept = profile.get("dept", -1)
	if dept < 0:
		dept = best_fields()[0]   # 配属の指定がなければ、得意分野の部署に入る
	slot_offset = Vector2((slot - 1) * 36.0, 0)
	_sheet = GameData.tex("res://assets/characters/mouse_%s.png" % palette)
	ai = CharacterAI.new()
	ai.setup(self, g)


func set_priority(job: int, value: int) -> void:
	priorities[job] = clampi(value, 0, GameData.MAX_PRIORITY)
	ai.on_priority_changed()   # 優先度が変わったら仕事を選び直す


## 調査隊として出発する。仕事を中断して、持っていた物・予約を元に戻し、拠点から姿を消す。
func depart() -> void:
	var a := ai
	match a.state:
		CharacterAI.State.HAUL_MOVE:              # 加工設備へ運んでいる材料は倉庫へ戻す
			if not a.haul_recipe.is_empty():
				game.processor.cancel_reservation(a.haul_recipe)
				for it in a.haul_recipe["in"]:
					game.storage.add_item(it, a.haul_recipe["in"][it])
				a.haul_recipe = {}
				carrying = -1
		CharacterAI.State.REFUEL_MOVE, CharacterAI.State.REFUEL:
			game.base.refuel_reserved = false
		CharacterAI.State.REPAIR_MOVE, CharacterAI.State.REPAIR:
			game.base.repair_reserved.erase(a.repair_part)
			a.repair_part = -1
	if carrying >= 0:                              # 手に持っている物は倉庫へ
		if carrying == GameData.Item.CARCASS:
			game.storage.butcher(carrying_species)
		else:
			game.storage.add_item(carrying, carry_n)
			for it in carry_bonus:
				game.storage.add_item(it, carry_bonus[it])
		carrying = -1
		carrying_species = ""
		carry_n = 1
		carry_bonus = {}
	a._release_task()
	a._set_state(CharacterAI.State.IDLE)
	a.timer = 9999.0
	away = true
	visible = false
	set_process(false)
	position = Vector2(-2000.0, GameData.LO_Y)     # 敵の攻撃やクリックの対象にならない場所


## 調査隊から戻る。斜路の下に現れ、元気を引き継ぐ。
func arrive(new_energy: float) -> void:
	away = false
	visible = true
	set_process(true)
	energy = new_energy
	floor_i = 0
	position = GameData.RAMP_FOOT + Vector2(randf_range(-30.0, 30.0), 0.0)
	target = position
	ai.timer = 0.0
	ai._set_state(CharacterAI.State.SEARCH)


## 採取ポイント kind に使う道具（-1 = 素手）。道具は枠（採掘・伐採）ごとに1つ。
func tool_for(kind: String) -> int:
	return int(tools.get(GatherDB.slot_of_point(kind), -1))


## 採取ポイント kind を掘るときの結果（採取ポイント × 道具 × 自分の能力）。data/gathering.gd の evaluate() を使う。
func gather_eval(kind: String) -> Dictionary:
	return GatherDB.evaluate(kind, tool_for(kind), ranks.get(GameData.Field.GATHERER, 0), field_mult(GameData.Field.GATHERER))


## 仕事の速さの倍率。分野ランク・得意分野・レベル・拠点の分野レベルで決まる。
func skill_mult(job: int) -> float:
	var f: int = GameData.JOB_FIELD.get(job, -1)
	if f < 0:
		return 1.0
	return field_mult(f)


## 分野ごとの作業の速さ（加工ではレシピの分野を使う。調理なら料理人のランク）。
## 空腹のときは遅くなる。
func field_mult(f: int) -> float:
	var r: int = ranks.get(f, 0)
	var s: int = best_rank()
	var m := 0.75 + 0.1 * r + 0.02 * s + 0.02 * (level - 1)
	m *= 1.0 + 0.05 * (GameData.field_level(game.workers, f) - 1)
	if game.hungry:
		m *= GameData.HUNGRY_MULT
	return m * game.director.work_mult()      # 襲撃で防備を固めているあいだは作業が遅くなる


## 個体ランク = その個体が持つ分野ランクの最高値（別の能力値ではない）。
## 得意分野 = 最高ランクの分野すべて（同率なら複数）。
func best_rank() -> int:
	var m := 0
	for f in GameData.Field.values():
		m = maxi(m, ranks.get(f, 0))
	return m


func best_fields() -> Array:
	var r := best_rank()
	var l: Array = []
	for f in GameData.Field.values():
		if ranks.get(f, 0) == r:
			l.append(f)
	return l


func best_fields_text() -> String:
	var n: Array = []
	for f in best_fields():
		n.append(GameData.FIELD_NAMES[f])
	return "／".join(PackedStringArray(n))


func rank_letter() -> String:
	return GameData.RANKS[best_rank()]


func rank_text(field: int) -> String:
	return GameData.RANKS[ranks.get(field, 0)]


## 疲れると動きが遅くなる。
func current_speed() -> float:
	var sp := speed
	if game != null and game.hungry:
		sp *= GameData.HUNGRY_MULT          # 空腹だと移動も遅い
	if energy >= 25.0:
		return sp
	return sp * (0.5 + 0.5 * energy / 25.0)


## target へ向かって1歩進む。到着したら true。
## 別の階に target がある場合は、斜路・ハシゴを経由して移動する。
func move_to_target(delta: float) -> bool:
	var step := current_speed() * delta
	# 階の移動中（斜路・ハシゴ）
	if _climb_dest != null:
		var d: Vector2 = _climb_dest - position
		var st := step * (0.7 if _climb_kind == "ladder" else 1.0)
		moving = true
		if d.length() <= maxf(3.0, st):
			position = _climb_dest
			floor_i = _climb_floor
			_climb_dest = null
		else:
			position += d.normalized() * st
			if absf(d.x) > 1.0:
				facing = signf(d.x)
		return false
	var tf := GameData.floor_of_y(target.y)
	if floor_i != tf:
		var leg := GameData.route_leg(floor_i, tf)
		if _step_toward(leg["approach"], step):
			_climb_dest = leg["dest"]
			_climb_floor = leg["floor"]
			_climb_kind = leg["kind"]
			if absf(_climb_dest.x - position.x) > 1.0:
				facing = signf(_climb_dest.x - position.x)
		return false
	return _step_toward(target, step)


func _step_toward(p: Vector2, step: float) -> bool:
	var d := p - position
	if d.length() <= maxf(4.0, step):
		position = p
		return true
	position += d.normalized() * step
	if floor_i != 0:
		position.y = GameData.deck_y(floor_i)   # 階の中では床の高さを保つ
	moving = true
	if absf(d.x) > 1.0:
		facing = signf(d.x)
	return false


func _process(delta: float) -> void:
	_t += delta
	moving = false
	attacking = false
	sleeping = false
	pose = ""
	ai.tick(delta)
	# 元気の増減
	if sleeping:
		# 車体が傷んでいると（居住区が傷んで）よく休めない
		var rec := 9.0 if game.base.condition(GameData.Part.HULL) >= GameData.PART_BAD else 4.5
		energy = minf(100.0, energy + rec * delta)
	elif ai.state == CharacterAI.State.IDLE:
		energy = maxf(0.0, energy - 0.25 * game.director.energy_mult() * delta)
	else:
		energy = maxf(0.0, energy - 0.7 * game.director.energy_mult() * delta)   # 酷暑などで疲れやすくなる
	queue_redraw()


func _frame() -> int:
	if sleeping:
		return F_SLEEP
	if _climb_dest != null and _climb_kind == "ladder":
		return F_CLIMB0 + (int(_t * 8.0) % 2)
	if pose == "pick":
		return F_PICK
	if pose == "work" or attacking:
		return F_WORK0 + (int(_t * 6.0) % 2)
	if moving:
		return F_WALK0 + (int(_t * 10.0) % 4)
	if carrying >= 0:
		return F_CARRY
	return F_IDLE0 + (int(_t * 1.6) % 2)


func _draw() -> void:
	var snap := ((position / 4.0).round() * 4.0) - position
	var lift := Vector2(0, -24) if sleeping else Vector2.ZERO
	var fr := _frame()
	if not sleeping:
		draw_rect(Rect2(snap + Vector2(-20, -4), Vector2(40, 8)), Color(0, 0, 0, 0.25))
	if selected:
		var c := Color("fff27a")
		draw_rect(Rect2(snap + Vector2(-28, 0), Vector2(56, 4)), c)
		draw_rect(Rect2(snap + Vector2(-20, 4), Vector2(40, 4)), c)
	draw_set_transform(snap + lift, 0.0, Vector2(facing, 1.0))
	draw_texture_rect_region(_sheet, Rect2(-32, -64, 64, 64), Rect2(fr * 16, 0, 16, 16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 採取ポイントを掘っているあいだは、手にした道具が見える
	if pose == "pick" and ai.res is GatherPoint and not sleeping:
		var tl: int = tool_for(ai.res.kind)
		if tl >= 0:
			GameData.draw_item(self, tl, snap + Vector2(facing * 26.0, -34.0), 0.75)
	var top := -70.0
	if carrying == GameData.Item.CARCASS and carrying_species != "":
		GameData.draw_creature(self, carrying_species, 0, snap + Vector2(0, top + 6), facing, true, 0.6)
		top -= 34.0
	elif carrying >= 0:
		GameData.draw_item(self, carrying, snap + Vector2(0, top - 8), 0.5)
		top -= 30.0
	if sleeping:
		var z := "Zzz" if int(_t * 1.5) % 2 == 0 else "Zz"
		GameData.draw_text(self, snap + Vector2(16, -60), z, 14, Color("cfe6ff"), 60.0)
	else:
		GameData.draw_text(self, snap + Vector2(0, top - 4), ai.status_text(), 12, Color("fde68a"), 150.0)
	GameData.draw_text(self, snap + Vector2(0, 22), char_name, 12, Color.WHITE, 90.0)
