class_name CanyonRecoveryOccupancy
extends Node2D
## Immutable display-side ground occupancy for the fixed canyon view.
## RecoveryRouteConnectionSession remains the movement authority; this only
## describes which painted ground is a cliff/ravine and where the bridge deck
## makes that ravine crossable for the hub's navigation contract and tests.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func solid_contains(screen_point: Vector2) -> bool:
	var solids := get_node_or_null("TerrainSolids")
	if solids == null:
		return false
	var local_point := to_local(screen_point)
	for child in solids.get_children():
		if child is CollisionPolygon2D:
			var polygon: PackedVector2Array = (child as CollisionPolygon2D).polygon
			if Geometry2D.is_point_in_polygon(local_point, polygon):
				return true
	return false

func bridge_contains(screen_point: Vector2) -> bool:
	var deck := get_node_or_null("BridgeConnection/Deck") as CollisionPolygon2D
	if deck == null:
		return false
	return Geometry2D.is_point_in_polygon(to_local(screen_point), deck.polygon)

func allows_walkable(screen_point: Vector2) -> bool:
	# The bridge deck deliberately overrides the ravine's solid ground.  No
	# physics body drives Workers here, so this cannot add a second movement
	# authority or alter the existing bridge session.
	return bridge_contains(screen_point) or not solid_contains(screen_point)
