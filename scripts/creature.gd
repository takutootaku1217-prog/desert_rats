class_name Creature
extends Node2D
## 砂漠の生物（第1段階はすべて無害）。普段は拠点と一緒に流れながらゆっくり歩き、
## 狩りに来た仲間が近づくと逃げる。倒すと「獲物」になり、倉庫で解体すると素材になる。
## 将来: 捕獲（capturable）・飼育・購入・交換は、同じ species と drops を使って追加する。

var game
var species := "hare"
var max_hp := 16.0
var hp := 16.0
var dead := false
var hunted_by = null          # 狩りに来ている Worker
var capturable := true        # 将来の捕獲用（今は未使用）
var _flee_speed := 120.0
var _wander := 0.0            # のんびり歩く速さ（地面に対して）
var _wander_t := 0.0
var _fleeing := false
var _facing := -1.0
var _t := 0.0
var _flash := 0.0

const NOTICE_DIST := 170.0     # 仲間がこれより近づくと逃げ出す


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(g, sp: String) -> void:
	game = g
	species = sp
	var d: Dictionary = GameData.CREATURES[sp]
	max_hp = d["hp"]
	hp = max_hp
	_flee_speed = d["flee"]


func display_name() -> String:
	return GameData.CREATURES[species]["name"]


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.1
	_fleeing = true
	if hp <= 0.0:
		dead = true
		game.on_creature_killed(self)
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	var ground_v := 0.0     # 地面に対する速さ（+ = 右）
	# 狩りの仲間が近いと逃げる（右へ。拠点の進む向きと同じなので、足の遅い生物は追いつかれる）
	if hunted_by != null and is_instance_valid(hunted_by):
		if hunted_by.position.distance_to(position) < NOTICE_DIST:
			_fleeing = true
	else:
		hunted_by = null
	if _fleeing:
		ground_v = _flee_speed
		_facing = 1.0
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.2, 3.0)
			_wander = [-30.0, 0.0, 0.0, 25.0].pick_random()
		ground_v = _wander
		if absf(_wander) > 1.0:
			_facing = signf(_wander)
	position.x += (ground_v - game.scroll_speed) * delta
	# 逃げ切った・流れ去った
	if position.x > 1340.0 or position.x < -80.0:
		if hunted_by != null and is_instance_valid(hunted_by):
			hunted_by = null
		queue_free()
		return
	queue_redraw()


func is_moving() -> bool:
	return _fleeing or absf(_wander) > 1.0 or game.scroll_speed > 0.0


func _draw() -> void:
	var snap := ((position / 4.0).round() * 4.0) - position
	var sz: Vector2 = GameData.CREATURES[species]["size"]
	draw_rect(Rect2(snap + Vector2(-sz.x * 2.0, -4), Vector2(sz.x * 4.0, 6)), Color(0.35, 0.22, 0.1, 0.3))
	var fr := 2 if _fleeing and int(_t * 6.0) % 3 == 0 else int(_t * (12.0 if _fleeing else 5.0)) % 2
	var col := Color.WHITE if _flash <= 0.0 else Color(2.0, 2.0, 2.0)
	GameData.draw_creature(self, species, fr, snap, _facing, false, 1.0, col)
	var top := -sz.y * GameData.PX - 10.0
	if hp < max_hp:
		draw_rect(Rect2(snap + Vector2(-22, top - 6), Vector2(44, 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(snap + Vector2(-22, top - 6), Vector2(44.0 * clampf(hp / max_hp, 0.0, 1.0), 5)), Color("7be07b"))
	GameData.draw_text(self, snap + Vector2(0, top - 10), display_name() + ("（逃走中）" if _fleeing else ""),
			12, Color("e8f5d0"), 150.0)
