extends SceneTree
## Focused proof for the isolated large-fortress coordinate contract.

func _init() -> void:
	GameData.large_three_deck_enabled = true
	_assert_rect_contract()
	_assert_three_deck_routes()
	_assert_normal_mode_is_unchanged()
	print("LARGE_VEHICLE_LAYOUT_COMPLETE")
	quit()


func _assert_rect_contract() -> void:
	var hull := LargeVehicleLayout.HULL_RECT
	assert(hull.position.x == GameData.HULL_POS.x)
	assert(is_equal_approx(hull.end.x, 912.0))
	assert(is_equal_approx(hull.end.y, MobileBase.WHEEL_Y))
	for wheel in LargeVehicleLayout.WHEEL_CENTERS:
		assert(wheel.x >= hull.position.x and wheel.x <= hull.end.x)
		assert(is_equal_approx(wheel.y, hull.end.y))
	for floor_i in [1, 2, 3]:
		assert(hull.has_point(Vector2(400, GameData.deck_y(floor_i))))
	assert(LargeVehicleLayout.ROOF_TURRET_MOUNT.x >= hull.position.x and LargeVehicleLayout.ROOF_TURRET_MOUNT.x <= hull.end.x)
	assert(LargeVehicleLayout.ROOF_TURRET_MOUNT.y < hull.position.y)


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
