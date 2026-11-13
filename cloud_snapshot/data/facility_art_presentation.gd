class_name FacilityArtPresentation
extends RefCounted
## Display-only presentation contract for the approved moving-fortress room art.
##
## The normal room grid, facility spots, worker routes, selection and save data
## remain owned by Rooms / FacilityDB. This file deliberately contains only
## source crops and draw rectangles for the high-resolution bay layer.

const BACKWALL_PATH := "res://assets/fortress_moving/facilities/empty_bay_backwall_v1.png"
const BACKWALL_SIZE := Vector2(1697.0, 927.0)
const FURNITURE_PATHS := {
	"infirmary": "res://assets/fortress_moving/facilities/medical_furniture_idle_v1.png",
	"mess": "res://assets/fortress_moving/facilities/dining_furniture_idle_v1.png",
	"workshop": "res://assets/fortress_moving/facilities/workbench_furniture_idle_v1.png",
}

## These regions are the verified alpha > 127 bounds. Dining and workshop
## include harmless alpha=1 edge noise, so drawing the full source canvas would
## make fitting depend on transparent pixels rather than the actual furniture.
const FURNITURE_ALPHA_BOUNDS := {
	"infirmary": Rect2(94.0, 116.0, 1524.0, 689.0),
	"mess": Rect2(126.0, 122.0, 1412.0, 696.0),
	"workshop": Rect2(128.0, 210.0, 1389.0, 583.0),
}
const FURNITURE_SOURCE_SIZES := {
	"infirmary": Vector2(1697.0, 927.0),
	"mess": Vector2(1649.0, 954.0),
	"workshop": Vector2(1649.0, 954.0),
}

## Keep the existing bay trim and floor line visible. Furniture is bottom
## aligned immediately above this retained deck strip.
const SIDE_INSET := 5.0
const TOP_INSET := 4.0
const FLOOR_RETAIN_HEIGHT := 6.0
const WORKSHOP_REPLACED_FACILITIES := ["workbench", "parallel_bench", "supply_cache"]
static var _asset_availability: Dictionary = {}


static func handles_room(room_type: String) -> bool:
	return room_type == "empty" or FURNITURE_PATHS.has(room_type)


static func assets_available_for(room_type: String) -> bool:
	if _asset_availability.has(room_type):
		return bool(_asset_availability[room_type])
	var available := handles_room(room_type) and FileAccess.file_exists(BACKWALL_PATH)
	if available:
		var furniture_path := furniture_path_for(room_type)
		available = furniture_path == "" or FileAccess.file_exists(furniture_path)
	# Assets ship with the game and are not hot-swapped during play. Caching
	# avoids repeated filesystem probes from the per-frame draw paths while
	# retaining the missing-asset fallback at scene startup.
	_asset_availability[room_type] = available
	return available


static func furniture_path_for(room_type: String) -> String:
	return str(FURNITURE_PATHS.get(room_type, ""))


static func furniture_source_region(room_type: String) -> Rect2:
	return FURNITURE_ALPHA_BOUNDS.get(room_type, Rect2())


static func furniture_source_size(room_type: String) -> Vector2:
	return FURNITURE_SOURCE_SIZES.get(room_type, Vector2.ZERO)


## Return all rendering geometry in world display coordinates. It can be
## exercised by tests without a live scene and is never a logical room rect.
static func presentation_for(slot: String, room_type: String) -> Dictionary:
	if not assets_available_for(room_type):
		return {}
	var bay := LargeVehicleLayout.moving_interior_slot_rect(slot)
	if bay.size.x <= SIDE_INSET * 2.0 or bay.size.y <= TOP_INSET + FLOOR_RETAIN_HEIGHT:
		return {}
	var background_rect := Rect2(
		bay.position + Vector2(SIDE_INSET, TOP_INSET),
		Vector2(bay.size.x - SIDE_INSET * 2.0, bay.size.y - TOP_INSET)
	)
	var floor_strip := Rect2(
		Vector2(background_rect.position.x, background_rect.end.y - FLOOR_RETAIN_HEIGHT),
		Vector2(background_rect.size.x, FLOOR_RETAIN_HEIGHT)
	)
	var furniture_area := Rect2(background_rect.position, Vector2(background_rect.size.x, background_rect.size.y - FLOOR_RETAIN_HEIGHT))
	var furniture_source := furniture_source_region(room_type)
	var furniture_rect := _floor_fit(furniture_source.size, furniture_area) if furniture_source.size.x > 0.0 else Rect2()
	return {
		"slot": slot,
		"room_type": room_type,
		"bay": bay,
		"background_rect": background_rect,
		"background_source": _cover_source(BACKWALL_SIZE, background_rect.size),
		"floor_strip": floor_strip,
		"furniture_rect": furniture_rect,
		"furniture_source": furniture_source,
	}


static func replaces_legacy_facility(room_type: String, facility_id: String) -> bool:
	return room_type == "workshop" and facility_id in WORKSHOP_REPLACED_FACILITIES


static func replaces_processor(room_type: String) -> bool:
	return room_type == "workshop"


static func _floor_fit(source_size: Vector2, target: Rect2) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0 or target.size.x <= 0.0 or target.size.y <= 0.0:
		return Rect2()
	var scale := minf(target.size.x / source_size.x, target.size.y / source_size.y)
	var size := source_size * scale
	return Rect2(Vector2(target.position.x + (target.size.x - size.x) * 0.5, target.end.y - size.y), size)


## Crop the supplied opaque wall art to cover one bay without altering the
## original PNG. The crop is centred so each bay keeps the same wall material.
static func _cover_source(source_size: Vector2, target_size: Vector2) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0 or target_size.x <= 0.0 or target_size.y <= 0.0:
		return Rect2()
	var source_aspect := source_size.x / source_size.y
	var target_aspect := target_size.x / target_size.y
	if source_aspect > target_aspect:
		var width := source_size.y * target_aspect
		return Rect2(Vector2((source_size.x - width) * 0.5, 0.0), Vector2(width, source_size.y))
	var height := source_size.x / target_aspect
	return Rect2(Vector2(0.0, (source_size.y - height) * 0.5), Vector2(source_size.x, height))
