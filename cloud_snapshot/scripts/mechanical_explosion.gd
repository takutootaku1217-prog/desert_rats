class_name MechanicalExplosion
extends Node2D
## Visual only. Code-generated animated atlas; no damage, save or global RNG changes.
## Origin is the ground contact. Never rotate the whole effect: smoke rises vertically.
const ATLAS = preload("res://assets/effects/mechanical_explosion.png")
const FRAME_SIZE := Vector2(320, 180)
const ORIGIN := Vector2(160, 124)
const FPS := 30.0
const FRAME_COUNT := 54
const MAX_ACTIVE := 8
var elapsed := 0.0
var pixel_scale := 2.0

static func spawn(parent: Node, origin: Vector2, display_scale: float = 2.0) -> MechanicalExplosion:
	var active: Array[Node] = []
	for node in parent.get_children():
		if node is MechanicalExplosion:
			active.append(node)
	while active.size() >= MAX_ACTIVE:
		var oldest: Node = active.pop_front()
		parent.remove_child(oldest)
		oldest.queue_free()
	var effect := MechanicalExplosion.new()
	effect.position = origin
	effect.pixel_scale = clampf(display_scale, 0.5, 4.0)
	parent.add_child(effect)
	return effect

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3

func frame_index() -> int:
	return mini(int(floor(elapsed * FPS + 0.00001)), FRAME_COUNT - 1)

func advance(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	if elapsed >= FRAME_COUNT / FPS:
		queue_free()
	queue_redraw()

func _process(delta: float) -> void:
	advance(delta)

func _draw() -> void:
	var f := frame_index()
	var source := Rect2(Vector2(f % 9, floori(float(f) / 9.0)) * FRAME_SIZE, FRAME_SIZE)
	draw_texture_rect_region(ATLAS, Rect2(-ORIGIN * pixel_scale, FRAME_SIZE * pixel_scale), source)
