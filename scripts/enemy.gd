class_name Enemy
extends Node2D
## 砂漠の敵（サソリ系）。右から現れ、拠点の前まで来て車体を攻撃する（襲撃の出来事。scripts/director.gd）。
## 種類は EventDB.ENEMIES（体力・被害・速さ・大きさ・色・戦利品）。戦闘担当の仲間が倒す。
## 車体の被害は「防備を固める」で減る。近くで戦っている仲間は疲れる。

var game
var kind := "scorpion"
var max_hp := 40.0
var hp := 40.0
var dead := false
var hold_x := 700.0          # このx位置まで来たら止まって拠点を攻撃する
var run_speed := 55.0        # 砂漠の流れに加えて進む速さ
var damage := 2.0            # 1秒あたりの車体への被害
var body_scale := 1.0
var _body := Color("8b2e2e")
var _atk_timer := 0.6
var _flash := 0.0
var _t := 0.0

const HIT_REACH := 80.0      # 攻撃が仲間に届く距離
const HIT_TIRE := 2.5        # 攻撃1回で仲間に加わる疲労度


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup_kind(g, k: String) -> void:
	game = g
	kind = k
	var d: Dictionary = EventDB.ENEMIES[k]
	max_hp = d["hp"]
	hp = max_hp
	damage = d["dmg"]
	run_speed = d["run"]
	body_scale = d["scale"]
	_body = Color(d["color"])
	hold_x = randf_range(560.0, 860.0)


## 旧来の呼び出し（体力だけ指定）。サソリとして扱う。
func setup(g, hp_value: float) -> void:
	setup_kind(g, "scorpion")
	max_hp = hp_value
	hp = hp_value


func display_name() -> String:
	return EventDB.ENEMIES[kind]["name"]


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.1
	if hp <= 0.0:
		dead = true
		game.on_enemy_killed(self)
		queue_free()


func is_attacking() -> bool:
	return position.x <= hold_x + 2.0


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if position.x > hold_x:
		position.x -= (game.scroll_speed + run_speed) * delta
	else:
		position.x = hold_x
		_atk_timer -= delta
		if _atk_timer <= 0.0:
			_atk_timer = 1.0
			game.base.take_damage(damage * game.director.hull_dmg_mult())
			_hit_nearby_worker()
	queue_redraw()


## 近くにいる仲間を1人、疲れさせ、ケガをさせる（倒れている仲間は狙わない）。HP の失い方は CrewStatusDB。
func _hit_nearby_worker() -> void:
	var best = null
	var best_d := HIT_REACH * body_scale
	for w in game.workers:
		if w.down:
			continue
		var d: float = w.position.distance_to(position)
		if d < best_d:
			best_d = d
			best = w
	if best != null:
		best.fatigue = minf(CrewStatusDB.MAX_FATIGUE, best.fatigue + HIT_TIRE)
		CrewStatus.damage(best, CrewStatusDB.RAID_HIT_HP * body_scale, CrewStatusDB.RAID_HIT_STRESS)


func _draw() -> void:
	var body := _body if _flash <= 0.0 else Color("ffffff")
	var dark := body.darkened(0.35)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(body_scale, body_scale))
	draw_colored_polygon(_ellipse(Vector2(0, 14), 24, 6), Color(0, 0, 0, 0.2))
	# 脚
	for i in 4:
		var x := -14.0 + i * 9.0
		var sw := sin(_t * 14.0 + i * 1.6) * 4.0
		draw_line(Vector2(x, 6), Vector2(x - 6 + sw, 16), dark, 2.0)
		draw_line(Vector2(x, 6), Vector2(x + 6 - sw, 16), dark, 2.0)
	# 体・尾・はさみ
	draw_colored_polygon(_ellipse(Vector2(0, 2), 20, 11), body)
	draw_polyline(PackedVector2Array([Vector2(16, 0), Vector2(28, -6), Vector2(30, -20), Vector2(20, -28),
			Vector2(12, -24)]), body, 5.0)
	draw_circle(Vector2(12, -24), 4, Color("f0c040"))
	draw_line(Vector2(-16, -2), Vector2(-30, -8), dark, 4.0)
	draw_line(Vector2(-16, 6), Vector2(-30, 10), dark, 4.0)
	draw_circle(Vector2(-32, -9), 6, body)
	draw_circle(Vector2(-32, 11), 6, body)
	draw_circle(Vector2(-12, -4), 2, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 体力バーと名前
	var top := -40.0 * body_scale
	draw_rect(Rect2(-22, top, 44, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-22, top, 44.0 * clampf(hp / max_hp, 0.0, 1.0), 6), Color("e0533d"))
	GameData.draw_text(self, Vector2(0, top - 6), display_name(), 12, Color("ffb4a8"), 90.0)


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
