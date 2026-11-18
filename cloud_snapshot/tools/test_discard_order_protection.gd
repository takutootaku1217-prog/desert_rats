extends SceneTree
## Warehouse discard must protect materials held for unstarted player production orders and queued builds,
## exactly like the town sale (TownEconomy.available). The inventory row shows them as reserved.
## Fixture (labeled): starting stock is set directly; the order / build requests use the real Main APIs that
## the craft (F) and build (B) screens call. Workers and the director are stopped so nothing is consumed.
var main
var checks := 0
var failures := 0
const STONE := GameData.Item.STONE
const WOOD := GameData.Item.WOOD

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("%s %s" % ["ok" if ok else "FAIL", label])
	if not ok: failures += 1

func row(item: int) -> Dictionary:
	return main.warehouse_stock_row(item)

func run() -> void:
	if OS.get_environment("FLUID_TEST_HOME") == "": quit(2); return
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 20261118)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	for w in main.workers: w.stop_work()
	main.storage.inventory.counts = {STONE: 3}

	# A stone pickaxe order (stone 2 + wood 1) with wood missing: its stone stays in the warehouse, unstarted.
	check(main.request_order("tool_hammer", 1) == 1 and main.production_orders.size() == 1, "player orders one stone pickaxe (materials incomplete, order unstarted)")
	check(main.warehouse_discard_limit(STONE) == 1, "only the stone beyond the order is discardable (available %d of 3)" % main.warehouse_discard_limit(STONE))
	check(row(STONE).owned == 3 and row(STONE).reserved == 2 and row(STONE).usable == 1, "the inventory row shows the order's stone as reserved: %s" % str(row(STONE)))
	check(main.town.available(STONE) == main.warehouse_discard_limit(STONE), "town sale and discard agree on the free stone (%d / %d)" % [main.town.available(STONE), main.warehouse_discard_limit(STONE)])
	check(main.warehouse_discard_snapshot(STONE, 2).is_empty(), "a discard of 2 stone is refused (it would eat the order's materials)")
	var snap: Dictionary = main.warehouse_discard_snapshot(STONE, 1)
	check(not snap.is_empty() and main.discard_warehouse(snap) and main.storage.count_of(STONE) == 2, "discarding the 1 surplus stone works and leaves the 2 for the order")
	check(main.warehouse_discard_limit(STONE) == 0 and main.warehouse_discard_snapshot(STONE, 1).is_empty(), "nothing more is discardable while the order waits")

	# The confirmation re-checks at execution: an order placed after the confirmation opened blocks it.
	main.storage.inventory.counts[STONE] = 4
	main.cancel_manual_craft("tool_hammer")
	var early: Dictionary = main.warehouse_discard_snapshot(STONE, 4)
	check(not early.is_empty(), "with no order all 4 stone are discardable (confirmation opened)")
	main.request_order("tool_hammer", 1)
	check(not main.discard_warehouse(early) and main.storage.count_of(STONE) == 4, "an order placed while the confirmation was open makes the stale discard fail; nothing is lost")

	# Cancelling the order frees the stone again.
	main.cancel_manual_craft("tool_hammer")
	check(main.production_orders.is_empty() and main.warehouse_discard_limit(STONE) == 4 and row(STONE).reserved == 0, "after cancelling the order all stone is discardable again")

	# A queued build (workbench: wood 3) also protects its materials; it is counted once, not twice.
	main.storage.inventory.counts = {WOOD: 5}
	check(main.request_build("workbench"), "player queues the workbench build (wood 3)")
	check(main.warehouse_discard_limit(WOOD) == 2, "only the wood beyond the queued build is discardable (available %d of 5)" % main.warehouse_discard_limit(WOOD))
	check(main.town.available(WOOD) == main.warehouse_discard_limit(WOOD), "town sale and discard agree on the free wood (%d / %d)" % [main.town.available(WOOD), main.warehouse_discard_limit(WOOD)])
	check(main.warehouse_discard_available(WOOD) == 5, "the shared unreserved count (road payment, fuel service, armor, guide) is unchanged by the queued build (%d)" % main.warehouse_discard_available(WOOD))
	main.cancel_build("workbench")
	check(main.warehouse_discard_limit(WOOD) == 5, "cancelling the build frees the wood")

	print("RESULT checks=%d failures=%d" % [checks, failures])
	main.queue_free()
	await process_frame
	SaveGame.disabled = false
	quit(1 if failures > 0 else 0)
