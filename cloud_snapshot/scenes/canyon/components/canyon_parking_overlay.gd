class_name CanyonParkingOverlay
extends Node2D
## Read-only feedback for the vertical-slice parking flow.  It deliberately
## does not move the existing mobile-base art or alter collision/navigation.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var hub = get_parent()
	if hub == null or not "session" in hub:
		return
	var route_session = hub.session
	var vertical: bool = route_session != null and route_session.has_method("is_vertical_slice") and bool(route_session.call("is_vertical_slice"))
	var mine_path: bool = route_session != null and route_session.has_method("is_mine_path_engineering") and bool(route_session.call("is_mine_path_engineering"))
	if not vertical and not mine_path:
		return
	var relay: Vector2 = hub.map_point(RecoveryRouteConnectionSession.MINE_PATH_RUBBLE if mine_path else RecoveryRouteConnectionSession.RELAY).round()
	var access: String = str(route_session.state_summary().get("intermediate_access", "blocked"))
	if access != "cleared":
		_draw_small_barricade(relay, access == "clearing")

func _draw_small_barricade(relay: Vector2, clearing: bool) -> void:
	var p := relay + Vector2(-18, -12)
	var body := Color("856244") if not clearing else Color("bf8743")
	draw_rect(Rect2(p - Vector2(17, 7), Vector2(34, 14)), body, true)
	draw_rect(Rect2(p - Vector2(18, 8), Vector2(36, 16)), Color("2c2520"), false, 1.0)
	draw_line(p + Vector2(-14, -5), p + Vector2(-4, 5), Color("f1c45a"), 3.0)
	draw_line(p + Vector2(-3, -5), p + Vector2(7, 5), Color("f1c45a"), 3.0)
	draw_line(p + Vector2(8, -5), p + Vector2(15, 3), Color("f1c45a"), 3.0)
