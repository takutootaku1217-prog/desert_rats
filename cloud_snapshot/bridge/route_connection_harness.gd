class_name RecoveryRouteConnectionHarness
extends Node
## 本編 main.tscn を変更せず、A地域の横視点→C固定クォータービュー→横視点を結ぶ検証入口。

const Session = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")

var game
var stage := "boot" # boot / to_site / field / returning / at_a
var bridge_layer: CanvasLayer
var launch_panel: PanelContainer
var status_label: Label
var notice_label: Label
var return_cancel_button: Button
var field = null
var run_counter := 0
var resume_requested := false
var single_worker_requested := false
var vertical_slice_requested := false

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	# 今回は通常保存を使わない。SaveUIも非表示かつ停止し、bridgeの明示的な
	# project-local fixture 以外へ書き込ませない。
	SaveGame.disabled = true
	resume_requested = OS.get_cmdline_user_args().has("route-bridge-resume") or OS.get_cmdline_user_args().has("--route-bridge-resume")
	game = load("res://scenes/main.tscn").instantiate()
	game.set("first_region_a_pilot", true)
	add_child(game)
	await get_tree().process_frame
	# This launcher owns a fresh, unsaved validation copy.  Keep its party idle
	# during A→B→C travel: a normal auto-job can otherwise reserve or carry a
	# C-site resource before the vertical session snapshots the party, causing
	# the player-facing entry gate to reject the slice.
	game.tool_auto = false
	for worker in game.workers:
		worker.stop_work()
		for job in GameData.job_list():
			worker.priorities[job] = 0
	if game.save_ui != null:
		game.save_ui.visible = false
		game.save_ui.process_mode = Node.PROCESS_MODE_DISABLED
	_build_overlay()
	stage = "at_a"
	_notice("検証専用入口です。通常 user:// 保存は無効で、A→B→C の横移動後に固定画面へ入ります。")
	if resume_requested:
		_start_to_site()

func _process(_delta: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	if stage == "to_site" and game.world.phase == "stopped":
		if game.world.region == "b_forest":
			_request_world("c_quarry")
		elif game.world.region == "c_quarry":
			_enter_field()
	if stage == "returning" and game.world.phase == "stopped":
		if game.world.region == "b_forest":
			_request_world("a_start")
		elif game.world.region == "a_start":
			stage = "at_a"
			_notice("A はじまりの街へ帰還しました。次の往復を開始できます。")
	_update_overlay()

func _build_overlay() -> void:
	bridge_layer = CanvasLayer.new()
	bridge_layer.layer = 90
	add_child(bridge_layer)
	var panel := PanelContainer.new()
	panel.name = "RouteBridgeLauncher"
	panel.position = Vector2(906, 18)
	panel.size = Vector2(354, 222)
	bridge_layer.add_child(panel)
	launch_panel = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "峡谷回収ルート接続試作（検証コピー限定）"
	box.add_child(title)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	var start_button := Button.new()
	start_button.text = "通常分業でA→C 古い採石場へ移動"
	start_button.pressed.connect(_start_normal_to_site)
	box.add_child(start_button)
	var vertical_slice_button := Button.new()
	vertical_slice_button.text = "入口固定停車でA→C（検証）"
	vertical_slice_button.pressed.connect(_start_vertical_slice_to_site)
	box.add_child(vertical_slice_button)
	var single_worker_button := Button.new()
	single_worker_button.text = "単独追跡でA→C（検証）"
	single_worker_button.pressed.connect(_start_single_worker_to_site)
	box.add_child(single_worker_button)
	return_cancel_button = Button.new()
	return_cancel_button.text = "横視点の復路を取消"
	return_cancel_button.pressed.connect(_cancel_return)
	box.add_child(return_cancel_button)
	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.modulate = Color("ffd38a")
	box.add_child(notice_label)
	_update_overlay()

func _update_overlay() -> void:
	if status_label == null or game == null:
		return
	if launch_panel != null:
		launch_panel.visible = not (stage == "field" and vertical_slice_requested)
	status_label.text = "段階: %s\n横視点: %s\n通常SaveGame: 無効 / 検証保存: project-local" % [stage, game.world.status_text().replace("\n", " ")]
	return_cancel_button.disabled = stage != "returning" or game.world.phase not in ["travel", "arriving", "turning"]

func _start_normal_to_site() -> void:
	_start_to_site(false)

func _start_single_worker_to_site() -> void:
	_start_to_site(true)

func _start_vertical_slice_to_site() -> void:
	_start_to_site(false, true)

func _start_to_site(request_single_worker := false, request_vertical_slice := false) -> void:
	if stage != "at_a":
		_notice("現在の段階では新しい出発を開始できません。")
		return
	if game.world.region != "a_start" or game.world.phase != "stopped":
		_notice("A はじまりの街へ停車してから開始してください。")
		return
	single_worker_requested = request_single_worker
	vertical_slice_requested = request_vertical_slice
	stage = "to_site"
	_request_world("b_forest")

func _request_world(destination: String) -> void:
	if not game.world.request(destination):
		_notice("横視点移動を開始できません: " + game.world.ready_reason())

func _enter_field() -> void:
	if field != null:
		return
	var result: Dictionary
	if resume_requested:
		result = Session.load_project_fixture("bridge_resume_session.json")
		resume_requested = false
		if bool(result.get("ok", false)) and result.get("session", null) != null and result.session.has_method("has_reserved_field_tool_kits") and bool(result.session.call("has_reserved_field_tool_kits")):
			result = {"ok": false, "reason": "携行採掘具を預けた縦切りは同じ実行中sessionでのみ読込できます。新しい本編倉庫へ二重に持ち込まないため再開を拒否しました"}
	else:
		run_counter += 1
		var options := {"outpost_enabled": true}
		if single_worker_requested:
			options = {"outpost_enabled": false, "single_worker_demo": true}
		elif vertical_slice_requested:
			options = {"outpost_enabled": false, "vertical_slice": true}
		result = Session.create_from_game(game, "route-%03d" % run_counter, options)
	if not bool(result.get("ok", false)):
		stage = "at_a"
		_notice("固定画面へ入れません: " + str(result.get("reason", "不明")))
		return
	game.visible = false
	game.process_mode = Node.PROCESS_MODE_DISABLED
	field = FieldAdapter.new()
	field.configure(game, result.session)
	bridge_layer.add_child(field)
	field.exit_to_horizontal.connect(_return_to_horizontal)
	stage = "field"
	if single_worker_requested:
		_notice("C 古い採石場の単独追跡検証へ入場しました。通常分業モードは変更していません。")
	elif vertical_slice_requested:
		_notice("入口固定停車の現地検証へ入場しました。仲間の回収・運搬・通路整備を検証します。")
	else:
		_notice("C 古い採石場の固定クォータービュー前哨地へ入場しました。既存装備の護衛が対処後に回収します。")

func _return_to_horizontal(result: Dictionary) -> void:
	if field != null:
		field.queue_free()
		field = null
	single_worker_requested = false
	vertical_slice_requested = false
	game.visible = true
	game.process_mode = Node.PROCESS_MODE_INHERIT
	stage = "returning"
	_notice("搬入確定: %s。横視点でC→B→Aへ戻ります。" % [str(result.get("summary", {}))])
	_request_world("b_forest")

func _cancel_return() -> void:
	if game.world.cancel_or_return():
		_notice("復路を取消しました。横視点の状態だけを反転し、貨物は増減しません。")
	else:
		_notice("この段階では復路を取消できません。")

func _notice(text: String) -> void:
	if notice_label != null:
		notice_label.text = text
