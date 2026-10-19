extends SceneTree
## Viewport synthetic input only. It verifies the same key and buttons as play,
## but is not an OS-level keyboard/mouse test.
var main
var fails := 0

func check(ok: bool, message: String) -> void:
	print(("OK " if ok else "FAIL ") + message)
	if not ok:
		fails += 1

func frames() -> void:
	for _i in 8:
		await process_frame

func key(code: int) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames()

func click(button: Button) -> void:
	var pos := button.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.global_position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames()

func screenshot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--screenshots=").path_join("boost-core-hud.png"))

func _initialize() -> void:
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.world.active = false
	main.quarry.state = "road"
	main.base.fuel = GameData.FUEL_CAP
	main.target_speed = 60.0
	check(main.status._boost.text.contains("ブースト負荷"), "HUDに燃料と別のブースト負荷を表示")
	await key(KEY_V)
	check(main.boost_active and main.status._boost_toggle.text.contains("解除"), "VキーのViewport入力で開始")
	await click(main.status._boost_toggle)
	check(not main.boost_active, "HUDボタンで解除")
	await click(main.status._boost_burst)
	check(main.boost_core_id == BoostCores.BURST and main.status._boost.text.contains("短時間型"), "HUDボタンで短時間型を選択")
	await screenshot()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
