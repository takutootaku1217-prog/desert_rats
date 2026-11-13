class_name FirstRegionMineArrivalGate
extends CanvasLayer
## Player-facing bridge from the normal first-region C stop to the existing
## fixed quarter-view recovery session. JourneyPlan remains the authority for
## pass-through and stop plans.

const Session = preload("res://bridge/route_connection_session.gd")
const FieldAdapter = preload("res://bridge/route_connection_adapter.gd")
const SITE_ID := "c_quarry"

class ArrivalBlocker extends ColorRect:
	var game
	func _has_point(point: Vector2) -> bool:
		if not Rect2(Vector2.ZERO, size).has_point(point):
			return false
		# Navigation is created after this gate. Resolve its live geometry only
		# when hit-testing, and fail closed if it is absent or hidden.
		if not is_instance_valid(game) or not is_instance_valid(game.navigation):
			return true
		var bar: Control = game.navigation.bar
		if not is_instance_valid(bar) or not bar.is_visible_in_tree():
			return true
		var viewport_point := get_global_transform_with_canvas() * point
		var bar_point := bar.get_global_transform_with_canvas().affine_inverse() * viewport_point
		return not Rect2(Vector2.ZERO, bar.size).has_point(bar_point)

var game
var field = null
var _state := "idle" # idle / arrival_choice / entry_wait / field
var _entry_stance := ""
var _field_failure_button: Button
var _entry_options := {}
var _outpost_button: Button
var _boss_button: Button
var _outpost_warning: Label
var _enter_button: Button
var _cancel_button: Button
var _save_override_active := false
var _dismissed_here := false
var _session_serial := 0
var _save_was_disabled := false
var _overlay: ColorRect
var _panel: PanelContainer
var _notice: Label
var _outpost_dialog: ConfirmationDialog
var _outpost_owns_pause := false
var _outpost_was_paused := false

func setup(p_game) -> void:
	game = p_game
	if game != null and not game.tree_exiting.is_connected(_on_game_tree_exiting):
		game.tree_exiting.connect(_on_game_tree_exiting)

func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_choice()

func _exit_tree() -> void:
	cancel_outpost_entry()
	_restore_entry_stance()
	if field != null and is_instance_valid(field):
		field.queue_free()
	field = null
	if game != null and is_instance_valid(game):
		game.visible = true
		if game.process_mode == Node.PROCESS_MODE_DISABLED:
			game.process_mode = Node.PROCESS_MODE_INHERIT
	if _save_override_active:
		SaveGame.disabled = _save_was_disabled

func _on_game_tree_exiting() -> void:
	queue_free()

func _process(_delta: float) -> void:
	if game == null or not is_instance_valid(game):
		queue_free()
		return
	if _notice != null and _panel != null:
		_notice.position.y = _panel.position.y + _panel.size.y + 8.0
	if _field_failure_button != null:
		_field_failure_button.visible = field != null and is_instance_valid(field) and field.session.actors.keys().any(func(actor_id): return bool(field.session.actors[actor_id].get("down", false)) or field.session.expired_recovery.owns(str(actor_id)))
		if _field_failure_button.visible:
			_field_failure_button.move_to_front()
	if game.game_over:
		cancel_outpost_entry()
		cancel_pending_entry()
		_hide_choice()
		return
	if field != null:
		return
	if is_outpost_confirmation_open() and not _outpost_confirmation_context():
		cancel_outpost_entry()
	# Suppress presentation, not the unresolved decision or recall orders.
	# A ready recall must not replace a management panel with a hidden field.
	var managing: bool = game.has_open_management_panel(self)
	visible = not managing
	if managing and _at_stopped_mine():
		return
	if _state == "entry_wait":
		if not _at_stopped_mine():
			cancel_pending_entry()
		else:
			var reason := str(game.world.ready_reason())
			if reason.is_empty():
				_complete_entry()
			else:
				_notice.text = "入場準備中: " + reason + "\n仲間の帰還後に入ります。取消できます。"
				_notice.show()
				_notice.position.y = _panel.position.y + _panel.size.y + 8.0
			return
	if _at_stopped_mine():
		if not _dismissed_here and _state == "idle":
			_show_choice()
		return
	# Leaving C (including a normal return turn) enables a fresh decision only
	# when C becomes a stopped destination again. It never changes trip state.
	_dismissed_here = false
	if _state == "arrival_choice":
		_hide_choice()

func visible_state() -> String:
	return _state

## Presentation only. Readiness belongs to enter_mine(), so workers outside
## do not prevent a player from reaching its existing recall controls.
func can_reopen_from_map() -> bool:
	if not is_instance_valid(game) or not _at_stopped_mine():
		return false
	return game.world.active and game.quarry.state == "road" and game.visible and not game.game_over \
		and field == null and _state in ["idle", "arrival_choice"] \
		and game.map_ui != null and game.map_ui.is_open() \
		and not game.has_open_management_panel(game.map_ui)

func reopen_from_map() -> bool:
	if not can_reopen_from_map():
		return false
	# Existing close restores prior pause and focus/quote cleanup. No await:
	# validation, map close and choice reveal are one synchronous UI action.
	game.map_ui.close()
	_dismissed_here = false
	_show_choice()
	show()
	return true

func suspend_choice_for_panel() -> void:
	cancel_outpost_entry()
	if field == null and _state in ["arrival_choice", "entry_wait"]:
		hide()

func is_outpost_confirmation_open() -> bool:
	return _outpost_owns_pause

func _outpost_confirmation_context() -> bool:
	return is_instance_valid(game) and _state == "arrival_choice" and field == null \
		and _at_stopped_mine() and game.world.active and game.quarry.state == "road" \
		and game.visible and not game.game_over and _panel.is_visible_in_tree() \
		and not game.has_open_management_panel(self)

func request_outpost_entry() -> bool:
	if is_outpost_confirmation_open() or not _outpost_confirmation_context():
		return false
	# No options, recall, session, save or resource mutation before consent.
	_outpost_was_paused = get_tree().paused
	_outpost_owns_pause = true
	get_tree().paused = true
	_outpost_dialog.popup_centered(Vector2i(760, 360))
	_outpost_dialog.get_cancel_button().grab_focus()
	return true

func cancel_outpost_entry() -> void:
	if _outpost_dialog != null:
		_outpost_dialog.hide()
	if _outpost_owns_pause:
		_outpost_owns_pause = false
		if get_tree() != null:
			get_tree().paused = _outpost_was_paused

func _confirm_outpost_entry() -> void:
	if not is_outpost_confirmation_open():
		return
	var eligible := _outpost_dialog.visible and _outpost_confirmation_context()
	# Consume first; duplicate/stale signals cannot create a second session.
	cancel_outpost_entry()
	if eligible:
		enter_mine(true)

func enter_boss() -> bool:
	return enter_mine(false,FirstRegionCompletion.ENCOUNTER_ID)

func enter_mine(outpost := false, encounter := "") -> bool:
	if _state != "arrival_choice" or field != null or not _at_stopped_mine() or game.game_over or game.has_open_management_panel():
		return false
	# Refuse unsupported boss equipment before a pending recall changes orders.
	# Session creation rechecks this boundary if equipment changes while waiting.
	if encounter == FirstRegionCompletion.ENCOUNTER_ID:
		var loadout_reason := Session.boss_loadout_reason(game)
		if not loadout_reason.is_empty():
			_notice.text = loadout_reason
			_notice.show()
			return false
	_entry_options = {"outpost_enabled": outpost,"encounter_id":encounter}
	# Ordinary C entry is the one-site route-engineering verification. The optional
	# outpost fixture remains separate so combat never changes cart-route state.
	if not outpost:
		_entry_options["mine_path_engineering"] = true
		_entry_options["cart_shortcut_cleared"] = bool(game.world.call("c_quarry_cart_shortcut_cleared")) if game.world != null and game.world.has_method("c_quarry_cart_shortcut_cleared") else false
	if not game.world.ready_reason().is_empty():
		_entry_stance = str(game.operations.stance)
		if not game.operations.set_stance("recall"):
			_entry_stance = ""
			return false
		_state = "entry_wait"
		_outpost_warning.visible = outpost
		_enter_button.disabled = true
		_outpost_button.disabled = true
		_boss_button.disabled = true
		_enter_button.text = "仲間の帰還を待っています"
		_cancel_button.show()
		_notice.text = "入場準備中: " + str(game.world.ready_reason())
		_notice.show()
		return false # Compatibility: true means a field was actually created.
	return _complete_entry()

func cancel_pending_entry() -> void:
	if _state != "entry_wait":
		return
	_restore_entry_stance()
	_entry_options.clear()
	_state = "arrival_choice"
	_enter_button.disabled = false
	_outpost_button.disabled = false
	_refresh_boss_choice()
	_outpost_warning.show()
	_enter_button.text = "採掘地に入る"
	_cancel_button.hide()
	_notice.hide()

func _restore_entry_stance() -> void:
	if _entry_stance.is_empty():
		return
	if game != null and is_instance_valid(game):
		if not game.operations.set_stance(_entry_stance):
			game.operations.stance = _entry_stance
	_entry_stance = ""

func _complete_entry() -> bool:
	var next_id := _session_serial + 1
	var made: Dictionary = Session.create_from_game(game, "mine-arrival-%03d" % next_id, _entry_options)
	if not bool(made.get("ok", false)):
		cancel_pending_entry()
		_restore_entry_stance()
		_entry_options.clear()
		_notice.text = "採掘地に入れません: " + str(made.get("reason", "不明な理由"))
		_notice.show()
		return false
	_entry_options.clear()
	_session_serial = next_id
	_save_was_disabled = SaveGame.disabled
	_save_override_active = true
	SaveGame.disabled = true
	_hide_choice()
	game.close_other_panels(null)
	game.visible = false
	game.process_mode = Node.PROCESS_MODE_DISABLED
	field = FieldAdapter.new()
	field.name = "FirstRegionMineRecoveryField"
	field.configure(game, made.session)
	add_child(field)
	show()
	field.exit_to_horizontal.connect(_on_field_exit)
	_state = "field"
	return true

func fail_field_to_menu(reason: String) -> bool:
	if field == null or not is_instance_valid(field): return false
	var failed = field
	if failed.life_clock != null:
		reason += "\n" + failed.life_clock.failure_status_text()
	field = null
	failed.process_mode = Node.PROCESS_MODE_DISABLED
	failed.hide()
	# Restore parentage before destroying the adapter; never commit this session.
	failed.call("_restore_workers")
	remove_child(failed)
	failed.queue_free()
	_restore_entry_stance()
	_entry_options.clear()
	_state = "failed"
	_dismissed_here = true
	_hide_choice()
	_field_failure_button.hide()
	game.visible = true
	game.process_mode = Node.PROCESS_MODE_INHERIT
	var previous_disabled := _save_was_disabled
	_save_override_active = false
	if not game.game_over: game._game_over()
	game.save_ui.open_failed_field(reason, previous_disabled)
	return true

func reset_failed_entry() -> void:
	if _state == "failed":
		_state = "idle"
		_dismissed_here = false

func decline_entry() -> bool:
	if _state not in ["arrival_choice", "entry_wait"] or field != null or not _at_stopped_mine():
		return false
	cancel_pending_entry()
	_dismissed_here = true
	_hide_choice()
	if game.map_ui != null:
		game.map_ui.open()
	return true

func _on_field_exit(result: Dictionary) -> void:
	if field == null:
		return
	var exiting = field
	field = null
	if is_instance_valid(exiting):
		exiting.queue_free()
	if game != null and is_instance_valid(game):
		game.visible = true
		game.process_mode = Node.PROCESS_MODE_INHERIT
	SaveGame.disabled = _save_was_disabled
	_save_override_active = false
	_restore_entry_stance()
	_dismissed_here = true
	_state = "idle"
	_hide_choice()
	if game != null and is_instance_valid(game):
		game.director.note(return_receipt(result))

## Presentation only: a failed/malformed result must not look like an empty
## successful delivery. The session remains the sole cargo/commit authority.
func return_receipt(result: Variant) -> String:
	if not result is Dictionary or not result.get("ok") is bool:
		return "帰還結果を確認できません。搬入内容は未確認です。"
	if not result.ok:
		var reason: Variant = result.get("reason")
		return "帰還を確認できません: " + reason if reason is String and not reason.is_empty() else "帰還結果は未確認です。"
	var summary: Variant = result.get("summary")
	if not summary is Dictionary or not summary.has("deposited") or not summary.has("left_outside"):
		return "帰還結果を確認できません。搬入内容は未確認です。"
	if summary.has("conservation_ok") and (not summary.conservation_ok is bool or not summary.conservation_ok):
		return "帰還結果の数量の整合を確認できません。搬入内容は未確認です。"
	var loaded := _receipt_cargo(summary.deposited)
	var outside := _receipt_cargo(summary.left_outside)
	var prefix := "帰還結果に未確認の荷物があります。" if loaded == "未確認" or outside == "未確認" else "採掘地から車体へ帰還。"
	return prefix + "車内へ搬入: " + loaded + "。Cに残す: " + outside + "。"

func _receipt_cargo(cargo: Variant) -> String:
	if not cargo is Dictionary:
		return "未確認"
	# Validate before sorting: unknown/mixed keys and lossy count coercions must
	# not silently become known items or disappear from the receipt.
	for item in cargo:
		if not item is int or not GameData.ITEM_NAMES.has(item):
			return "未確認"
		var count: Variant = cargo[item]
		if typeof(count) not in [TYPE_INT, TYPE_FLOAT] or count < 0:
			return "未確認"
		if count is float and (not is_finite(count) or count != floor(count) or count >= 9223372036854775808.0):
			return "未確認"
	var items: Array = cargo.keys()
	items.sort()
	var rows: PackedStringArray = []
	for item in items:
		if cargo[item] > 0:
			rows.append("%s×%d" % [GameData.ITEM_NAMES[item], int(cargo[item])])
	return "なし" if rows.is_empty() else "、".join(rows)

func _at_stopped_mine() -> bool:
	return game != null and game.world != null and game.world.first_region() and game.world.region == SITE_ID and game.world.phase == "stopped"

func _show_choice() -> void:
	_state = "arrival_choice"
	_notice.hide()
	_enter_button.disabled = false
	_outpost_button.disabled = false
	_refresh_boss_choice()
	_outpost_warning.show()
	_enter_button.text = "採掘地に入る"
	_cancel_button.hide()
	_overlay.show()
	_panel.show()

func _refresh_boss_choice() -> void:
	var done:bool=FirstRegionCompletion.boss_returned(game.world.region_completion)
	_boss_button.disabled=done
	_boss_button.text="採石場の主：撃破・帰還確定済み" if done else "採石場の主に挑む（地域目標）"

func _hide_choice() -> void:
	cancel_outpost_entry()
	if _state == "arrival_choice":
		_state = "idle"
	if _overlay != null:
		_overlay.hide()
	if _panel != null:
		_panel.hide()
	if _notice != null:
		_notice.hide()

func _build_choice() -> void:
	_overlay = ArrivalBlocker.new()
	_overlay.game = game
	_overlay.name = "MineArrivalModalBlocker"
	_overlay.color = Color(0.03, 0.05, 0.05, 0.22)
	_overlay.position = Vector2.ZERO
	_overlay.size = Vector2(1280, 720)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_panel = PanelContainer.new()
	_panel.name = "MineArrivalChoice"
	_panel.position = Vector2(774, 168)
	_panel.custom_minimum_size = Vector2(430, 214)
	_panel.add_theme_stylebox_override("panel", UIKit.box(Color("20332c", 0.97), Color("e5c57c"), 2, 10))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	_panel.add_child(box)
	box.add_child(UIKit.lbl("C 鉱山入口に到着", 22))
	var detail := UIKit.lbl("車体は停車しています。固定クォータービューの採掘地に入るか、全体マップで次の行き先を選びます。", 16)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(396, 62)
	box.add_child(detail)
	_enter_button = UIKit.button("採掘地に入る", enter_mine)
	box.add_child(_enter_button)
	_boss_button = UIKit.button("採石場の主に挑む（地域目標）", enter_boss)
	_boss_button.tooltip_text = "独立したボス挑戦。既存の護衛が戦います。負傷時は撤退、戦闘不能時は手動救助。撃破後、全員と荷物を帰還して確定。HP72は暫定です。"
	box.add_child(_boss_button)
	_outpost_button = UIKit.button("危険な前哨地・戦闘検証に入る", request_outpost_entry)
	box.add_child(_outpost_button)
	_outpost_warning = UIKit.lbl("前哨地の専用検証：既存敵3体。負傷する前に撤退。", 13, Color("ffd38a"))
	_outpost_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outpost_warning.custom_minimum_size = Vector2(396, 0)
	box.add_child(_outpost_warning)
	var rescue_guidance := UIKit.lbl("救助は手動指定。残り時間内に担ぎ上げて入口へ搬送。\n経路・装備に制限あり。未救助者が残ると帰還確定できません。", 13, Color("ffd38a"))
	rescue_guidance.name = "RescueGuidance"
	rescue_guidance.mouse_filter = Control.MOUSE_FILTER_PASS
	rescue_guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rescue_guidance.custom_minimum_size = Vector2(396, 0)
	rescue_guidance.tooltip_text = "期限切れ後は長期行動不能の後に自力回復・入口へ帰還する暫定仕様です。都市での復活仕様は未確定です。経路の状態や担ぎ手の装備によって指定できない場合があります。"
	box.add_child(rescue_guidance)
	_cancel_button = UIKit.button("入場待ちを取消", cancel_pending_entry)
	box.add_child(_cancel_button)
	_cancel_button.hide()
	box.add_child(UIKit.button("入らず出発（全体マップへ）", decline_entry))
	_notice = UIKit.lbl("", 15, Color("ffd38a"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.position = Vector2(774, 392)
	_notice.size = Vector2(430, 90)
	add_child(_notice)
	_notice.hide()
	_overlay.hide()
	_panel.hide()
	_field_failure_button = UIKit.button("戦闘不能・負傷：失敗として終了", func(): fail_field_to_menu("仲間が戦闘不能になり、現地検証に失敗しました。"))
	_field_failure_button.position = Vector2(960, 658)
	_field_failure_button.custom_minimum_size = Vector2(300, 42)
	_field_failure_button.z_index = 100
	_field_failure_button.tooltip_text = "未確定回収を搬入せず終了。既存保存からの再開またはニューゲームへ。"
	add_child(_field_failure_button)
	_field_failure_button.hide()
	_outpost_dialog = ConfirmationDialog.new()
	_outpost_dialog.title = "危険な前哨地への入場確認"
	_outpost_dialog.ok_button_text = "確認して前哨地に入る"
	_outpost_dialog.cancel_button_text = "取消（入場しない）"
	_outpost_dialog.dialog_autowrap = true
	_outpost_dialog.dialog_hide_on_ok = false
	_outpost_dialog.exclusive = true
	# Reserve width before autowrap computes its minimum height. Otherwise the
	# first layout can shrink to the buttons' width and push actions offscreen.
	_outpost_dialog.min_size = Vector2i(760, 360)
	_outpost_dialog.dialog_text = "通常採掘や地域目標のボスとは別の任意モードです。\n\n戦闘で仲間が負傷・戦闘不能になることがあります。救助は手動指定で、経路・装備に制限があります。全員と荷物の帰還準備が整うまで帰還確定できません。\n\nこのモードは途中保存に対応していません。終了後に現地の続きから再開することはできません。帰還確定後に手動保存してください。入場時の自動保存はありません。\n\n必要なら取消して、先に手動保存してください。"
	_outpost_dialog.get_label().add_theme_font_size_override("font_size", 18)
	_outpost_dialog.confirmed.connect(_confirm_outpost_entry)
	_outpost_dialog.canceled.connect(cancel_outpost_entry)
	_outpost_dialog.close_requested.connect(cancel_outpost_entry)
	add_child(_outpost_dialog)

func discard_field_for_load() -> void:
	cancel_outpost_entry()
	if field == null: return
	var previous = field
	field = null
	previous.discard_for_load()
	remove_child(previous)
	previous.free()
	if _save_override_active: SaveGame.disabled = _save_was_disabled
	_save_override_active = false
	_entry_stance = ""
	_entry_options.clear()
	_state = "idle"
	game.visible = true
	game.process_mode = Node.PROCESS_MODE_INHERIT

## Only SaveGame's validated complete bundle reaches this publication step.
func install_saved_field(bundle: Dictionary) -> void:
	_save_was_disabled = SaveGame.disabled
	_session_serial = maxi(_session_serial, int(bundle.gate_serial))
	_entry_stance = bundle.entry_stance
	_save_override_active = true
	SaveGame.disabled = true
	_hide_choice()
	game.visible = false
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var restored = bundle.session
	restored.life_clock_token = ""
	field = FieldAdapter.new()
	field.configure(game, restored)
	add_child(field)
	show()
	for i in game.workers.size():
		var key: int = game.workers[i].get_instance_id()
		field.original_positions[key] = bundle.workers[i].position
		field.original_process_modes[key] = bundle.workers[i].mode
		field.original_visibilities[key] = bundle.workers[i].visible
	field.exit_to_horizontal.connect(_on_field_exit)
	field._owns_field_pause = true
	field.vehicle_pause_button.text = "再開"
	_state = "field"
