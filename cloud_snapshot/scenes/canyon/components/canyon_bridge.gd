extends Node2D
## The bridge art itself is a non-rotated quarter-view asset.  This script only
## paints short approach ruts beneath it, keeping entry/exit tied to session
## waypoints without inventing a second traversal system.

# These are calibrated from the visible bright plank centreline of the
# non-rotated art, not from the sprite's geometric centre.  Its texture-space
# plank line is approximately (80,45)→(240,125), with this sprite at (415,385).
const NEAR_SLOPE_FOOT := Vector2(590, 475)
const NEAR_LANDING := Vector2(543, 426)
const DECK_NEAR_BOARD := Vector2(507, 408)
const DECK_FAR_BOARD := Vector2(323, 316)
const FAR_LANDING := Vector2(311, 310)
const PRESENTATION_DECK_HALF_WIDTH := 12.0
const PRESENTATION_APPROACH_HALF_WIDTH := 18.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var hub = get_parent()
	if hub == null:
		return
	var path: Array = presentation_path(hub)
	if path.size() < 7:
		return
	for segment_index in [0, 1, 2, 4, 5]:
		_draw_approach(path[segment_index] as Vector2, path[segment_index + 1] as Vector2)
	_draw_approach_surface_marks(approach_surface_marks(hub))

## One shared display-only path for bridge art, direct-demo actor projection,
## ruts, and evidence checks.  It never mutates the session route.
func presentation_path(hub) -> Array:
	var join: Vector2 = hub.single_demo_bridge_join() if hub.has_method("single_demo_bridge_join") else hub.map_point(RecoveryRouteConnectionSession.BYPASS)
	var resource: Vector2 = hub.map_point(RecoveryRouteConnectionSession.RESOURCE)
	return [join, NEAR_SLOPE_FOOT, NEAR_LANDING, DECK_NEAR_BOARD, DECK_FAR_BOARD, FAR_LANDING, resource]

func approach_surface_marks(hub) -> Array[Dictionary]:
	var path: Array = presentation_path(hub)
	if path.size() < 7:
		return []
	var marks: Array[Dictionary] = []
	for segment_index in [0, 1, 2]:
		_append_approach_surface_marks(marks, path[segment_index] as Vector2, path[segment_index + 1] as Vector2, segment_index)
	for segment_index in [4, 5]:
		_append_approach_surface_marks(marks, path[segment_index] as Vector2, path[segment_index + 1] as Vector2, segment_index)
	return marks

## This is narrower than the collision/navigation deck: it is only the
## visible boardwalk centerline used to select a truthful runtime screenshot,
## rather than a rocky abutment edge where a worker would look ungrounded.
func presentation_deck_contains(screen_point: Vector2) -> bool:
	return _segment_band_contains(screen_point, DECK_NEAR_BOARD, DECK_FAR_BOARD, PRESENTATION_DECK_HALF_WIDTH)

## A narrow painted-ground band, deliberately independent from the broader
## collision polygon.  It keeps visual proof from accepting foreground rock.
func presentation_path_contains(screen_point: Vector2, hub = null) -> bool:
	return str(surface_sample(screen_point, hub).get("region", "outside")) != "outside"

## Return the visible ground region independently from collision.  Capture
## writes this as a witness so a source-space progress value cannot bless a
## worker standing on an abutment or foreground rock.
func surface_sample(screen_point: Vector2, hub = null) -> Dictionary:
	var path: Array = presentation_path(hub) if hub != null else [Vector2(580, 500), NEAR_SLOPE_FOOT, NEAR_LANDING, DECK_NEAR_BOARD, DECK_FAR_BOARD, FAR_LANDING, Vector2(250, 235)]
	if path.size() < 7:
		return {"region": "outside", "deck_progress": -1.0, "centerline_distance": INF}
	var best_distance := INF
	var best_region := "outside"
	var best_deck_progress := -1.0
	for segment_index in range(path.size() - 1):
		var start: Vector2 = path[segment_index] as Vector2
		var end: Vector2 = path[segment_index + 1] as Vector2
		var segment := end - start
		var length_squared := segment.length_squared()
		if length_squared <= 0.001:
			continue
		var t := clampf((screen_point - start).dot(segment) / length_squared, 0.0, 1.0)
		var distance := screen_point.distance_to(start + segment * t)
		var half_width := PRESENTATION_DECK_HALF_WIDTH if segment_index == 3 else PRESENTATION_APPROACH_HALF_WIDTH
		if distance > half_width or distance >= best_distance:
			continue
		best_distance = distance
		best_region = "deck" if segment_index == 3 else ("approach_near" if segment_index < 3 else "approach_far")
		best_deck_progress = t if segment_index == 3 else -1.0
	return {"region": best_region, "deck_progress": best_deck_progress, "centerline_distance": best_distance}

func _legacy_presentation_path_contains(screen_point: Vector2, hub = null) -> bool:
	var path: Array = presentation_path(hub) if hub != null else [Vector2(580, 500), NEAR_SLOPE_FOOT, NEAR_LANDING, DECK_NEAR_BOARD, DECK_FAR_BOARD, FAR_LANDING, Vector2(250, 235)]
	if path.size() < 7:
		return false
	for segment_index in range(path.size() - 1):
		var half_width := PRESENTATION_DECK_HALF_WIDTH if segment_index == 3 else PRESENTATION_APPROACH_HALF_WIDTH
		if _segment_band_contains(screen_point, path[segment_index] as Vector2, path[segment_index + 1] as Vector2, half_width):
			return true
	return false

func _segment_band_contains(screen_point: Vector2, start: Vector2, end: Vector2, half_width: float) -> bool:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return false
	var t := clampf((screen_point - start).dot(segment) / length_squared, 0.0, 1.0)
	var closest := start + segment * t
	return screen_point.distance_to(closest) <= half_width

func _append_approach_surface_marks(marks: Array[Dictionary], a: Vector2, b: Vector2, phase: int) -> void:
	var offset := b - a
	var length := offset.length()
	if length <= 12.0:
		return
	var direction := offset / length
	var normal := Vector2(-direction.y, direction.x)
	var distance := 9.0 + float(phase) * 3.0
	var mark_index := 0
	while distance < length - 5.0:
		var center := a + direction * distance
		for side in [-1.0, 1.0]:
			marks.append({
				"position": center + normal * side * 3.0,
				"direction": direction,
				"length": 5.0 + float((mark_index + phase) % 2) * 2.0,
				"kind": "rut",
			})
			if (mark_index + phase) % 2 == 0:
				marks.append({
					"position": center + normal * side * 8.0,
					"direction": direction,
					"length": 0.0,
					"kind": "edge",
				})
		distance += 16.0
		mark_index += 1

func _draw_approach(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, Color("8c4e3a"), 16.0, false)
	draw_line(a, b, Color("c87845"), 12.0, false)

func _draw_approach_surface_marks(marks: Array[Dictionary]) -> void:
	for mark in marks:
		var position: Vector2 = mark.get("position", Vector2.ZERO)
		if str(mark.get("kind", "")) == "edge":
			draw_circle(position, 1.0, Color(0.48, 0.26, 0.23, 0.56))
			continue
		var direction: Vector2 = mark.get("direction", Vector2.RIGHT)
		var half := direction * (float(mark.get("length", 6.0)) * 0.5)
		draw_line(position - half, position + half, Color(0.52, 0.29, 0.22, 0.62), 1.5, false)
