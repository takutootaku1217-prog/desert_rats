class_name Enemy
extends Node2D
## 砂漠の敵（サソリ系）。右から現れ、拠点の前まで来て車体を攻撃する（襲撃の出来事。scripts/director.gd）。
## 種類は EventDB.ENEMIES（体力・被害・速さ・大きさ・色・戦利品）。戦闘担当の仲間が倒す。
## 車体の被害は「防備を固める」で減る。近くで戦っている仲間は疲れる。

var game
# 新しい地域生物のみ。旧セーブの襲撃は既存動作を保持。
var ecological := false
var present := true
var home_x := 0.0
var target_index := -1
var provoked_index := -1
var lost_for := 0.0
var search_left := 0.0
var peaceful_until := 0.0
const SIGHT := 200.0
const TERRITORY := 340.0
const LOSE_SECONDS := 4.0
const SEARCH_SECONDS := 5.0
const ECO_FIELDS := ["ecological","present","home_x","target_index","provoked_index","lost_for","search_left","peaceful_until"]
var world_id := ""
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
	hold_x = 700.0 if d.get("herbivore",false) else randf_range(560.0, 860.0) # 中立の固定個体は旧襲撃用の乱数を消費しない


## 旧来の呼び出し（体力だけ指定）。サソリとして扱う。
func setup(g, hp_value: float) -> void:
	setup_kind(g, "scorpion")
	max_hp = hp_value
	hp = hp_value


func display_name() -> String:
	return EventDB.ENEMIES[kind]["name"]


func take_damage(amount: float, attacker = null) -> void:
	if dead or amount<=0:
		return
	if ecological and attacker != null:
		provoked_index = game.workers.find(attacker)
		target_index = provoked_index
		peaceful_until = 0.0
	hp -= amount
	_flash = 0.1
	if hp <= 0.0:
		dead = true
		game.world.consume(self)
		game.on_enemy_killed(self)
		queue_free()


func is_attacking() -> bool:
	if ecological: return present and (target_index >= 0 or (behavior().begins_with("hull") and absf(position.x-hull_attack_point().x)<90.0))
	return position.x <= hold_x + 2.0


func _process(delta: float) -> void:
	if ecological:
		_tick_ecology(delta)
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if position.x > hold_x:
		position.x -= (game.scroll_speed + run_speed) * delta
	else:
		position.x = hold_x
		_atk_timer -= delta
		if _atk_timer <= 0.0:
			_atk_timer = 1.0
			game.base.take_damage(damage * game.director.hull_dmg_mult(), position.x)
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



func behavior() -> String:
	return EventDB.ENEMIES[kind].get("behavior","hull")

func territory() -> float:
	return 600.0 if behavior().begins_with("hull") else TERRITORY


func hull_attack_point() -> Vector2:
	return game.base.rear_engine_attack_point() if behavior()=="hull_rear" else GameData.RAMP_FOOT

func threatens(w) -> bool:
	if dead or is_queued_for_deletion(): return false
	if not ecological: return true
	return present and game.director.elapsed >= peaceful_until and (behavior() != "neutral" or provoked_index == game.workers.find(w))

func _visible_worker(w) -> bool:
	return not w.away and not w.down and w.floor_i==0 and w.position.distance_to(position)<=SIGHT and absf(w.position.x-home_x)<=territory()

func _tick_ecology(delta: float) -> void:
	visible = present
	if not present or dead:return
	_t+=delta;_flash=maxf(0.0,_flash-delta)
	# 地域内の生物は地域座標。鉱床への接近演出で域外へ流して消さない。
	if game.world.phase in ["travel","arriving","turning"]:
		home_x-=game.scroll_speed*delta
		position.x-=game.scroll_speed*delta
	var target = game.workers[target_index] if target_index>=0 and target_index<game.workers.size() else null
	if target!=null:
		if _visible_worker(target): lost_for=0.0
		else: lost_for+=delta
		if lost_for>=LOSE_SECONDS or absf(position.x-home_x)>territory():
			target_index=-1;target=null;provoked_index=-1;search_left=SEARCH_SECONDS;lost_for=0.0
	elif search_left>0:
		search_left=maxf(0.0,search_left-delta)
		if search_left==0: peaceful_until=game.director.elapsed+8.0
	elif game.director.elapsed>=peaceful_until:
		for i in game.workers.size():
			var w=game.workers[i]
			if _visible_worker(w) and (behavior()!="neutral" or provoked_index==i):
				target_index=i;target=w;break
	var destination:=Vector2(home_x,position.y)
	if target!=null:
		# 仲間が車内へ入ったらその位置へ潜り込まない。入口で短く探す。
		if target.floor_i==0:
			destination=Vector2(target.position.x,game.world.clamp_outdoor_y(target.position.y))
		else:
			destination.x=GameData.RAMP_FOOT.x
	elif behavior().begins_with("hull") and absf(hull_attack_point().x-position.x)<=SIGHT and absf(hull_attack_point().x-home_x)<=territory():
		destination.x=hull_attack_point().x
	elif search_left>0:
		destination.x=position.x
	if game.world.depth_strip_active():
		position=position.move_toward(destination,run_speed*delta)
	else:
		position.x=move_toward(position.x,destination.x,run_speed*delta)
	_atk_timer-=delta
	if _atk_timer<=0:
		_atk_timer=1.0
		if target!=null and target.floor_i==0 and position.distance_to(target.position)<float(EventDB.ENEMIES[kind].get("hit_reach",HIT_REACH)):
			CrewStatus.damage(target,CrewStatusDB.RAID_HIT_HP,CrewStatusDB.RAID_HIT_STRESS)
		elif behavior().begins_with("hull") and absf(position.x-hull_attack_point().x)<65.0:
			game.base.take_damage(damage*game.director.hull_dmg_mult(), position.x)
	queue_redraw()

func herbivore() -> bool:
	return EventDB.ENEMIES[kind].get("herbivore",false)

func body_rect() -> Rect2:
	if kind=="paraceratherium":return Rect2(-105,-218,180,218)
	if kind=="dune_horn":return Rect2(-100,-112,172,112)
	return Rect2(Vector2(-50,-52.0*body_scale-50.0),Vector2(100,100))

func hit_test(world_position: Vector2) -> bool:
	if herbivore():return body_rect().has_point(to_local(world_position))
	return (position+Vector2(0,-52.0*body_scale) if ecological else position).distance_to(world_position)<50.0

func _draw_herbivore() -> void:
	var body:=_body if _flash<=0 else Color.WHITE
	var dark:=body.darkened(0.25)
	var large:=kind=="paraceratherium"
	var top:float=-218.0 if large else -112.0
	draw_colored_polygon(_ellipse(Vector2(0,-3),75,10),Color(0,0,0,0.2))
	# 四肢は足元を接地。大型は長い首と柱状の脚、中型は襟と角。
	for i in 4:
		var x:float=-42.0+i*28.0
		var sway:float=sin(_t*5+i*1.8)*3 if target_index>=0 else 0.0
		draw_line(Vector2(x,-100 if large else -45),Vector2(x+sway,-6),dark if i%2==0 else body,14 if large else 12)
		draw_rect(Rect2(x+sway-8,-9,17,8),dark.darkened(0.3))
	draw_colored_polygon(_ellipse(Vector2(0,-117 if large else -62),65,43 if large else 31),body)
	draw_line(Vector2(59,-120 if large else -66),Vector2(72,-75 if large else -35),dark,5)
	if large:
		draw_colored_polygon(PackedVector2Array([Vector2(-55,-115),Vector2(-35,-126),Vector2(-55,-198),Vector2(-75,-204),Vector2(-72,-147)]),body)
		draw_colored_polygon(_ellipse(Vector2(-77,-202),26,14),body)
		draw_colored_polygon(PackedVector2Array([Vector2(-65,-209),Vector2(-60,-218),Vector2(-55,-207)]),dark)
		draw_circle(Vector2(-86,-204),3,Color("292b25"))
		draw_line(Vector2(-100,-197),Vector2(-91,-196),dark,2)
	else:
		draw_colored_polygon(_ellipse(Vector2(-43,-76),24,35),dark)
		draw_colored_polygon(_ellipse(Vector2(-65,-57),28,20),body)
		for at in [Vector2(-65,-70),Vector2(-52,-74)]:
			draw_colored_polygon(PackedVector2Array([at,at+Vector2(-17,-26),at+Vector2(9,-3)]),Color("eee0b8"))
		draw_colored_polygon(PackedVector2Array([Vector2(-88,-59),Vector2(-100,-72),Vector2(-80,-63)]),Color("eee0b8"))
		draw_circle(Vector2(-75,-61),3,Color("292b25"))
	if hp<max_hp:
		draw_rect(Rect2(-28,top-14,56,5),Color(0,0,0,0.7))
		draw_rect(Rect2(-28,top-14,56*clampf(hp/max_hp,0,1),5),Color("7be07b"))
	GameData.draw_text(self,Vector2(-10,top-23),display_name(),13,Color("e8f5d0"),210)
	GameData.draw_text(self,Vector2(-10,top-7),"反撃中" if target_index>=0 else "中立・攻撃すると反撃",11,Color("dfcfaa"),210)

func _draw() -> void:
	if herbivore():
		_draw_herbivore()
		return
	var body := _body if _flash <= 0.0 else Color("ffffff")
	var dark := body.darkened(0.35)
	draw_set_transform(Vector2(0,-52.0*body_scale) if ecological else Vector2.ZERO, 0.0, Vector2(body_scale, body_scale))
	draw_colored_polygon(_ellipse(Vector2(0, 14), 24, 6), Color(0, 0, 0, 0.2))
	# 脚
	for i in 4:
		var x := -14.0 + i * 9.0
		var sw := sin(_t * 14.0 + i * 1.6) * 4.0
		draw_line(Vector2(x, 6), Vector2(x - 6 + sw, 16), dark, 2.0)
		draw_line(Vector2(x, 6), Vector2(x + 6 - sw, 16), dark, 2.0)
	if ecological and behavior()=="hull":
		draw_rect(Rect2(-18,-12,36,8),dark)
	if ecological and behavior()=="neutral":
		draw_circle(Vector2(-32,-9),9,_body);draw_circle(Vector2(-32,11),9,_body)
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
	var top := (-92.0 if ecological else -40.0) * body_scale
	draw_rect(Rect2(-22, top, 44, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-22, top, 44.0 * clampf(hp / max_hp, 0.0, 1.0), 6), Color("e0533d"))
	GameData.draw_text(self, Vector2(0, top - 6), display_name(), 12, Color("ffb4a8"), 90.0)


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
