extends Node2D
## Front-facing vehicle/checkpoint parts are separate from their rear art so
## projected workers can pass behind a wheel, stair, fence, or cargo stack.

@export var piece := "base"

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if piece == "checkpoint":
		_draw_checkpoint_front()
	else:
		_draw_base_front()

func _draw_base_front() -> void:
	# The generated rear asset ends at y≈614.  These lower wheels, dock boxes,
	# tool cart, and rail intentionally sit above actor sprites at z=5.
	draw_rect(Rect2(805, 574, 254, 27), Color("2e2b33"))
	draw_rect(Rect2(816, 570, 233, 11), Color("b76f42"))
	draw_line(Vector2(820, 581), Vector2(1042, 581), Color("efaa5d"), 2.0, false)
	for wheel_x in [850.0, 916.0, 982.0]:
		draw_circle(Vector2(wheel_x, 598), 24.0, Color("292a31"))
		draw_circle(Vector2(wheel_x, 598), 17.0, Color("60433b"))
		draw_circle(Vector2(wheel_x, 598), 9.0, Color("d09b59"))
		draw_circle(Vector2(wheel_x, 598), 4.0, Color("3a3035"))
	for p in [Vector2(1075, 574), Vector2(1100, 582), Vector2(1123, 568), Vector2(1147, 579)]:
		draw_rect(Rect2(p - Vector2(9, 10), Vector2(18, 20)), Color("594038"))
		draw_rect(Rect2(p - Vector2(7, 8), Vector2(14, 4)), Color("df9b54"))
		draw_line(p - Vector2(6, -2), p + Vector2(6, 8), Color("302d35"), 2.0, false)
	draw_rect(Rect2(1047, 529, 5, 67), Color("292b32"))
	draw_rect(Rect2(1051, 537, 31, 4), Color("d49652"))
	draw_line(Vector2(1052, 542), Vector2(1080, 573), Color("d49652"), 3.0, false)

func _draw_checkpoint_front() -> void:
	for p in [Vector2(920, 295), Vector2(965, 302), Vector2(1010, 309), Vector2(1055, 316), Vector2(1100, 323)]:
		draw_rect(Rect2(p - Vector2(3, 20), Vector2(6, 27)), Color("2d2c34"))
		draw_line(p - Vector2(12, 12), p + Vector2(12, -2), Color("a66340"), 3.0, false)
	draw_rect(Rect2(956, 319, 144, 9), Color("3c3035"))
	draw_line(Vector2(962, 318), Vector2(1094, 325), Color("e1a254"), 2.0, false)
