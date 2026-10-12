class_name QuarryUI
extends CanvasLayer
var game
var _overlay: PanelContainer
var _backdrop: ColorRect
var _info: Label
var _go: Button
var _recall: Button
var _leave: Button
var _cancel: Button
var _range: Button
var _entry: Button
var _discard: Button
var _confirm: ColorRect
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button
var _discard_snapshot := {}
var _report: ColorRect
var _report_text: Label

func _ready() -> void:
	layer = 27
	var buttons := CanvasLayer.new()
	buttons.layer = 12
	add_child(buttons)
	_entry = UIKit.button("採取地点 (G)", open)
	_entry.position = Vector2(1000, 514)
	_entry.custom_minimum_size = Vector2(272, 36)
	buttons.add_child(_entry)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.5)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_overlay = PanelContainer.new()
	_overlay.position = Vector2(230, 95)
	_overlay.custom_minimum_size = Vector2(820, 480)
	_overlay.add_theme_stylebox_override("panel", UIKit.box(Color("202329"), Color("636b7a"), 3, 18))
	add_child(_overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_overlay.add_child(box)
	box.add_child(UIKit.lbl(QuarryDB.NAME, 24, UIKit.C_ACCENT))
	_info = UIKit.lbl("", 16)
	_info.custom_minimum_size = Vector2(775, 210)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_range = UIKit.button("", func(): game.quarry.near_only = not game.quarry.near_only)
	box.add_child(_range)
	var row := HBoxContainer.new()
	box.add_child(row)
	_go = UIKit.button("この鉱床へ向かう", func(): game.quarry.select())
	_recall = UIKit.button("採取を切り上げ、全員帰還", func(): game.quarry.request_departure())
	_leave = UIKit.button("街道へ出発", func(): game.quarry.leave())
	for b in [_go, _recall, _leave]: row.add_child(b)
	row.add_child(UIKit.button("採取記録", func(): _report_text.text = game.quarry.report_text(); _report.show()))
	_cancel = UIKit.button("移動／帰還を取り消す", func(): game.quarry.cancel())
	box.add_child(_cancel)
	_discard = UIKit.button("残置品を放棄して出発…", _ask_discard)
	box.add_child(_discard)
	box.add_child(UIKit.button("閉じる (G / Esc)", close))
	_confirm = ColorRect.new()
	_confirm.color = Color(0, 0, 0, 0.8)
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)
	var panel := PanelContainer.new()
	panel.position = Vector2(250, 200)
	panel.custom_minimum_size = Vector2(780, 260)
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("202329"), Color("bd7c67"), 3, 18))
	_confirm.add_child(panel)
	var confirm_box := VBoxContainer.new()
	confirm_box.add_theme_constant_override("separation", 20)
	panel.add_child(confirm_box)
	_confirm_text = UIKit.lbl("", 18)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(720, 130)
	confirm_box.add_child(_confirm_text)
	_confirm_yes = UIKit.button("表示した品を捨てて出発", _do_discard)
	_confirm_no = UIKit.button("取り消す（捨てない）", func(): _confirm.hide(); _discard_snapshot.clear())
	confirm_box.add_child(_confirm_yes)
	confirm_box.add_child(_confirm_no)
	_report = ColorRect.new()
	_report.color = Color(0,0,0,0.8)
	_report.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_report)
	var report_panel := PanelContainer.new()
	report_panel.position = Vector2(250,145)
	report_panel.custom_minimum_size = Vector2(780,380)
	report_panel.add_theme_stylebox_override("panel", UIKit.box(Color("202329"),Color("636b7a"),3,18))
	_report.add_child(report_panel)
	var report_box := VBoxContainer.new()
	report_box.add_theme_constant_override("separation",18)
	report_panel.add_child(report_box)
	_report_text = UIKit.lbl("",18)
	_report_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_text.custom_minimum_size = Vector2(720,280)
	report_box.add_child(_report_text)
	report_box.add_child(UIKit.button("閉じる",func(): _report.hide()))
	close()

func _ask_discard() -> void:
	_discard_snapshot = game.quarry.loose.duplicate()
	if _discard_snapshot.is_empty() or not game.quarry.crew_ready_to_leave(): return
	_confirm_text.text = "次の残置品を捨てて街道へ出発します。取り戻せません。\n\n" + game.quarry.cargo_text() + "\n\n倉庫・作業場・仲間の荷物は捨てません。"
	_confirm_yes.disabled = false
	_confirm.show()

func _do_discard() -> void:
	if not game.quarry.discard_and_leave(_discard_snapshot):
		_confirm_text.text = "数量または帰還状況が変わりました。取り消して内容を確認し直してください。"
		_confirm_yes.disabled = true
		return
	_confirm.hide()
	_discard_snapshot.clear()

func open() -> void:
	game.close_other_panels(self)
	_backdrop.show()
	_overlay.show()
	_refresh()

func close() -> void:
	_overlay.hide()
	_backdrop.hide()
	if _confirm != null: _confirm.hide()
	if _report != null: _report.hide()
	_discard_snapshot.clear()

func is_open() -> bool:
	return _overlay.visible

func _process(_delta: float) -> void:
	_entry.text = "採取地点 (G)" if game.quarry.state == "road" else "採取地点 (G) ・ " + {"approach":"移動中", "parked":"停車中", "recall":"帰還待ち", "returning":"復帰中"}.get(game.quarry.state, "")
	if is_open(): _refresh()
	if _report.visible: _report_text.text = game.quarry.report_text()

func _refresh() -> void:
	var q = game.quarry
	_info.text = "%s\n\n鉱床残量：近場 %d ／ 奥の密集群 %d\n近場は短い往復。奥は歩く距離が長く、食料と休憩の準備が必要です。\n残量1から主素材1個。道具と能力で採取時間が変わります。\n滞在中も食事・休憩・修理・天候は進みます。食材は自動補充されません。\n搬入口の残置：%s\n採取済みの分は再訪しても復活せず、未採取の残量を保持します（手動セーブに保存）。" % [q.status_text(), q.group_left("近場"), q.group_left("奥"), q.cargo_text()]
	_range.text = "採取範囲：近場のみ（押すと全体）" if q.near_only else "採取範囲：全体（押すと近場のみ）"
	_go.disabled = q.state != "road" or game.game_over
	_recall.disabled = q.state != "parked" or game.game_over
	_leave.disabled = not q.ready_to_leave() or game.game_over
	_discard.disabled = q.loose.is_empty() or not q.crew_ready_to_leave()
	_cancel.disabled = q.state not in ["approach", "recall"] or game.game_over

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			if is_open(): close()
			else: open()
		elif event.keycode == KEY_ESCAPE and is_open():
			if _report.visible:
				_report.hide()
			elif _confirm.visible:
				_confirm.hide()
				_discard_snapshot.clear()
			else: close()
