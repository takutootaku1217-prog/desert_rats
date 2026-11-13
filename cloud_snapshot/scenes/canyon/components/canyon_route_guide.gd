class_name CanyonRouteGuide
extends Control
## A read-only, top-down comparison guide for the fixed-entry C quarry.
## It visualizes the live session route state but cannot issue engineering,
## movement, gathering, or combat commands.

var session
var snapshot: Dictionary = {}
var _title: Label
var _state: Label
var _legend: Label

func configure(p_session) -> void:
 session = p_session
 refresh_from_session()

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_STOP
 _title = Label.new()
 _title.position = Vector2(12, 6)
 _title.text = "C鉱山 経路案内図（比較・表示のみ）"
 _title.add_theme_font_size_override("font_size", 14)
 add_child(_title)
 _state = Label.new()
 _state.position = Vector2(12, 26)
 _state.add_theme_font_size_override("font_size", 11)
 add_child(_state)
 _legend = Label.new()
 _legend.position = Vector2(12, 224)
 _legend.add_theme_font_size_override("font_size", 10)
 _legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _legend.custom_minimum_size = Vector2(332, 34)
 _legend.text = "黄: 背負い専用段差  青: 手押し車迂回  赤/緑: 瓦礫・開通後近道\n入口は固定。案内図から作業命令は出しません。"
 add_child(_legend)
 refresh_from_session()

func refresh_from_session() -> void:
 if session != null and session.has_method("mine_path_guide_snapshot"):
  snapshot = Dictionary(session.call("mine_path_guide_snapshot")).duplicate(true)
 else:
  snapshot = {}
 if _state != null:
  var rubble := str(snapshot.get("rubble", "unavailable"))
  _state.text = "入口固定 / 段差: 背負いのみ / 手押し車: %s / 瓦礫: %s" % [str(snapshot.get("cart_route", "-")), rubble]
 queue_redraw()

func _draw() -> void:
 draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
 if snapshot.is_empty():
  return
 var entry := _guide_point("entry")
 var resource := _guide_point("resource")
 var step := _guide_point("backpack_step_point")
 var detour_entry := _guide_point("cart_detour_entry")
 var detour := _guide_point("cart_detour_point")
 var shortcut := _guide_point("cart_shortcut_point")
 draw_line(entry, step, Color("e5cb62"), 5.0, true)
 draw_line(step, resource, Color("e5cb62"), 5.0, true)
 draw_line(entry, detour_entry, Color("5b9fd8"), 6.0, true)
 draw_line(detour_entry, detour, Color("5b9fd8"), 6.0, true)
 draw_line(detour, resource, Color("5b9fd8"), 6.0, true)
 var shortcut_color := Color("86d67b") if bool(snapshot.get("cart_shortcut", false)) else Color("bb5c52")
 draw_line(entry, shortcut, shortcut_color, 6.0, true)
 draw_line(shortcut, resource, shortcut_color, 6.0, true)
 draw_circle(entry, 9.0, Color("e8d79a"))
 draw_circle(resource, 9.0, Color("9bc7d8"))
 draw_circle(step, 7.0, Color("e5cb62"))
 draw_circle(shortcut, 12.0, shortcut_color)
 draw_circle(detour, 7.0, Color("5b9fd8"))
 draw_string(ThemeDB.fallback_font, entry + Vector2(-16, 25), "ENTRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("fff3cf"))
 draw_string(ThemeDB.fallback_font, resource + Vector2(-16, -15), "ORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d7efff"))
 draw_string(ThemeDB.fallback_font, shortcut + Vector2(-24, 25), "RUBBLE" if not bool(snapshot.get("cart_shortcut", false)) else "SHORTCUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("fff0df"))

func _guide_point(key: String) -> Vector2:
 var raw: Array = Array(snapshot.get(key, []))
 if raw.size() < 2:
  return Vector2.ZERO
 var world := Vector2(float(raw[0]), float(raw[1]))
 var width := maxf(1.0, size.x - 40.0)
 var height := maxf(1.0, size.y - 102.0)
 return Vector2(20.0 + (world.x - 100.0) / 1000.0 * width, 52.0 + (world.y - 170.0) / 560.0 * height)

func _panel_style() -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = Color(0.06, 0.09, 0.10, 0.94)
 style.border_color = Color("9ac8bc")
 style.set_border_width_all(2)
 style.set_corner_radius_all(8)
 return style
