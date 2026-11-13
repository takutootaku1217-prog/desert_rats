extends Node2D
## Activity tags read the live bridge state only.  They never update it.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var hub: CanyonRecoveryHub = get_parent() as CanyonRecoveryHub
	if hub == null or hub.session == null:
		return
	var plan := badge_plan()
	if plan.is_empty():
		return
	var actor: Dictionary = plan.actor
	var point: Vector2 = hub.presentation_point_for_actor(actor) if hub.has_method("presentation_point_for_actor") else hub.map_point(Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0))))
	var label: String = str(plan.label)
	var label_width: float = 31.0 if label.length() <= 2 else 42.0
	var tag_rect: Rect2 = Rect2(point + Vector2(-label_width * 0.5, -57), Vector2(label_width, 15))
	draw_rect(tag_rect.grow(1.0), Color("302936"))
	draw_rect(tag_rect, _badge_color(label))
	draw_string(ThemeDB.fallback_font, tag_rect.position + Vector2(4, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("fff0c6"))
	if not str(actor.get("wait_reason", "")).is_empty():
		draw_circle(point + Vector2(17, -34), 7.0, Color("56393a"))
		draw_string(ThemeDB.fallback_font, point + Vector2(14, -30), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("ffd26f"))

## Exactly one text badge is intentional: cargo is already visible on its
## matching CrewView, so the label only follows the most actionable worker.
func badge_plan() -> Dictionary:
	var hub: CanyonRecoveryHub = get_parent() as CanyonRecoveryHub
	if hub == null or hub.session == null:
		return {}
	var harvest_candidate := {}
	for actor_id in hub.session.actors:
		var actor: Dictionary = hub.session.actors[actor_id]
		if int(actor.get("carry_n", 0)) > 0:
			return {"actor": actor, "label": "運搬"}
		if str(actor.get("state", "")) == "harvesting" and harvest_candidate.is_empty():
			harvest_candidate = actor
	if not harvest_candidate.is_empty():
		return {"actor": harvest_candidate, "label": "採取"}
	return {}

func visible_badge_count() -> int:
	return 0 if badge_plan().is_empty() else 1

func _badge_color(label: String) -> Color:
	match label:
		"採取":
			return Color("237b88")
		"運搬":
			return Color("9a5a39")
		"護衛":
			return Color("87484a")
		"歩行":
			return Color("596a65")
		_:
			return Color("65554a")
