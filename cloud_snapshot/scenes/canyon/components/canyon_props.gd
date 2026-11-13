extends Node2D
## Small readable scene parts: ore piles, rail fragments, fences, pipes and lamps.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	_draw_quarry_rails()
	_draw_relay_yard()
	_draw_lamps_and_fences()

func _draw_quarry_rails() -> void:
	var start := Vector2(116, 286)
	var finish := Vector2(393, 361)
	draw_line(start, finish, Color("302b35"), 8.0, false)
	draw_line(start + Vector2(0, -5), finish + Vector2(0, -5), Color("d09b5b"), 2.0, false)
	draw_line(start + Vector2(0, 5), finish + Vector2(0, 5), Color("d09b5b"), 2.0, false)
	for step in range(10):
		var p := start.lerp(finish, float(step) / 10.0)
		draw_line(p + Vector2(-3, -11), p + Vector2(3, 11), Color("744537"), 4.0, false)
	for p in [Vector2(185, 337), Vector2(230, 311), Vector2(282, 378), Vector2(343, 336)]:
		_crystal(p, 1.0)

func _draw_relay_yard() -> void:
	var p := Vector2(778, 409)
	draw_rect(Rect2(p - Vector2(28, 11), Vector2(56, 23)), Color("42333a"))
	draw_rect(Rect2(p - Vector2(24, 17), Vector2(48, 11)), Color("c27b43"))
	var offsets: Array[Vector2] = [Vector2(-42, 22), Vector2(-27, 29), Vector2(36, 18), Vector2(50, 26)]
	for offset in offsets:
		var c: Vector2 = p + offset
		draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), Color("6c4a3e"))
		draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 4)), Color("e0a154"))
		draw_line(c - Vector2(6, 1), c + Vector2(6, 9), Color("392f38"), 2.0, false)

func _draw_lamps_and_fences() -> void:
	for p in [Vector2(427, 338), Vector2(718, 364), Vector2(875, 306), Vector2(1095, 343), Vector2(1178, 523), Vector2(680, 595)]:
		draw_rect(Rect2(p - Vector2(2, 25), Vector2(4, 28)), Color("2d2933"))
		draw_rect(Rect2(p - Vector2(5, 29), Vector2(10, 8)), Color("65362f"))
		draw_circle(p - Vector2(0, 25), 5.0, Color("ffb94f"))
		draw_circle(p - Vector2(0, 25), 10.0, Color(1.0, 0.61, 0.22, 0.16))
	for p in [Vector2(826, 228), Vector2(859, 240), Vector2(892, 252), Vector2(925, 264), Vector2(958, 276), Vector2(991, 288)]:
		draw_rect(Rect2(p - Vector2(2, 14), Vector2(4, 23)), Color("372e36"))
		draw_line(p - Vector2(10, 7), p + Vector2(10, -3), Color("6d453b"), 3.0, false)

func _crystal(p: Vector2, size: float) -> void:
	var s := 11.0 * size
	_poly([p + Vector2(-s, 7), p + Vector2(-3, -s), p + Vector2(8, -2), p + Vector2(6, 10)], Color("087da8"))
	_poly([p + Vector2(-3, -s), p + Vector2(8, -2), p + Vector2(1, 2)], Color("6eeaff"))
	draw_rect(Rect2(p + Vector2(-2, -3), Vector2(4, 4)), Color("c4ffff"))

func _poly(points: Array, color: Color) -> void:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(point)
	draw_colored_polygon(packed, color)
