extends SceneTree
## C 古い採石場の前哨地 bridge を、通常 user:// を使わずに検証する。
## 本編Enemy/AIを並列に動かさず、既存の敵定義・武器式・HP撤退閾値を
## bridge sessionの唯一の現地台帳へ適用する。

const RouteSession = preload("res://bridge/route_connection_session.gd")
const FIXTURE_SESSION := "outpost_resume_session.json"
const FIXTURE_RESULT := "outpost_resume_result.json"
const STEP := 0.2

var main
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_cmdline_user_args().has("outpost-resume"):
		await _resume_process()
		return
	await _clear_collect_return_and_reenter()
	if fails == 0:
		await _injured_retreat()
	if fails == 0:
		await _down_blocks_commit()
	if fails == 0:
		await _fresh_process_restore_and_retreat()
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
	if main.world.region == "a_start" and not await move_leg("b_forest"):
		return false
	if main.world.region == "b_forest":
		return await move_leg("c_quarry")
	return main.world.region == "c_quarry" and main.world.phase == "stopped"

func move_to_start() -> bool:
	if main.world.region == "c_quarry" and not await move_leg("b_forest"):
		return false
	if main.world.region == "b_forest":
		return await move_leg("a_start")
	return main.world.region == "a_start" and main.world.phase == "stopped"

func make_outpost(tag: String, expected_remaining := 3):
	var created: Dictionary = RouteSession.create_from_game(main, tag, {"outpost_enabled": true})
	check(bool(created.get("ok", false)), tag + ": Cの既存有限資源と既存仲間から前哨地sessionを作成")
	if not bool(created.get("ok", false)):
		return null
	var session = created.session
	check(session.outpost_enemy_total() == 3 and session.outpost_remaining() == expected_remaining, tag + ": 前哨地の既存sand_stalker状態を正しく引継ぎ")
	return session

func advance_until(session, predicate: Callable, seconds: float) -> bool:
	for unused in ceili(seconds / STEP):
		session.tick(STEP)
		var projected: Dictionary = session.apply_projection_to_workers(main)
		if not bool(projected.get("ok", false)):
			return false
		if predicate.call():
			return true
	return predicate.call()

func source_total(session) -> int:
	return session.total_source_remaining()

func stock_for_session(session) -> int:
	var total := 0
	var seen := {}
	for resource_id in session.resources:
		var item := int(session.resources[resource_id].item)
		if not seen.has(item):
			seen[item] = true
			total += main.storage.count_of(item)
	return total

func settle_and_commit(session, label: String) -> bool:
	session.request_recall()
	var ready := await advance_until(session, func(): return session.phase == "ready_to_exit", 100.0)
	check(ready, label + ": 全班帰還で予約・cargo・relay・入口列を解消")
	if not ready:
		return false
	var stock_before := stock_for_session(session)
	var depot := int(session.state_summary().depot)
	var committed: Dictionary = session.commit_to_game(main)
	check(bool(committed.get("ok", false)), label + ": 本編台帳へ一回だけ確定")
	check(stock_for_session(session) == stock_before + depot, label + ": 本編在庫へcargoを一回だけ搬入")
	var repeat: Dictionary = session.commit_to_game(main)
	check(bool(repeat.get("ok", false)) and bool(repeat.get("already_committed", false)), label + ": 二重確定で貨物を複製しない")
	return bool(committed.get("ok", false))

func _clear_collect_return_and_reenter() -> void:
	print("-- 前哨地入場→対処→回収→帰還→再入場")
	await fresh()
	if not await move_to_quarry():
		check(false, "攻略試験: 既存WorldTripでA→B→Cへ横移動")
		return
	check(true, "攻略試験: 既存WorldTripでA→B→Cへ横移動")
	var session = make_outpost("outpost-clear")
	if session == null:
		return
	session.set_gate_closed(true)
	var bypass := await advance_until(session, func(): return str(session.actors["worker:2"].get("route", "")) == "bypass", 20.0)
	check(bypass, "主経路閉鎖で護衛は迂回入口・遮蔽物を経由")
	var engaged := await advance_until(session, func(): return session.outpost_remaining() < session.outpost_enemy_total(), 60.0)
	check(engaged, "既存装備の護衛が前哨地の敵へ自動で対処を開始")
	var cleared := await advance_until(session, func(): return session.outpost_cleared, 120.0)
	check(cleared and session.outpost_remaining() == 0, "前哨地の敵を無力化後に既存C資源の回収を開放")
	var collected := await advance_until(session, func(): return int(session.state_summary().depot) > 0, 100.0)
	check(collected and session.conservation_ok(), "回収役→relay→搬入口の荷物運搬と保存則")
	var source_after := source_total(session)
	if not await settle_and_commit(session, "攻略試験"):
		return
	check(await move_to_start(), "攻略試験: C→B→Aへ既存横移動で帰還")
	check(main.workers.all(func(worker): return worker.carrying < 0), "攻略試験: 帰還後に仲間の手持ちを正常化")
	if not await move_to_quarry():
		check(false, "再入場試験: A→B→Cへ再到達")
		return
	var reentered = make_outpost("outpost-reenter", 0)
	if reentered == null:
		return
	check(reentered.outpost_cleared, "再入場で同一横移動runの撃破済み前哨地を再出現させない")
	check(reentered.total_source_remaining() == source_after and reentered.conservation_ok(), "再入場でC有限資源・cargo・予約を複製しない")
	reentered.request_recall()
	check(await advance_until(reentered, func(): return reentered.phase == "ready_to_exit", 30.0), "再入場直後の撤退でも安全に解消")
	check(bool(reentered.commit_to_game(main).get("ok", false)), "再入場の空cargo確定は在庫を増やさない")
	check(await move_to_start(), "再入場試験後もC→Aへ帰還")

func _injured_retreat() -> void:
	print("-- 既存HP閾値による負傷撤退")
	await fresh()
	if not await move_to_quarry():
		check(false, "負傷撤退: A→Cへ移動")
		return
	var session = make_outpost("outpost-injury")
	if session == null:
		return
	var fighting := await advance_until(session, func(): return str(session.actors["worker:2"].get("state", "")) == "combat", 60.0)
	check(fighting, "負傷撤退: 護衛が既存射程で戦闘位置へ到達")
	if not fighting:
		return
	session.actors["worker:2"]["hp"] = FieldOperations.RETREAT_HP + CrewStatusDB.RAID_HIT_HP * 0.5
	var retreated := await advance_until(session, func(): return str(session.actors["worker:2"].get("state", "")) in ["injured_return", "injured_wait"], 12.0)
	check(retreated, "既存RAID_HIT_HPとHP30閾値で護衛は追撃を中断して撤退")
	if not await settle_and_commit(session, "負傷撤退"):
		return
	check(main.workers[2].hp <= FieldOperations.RETREAT_HP and main.workers[2].ai.low_hp_retreat, "確定後も既存の低HP帰還状態を本編Workerへ反映")
	check(await move_to_start(), "負傷撤退後もC→Aへ帰還")

func _down_blocks_commit() -> void:
	print("-- HP0戦闘不能は安全に確定を拒否")
	await fresh()
	if not await move_to_quarry():
		check(false, "戦闘不能: A→Cへ移動")
		return
	var session = make_outpost("outpost-down")
	if session == null:
		return
	var actor: Dictionary = session.actors["worker:2"]
	actor["hp"] = 0.0
	actor["down"] = false
	session.tick(STEP)
	check(bool(actor.get("down", false)) and str(actor.get("state", "")) == "down", "HP0の仲間をbridge内で戦闘不能として停止")
	var projected: Dictionary = session.apply_projection_to_workers(main)
	check(bool(projected.get("ok", false)) and main.workers[2].down, "戦闘不能表示を停止中の既存Workerへ投影")
	session.request_recall()
	var rejected: Dictionary = session.commit_to_game(main)
	check(not bool(rejected.get("ok", false)) and str(rejected.get("reason", "")).contains("戦闘不能"), "戦闘不能のsessionは横視点への確定を安全に拒否")

func _fresh_process_restore_and_retreat() -> void:
	print("-- 戦闘中保存→新Godotプロセス復元→撤退")
	await fresh()
	if not await move_to_quarry():
		check(false, "別プロセス試験: A→Cへ移動")
		return
	var session = make_outpost("outpost-fresh-process")
	if session == null:
		return
	var combat_started := await advance_until(session, func(): return str(session.actors["worker:2"].get("state", "")) == "combat" and float(session.outpost_enemies["outpost:bypass"].get("hp", 0.0)) < float(session.outpost_enemies["outpost:bypass"].get("max_hp", 0.0)), 80.0)
	check(combat_started, "保存前に敵HP・仲間HP・装備を持つ戦闘中sessionへ到達")
	if not combat_started:
		return
	var saved: Dictionary = session.save_project_fixture(FIXTURE_SESSION)
	check(bool(saved.get("ok", false)), "通常user://を使わず戦闘中sessionをproject-local fixtureへ保存")
	var output: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/test_a_recovery_outpost.gd", "--", "outpost-resume"]
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	for line in output:
		print(line)
	check(code == 0, "新Godotプロセスで戦闘中前哨地sessionを復元し撤退・帰還")
	var read := _read_fixture(FIXTURE_RESULT)
	check(bool(read.get("ok", false)) and bool(read.get("data", {}).get("passed", false)), "別プロセスで敵HP・仲間・貨物・予約の照合結果を取得")

func _resume_process() -> void:
	await fresh()
	var checks: Array = []
	_record(checks, await move_to_quarry(), "fresh processでA→Cを既存WorldTripにより再到達")
	var loaded: Dictionary = RouteSession.load_project_fixture(FIXTURE_SESSION)
	_record(checks, bool(loaded.get("ok", false)), "project-local前哨地fixtureを読込")
	if bool(loaded.get("ok", false)):
		var session = loaded.session
		_record(checks, session.outpost_enabled and session.outpost_remaining() > 0 and not session.outpost_cleared, "戦闘中の既存敵HP状態を復元")
		var projected: Dictionary = session.apply_projection_to_workers(main)
		_record(checks, bool(projected.get("ok", false)), "仲間の名前・既存装備を照合して投影")
		_record(checks, session.conservation_ok(), "読込直後の資源・cargo保存則")
		session.request_recall()
		var ready := await advance_until(session, func(): return session.phase == "ready_to_exit", 100.0)
		_record(checks, ready, "未対処の前哨地から全班を撤退して現地台帳を解消")
		var committed: Dictionary = session.commit_to_game(main)
		_record(checks, bool(committed.get("ok", false)), "fresh processで一回だけ本編へ確定")
		_record(checks, main.workers.all(func(worker): return worker.carrying < 0) and session.conservation_ok(), "撤退後も仲間手持ち・資源・貨物を二重処理しない")
	var passed := checks.all(func(row): return bool(row.passed))
	_write_fixture(FIXTURE_RESULT, {"passed": passed, "checks": checks, "normal_user_save_touched": false})
	print("== 結果: %s ==" % ("すべて成功" if passed else "fresh process失敗"))
	quit(0 if passed else 1)

func _record(rows: Array, ok: bool, text: String) -> void:
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
