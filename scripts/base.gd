class_name MobileBase
extends Node2D
## 移動拠点（横から見た断面）。車体・車輪・斜路と、倉庫・加工設備・ベッドを持つ。
## 拠点自体は画面内に留まり、背景と資源が流れることで「進んでいる」ように見せる。
##
## 階: 上の階(加工室・寝室・操縦室) / 下の階(機関室・倉庫・搬入口)。ハシゴでつながる。

var game
var storage: BaseStorage
var processor: BaseProcessor
var beds: Array = [null, null, null]     # ベッドを使っている Worker
var max_hp := 100.0
var hp := 100.0                          # 戦闘用（現段階では未使用）
var hit_timer := 0.0
var fuel := GameData.FUEL_CAP            # 拠点の維持資源（燃料）
var refuel_reserved := false             # 補給に向かっている仲間がいる
var total_refuel := 0                    # 補給した回数（確認用）
## 耐久度（0〜100）。車体・走行装置・加工設備。
var parts := {GameData.Part.HULL: 100.0, GameData.Part.DRIVE: 100.0, GameData.Part.MACHINE: 100.0}
var repair_reserved := {}                # Part -> 修理に向かっている Worker
var total_repair := 0                    # 修理した回数（確認用）
var _wheel_t := 0.0
var _puffs: Array = []                   # 煙・砂ぼこり
var _puff_timer := 0.0
var _dust_timer := 0.0

const WHEEL_X := [296.0, 424.0, 664.0, 792.0]
const WHEEL_Y := 506.0
const STACK_X := [664.0, 696.0]


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	storage = BaseStorage.new()
	storage.position = Vector2(GameData.STORAGE_X, GameData.LO_Y)
	add_child(storage)
	processor = BaseProcessor.new()
	processor.position = Vector2(GameData.MACHINE_X, GameData.UP_Y)
	add_child(processor)


# ---- ベッド ----
func claim_bed(w) -> int:
	for i in beds.size():
		if beds[i] == null or not is_instance_valid(beds[i]):
			beds[i] = w
			return i
	return -1


func release_bed(w) -> void:
	for i in beds.size():
		if beds[i] == w:
			beds[i] = null


func bed_point(i: int) -> Vector2:
	return Vector2(GameData.BED_X[i], GameData.UP_Y)


func bed_index_of(w) -> int:
	return beds.find(w)


# ---- 燃料 ----
func engine_point() -> Vector2:
	return Vector2(GameData.ENGINE_X, GameData.LO_Y)


## 燃料を補給したほうがよいか（1個分入る空きがある）。
func wants_fuel(item: int) -> bool:
	return not refuel_reserved and fuel <= GameData.FUEL_CAP - GameData.FUEL_ITEMS.get(item, 0.0)


func add_fuel(item: int) -> void:
	fuel = minf(GameData.FUEL_CAP, fuel + GameData.FUEL_ITEMS.get(item, 0.0))
	total_refuel += 1


## 進んだ距離の分だけ燃料を使う。
func burn(distance: float) -> void:
	fuel = maxf(0.0, fuel - distance * GameData.FUEL_PER_PX * game.director.burn_mult())


func has_fuel() -> bool:
	return fuel > 0.0


# ---- 耐久度と修理 ----
func condition(part: int) -> float:
	return parts[part]


func wear(part: int, amount: float) -> void:
	# 天候の対処方針で傷みやすさが変わる（scripts/director.gd）
	parts[part] = maxf(0.0, parts[part] - amount * game.director.wear_mult(part))


## 時間と移動距離による傷み（加工設備の傷みは加工中に processor が入れる）。
func wear_by(delta: float, distance: float) -> void:
	wear(GameData.Part.HULL, GameData.HULL_WEAR_PER_SEC * delta)
	wear(GameData.Part.DRIVE, GameData.DRIVE_WEAR_PER_PX * distance)


## 修理が必要で、まだ誰も向かっていない部位のうち、いちばん傷んでいるもの（なければ -1）。
func part_to_repair() -> int:
	var best := -1
	var low := GameData.REPAIR_BELOW
	for p in parts:
		if repair_reserved.has(p):
			continue
		if parts[p] < low:
			low = parts[p]
			best = p
	return best


## 危険域（不調）の部位があるか
func has_critical_part() -> bool:
	for p in parts:
		if parts[p] < GameData.PART_BAD and not repair_reserved.has(p):
			return true
	return false


func part_point(part: int) -> Vector2:
	match part:
		GameData.Part.DRIVE:
			return Vector2(300.0, GameData.LO_Y)       # 機関室の奥（車軸と機関）
		GameData.Part.MACHINE:
			return Vector2(GameData.MACHINE_X + 60.0, GameData.UP_Y)
	return Vector2(760.0, GameData.LO_Y)               # 車体（搬入口まわりの壁）


func repair(part: int) -> void:
	parts[part] = minf(100.0, parts[part] + GameData.REPAIR_AMOUNT)
	repair_reserved.erase(part)
	total_repair += 1


## 走行装置が傷んでいると速度が出ない。
func speed_limit() -> float:
	if parts[GameData.Part.DRIVE] <= 0.0:
		return GameData.CRAWL_SPEED
	if parts[GameData.Part.DRIVE] < GameData.PART_BAD:
		return 40.0
	return 9999.0


# ---- 戦闘用（現段階では未使用） ----
func repair_point() -> Vector2:
	return Vector2(700.0, GameData.LO_Y)


func take_damage(amount: float) -> void:
	# 敵の攻撃は車体に当たる（車体の耐久度が0になると拠点は動かなくなる）
	parts[GameData.Part.HULL] = maxf(0.0, parts[GameData.Part.HULL] - amount)
	hit_timer = 0.25


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func _process(delta: float) -> void:
	hit_timer = maxf(0.0, hit_timer - delta)
	var spd: float = game.scroll_speed
	_wheel_t += spd * delta / 13.6
	# 排気の煙
	_puff_timer -= delta
	if _puff_timer <= 0.0 and has_fuel():   # 燃料切れのときは煙が出ない
		_puff_timer = 0.35
		for sx in STACK_X:
			_puffs.append({"p": Vector2(sx + 4.0, 200.0), "v": Vector2(-26.0 - spd * 0.4, -34.0), "t": 0.0,
					"life": 2.4, "s": 8.0, "smoke": true})
	# 車輪の砂ぼこり
	_dust_timer -= delta
	if _dust_timer <= 0.0 and spd > 5.0:
		_dust_timer = 0.16
		var wx: float = WHEEL_X[randi() % WHEEL_X.size()]
		_puffs.append({"p": Vector2(wx - 40.0, 556.0), "v": Vector2(-50.0 - spd, -14.0), "t": 0.0,
				"life": 0.9, "s": 8.0, "smoke": false})
	for pf in _puffs:
		pf["t"] += delta
		pf["p"] += pf["v"] * delta
	_puffs = _puffs.filter(func(pf): return pf["t"] < pf["life"])
	queue_redraw()


func _draw() -> void:
	var shake := Vector2(randf_range(-4, 4), 0) if hit_timer > 0.0 else Vector2.ZERO
	var bob := 0.0
	# 車輪
	var wheels := GameData.tex("res://assets/base/wheels.png")
	var f := int(_wheel_t) % 4
	for wx in WHEEL_X:
		draw_texture_rect_region(wheels, Rect2(Vector2(wx - 56.0, WHEEL_Y - 56.0 + bob), Vector2(112, 112)),
				Rect2(f * 30, 0, 28, 28))
	var hull := GameData.tex("res://assets/base/hull.png")
	draw_texture_rect(hull, Rect2(GameData.HULL_POS + shake + Vector2(0, bob), Vector2(hull.get_size()) * GameData.PX), false)
	# 斜路
	var ramp := GameData.tex("res://assets/base/ramp.png")
	draw_texture_rect(ramp, Rect2(Vector2(900, 482) + Vector2(0, bob), Vector2(ramp.get_size()) * GameData.PX), false)
	# 機関室の燃料計
	var gx := GameData.ENGINE_X - 44.0
	var gy := 392.0
	var r := fuel / GameData.FUEL_CAP
	var fc := Color("7be07b") if r > 0.5 else (Color("f0c040") if r > 0.2 else Color("e0533d"))
	draw_rect(Rect2(gx, gy, 88, 12), Color(0.08, 0.07, 0.06, 0.95))
	draw_rect(Rect2(gx + 4, gy + 4, 80.0 * r, 4), fc)
	GameData.draw_text(self, Vector2(GameData.ENGINE_X, gy - 4), "燃料" if has_fuel() else "燃料切れ", 12,
			Color("fde68a") if has_fuel() else Color("ff8a70"), 90.0)
	# 煙・砂ぼこり（ドットの格子に合わせた四角）
	for pf in _puffs:
		var k: float = pf["t"] / pf["life"]
		var s: float = snappedf(float(pf["s"]) * (1.0 + k * 1.6), 4.0)
		var p: Vector2 = (pf["p"] as Vector2).snapped(Vector2(4, 4))
		var col := Color(0.32, 0.3, 0.3, 0.55 * (1.0 - k)) if pf["smoke"] else Color(0.93, 0.78, 0.5, 0.6 * (1.0 - k))
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), col)
