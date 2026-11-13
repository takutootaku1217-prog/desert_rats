class_name TravelHUD
extends CanvasLayer
const TravelLanePresentation = preload("res://scripts/travel_lane_presentation.gd")

## Travel overlay. Explicit hunting buttons forward requests to existing models;
## route, fuel, hull, cargo and crew remain in their existing models.

var game
var _card: PanelContainer
var _summary: Label
var _details: Label
var _toggle: Button
var _details_open := false
var _hunt_open := false
var _hunt_toggle: Button
var _hunt_panel: VBoxContainer
var _hunt_status: Label
var _hunt_note: Label
var _hunt_species: OptionButton
var _hunt_request: Button
var _hunt_cancel: Button
var _food_forecast: Label
var _cooking_reason: Label
var _cook: Button


func _ready() -> void:
	layer = 18
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UIKit.box(Color("192028", 0.90), Color("6f7a88"), 4, 7))
	_card.position = Vector2(16, 14)
	_card.custom_minimum_size = Vector2(396, 0)
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_card.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	_summary = UIKit.lbl("", 16, Color("fff4d0"))
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_summary)
	_toggle = UIKit.button("詳細", func(): set_details_open(not _details_open))
	_toggle.custom_minimum_size = Vector2(76, 30)
	top.add_child(_toggle)
	_details = UIKit.lbl("", 13, UIKit.C_DIM)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(370, 0)
	column.add_child(_details)
	_build_hunt_controls(column)
	_refresh()


func _build_hunt_controls(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)
	_hunt_toggle = UIKit.button("車上狩猟", func(): set_hunt_open(not _hunt_open))
	_hunt_toggle.custom_minimum_size = Vector2(104, 32)
	_hunt_toggle.icon = GameData.item_tex(GameData.Item.MEAT)
	_hunt_toggle.expand_icon = true
	_hunt_toggle.add_theme_constant_override("icon_max_width", 22)
	row.add_child(_hunt_toggle)
	_hunt_status = UIKit.lbl("依頼した生物だけを狩猟", 13, UIKit.C_DIM)
	_hunt_status.custom_minimum_size = Vector2(270, 0)
	_hunt_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hunt_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_hunt_status)
	_hunt_panel = VBoxContainer.new()
	column.add_child(_hunt_panel)
	_hunt_note = UIKit.lbl("検証用車上狩猟装置 • 射程460 / 同時回収1体", 12, UIKit.C_DIM)
	_hunt_panel.add_child(_hunt_note)
	var choices := HBoxContainer.new()
	_hunt_panel.add_child(choices)
	_hunt_species = OptionButton.new()
	_hunt_species.custom_minimum_size = Vector2(148, 32)
	for species in GameData.CREATURES:
		var index := _hunt_species.item_count
		_hunt_species.add_item(GameData.CREATURES[species]["name"])
		_hunt_species.set_item_metadata(index, species)
		if species == "dodo": _hunt_species.select(index)
	choices.add_child(_hunt_species)
	_hunt_request = UIKit.button("1体依頼", func():
		game.request_hunt(_selected_species(), 1)
		_refresh())
	choices.add_child(_hunt_request)
	_hunt_cancel = UIKit.button("取消", func():
		game.cancel_hunt(_selected_species())
		_refresh())
	choices.add_child(_hunt_cancel)
	_food_forecast = UIKit.lbl("", 12, UIKit.C_TEXT)
	_food_forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_food_forecast.custom_minimum_size = Vector2(370, 0)
	_hunt_panel.add_child(_food_forecast)
	_cooking_reason = UIKit.lbl("", 12, UIKit.C_DIM)
	_cooking_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cooking_reason.custom_minimum_size = Vector2(370, 0)
	_hunt_panel.add_child(_cooking_reason)
	_cook = UIKit.button("料理へ → 作成", func():
		game.craft_ui.open_entry("cook")
		_refresh())
	_cook.icon = GameData.item_tex(GameData.Item.FOOD)
	_cook.expand_icon = true
	_cook.add_theme_constant_override("icon_max_width", 22)
	_hunt_panel.add_child(_cook)


func _selected_species() -> String:
	return str(_hunt_species.get_item_metadata(_hunt_species.selected))


func set_hunt_open(open: bool) -> void:
	_hunt_open = open
	_refresh()


func _modal_open() -> bool:
	for owner in [game.policy, game.expedition_ui, game.build_ui, game.room_ui, game.inventory_ui, game.craft_ui, game.vehicle_ui, game.quarry_ui, game.save_ui, game.map_ui, game.town_ui, game.detail, game.crew_alerts]:
		if owner != null and owner._overlay != null and owner._overlay.visible:
			return true
	return false


func is_compact() -> bool:
	return TravelLanePresentation.active(game) and not _details_open and not _hunt_open


func details_open() -> bool:
	return _details_open


func set_details_open(open: bool) -> void:
	_details_open = open
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _card == null:
		return
	var active := TravelLanePresentation.active(game)
	_card.visible = active and not _modal_open() and not game.game_over
	if not active or game == null or game.base == null:
		return
	var destination := String(game.world.destination)
	if destination.is_empty():
		destination = "次の地点"
	var threat := TravelLanePresentation.composition(game) == "danger"
	var prefix := "警戒: " if threat else "移動: "
	_summary.text = "%s%s   燃料 %d/%d   耐久 %d" % [prefix, destination, int(game.base.fuel), int(GameData.FUEL_CAP), int(game.base.condition(GameData.Part.HULL))]
	_toggle.text = "閉じる" if _details_open else "詳細"
	_hunt_panel.visible = _hunt_open
	_hunt_toggle.text = "狩猟を閉じる" if _hunt_open else "車上狩猟"
	var controller = game.get("vehicle_hunt")
	if controller != null:
		var state: Dictionary = controller.status()
		_hunt_status.text = str(state.get("text", "依頼した生物だけを狩猟"))
		if state.get("stage", "") == "recovering":
			_hunt_status.text += " %d%%" % int(clampf(float(state.get("progress", 0.0)), 0.0, 1.0) * 100.0)
	_hunt_cancel.disabled = game.hunt_request_remaining(_selected_species()) <= 0
	_hunt_request.disabled = game.hunt_request_remaining(_selected_species()) > 0
	var recipe := GameData.recipe_by_id("cook")
	var station := GameData.recipe_station(recipe)
	var meat: int = game.storage.count_of(GameData.Item.MEAT)
	var food: int = game.storage.count_of(GameData.Item.FOOD)
	var meat_per_batch: int = int(recipe.get("in", {}).get(GameData.Item.MEAT, 0))
	var possible_food := floori(float(meat) / float(meat_per_batch)) * int(recipe.get("n", 0)) if meat_per_batch > 0 and recipe.get("out", -1) == GameData.Item.FOOD else 0
	_food_forecast.text = "倉庫: 生肉%d / 食料%d
肉の調理完了で食料 +%d の見込み（回収中・作業場は含まず）" % [meat, food, possible_food]
	_cooking_reason.text = (FacilityDB.name_of(station) + "が必要 → 作成で必要素材を確認") if not game.has_facility(station) else "生肉 → 食料。作成で材料と調理の依頼を確認"

	_details.visible = _details_open
	if _details_open:
		_details.text = "状態: %s  /  積載: %d/%d  /  仲間: %d/%d\n加工・料理・休憩は車内で継続。一般採取は停車後。車上狩猟は明示依頼のみ。" % [TravelLanePresentation.phase_label(game), int(game.storage.current_weight()), int(game.storage.max_weight()), int(game.workers.size()), int(game.workers.size())]
