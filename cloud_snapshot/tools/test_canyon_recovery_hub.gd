extends SceneTree
## 峡谷の回収拠点は bridge session を変更せず、表示部品と歩行帯だけを提供する。

const HUB_URI := "res://scenes/canyon/canyon_recovery_hub.tscn"
const Adapter = preload("res://bridge/route_connection_adapter.gd")
const RouteSession = preload("res://bridge/route_connection_session.gd")
const RouteHarness = preload("res://bridge/route_connection_harness.gd")

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	_check(ResourceLoader.exists(HUB_URI), "CanyonRecoveryHub の分離 scene が存在する")
	if ResourceLoader.exists(HUB_URI):
		var hub = load(HUB_URI).instantiate()
		root.add_child(hub)
		await process_frame
		for component in ["Terrain", "GroundModules", "Cliffs", "CliffModules", "Occupancy", "Quarry", "Bridge", "BaseRear", "BaseFront", "CheckpointRear", "CheckpointFront", "CanyonCrewViews", "ActivityOverlay", "CargoYard"]:
			_check(hub.get_node_or_null(component) != null, component + " は独立した表示部品")
		var occupancy = hub.get_node_or_null("Occupancy")
		_check(occupancy != null and occupancy.get_node_or_null("TerrainSolids/BackCliffSolid") != null and occupancy.get_node_or_null("TerrainSolids/RavineSolid") != null, "崖と谷は独立した地面占有ポリゴンを持つ")
		_check(occupancy != null and occupancy.get_node_or_null("BridgeConnection/Deck") != null, "短い橋には谷を越える接続ポリゴンを持つ")
		if occupancy != null:
			_check(occupancy.solid_contains(Vector2(520, 100)), "奥の崖面は歩行不可地面占有として判定")
			_check(occupancy.solid_contains(Vector2(520, 565)), "乾いた谷底は歩行不可地面占有として判定")
		_check(occupancy.bridge_contains(hub.map_point(Vector2(865, 385))), "橋中央だけが谷を越える歩行接続として判定")
		var base_rear: CanvasItem = hub.get_node("BaseRear") as CanvasItem
		var base_front: CanvasItem = hub.get_node("BaseFront") as CanvasItem
		var overlay: CanvasItem = hub.get_node("ActivityOverlay") as CanvasItem
		_check(base_rear.z_index < base_front.z_index and base_front.z_index < overlay.z_index, "基地の後景→前景→活動表示の足元基準描画順")
		_check(hub.is_integer_render_layout(), "表示位置・倍率・最近傍フィルタは整数ピクセル契約")
		var bridge_sprite := hub.get_node_or_null("Bridge/DiagonalRavineBridge") as Sprite2D
		_check(bridge_sprite != null and bridge_sprite.texture != null and bridge_sprite.texture.resource_path.ends_with("v2/route_bridge.png") and bridge_sprite.position == Vector2(415, 385), "橋は実 session の迂回線に合う非回転の対角素材と整数接地点を使う")
		var bridge_component = hub.get_node_or_null("Bridge")
		var deck_capture_band_ok: bool = bridge_component != null and bridge_component.has_method("presentation_deck_contains")
		if deck_capture_band_ok:
			deck_capture_band_ok = bool(bridge_component.call("presentation_deck_contains", Vector2(417, 363))) and not bool(bridge_component.call("presentation_deck_contains", Vector2(415, 385))) and not bool(bridge_component.call("presentation_deck_contains", Vector2(531, 491))) and not bool(bridge_component.call("presentation_deck_contains", Vector2(502, 464)))
		_check(deck_capture_band_ok, "橋の実画面証跡は前景構造でなく実際の木床中心帯を選ぶ")
		var calibrated_bridge_projection_ok: bool = hub.has_method("single_demo_bridge_path") and bridge_component != null and bridge_component.has_method("presentation_path_contains")
		if calibrated_bridge_projection_ok:
			var source_start := RecoveryRouteConnectionSession.BYPASS
			var source_end := RecoveryRouteConnectionSession.RESOURCE
			for progress in [0.0, 0.15, 0.35, 0.50, 0.70, 0.88, 1.0]:
				var source := source_start.lerp(source_end, progress)
				var outbound: Vector2 = hub.presentation_point_for_actor({"direct_depot_loop": true, "state": "to_resource", "x": source.x, "y": source.y})
				var loaded_return: Vector2 = hub.presentation_point_for_actor({"direct_depot_loop": true, "state": "to_base", "carry_n": 3, "x": source.x, "y": source.y})
				calibrated_bridge_projection_ok = calibrated_bridge_projection_ok and outbound.distance_to(loaded_return) <= 0.01 and bool(bridge_component.call("presentation_path_contains", outbound))
				if progress >= 0.35 and progress <= 0.70:
					calibrated_bridge_projection_ok = calibrated_bridge_projection_ok and bool(bridge_component.call("presentation_deck_contains", outbound))
			var raw_abutment: Vector2 = hub.map_point(source_start.lerp(source_end, 0.20))
			calibrated_bridge_projection_ok = calibrated_bridge_projection_ok and not bool(bridge_component.call("presentation_path_contains", raw_abutment)) and not bool(bridge_component.call("presentation_path_contains", Vector2(531, 491))) and not bool(bridge_component.call("presentation_path_contains", Vector2(502, 464)))
		_check(calibrated_bridge_projection_ok, "単独追跡の往復橋表示は同一の校正済み地面帯を通り前景岩壁を横切らない")
		var bridge_progress_boundary_ok: bool = hub.has_method("single_demo_bridge_progress_for_source")
		if bridge_progress_boundary_ok:
			var service_mid := RecoveryRouteConnectionSession.BASE.lerp(RecoveryRouteConnectionSession.BYPASS, 0.50)
			var bridge_mid := RecoveryRouteConnectionSession.BYPASS.lerp(RecoveryRouteConnectionSession.RESOURCE, 0.50)
			bridge_progress_boundary_ok = float(hub.call("single_demo_bridge_progress_for_source", service_mid)) < 0.0 and is_equal_approx(float(hub.call("single_demo_bridge_progress_for_source", bridge_mid)), 0.50)
		_check(bridge_progress_boundary_ok, "橋の表示進行率はservice apronを橋入口として誤分類せず実bridge区間だけを示す")
		var ground_modules := hub.get_node_or_null("GroundModules") as Node2D
		var route_segments := [
			[hub.map_point(RecoveryRouteConnectionSession.BASE), hub.map_point(RecoveryRouteConnectionSession.RELAY)],
			[hub.map_point(RecoveryRouteConnectionSession.RELAY), hub.map_point(RecoveryRouteConnectionSession.GATE)],
			[hub.map_point(RecoveryRouteConnectionSession.GATE), hub.map_point(RecoveryRouteConnectionSession.RESOURCE)],
			[hub.map_point(RecoveryRouteConnectionSession.BASE), hub.map_point(RecoveryRouteConnectionSession.BYPASS)],
			[hub.map_point(RecoveryRouteConnectionSession.BYPASS), hub.map_point(RecoveryRouteConnectionSession.RESOURCE)],
		]
		if hub.has_method("single_demo_bridge_path"):
			var demo_bridge_path: Array = hub.call("single_demo_bridge_path")
			for path_index in range(demo_bridge_path.size() - 1):
				route_segments.append([demo_bridge_path[path_index] as Vector2, demo_bridge_path[path_index + 1] as Vector2])
		var terrain := hub.get_node_or_null("Terrain") as Node2D
		var route_surface_features_are_bound := terrain != null and terrain.has_method("route_surface_marks")
		if route_surface_features_are_bound:
			var marks: Array = terrain.call("route_surface_marks", hub)
			route_surface_features_are_bound = not marks.is_empty()
			for mark in marks:
				var position: Vector2 = mark.get("position", Vector2.INF) if mark is Dictionary else Vector2.INF
				route_surface_features_are_bound = route_surface_features_are_bound and is_finite(position.x) and is_finite(position.y) and _distance_to_segments(position, route_segments) <= 43.0
		_check(route_surface_features_are_bound, "主運搬路の砂轍・端部テクスチャは実経路上だけに反復する")
		var bridge := hub.get_node_or_null("Bridge") as Node2D
		var bridge_approach_features_are_bound := bridge != null and bridge.has_method("approach_surface_marks")
		if bridge_approach_features_are_bound:
			var approach_marks: Array = bridge.call("approach_surface_marks", hub)
			bridge_approach_features_are_bound = not approach_marks.is_empty()
			for mark in approach_marks:
				var position: Vector2 = mark.get("position", Vector2.INF) if mark is Dictionary else Vector2.INF
				bridge_approach_features_are_bound = bridge_approach_features_are_bound and is_finite(position.x) and is_finite(position.y) and _distance_to_segments(position, route_segments) <= 43.0
		_check(bridge_approach_features_are_bound, "橋アプローチの砂轍・端部テクスチャは迂回経路に連続する")
		var only_connected_ground_modules := ground_modules != null
		if ground_modules != null:
			for module in ground_modules.get_children():
				if module is Node2D:
					only_connected_ground_modules = only_connected_ground_modules and _distance_to_segments((module as Node2D).position, route_segments) <= 72.0
		_check(only_connected_ground_modules, "道路として読める地面モジュールは実運搬路から孤立しない")
		var yard_sprite := hub.get_node_or_null("CargoYard/CargoRepairAwningAndTools") as Sprite2D
		_check(yard_sprite != null and yard_sprite.texture != null and yard_sprite.position.x + yard_sprite.texture.get_width() * 0.5 <= 1280.0, "整備ヤードは右端で切れず拠点と荷下ろし関係を保つ")
		for prop_name in ["RelayHandcart", "DockCrate", "LooseOre"]:
			var prop_sprite := hub.get_node_or_null("Props/" + prop_name) as Sprite2D
			_check(prop_sprite != null and prop_sprite.texture != null and prop_sprite.texture.resource_path.contains("canyon_recovery/v2/props/"), prop_name + " は不透明な黒背景を使わない v2 透過小物")
		_check(hub.walkable_contains(RecoveryRouteConnectionSession.BASE), "駐車基地は歩行帯")
		_check(hub.walkable_contains(RecoveryRouteConnectionSession.RELAY), "集積所は歩行帯")
		_check(hub.walkable_contains(RecoveryRouteConnectionSession.GATE), "主経路の橋接続は歩行帯")
		_check(hub.walkable_contains(RecoveryRouteConnectionSession.BYPASS), "迂回路の橋接続は歩行帯")
		_check(hub.walkable_contains(Vector2(425, 535)), "基地から迂回入口への実 session 直線も歩行帯")
		for bypass_sample in [Vector2(770, 470), Vector2(865, 385)]:
			_check(hub.walkable_contains(bypass_sample), "迂回橋の全接続帯 %s は歩行帯" % bypass_sample)
		_check(hub.walkable_contains(RecoveryRouteConnectionSession.RESOURCE), "鉱石採取地点は歩行帯")
		_check(not hub.walkable_contains(Vector2(640, 145)), "崖面は歩行帯に含めない")
		_check(hub.activity_label_for({"state": "harvesting"}) == "採取", "採取状態を実 session 名から表示")
		_check(hub.activity_label_for({"state": "to_relay", "carry_n": 2}) == "運搬", "cargo を持つ移動を運搬表示")
		_check(hub.activity_label_for({"state": "safe_wait"}) == "待機", "経路閉鎖時を待機表示")
		_check(hub.activity_label_for({"state": "to_resource"}) == "歩行", "資源へ向かう移動を歩行表示")
		_continuous_capture_contract_regression(hub)
		hub.queue_free()
	if fails == 0:
		await _adapter_integration()
	if fails == 0:
		await _haul_frame_normal_presentation_integration()
	if fails == 0:
		await _live_recovery_loop_integration()
	if fails == 0:
		_harness_mode_guard_regression()
	if fails == 0:
		await _single_worker_loop_integration()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)

func _continuous_capture_contract_regression(hub) -> void:
	## This starts red: a capture cannot claim a smooth movie merely because it
	## chose representative stills.  The contract is shared by the direct
	## runtime recorder and verifies the evidence metadata, not a mock session.
	var contract_script = load("res://tools/canyon_continuous_capture_contract.gd")
	_check(contract_script != null, "連続収録: frame/時刻/足元/bridge/unload を検証する契約が存在する")
	var path_ready: bool = hub != null and hub.has_method("single_demo_service_path")
	_check(path_ready, "連続収録: service apron は速度保存の共有表示pathを持つ")
	if contract_script == null or not path_ready:
		return
	var verifier = contract_script.new()
	var has_preconditions: bool = verifier.has_method("validate_preconditions")
	_check(has_preconditions, "連続収録: headless・出力不能・非検証modeを拒否する開始条件を持つ")
	_check(ResourceLoader.exists("res://tools/capture_canyon_single_worker_continuous.gd"), "連続収録: 実Viewport専用の収録scriptが存在する")
	if has_preconditions:
		_check(not bool(verifier.validate_preconditions("headless", true, true).get("ok", true)), "連続収録: headlessを実画面証跡として拒否する")
		_check(not bool(verifier.validate_preconditions("x11", false, true).get("ok", true)), "連続収録: 出力不能を成功扱いしない")
		_check(not bool(verifier.validate_preconditions("x11", true, false).get("ok", true)), "連続収録: 通常modeを単独追跡動画として拒否する")
	var samples := [
		{"frame_number": 1, "capture_msec": 1000, "video_elapsed_msec": 0, "session_elapsed": 0.00, "state": "to_resource", "carried": 0, "depot": 0, "conservation_ok": true, "presentation_error": 0.0, "scale": [1.0, 1.0], "speed_ratio": 1.0, "bridge_progress": 0.10, "bridge_path": true, "bridge_deck": false},
		{"frame_number": 2, "capture_msec": 1083, "video_elapsed_msec": 83, "session_elapsed": 0.08, "state": "to_resource", "carried": 0, "depot": 0, "conservation_ok": true, "presentation_error": 0.0, "scale": [1.0, 1.0], "speed_ratio": 1.0, "bridge_progress": 0.48, "bridge_path": true, "bridge_deck": true},
		{"frame_number": 3, "capture_msec": 1166, "video_elapsed_msec": 166, "session_elapsed": 0.16, "state": "to_resource", "carried": 0, "depot": 0, "conservation_ok": true, "presentation_error": 0.0, "scale": [1.0, 1.0], "speed_ratio": 1.0, "bridge_progress": 0.86, "bridge_path": true, "bridge_deck": false},
		{"frame_number": 4, "capture_msec": 1249, "video_elapsed_msec": 249, "session_elapsed": 0.24, "state": "harvesting", "carried": 0, "depot": 0, "conservation_ok": true, "presentation_error": 0.0, "scale": [1.0, 1.0], "speed_ratio": -1.0, "bridge_progress": -1.0, "foot_stationary": true},
		{"frame_number": 5, "capture_msec": 1332, "video_elapsed_msec": 332, "session_elapsed": 0.32, "state": "to_base", "carried": 3, "depot": 0, "conservation_ok": true, "presentation_error": 0.0, "scale": [1.0, 1.0], "speed_ratio": 1.0, "bridge_progress": 0.84, "bridge_path": true, "bridge_deck": false},
		{"frame_number": 6, "capture_msec": 1415, "video_elapsed_msec": 415, "session_elapsed": 0.40, "state": "dock_wait", "carried": 3, "depot": 0, "conservation_ok": true, "presentation_error": 0.0, "scale": [1.0, 1.0], "speed_ratio": -1.0, "bridge_progress": -1.0},
		{"frame_number": 7, "capture_msec": 1498, "video_elapsed_msec": 498, "session_elapsed": 0.48, "state": "to_resource", "carried": 0, "depot": 3, "conservation_ok": true, "presentation_error": 0.0, "scale": [1.0, 1.0], "speed_ratio": 1.0, "bridge_progress": -1.0},
	]
	var cycles := [{"cycle": 1, "frame_number": 7, "depot_before": 0, "depot_after": 3, "carried": 0, "conservation_ok": true}]
	var accepted: Dictionary = verifier.validate(samples, cycles, 12.0)
	_check(bool(accepted.get("ok", false)), "連続収録: 等間隔frameが橋→採取→運搬→荷下ろし→再出発を保存則付きで満たす")
	var jittered: Array = samples.duplicate(true)
	var wall_msec := 1000
	for index in range(jittered.size()):
		if index > 0:
			wall_msec += 170 if index == 3 else 75
		jittered[index]["capture_msec"] = wall_msec
	var bounded_jitter: Dictionary = verifier.validate(jittered, cycles, 10.0)
	_check(bool(bounded_jitter.get("ok", false)) and float(bounded_jitter.get("actual_fps", 0.0)) >= 10.0 and float(bounded_jitter.get("max_interval_msec", 0.0)) == 170.0, "連続収録: 平均10Hz以上なら単発170msのpost-draw観測jitterを受理する")
	var excessive_gap: Array = jittered.duplicate(true)
	for index in range(3, excessive_gap.size()):
		excessive_gap[index]["capture_msec"] = int(excessive_gap[index].capture_msec) + 31
	var rejected_gap: Dictionary = verifier.validate(excessive_gap, cycles, 10.0)
	_check(not bool(rejected_gap.get("ok", true)) and float(rejected_gap.get("actual_fps", 0.0)) >= 10.0 and rejected_gap.get("errors", []) == ["capture-gap"], "連続収録: 同じ状態保存traceでも200ms超の観測gapは拒否する")
	var boundary_gap: Array = jittered.duplicate(true)
	for index in range(3, boundary_gap.size()):
		boundary_gap[index]["capture_msec"] = int(boundary_gap[index].capture_msec) + 30
	_check(bool(verifier.validate(boundary_gap, cycles, 10.0).get("ok", false)), "連続収録: 平均10Hz以上なら200ms境界までの観測gapを受理する")
	var skipped: Array = samples.duplicate(true)
	skipped[3]["frame_number"] = 5
	var rejected: Dictionary = verifier.validate(skipped, cycles, 12.0)
	_check(not bool(rejected.get("ok", true)), "連続収録: 欠番frameは動画証跡として拒否する")
	var jumped: Array = samples.duplicate(true)
	jumped[2]["source_delta"] = 1.0
	jumped[2]["foot_delta"] = 80.0
	var jump_rejected: Dictionary = verifier.validate(jumped, cycles, 12.0)
	_check(not bool(jump_rejected.get("ok", true)), "連続収録: sourceに対する足元teleportは動画証跡として拒否する")
	var has_video_window: bool = verifier.has_method("validate_video_window")
	_check(has_video_window, "連続収録: 完了cycleがMP4時間内に映ることを検証する")
	if has_video_window:
		var video_window_ok: Dictionary = verifier.validate_video_window(samples, cycles, 600)
		_check(bool(video_window_ok.get("ok", false)), "連続収録: bridge→採取→運搬→荷下ろし→再出発が動画時間内に収まる")
		var late_samples: Array = samples.duplicate(true)
		late_samples[6]["video_elapsed_msec"] = 650
		var video_window_late: Dictionary = verifier.validate_video_window(late_samples, cycles, 600)
		_check(not bool(video_window_late.get("ok", true)), "連続収録: 動画終了後の荷下ろし・再出発は成功証跡として拒否する")
		var v4_evidence := FileAccess.open("res://prototypes/recovery_map_lab/results/route_connection_runtime/canyon_single_worker_continuous_v4.json", FileAccess.READ)
		var v4_document = JSON.parse_string(v4_evidence.get_as_text()) if v4_evidence != null else null
		if v4_evidence != null:
			v4_evidence.close()
		var v4_video_window: Dictionary = verifier.validate_video_window((v4_document as Dictionary).get("samples", []) if v4_document is Dictionary else [], (v4_document as Dictionary).get("cycle_log", []) if v4_document is Dictionary else [], 13000)
		_check(bool(v4_video_window.get("ok", false)), "連続収録: 採用v4の全仕事loopは13秒MP4の時間内に収まる")
	_three_cycle_capture_contract_regression(verifier, samples)
	_strict_v8_bridge_contract_regression(verifier)
	var has_video_probe: bool = verifier.has_method("validate_video_probe")
	_check(has_video_probe, "連続収録: movieをffprobeの実duration/frame数で完全性検証する")
	if has_video_probe:
		var valid_probe := {
			"streams": [{"codec_type": "video", "codec_name": "h264", "width": 1280, "height": 720, "avg_frame_rate": "10/1", "nb_read_frames": "130"}],
			"format": {"duration": "13.000000", "size": "1179253"},
		}
		var accepted_probe: Dictionary = verifier.validate_video_probe(valid_probe, 10.0, 13000)
		_check(bool(accepted_probe.get("ok", false)), "連続収録: 完全な1280x720/10fps/13秒movieだけを受理する")
		var truncated_probe: Dictionary = valid_probe.duplicate(true)
		truncated_probe["streams"][0]["nb_read_frames"] = "129"
		truncated_probe["format"]["duration"] = "12.900000"
		var rejected_probe: Dictionary = verifier.validate_video_probe(truncated_probe, 10.0, 13000)
		_check(not bool(rejected_probe.get("ok", true)), "連続収録: 短縮または欠frameのmovieを成功証跡として拒否する")
		var probe_output: Array = []
		var probe_args := ["-v", "error", "-count_frames", "-show_entries", "stream=codec_type,codec_name,width,height,avg_frame_rate,nb_read_frames:format=duration,size", "-of", "json", ProjectSettings.globalize_path("res://prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v4/canyon_single_worker_continuous_v4.mp4")]
		var probe_exit := OS.execute("ffprobe", probe_args, probe_output, true)
		var probe_text := ""
		for line in probe_output:
			probe_text += str(line)
		var actual_probe_document = JSON.parse_string(probe_text)
		var actual_probe: Dictionary = verifier.validate_video_probe(actual_probe_document as Dictionary, 10.0, 13000) if actual_probe_document is Dictionary else {"ok": false}
		_check(probe_exit == 0 and bool(actual_probe.get("ok", false)), "連続収録: 採用v4 MP4を実ffprobeで10fps/130frame/13秒として復号する")
	var path: Array = hub.call("single_demo_service_path")
	var path_length := 0.0
	for index in range(path.size() - 1):
		path_length += (path[index + 1] as Vector2).distance_to(path[index] as Vector2)
	_check(absf(path_length - RecoveryRouteConnectionSession.BASE.distance_to(RecoveryRouteConnectionSession.BYPASS)) <= 1.0, "連続収録: service apron の画面長はsession BASE→BYPASS長と一致して速度急変を避ける")

func _strict_v8_bridge_contract_regression(verifier) -> void:
	var supports_strict_validate := false
	var supports_strict_window := false
	for method in verifier.get_method_list():
		if str(method.get("name", "")) == "validate":
			supports_strict_validate = (method.get("args", []) as Array).size() >= 4
		if str(method.get("name", "")) == "validate_video_window":
			supports_strict_window = (method.get("args", []) as Array).size() >= 6
	_check(supports_strict_validate and supports_strict_window, "v8橋証跡: strict visual bridge modeを明示的に選べる")
	if not supports_strict_validate or not supports_strict_window:
		return
	var samples: Array = [
		_v8_bridge_sample(1, 1000, 100, 0.00, "to_resource", 0, 0, 0.10, "approach_near", false),
		_v8_bridge_sample(2, 1100, 200, 0.10, "to_resource", 0, 0, 0.50, "deck", true),
		_v8_bridge_sample(3, 1200, 300, 0.20, "to_resource", 0, 0, 0.90, "approach_far", false),
		_v8_bridge_sample(4, 1300, 400, 0.30, "harvesting", 0, 0, -1.0, "outside", false, true),
		_v8_bridge_sample(5, 1400, 500, 0.40, "to_base", 3, 0, 0.90, "approach_far", false),
		_v8_bridge_sample(6, 1500, 600, 0.50, "to_base", 3, 0, 0.50, "deck", true),
		_v8_bridge_sample(7, 1600, 700, 0.60, "to_base", 3, 0, 0.10, "approach_near", false),
		_v8_bridge_sample(8, 1700, 800, 0.70, "dock_wait", 3, 0, -1.0, "outside", false),
		_v8_bridge_sample(9, 1800, 900, 0.80, "to_resource", 0, 3, -1.0, "outside", false),
		_v8_bridge_sample(10, 1900, 1000, 0.90, "to_resource", 0, 3, -1.0, "outside", false),
	]
	for sample in samples:
		sample["status_text"] = "鉱 51  中継 0  拠点 %d  前哨 OFF" % int(sample.depot)
		sample["detail_text"] = "単独追跡 worker: 歩行 / 手%d / 拠点%d" % [int(sample.carried), int(sample.depot)]
		sample["source_remaining"] = 51
	var cycles: Array = [{"cycle": 1, "frame_number": 9, "depot_before": 0, "depot_after": 3, "carried": 0, "conservation_ok": true, "status_text": samples[8].status_text, "detail_text": samples[8].detail_text}]
	var strict_accepted: Dictionary = verifier.call("validate", samples, cycles, 10.0, true)
	var strict_video_accepted: Dictionary = verifier.call("validate_video_window", samples, cycles, 1200, 1, 0, true)
	_check(bool(strict_accepted.get("ok", false)) and bool(strict_video_accepted.get("ok", false)), "v8橋証跡: 往復の入口→床板→出口を含む一周だけをstrict受理する")
	for broken_index in [1, 5]:
		var missing_deck: Array = samples.duplicate(true)
		missing_deck[broken_index]["bridge_deck"] = false
		var rejected_trace: Dictionary = verifier.call("validate", missing_deck, cycles, 10.0, true)
		var rejected_window: Dictionary = verifier.call("validate_video_window", missing_deck, cycles, 1200, 1, 0, true)
		_check(not bool(rejected_trace.get("ok", true)) and not bool(rejected_window.get("ok", true)), "v8橋証跡: source進行率が正常でも往復%dの床板witness欠落を拒否する" % broken_index)
	var outside_return: Array = samples.duplicate(true)
	outside_return[6]["bridge_region"] = "outside"
	outside_return[6]["bridge_path"] = false
	var rejected_outside: Dictionary = verifier.call("validate", outside_return, cycles, 10.0, true)
	var rejected_outside_window: Dictionary = verifier.call("validate_video_window", outside_return, cycles, 1200, 1, 0, true)
	_check(not bool(rejected_outside.get("ok", true)) and not bool(rejected_outside_window.get("ok", true)), "v8橋証跡: loaded returnの近側接地面外れを拒否する")

func _v8_bridge_sample(frame_number: int, capture_msec: int, video_elapsed_msec: int, session_elapsed: float, state: String, carried: int, depot: int, bridge_progress: float, bridge_region: String, bridge_deck: bool, foot_stationary := false) -> Dictionary:
	return {
		"frame_number": frame_number,
		"capture_msec": capture_msec,
		"video_elapsed_msec": video_elapsed_msec,
		"session_elapsed": session_elapsed,
		"state": state,
		"carried": carried,
		"depot": depot,
		"conservation_ok": true,
		"presentation_error": 0.0,
		"scale": [1.0, 1.0],
		"speed_ratio": 1.0 if bridge_progress >= 0.0 else -1.0,
		"bridge_progress": bridge_progress,
		"bridge_region": bridge_region,
		"bridge_path": bridge_region != "outside",
		"bridge_deck": bridge_deck,
		"foot_stationary": foot_stationary,
	}

func _three_cycle_capture_contract_regression(verifier, single_cycle: Array) -> void:
	var recorder_source := FileAccess.get_file_as_string("res://tools/capture_canyon_single_worker_continuous.gd")
	_check(recorder_source.contains("canyon_single_worker_continuous_v10") and recorder_source.contains("const TARGET_CYCLES := 3") and recorder_source.contains("const VIDEO_DURATION_MSEC := 36000") and recorder_source.contains("const PRE_ROLL_MSEC := 180") and recorder_source.contains("field.process_mode = Node.PROCESS_MODE_DISABLED") and recorder_source.contains("field.process_mode = Node.PROCESS_MODE_INHERIT") and recorder_source.contains("contract.validate(samples, cycle_log, TARGET_HZ, true)") and recorder_source.contains("TARGET_CYCLES, VIDEO_SAFE_MARGIN_MSEC, true)"), "三周収録: v10は短い非tick pre-rollとstrict往復橋契約を使う")
	var mouse_option := recorder_source.find('"-draw_mouse", "0"')
	_check(mouse_option >= 0 and mouse_option < recorder_source.find('"-i", display'), "三周収録: X11入力はcursor収録を無効化する")
	# These hand-ordered cycles catch reusing the first cycle's bridge/harvest
	# evidence, accepting deposits beyond movie end, and stale HUD snapshots.
	var samples: Array = []
	var cycles: Array = []
	for cycle_index in range(3):
		for phase_index in range(8):
			var sample: Dictionary = single_cycle[mini(phase_index, 6)].duplicate(true)
			var frame := cycle_index * 8 + phase_index + 1
			sample["frame_number"] = frame
			sample["video_elapsed_msec"] = (frame - 1) * 100
			sample["depot"] = cycle_index * 3 + (3 if phase_index >= 6 else 0)
			if phase_index == 6:
				sample["state"] = "idle"
			sample["status_text"] = "鉱 51  中継 0  拠点 %d  前哨 OFF" % int(sample.depot)
			sample["detail_text"] = "単独追跡 worker: 歩行 / 手%d / 拠点%d" % [int(sample.carried), int(sample.depot)]
			sample["source_remaining"] = 51
			samples.append(sample)
		cycles.append({"cycle": cycle_index + 1, "frame_number": cycle_index * 8 + 7, "depot_before": cycle_index * 3, "depot_after": (cycle_index + 1) * 3, "carried": 0, "conservation_ok": true, "status_text": samples[-2].status_text, "detail_text": samples[-2].detail_text})
	var supports_cycle_count := false
	var supports_safe_margin := false
	for method in verifier.get_method_list():
		if str(method.get("name", "")) == "validate_video_window":
			supports_cycle_count = (method.get("args", []) as Array).size() >= 4
			supports_safe_margin = (method.get("args", []) as Array).size() >= 5
	_check(supports_cycle_count, "三周収録: video window は要求cycle数を受け取る")
	if supports_cycle_count:
		var accepted: Dictionary = verifier.validate_video_window(samples, cycles, 2400, 3)
		_check(bool(accepted.get("ok", false)), "三周収録: 三つの完全な仕事と再出発が動画内なら受理する")
		_check(not bool(verifier.validate_video_window(samples.slice(0, 16), cycles.slice(0, 2), 2400, 3).get("ok", true)), "三周収録: 二周だけのtraceを拒否する")
		_check(not bool(verifier.validate_video_window(samples, cycles, 2150, 3).get("ok", true)), "三周収録: 三回目のdepositが動画外なら拒否する")
		_check(not bool(verifier.validate_video_window(samples, cycles, 2250, 3).get("ok", true)), "三周収録: 三回目後の再出発が動画外なら拒否する")
		for broken_index in [9, 11, 12, 13]:
			var broken: Array = samples.duplicate(true)
			broken[broken_index]["state"] = "idle"
			_check(not bool(verifier.validate_video_window(broken, cycles, 2400, 3).get("ok", true)), "三周収録: 各周自身の順序付きbridge/採取/運搬/dockが必要 %d" % broken_index)
		var missing_hud: Array = samples.duplicate(true)
		missing_hud[22].erase("detail_text")
		_check(not bool(verifier.validate_video_window(missing_hud, cycles, 2400, 3).get("ok", true)), "三周収録: deposit時のHUD snapshot欠落を拒否する")
		var stale_hud: Array = samples.duplicate(true)
		stale_hud[22]["status_text"] = "鉱 51  中継 0  拠点 6  前哨 OFF"
		_check(not bool(verifier.validate_video_window(stale_hud, cycles, 2400, 3).get("ok", true)), "三周収録: depositと一致しないHUD値を拒否する")
	_check(supports_safe_margin, "三周収録: encoder起動と終端に安全余白を指定できる")
	if supports_safe_margin:
		var buffered: Array = samples.duplicate(true)
		for sample in buffered:
			sample["video_elapsed_msec"] = int(sample.video_elapsed_msec) + 1500
		_check(bool(verifier.validate_video_window(buffered, cycles, 5000, 3, 1000).get("ok", false)), "三周収録: 両端1秒の余白内に完全三周があれば受理する")
		_check(bool(verifier.validate_video_window(buffered, cycles, 4500, 3).get("ok", false)), "三周収録: 余白なしの既定APIは従来のnominal時間を維持する")
		_check(not bool(verifier.validate_video_window(buffered, cycles, 4500, 3, 1000).get("ok", true)), "三周収録: nominal動画内でも終端1秒のdepositを拒否する")
		_check(not bool(verifier.validate_video_window(buffered, cycles, 4750, 3, 1000).get("ok", true)), "三周収録: nominal動画内でも終端1秒のpost-third restartを拒否する")
		buffered[0]["video_elapsed_msec"] = 900
		_check(not bool(verifier.validate_video_window(buffered, cycles, 5000, 3, 1000).get("ok", true)), "三周収録: 起動後1秒未満の必須bridge入口を拒否する")
	_check(recorder_source.contains("const VIDEO_SAFE_MARGIN_MSEC := 1000") and recorder_source.contains("TARGET_CYCLES, VIDEO_SAFE_MARGIN_MSEC, true)"), "三周収録: v10 recorderは両端1秒の安全余白とstrict橋契約を渡す")
	var has_digests: bool = verifier.has_method("validate_frame_digest_sequence")
	_check(has_digests, "三周収録: decoded frame digestの完全性・連続停止を検証する")
	if has_digests:
		_check(bool(verifier.validate_frame_digest_sequence(["a", "a", "b", "c"], 4).get("ok", false)), "三周収録: 最大二frameまでの同一digestは受理する")
		_check(not bool(verifier.validate_frame_digest_sequence(["a", "b", "c"], 4).get("ok", true)), "三周収録: decoded digest欠落を拒否する")
		_check(not bool(verifier.validate_frame_digest_sequence(["a", "", "b", "c"], 4).get("ok", true)), "三周収録: 空digestを拒否する")
		_check(not bool(verifier.validate_frame_digest_sequence(["a", "a", "a", "b"], 4).get("ok", true)), "三周収録: 三連続の同一decoded frameを拒否する")
	_frame_digest_decode_boundary_regression(verifier)

func _frame_digest_decode_boundary_regression(verifier) -> void:
	var output: Array = []
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-i",
		ProjectSettings.globalize_path("res://prototypes/recovery_map_lab/evidence/canyon_single_worker_continuous_v4/canyon_single_worker_continuous_v4.mp4"),
		"-map", "0:v:0", "-an", "-f", "framemd5", "-",
	])
	var exit_code := OS.execute("ffmpeg", args, output, true)
	_check(exit_code == 0, "三周収録: 採用v4 MP4を実ffmpeg framemd5へ直接復号できる")
	var has_parser: bool = verifier.has_method("parse_frame_digest_rows")
	_check(has_parser, "三周収録: recorderと共有するframemd5 row parserがある")
	if not has_parser:
		return
	var raw := ""
	for chunk in output:
		raw += str(chunk)
	var actual_digests: Array = verifier.parse_frame_digest_rows(raw)
	_check(actual_digests.size() == 130, "三周収録: 実v4 framemd5出力から130個のhashを抽出する")
	_check(bool(verifier.validate_frame_digest_sequence(actual_digests, 130).get("ok", false)), "三周収録: 実v4 decoded hash列は欠落・三連続停止なく受理する")
	var representative := "#format: frame checksums\n#stream#, dts, pts, duration, size, hash\n0, 0, 0, 1, 1382400, 00000000000000000000000000000000\n0, -1, -1, 1, 1382400, FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF\r\nframe=130 fps=0.0 Lsize=N/A\n0, 2, 2, 1, 1382400, short\n0, 3, 3, oops, 1382400, 00000000000000000000000000000000\n0, 4, 4, 1, 1382400, 00000000000000000000000000000000 trailing\n"
	var parsed: Array = verifier.parse_frame_digest_rows(representative)
	_check(parsed == ["00000000000000000000000000000000", "ffffffffffffffffffffffffffffffff"], "三周収録: header/trailer/不正rowを除外して実rowだけを抽出する")

func _adapter_integration() -> void:
	SaveGame.disabled = true
	var main = load("res://scenes/main.tscn").instantiate()
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
	for destination in ["b_forest", "c_quarry"]:
		_check(main.world.request(destination), "統合準備: 既存WorldTripで " + destination + " へ出発")
		for unused in 240:
			main._process(0.2)
			await process_frame
			if main.world.phase == "stopped" and main.world.region == destination:
				break
		_check(main.world.phase == "stopped" and main.world.region == destination, "統合準備: " + destination + " へ停止")
	var created: Dictionary = RouteSession.create_from_game(main, "canyon-contract", {"outpost_enabled": true})
	_check(bool(created.get("ok", false)), "統合準備: 既存有限資源と仲間からsessionを作成")
	if not bool(created.get("ok", false)):
		main.queue_free()
		return
	var normal_mode_contract := not bool(created.session.call("is_single_worker_demo")) and str(created.session.call("tracked_worker_id")).is_empty()
	for actor_id in created.session.actors:
		var normal_actor: Dictionary = created.session.actors[actor_id]
		normal_mode_contract = normal_mode_contract and str(normal_actor.get("role", "")) in ["harvest", "carry", "escort"] and not bool(normal_actor.get("direct_depot_loop", false)) and not bool(normal_actor.get("presentation_hidden", false))
	_check(normal_mode_contract, "通常分業: 既定sessionは単独直搬送・隠し表示を持たない")
	var tampered_normal_fixture: Dictionary = created.session.to_dict()
	tampered_normal_fixture.actors["worker:0"]["direct_depot_loop"] = true
	var tampered_normal_loaded: Dictionary = RouteSession.from_dict(tampered_normal_fixture)
	_check(not bool(tampered_normal_loaded.get("ok", false)), "通常分業: fixtureが直搬送actorを混入させたら復元を拒否")
	var source_before := int(created.session.state_summary().source_remaining)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var worker_originals := {}
	for worker in main.workers:
		worker_originals[worker.get_instance_id()] = {"parent": worker.get_parent(), "position": worker.position, "process": worker.process_mode, "visible": worker.visible}
	var adapter = Adapter.new()
	adapter.configure(main, created.session)
	layer.add_child(adapter)
	await process_frame
	_check(adapter.get_node_or_null("CanyonRecoveryHub") != null, "adapter はCanyonRecoveryHubを表示専用子として接続")
	var crew_views = adapter.canyon_hub.get_node_or_null("CanyonCrewViews")
	_check(crew_views != null and crew_views.has_method("view_count") and crew_views.view_count() == main.workers.size(), "v2 人間CrewViewはsession班員数と一対一で表示専用同期")
	_check(crew_views != null and crew_views.sprite_key_for({"state": "harvesting", "carry_n": 0}) == "harvest" and crew_views.sprite_key_for({"state": "to_relay", "carry_n": 1}) == "carry" and crew_views.sprite_key_for({"state": "to_resource", "carry_n": 0}) == "walk", "v2 人間CrewViewは待機・歩行・採取・運搬を独立素材に対応")
	_check(adapter.actor_layer != null and adapter.actor_layer.scale == Vector2.ONE, "文字とスプライトを反転せず通常倍率のWorker投影層を使う")
	var actor_zero: Dictionary = adapter.session.actors["worker:0"]
	var projected_zero: Worker = main.workers[0]
	var expected_zero: Vector2 = adapter.canyon_hub.map_point(Vector2(float(actor_zero.x), float(actor_zero.y)))
	_check(projected_zero.position == expected_zero, "Worker座標だけを鏡像化して右手前の拠点へ対応")
	_check(adapter.actor_layer.get_child_count() == main.workers.size() and adapter.actor_layer.get_children().all(func(worker): return worker.process_mode == Node.PROCESS_MODE_DISABLED and not worker.visible), "仲間は既存AIを二重実行せず旧横向き絵を隠して表示専用投影")
	var overlay = adapter.canyon_hub.get_node_or_null("ActivityOverlay")
	_check(overlay != null and overlay.has_method("visible_badge_count") and overlay.visible_badge_count() <= 1, "活動テキストは必要な一人だけに縮約して重ならない")
	var controls = adapter.get_node_or_null("RouteControls") as Control
	_check(controls != null and controls.size.x <= 270.0 and controls.size.y <= 112.0, "HUDは内容に対する巨大な空白パネルを残さない")
	var rear: CanvasItem = adapter.canyon_hub.get_node("BaseRear") as CanvasItem
	var front: CanvasItem = adapter.canyon_hub.get_node("BaseFront") as CanvasItem
	_check(rear.z_index < adapter.actor_layer.z_index and adapter.actor_layer.z_index < front.z_index, "建物・車体の前後を越える人物投影順")
	adapter.gate_button.emit_signal("pressed")
	_check(adapter.session.gate_closed, "画面の迂回ボタンで既存主経路閉鎖を切替")
	adapter._update_controls()
	_check(adapter.detail_label.text.contains("主路閉鎖") and adapter.detail_label.text.contains("迂回") and adapter.gate_button.text == "主路: 閉鎖→迂回", "通常HUDは主路閉鎖と実際の迂回を曖昧なON/OFFでなく表示")
	adapter.block_button.emit_signal("pressed")
	_check(adapter.session.all_routes_closed, "画面の全路ボタンで安全待機を切替")
	adapter._update_controls()
	_check(adapter.detail_label.text.contains("全路閉鎖") and adapter.detail_label.text.contains("安全待機") and adapter.block_button.text == "全路: 閉鎖→安全待機", "通常HUDは全路閉鎖の安全待機を最優先の判断として表示")
	adapter.dock_button.emit_signal("pressed")
	_check(adapter.session.dock_count == 2, "画面の搬入口ボタンで既存dock数を切替")
	var retreat_button := _button_with_text(adapter, "撤退")
	var save_button := _button_with_text(adapter, "検証保存")
	var load_button := _button_with_text(adapter, "検証読込")
	_check(retreat_button != null and save_button != null and load_button != null, "HUD は撤退・検証保存・検証読込の各ボタンを持つ")
	if save_button != null and load_button != null and retreat_button != null:
		save_button.emit_signal("pressed")
		await process_frame
		_check(adapter.notice_label.visible and adapter.notice_label.text.begins_with("検証保存:"), "画面の検証保存ボタンは project fixture 保存を実行")
		load_button.emit_signal("pressed")
		await process_frame
		_check(adapter.notice_label.visible and adapter.notice_label.text.begins_with("検証セッションを復元"), "画面の検証読込ボタンは保存済みfixtureを復元")
		retreat_button.emit_signal("pressed")
		_check(adapter.session.phase == "recall", "画面の撤退ボタンは既存sessionへ帰還要求を送る")
	_check(int(adapter.session.state_summary().source_remaining) == source_before, "hub接続だけでは有限資源・収納正本を変更しない")
	adapter.queue_free()
	await process_frame
	for worker in main.workers:
		var original: Dictionary = worker_originals[worker.get_instance_id()]
		_check(worker.get_parent() == original.parent and worker.position == original.position and worker.process_mode == int(original.process) and worker.visible == bool(original.visible), "峡谷終了後に Worker 親子・位置・process・表示を横視点の元状態へ復元")
	main.queue_free()

func _haul_frame_normal_presentation_integration() -> void:
	## A separate normal-role instance proves that the frame display reads the
	## immutable session entry snapshot.  The completed item is a visual-test
	## fixture, then it moves through Main.equip_work_support like real play.
	SaveGame.disabled = true
	var main = load("res://scenes/main.tscn").instantiate()
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
	main.storage.store_owned(GameData.Item.HAUL_FRAME, 1, Inventory.SOURCE_TRANSFER)
	_check(main.equip_work_support(main.workers[0], GameData.Item.HAUL_FRAME), "背負いフレームは既存装備APIで採掘役へ装備できる")
	for destination in ["b_forest", "c_quarry"]:
		_check(main.world.request(destination), "背負いフレーム表示準備: " + destination + "へ出発")
		for unused in 240:
			main._process(0.2)
			await process_frame
			if main.world.phase == "stopped" and main.world.region == destination:
				break
		_check(main.world.phase == "stopped" and main.world.region == destination, "背負いフレーム表示準備: " + destination + "へ停止")
	var created: Dictionary = RouteSession.create_from_game(main, "haul-frame-presentation", {"outpost_enabled": false})
	_check(bool(created.get("ok", false)), "背負いフレーム表示: 通常分業sessionを作成")
	if not bool(created.get("ok", false)):
		main.queue_free()
		return
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var adapter = Adapter.new()
	adapter.configure(main, created.session)
	layer.add_child(adapter)
	await process_frame
	var actor_before: Dictionary = Dictionary(adapter.session.actors["worker:0"]).duplicate(true)
	var crew_views = adapter.canyon_hub.get_node_or_null("CanyonCrewViews")
	var frame_actor: Dictionary = adapter.session.actors.get("worker:0", {})
	_check(not bool(adapter.session.call("is_single_worker_demo")) and str(frame_actor.get("role", "")) == "harvest" and int(frame_actor.get("work_support", -1)) == GameData.Item.HAUL_FRAME and int(frame_actor.get("carry_limit", 0)) == GameData.HAUL_FRAME_LIMIT, "背負いフレーム表示: 通常採掘役のsession snapshotだけが便5を保持")
	var support_snapshot: Dictionary = crew_views.debug_snapshot("worker:0") if crew_views != null and crew_views.has_method("debug_snapshot") else {}
	var support_count := int(crew_views.call("support_view_count")) if crew_views != null and crew_views.has_method("support_view_count") else -1
	_check(support_count == 1 and int(support_snapshot.get("support_item", -1)) == GameData.Item.HAUL_FRAME and bool(support_snapshot.get("support_visible", false)), "背負いフレーム表示: 通常v2作業員の背面に独立support spriteを一つだけ置く")
	_check(str(support_snapshot.get("support_texture_path", "")).ends_with("item_haul_frame.png") and Vector2(support_snapshot.get("support_scale", Vector2.ZERO)) == Vector2.ONE and int(support_snapshot.get("support_z_index", 0)) < 0, "背負いフレーム表示: 既存透過assetをNearest・等倍・人物後ろで使う")
	var support_position: Vector2 = support_snapshot.get("support_position", Vector2(0.5, 0.5))
	_check(support_position == support_position.round() and adapter.canyon_hub.is_integer_render_layout(), "背負いフレーム表示: 接地点と整数ピクセル契約を崩さない")
	_check(adapter.detail_label.text.contains("採掘役") and adapter.detail_label.text.contains("背負いフレーム") and adapter.detail_label.text.contains("便5"), "通常HUDは実session由来の役割・装備・便容量を短く表示")
	adapter.canyon_hub.refresh(0.0)
	_check(adapter.session.actors["worker:0"] == actor_before and adapter.session.conservation_ok(), "背負いフレーム表示refreshはsessionの装備・貨物・保存則を書き換えない")
	adapter.queue_free()
	layer.queue_free()
	main.queue_free()

func _live_recovery_loop_integration() -> void:
	## Exercise the same adapter update path that a player sees rather than only
	## calling the label helper with synthetic dictionaries.  The session stays
	## sole authority; the test merely observes its projected state.
	SaveGame.disabled = true
	var main = load("res://scenes/main.tscn").instantiate()
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
	for destination in ["b_forest", "c_quarry"]:
		_check(main.world.request(destination), "実ループ準備: 既存WorldTripで " + destination + " へ出発")
		for unused in 240:
			main._process(0.2)
			await process_frame
			if main.world.phase == "stopped" and main.world.region == destination:
				break
		_check(main.world.phase == "stopped" and main.world.region == destination, "実ループ準備: " + destination + " へ停止")
	var created: Dictionary = RouteSession.create_from_game(main, "canyon-live-loop", {"outpost_enabled": false})
	_check(bool(created.get("ok", false)), "実ループ準備: 敵なしC資源から既存sessionを作成")
	if not bool(created.get("ok", false)):
		main.queue_free()
		return
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var adapter = Adapter.new()
	adapter.configure(main, created.session)
	layer.add_child(adapter)
	await process_frame
	# This integration witness advances the production callback explicitly with
	# deterministic deltas below. Prevent the scene tree from adding an
	# uncontrolled real-frame tick between samples, which otherwise makes the
	# speed/bridge continuity assertion observe two advances per iteration.
	adapter.process_mode = Node.PROCESS_MODE_DISABLED
	adapter.session.set_gate_closed(true)
	var bypass_seen := await _advance_adapter_until(adapter, func():
		for actor_id in adapter.session.actors:
			if str(adapter.session.actors[actor_id].get("route", "")) == "bypass":
				return true
		return false, 180)
	_check(bypass_seen, "実ループ: 主経路閉鎖時に表示中の班が短い橋の迂回路を選ぶ")
	var bridge_steps := await _collect_bridge_walk_samples(adapter, 300)
	_check(_bridge_walk_is_continuous(adapter, bridge_steps), "実ループ: 同じ仲間が橋デッキ上を連続歩行し、全点が実際の歩行帯")
	var harvest_seen := await _advance_adapter_until(adapter, func():
		for actor_id in adapter.session.actors:
			var actor: Dictionary = adapter.session.actors[actor_id]
			if str(actor.get("state", "")) == "harvesting" and adapter.canyon_hub.activity_label_for(actor) == "採取":
				return true
		return false, 360)
	_check(harvest_seen, "実ループ: live session の採取状態が画面の採取表示へ対応")
	var carrying_seen := await _advance_adapter_until(adapter, func():
		for actor_id in adapter.session.actors:
			var actor: Dictionary = adapter.session.actors[actor_id]
			if int(actor.get("carry_n", 0)) > 0 and adapter.canyon_hub.activity_label_for(actor) == "運搬":
				var worker_index := int(actor.get("worker_index", -1))
				if worker_index >= 0 and worker_index < main.workers.size():
					var expected: Vector2 = adapter.canyon_hub.map_point(Vector2(float(actor.x), float(actor.y)))
					return main.workers[worker_index].position == expected
		return false, 600)
	_check(carrying_seen, "実ループ: 運搬中の既存Workerは反転なしの正しい足元座標へ投影")
	var deposited := await _advance_adapter_until(adapter, func(): return int(adapter.session.state_summary().get("depot", 0)) > 0, 900)
	_check(deposited and adapter.session.conservation_ok(), "実ループ: 採取→relay→搬入口→拠点収納を保存則付きで反復")
	adapter.session.request_recall()
	var ready := await _advance_adapter_until(adapter, func(): return adapter.session.phase == "ready_to_exit", 600)
	_check(ready, "実ループ: 帰還指示で手持ち・relay・搬入口を安全に解消")
	if ready:
		var committed: Dictionary = adapter.session.commit_to_game(main)
		_check(bool(committed.get("ok", false)), "実ループ: 拠点収納を本編台帳へ一回だけ確定")
		var repeated: Dictionary = adapter.session.commit_to_game(main)
		_check(bool(repeated.get("ok", false)) and bool(repeated.get("already_committed", false)), "実ループ: 二重確定では収納を重複しない")
	adapter.queue_free()
	await process_frame
	main.queue_free()

func _advance_adapter_until(adapter, predicate: Callable, limit: int) -> bool:
	for unused in limit:
		adapter._process(0.2)
		await process_frame
		if predicate.call():
			return true
	return predicate.call()

func _collect_bridge_walk_samples(adapter, limit: int) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var tracked_actor_id: String = ""
	var occupancy: CanyonRecoveryOccupancy = adapter.canyon_hub.get_node_or_null("Occupancy") as CanyonRecoveryOccupancy
	for unused in limit:
		adapter._process(0.1)
		await process_frame
		for raw_actor_id in adapter.session.actors:
			var actor_id := str(raw_actor_id)
			var actor: Dictionary = adapter.session.actors[raw_actor_id]
			if str(actor.get("route", "")) != "bypass":
				continue
			var source: Vector2 = Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0)))
			var screen: Vector2 = adapter.canyon_hub.map_point(source)
			if occupancy == null or not occupancy.bridge_contains(screen):
				continue
			if tracked_actor_id.is_empty():
				tracked_actor_id = actor_id
			if actor_id != tracked_actor_id:
				continue
			var previous_sample: Dictionary = samples.back() if not samples.is_empty() else {}
			var previous_source: Vector2 = previous_sample.get("source", Vector2.INF)
			if samples.is_empty() or previous_source.distance_to(source) > 0.01:
				samples.append({"actor_id": actor_id, "source": source, "screen": screen, "state": str(actor.get("state", ""))})
			if samples.size() >= 4 and screen.x <= 360.0 and screen.y <= 330.0:
				return samples
	return samples

func _bridge_walk_is_continuous(adapter, samples: Array[Dictionary]) -> bool:
	if samples.size() < 3:
		return false
	var occupancy: CanyonRecoveryOccupancy = adapter.canyon_hub.get_node_or_null("Occupancy") as CanyonRecoveryOccupancy
	var actor_id := str(samples[0].get("actor_id", ""))
	var previous_source: Vector2 = samples[0].get("source", Vector2.ZERO)
	var saw_upper_exit := false
	for sample: Dictionary in samples:
		if str(sample.get("actor_id", "")) != actor_id:
			return false
		var source: Vector2 = sample.get("source", Vector2.ZERO)
		var screen: Vector2 = sample.get("screen", Vector2.ZERO)
		if not adapter.canyon_hub.walkable_contains(source) or occupancy == null or not occupancy.bridge_contains(screen):
			return false
		if source != previous_source and source.distance_to(previous_source) > RecoveryRouteConnectionSession.MOVE_SPEED * 0.15:
			return false
		if screen.x <= 360.0 and screen.y <= 330.0:
			saw_upper_exit = true
		previous_source = source
	return saw_upper_exit

func _distance_to_segments(point: Vector2, segments: Array) -> float:
	var nearest := INF
	for segment in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var delta := b - a
		var length_squared := delta.length_squared()
		var t := 0.0 if length_squared <= 0.001 else clampf((point - a).dot(delta) / length_squared, 0.0, 1.0)
		nearest = minf(nearest, point.distance_to(a + delta * t))
	return nearest

func _button_with_text(root_node: Node, title: String) -> Button:
	for node in root_node.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == title:
			return button
	return null

func _harness_mode_guard_regression() -> void:
	## A click while a trip is already underway must not silently change the
	## mode the pending field entry will use.
	var harness = RouteHarness.new()
	harness.stage = "to_site"
	harness.single_worker_requested = false
	harness.call("_start_single_worker_to_site")
	_check(not harness.single_worker_requested, "検証入口: 移動中の単独追跡クリックは保留modeを変更しない")
	harness.queue_free()

func _single_worker_loop_integration() -> void:
	## The player-facing one-worker proof must be authoritative. This test asks
	## the session for an opt-in mode rather than making a display layer pretend
	## that the normal relay hand-off is one person.
	SaveGame.disabled = true
	var main = load("res://scenes/main.tscn").instantiate()
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
	for destination in ["b_forest", "c_quarry"]:
		_check(main.world.request(destination), "単独追跡準備: 既存WorldTripで " + destination + " へ出発")
		for unused in 240:
			main._process(0.2)
			await process_frame
			if main.world.phase == "stopped" and main.world.region == destination:
				break
		_check(main.world.phase == "stopped" and main.world.region == destination, "単独追跡準備: " + destination + " へ停止")
	var created: Dictionary = RouteSession.create_from_game(main, "canyon-single-worker-loop", {"outpost_enabled": false, "single_worker_demo": true})
	_check(bool(created.get("ok", false)), "単独追跡準備: 敵なしC資源から単独検証sessionを作成")
	if not bool(created.get("ok", false)):
		main.queue_free()
		return
	var session = created.session
	var mode_enabled: bool = session.has_method("is_single_worker_demo") and bool(session.call("is_single_worker_demo"))
	_check(mode_enabled, "単独追跡: 通常分業を変えない opt-in single_worker_demo を明示する")
	if not mode_enabled:
		main.queue_free()
		return
	_check(session.gate_closed, "単独追跡: 検証開始時は橋を通る迂回経路を明示的に選ぶ")
	session.set_gate_closed(false)
	_check(session.gate_closed, "単独追跡: 橋を見せる検証中は主経路への切替で投影経路を崩さない")
	var tracked_actor_id := str(session.call("tracked_worker_id"))
	var tracked_actor: Dictionary = Dictionary(session.actors.get(tracked_actor_id, {})).duplicate(true)
	_check(tracked_actor_id == "worker:0" and str(tracked_actor.get("role", "")) == "solo" and bool(tracked_actor.get("direct_depot_loop", false)), "単独追跡: worker:0 だけが採取から既存搬入口まで担当する")
	var other_actors_idle := true
	for actor_id in session.actors:
		if str(actor_id) == tracked_actor_id:
			continue
		var actor: Dictionary = session.actors[actor_id]
		other_actors_idle = other_actors_idle and str(actor.get("state", "")) == "idle" and bool(actor.get("presentation_hidden", false))
	_check(other_actors_idle, "単独追跡: 他班は正本を動かさず表示対象から外れる")
	var tampered_demo_fixture: Dictionary = session.to_dict()
	for actor_id in session.actors:
		if str(actor_id) != tracked_actor_id:
			tampered_demo_fixture.actors[actor_id]["presentation_hidden"] = false
			break
	var tampered_demo_loaded: Dictionary = RouteSession.from_dict(tampered_demo_fixture)
	_check(not bool(tampered_demo_loaded.get("ok", false)), "単独追跡: fixtureが補助班を可視・稼働状態に戻したら復元を拒否")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var adapter = Adapter.new()
	adapter.configure(main, session)
	layer.add_child(adapter)
	await process_frame
	var crew_views = adapter.canyon_hub.get_node_or_null("CanyonCrewViews")
	var safe_service_approach: bool = adapter.canyon_hub.has_method("presentation_point_for_actor")
	if safe_service_approach:
		var service_foot: Vector2 = adapter.canyon_hub.call("presentation_point_for_actor", tracked_actor)
		var occupancy: CanyonRecoveryOccupancy = adapter.canyon_hub.get_node_or_null("Occupancy") as CanyonRecoveryOccupancy
		safe_service_approach = occupancy != null and occupancy.allows_walkable(service_foot) and not occupancy.solid_contains(service_foot) and service_foot.distance_to(adapter.canyon_hub.map_point(RecoveryRouteConnectionSession.BASE)) > 80.0
	_check(safe_service_approach, "単独追跡表示: 基地直下を横切らない地上の積卸しアプローチを使う")
	var has_animated_snapshot: bool = crew_views != null and crew_views.has_method("debug_snapshot")
	_check(has_animated_snapshot, "単独追跡表示: 読み取り専用の方向・frame・足元・cargo snapshotを持つ")
	if not has_animated_snapshot:
		adapter.queue_free()
		await process_frame
		main.queue_free()
		return
	_check(crew_views.view_count() == 1, "単独追跡表示: 追跡workerだけを可視化し通常班を変更しない")
	_check(adapter.detail_label != null and adapter.detail_label.text.contains("単独追跡") and adapter.detail_label.text.contains("手") and adapter.detail_label.text.contains("拠点"), "単独追跡HUD: 検証mode・作業状態・手荷物・拠点在庫を既存の小表示に明示")
	var idle_actor: Dictionary = tracked_actor.duplicate(true)
	idle_actor["state"] = "idle"
	idle_actor["carry_n"] = 0
	session.actors[tracked_actor_id] = idle_actor
	adapter.canyon_hub.refresh(0.0)
	await process_frame
	var idle_snapshot: Dictionary = crew_views.call("debug_snapshot", tracked_actor_id)
	_check(str(idle_snapshot.get("texture_path", "")).contains("canyon_recovery/v3/walk_west_0.png"), "単独追跡表示: 空手待機も固定足元のv3 canvasを使う")
	session.actors[tracked_actor_id] = tracked_actor.duplicate(true)
	adapter.canyon_hub.refresh(0.0)
	await process_frame
	var initial_total := int(adapter.session.initial_total())
	adapter.session.set_gate_closed(true)
	var visual_foot_fixed := true
	var walk_frames := {}
	var walk_directions := {}
	var harvest_frames := {}
	var harvest_direction := ""
	var harvest_foot_fixed := true
	var reached_carry := false
	for unused in 360:
		adapter._process(0.08)
		await process_frame
		var observed_actor: Dictionary = adapter.session.actors.get(tracked_actor_id, {})
		var snapshot: Dictionary = crew_views.call("debug_snapshot", tracked_actor_id)
		var expected_foot: Vector2 = adapter.canyon_hub.call("presentation_point_for_actor", observed_actor) if adapter.canyon_hub.has_method("presentation_point_for_actor") else adapter.canyon_hub.map_point(Vector2(float(observed_actor.get("x", 0.0)), float(observed_actor.get("y", 0.0))))
		var snapshot_foot: Vector2 = snapshot.get("foot_point", Vector2.INF)
		var state := str(observed_actor.get("state", ""))
		if state == "to_resource" and bool(snapshot.get("moving", false)):
			visual_foot_fixed = visual_foot_fixed and snapshot_foot.distance_to(expected_foot) <= 0.01
			walk_frames[str(snapshot.get("frame_name", ""))] = true
			walk_directions[str(snapshot.get("direction", ""))] = true
		if state == "harvesting":
			harvest_foot_fixed = harvest_foot_fixed and snapshot_foot.distance_to(expected_foot) <= 0.01 and not bool(snapshot.get("moving", true))
			harvest_frames[str(snapshot.get("frame_name", ""))] = true
			harvest_direction = str(snapshot.get("direction", ""))
		if state == "to_base" and int(observed_actor.get("carry_n", 0)) > 0 and harvest_frames.size() >= 2:
			reached_carry = true
			break
	_check(visual_foot_fixed and walk_frames.size() >= 2 and (walk_directions.has("west") or walk_directions.has("northwest")), "単独追跡表示: 実移動の画面方向に合わせて異なる脚frameを使い足元を固定")
	_check(harvest_foot_fixed and harvest_frames.size() >= 2 and not harvest_direction.is_empty(), "単独追跡表示: 採掘停止中は足を滑らせず道具frameだけを進める")
	_check(reached_carry, "単独追跡表示: 採掘完了後に正本carryを持つ基地向け運搬へ遷移")
	var depot_before := int(adapter.session.state_summary().get("depot", 0))
	var cycles := 0
	var harvest_hits := 0
	var carry_hits := 0
	var bypass_seen := false
	var closure_checked := false
	var fixture_checked := false
	var cargo_view_seen := false
	var unload_view_seen := false
	var cargo_removed_after_depot := false
	var storage_checks_ok := true
	var last_depot := depot_before
	for unused in 2400:
		adapter._process(0.12)
		await process_frame
		var live_actor: Dictionary = adapter.session.actors.get(tracked_actor_id, {})
		var state := str(live_actor.get("state", ""))
		var carried := int(live_actor.get("carry_n", 0))
		storage_checks_ok = storage_checks_ok and adapter.session.conservation_ok()
		bypass_seen = bypass_seen or str(live_actor.get("route", "")) == "bypass"
		if state == "harvesting":
			harvest_hits += 1
		if state == "to_base" and carried > 0:
			carry_hits += 1
			var carry_snapshot: Dictionary = crew_views.call("debug_snapshot", tracked_actor_id)
			cargo_view_seen = cargo_view_seen or bool(carry_snapshot.get("cargo_visible", false)) and str(carry_snapshot.get("frame_name", "")).begins_with("carry_")
			if not closure_checked:
				adapter.session.set_all_routes_closed(true)
				await process_frame
				adapter._process(0.12)
				await process_frame
				var blocked_actor: Dictionary = adapter.session.actors.get(tracked_actor_id, {})
				_check(str(blocked_actor.get("state", "")) == "safe_wait" and int(blocked_actor.get("carry_n", 0)) == carried and adapter.session.conservation_ok(), "単独追跡: 運搬中の全路閉鎖は手荷物を保った安全待機になる")
				adapter.session.set_all_routes_closed(false)
				var resumed := await _advance_adapter_until(adapter, func():
					var resumed_actor: Dictionary = adapter.session.actors.get(tracked_actor_id, {})
					return str(resumed_actor.get("state", "")) == "to_base" and int(resumed_actor.get("carry_n", 0)) == carried, 80)
				_check(resumed, "単独追跡: 経路再開後は同じ手荷物で基地への運搬を再開")
				closure_checked = true
			if not fixture_checked:
				var saved: Dictionary = adapter.session.save_project_fixture("canyon_single_worker_loop.json")
				_check(bool(saved.get("ok", false)), "単独追跡: 運搬中のsessionをproject fixtureへ保存")
				# Snapshot after the save. The preceding closure/reopen may have
				# legitimately refreshed the route, so a pre-save observation is
				# not the fixture contract.
				var saved_actor: Dictionary = Dictionary(adapter.session.actors.get(tracked_actor_id, {})).duplicate(true)
				var saved_summary: Dictionary = adapter.session.state_summary().duplicate(true)
				adapter._process(0.24)
				await process_frame
				var loaded: Dictionary = RouteSession.load_project_fixture("canyon_single_worker_loop.json")
				var loaded_actor: Dictionary = loaded.get("session", null).actors.get(tracked_actor_id, {}) if bool(loaded.get("ok", false)) else {}
				# JSON restores numeric values as floats. Compare the semantic
				# session/presentation contract rather than GDScript's int/float
				# container identity.
				var restored_exactly: bool = bool(loaded.get("ok", false)) and _same_solo_actor_state(saved_actor, loaded_actor) and loaded.session.state_summary() == saved_summary and bool(loaded.session.call("is_single_worker_demo"))
				_check(restored_exactly, "単独追跡: 保存読込は追跡actorの状態・手荷物・単独モードを一致復元")
				if bool(loaded.get("ok", false)):
					adapter.session = loaded.session
					adapter.canyon_hub.configure(adapter.session)
				fixture_checked = true
		var summary: Dictionary = adapter.session.state_summary()
		var current_snapshot: Dictionary = crew_views.call("debug_snapshot", tracked_actor_id)
		unload_view_seen = unload_view_seen or state == "dock_wait" and bool(current_snapshot.get("cargo_visible", false)) and str(current_snapshot.get("frame_name", "")).begins_with("unload_")
		var depot_now := int(summary.get("depot", 0))
		if depot_now > last_depot:
			cycles += 1
			cargo_removed_after_depot = cargo_removed_after_depot or not bool(current_snapshot.get("cargo_visible", true))
			_check(int(live_actor.get("carry_n", 0)) == 0 and depot_now > last_depot and bool(summary.get("conservation_ok", false)), "単独追跡: cycle %d の荷下ろしは手荷物消失と拠点在庫増加を同じsession更新で示す" % cycles)
			last_depot = depot_now
		if cycles >= 3:
			break
	_check(cycles >= 3 and harvest_hits > 0 and carry_hits > 0 and bypass_seen and closure_checked and fixture_checked, "単独追跡: 同じworkerが迂回を通る採取→運搬→収納を3回連続で完了")
	_check(cargo_view_seen and unload_view_seen and cargo_removed_after_depot, "単独追跡表示: 手荷物はcarry/dock中だけ可視で収納確定後に消える")
	var conservation_target := initial_total == int(adapter.session.state_summary().get("source_remaining", 0)) + int(adapter.session.state_summary().get("carried", 0)) + int(adapter.session.state_summary().get("relay", 0)) + int(adapter.session.state_summary().get("depot", 0))
	_check(storage_checks_ok and conservation_target and adapter.session.conservation_ok(), "単独追跡: 3 cycle の各観測点と最終時点で資源保存則を維持")
	var before_recall_actor: Dictionary = adapter.session.actors.get(tracked_actor_id, {})
	var before_recall_foot: Vector2 = adapter.canyon_hub.call("presentation_point_for_actor", before_recall_actor)
	adapter.session.request_recall()
	var after_recall_actor: Dictionary = adapter.session.actors.get(tracked_actor_id, {})
	var after_recall_foot: Vector2 = adapter.canyon_hub.call("presentation_point_for_actor", after_recall_actor)
	_check(before_recall_foot.distance_to(after_recall_foot) <= 0.01, "単独追跡表示: 帰還開始でservice approach上の足元を跳躍させない")
	var recall_fixture: Dictionary = RouteSession.from_dict(adapter.session.to_dict())
	_check(bool(recall_fixture.get("ok", false)), "単独追跡: 帰還を開始した隠し補助班を含むfixtureも安全に復元できる")
	var ready := await _advance_adapter_until(adapter, func(): return adapter.session.phase == "ready_to_exit", 900)
	_check(ready, "単独追跡: 帰還指示は手荷物と搬入口列を安全に解消")
	if ready:
		var session_before_rejected_commit: Dictionary = adapter.session.to_dict()
		var original_bonus: int = main.storage.capacity_bonus
		main.storage.capacity_bonus = -CargoDB.CAPACITY
		var rejected: Dictionary = adapter.session.commit_to_game(main)
		main.storage.capacity_bonus = original_bonus
		_check(not bool(rejected.get("ok", false)) and adapter.session.to_dict() == session_before_rejected_commit, "単独追跡: 拠点容量満杯時は確定を拒否し現地在庫を変えない")
	adapter.queue_free()
	await process_frame
	main.queue_free()

func _same_solo_actor_state(before: Dictionary, after: Dictionary) -> bool:
	return str(before.get("name", "")) == str(after.get("name", "")) \
		and str(before.get("role", "")) == str(after.get("role", "")) \
		and str(before.get("state", "")) == str(after.get("state", "")) \
		and str(before.get("route", "")) == str(after.get("route", "")) \
		and str(before.get("resume_state", "")) == str(after.get("resume_state", "")) \
		and str(before.get("wait_reason", "")) == str(after.get("wait_reason", "")) \
		and int(before.get("carry_item", -1)) == int(after.get("carry_item", -1)) \
		and int(before.get("carry_n", 0)) == int(after.get("carry_n", 0)) \
		and int(before.get("path_index", 0)) == int(after.get("path_index", 0)) \
		and bool(before.get("direct_depot_loop", false)) == bool(after.get("direct_depot_loop", false)) \
		and bool(before.get("presentation_hidden", false)) == bool(after.get("presentation_hidden", false)) \
		and is_equal_approx(float(before.get("x", 0.0)), float(after.get("x", 0.0))) \
		and is_equal_approx(float(before.get("y", 0.0)), float(after.get("y", 0.0))) \
		and is_equal_approx(float(before.get("work_left", 0.0)), float(after.get("work_left", 0.0)))
