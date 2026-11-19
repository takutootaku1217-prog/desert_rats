extends SceneTree
## Internal input-handler and save regression for the ordinary vehicle interior.
## Fixtures set stock, worker positions and equipment directly; OS input is verified separately.
const FOOD := GameData.Item.FOOD
const WOOD := GameData.Item.WOOD
var game
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("%s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1

func click_slot(slot: String) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.get_canvas_transform() * game.base.to_global(Rooms.overlay_rect(slot).get_center())
	game._unhandled_input(click)

func run() -> void:
	if OS.get_environment("FLUID_TEST_HOME").is_empty():
		quit(2)
		return
	SaveGame.disabled = true
	game = load("res://scenes/main.tscn").instantiate()
	game.first_region_a_pilot = true
	game.set_meta("diagnostic_seed", 20261119)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.director.enabled = false
	game.close_other_panels(null)
	for worker in game.workers:
		worker.stop_work()
		worker.set_process(false)
		worker.hide()
	var ui = game.room_ui
	var worker = game.workers[0]
	var old_position: Vector2 = worker.position
	worker.position = game.base.to_global(Rooms.overlay_rect("u3").get_center()) + Vector2(0, 25)
	worker.show()
	click_slot("u3")
	check(game.follow_target == worker and not ui.is_open(), "a visible crew member wins overlapping room hit")
	worker.position = old_position
	worker.hide()
	game.follow_target = null
	game.close_other_panels(null)
	game.base.set_view_exterior(true)
	click_slot("u3")
	check(not ui.is_open(), "exterior cannot open interior rooms")
	game.base.set_view_exterior(false)
	click_slot("u3")
	if not ui.is_open():
		check(false, "an interior click opens the selected slot")
		quit(1)
		return
	check(ui._slot == "u3", "an interior click opens the selected slot")
	game.storage.inventory.counts = {FOOD: 3, WOOD: 1}
	check(not game.can_build_room("u3", "mess"), "short stock blocks building")
	game.storage.inventory.counts[WOOD] = 4
	ui._preview("mess")
	check(game.storage.count_of(WOOD) == 4, "preview uses no materials")
	ui._cancel_preview()
	check(game.room_layout.u3 == "empty" and game.storage.count_of(FOOD) == 3, "cancel leaves layout and stock alone")
	ui._preview("mess")
	check(game.request_build("workbench") and game.warehouse_stock_row(WOOD).usable == 1, "queued workbench reserves three wood")
	ui._confirm_preview()
	check(game.room_layout.u3 == "empty" and game.storage.count_of(WOOD) == 4, "confirmation rechecks reserved materials")
	game.cancel_build("workbench")
	var before: float = game.room_effect("drain_cut")
	worker.ai.state = CharacterAI.State.HAUL_MOVE
	var fatigue_without := _fatigue_gain(worker)
	ui._preview("mess")
	ui._confirm_preview()
	ui._confirm_preview()
	check(game.room_layout.u3 == "mess" and game.storage.count_of(WOOD) == 2 and game.storage.count_of(FOOD) == 0, "build spends precisely one set even on repeat")
	check(is_equal_approx(game.room_effect("drain_cut"), before + 0.12), "dining room applies existing fatigue reduction")
	check(is_equal_approx(_fatigue_gain(worker), fatigue_without * 0.88), "existing crew fatigue calculation uses dining room")
	ui._preview("empty")
	ui._confirm_preview()
	ui._confirm_preview()
	check(game.room_layout.u3 == "empty" and is_equal_approx(game.room_effect("drain_cut"), before), "demolition removes the effect")
	check(is_equal_approx(_fatigue_gain(worker), fatigue_without), "crew fatigue returns to its original rate")
	worker.stop_work()
	check(game.storage.count_of(WOOD) == 2 and game.storage.count_of(FOOD) == 0, "demolition returns no raw materials")
	check(not game.build_room("u1", "empty") and not game.build_room("u2", "empty") and not game.build_room("l2", "empty"), "required rooms cannot be demolished")
	ui.close()
	ui.open()
	ui.select_slot("u3")
	check(not ui._interior and ui._slot == "u3", "R management uses the same slot and actions")
	game.storage.inventory.counts = {FOOD: 6, WOOD: 6, GameData.Item.IRON: 2, GameData.Item.STONE: 2}
	ui._preview("mess")
	ui._confirm_preview()
	check(game.build_room("l1", "engine"), "fixture: build the optional engine room")
	game.base.refuel_reserved = true
	check(not game.build_room("l1", "empty") and game.room_block_reason("l1", "empty").contains("補給"), "an engine room in use cannot be demolished")
	game.base.refuel_reserved = false
	check(game.build_room("l1", "empty"), "the optional engine room can be dismantled when idle")

	game.finish_build("bed")
	game.base.beds[0] = worker
	check(game.facility_pack_reason("bed", 0).contains("休息") and not game.build_room("u2", "empty"), "active bed cannot be packed or removed with its room")
	game.base.beds[0] = null
	game.finish_build("cargo_rack")
	var previous_stock: Dictionary = game.storage.inventory.counts.duplicate()
	game.storage.inventory.counts[WOOD] = game.storage.max_weight()
	check(game.facility_pack_reason("cargo_rack", 0).contains("容量不足") and not game.build_room("l2", "empty"), "capacity loss and return cargo are checked by existing packing rules")
	game.storage.inventory.counts = previous_stock

	game.storage.inventory.counts[GameData.Item.IRON] = 2
	game.storage.inventory.counts[WOOD] = 6
	ui.select_slot("l3")
	ui._preview("workshop")
	ui._confirm_preview()
	check(game.room_layout.l3 == "workshop" and Rooms.count(game.room_layout, "workshop") == 1
		and game.base.facility_count("workbench") == 0, "relocation keeps one workshop and constructs no workbench")
	game.finish_build("workbench")
	check(game.request_order("tool_wood_pick", 1) == 1 and game.facility_pack_reason("workbench", 0).contains("製作依頼"), "existing workbench accepts production and cannot pack with dependent order")
	game.cancel_manual_craft("tool_wood_pick")
	game.queue_free()
	await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	game.set_meta("diagnostic_seed", 20261119)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.director.enabled = false
	for crew in game.workers:
		crew.stop_work()
		crew.set_process(false)
	game.storage.inventory.counts = {FOOD: 6, WOOD: 4}
	check(game.build_room("u3", "mess"), "fixture: add a dining room to the legacy-map vehicle")
	_test_legacy_save()

	print("RESULT checks=%d failures=%d" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _fatigue_gain(worker) -> float:
	worker.fatigue = 0.0
	CrewStatus._tick_fatigue(worker, 1.0)
	return worker.fatigue


func _test_legacy_save() -> void:
	# Build a v2 envelope in the QA profile using fields supported by the existing
	# migration. No production save is read or overwritten.
	var old_path := "user://interior_room_ui_v2.fixture"
	var new_path := "user://interior_room_ui_v3.fixture"
	var snapshot := SaveGame.capture(game)
	snapshot.version = 2
	snapshot.erase("world")
	for section in ["resources", "creatures", "enemies"]:
		snapshot[section] = []
	var bytes := var_to_bytes(snapshot)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var file := FileAccess.open(old_path, FileAccess.WRITE)
	if file == null:
		check(false, "write isolated legacy fixture")
		return
	file.store_string(JSON.stringify({"version": 2, "payload": Marshalls.raw_to_base64(bytes), "sha256": hash.finish().hex_encode()}))
	file.close()
	var original_hash := FileAccess.get_sha256(old_path)
	game.room_layout = Rooms.default_layout()
	game.storage.inventory.counts = {}
	var migrated := SaveGame.migrate_v2(SaveGame.read(old_path, true), game)
	check(not migrated.is_empty() and SaveGame.apply(game, migrated), "read and apply a version 2 fixture: " + SaveGame.last_error)
	SaveGame.disabled = false
	check(SaveGame.write(game, new_path), "resave the migrated snapshot: " + SaveGame.last_error)
	var saved := SaveGame.read(new_path)
	check(saved.get("main", {}).get("room_layout", {}) == snapshot.main.room_layout
		and saved.get("inventory") == snapshot.inventory and is_equal_approx(game.room_effect("drain_cut"), 0.12)
		and FileAccess.get_sha256(old_path) == original_hash, "resave preserves layout, stock and effect while keeping the old fixture intact")
