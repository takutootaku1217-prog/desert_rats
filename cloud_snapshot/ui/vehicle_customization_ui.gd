class_name VehicleCustomizationUI
extends CanvasLayer
## Shared armor uses a paid, confirmed transaction. Other slots remain prototypes.

var game
var _overlay: Control
var _weight: Label
var _stats: Label
var _result: Label
var _rows := {}
var _armor_dialog: ConfirmationDialog
var _armor_token := -1

func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.06, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = -12
	panel.offset_bottom = -12
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("202630"), Color("dca85f"), 3, 12))
	_overlay.add_child(panel)
	# This control is outside the scroll content, so it remains reachable on
	# a narrow or high-DPI game window.
	var pinned_close := UIKit.button("閉じる (V / Esc)", close)
	pinned_close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pinned_close.offset_left = -188
	pinned_close.offset_top = 20
	pinned_close.offset_right = -20
	pinned_close.offset_bottom = 64
	pinned_close.custom_minimum_size = Vector2(168, 44)
	pinned_close.z_index = 2
	_overlay.add_child(pinned_close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := UIKit.lbl("大型移動拠点・改造試作", 28, Color("ffe4a3"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button := UIKit.button("閉じる (V / Esc)", close)
	close_button.custom_minimum_size = Vector2(170, 42)
	top.add_child(close_button)
	var description := UIKit.lbl("大型シャーシ（縦増築3層の試作表示）。武装・装甲の数値と重量は仮データです。部屋・設備そのものは積載に含めません。", 15, UIKit.C_DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(description)
	var prototype_note := UIKit.lbl("装甲：F→装備でキットを製作し、倉庫収納後に比較・確定。その他の外装は素材非消費の試作です。", 14, Color("b9f3b9"))
	prototype_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(prototype_note)
	_weight = UIKit.lbl("", 19, Color("cce8ff"))
	box.add_child(_weight)
	_stats = UIKit.lbl("", 15, Color("f9dda4"))
	box.add_child(_stats)
	for slot in ["armor", "chassis", "drive", "power", "primary", "secondary"]:
		_add_slot(box, slot)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var primary := UIKit.button("主砲を撃つ", func(): game.fire_vehicle_weapon("primary"))
	primary.custom_minimum_size = Vector2(170, 46)
	actions.add_child(primary)
	var secondary := UIKit.button("補助武装を撃つ", func(): game.fire_vehicle_weapon("secondary"))
	secondary.custom_minimum_size = Vector2(190, 46)
	actions.add_child(secondary)
	var spawn := UIKit.button("試験用の既存敵を呼ぶ", game.spawn_vehicle_test_enemy)
	spawn.custom_minimum_size = Vector2(230, 46)
	actions.add_child(spawn)
	var ammo := UIKit.button("試験弾薬 +6", game.refill_vehicle_ammo)
	ammo.custom_minimum_size = Vector2(165, 46)
	actions.add_child(ammo)
	var preset := UIKit.button("戦闘フルスペック試作", game.apply_vehicle_combat_preset)
	preset.custom_minimum_size = Vector2(230, 46)
	actions.add_child(preset)
	_result = UIKit.lbl("", 16, Color("b9f3b9"))
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_result)
	var future := UIKit.lbl("今回未実装：作業・支援装置の改造、車内部屋の建設／撤去の両入口。既存の部屋・設備は保持し、重量は0として扱います。", 13, UIKit.C_DIM)
	future.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	future.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(future)
	_armor_dialog = ConfirmationDialog.new()
	_armor_dialog.title = "左右共通の装甲を比較"
	_armor_dialog.ok_button_text = "キット1個を消費して装着"
	_armor_dialog.cancel_button_text = "取消（消費なし）"
	_armor_dialog.dialog_autowrap = true
	_armor_dialog.dialog_hide_on_ok = false
	_armor_dialog.exclusive = true
	_armor_dialog.confirmed.connect(_confirm_armor)
	_armor_dialog.canceled.connect(_cancel_armor)
	_armor_dialog.close_requested.connect(_cancel_armor)
	add_child(_armor_dialog)
	_overlay.hide()

func _add_slot(parent: Control, slot: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("151a22"), Color("4d5c70"), 2, 6))
	parent.add_child(panel)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var label := UIKit.lbl("", 16)
	label.custom_minimum_size = Vector2(0, 42)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(choices)
	_rows[slot] = {"label":label, "choices":choices}

func open() -> void:
	game.close_other_panels(self)
	_overlay.show()
	refresh()

func close() -> void:
	_cancel_armor()
	if _overlay != null:
		_overlay.hide()

func is_open() -> bool:
	return _overlay != null and _overlay.visible

func refresh() -> void:
	if game == null or game.base == null:
		return
	var state: Dictionary = game.base.vehicle_loadout
	var st = game.storage
	_weight.text = "積載（共通）  使用 %d / 上限 %d　残り %d　｜　外装部品 %d　貨物・装備等 %d" % [st.current_weight(), st.max_weight(), st.max_weight() - st.current_weight(), game.base.vehicle_equipment_weight(), st.current_weight() - game.base.vehicle_equipment_weight()]
	_stats.text = "防御 %d（敵1発 %.0f → 実被害 %.0f）　試験弾薬 %d　｜　装甲の軽減と被弾ログは実際の攻撃へ適用されます。" % [int(game.base.vehicle_defense()), game.vehicle_test_enemy_damage(), game.base.damage_after_armor(game.vehicle_test_enemy_damage()), int(state.ammo)]
	_result.text = str(state.get("last_note", ""))
	for slot in ["chassis", "drive", "power", "armor", "primary", "secondary"]:
		var row: Dictionary = _rows[slot]
		var current := str(state[slot])
		row.label.text = _slot_title(slot, current)
		for child in row.choices.get_children():
			child.queue_free()
		for part in VehicleLoadout.PARTS[slot]:
			var candidate: Dictionary = part
			if slot == "armor":
				var armor_text := "%s ｜ 重量%d / 防御%d" % [candidate.name, candidate.weight, candidate.defense]
				if candidate.id == current: armor_text += "（装着中）"
				elif candidate.id == "plate" and current == "none": armor_text += " ｜ キット1個で比較・装着"
				else: armor_text += "（取り外し・交換は未対応）"
				var armor_button := UIKit.button(armor_text, func(): preview_armor(candidate.id))
				armor_button.custom_minimum_size = Vector2(0,44)
				armor_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				armor_button.disabled = candidate.id != "plate" or current != "none"
				armor_button.tooltip_text = "左右共通。材料: 鉄3・皮2（仮）。F→装備で製作。確定まで在庫・装備を変更しません。"
				row.choices.add_child(armor_button)
				continue
			var preview: Dictionary = game.base.preview_loadout(slot, candidate.id)
			var text := "%s　重量 %d（変更後 %d / 残り %d / %+d）　素材: %s" % [candidate.name, int(candidate.weight), int(preview.used), int(preview.left), int(preview.delta), _materials(candidate.materials)]
			if slot == "armor" or slot == "chassis":
				text += "　防御 %d / 実被害 %.0f" % [int(candidate.get("defense", 0)), float(preview.damage_after)]
			elif slot == "primary" or slot == "secondary":
				text += "　ダメージ %d / 弾薬 %d" % [int(candidate.get("damage", 0)), int(candidate.get("ammo", 0))]
			elif slot == "drive":
				text += "　速度上限 %d / 燃料 %.2f倍" % [int(candidate.get("speed", 0)), float(candidate.get("fuel_mult", 1.0))]
			else:
				text += "　速度 %+d / 燃料 %.2f倍" % [int(candidate.get("speed_bonus", 0)), float(candidate.get("fuel_mult", 1.0))]
			var button := UIKit.button(text, func(): game.equip_vehicle_part(slot, candidate.id))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = Vector2(0, 44)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.disabled = current == candidate.id
			button.tooltip_text = candidate.desc + "\n試作段階では素材は表示のみで消費しません。"
			row.choices.add_child(button)

func preview_armor(id: String) -> void:
	var quote: Dictionary = game.base.begin_armor_preview(id)
	_armor_token = int(quote.token)
	_armor_dialog.dialog_text = ("装甲：外装なし → 鉄板装甲（左右共通）\n積載 %d → %d / 上限%d（予約%d・残り%d）\n防御 %.0f → %.0f ／ 敵1発8 → 被害%.0f\n確定時：倉庫のキット1個を消費（素材は製作時に消費済み）。\n取消は消費なし。装着によるHP・燃料・耐久回復はありません。\n%s" % [quote.before_weight,quote.used,quote.capacity,quote.reserved,quote.left,quote.before_defense,quote.defense,quote.damage_after,"" if quote.ok else quote.reason])
	_armor_dialog.get_ok_button().disabled = not quote.ok
	_armor_dialog.popup_centered(Vector2i(780,340))
	_armor_dialog.get_cancel_button().grab_focus()

func _cancel_armor() -> void:
	if game != null and game.base != null: game.base.cancel_armor_preview()
	_armor_token = -1
	if _armor_dialog != null: _armor_dialog.hide()

func _confirm_armor() -> void:
	var succeeded: bool = game.base.confirm_armor_install(_armor_token)
	_armor_token = -1
	refresh()
	if succeeded:
		_armor_dialog.hide()
	else:
		_armor_dialog.dialog_text = "在庫・予約・装備が変わったため、装着を取り消しました。\nキットは消費していません。\n取消で戻り、もう一度比較してください。"
		_armor_dialog.get_ok_button().disabled = true
		_armor_dialog.get_cancel_button().grab_focus()

func _slot_title(slot: String, current: String) -> String:
	var heading: String = str({"chassis":"車体", "drive":"走行装置", "power":"動力", "primary":"武装：主砲", "secondary":"武装：補助", "armor":"装甲・外装"}.get(slot, slot))
	return "%s: %s" % [heading, VehicleLoadout.part(slot, current).get("name", "未装備")]

func _materials(cost: Dictionary) -> String:
	if cost.is_empty():
		return "なし"
	var names := {"iron":"鉄", "hide":"皮"}
	var values := []
	for id in cost:
		values.append("%s×%d" % [names.get(id, id), cost[id]])
	return " ".join(values)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			if is_open(): close()
			else: open()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_open():
			close()
			get_viewport().set_input_as_handled()
