extends Node2D
## Modular top planes and dark canyon sides.  These are deliberately separate
## from the walkable route declaration in the hub; session traversal stays sole
## authority for route safety.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	_draw_back_wall()
	_draw_ravine()
	_draw_foreground_rocks()

func _draw_back_wall() -> void:
	# High-density transparent cliff modules carry the major silhouettes.  These
	# small contact shadows/rock seams integrate them with the floor without
	# leaving the old giant flat purple wedges on screen.
	var contact_starts: Array[Vector2] = [Vector2(24, 210), Vector2(450, 204), Vector2(890, 220)]
	for start: Vector2 in contact_starts:
		for index in range(8):
			var p: Vector2 = start + Vector2(index * 35, (index % 3) * 5)
			draw_line(p, p + Vector2(24, 4), Color("69403f"), 3.0, false)
			draw_rect(Rect2(p + Vector2(5, 5), Vector2(5, 2)), Color("b36845"))

func _draw_ravine() -> void:
	# The diagonal bridge asset supplies both abutments.  Keep the void local to
	# that crossing so it reads as a short dry ravine instead of a giant polygon.
	_poly([
		Vector2(274, 326), Vector2(365, 275), Vector2(565, 420), Vector2(545, 490),
		Vector2(452, 510), Vector2(292, 378),
	], Color("4b3540"))
	_poly([
		Vector2(298, 331), Vector2(370, 296), Vector2(542, 425), Vector2(521, 470),
		Vector2(454, 486), Vector2(318, 371),
	], Color("75413e"))
	for p in [Vector2(340, 350), Vector2(390, 382), Vector2(440, 414), Vector2(488, 447)]:
		draw_rect(Rect2(p, Vector2(25, 5)), Color("c77848"))
		draw_rect(Rect2(p + Vector2(4, 7), Vector2(15, 3)), Color("382d3d"))

func _draw_foreground_rocks() -> void:
	for p in [Vector2(20, 576), Vector2(96, 628), Vector2(204, 650), Vector2(320, 673), Vector2(407, 640), Vector2(1140, 642), Vector2(1210, 578)]:
		_poly([p + Vector2(-24, 8), p + Vector2(-9, -17), p + Vector2(19, -10), p + Vector2(28, 13), p + Vector2(-4, 21)], Color("633b45"))
		_poly([p + Vector2(-14, -8), p + Vector2(-4, -23), p + Vector2(19, -10), p + Vector2(5, 0)], Color("b96945"))
		draw_rect(Rect2(p + Vector2(-5, -9), Vector2(9, 3)), Color("e5a45d"))

func _poly(points: Array, color: Color) -> void:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(point)
	draw_colored_polygon(packed, color)
