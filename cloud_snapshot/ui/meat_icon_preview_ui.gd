class_name MeatIconPreviewUI
extends CanvasLayer
## A QA-only display of all six supplied art variants.  It does not change
## inventory, crafting, nutrition, prices, or which item IDs are saved.

var game
var _overlay: Control


func _ready() -> void:
	layer = 26
	_overlay = Control.new()
	_overlay.name = "MeatIconPreviewOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close())
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "MeatIconPreviewPanel"
	panel.position = Vector2(212, 86)
	panel.custom_minimum_size = Vector2(856, 546)
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("1b1e24", 0.99), UIKit.C_ACCENT, 3, 16))
	_overlay.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UIKit.lbl("肉アイコン見本（検証用）", 24, UIKit.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button := UIKit.button("閉じる (Esc)", close)
	close_button.custom_minimum_size = Vector2(152, 40)
	top.add_child(close_button)
	var note := UIKit.lbl("通常表示は B。A/B/C は生肉・調理済みの表示候補のみで、品目・性能・レシピ・セーブは変わりません。", 15, UIKit.C_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(792, 48)
	root.add_child(note)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 16)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	for variant_id in variant_ids():
		grid.add_child(_variant_column(variant_id))


func _variant_column(variant_id: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "MeatVariant_%s" % variant_id.to_upper()
	column.custom_minimum_size = Vector2(252, 0)
	column.add_theme_constant_override("separation", 8)
	var heading := UIKit.lbl("%s%s" % [variant_id.to_upper(), "（通常）" if variant_id == GameData.DEFAULT_MEAT_ICON_VARIANT else ""], 20, UIKit.C_ACCENT if variant_id == GameData.DEFAULT_MEAT_ICON_VARIANT else UIKit.C_TEXT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	column.add_child(_icon_card(variant_id, false, "生肉"))
	column.add_child(_icon_card(variant_id, true, "調理済み"))
	return column


func _icon_card(variant_id: String, cooked: bool, label_text: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "MeatVariant_%s_%s" % [variant_id.to_upper(), "cooked" if cooked else "raw"]
	card.custom_minimum_size = Vector2(252, 164)
	card.add_theme_stylebox_override("panel", UIKit.box(Color("252a32"), Color("6f7a88"), 2, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.texture = GameData.meat_icon_variant_tex(variant_id, cooked)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(132, 132)
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	text.add_child(UIKit.lbl(label_text, 18, UIKit.C_TEXT))
	text.add_child(UIKit.lbl("%s_%s" % [variant_id.to_upper(), "COOKED" if cooked else "RAW"], 13, UIKit.C_DIM))
	return card


func variant_ids() -> Array:
	return GameData.meat_icon_variant_ids()


func icon_count() -> int:
	return variant_ids().size() * 2


func open() -> void:
	if game != null:
		game.close_other_panels(self)
	_overlay.show()


func close() -> void:
	if _overlay != null:
		_overlay.hide()


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F8]:
		close()
		get_viewport().set_input_as_handled()
