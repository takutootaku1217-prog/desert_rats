extends SceneTree
## Real UI routing with explicit fixture travel/cargo; not ordinary OS-input proof.
var game
var failures := 0
var assertions := 0

class PointerLeakProbe extends Node:
	var presses := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			presses += 1

func click_at(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = down
		root.push_input(event, true)
		await process_frame
func click_control(control: Control) -> void:
	await click_at(control.get_global_transform_with_canvas() * (control.size / 2.0))

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	print("%s %s" % ["ok" if ok else "FAIL",label])
	if not ok: failures += 1
func press(code: Key) -> void:
	var e := InputEventKey.new(); e.keycode = code; e.pressed = true
	root.push_input(e)
	e = InputEventKey.new(); e.keycode = code; e.pressed = false
	root.push_input(e)
func travel(destination: String) -> bool:
	if not game.world.request(destination): return false
	for i in 240:
		game._process(0.2)
		await process_frame
		if game.world.phase == "stopped" and game.world.region == destination: return true
	return false
func stable_state() -> Dictionary:
	return {"world":SaveGame.fields(game.world,WorldTrip.FIELDS),"inventory":game.storage.inventory.counts.duplicate(true),"armor":game.base.vehicle_loadout.duplicate(true),"credits":game.town.credits}
func dialog_key(dialog: Window, code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code; event.pressed = down
		dialog.push_input(event,true)
		await process_frame
func dialog_click(dialog: Window, control: Control) -> void:
	# Embedded Window mouse hover is owned by the root Viewport. Direct
	# dialog.push_input skips that hover traversal and cannot press BaseButton.
	var local_point := control.get_global_transform_with_canvas() * (control.size / 2.0)
	var point := Vector2(dialog.position) + dialog.get_final_transform() * local_point
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	root.push_input(motion,true)
	await process_frame
	check(dialog.gui_get_hovered_control() == control,"root mouse routing reaches intended dialog button")
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event,true)
		await process_frame
func outpost_pointer_contract(file_hash: String) -> void:
	var gate = game.mine_arrival_gate
	var state_before := SaveGame.capture(game)
	var dialog = gate._outpost_dialog
	for window_size in [Vector2i(1280,720),Vector2i(1440,900)]:
		root.size = window_size
		for frame in 3: await process_frame
		await click_control(gate._outpost_button)
		check(dialog.visible and gate.field == null and paused,"pointer danger action opens confirmation only " + str(window_size))
		print("outpost diagnostic root=",root.size," dialog pos=",dialog.position," size=",dialog.size," embedded=",dialog.is_embedded()," prior_pause=",gate._outpost_was_paused," cancel=",dialog.get_cancel_button().get_global_rect()," ok=",dialog.get_ok_button().get_global_rect())
		check(Rect2(Vector2.ZERO,Vector2(window_size)).encloses(Rect2(Vector2(dialog.position),Vector2(dialog.size))),"danger confirmation fits viewport " + str(window_size))
		check(dialog.get_cancel_button().has_focus(),"confirmation initially focuses safe cancellation")
		# Test actual engine input dispatch, not just emitted button signals.
		game.process_mode = Node.PROCESS_MODE_INHERIT
		for code in [KEY_V,KEY_M,KEY_O,KEY_I,KEY_UP,KEY_DOWN]:
			await dialog_key(dialog,code)
		check(dialog.visible and SaveGame.capture(game)==state_before,"dialog keys and running game cannot mutate behind confirmation")
		game.process_mode = Node.PROCESS_MODE_DISABLED
		await dialog_click(dialog,dialog.get_cancel_button())
		print("outpost after cancel visible=",dialog.visible," pause=",paused," owns=",gate._outpost_owns_pause," field=",gate.field)
		check(not dialog.visible and not paused and gate.field == null,"pointer Cancel closes only confirmation")
		check(SaveGame.capture(game)==state_before and FileAccess.get_sha256(game.save_ui.path)==file_hash,"pointer Cancel leaves all saved state and bytes unchanged")
	root.size = Vector2i(1280,720)
	await click_control(gate._outpost_button)
	# AcceptDialog processes Escape in Window::_input_from_window, before the
	# Viewport.push_input pipeline. Native Escape is a mandatory separate check.
	dialog.close_requested.emit()
	await process_frame
	check(not dialog.visible and not paused and gate.field == null,"window-close callback cancels optional danger without entry")
	await click_control(gate._outpost_button)
	await dialog_key(dialog,KEY_ENTER)
	check(not dialog.visible and not paused and gate.field == null,"Enter on initially focused Cancel does not enter danger")
	# Freeze input scene for deterministic confirmation; this is not native gameplay.
	await click_control(gate._outpost_button)
	var serial: int = gate._session_serial
	await dialog_click(dialog,dialog.get_ok_button())
	check(gate.field != null and gate._session_serial == serial+1,"pointer explicit confirmation creates one outpost")
	if gate.field != null:
		gate.field.process_mode = Node.PROCESS_MODE_DISABLED
		check(not SaveGame.write_field(game,game.save_ui.path,true),"optional outpost still refuses unsupported full mid-field save")
		check(FileAccess.get_sha256(game.save_ui.path)==file_hash,"refused optional save preserves previous ordinary save")
	check(SaveGame.apply(game,state_before),"restore ordinary C after explicit pointer-confirmed outpost")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	await process_frame
func run() -> void:
	SaveGame.disabled = true
	# Explicit headless embedded-window fixture; native OS windows are verified
	# separately. Viewport.push_input does not emulate the OS window dispatcher.
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280,720)
	game = load("res://scenes/main.tscn").instantiate()
	game.first_region_a_pilot = true
	root.add_child(game)
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.director.enabled = false
	for w in game.workers:
		w.stop_work()
		for job in GameData.job_list(): w.priorities[job] = 0
	check(await travel("b_forest") and await travel("c_quarry"),"actual WorldTrip reaches stopped C")
	var gate = game.mine_arrival_gate
	check(gate.visible_state() == "arrival_choice" and gate._panel.is_visible_in_tree(),"C offers unresolved arrival choice")
	SaveGame.disabled = false
	game.save_ui.path = "user://modal-feedback-c.json"
	check(not OS.get_environment("FLUID_TEST_HOME").is_empty() and SaveGame.write(game,game.save_ui.path,true),"C fixture saves to isolated file")
	var file_hash := FileAccess.get_sha256(game.save_ui.path)
	var pointer_before := stable_state()
	# Catch an unreachable/clipped button or pause left behind after real viewport input.
	gate.decline_entry()
	var reopen_btn = game.map_ui.find_child("CReopenChoice",true,false)
	check(reopen_btn is Button and reopen_btn.is_visible_in_tree(),"C map has a visible reopen control for pointer input")
	if reopen_btn is Button:
		for window_size in [Vector2i(1280,720), Vector2i(1440,900)]:
			root.size = window_size
			for frame in 3: await process_frame
			check(Rect2(Vector2.ZERO,Vector2(window_size)).encloses(reopen_btn.get_global_rect()),"map reopen control remains inside viewport " + str(window_size))
			await click_control(reopen_btn)
			check(not game.map_ui.is_open() and gate._panel.is_visible_in_tree() and not paused,"actual viewport pointer reopens choice and releases map pause " + str(window_size))
			check(stable_state() == pointer_before and FileAccess.get_sha256(game.save_ui.path) == file_hash,"pointer reopen leaves world inventory and saved bytes unchanged")
			gate.decline_entry()
		game.map_ui.close()
		root.size = Vector2i(1280,720)
		game.map_ui.open()
		await click_control(reopen_btn)
	else:
		# Keep unrelated existing tests independent of this intended RED.
		game.map_ui.close(); gate._dismissed_here = false; gate._show_choice(); gate.show()
	await outpost_pointer_contract(file_hash)
	await click_control(game.navigation.buttons["仲間"])
	check(game.detail._overlay.visible and not gate._panel.is_visible_in_tree(),"pointer Crew opens management through arrival blocker")
	game.detail.close()
	await process_frame
	check(gate._panel.is_visible_in_tree() and not gate._dismissed_here and stable_state() == pointer_before,"pointer Crew close restores unresolved choice without mutation")
	var probe := PointerLeakProbe.new()
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(probe)
	for point in [Vector2(100,670), Vector2(400,100), game.navigation.bar.get_global_transform_with_canvas() * Vector2(2,2)]:
		await click_at(point)
		await click_at(point,MOUSE_BUTTON_RIGHT)
	check(probe.presses == 0,"outside navigation and bar padding consume left and right pointer")
	var crew_point: Vector2 = game.navigation.buttons["仲間"].get_global_transform_with_canvas() * (game.navigation.buttons["仲間"].size / 2.0)
	game.navigation.bar.hide()
	await click_at(crew_point)
	check(probe.presses == 0 and not game.detail._overlay.visible,"hidden navigation does not leave a world-input hole")
	game.navigation.bar.show()
	probe.free()
	await click_control(game.navigation.buttons["その他"])
	check(game.navigation.popup.visible and not gate._panel.is_visible_in_tree(),"pointer Other opens above suspended arrival")
	if game.navigation.popup.visible:
		for child in game.navigation.groups["その他"].find_children("*","Button",true,false):
			if child is Button and child.text == "保存 / 設定など":
				await click_control(child)
	check(game.save_ui.is_open() and paused,"pointer Other Save owns pause")
	game.save_ui.close()
	game.navigation.close()
	await process_frame
	check(gate._panel.is_visible_in_tree() and FileAccess.get_sha256(game.save_ui.path) == file_hash,"pointer Save close restores choice without rewriting save")
	game.save_ui.open()
	check(not gate._panel.is_visible_in_tree() and not gate._overlay.is_visible_in_tree(),"opening Save immediately suspends C presentation")
	game.save_ui.ask("load"); game.save_ui.execute()
	await process_frame
	press(KEY_V)
	check(game.save_ui.is_open() and paused and not game.vehicle_ui.is_open(),"Save Continue owns keyboard and pause")
	check(not gate._panel.is_visible_in_tree(),"C does not reopen behind loaded Save menu")
	game.save_ui.close()
	await process_frame
	var before := stable_state()
	press(KEY_V)
	check(game.vehicle_ui.is_open() and not gate._panel.is_visible_in_tree(),"V immediately replaces arrival presentation")
	for i in 3: await process_frame
	check(game.vehicle_ui.is_open() and not gate._overlay.is_visible_in_tree() and not gate._notice.is_visible_in_tree(),"C stays suppressed across frames")
	check(stable_state() == before and not paused and not gate._dismissed_here and gate.field == null,"temporary suppression preserves unresolved state and normal pause ownership")
	check(not gate.enter_mine(),"hidden arrival action cannot enter behind equipment")
	# A failing boundary must not contaminate the independent recall/armor cases.
	if gate.field != null:
		gate.discard_field_for_load()
		check(SaveGame.apply(game,SaveGame.read(game.save_ui.path)),"restore C after unintended hidden-entry failure")
		game.process_mode = Node.PROCESS_MODE_DISABLED
	game.vehicle_ui.close()
	await process_frame
	check(gate.visible_state() == "arrival_choice" and gate._panel.is_visible_in_tree(),"closing V reoffers the same arrival choice")
	check(FileAccess.get_sha256(game.save_ui.path) == file_hash,"UI arbitration does not change saved bytes")
	game.navigation.activate("拠点・街")
	await process_frame
	check(game.navigation.popup.visible and not gate._panel.is_visible_in_tree(),"navigation popup also suppresses the unresolved choice")
	game.navigation.close()
	await process_frame
	check(gate._panel.is_visible_in_tree() and not gate._dismissed_here,"closing navigation reoffers rather than dismissing arrival")
	# Preserve a pending recall while its readiness changes behind another panel.
	game.workers[0].carrying = GameData.Item.WOOD
	game.workers[0].carry_n = 1
	check(not gate.enter_mine() and gate.visible_state() == "entry_wait","entry waits for carried cargo")
	var stance: String = game.operations.stance
	var options: Dictionary = gate._entry_options.duplicate(true)
	game.inventory_ui.open()
	game.workers[0].carrying = -1; game.workers[0].carry_n = 0
	for i in 3: await process_frame
	check(gate.field == null and gate.visible_state() == "entry_wait" and game.inventory_ui.is_open(),"ready recall cannot enter behind inventory")
	check(game.operations.stance == stance and gate._entry_options == options,"suppressed pending entry preserves recall and options")
	if gate.field != null:
		gate.discard_field_for_load()
		check(SaveGame.apply(game,SaveGame.read(game.save_ui.path)),"restore C after unintended ready-entry failure")
		game.process_mode = Node.PROCESS_MODE_DISABLED
	gate.cancel_pending_entry()
	game.inventory_ui.close()
	await process_frame
	check(gate._panel.is_visible_in_tree() and gate.visible_state() == "arrival_choice","cancelled recall returns to usable choice")
	# Ready recall must complete once when the management screen closes, without
	# another enter action. Cargo is an explicit fixture, not natural GUI evidence.
	var serial_before: int = gate._session_serial
	game.workers[0].carrying = GameData.Item.WOOD
	game.workers[0].carry_n = 1
	check(not gate.enter_mine() and gate.visible_state() == "entry_wait","second entry requests recall before automatic completion")
	await click_control(game.navigation.buttons["仲間"])
	check(game.detail._overlay.visible and not gate._panel.is_visible_in_tree(),"pointer Crew opens during pending recall")
	# Isolate remaining readiness checks if the RED pointer assertion fails.
	if not game.detail._overlay.visible: game.inventory_ui.open()
	game.workers[0].carrying = -1; game.workers[0].carry_n = 0
	for i in 3: await process_frame
	check(gate.field == null and gate._session_serial == serial_before,"ready entry still has no session behind pointer-opened Crew")
	game.detail.close()
	game.inventory_ui.close()
	for i in 3: await process_frame
	check(gate.field != null and gate.visible_state() == "field","closing pointer-opened Crew automatically completes ready recall")
	if gate.field != null:
		gate.field.process_mode = Node.PROCESS_MODE_DISABLED
		var automatic_field = gate.field
		check(gate.visible and automatic_field.is_visible_in_tree() and not game.visible,"automatic entry displays field rather than hidden horizontal view")
		check(gate._session_serial == serial_before + 1,"automatic completion creates exactly one session")
		check(automatic_field.session.mine_path_engineering and not automatic_field.session.outpost_enabled,"pending ordinary-C options survive management suspension")
		for i in 3: await process_frame
		check(gate.field == automatic_field and gate._session_serial == serial_before + 1,"later frames do not duplicate the automatically entered field")
	check(FileAccess.get_sha256(game.save_ui.path) == file_hash,"automatic entry does not rewrite ordinary save")
	check(SaveGame.apply(game,SaveGame.read(game.save_ui.path)),"restore ordinary saved C after automatic-entry observation")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	await process_frame
	check(gate.enter_mine(),"normal visible choice still enters the field")
	await process_frame
	if gate.field != null:
		gate.field.process_mode = Node.PROCESS_MODE_DISABLED
		check(SaveGame.write_field(game,"user://modal-feedback-field.json",true),"field snapshot prepared through real save boundary")
		check(SaveGame.apply(game,SaveGame.read(game.save_ui.path)),"return to saved ordinary C without committing field")
		game.process_mode = Node.PROCESS_MODE_DISABLED
		await process_frame
		game.save_ui.open()
		game.save_ui.path = "user://modal-feedback-field.json"
		game.save_ui.ask("load"); game.save_ui.execute()
		game.save_ui.close()
		await process_frame
		check(gate.field != null and gate.field.is_visible_in_tree() and gate.visible and paused,"field loaded after choice suppression is visible and explicitly paused")
		check(SaveGame.apply(game,SaveGame.read("user://modal-feedback-c.json")),"restore ordinary C fixture for armor checks")
		game.process_mode = Node.PROCESS_MODE_DISABLED
		paused = false
		await process_frame
	gate.decline_entry(); game.map_ui.close()
	# Explicit kit fixture isolates rejection presentation from resource acquisition.
	game.storage.inventory.counts = {GameData.Item.ARMOR_PLATE_KIT:1}
	game.vehicle_ui.open()
	game.vehicle_ui.preview_armor("plate")
	var dialog = game.vehicle_ui._armor_dialog
	var token: int = game.vehicle_ui._armor_token
	game.storage.inventory.counts[GameData.Item.FOOD] = 1
	before = stable_state()
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(dialog.visible and dialog.dialog_text.contains("消費") and dialog.dialog_text.contains("もう一度"),"stale OK keeps readable no-consumption and retry guidance")
	check(dialog.get_ok_button().disabled and dialog.get_cancel_button().has_focus(),"rejected comparison disables repeat OK and focuses Cancel")
	check(stable_state() == before and game.vehicle_ui._armor_token == -1 and not game.base.confirm_armor_install(token),"rejected UI consumes nothing and invalidates token")
	game.vehicle_ui.refresh()
	check(dialog.visible and dialog.dialog_text.contains("もう一度"),"refresh cannot erase visible rejection")
	game.vehicle_ui._cancel_armor()
	check(not dialog.visible and stable_state() == before,"cancel closes rejection without changing state")
	game.vehicle_ui.preview_armor("plate")
	check(dialog.visible and not dialog.get_ok_button().disabled,"explicit fresh comparison enables confirmation")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(not dialog.visible and game.base.vehicle_loadout.armor == "plate" and game.storage.count_of(GameData.Item.ARMOR_PLATE_KIT) == 0,"fresh confirmation installs once and closes")
	game.vehicle_ui.close()
	game.free()
	paused = false
	print("UI FEEDBACK ASSERTIONS %d FAILURES %d" % [assertions,failures])
	quit(1 if failures else 0)
