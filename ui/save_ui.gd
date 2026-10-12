class_name SaveUI
extends CanvasLayer
## 明示的な1スロット保存。ロード/ニューゲーム/上書きは必ず確認。
static var skip_start_once := false
var game
var path := SaveGame.PATH
var _overlay: ColorRect
var _text: Label
var _confirm: Button
var _action := ""
var _legacy: Button
var _legacy_path := ""
var _was_paused := false

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
	panel.position = Vector2(240,110)
	panel.custom_minimum_size = Vector2(800,480)
	panel.add_theme_stylebox_override("panel",UIKit.box(Color("1b1e24"),UIKit.C_ACCENT,4,20))
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	panel.add_child(box)
	box.add_child(UIKit.lbl("保存 / 続きから（1スロット）",24,UIKit.C_ACCENT))
	_text = UIKit.lbl("",17)
	_text.custom_minimum_size = Vector2(740,135)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	for pair in [["手動で保存", "save"],["続きから", "load"],["バックアップから再開", "backup"],["ニューゲーム", "new"]]:
		var action: String = pair[1]
		box.add_child(UIKit.button(pair[0],func(): ask(action)))
	_legacy = UIKit.button("旧version2を確認して移行",func(): ask("migrate"))
	box.add_child(_legacy)
	_legacy.hide()
	_confirm = UIKit.button("実行する",execute)
	box.add_child(_confirm)
	box.add_child(UIKit.button("キャンセル / ゲームへ戻る",close))
	_overlay.hide()
	# 起動時に自動ロード/自動上書きしない。保存がある場合だけ選択画面で停止。
	if not skip_start_once and DisplayServer.get_name() != "headless" and not SaveGame.disabled and SaveGame.exists(path): open.call_deferred()
	skip_start_once = false

func open() -> void:
	if not is_open():
		game.close_other_panels(self)
		_was_paused = get_tree().paused
		get_tree().paused = true
	_overlay.show()
	_action = ""
	_legacy.hide()
	_confirm.hide()
	_text.text = "この画面を開いている間は時間が止まります。\n保存は手動です。終了時の自動保存・オフライン進行はありません。\n" + ("保存済みデータがあります。" if SaveGame.exists(path) else "まだ保存はありません。手動で保存すると最初の保存を作ります。")

func close() -> void:
	if not is_open(): return
	_overlay.hide()
	_action = ""
	get_tree().paused = _was_paused

func is_open() -> bool:
	return _overlay != null and _overlay.visible

func ask(action: String) -> void:
	_action = action
	_confirm.show()
	match action:
		"save": _text.text = ("既存の保存を現在の進行で上書きします。直前の有効な保存はバックアップへ残します。" if SaveGame.exists(path) else "現在の進行を最初の保存として記録します。") + "\n旧version2は .legacy-v2、破損・その他の旧形式は .damaged に保全します。\n実行しますか？"
		"load", "backup": _text.text = "未保存の現在の進行を破棄し、%sから再開します。\n読込に失敗した場合は、現在の進行もファイルも変更しません。\n実行しますか？" % ("バックアップ" if action == "backup" else "保存")
		"migrate": _text.text = "旧保存を消さず進行を読み込みます。鉱床滞在は大鉱山入口へ対応付けます。\n地域不明の街道は未配置で保持し、地図で村を出発地点にする際に別途同意が必要です。\n新形式の保存はこの後の手動保存で確認します。"
		"new": _text.text = "未保存の現在の進行を終了して、新しく始めます。\n既存の保存は削除しません。次に手動保存して上書きを確認するまで残ります。\n実行しますか？"

func execute() -> void:
	var action := _action
	_action = ""
	_confirm.hide()
	match action:
		"save":
			var ok := SaveGame.write(game,path,true)
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
			game.game_over = false
			if is_instance_valid(game._over_layer): game._over_layer.queue_free()
			_was_paused = false
			_text.text = "再開データを読み込みました。ゲームへ戻ると時間が進みます。"
		"migrate":
			var raw:=SaveGame.read(_legacy_path,true)
			var converted:=SaveGame.migrate_v2(raw,game)
			if converted.is_empty() or not SaveGame.apply(game,converted):
				_text.text="移行できません。元ファイルは変更していません。"+SaveGame.last_error
				return
			_legacy.hide(); _was_paused=false; game.game_over=false
			if is_instance_valid(game._over_layer): game._over_layer.queue_free()
			_text.text="旧保存を読み込みました。元ファイルは未変更です。地域未配置の場合は地図を開いて移行を確認してください。"
		"new":
			skip_start_once = true
			get_tree().paused = false
			get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE: close()
		get_viewport().set_input_as_handled()
