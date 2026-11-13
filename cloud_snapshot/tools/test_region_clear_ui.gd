extends SceneTree
## Explicit valid completed-save fixture; not a natural playthrough.
var game
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	print("  %s %s" % ["ok" if ok else "FAIL", label])
	if not ok: failures += 1
func settle() -> void:
	for unused in 3: await process_frame
func key(code: int, down: bool, echo := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = down; event.echo = echo; event.shift_pressed = shift
	root.push_input(event)
	await process_frame
func click_at(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point
		event.button_index = button; event.pressed = down
		root.push_input(event,true)
		await process_frame
func completed_fixture() -> Dictionary:
	game.world.region_state.roads.bd.cleared = true
	var enemy := {"id":FirstRegionCompletion.BOSS_ID,"kind":FirstRegionCompletion.BOSS_KIND,"lane":FirstRegionCompletion.BOSS_LANE,"home_x":842.0,"home_y":326.0,"x":842.0,"y":326.0,"hp":0.0,"max_hp":72.0,"attack_left":0.0,"target":"","engager":"","dead":true}
	game.world.region_completion.encounters[FirstRegionCompletion.ENCOUNTER_ID] = {"cleared":true,"enemies":{FirstRegionCompletion.BOSS_ID:enemy}}
	game.world.refresh_region_completion()
	return SaveGame.capture(game)
func run() -> void:
	if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2); return
	root.size = Vector2i(1280,720)
	SaveGame.disabled = true
	game = load("res://scenes/main.tscn").instantiate()
	game.first_region_a_pilot = true
	game.set_meta("diagnostic_seed",104729)
	root.add_child(game)
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.director.enabled = false
	game.save_ui.path = "user://region-ack-manual.json"
	game.save_ui.checkpoint_path = "user://region-ack-checkpoint.json"
	SaveGame.disabled = false
	var incomplete := SaveGame.capture(game)
	var completed := completed_fixture()
	check(SaveGame.validate(completed,game),"explicit completed fixture is a valid ordinary save")
	await settle()
	var ui = game.get("region_clear_ui")
	check(ui != null and ui.is_open(),"completed horizontal game presents an acknowledgement")
	if ui == null: await finish(); return
	check(paused,"acknowledgement owns a simulation pause")
	check(SaveGame.capture(game) == completed,"display does not mutate durable game state")
	ui.acknowledge()
	await settle()
	check(not ui.is_open() and not paused,"explicit confirmation restores prior running state")
	check(SaveGame.capture(game) == completed,"acknowledgement does not grant rewards or rewrite state")
	await settle()
	check(not ui.is_open(),"confirmed goal does not repeatedly reopen")
	var invalid := completed.duplicate(true)
	invalid.world.region_completion.completed = false
	check(not SaveGame.apply(game,invalid),"malformed completed save is rejected")
	await settle()
	check(not ui.is_open(),"failed load does not rearm an acknowledged goal")
	check(SaveGame.apply(game,completed),"valid completed load rearms acknowledgement")
	await settle()
	check(ui.is_open() and paused,"completed load presents again")
	check(not SaveGame.apply(game,invalid) and ui.is_open() and paused,"failed load while open preserves modal and pause")
	# Enable actual Main processing: owned pause, not a disabled fixture, must
	# stop simulation and block shortcut input. Disable again before resuming.
	game.process_mode = Node.PROCESS_MODE_INHERIT
	var stopped := SaveGame.capture(game)
	var view_before: int = game.base_view.mode
	var speed_before: float = game.target_speed
	for code in [KEY_O,KEY_I,KEY_V,KEY_M,KEY_C,KEY_F,KEY_B,KEY_R,KEY_ESCAPE,KEY_UP,KEY_DOWN]:
		await key(code,true); await key(code,false)
	await key(KEY_TAB,true); await key(KEY_TAB,false)
	await key(KEY_TAB,true,false,true); await key(KEY_TAB,false,false,true)
	await click_at(Vector2(24,680))
	await click_at(Vector2(1040,220),MOUSE_BUTTON_RIGHT)
	check(ui.is_open() and ui._confirm.has_focus(),"Esc and background pointer input do not dismiss; Tab traps focus")
	check(game.base_view.mode == view_before and game.target_speed == speed_before,"O/I and gameplay shortcuts do not leak")
	check(SaveGame.capture(game) == stopped,"processing-enabled game remains unchanged under pause")
	check(not game.navigation.bar.visible and game.has_open_management_panel(),"acknowledgement participates in menu arbitration")
	await key(KEY_UP,true)
	await key(KEY_ENTER,true)
	await key(KEY_ENTER,true,true)
	await key(KEY_ENTER,false)
	await settle()
	check(ui.is_open() and paused,"confirm waits for another held key release")
	await key(KEY_UP,true,true)
	check(game.target_speed == speed_before,"held arrow repeat after confirmation does not leak")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await key(KEY_UP,false)
	await settle()
	check(not ui.is_open() and not paused,"final input release resumes exactly once")
	for code in [KEY_SPACE,KEY_KP_ENTER]:
		SaveGame.apply(game,completed); await settle()
		await key(code,true); await key(code,true,true)
		check(ui.is_open() and paused,"held confirming key keeps shield: "+str(code))
		await key(code,false); await settle()
		check(not ui.is_open() and not paused,"confirming release clears shield: "+str(code))
	SaveGame.apply(game,completed)
	paused = true
	await settle()
	await click_at(ui._confirm.get_global_rect().get_center())
	await settle()
	check(not ui.is_open() and paused,"mouse confirmation preserves prior manual pause")
	paused = false
	SaveGame.apply(game,completed); await settle()
	await key(KEY_ENTER,true)
	root.focus_exited.emit() # Explicit OS focus-loss event fixture.
	await settle()
	check(not ui.is_open() and not paused,"focus loss cannot strand a confirmed held-key modal")
	SaveGame.apply(game,incomplete)
	await key(KEY_UP,true)
	completed_fixture(); await settle()
	await key(KEY_ENTER,true); await key(KEY_ENTER,false); await settle()
	check(ui.is_open() and paused,"key held before presentation retains shield after confirmation")
	await key(KEY_UP,false); await settle()
	check(not ui.is_open() and not paused,"pre-existing key release safely finishes confirmation")
	await key(KEY_UP,true)
	check(SaveGame.apply(game,completed),"successful load while key is held")
	await settle()
	await key(KEY_ENTER,true); await key(KEY_ENTER,false); await settle()
	check(ui.is_open() and paused,"successful load reset preserves pre-existing input hold")
	await key(KEY_UP,false); await settle()
	game.save_ui.open()
	check(SaveGame.apply(game,completed),"successful apply inside SaveUI")
	await settle()
	check(not ui.is_open() and game.save_ui.is_open() and paused,"save menu retains pause and priority")
	game.save_ui.close(); await settle()
	check(ui.is_open() and paused,"ack appears only after save menu closes")
	check(SaveGame.apply(game,incomplete),"earlier incomplete save applies while acknowledgement open")
	await settle()
	check(not ui.is_open() and not paused,"rollback releases only owned pause and clears eligibility")
	SaveGame.apply(game,completed)
	game.game_over = true
	await settle()
	check(not ui.is_open(),"game-over flow is never covered by completion")
	game.game_over = false
	await settle()
	check(ui.is_open(),"safe horizontal state can present pending completion")
	ui.acknowledge(); await settle()
	SaveGame.apply(game,incomplete)
	for worker in game.workers:
		worker.stop_work()
		for job in GameData.job_list(): worker.priorities[job] = 0
	for destination in ["b_forest","c_quarry"]:
		check(game.world.request(destination),"field fixture requests "+destination)
		for unused in 300:
			game._process(0.25); await process_frame
			if game.world.region == destination and game.world.phase == "stopped": break
		check(game.world.region == destination,"field fixture arrives "+destination)
	var gate = game.mine_arrival_gate
	gate._process(0.0)
	completed_fixture()
	check(gate.enter_mine(),"completed ordinary C field starts before deferred UI")
	if gate.field != null:
		gate.field.process_mode = Node.PROCESS_MODE_DISABLED
		await settle()
		check(not ui.is_open(),"field presentation is not covered by acknowledgement")
		var field_save := SaveGame.capture(game)
		check(SaveGame.validate(field_save,game),"completed ordinary field save validates")
		check(SaveGame.apply(game,completed),"leave field for completed horizontal load")
		game.process_mode = Node.PROCESS_MODE_DISABLED
		await settle()
		check(ui.is_open() and paused,"ack owns pause before field replacement")
		check(SaveGame.apply(game,field_save),"completed field load succeeds")
		gate.field.process_mode = Node.PROCESS_MODE_DISABLED
		await settle()
		check(paused and not ui.is_open(),"field load owns pause without acknowledgement overlap")
		var adapter = gate.field
		adapter._toggle_field_pause()
		adapter.session.request_recall()
		for unused in 2000:
			if adapter.session.phase == "ready_to_exit": break
			adapter.life_clock.tick(0.05)
		check(adapter.session.phase == "ready_to_exit","field physically recalls before return")
		adapter._commit_and_exit()
		await settle()
		check(gate.field == null and ui.is_open() and paused,"acknowledgement appears after committed horizontal return")
	check(not SaveGame.exists(game.save_ui.path),"acknowledgement never automatically creates manual save")
	root.size = Vector2i(640,480)
	await settle()
	print("resize physical=",root.size," logical=",root.get_visible_rect()," confirm=",ui._confirm.get_global_rect())
	check(root.get_visible_rect().encloses(ui._confirm.get_global_rect()),"confirmation remains inside resized logical viewport")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true # Wheel pulses intentionally have no matching release.
	wheel.position = ui._text.get_global_rect().get_center()
	root.push_input(wheel,true)
	await key(KEY_ENTER,true); await key(KEY_ENTER,false); await settle()
	check(not ui.is_open(),"scroll-wheel pulse cannot strand confirmed modal")
	await finish()
func finish() -> void:
	paused = false
	SaveGame.disabled = true
	if is_instance_valid(game): game.queue_free()
	await process_frame
	print("REGION CLEAR UI assertions=",assertions," failures=",failures)
	quit(0 if failures == 0 else 1)
