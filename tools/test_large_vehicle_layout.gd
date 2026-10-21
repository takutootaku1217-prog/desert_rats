extends SceneTree
## Focused proof for the isolated large-fortress coordinate contract.

func _init() -> void:
	GameData.large_three_deck_enabled = true
	_assert_rect_contract()
	_assert_three_deck_routes()
	_assert_pixel_exterior()
	_assert_moving_parts()
	_assert_normal_mode_is_unchanged()
	print("LARGE_VEHICLE_LAYOUT_COMPLETE")
	quit()


func _assert_pixel_exterior() -> void:
	assert(LargeVehicleLayout.pixel_exterior_available())
	var exterior := LargeVehicleLayout.PIXEL_HULL_RECT
	assert(absf(exterior.size.aspect() - LargeVehicleLayout.PIXEL_HULL_REGION.size.aspect()) < 0.0001)
	for spec in [[LargeVehicleLayout.PIXEL_HULL, LargeVehicleLayout.PIXEL_HULL_REGION], [LargeVehicleLayout.PIXEL_WHEEL, LargeVehicleLayout.PIXEL_WHEEL_REGION], [LargeVehicleLayout.PIXEL_GUN, LargeVehicleLayout.PIXEL_GUN_REGION]]:
		var source := Image.load_from_file(str(spec[0]))
		assert(source != null and source.get_format() == Image.FORMAT_RGBA8)
		assert(Rect2(Vector2.ZERO, Vector2(source.get_size())).encloses(spec[1]))
	assert(LargeVehicleLayout.PIXEL_WHEEL_CENTERS.size() == 6)
	for wheel in LargeVehicleLayout.PIXEL_WHEEL_CENTERS:
		assert(wheel.x >= exterior.position.x and wheel.x <= exterior.end.x)
		assert(is_equal_approx(wheel.y + LargeVehicleLayout.PIXEL_WHEEL_RADIUS, 562.0))


func _assert_moving_parts() -> void:
	assert(LargeVehicleLayout.moving_parts_available())
	assert(LargeVehicleLayout.MOVING_BODY_RECT.size == LargeVehicleLayout.PIXEL_HULL_RECT.size)
	for spec in [[LargeVehicleLayout.MOVING_BODY, LargeVehicleLayout.MOVING_BODY_REGION], [LargeVehicleLayout.MOVING_WHEEL, LargeVehicleLayout.MOVING_WHEEL_REGION], [LargeVehicleLayout.MOVING_GUN, LargeVehicleLayout.MOVING_GUN_REGION], [LargeVehicleLayout.MOVING_CRANE, LargeVehicleLayout.MOVING_CRANE_REGION], [LargeVehicleLayout.MOVING_FLAG, LargeVehicleLayout.MOVING_FLAG_REGION], [LargeVehicleLayout.MOVING_SHUTTER, LargeVehicleLayout.MOVING_SHUTTER_REGION]]:
		var source := Image.load_from_file(str(spec[0]))
		assert(source != null and source.get_format() == Image.FORMAT_RGBA8)
		assert(Rect2(Vector2.ZERO, Vector2(source.get_size())).encloses(spec[1]))
	assert(LargeVehicleLayout.MOVING_WHEEL_CENTERS.size() == 6)
	for wheel in LargeVehicleLayout.MOVING_WHEEL_CENTERS:
		assert(is_equal_approx(wheel.y + LargeVehicleLayout.MOVING_WHEEL_RADIUS, 562.0))


func _assert_rect_contract() -> void:
	var hull := LargeVehicleLayout.HULL_RECT
	assert(hull.position.x == GameData.HULL_POS.x)
	assert(is_equal_approx(hull.end.x, 912.0))
	assert(is_equal_approx(hull.end.y, MobileBase.WHEEL_Y))
	for wheel in LargeVehicleLayout.WHEEL_CENTERS:
		assert(wheel.x >= hull.position.x and wheel.x <= hull.end.x)
		assert(is_equal_approx(wheel.y + LargeVehicleLayout.WHEEL_RADIUS, MobileBase.WHEEL_Y + 56.0))
	for floor_i in [1, 2, 3]:
		assert(hull.has_point(Vector2(400, GameData.deck_y(floor_i))))
	assert(LargeVehicleLayout.ROOF_TURRET_MOUNT.x >= hull.position.x and LargeVehicleLayout.ROOF_TURRET_MOUNT.x <= hull.end.x)
	assert(hull.has_point(LargeVehicleLayout.ROOF_TURRET_MOUNT))
	var exterior := LargeVehicleLayout.EXTERIOR_HULL_RECT
	var source := Image.load_from_file(LargeVehicleLayout.RASTER_HULL)
	assert(absf(exterior.size.aspect() - source.get_size().aspect()) < 0.0001)
	assert(LargeVehicleLayout.LOWER_LADDER_X == LargeVehicleLayout.UPPER_LADDER_X)
	# Sample actual source rungs across all three floors. Both route segments
	# must use the visible shaft instead of traversing an unpainted wall.
	var interior := Image.load_from_file(LargeVehicleLayout.RASTER_INTERIOR)
	for floor_i in [1, 2]:
		var rung_y := (LargeVehicleLayout.deck_y(floor_i) + LargeVehicleLayout.deck_y(floor_i + 1)) * 0.5
		var source_point := (Vector2(LargeVehicleLayout.LOWER_LADDER_X, rung_y) - hull.position) / hull.size * Vector2(interior.get_size())
		assert(interior.get_pixelv(Vector2i(source_point)).a > 0.9)


func _walk_to(worker: Worker, destination: Vector2, expected_floor: int) -> void:
	worker.target = destination
	for _step in 1200:
		if worker.move_to_target(0.05):
			break
	assert(worker.floor_i == expected_floor)
	assert(worker.position.distance_to(destination) <= 4.1)


func _assert_three_deck_routes() -> void:
	var worker := Worker.new()
	worker.position = LargeVehicleLayout.RAMP_FOOT
	worker.floor_i = 0
	for i in LargeVehicleLayout.TOP_DECK_ROOMS.size():
		_walk_to(worker, LargeVehicleLayout.top_room_anchor(i), 3)
		_walk_to(worker, Vector2(360 + i * 60, GameData.deck_y(2)), 2)
		_walk_to(worker, Vector2(220 + i * 80, GameData.deck_y(1)), 1)
	_walk_to(worker, LargeVehicleLayout.RAMP_FOOT, 0)
	worker.free()


func _assert_normal_mode_is_unchanged() -> void:
	GameData.large_three_deck_enabled = false
	assert(GameData.floor_of_y(GameData.LO_Y) == 1)
	assert(GameData.floor_of_y(GameData.UP_Y) == 2)
	assert(is_equal_approx(GameData.deck_y(1), GameData.LO_Y))
	assert(is_equal_approx(GameData.deck_y(2), GameData.UP_Y))
