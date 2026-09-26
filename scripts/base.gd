class_name MobileBase
extends Node2D
## 移動拠点。車体・車輪・斜路と、倉庫・加工設備・ベッドを持つ。内装（横から見た断面）と外装（外から見た車体）の
## 2つの見え方があり、どちらも「同じ拠点のデータ」（部屋の配置・建てた設備・耐久・燃料・走行距離）を読んで描く。
## 拠点自体は画面内に留まり、背景と資源が流れることで「進んでいる」ように見せる。
##
## 階: 上の階(加工室・寝室・操縦室) / 下の階(機関室・倉庫・搬入口)。ハシゴでつながる。
## 部屋の配置（4つの区画に何の部屋があるか）は Main.room_layout（data/rooms.gd）。部屋を変えると apply_layout で
## 加工設備・倉庫の位置が移り、設備（ワークベンチ・ベッド）の置き場所も facility_spots で新しい区画に追従する。
## 見え方の切り替え（外装 ⇄ 内装）は scripts/base_view.gd。ここは view_exterior の旗と、描き分けだけを持つ。
## 描く仕組み: このノードが車輪・煙・砂ぼこり（どちらの画面でも同じ）と、内装の断面図を描く。外装（車体・窓・外装パーツ）は
## 子の BaseExterior（scripts/base_exterior.gd）が描く。

var game
var storage: BaseStorage
var processor: BaseProcessor
var beds: Array = [null, null, null]     # ベッドを使っている Worker（建てていない区画は使えない。built["bed"]）
var built := {}                          # 建てた設備 {id: 建てた区画の番号の配列}（data/facilities.gd。建設は Main.finish_build）
var built_at := {}                       # "id:区画" -> 完成した時刻（ミリ秒。完成の演出用）
var room_built_at := {}                  # 区画 -> 部屋ができた時刻（ミリ秒。完成の演出用）
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
var view_exterior := false               # true なら外から見る（外装）。false なら中を見る（内装の断面図）。切り替えは BaseView
var exterior: BaseExterior               # 外装の描画（子）
var body_bob := 0.0                      # 外装で、走っているときに車体が小さく跳ねる量（px。内装では 0）
var _shake := Vector2.ZERO               # 被弾で揺れる量（このフレーム。内装・外装で同じ値を使う）
var _body_t := 0.0
var _wheel_t := 0.0
var _puffs: Array = []                   # 煙・砂ぼこり
var _puff_timer := 0.0
var _dust_timer := 0.0

const WHEEL_X := [296.0, 424.0, 664.0, 792.0]
const WHEEL_Y := 506.0
const STACK_X := [664.0, 696.0]
const HULL_H := ArtSpec.HULL.y           # 車体の高さ（ユニット。内装の断面図と外装の車体で同じ）


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	storage = BaseStorage.new()
	add_child(storage)
	processor = BaseProcessor.new()
	add_child(processor)
	exterior = BaseExterior.new()                # 加工設備・倉庫のあとに作る（外装は、それらより手前に描く）
	exterior.base = self
	add_child(exterior)
	apply_layout()


# ---- 見え方（外装 ⇄ 内装）。同じ拠点を、外から見るか中から見るかだけの違い（ゲームの状態は変わらない） ----
## 外装（外から見る）にする／内装（断面図）に戻す。加工設備・倉庫は内装の物なので、外装では描かない（位置・中身はそのまま）。
func set_view_exterior(on: bool) -> void:
	view_exterior = on
	processor.visible = not on
	storage.visible = not on
	queue_redraw()


## 車体の揺れ（被弾・走行中の小さな跳ね）。外装の描画と共通。
func body_offset() -> Vector2:
	return _shake + Vector2(0.0, body_bob)


## 車体の中（外から見たとき、姿が見えない場所）か。斜路の上・地面にいる仲間は外にいる。斜路の上の端（搬入口の入口）から中。
func is_inside(p: Vector2) -> bool:
	return p.x < GameData.RAMP_TOP.x + 1.0 and p.y < GameData.HULL_POS.y + float(HULL_H * GameData.PX)


# ---- 部屋（区画。data/rooms.gd） ----
## 部屋の配置に合わせて、加工設備と倉庫を、それぞれの部屋の位置へ置く（部屋を建てた・移したときに呼ぶ）。
## 仲間の行き先は毎フレーム位置から決めているので、途中でも新しい場所へ向かい直す。
func apply_layout() -> void:
	var lay: Dictionary = game.room_layout
	var ws := Rooms.slot_of(lay, "workshop")
	processor.position = Rooms.processor_pos(ws) if ws != "" else Vector2(GameData.MACHINE_X, GameData.UP_Y)
	var ss := Rooms.slot_of(lay, "storage")
	storage.position = Rooms.storage_pos(ss) if ss != "" else Vector2(GameData.STORAGE_X, GameData.LO_Y)


## 部屋の種類の区画（なければ ""）
func room_slot(rtype: String) -> String:
	return Rooms.slot_of(game.room_layout, rtype)


# ---- 設備（建設。data/facilities.gd） ----
## 設備 id の置き場所（足元のワールド座標）。その設備を置く部屋がいまある区画の位置（部屋がなければ空）。
func facility_spots(id: String) -> Array:
	var slot := room_slot(FacilityDB.room_of(id))
	return FacilityDB.spots_in(id, slot) if slot != "" else []


## 設備 id が拠点にあるか。"" は手作業（加工設備）＝いつでもある。
func has_facility(id: String) -> bool:
	return id == "" or not built.get(id, []).is_empty()


func facility_count(id: String) -> int:
	return built.get(id, []).size()


## 設備を1つ建てる（いちばん若い空き区画へ）。建てた区画の番号を返す。もう建てられなければ -1。
func add_facility(id: String, silent := false) -> int:
	var slots: Array = built.get(id, [])
	if slots.size() >= FacilityDB.max_of(id):
		return -1
	var slot := 0
	while slot in slots:
		slot += 1
	slots.append(slot)
	built[id] = slots
	if not silent:
		built_at["%s:%d" % [id, slot]] = Time.get_ticks_msec()
	return slot


## 全設備を建てる（自己診断・放置比較ツール用。FacilityDB.start_all）
func grant_all() -> void:
	for id in FacilityDB.ids():
		while add_facility(id, true) >= 0:
			pass


## 設備で作業する場所（足元）。建てていなければ加工設備の位置。
func facility_point(id: String) -> Vector2:
	var spots: Array = facility_spots(id)
	if built.get(id, []).is_empty() or spots.is_empty():
		return processor.global_position
	return spots[built[id][0]]


# ---- ベッド ----
func claim_bed(w) -> int:
	var slots: Array = built.get("bed", [])
	for i in beds.size():
		if i in slots and (beds[i] == null or not is_instance_valid(beds[i])):
			beds[i] = w
			return i
	return -1


func release_bed(w) -> void:
	for i in beds.size():
		if beds[i] == w:
			beds[i] = null


func bed_point(i: int) -> Vector2:
	var spots: Array = facility_spots("bed")
	return spots[i] if i >= 0 and i < spots.size() else processor.global_position


func bed_index_of(w) -> int:
	return beds.find(w)


# ---- 燃料 ----
## 燃料を入れる場所。機関室があればその炉の口、なければ搬入口（機関室は必須ではないため）。
func engine_point() -> Vector2:
	var s := room_slot("engine")
	return Rooms.engine_pos(s) if s != "" else Rooms.fallback_fuel_pos()


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
			return processor.position + Vector2(60.0, 0.0)
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
	_shake = Vector2(randf_range(-4, 4), 0) if hit_timer > 0.0 else Vector2.ZERO
	# 外装: 走っているとき、車体（車輪は地面のまま）が段差で1ドットぶん跳ねる。内装は仲間の足元が動かないよう跳ねない
	if view_exterior and spd > 5.0:
		_body_t += delta * spd / 60.0
		body_bob = -float(GameData.PX) if sin(_body_t * 2.1) + sin(_body_t * 3.7 + 1.0) > 1.3 else 0.0
	else:
		body_bob = 0.0
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


## 4つの区画の部屋の絵を、車体（初期配置の部屋が焼き込まれた hull.png）の上に重ねて描く。
## 部屋を変えるとここが変わる（重ね絵は assets/base/rooms/<系統>/。初期配置と同じ部屋でも同じ絵を重ねるので継ぎ目は出ない）。
func _draw_rooms(off: Vector2) -> void:
	var now := Time.get_ticks_msec()
	for slot in Rooms.SLOT_ORDER:
		var rtype: String = game.room_layout.get(slot, "empty")
		var rect: Rect2 = Rooms.overlay_rect(slot)
		draw_texture_rect(GameData.tex(Rooms.overlay_path(slot, rtype)), Rect2(rect.position + off, rect.size), false)
		var age := float(now - int(room_built_at.get(slot, -99999))) / 1000.0
		if age < 1.6:                                                    # 部屋ができた合図
			GameData.draw_text(self, rect.position + off + Vector2(rect.size.x / 2.0, 76.0 - age * 14.0), "%sができた!" % Rooms.TYPES[rtype]["name"],
					16, Color("fde68a"), 160.0)


## 建てた設備（ワークベンチ・ベッド）を車体の上に重ねて描く。まだ建てていない置き場所は、
## 建てられるなら薄く（建てる予定なら少し濃く点滅）、必要設備がなければ何も描かない。作業中のワークベンチは槌を振る。
func _draw_facilities(off: Vector2) -> void:
	var now := Time.get_ticks_msec()
	for id in FacilityDB.ids():
		var d: Dictionary = FacilityDB.def(id)
		var slots: Array = built.get(id, [])
		var pend: int = game.build_pending(id)
		var fs: Vector2i = d["frame"]
		var size := ArtSpec.px_size(fs)                                  # 画面上の大きさ（基準の大きさ×UNIT_PX。絵の細かさに依存しない）
		var spec := FacilityDB.sprite_spec(id)                           # 絵の切り出しの基準（コマの大きさ・間隔・コマ数）
		var spots: Array = facility_spots(id)                            # 設備を置く部屋がある区画の位置（部屋を移すと追従する）
		for i in spots.size():
			var spot: Vector2 = spots[i]
			var tex := GameData.tex(FacilityDB.sprite_path(id, i))
			var rect := Rect2(spot + off - Vector2(size.x / 2.0, size.y), size)
			var frame := 0
			var col := Color.WHITE
			if i in slots:
				if d["station"] and processor.is_active_at(id):
					frame = 1 + (int(now / 200.0) % 2)
				var age := float(now - int(built_at.get("%s:%d" % [id, i], -99999))) / 1000.0
				if age < 1.6:                                  # 完成の合図
					GameData.draw_text(self, spot + off + Vector2(0, -size.y - 8.0 - age * 14.0), "完成!", 14, Color("fde68a"), 80.0)
			else:
				if not game.facility_unlocked(id):
					continue
				col = Color(1, 1, 1, 0.13)
				if i - slots.size() < pend:
					col.a = 0.32 + 0.12 * sin(now / 260.0)
			draw_texture_rect_region(tex, rect, ArtSpec.frame_src(tex, spec, frame), col)


func _draw() -> void:
	var shake := _shake
	var bob := 0.0                                  # 内装は跳ねない。外装の車体の跳ねは body_bob（BaseExterior が使う）
	# 車輪（どちらの画面でも同じ。外装の車体は、この上に重ねて描かれる）
	var wheels := GameData.tex("res://assets/base/wheels.png")
	var wspec := ArtSpec.WHEELS
	var wsize := ArtSpec.px_size(wspec["cell"])                     # 画面上の大きさ（絵の細かさに依存しない）
	var f := int(_wheel_t) % int(wspec["frames"])
	for wx in WHEEL_X:
		draw_texture_rect_region(wheels, Rect2(Vector2(wx, WHEEL_Y + bob) - wsize / 2.0, wsize), ArtSpec.frame_src(wheels, wspec, f))
	if not view_exterior:
		# 内装: 横から見た断面（車体・部屋・斜路・設備・燃料計）。屋根の上の物は、子の BaseExterior が重ねて描く
		var hull := GameData.tex("res://assets/base/hull.png")
		draw_texture_rect(hull, Rect2(GameData.HULL_POS + shake + Vector2(0, bob), ArtSpec.px_size(ArtSpec.HULL)), false)
		_draw_rooms(shake + Vector2(0, bob))
		# 斜路
		var ramp := GameData.tex("res://assets/base/ramp.png")
		draw_texture_rect(ramp, Rect2(Vector2(900, 482) + Vector2(0, bob), ArtSpec.px_size(ArtSpec.RAMP)), false)
		_draw_facilities(shake + Vector2(0, bob))
		# 燃料計（燃料を入れる場所の上。機関室があればその炉、なければ搬入口）
		var ex := engine_point().x
		var gx := ex - 44.0
		var gy := 392.0
		var r := fuel / GameData.FUEL_CAP
		var fc := Color("7be07b") if r > 0.5 else (Color("f0c040") if r > 0.2 else Color("e0533d"))
		draw_rect(Rect2(gx, gy, 88, 12), Color(0.08, 0.07, 0.06, 0.95))
		draw_rect(Rect2(gx + 4, gy + 4, 80.0 * r, 4), fc)
		GameData.draw_text(self, Vector2(ex, gy - 4), "燃料" if has_fuel() else "燃料切れ", 12,
				Color("fde68a") if has_fuel() else Color("ff8a70"), 90.0)
	# 煙・砂ぼこり（論理ユニットの格子に合わせた四角。絵ではなく描画で作るので、絵の細かさとは関係がない）
	var grid := float(ArtSpec.UNIT_PX)
	for pf in _puffs:
		var k: float = pf["t"] / pf["life"]
		var s: float = snappedf(float(pf["s"]) * (1.0 + k * 1.6), grid)
		var p: Vector2 = (pf["p"] as Vector2).snapped(Vector2(grid, grid))
		var col := Color(0.32, 0.3, 0.3, 0.55 * (1.0 - k)) if pf["smoke"] else Color(0.93, 0.78, 0.5, 0.6 * (1.0 - k))
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), col)
