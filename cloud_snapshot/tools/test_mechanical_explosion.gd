extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
	else:
		print("PASS: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := "res://scripts/mechanical_explosion.gd"
	check(ResourceLoader.exists(path), "mechanical explosion component exists")
	if not ResourceLoader.exists(path):
		quit(1)
		return
	var script = load(path)
	var holder := Node2D.new()
	root.add_child(holder)
	var fx = script.spawn(holder, Vector2(100, 200))
	check(fx != null and fx.position == Vector2(100, 200), "spawn uses local origin")
	check(fx.frame_index() == 0, "starts at flash frame")
	fx.advance(0.3)
	check(fx.frame_index() == 9, "time advances actual frames")
	fx.advance(-1.0)
	check(fx.frame_index() == 9, "negative time cannot rewind")
	for i in 20:
		script.spawn(holder, Vector2.ZERO)
	check(holder.get_child_count() <= 8, "burst pool is bounded")
	var last = holder.get_child(holder.get_child_count()-1)
	last.advance(2.0)
	check(last.is_queued_for_deletion(), "effect frees after lifetime")
	await process_frame
	holder.queue_free()
	await process_frame
	quit(1 if failures else 0)
