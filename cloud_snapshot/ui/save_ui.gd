class_name SaveUI
extends CanvasLayer
## 明示的な1スロット保存。ロード/ニューゲーム/上書きは必ず確認。
static var skip_start_once := false
var game
var path := SaveGame.PATH
var checkpoint_path := SaveGame.CHECKPOINT_PATH
var _overlay: ColorRect
var _text: Label
var _confirm: Button
var _action := ""
var _action_buttons: Array[Button] = []
var _legacy: Button
var _legacy_path := ""
var _was_paused := false
var _field_failure_lock := false
var _failure_save_disabled := false
var _failure_reason := ""
var _startup := false
var _title: Label
var _cancel: Button

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var entry := UIKit.button("保存 / 続きから", open)
	entry.position = Vector2(1000, 558)
	entry.custom_minimum_size = Vector2(272, 34)
	var entry_layer := CanvasLayer.new()
	entry_layer.layer = 12
	add_child(entry_layer)
	entry_layer.add_child(entry)
	_overlay = ColorRect.new()
	_overlay.color = Color(0,0,0,0.85)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(240,80)
	panel.custom_minimum_size = Vector2(800,560)
	panel.add_theme_stylebox_override("panel",UIKit.box(Color("1b1e24"),UIKit.C_ACCENT,4,20))
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	panel.add_child(box)
	_title = UIKit.lbl("保存 / 続きから（1スロット）",24,UIKit.C_ACCENT)
	box.add_child(_title)
	_text = UIKit.lbl("",17)
	_text.custom_minimum_size = Vector2(0,135)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var message_scroll := ScrollContainer.new()
	message_scroll.name = "SaveMessageScroll"
	message_scroll.custom_minimum_size = Vector2(740, 135)
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_scroll.add_child(_text)
	box.add_child(message_scroll)
	for pair in [["手動で保存", "save"],["続きから", "load"],["バックアップから再開", "backup"],["出撃前checkpointからやり直す", "checkpoint"],["ニューゲーム", "new"]]:
		var action: String = pair[1]
		var action_button := UIKit.button(pair[0],func(): ask(action))
		action_button.set_meta("save_action", action)
		_action_buttons.append(action_button)
		box.add_child(action_button)
	_legacy = UIKit.button("旧version2を確認して移行",func(): ask("migrate"))
	box.add_child(_legacy)
	_legacy.hide()
	_confirm = UIKit.button("実行する",execute)
	box.add_child(_confirm)
	_cancel = UIKit.button("キャンセル / ゲームへ戻る",close)
	box.add_child(_cancel)
	for button in _action_buttons + [_legacy, _confirm, _cancel]:
		button.focus_mode = Control.FOCUS_ALL
	_overlay.hide()
	# 起動時に自動ロード/自動上書きしない。保存がある場合だけ選択画面で停止。
	if not skip_start_once and DisplayServer.get_name() != "headless" and not SaveGame.disabled and (SaveGame.exists(path) or SaveGame.exists(checkpoint_path)): open.call_deferred()
	skip_start_once = false

func _set_action_buttons_enabled(enabled: bool) -> void:
	for button in _action_buttons:
		if is_instance_valid(button):
			var action := str(button.get_meta("save_action", ""))
			button.disabled = not enabled or not _action_available(action)
			if action == "new": button.text = "新しく始める" if _startup else "ニューゲーム"
	if is_instance_valid(_legacy): _legacy.disabled = not enabled or _field_failure_lock

func _action_available(action: String) -> bool:
	if _field_failure_lock and action not in ["load", "backup", "checkpoint", "new"]: return false
	if _startup and action == "save": return false
	if action == "load": return SaveGame.exists(path)
	if action == "backup": return SaveGame.exists(path + ".bak")
	if action == "checkpoint": return SaveGame.exists(checkpoint_path)
	return true

func open_start() -> void:
	_startup = true
	open()
	_title.text = "流動拠点サバイバル — 第1地域"
	_text.text = "新しく始めるか、保存した進行を選んでください。選択中は時間が止まります。\n新しく始めても既存の保存は削除・上書きしません。保存は開始後の手動確認で行います。\n手動保存・バックアップ・出撃前checkpointは別の選択肢です。"

func _unlock_actions_after_confirmation() -> void:
	if is_open():
		_set_action_buttons_enabled(true)
		_focus_first_action()

func _keyboard_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for button in _action_buttons + [_legacy, _confirm, _cancel]:
		if button.is_visible_in_tree() and not button.disabled: buttons.append(button)
	return buttons

func _focus_first_action() -> void:
	var buttons := _keyboard_buttons()
	if not buttons.is_empty(): buttons[0].grab_focus()

func open_failed_field(reason: String, previous_save_disabled: bool) -> void:
	if not _field_failure_lock:
		_failure_save_disabled = previous_save_disabled
	_field_failure_lock = true
	_failure_reason = reason
	SaveGame.disabled = true
	layer = 120
	open()

func _release_failed_field() -> void:
	if not _field_failure_lock: return
	_field_failure_lock = false
	var gate = game.mine_arrival_gate
	if gate != null and gate.field != null and gate._save_override_active:
		gate._save_was_disabled = _failure_save_disabled
		SaveGame.disabled = true
	else:
		SaveGame.disabled = _failure_save_disabled
	_failure_reason = ""
	if game.mine_arrival_gate != null and game.mine_arrival_gate.has_method("reset_failed_entry"):
		game.mine_arrival_gate.reset_failed_entry()

func open() -> void:
	layer = 120
	_title.text = "保存 / 続きから（1スロット）"
	if not is_open():
		game.close_other_panels(self)
		_was_paused = get_tree().paused
		get_tree().paused = true
	_overlay.show()
	_action = ""
	_legacy.hide()
	_confirm.hide()
	_set_action_buttons_enabled(true)
	_focus_first_action()
	_text.text = "この画面を開いている間は時間が止まります。\n手動保存と出撃前checkpointは別枠です。終了時の自動保存・オフライン進行はありません。\n" + ("手動保存済みデータがあります。" if SaveGame.exists(path) else "まだ手動保存はありません。") + ("\n出撃前checkpointがあります。" if SaveGame.exists(checkpoint_path) else "\n出撃前checkpointはまだありません。")

	if _field_failure_lock:
		_text.text = _failure_reason + "\n現地の未確定回収は搬入していません。保存から再開するかニューゲームを選んでください。現在の失敗状態は保存・再開できません。"

func close() -> void:
	if not is_open(): return
	if _startup and not _field_failure_lock:
		open_start()
		return
	if _field_failure_lock:
		_action = ""
		_confirm.hide()
		_set_action_buttons_enabled(true)
		_focus_first_action()
		get_tree().paused = true
		return
	_overlay.hide()
	layer = 60
	_action = ""
	_set_action_buttons_enabled(true)
	get_tree().paused = _was_paused

func is_open() -> bool:
	return _overlay != null and _overlay.visible

func ask(action: String) -> void:
	if not _action_available(action): return
	if _action != "": return
	_action = action
	_set_action_buttons_enabled(false)
	_confirm.show()
	_confirm.grab_focus()
	match action:
		"save": _text.text = ("既存の保存を現在の進行で上書きします。直前の有効な保存はバックアップへ残します。" if SaveGame.exists(path) else "現在の進行を最初の保存として記録します。") + "\n旧version2は .legacy-v2、破損・その他の旧形式は .damaged に保全します。\n実行しますか？"
		"load", "backup": _text.text = "未保存の現在の進行を破棄し、%sから再開します。\n読込に失敗した場合は、現在の進行もファイルも変更しません。\n実行しますか？" % ("バックアップ" if action == "backup" else "保存")
		"checkpoint":
			if not SaveGame.exists(checkpoint_path):
				_text.text = "出撃前checkpointはまだありません。現在の進行は変更しません。"
				_action = ""
				_confirm.hide()
				_set_action_buttons_enabled(true)
				return
			var snapshot := SaveGame.read(checkpoint_path)
			if snapshot.is_empty() or not SaveGame.validate(snapshot,game) or not snapshot.get("town", {}) is Dictionary:
				_text.text = SaveGame.last_error if SaveGame.last_error != "" else "checkpointを確認できません。現在の進行は変更しません。"
				_action = ""
				_confirm.hide()
				_set_action_buttons_enabled(true)
				return
			var town_state: Dictionary = TownEconomy.normalized(snapshot.town)
			if town_state.is_empty():
				_text.text = "checkpointの街データを確認できません。現在の進行は変更しません。"
				_action = ""
				_confirm.hide()
				_set_action_buttons_enabled(true)
				return
			var fee := SaveGame.checkpoint_loss(int(town_state.credits))
			_text.text = "未保存の現在の進行を破棄し、出撃前checkpoint時点の通貨・装備・在庫・仲間・依頼・報酬受領・補充予約を一括復元します。\n所持金 %d Cr の10%%（%d Cr）だけを切捨て控除します。資源は失わず、同じcheckpointを選び直しても控除は累積しません。通常の「続きから」にはこの控除はありません。\n実行しますか？" % [town_state.credits, fee]
		"migrate": _text.text = "旧保存を消さず進行を読み込みます。鉱床滞在は大鉱山入口へ対応付けます。\n地域不明の街道は未配置で保持し、地図で村を出発地点にする際に別途同意が必要です。\n新形式の保存はこの後の手動保存で確認します。"
		"new": _text.text = "未保存の現在の進行を終了して、新しく始めます。\n既存の保存は削除しません。次に手動保存して上書きを確認するまで残ります。\n実行しますか？"

func execute() -> void:
	var action := _action
	if action == "": return
	if _field_failure_lock and action not in ["load", "backup", "checkpoint", "new"]:
		_action = ""
		return
	_action = ""
	_confirm.hide()
	# Keep the menu controls disabled through this input event.  Otherwise a
	# confirmation click can fall through to an action row exposed by layout
	# changes, such as "続きから".
	call_deferred("_unlock_actions_after_confirmation")
	match action:
		"save":
			var active_field: bool = game.mine_arrival_gate != null and game.mine_arrival_gate.field != null
			var ok := SaveGame.write_field(game,path,true) if active_field else SaveGame.write(game,path,true)
			_text.text = "保存しました。" if ok else SaveGame.last_error
		"load", "backup":
			var d := SaveGame.read(path + (".bak" if action == "backup" else ""))
			if d.is_empty():
				_text.text = SaveGame.last_error
				_legacy.visible = SaveGame.last_error.begins_with("旧version2")
				_legacy_path = path + (".bak" if action=="backup" else "")
				return
			if not SaveGame.apply(game,d):
				_text.text = SaveGame.last_error
				return
			_release_failed_field()
			_startup = false
			game.game_over = false
			if is_instance_valid(game._over_layer): game._over_layer.queue_free()
			_was_paused = d.has("field_snapshot")
			_text.text = "現地の続きへ戻りました。ゲームへ戻り、現地の「再開」で時間を進めてください。" if _was_paused else "再開データを読み込みました。ゲームへ戻ると時間が進みます。"
		"checkpoint":
			if not SaveGame.restore_checkpoint(game, checkpoint_path):
				_text.text = SaveGame.last_error
				return
			_release_failed_field()
			_startup = false
			game.game_over = false
			if is_instance_valid(game._over_layer): game._over_layer.queue_free()
			_was_paused = false
			_text.text = "出撃前checkpointから再開しました。所持金だけ10%切捨て控除済みです。ゲームへ戻ると時間が進みます。"
		"migrate":
			var raw:=SaveGame.read(_legacy_path,true)
			var converted:=SaveGame.migrate_v2(raw,game)
			if converted.is_empty() or not SaveGame.apply(game,converted):
				_text.text="移行できません。元ファイルは変更していません。"+SaveGame.last_error
				return
			_legacy.hide(); _was_paused=false; game.game_over=false; _startup=false
			if is_instance_valid(game._over_layer): game._over_layer.queue_free()
			_text.text="旧保存を読み込みました。元ファイルは未変更です。地域未配置の場合は地図を開いて移行を確認してください。"
		"new":
			_release_failed_field()
			skip_start_once = true
			get_tree().paused = false
			get_tree().reload_current_scene()

## Consume keys before focused field Controls, not after GUI dispatch.
func _input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey:
		get_viewport().set_input_as_handled()
		if not event.pressed or event.echo: return
		if event.keycode == KEY_ESCAPE:
			close()
			return
		var buttons := _keyboard_buttons()
		if buttons.is_empty(): return
		var focused := get_viewport().gui_get_focus_owner()
		var index := buttons.find(focused)
		if event.keycode in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			var backwards: bool = event.keycode in [KEY_UP, KEY_LEFT] or (event.keycode == KEY_TAB and event.shift_pressed)
			var next := (index - 1 if backwards else index + 1) if index >= 0 else 0
			buttons[posmod(next, buttons.size())].grab_focus()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and index >= 0:
			# Never activate a focused background field control through the modal.
			buttons[index].pressed.emit()
