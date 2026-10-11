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
	_cancel = UIKit.button("移動／帰還を取り消す", func(): game.quarry.cancel())
	box.add_child(_cancel)
	box.add_child(UIKit.button("閉じる (G / Esc)", close))
	close()

func open() -> void:
	game.close_other_panels(self)
	_backdrop.show()
	_overlay.show()
	_refresh()

func close() -> void:
	_overlay.hide()
	_backdrop.hide()

func is_open() -> bool:
	return _overlay.visible

func _process(_delta: float) -> void:
	_entry.text = "採取地点 (G)" if game.quarry.state == "road" else "採取地点 (G) ・ " + {"approach":"移動中", "parked":"停車中", "recall":"帰還待ち", "returning":"復帰中"}.get(game.quarry.state, "")
	if is_open(): _refresh()

func _refresh() -> void:
	var q = game.quarry
	_info.text = "%s\n\n鉱床残量：近場 %d ／ 奥の密集群 %d\n近場は短い往復。奥は歩く距離が長く、食料と休憩の準備が必要です。\n残量は掘れる量で、持ち帰れる数は道具と能力で変わります。\n滞在中も食事・休憩・修理・天候は進みます。食材は自動補充されません。\n搬入口の残置：%s\n未採取の鉱床は再訪しても復活しません（この実行中のみ）。" % [q.status_text(), q.group_left("近場"), q.group_left("奥"), q.cargo_text()]
	_range.text = "採取範囲：近場のみ（押すと全体）" if q.near_only else "採取範囲：全体（押すと近場のみ）"
	_go.disabled = q.state != "road" or game.game_over
	_recall.disabled = q.state != "parked" or game.game_over
	_leave.disabled = not q.ready_to_leave() or game.game_over
	_cancel.disabled = q.state not in ["approach", "recall"] or game.game_over

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			if is_open(): close()
			else: open()
		elif event.keycode == KEY_ESCAPE and is_open(): close()
