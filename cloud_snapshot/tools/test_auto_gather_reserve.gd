extends SceneTree
## 実際の拠点と仲間で採取を進める。在庫の直接操作は積載・道具の初期条件だけ。

const Guide = preload("res://ui/first_loop_guide.gd")
const STEP := 0.2
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const ORE := GameData.Item.IRON_ORE
const FILLER := GameData.Item.HIDE

var main
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _new_main() -> void:
	if is_instance_valid(main):
		main.free()
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	main.target_speed = 0.0
	for setting in main.refill_settings.values():
		setting.enabled = false
	# 診断中に食事で空きが増えないよう、初期食料を除く。
	main.storage.inventory.take_n(GameData.Item.FOOD, _count(GameData.Item.FOOD))
	for worker in main.workers:
		worker.stop_work()
	# 地域の既定の資源を外し、診断で置いた採取ポイントだけを使う。
	main.world.locations[main.world.key()] = {}
	for node in main.resources_root.get_children() + main.creatures_root.get_children():
		node.free()


func _free_weight() -> int:
	return main.storage.max_weight() - main.storage.current_weight()


func _reserve() -> int:
	return ceili(main.storage.max_weight() * CargoDB.AUTO_GATHER_RESERVE_RATIO)


func _count(item: int) -> int:
	return main.storage.count_of(item)


func _fixture_load(free_weight: int) -> void:
	# 積載境界を再現するため、重さ1の皮で残り重量を設定。
	var n := _free_weight() - free_weight
	_check(n >= 0 and main.storage.add_item(FILLER, n) == n, "fixture: cargo now has %d free weight" % free_weight)


func _fixture_pickaxes() -> void:
	# 石・鉱床の道具条件を満たす初期装備。
	for worker in main.workers:
		main.storage.add_item(GameData.Item.HAMMER, 1)
		_check(main.equip_tool(worker, GameData.Item.HAMMER), "fixture: stone pickaxe equipped")


func _point(kind: String, x: float = 650.0) -> GatherPoint:
	var point := GatherPoint.new()
	point.setup(main, kind)
	point.position = Vector2(x, 610)
	main.resources_root.add_child(point)
	return point


func _advance(seconds: float, until := Callable()) -> bool:
	for frame in ceili(seconds / STEP):
		main._process(STEP)
		for worker in main.workers:
			worker._process(STEP)
		if until.is_valid() and until.call():
			return true
		if frame % 48 == 0:
			await process_frame
	return false


func _automatic_and_reload() -> void:
	_new_main()
	_fixture_pickaxes()
	_fixture_load(_reserve() + 72)
	var tree: GatherPoint
	var rock: GatherPoint
	for i in 6:
		tree = _point("tree", 640.0 + i * 12)
	var wood_before := _count(WOOD)
	var stone_before := _count(STONE)
	_check(await _advance(5.0, func(): return not main.gather_room().is_empty()), "workers start on available wood")
	for i in 6:
		rock = _point("rock", 650.0 + i * 12)
	await _advance(90.0)
	var free := _free_weight()
	_check(_count(WOOD) > wood_before and _count(STONE) > stone_before, "default policy gathered both wood and stone")
	_check(free >= _reserve() and free < _reserve() + CargoDB.size_of(WOOD) and main.gather_room().is_empty(),
		"all bags landed and automatic gathering stopped at free=%d, reserve=%d" % [free, _reserve()])
	_check(tree.available() and rock.available() and main.gather_point_hint(tree) == "積載の空きを残すため自動採取を止めています",
		"usable points remain and explain why automatic gathering stopped")

	const PATH := "user://auto_gather_reserve_test.json"
	SaveGame.disabled = false
	var saved := SaveGame.write(main, PATH)
	SaveGame.disabled = true
	_check(saved, "save while at reserve: %s" % SaveGame.last_error)
	var snapshot := SaveGame.read(PATH)
	var wood := _count(WOOD)
	var stone := _count(STONE)
	_new_main()
	_check(SaveGame.apply(main, snapshot), "reload the blocked state")
	var points: Array = main.resources_root.get_children()
	await _advance(45.0)
	_check(not points.is_empty() and _count(WOOD) == wood and _count(STONE) == stone
		and points.all(func(point): return point.claimed_by == null),
		"wood and stone stay blocked after reload (free %d → %d)" % [free, _free_weight()])


func _requests() -> void:
	_new_main()
	_fixture_load(_reserve())
	var wood := _count(WOOD)
	var target := int(main.build_cost("workbench")[WOOD])
	var tree := _point("tree")
	_check(wood < target and main.request_build("workbench"), "queued build has a wood shortfall")
	# 組み立てへ運ぶ前の不足解消を観察する。
	for worker in main.workers:
		worker.set_priority(GameData.Job.HAUL, 0)
	await _advance(85.0)
	_check(_count(WOOD) == target and _free_weight() < _reserve() and tree.claimed_by == null,
		"build gathers exactly its wood shortfall using the reserve")

	_fixture_pickaxes()
	var rock := _point("rock")
	var goal := _count(STONE) + 3
	main.set_procurement(STONE, goal)
	await _advance(85.0)
	_check(_count(STONE) == goal and rock.claimed_by == null and not main.procurement_goals.has(STONE),
		"player procurement uses the reserve and stops exactly at its target")

	# プレイヤー注文の素材不足を採取で解消する。搬入担当は引き続き無効。
	var recipe := GameData.recipe_by_id("repair_stone")
	var orders := _count(STONE) + 1
	var order_target := orders * int(recipe["in"][STONE])
	_check(main.request_order("repair_stone", orders) == orders and not main.production_orders.is_empty(),
		"player production order requests missing stone")
	_point("rock", 700.0)
	await _advance(65.0)
	_check(_count(STONE) == order_target, "production order uses only its missing stone")

	var worker = main.workers[0]
	wood = _count(WOOD)
	main.set_gather_focus(worker, WOOD)
	_check(await _advance(35.0, func(): return _count(WOOD) > wood), "individual wood request can also use reserve space")


func _ore_and_warning() -> void:
	_new_main()
	_fixture_pickaxes()
	_fixture_load(32)
	var tree := _point("tree")
	var rock := _point("rock")
	var ore := _point("vein")
	var before := SaveGame.capture(main)
	var warning := Guide.snapshot(main)
	var recommendation := Guide.recommendation(main, warning)
	_check(warning.cargo.near_full and str(warning.next_step.body).contains("積載の残りが少ない")
		and str(warning.sections[1].title).begins_with("積載の残りが少ない")
		and warning.next_step.id == recommendation.id, "near-full warning appears below 10% and preserves the next step")
	var remedies := str(warning.sections[1].body)
	_check(remedies.contains("購買店") and remedies.contains("廃棄") and remedies.contains("回収の優先")
		and remedies.contains("収納ボックス") and SaveGame.capture(main) == before, "warning explains all four remedies without changing the save")
	var wood := _count(WOOD)
	var stone := _count(STONE)
	var ore_before := _count(ORE)
	await _advance(50.0)
	_check(_count(ORE) == ore_before + 4 and _free_weight() == 0 and ore.available(),
		"stone pickaxe gathers ore until true capacity")
	_check(_count(WOOD) == wood and _count(STONE) == stone and tree.claimed_by == null and rock.claimed_by == null,
		"wood and stone stayed blocked while ore was gathered")
	_check(main.discard_warehouse(main.warehouse_discard_snapshot(FILLER, _reserve())), "use the existing discard action to make room")
	var relieved := Guide.snapshot(main)
	_check(not relieved.cargo.near_full and not str(relieved.next_step.body).contains("積載の残りが少ない"),
		"warning disappears when there is room")


func _reserved_bag() -> void:
	_new_main()
	_fixture_load(_reserve() + 32)
	var tree := _point("tree")
	var wood := _count(WOOD)
	_check(await _advance(5.0, func(): return tree.claimed_by != null), "real AI reserves a wood bag before reaching the reserve")
	var bag := tree.reserved
	var remaining := tree.remaining
	# 積載境界の変化を再現する。確保済みの袋は物理容量には収まる。
	_fixture_load(_reserve() - 4)
	var weight: int = main.storage.current_weight()
	await _advance(45.0)
	_check(bag > 0 and _count(WOOD) == wood + bag and tree.remaining == remaining - bag
		and main.storage.current_weight() == weight + bag * CargoDB.size_of(WOOD)
		and main.gather_room().is_empty(), "reserved bag=%d, delivered=%d, depleted=%d, weight delta=%d" % [
			bag, _count(WOOD) - wood, remaining - tree.remaining, main.storage.current_weight() - weight])


func _run() -> void:
	SaveGame.disabled = true
	seed(104729)
	await _automatic_and_reload()
	await _requests()
	await _ore_and_warning()
	await _reserved_bag()
	main.free()
	quit(1 if failures else 0)
