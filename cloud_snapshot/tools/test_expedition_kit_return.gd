extends SceneTree
## A repair kit taken on a ruin expedition is owned cargo the whole time. When it is not used it comes back
## to storage exactly once on return (complete or retreat); a used kit is consumed. Save/load mid-run and
## re-applying a post-finish save never duplicate it.
## Fixture (labeled): starting stock {FOOD 2, KIT 1}, the offered ruin, the step list and the RNG seed are set
## by the test so the outcome (kit used / unused / retreat) is deterministic. The finish logic itself is the
## real Expedition.tick() -> _resolve_step() -> _finish() path. No OS input.
var main
var checks := 0
var failures := 0
const FOOD := GameData.Item.FOOD
const KIT := GameData.Item.REPAIR_KIT
const PHRASE := "使わなかった応急修理板を持ち帰った"

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("%s %s" % ["ok" if ok else "FAIL", label])
	if not ok: failures += 1

func finish() -> void:
	print("RESULT checks=%d failures=%d" % [checks, failures])
	if is_instance_valid(main): main.queue_free()
	await process_frame
	SaveGame.disabled = false
	quit(1 if failures > 0 else 0)

func fresh() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.first_region_a_pilot = true
	main.set_meta("diagnostic_seed", 20261118)
	root.add_child(main)
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.enabled = false
	for w in main.workers: w.stop_work()

## Reset to a clean offered ruin with the fixture stock, depart with one member carrying the kit.
func depart(steps: Array, fatigue: float) -> Variant:
	var ex = main.expedition
	for w in main.workers:
		if w.away: w.arrive(0.0)
		w.fatigue = 0.0
	ex.state = "idle"
	ex.offer("ruins_small")
	main.storage.inventory.counts = {FOOD: 2, KIT: 1}
	var w = main.workers[0]
	if not ex.start([w], "normal", true): return null
	w.fatigue = fatigue
	ex.steps = steps.duplicate()
	return w

func run_to_end() -> void:
	var ex = main.expedition
	var guard := 0
	while ex.state == "running" and guard < 20:
		ex.tick(ex.step_time + 1.0)
		guard += 1

func run() -> void:
	if OS.get_environment("FLUID_TEST_HOME") == "": quit(2); return
	SaveGame.disabled = true
	await fresh()
	var ex = main.expedition

	# 1) Unused kit, normal end: explore failures never consume the kit.
	var w = depart(["explore", "explore", "explore"], 0.0)
	check(w != null and ex.state == "running" and main.storage.count_of(KIT) == 0, "fixture: one member departs with the only kit (kit leaves the warehouse)")
	var weight_running: int = main.storage.current_weight()
	run_to_end()
	var kit_loot: int = int(ex.loot.get(KIT, 0))
	check(ex.state == "done" and not ex.retreated and not ex.kit_used, "unused case ends normally without using the kit")
	check(main.storage.count_of(KIT) == 1 + kit_loot, "the unused kit comes back exactly once (kit=%d, kit loot=%d)" % [main.storage.count_of(KIT), kit_loot])
	var loot_weight := 0
	for it in ex.loot: loot_weight += CargoDB.size_of(it) * int(ex.loot[it])
	check(main.storage.current_weight() == weight_running + loot_weight, "owned weight is exact across the finish: before %d + loot %d = after %d (the kit was counted all along)" % [weight_running, loot_weight, main.storage.current_weight()])
	check(ex.log.has(PHRASE), "the expedition log says the unused kit was brought back")
	var done_counts: Dictionary = main.storage.inventory.counts.duplicate()
	for i in 10: ex.tick(30.0)
	check(main.storage.inventory.counts == done_counts, "waiting on the result screen does not return it again")

	# 2) Used kit: a non-explore failure is absorbed by the kit; it is consumed and not returned.
	var used_seed := -1
	for s in range(1, 400):
		w = depart(["trap", "trap", "trap"], 0.0)
		seed(s)
		run_to_end()
		if ex.kit_used:
			used_seed = s
			break
	check(used_seed > 0, "fixture: a seed where a trap failure is absorbed by the kit (seed %d)" % used_seed)
	if used_seed > 0:
		check(main.storage.count_of(KIT) == int(ex.loot.get(KIT, 0)), "a used kit is consumed and not returned (kit=%d, kit loot=%d)" % [main.storage.count_of(KIT), int(ex.loot.get(KIT, 0))])
		check(not ex.log.has(PHRASE), "no 'brought back' line when the kit was used")

	# 3) Retreat with the kit unused: the kit still comes back.
	var retreat_seed := -1
	for s in range(1, 400):
		w = depart(["explore", "explore", "explore"], 95.0)
		seed(s)
		run_to_end()
		if ex.retreated:
			retreat_seed = s
			break
	check(retreat_seed > 0, "fixture: a seed where the party retreats on an explore failure (seed %d)" % retreat_seed)
	if retreat_seed > 0:
		check(not ex.kit_used and main.storage.count_of(KIT) == 1 + int(ex.loot.get(KIT, 0)), "after a retreat the unused kit comes back exactly once")
		check(ex.log.has(PHRASE), "retreat log also says the kit was brought back")

	# 4) Save mid-run -> load -> finish returns the kit once; re-applying a post-finish save never duplicates.
	w = depart(["explore", "explore", "explore"], 0.0)
	ex.tick(ex.step_time + 1.0)
	check(ex.state == "running" and ex.step_i == 1, "fixture: one step done, still running")
	var mid: Dictionary = SaveGame.capture(main)
	var kit_at_save: int = main.storage.count_of(KIT)
	run_to_end()
	check(main.storage.count_of(KIT) == kit_at_save + 1 + int(ex.loot.get(KIT, 0)), "first finish from the running state returns the kit once")
	check(SaveGame.apply(main, mid), "the mid-run save loads")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	check(ex.state == "running" and ex.kit and not ex.kit_used and main.storage.count_of(KIT) == kit_at_save, "after loading: running with the kit still away, warehouse kit count as saved")
	run_to_end()
	var final_kits: int = main.storage.count_of(KIT)
	check(final_kits == kit_at_save + 1 + int(ex.loot.get(KIT, 0)), "finishing after the load returns the kit exactly once (kit=%d)" % final_kits)
	var post: Dictionary = SaveGame.capture(main)
	check(SaveGame.apply(main, post), "the post-finish save loads")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 10: ex.tick(30.0)
	check(main.storage.count_of(KIT) == final_kits, "re-applying the post-finish save and waiting never returns it again")
	await finish()
