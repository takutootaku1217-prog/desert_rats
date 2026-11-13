extends SceneTree
## Catches hidden or misleading recommendations without granting progression.
var main
var failures := 0

func _init() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok: failures += 1
func next_id() -> String:
	return str(main.navigation.guide_snapshot().get("next_step", {}).get("id", ""))
func _run() -> void:
	if OS.get_environment("FLUID_TEST_HOME").is_empty(): quit(2); return
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 261109)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	var nav = main.navigation
	nav._process(0.0)
	var hint = nav.find_child("NextStepHint", true, false)
	check(hint != null, "fresh stopped first region visibly exposes the optional guide")
	check(next_id() == "workbench", "fresh advice starts with preparation, not recorded history or boss")
	if hint == null:
		await finish(); return
	var entry: Button = hint.find_child("NextStepGuideEntry", true, false)
	check(entry != null and hint.visible and not nav.popup.visible and not paused, "hint is discoverable without a forced modal or pause")
	var before: Dictionary = SaveGame.capture(main)
	for repeat in range(2):
		entry.emit_signal("pressed")
		nav._process(0.0)
		await process_frame
		check(nav.popup.visible and nav.selected == "はじめの一周" and paused and not hint.visible, "hint opens the real paused guide without overlapping it")
		check(nav.guide_text.text.begins_with("次の一手"), "practical recommendation precedes long action-history records")
		var escape := InputEventKey.new(); escape.pressed = true; escape.keycode = KEY_ESCAPE
		nav._unhandled_input(escape); nav._process(0.0)
		check(not nav.popup.visible and not paused and hint.visible, "Escape restores play and repeatable optional entry")
	check(before == SaveGame.capture(main), "reading/reopening guidance never changes saved game state")
	var rect: Rect2 = hint.get_global_rect()
	check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1280 and rect.end.y <= nav.bar.position.y, "hint fits viewport above rather than over the existing bar")
	await event_hud_layout()
	main.request_build("workbench")
	check(next_id() == "workbench_wait", "pending construction is acknowledged instead of ordering another workbench")
	nav._process(0.0); await process_frame
	var title_width: float = nav.guide_next.get_theme_font("font").get_string_size(nav.guide_next.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nav.guide_next.get_theme_font_size("font_size")).x
	check(title_width <= nav.guide_next.size.x and hint.get_global_rect().end.x <= 1280, "long pending-construction recommendation fits without truncating its title")
	main.finish_build("workbench")
	check(next_id() == "mining_tool", "built workbench advances advice to equipping a mining tool")
	main.workers[0].tools["mine"] = GameData.Item.WOOD_PICK
	check(next_id() == "visit_c", "a prepared crew sees first quarry-trip guidance")
	main.storage.store_owned(GameData.Item.IRON_ORE, 2, Inventory.SOURCE_TRANSFER)
	check(next_id() == "visit_c", "unproven ore stock never invents a quarry return")
	main.world.region = "c_quarry"
	check(next_id() == "enter_c", "stopped C guidance points at the actual field entry")
	var c_help: Dictionary = nav.guide_snapshot()
	check(str(c_help.next_step.body).contains("Cの入場選択を開く") and str(c_help.next_step.body).contains("移動"), "C advice includes the map route back to a dismissed arrival choice")
	main.world.guide_progress.completed["quarry_returned"] = true
	check(next_id() == "return_a", "committed quarry cargo points toward town before another outing")
	main.world.region = "a_start"
	main.world.guide_progress.completed["returned_a"] = true
	check(next_id() == "town_upgrade", "first A return exposes optional processing equipment and supply before another expedition")
	await return_preparation_guidance()
	await remaining_goal_guidance()
	completed_region_fixture()
	check(next_id() == "free_play", "completed region correctly offers continued free exploration")
	main.world.guide_progress.completed.clear()
	var old_history: Dictionary = main.world.guide_progress.duplicate(true)
	check(next_id() == "free_play", "completed region with empty older history is not sent through a fabricated first trip")
	check(main.world.guide_progress == old_history, "respecting regional completion does not invent missing operation records")
	main.storage.inventory.counts[GameData.Item.FOOD] = 0
	check(next_id() == "food", "empty food takes priority even after regional completion")
	var food: Dictionary = nav.guide_snapshot().next_step
	check(str(food.body).contains("購買店") and str(food.body).contains("料理"), "food advice offers current existing buy and cook routes without promising free food")
	var unchanged: Dictionary = SaveGame.capture(main)
	nav._process(0.0)
	check(unchanged == SaveGame.capture(main), "recommendation refresh is read-only for progressed state too")
	main.craft_ui.open(); nav._process(0.0)
	check(not hint.visible, "another modal hides the hint")
	main.craft_ui.close(); nav._process(0.0)
	check(hint.visible, "closing modal restores hint")
	main.world.phase = "travel"; nav._process(0.0)
	check(not hint.visible, "compact travel UI is not covered by stopped-site advice")
	main.world.phase = "stopped"; nav._process(0.0)
	check(hint.visible, "stopping restores contextual hint")
	main.world.map_profile = WorldMapDB.DESERT; nav._process(0.0)
	check(not hint.visible and next_id() == "", "alternate map never receives unavailable first-region advice")
	main.world.map_profile = WorldMapDB.FIRST_REGION_A
	main.game_over = true; nav._process(0.0)
	check(not hint.visible, "game over hides actionable-looking hint")
	await field_visibility()
	await finish()

func event_hud_layout() -> void:
	# Synthetic weather only in this automatic layout test, never the native profile.
	var hud = main.event_hud
	for id in ["sandstorm", "heatwave", "coldsnap"]:
		main.director.active.clear()
		main.director.log.clear()
		main.director.trigger(id, false)
		main.director.note("採掘地から車体へ帰還。車内へ搬入: 木材×1、石×2。Cに残す: なし。")
		for frame in range(4):
			hud._process(0.0); main.navigation._process(0.0); await process_frame
		var panel: Rect2 = hud._panel.get_global_rect()
		check(panel.end.x <= main.navigation.guide_hint.position.x and panel.end.x <= main.navigation.bar.position.x, id + " event panel stays beside rather than under guide/navigation")
		check(panel.position.y >= 0 and panel.end.y <= 720, id + " wrapped event panel remains inside the logical viewport")
		check(hud._log.text.contains("木材×1、石×2。Cに残す: なし。"), id + " exact return quantities remain in the visible log")
		for slot in hud._slots:
			if slot.id != id: continue
			for stance in EventDB.def(id).stances:
				var button: Button = slot.btns[stance.id]
				check(button.text == stance.name and panel.encloses(button.get_global_rect()), id + " stance retains its complete label inside the panel: " + stance.id)
				button.emit_signal("pressed")
				check(main.director.default_stance.get(id) == stance.id, id + " wrapped stance still applies: " + stance.id)
	main.director.active.clear(); main.director.log.clear(); main.director.default_stance.clear()
	hud._process(0.0)

func return_preparation_guidance() -> void:
	# Breaks caught: skipping upgrades, treating reserved/transit stock as equipped,
	# mutating armor quotes by reading, and inventing new boss prerequisites.
	for worker in main.workers: worker.stop_work()
	main.craft_queue.clear(); main.transfer_queue.clear()
	main.storage.inventory.counts = {GameData.Item.FOOD:8, GameData.Item.IRON_ORE:2}
	var before: Dictionary = SaveGame.capture(main)
	var prep: Dictionary = main.navigation.guide_snapshot().get("preparation", {})
	check(prep.get("visible", false) and prep.get("armor_status", "") == "craft", "returned A with ore exposes kit manufacture rather than pretending armor is installed")
	check(prep.get("ore", -1) == 2 and prep.get("iron", -1) == 0 and prep.get("food", -1) == 8, "preparation distinguishes current ore iron and food")
	check(before == SaveGame.capture(main), "reading initial preparation never grants goods or records history")
	main.craft_queue.append({"id":"armor_plate_kit", "n":1})
	check(main.navigation.guide_snapshot().get("preparation", {}).get("armor_status", "") == "waiting", "queued kit is work to finish rather than another kit or installed armor")
	main.craft_queue.clear()
	main.processor.output.append(GameData.Item.ARMOR_PLATE_KIT)
	check(main.navigation.guide_snapshot().get("preparation", {}).get("armor_status", "") == "waiting", "output tray kit waits for warehouse storage")
	main.processor.output.clear()
	main.workers[0].carrying = GameData.Item.ARMOR_PLATE_KIT
	main.workers[0].carry_n = 1
	check(main.navigation.guide_snapshot().get("preparation", {}).get("armor_status", "") == "waiting", "carried kit is not offered as warehouse-installable")
	main.workers[0].carrying = -1; main.workers[0].carry_n = 0
	main.processor.stock.counts[GameData.Item.ARMOR_PLATE_KIT] = 1
	prep = main.navigation.guide_snapshot().get("preparation", {})
	check(prep.get("armor_status", "") == "workshop" and str(prep.get("body", "")).contains("所持品 → 作業場 → 倉庫へ戻す"), "parked workshop kit requires explicit warehouse transfer, not passive waiting")
	main.transfer_queue.append({"item":GameData.Item.ARMOR_PLATE_KIT,"n":1,"dir":"to_storage"})
	check(main.navigation.guide_snapshot().get("preparation", {}).get("armor_status", "") == "waiting", "requested workshop return waits for normal transport")
	main.transfer_queue.clear(); main.processor.stock.counts.erase(GameData.Item.ARMOR_PLATE_KIT)
	main.storage.inventory.counts[GameData.Item.ARMOR_PLATE_KIT] = 1
	main.transfer_queue.append({"item":GameData.Item.ARMOR_PLATE_KIT,"n":1,"dir":"to_workshop"})
	prep = main.navigation.guide_snapshot().get("preparation", {})
	check(prep.get("armor_status", "") == "reserved" and prep.get("armor_available", -1) == 0, "reserved warehouse kit is not an available installation")
	main.transfer_queue.clear()
	var quote: Dictionary = main.base.begin_armor_preview("plate")
	check(quote.ok, "real unreserved kit opens a valid armor quote")
	var quoted: Dictionary = SaveGame.capture(main)
	for repeat in range(3):
		prep = main.navigation.guide_snapshot().get("preparation", {})
	check(prep.get("armor_status", "") == "compare" and prep.get("armor_available", 0) == 1, "stored free kit points at comparison without claiming confirmation")
	check(quoted == SaveGame.capture(main) and main.base.confirm_armor_install(quote.token), "repeated guide reads preserve game state and the live comparison token")
	check(main.navigation.guide_snapshot().get("preparation", {}).get("armor_status", "") == "installed", "paid install is reflected as current installed armor")
	main.storage.store_owned(GameData.Item.HAUL_FRAME, 1, Inventory.SOURCE_TRANSFER)
	check(main.equip_work_support(main.workers[0], GameData.Item.HAUL_FRAME), "fixture equips a genuinely owned frame")
	check(next_id() in ["route_materials", "route_travel"], "equipped preparations return primary advice to existing regional goals")
	main.navigation.activate("はじめの一周"); main.navigation._process(0.0); await process_frame
	check(main.navigation.guide_text.text.contains("鉄板装甲") and main.navigation.guide_text.text.contains("B–D"), "preparation and independent regional goal both reach the real guide")
	main.navigation.close()
	main.world.region = "b_forest"
	check(not main.navigation.guide_snapshot().get("preparation", {}).get("visible", true), "town-return card does not invite unavailable town actions at B")
	main.world.region = "a_start"
	main.world.guide_progress.completed.clear()
	var missing_history: Dictionary = main.world.guide_progress.duplicate(true)
	check(not main.navigation.guide_snapshot().get("preparation", {}).get("visible", true), "older missing history does not fabricate a quarry return from gear")
	check(missing_history == main.world.guide_progress, "reading prepared gear does not backfill absent history")
	main.world.guide_progress.completed["quarry_returned"] = true
	main.world.guide_progress.completed["returned_a"] = true

func remaining_goal_guidance() -> void:
	# Breaks caught: generic advice after a return, spendability using raw stock,
	# repeating a finished objective, and old history overriding real milestones.
	for worker in main.workers: worker.stop_work()
	main.transfer_queue.clear()
	main.storage.inventory.counts = {GameData.Item.WOOD:0, GameData.Item.STONE:0, GameData.Item.FOOD:8}
	check(next_id() == "route_materials", "returned crew lacking materials gets collection before road work")
	var advice: Dictionary = main.navigation.guide_snapshot().next_step
	check(str(advice.body).contains("木材 0/2（不足2）") and str(advice.body).contains("石 0/1（不足1）"), "road guidance shows the actual spendable shortage")
	main.storage.inventory.counts[GameData.Item.WOOD] = 2
	main.storage.inventory.counts[GameData.Item.STONE] = 1
	check(next_id() == "route_travel", "exact materials at A lead to B or D rather than pretending work is local")
	main.transfer_queue.append({"item":GameData.Item.WOOD,"n":2,"dir":"to_workshop"})
	var reserved_before: Dictionary = SaveGame.capture(main)
	check(next_id() == "route_materials", "reserved wood cannot be offered for road payment")
	check(str(main.navigation.guide_snapshot().next_step.body).contains("木材 0/2（不足2）"), "reservation-aware display agrees with payment availability")
	check(reserved_before == SaveGame.capture(main), "reading reserved-stock guidance preserves the actual reservation and all saved state")
	main.transfer_queue.clear()
	for site in ["b_forest", "d_yard"]:
		main.world.region = site
		check(next_id() == "route_open", "ready material at " + site + " points to the actual local map action")
		check(str(main.navigation.guide_snapshot().next_step.body).contains("B–D倒木近道の処理を確認"), "road instructions identify the existing confirmation entry")
	var before: Dictionary = SaveGame.capture(main)
	main.navigation.activate("はじめの一周")
	main.navigation._process(0.0)
	check(main.navigation.guide_text.text.contains("B–D倒木近道の処理を確認"), "the concrete action reaches the rendered guide, not just an unused snapshot")
	main.navigation.close()
	check(before == SaveGame.capture(main), "late guide does not spend, unlock, create history or change reservations")
	check(main.world.clear_shortcut(), "normal existing road payment accepts exactly the displayed available materials")
	check(next_id() == "boss_prepare", "opening the route changes the next action to independent boss preparation")
	advice = main.navigation.guide_snapshot().next_step
	check(str(advice.body).contains("採石場の主に挑む（地域目標）") and str(advice.body).contains("護衛") and str(advice.body).contains("帰還準備"), "boss advice supplies a real entry, combat role and exit instead of just a goal name")
	main.craft_ui.open_entry("simple_spear")
	var actual_category: String = main.craft_ui.selected_entry().cat
	check(actual_category == "装備" and str(advice.body).contains("作成 → " + actual_category), "boss weapon directions match the real craft tab containing the suggested recipe")
	main.craft_ui.close()
	main.world.guide_progress.completed.clear()
	check(next_id() == "boss_prepare", "committed road progress survives older saves with missing first-loop history")
	var previous_tools: Array = []
	for worker in main.workers:
		previous_tools.append(worker.tools.duplicate(true))
		worker.tools["mine"] = -1
	check(next_id() == "boss_prepare", "committed route with no mining tool still identifies the boss rather than inventing a tool prerequisite")
	var previous_built: Dictionary = main.base.built.duplicate(true)
	main.base.built.erase("workbench")
	check(not main.has_facility("workbench") and next_id() == "boss_prepare", "route-only legacy save without workbench keeps the remaining regional objective")
	main.base.built = previous_built
	for i in main.workers.size(): main.workers[i].tools = previous_tools[i]
	main.world.region = "c_quarry"
	check(next_id() == "boss_enter", "at C the remaining objective points to the local independent challenge")
	check(str(main.navigation.guide_snapshot().next_step.body).contains("Cの入場選択を開く"), "boss advice can recover a dismissed C choice too")
	completed_region_fixture()
	main.world.region_state.roads.bd.cleared = false
	main.world.region_completion.completed = false
	check(FirstRegionCompletion.valid(main.world.region_completion, main.world.region_state, true, main.workers.size()), "boss-first regression has a valid incomplete regional ledger")
	check(next_id() == "route_materials", "boss-first with empty history still points to the remaining road, not another boss or fabricated first trip")
	advice = main.navigation.guide_snapshot().next_step
	check(str(advice.body).contains("撃破・帰還確定済み"), "boss-first advice acknowledges the already committed result")
	before = SaveGame.capture(main)
	main.navigation.guide_snapshot()
	check(before == SaveGame.capture(main), "respecting legacy milestones never backfills missing guide events")
	main.world.region = "a_start"

func completed_region_fixture() -> void:
	var enemy := {"id":FirstRegionCompletion.BOSS_ID,"kind":"sand_stalker","lane":"採石場の主・独立挑戦","home_x":842.0,"home_y":326.0,"x":842.0,"y":326.0,"hp":0.0,"max_hp":72.0,"attack_left":1.0,"target":"","engager":"","dead":true}
	main.world.region_state.roads.bd.cleared = true
	main.world.region_completion = {"version":1,"encounters":{FirstRegionCompletion.ENCOUNTER_ID:{"cleared":true,"enemies":{FirstRegionCompletion.BOSS_ID:enemy}}},"completed":true}
	check(FirstRegionCompletion.valid(main.world.region_completion, main.world.region_state, true, main.workers.size()), "old-history regression uses a valid completed regional ledger")

func field_visibility() -> void:
	main.queue_free(); await process_frame
	paused = false; SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate(); main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 104729); root.add_child(main); await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED; main.director.enabled = false
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list(): worker.priorities[job] = 0
	for destination in ["b_forest", "c_quarry"]:
		check(main.world.request(destination), "guide ownership fixture takes ordinary road to " + destination)
		for tick in range(300):
			main._process(0.25); await process_frame
			if main.world.region == destination and main.world.phase == "stopped": break
	var gate = main.mine_arrival_gate; var nav = main.navigation
	gate._process(0.0); nav._process(0.0)
	check(gate.visible_state() == "arrival_choice", "actual C arrival choice owns its UI")
	check(not nav.guide_hint.visible, "mine arrival choice suppresses the lower-layer suggestion")
	check(gate.enter_mine(), "normal mine entry succeeds for visibility test")
	if gate.field == null: return
	var field = gate.field; field.process_mode = Node.PROCESS_MODE_DISABLED
	nav._process(0.0)
	check(not nav.guide_hint.visible, "active field never retains a clickable horizontal suggestion")
	field.session.request_recall()
	for tick in range(800):
		if field.session.phase == "ready_to_exit": break
		field.life_clock.tick(0.1)
	check(field.session.phase == "ready_to_exit", "real field recall reaches safe return")
	field._commit_and_exit(); await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED; nav._process(0.0)
	check(gate.field == null and nav.guide_hint.visible, "ordinary field return restores the horizontal suggestion")
func finish() -> void:
	paused = false
	if is_instance_valid(main): main.queue_free()
	await process_frame
	SaveGame.disabled = false
	print("NEXT STEP GUIDE failures=", failures)
	quit(1 if failures else 0)
