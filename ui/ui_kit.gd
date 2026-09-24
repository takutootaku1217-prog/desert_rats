class_name UIKit
extends RefCounted
## 管理画面などで共通に使う、ボタン・ラベル・枠の部品。見た目をここに一本化する。

const C_TEXT := Color("ffe9b0")
const C_DIM := Color("9aa3b2")
const C_ACCENT := Color("f2c14e")


static func box(bg: Color, edge: Color, border: int = 2, margin: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border)
	sb.border_color = edge
	sb.set_corner_radius_all(0)          # ドット絵に合わせて角丸にしない
	sb.anti_aliasing = false
	sb.set_content_margin_all(margin)
	return sb


static func style(b: Button, selected: bool) -> void:
	var edge := C_ACCENT if selected else Color("636b7a")
	b.add_theme_stylebox_override("normal", box(Color("4b5262") if selected else Color("3a3f4a"), edge, 3 if selected else 2))
	b.add_theme_stylebox_override("hover", box(Color("4b5262"), C_ACCENT))
	b.add_theme_stylebox_override("pressed", box(Color("22252b"), C_ACCENT))
	b.add_theme_stylebox_override("disabled", box(Color("25282e"), Color("3a3f4a")))


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", GameData.font())
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color("6b7280"))
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	style(b, false)
	b.pressed.connect(cb)
	return b


static func lbl(text: String, size: int = 15, color: Color = C_TEXT, minw: float = 0.0) -> Label:
	var l := GameData.make_label(text, size, color)
	if minw > 0.0:
		l.custom_minimum_size = Vector2(minw, 0)
	return l


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
