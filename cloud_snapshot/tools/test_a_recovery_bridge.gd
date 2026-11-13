extends SceneTree
## A地域横視点→C固定クォータービュー→横視点の接続境界を、通常 user:// を使わずに検証する。

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FIXTURE_SESSION := "bridge_resume_session.json"
const FIXTURE_RESULT := "bridge_resume_result.json"
const STEP := 0.2

var main
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_cmdline_user_args().has("bridge-resume"):
		await _resume_process()
		return
	await _three_continuous_cycles()
	if fails == 0:
		await _route_and_capacity_boundaries()
	if fails == 0:
		await _fresh_process_restore()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)

func check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func fresh() -> void:
	if main != null:
		root.remove_child(main)
		main.free()
	SaveGame.disabled = true
	main = load("res://scenes/main.tscn").instantiate()
	main.set("first_region_a_pilot", true)
	main.set_meta("diagnostic_seed", 104729)
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	main.director.enabled = false
	if main.save_ui != null:
		main.save_ui.visible = false
		main.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	for worker in main.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.priorities[job] = 0

func step_world() -> void:
	main._process(STEP)
	await process_frame

func move_leg(destination: String) -> bool:
	if not main.world.request(destination):
		return false
	for unused in 240:
		await step_world()
		if main.world.phase == "stopped" and main.world.region == destination:
			return true
	return main.world.phase == "stopped" and main.world.region == destination

func move_to_quarry() -> bool:
	if main.world.region == "a_start":
		if not await move_leg("b_forest"):
			return false
	if main.world.region == "b_forest":
		return await move_leg("c_quarry")
	return main.world.region == "c_quarry" and main.world.phase == "stopped"

func move_to_start() -> bool:
	if main.world.region == "c_quarry":
		if not await move_leg("b_forest"):
			return false
	if main.world.region == "b_forest":
		return await move_leg("a_start")
	return main.world.region == "a_start" and main.world.phase == "stopped"

func make_session(tag: String):
	var created: Dictionary = RouteSession.create_from_game(main, tag)
	check(bool(created.get("ok", false)), tag + ": Cの既存有限資源と既存仲間からsessionを作成")
	return created.get("session", null)

func advance_until(session, predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		session.tick(STEP)
		var projection: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projection.get("ok", false)):
			return false
		if predicate.call():
			return true
	return predicate.call()

func stock_for_session(session) -> int:
	var total := 0
	var seen := {}
	for resource_id in session.resources:
		var item := int(session.resources[resource_id].item)
		if not seen.has(item):
			seen[item] = true
			total += main.storage.count_of(item)
	return total

func settle_and_commit(session, label: String) -> Dictionary:
	var collected := await advance_until(session, func(): return int(session.state_summary().depot) > 0, 80.0)
	check(collected, label + ": 回収役→relay→運搬役→駐車基地の一周が進行")
	check(session.conservation_ok(), label + ": 現地の資源保存則")
	session.request_recall()
	var ready := await advance_until(session, func(): return session.phase == "ready_to_exit", 80.0)
	check(ready, label + ": 帰還指示で予約・手持ち・relay・入口列を解消")
	var stock_before := stock_for_session(session)
	var deposited := int(session.state_summary().depot)
	var source_before: int = session.total_source_remaining()
	var committed: Dictionary = session.commit_to_game(main)
	check(bool(committed.get("ok", false)), label + ": 本編台帳へ一回だけ確定")
	check(stock_for_session(session) == stock_before + deposited, label + ": 本編拠点在庫へ一回だけ搬入")
	check(main.world.locations[RouteSession.SOURCE_KEY] is Dictionary and session.total_source_remaining() == source_before, label + ": C有限資源の残量を維持")
	var repeat: Dictionary = session.commit_to_game(main)
	check(bool(repeat.get("ok", false)) and bool(repeat.get("already_committed", false)) and stock_for_session(session) == stock_before + deposited, label + ": 二重確定で在庫を増殖しない")
	return committed

func _three_continuous_cycles() -> void:
	print("-- 3連続 A→C→固定画面→A")
	await fresh()
	for cycle in 3:
		if not await move_to_quarry():
			check(false, "cycle %d: 既存WorldTripでA→B→Cへ横移動" % (cycle + 1))
			return
		check(true, "cycle %d: 既存WorldTripでA→B→Cへ横移動" % (cycle + 1))
		var session = make_session("cycle-%d" % (cycle + 1))
		if session == null:
			return
		await settle_and_commit(session, "cycle %d" % (cycle + 1))
		if cycle == 1:
			check(main.world.request("b_forest"), "cycle 2: C→B復路を開始")
			for unused in 8:
				await step_world()
			var snapshot := stock_for_session(session)
			check(main.world.cancel_or_return(), "cycle 2: 横視点の復路を途中取消")
			var returned_to_c := false
			for unused in 240:
				await step_world()
				if main.world.phase == "stopped" and main.world.region == "c_quarry":
					returned_to_c = true
					break
			check(returned_to_c and stock_for_session(session) == snapshot, "cycle 2: 取消で貨物・仲間数を増減せずCへ戻る")
		check(await move_to_start(), "cycle %d: 既存WorldTripでC→B→Aへ横移動" % (cycle + 1))
		check(main.workers.size() == 3 and main.workers.all(func(worker): return worker.carrying < 0), "cycle %d: 仲間の個体数と手持ちを正常化" % (cycle + 1))

func _route_and_capacity_boundaries() -> void:
	print("-- 閉鎖・到達不能・満載")
	if not await move_to_quarry():
		check(false, "境界試験: A→Cへ再入場")
		return
	check(true, "境界試験: A→Cへ再入場")
	var blocked = make_session("blocked-route")
	if blocked != null:
		blocked.set_gate_closed(true)
		var before_block: int = blocked.path_requests
		blocked.set_all_routes_closed(true)
		await advance_until(blocked, func(): return blocked.actors["worker:0"].state == "safe_wait", 4.0)
		var settled_requests: int = blocked.path_requests
		for unused in 20:
			blocked.tick(STEP)
		check(settled_requests >= before_block and blocked.path_requests == settled_requests, "全経路閉鎖は安全待機へ移り毎frame再探索しない")
		blocked.set_all_routes_closed(false)
		var recovered := await advance_until(blocked, func(): return int(blocked.state_summary().depot) > 0, 80.0)
		check(recovered and blocked.gate_closed and blocked.conservation_ok(), "主経路閉鎖時は迂回路で回収を再開")
		blocked.request_recall()
		check(await advance_until(blocked, func(): return blocked.phase == "ready_to_exit", 80.0), "閉鎖試験後も安全に現地を解消")
		var original_bonus: int = main.storage.capacity_bonus
		main.storage.capacity_bonus = -CargoDB.CAPACITY
		var inventory_before := stock_for_session(blocked)
		var rejected: Dictionary = blocked.commit_to_game(main)
		check(not bool(rejected.get("ok", false)) and stock_for_session(blocked) == inventory_before and blocked.phase == "ready_to_exit", "満載時は本編搬入を拒否し貨物を消失・重複させない")
		main.storage.capacity_bonus = original_bonus
		var recovered_commit: Dictionary = blocked.commit_to_game(main)
		check(bool(recovered_commit.get("ok", false)), "空きを戻すと同じsessionを一回だけ搬入できる")
	check(await move_to_start(), "境界試験後もC→Aへ帰還")

func _fresh_process_restore() -> void:
	print("-- 運搬中のproject-local保存→新Godotプロセス復元")
	await fresh()
	if not await move_to_quarry():
		check(false, "保存試験: A→Cへ移動")
		return
	check(true, "保存試験: A→Cへ移動")
	var session = make_session("fresh-process")
	if session == null:
		return
	var carrying := await advance_until(session, func(): return session.carried_total() > 0 or not session.reservations.is_empty(), 30.0)
	check(carrying, "保存前に予約または運搬中の実在仲間へ到達")
	var saved: Dictionary = session.save_project_fixture(FIXTURE_SESSION)
	check(bool(saved.get("ok", false)), "通常 user:// を使わずproject-local fixtureへ保存")
	var output: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/test_a_recovery_bridge.gd", "--", "bridge-resume"]
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	for line in output:
		print(line)
	check(code == 0, "新Godotプロセスで運搬中bridge sessionを復元して帰還")
	var read := _read_fixture(FIXTURE_RESULT)
	check(bool(read.get("ok", false)) and bool(read.get("data", {}).get("passed", false)), "fresh processの仲間ID・装備・数量・予約照合")

func _resume_process() -> void:
	await fresh()
	var checks: Array = []
	_record_to(checks, await move_to_quarry(), "fresh processでA→Cを既存WorldTripにより再到達")
	var loaded: Dictionary = RouteSession.load_project_fixture(FIXTURE_SESSION)
	_record_to(checks, bool(loaded.get("ok", false)), "project-local bridge fixtureを読込")
	if bool(loaded.get("ok", false)):
		var session = loaded.session
		var projected: Dictionary = session.apply_projection_to_workers(main)
		_record_to(checks, bool(projected.get("ok", false)), "仲間ID・名前・装備を照合して投影")
		_record_to(checks, session.conservation_ok(), "読込直後の資源保存則")
		session.request_recall()
		var ready := await advance_until(session, func(): return session.phase == "ready_to_exit", 80.0)
		_record_to(checks, ready, "読込後に予約・手持ち・relay・入口列を解消")
		var committed: Dictionary = session.commit_to_game(main)
		_record_to(checks, bool(committed.get("ok", false)), "fresh processで一回だけ本編へ搬入")
		_record_to(checks, main.workers.all(func(worker): return worker.carrying < 0) and session.conservation_ok(), "offscreen投影後も仲間手持ちと数量を二重処理しない")
	var passed := checks.all(func(row): return bool(row.passed))
	_write_fixture(FIXTURE_RESULT, {"passed": passed, "checks": checks, "normal_user_save_touched": false})
	print("== 結果: %s ==" % ("すべて成功" if passed else "fresh process失敗"))
	quit(0 if passed else 1)

func _record_to(rows: Array, ok: bool, text: String) -> void:
	rows.append({"name": text, "passed": ok})
	print("  %s %s" % ["ok" if ok else "FAIL", text])

func _read_fixture(file_name: String) -> Dictionary:
	var path := RouteSession.project_fixture_path(file_name)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	var json := JSON.new()
	var parsed := json.parse(file.get_as_text())
	file.close()
	return {"ok": parsed == OK and json.data is Dictionary, "data": json.data if parsed == OK else {}}

func _write_fixture(file_name: String, data: Dictionary) -> bool:
	var path := RouteSession.project_fixture_path(file_name)
	if path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true
