class_name BaseExterior
extends Node2D
## 外装の描画（外から見た移動拠点）。MobileBase の子で、絵の元は data/exterior.gd（パーツの表）と assets/base/exterior/。
##
## 外装と内装は同じ拠点（MobileBase）を、外から見るか中から見るかの違いだけ。ここは状態を持たず、拠点のデータを読んで描くだけ:
##   窓の色 ← 区画の部屋の種類（Main.room_layout） / 燃料の口 ← 機関室の位置 / 工具かけ・物干し・屋根の布 ← 建てた設備
##   荷物・アンテナ・タンク・装甲 ← 走行距離（ゲームの進み具合）
## 描く順番: 窓のガラス → 車体（窓の穴が透けてガラスが見える）→ 壁の物 → 装甲 → 屋根の上の物 → 斜路。
## 内装の断面図を見ているときは、屋根の上の物（layer "roof"）だけを、断面図の上に重ねて描く（同じ車両の屋根）。
## 車輪・排気の煙・砂ぼこりは、どちらの画面でも MobileBase が描く。
##
## 座標は論理ユニット（data/art_spec.gd）で持ち、画面の大きさ = ユニット × UNIT_PX。絵の細かさ（1ユニットのドット数）には依存しない
## （絵の切り出しだけが、絵ごとの細かさを使う）。絵を高精細にしても、ここは変えなくてよい。

const U := ArtSpec.UNIT_PX

var base                 # MobileBase
var _t := 0.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if base == null or base.game == null:
		return
	var off: Vector2 = base.body_offset()
	if base.view_exterior:
		_draw_glass(off)
		draw_texture_rect(ExteriorDB.body_tex(), Rect2(GameData.HULL_POS + off, ArtSpec.px_size(ArtSpec.HULL)), false)
		if str(base.vehicle_loadout.get("chassis", "medium")) != "medium":
			_draw_large_vehicle_layers(off)
		_draw_parts(["wall", "armor"], off)
	_draw_parts(["roof"], off)
	if base.view_exterior:
		draw_texture_rect(GameData.tex(ExteriorDB.RAMP_SHEET), Rect2(ExteriorDB.RAMP_POS, ArtSpec.px_size(ArtSpec.RAMP)), false)   # 斜路は車体に付いているので揺れない


## 論理ユニット座標（車体の絵の左上から）→ ワールド座標
func _world(unit: Vector2, off: Vector2) -> Vector2:
	return GameData.HULL_POS + off + unit * float(U)


## 窓のガラス。車体の絵は窓の部分が透明で、その後ろに、部屋の種類の色を塗る（外から見て、どんな部屋か分かる）。
## 加工室は作業中に明るさが揺れ、機関室の炉の色はゆらめく。運転席の窓は空の映り込み。
func _draw_glass(off: Vector2) -> void:
	var win_tex := ExteriorDB.windows_tex()
	for slot in Rooms.SLOT_ORDER:
		var rtype: String = base.game.room_layout.get(slot, "empty")
		var col: Color = ExteriorDB.glass_color(rtype)
		if rtype == "workshop" and base.processor.is_active():
			col = col.lerp(Color.WHITE, 0.16 + 0.12 * sin(_t * 9.0))
		elif rtype == "engine":
			col = col.lerp(Color("ffd060"), 0.08 + 0.08 * sin(_t * 3.0))
		var r := ExteriorDB.window_rect(slot)
		var rect := Rect2(_world(Vector2(r.position), off), Vector2(r.size) * float(U))
		draw_rect(rect, col)
		draw_texture_rect_region(win_tex, rect, ExteriorDB.window_frame("win" if r.size.y >= 10 else "win_low"))
	var c := ExteriorDB.cab_rect()
	var crect := Rect2(_world(Vector2(c.position), off), Vector2(c.size) * float(U))
	draw_rect(Rect2(crect.position, Vector2(crect.size.x, crect.size.y * 0.5)), ExteriorDB.GLASS_COCKPIT.lightened(0.12))
	draw_rect(Rect2(crect.position + Vector2(0, crect.size.y * 0.5), Vector2(crect.size.x, crect.size.y * 0.5)), ExteriorDB.GLASS_COCKPIT)
	draw_texture_rect_region(win_tex, crect, ExteriorDB.window_frame("cab_side"))


## いま見える外装パーツ（layers の層だけ）を描く。何が見えるかは ExteriorDB.visible_parts（走行距離・建てた設備・部屋の配置）。
func _draw_parts(layers: Array, off: Vector2) -> void:
	var engine_unit := -1.0
	if base.room_slot("engine") != "":
		engine_unit = (base.engine_point().x - GameData.HULL_POS.x) / float(U)
	for e in ExteriorDB.visible_parts(base.game, layers):
		var part: Dictionary = e["part"]
		var at := ExteriorDB.at_of(part, e["slot"], engine_unit)
		draw_texture_rect_region(ExteriorDB.sheet_tex(part["sheet"]),
				Rect2(_world(Vector2(at), off), Vector2(ExteriorDB.frame_units(part)) * float(U)), Rect2(ExteriorDB.frame_of(part)))


func _draw_large_vehicle_layers(off: Vector2) -> void:
	## Large chassis remains composed from independently readable exterior parts.
	## The interior stays authoritative for rooms/workers; this layer only supplies
	## the exterior shell, running gear, garage, and roof weapons.
	var state: Dictionary = base.vehicle_loadout
	var frame_col := Color("b57a32") if state.chassis == "large" else Color("c18d3e")
	var armor_col := Color("7d4228") if state.armor == "plate" else (Color("9a562b") if state.armor == "composite" else Color("a35f2f"))
	var outline := Color("2a1b18")
	var shadow := Color("593425")
	var glow := Color("ffb34f")
	var origin := GameData.HULL_POS + off
	var upper := Rect2(origin + Vector2(44, -114), Vector2(712, 184))
	# stepped roofline and riveted main shell
	var hull := PackedVector2Array([upper.position + Vector2(0, 178), upper.position + Vector2(0, 32), upper.position + Vector2(56, 32), upper.position + Vector2(56, 4), upper.position + Vector2(420, 4), upper.position + Vector2(420, 22), upper.position + Vector2(622, 22), upper.position + Vector2(712, 64), upper.position + Vector2(712, 178)])
	draw_colored_polygon(hull, outline)
	var inner := PackedVector2Array([upper.position + Vector2(8, 170), upper.position + Vector2(8, 40), upper.position + Vector2(64, 40), upper.position + Vector2(64, 12), upper.position + Vector2(412, 12), upper.position + Vector2(412, 30), upper.position + Vector2(616, 30), upper.position + Vector2(704, 68), upper.position + Vector2(704, 170)])
	draw_colored_polygon(inner, frame_col)
	for floor in [0, 1, 2]:
		var y: float = upper.position.y + 10 + floor * 56
		draw_line(Vector2(upper.position.x + 10, y + 48), Vector2(upper.end.x - 10, y + 48), shadow, 5.0)
		draw_line(Vector2(upper.position.x + 12, y + 45), Vector2(upper.end.x - 12, y + 45), Color("e0a24a"), 1.0)
		for column in 6:
			var panel := Rect2(Vector2(upper.position.x + 22 + column * 110, y + 10), Vector2(76, 31))
			draw_rect(panel.grow(2), outline)
			draw_rect(panel, armor_col.darkened(0.12 + 0.03 * ((column + floor) % 2)))
			# Small, recessed armored slits only: exterior must not read as a lit interior.
			if (floor == 0 and column == 1) or (floor == 1 and column == 4) or (floor == 2 and column == 2):
				var slit := Rect2(panel.position + Vector2(16, 11), Vector2(38, 7))
				draw_rect(slit.grow(2), Color("1c1716"))
				draw_rect(slit, glow.darkened(0.35))
				for bolt_y in [panel.position.y + 5.0, panel.end.y - 5.0]:
					draw_circle(Vector2(panel.position.x + 6, bolt_y), 2.0, Color("edb15d"))
					draw_circle(Vector2(panel.end.x - 6, bolt_y), 2.0, Color("edb15d"))
	# structural ribs, pipes and hanging lower garage frame
	for x in [upper.position.x + 90.0, upper.position.x + 198.0, upper.position.x + 418.0, upper.position.x + 550.0, upper.position.x + 665.0]:
		draw_line(Vector2(x, upper.position.y + 42), Vector2(x, upper.end.y - 10), shadow, 5.0)
		draw_line(Vector2(x + 2, upper.position.y + 46), Vector2(x + 2, upper.end.y - 14), Color("e2a248"), 1.0)
	var garage := Rect2(upper.position + Vector2(530, 116), Vector2(154, 54))
	draw_rect(garage.grow(4), outline)
	draw_rect(garage, Color("402821"))
	draw_rect(Rect2(garage.position + Vector2(12, 12), Vector2(102, 24)), Color("ab6030"))
	draw_circle(garage.position + Vector2(34, 39), 10, outline)
	draw_circle(garage.position + Vector2(34, 39), 6, Color("8c8574"))
	draw_circle(garage.position + Vector2(96, 39), 10, outline)
	draw_circle(garage.position + Vector2(96, 39), 6, Color("8c8574"))
	draw_line(upper.position + Vector2(28, 94), upper.position + Vector2(28, 156), Color("523126"), 8.0)
	draw_line(upper.position + Vector2(28, 94), upper.position + Vector2(70, 94), Color("523126"), 8.0)
	if state.armor != "none":
		for floor in 3:
			var left_plate := Rect2(Vector2(upper.position.x - 10, upper.position.y + floor * 56 + 12), Vector2(18, 38))
			var right_plate := Rect2(Vector2(upper.end.x - 8, upper.position.y + floor * 56 + 18), Vector2(18, 34))
			draw_rect(left_plate, outline)
			draw_rect(left_plate.grow(-3), armor_col)
			draw_rect(right_plate, outline)
			draw_rect(right_plate.grow(-3), armor_col)
	if state.primary != "none":
		var mount := Vector2(upper.position.x + 426, upper.position.y - 18)
		draw_circle(mount + Vector2(28, 18), 27, outline)
		draw_circle(mount + Vector2(28, 18), 21, Color("7c4a2c"))
		var recoil := sin(_t * 11.0) * 2.0 if int(state.get("ammo", 0)) > 0 else 0.0
		draw_rect(Rect2(mount + Vector2(40 - recoil, 11), Vector2(142, 14)), outline)
		draw_rect(Rect2(mount + Vector2(44 - recoil, 14), Vector2(138, 8)), Color("d7a64d"))
		draw_circle(mount + Vector2(20, 17), 5, Color("f6c263"))
	if state.secondary != "none":
		for x in [140.0, 270.0, 610.0]:
			var mount2 := Vector2(upper.position.x + x, upper.position.y - 12)
			draw_circle(mount2 + Vector2(15, 14), 17, outline)
			draw_circle(mount2 + Vector2(15, 14), 12, Color("71432a"))
			draw_rect(Rect2(mount2 + Vector2(22, 4), Vector2(60, 5)), Color("e1af55"))
			draw_rect(Rect2(mount2 + Vector2(22, 13), Vector2(60, 5)), Color("e1af55"))
