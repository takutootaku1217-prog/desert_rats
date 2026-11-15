extends Node2D
const Explosion = preload("res://scripts/mechanical_explosion.gd")
var clock := 0.0
var spawned := false
var effects: Node2D
func _ready() -> void:
	effects = Node2D.new()
	add_child(effects)
	var label := Label.new()
	label.text = "MECHANICAL EXPLOSION  /  Click or Space to replay\nFlash > rolling flame > tumbling bolts / gears / armor > rising smoke\nVisual-only preview. No save or gameplay changes."
	label.position = Vector2(24, 24)
	add_child(label)
func _process(delta: float) -> void:
	clock += delta
	if clock > 0.5 and not spawned:
		Explosion.spawn(effects, Vector2(640, 500), 4.0)
		spawned = true
	queue_redraw()
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Explosion.spawn(effects, get_global_mouse_position(), 3.0)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		Explosion.spawn(effects, Vector2(640, 500), 4.0)
func _draw() -> void:
	draw_rect(Rect2(0,0,1280,720), Color("181622"))
	draw_rect(Rect2(0,460,1280,260), Color("302a3c"))
	for i in 32:
		draw_rect(Rect2(i*43, 520+(i%4)*34, 22, 4),Color("494054"))
	# Static reference silhouettes demonstrate overlap and pixel scale.
	for x in [330,950]:
		draw_rect(Rect2(x,430,24,34),Color("b7b66c"))
		draw_rect(Rect2(x+3,412,18,20),Color("ead0ac"))
		draw_rect(Rect2(x,464,8,16),Color("806356"))
		draw_rect(Rect2(x+16,464,8,16),Color("806356"))
