extends SceneTree
## Display-only contract for the six supplied meat icons.  Existing MEAT/FOOD
## item IDs, recipes, nutrition, and saved inventory remain unchanged.

const VARIANT_ROOT := "res://assets/resources/meat_icon_variants"
const LEGACY_ROOT := "res://assets/resources/legacy_meat_icons_v3_2"
const IDS := ["a", "b", "c"]

var main
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _fresh() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 20261102)
	root.add_child(main)
	await process_frame


func _path(id: String, cooked: bool) -> String:
	return "%s/%s_%s.png" % [VARIANT_ROOT, id, "cooked" if cooked else "raw"]


func _same_bytes(left: String, right: String) -> bool:
	var a := FileAccess.get_file_as_bytes(left)
	var b := FileAccess.get_file_as_bytes(right)
	return not a.is_empty() and a == b


func _check_image(path: String, title: String) -> void:
	_check(FileAccess.file_exists(path), "%s is registered as a project asset" % title)
	if not FileAccess.file_exists(path):
		return
	var image := Image.new()
	_check(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK, "%s loads as PNG" % title)
	_check(image.get_width() == 48 and image.get_height() == 48, "%s remains 48x48" % title)
	_check(image.get_format() == Image.FORMAT_RGBA8, "%s remains RGBA" % title)


func _run() -> void:
	for id in IDS:
		_check_image(_path(id, false), "%s raw" % id.to_upper())
		_check_image(_path(id, true), "%s cooked" % id.to_upper())
	_check(FileAccess.file_exists("%s/item_meat_pre_meat_icons_v1.png" % LEGACY_ROOT), "pre-change raw icon is retained")
	_check(FileAccess.file_exists("%s/item_ration_pre_meat_icons_v1.png" % LEGACY_ROOT), "pre-change cooked icon is retained")
	_check(_same_bytes("res://assets/resources/item_meat.png", _path("b", false)), "normal MEAT uses supplied B raw pixels")
	_check(_same_bytes("res://assets/resources/item_ration.png", _path("b", true)), "normal FOOD uses supplied B cooked pixels")
	var cook: Dictionary = GameData.recipe_by_id("cook")
	_check(cook.get("in", {}).get(GameData.Item.MEAT, 0) == 1 and int(cook.get("out", -1)) == GameData.Item.FOOD and int(cook.get("n", 0)) == 2, "MEAT-to-FOOD recipe remains unchanged")
	await _fresh()
	var preview = main.get("meat_icon_preview")
	_check(preview != null, "Main creates the non-gameplay meat-icon preview")
	if preview != null:
		_check(preview.has_method("variant_ids") and preview.variant_ids() == IDS, "preview exposes A, B, C in fixed order")
		_check(preview.has_method("icon_count") and preview.icon_count() == 6, "preview registers all six raw/cooked images")
		var fuel_before: float = main.base.fuel
		var inventory_before: Dictionary = main.storage.inventory.counts.duplicate(true)
		preview.open()
		_check(preview.is_open(), "preview opens as a modal verification display")
		preview.close()
		_check(not preview.is_open(), "preview closes without gameplay action")
		_check(is_equal_approx(main.base.fuel, fuel_before) and main.storage.inventory.counts == inventory_before, "opening preview does not mutate fuel or inventory")
	var nav = main.navigation
	_check(nav.has_method("open_meat_icon_preview"), "Other menu exposes the verification display")
	if nav.has_method("open_meat_icon_preview"):
		nav.open_meat_icon_preview()
		_check(preview != null and preview.is_open(), "navigation opens the verification display")
		if preview != null:
			preview.close()
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("== meat icon variants: %s ==" % ("passed" if failures == 0 else "%d failures" % failures))
	quit(1 if failures else 0)
