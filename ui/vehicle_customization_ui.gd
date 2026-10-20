class_name VehicleCustomizationUI
extends CanvasLayer
## Prototype loadout screen: equipment is immediately swappable so its combat
## and cargo effects can be evaluated before the crafting loop is finalized.

var game
var _overlay: Control
var _weight: Label
var _stats: Label
var _result: Label
var _rows := {}

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
	panel.position = Vector2(90, 24)
	panel.custom_minimum_size = Vector2(1100, 672)
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("202630"), Color("dca85f"), 3, 12))
	_overlay.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1060, 0)
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
	description.custom_minimum_size.x = 980
	box.add_child(description)
	var prototype_note := UIKit.lbl("戦闘フルスペック試作: 重量は表示・比較するが、制限なしで装備・行動できます。", 14, Color("b9f3b9"))
	box.add_child(prototype_note)
	_weight = UIKit.lbl("", 19, Color("cce8ff"))
	box.add_child(_weight)
	_stats = UIKit.lbl("", 15, Color("f9dda4"))
	box.add_child(_stats)
	for slot in ["chassis", "drive", "power", "armor", "primary", "secondary"]:
		_add_slot(box, slot)
	var actions := HBoxContainer.new()
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
	var preset := UIKit.button("�����t���X�y�b�N����", game.apply_vehicle_combat_preset)
	preset.custom_minimum_size = Vector2(230, 46)
	actions.add_child(preset)
	_result = UIKit.lbl("", 16, Color("b9f3b9"))
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size.x = 980
	box.add_child(_result)
	var future := UIKit.lbl("今回未実装：作業・支援装置の改造、車内部屋の建設／撤去の両入口。既存の部屋・設備は保持し、重量は0として扱います。", 13, UIKit.C_DIM)
	future.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	future.custom_minimum_size.x = 980
	box.add_child(future)
	_overlay.hide()

func _add_slot(parent: Control, slot: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("151a22"), Color("4d5c70"), 2, 6))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var label := UIKit.lbl("", 16)
	label.custom_minimum_size = Vector2(410, 76)
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
			button.disabled = current == candidate.id
			button.tooltip_text = candidate.desc + "\n試作段階では素材は表示のみで消費しません。"
			row.choices.add_child(button)

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
