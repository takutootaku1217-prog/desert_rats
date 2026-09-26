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
		_draw_parts(["wall", "armor"], off)
	_draw_parts(["roof"], off)
	if base.view_exterior:
		draw_texture_rect(GameData.tex(ExteriorDB.RAMP_SHEET), Rect2(Vector2(900, 482), ArtSpec.px_size(ArtSpec.RAMP)), false)   # 斜路は車体に付いているので揺れない


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
