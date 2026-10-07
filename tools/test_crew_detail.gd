extends SceneTree
## 個体情報の集約・長い内容の閲覧・既存選択/配属/優先度の自己診断。
## Godot --headless --path . -s res://tools/test_crew_detail.gd
## OSの実クリックではなく、既存の選択入口・UIコールバックとControlの配置を検証する。

var fails := 0
var main
var detail
var W: Array


func check(cond: bool, message: String) -> void:
	if cond:
		print("  ok   ", message)
	else:
		fails += 1
		print("  FAIL ", message)


func _initialize() -> void:
	FacilityDB.start_all = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _layout()
	main.director.enabled = false
	main.target_speed = 0.0
	main.scroll_speed = 0.0
	main.tool_auto = false
	main.set_process(false)
	W = main.workers
	for w in W:
		w.set_process(false)
	detail = main.detail
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _layout() -> void:
	for i in 4:
		await process_frame


func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	if node is Label:
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels(child))
	return out


func _has_text(needle: String) -> bool:
	for l in _labels(detail._body):
		if l.text.contains(needle):
			return true
	return false


func _run() -> void:
	print("-- 同じ個体情報で、既存情報を確認できる --")
	main._select(W[0])
	var key := InputEventKey.new()
	key.keycode = KEY_C
	key.pressed = true
	detail._unhandled_input(key)
	await _layout()
	check(detail.layer == 27 and detail._overlay.get_parent() == detail and detail._button_layer.layer == 12, "開くボタンは通常HUD、管理画面は他の管理画面より上の別レイヤー")
	check(detail._tab_btns.size() == 2 and detail._tab_btns[0].text == "個体情報" and detail._tab_btns[1].text == "部署", "個体情報と部署の2タブ")
	for text in ["個体ランク", "得意分野", "分野ランク", "スキル", "採取道具", "仕事の効率", "仕事の優先度"]:
		check(_has_text(text), "個体情報に%sがある" % text)
	check(detail._live["view"]._gauges.size() == 3 and not detail._live["view"]._gauges.has("stamina"), "HP・満腹度・疲労度と精神状態を表示し、スタミナはない")
	check(_has_text("武器・防具：未実装"), "未実装の装備は機能があるように表示しない")

	print("-- 道具の現在値を、画面を閉じずに更新する --")
	W[0].tools.clear()
	detail._update_live()
	check(detail._live["tool_mine"].text.contains("素手") and detail._live["tool_chop"].text.contains("素手"), "持っていない枠は素手")
	check(detail._live["yield_mine"].text.contains("鉱床：採取対象外"), "素手で効率が既存の閾値未満になる鉱床は、採取対象外と表示する")
	W[0].tools["mine"] = GameData.Item.HAMMER
	detail._update_live()
	check(detail._live["tool_mine"].text.contains(GameData.ITEM_NAMES[GameData.Item.HAMMER]), "外部で道具が変わったとき、詳細の道具名が変わる")
	check(detail._live["yield_mine"].text.contains("岩場：回収率") and detail._live["yield_mine"].text.contains("鉱床：回収率") and not detail._live["yield_mine"].text.contains("個"), "装備後は既存の回収率を表示し、獲得個数と断定しない")
	check(_has_text("端数や袋の上限"), "回収率と実際の持ち帰り個数の違いを明示する")

	print("-- 閲覧対象と画面側の選択の関係 --")
	detail._picker.set_focus(W[2])
	check(detail._worker == W[2] and main.follow_target == W[0] and W[0].selected, "管理一覧で閲覧するだけではカメラの追従先を変えない")
	detail.close()
	detail._unhandled_input(key)
	check(detail._worker == W[0] and detail._picker.focus_worker == W[0] and detail._tab == 0, "Cで再度開くと、現在選択中の個体が表示される")
	main.ui.worker_selected.emit(W[1])
	check(detail._worker == W[1] and detail._picker.focus_worker == W[1] and main.follow_target == W[1], "上部カードの選択はmain._select経由で個体情報へ届く")
	W[2].visible = true
	W[2].away = false
	W[2].position = Vector2(1150.0, 580.0)
	var picked = main._pick_worker_at(W[2].position + Vector2(0.0, -30.0))
	check(picked == W[2], "世界側のクリック判定は頭・胴体から個体を選べる")
	if picked != null:
		main._select(picked)
	check(detail._worker == W[2] and main.follow_target == W[2], "世界側の選択も既存のmain._selectで詳細と追従先に届く")

	print("-- 長い情報と末尾の操作を閲覧できる --")
	W[2].char_name = "長い個体名を持つ仲間".repeat(10)
	for f in GameData.Field.values():
		W[2].ranks[f] = 5
	W[2].skills = ["長い説明を含む既存スキルの表示".repeat(8)]
	detail.show_worker(W[2])
	await _layout()
	var wrapped_name := false
	for l in _labels(detail._body):
		if l.text == W[2].char_name:
			wrapped_name = l.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and l.get_line_count() > 1
	check(wrapped_name, "長い個体名が折り返される")
	var panel: PanelContainer = null
	for child in detail._overlay.get_children():
		if child is PanelContainer:
			panel = child
	var viewport_size: Vector2 = root.get_visible_rect().size
	if panel != null:
		var panel_area: Rect2 = panel.get_global_rect()
		print("  配置: panel=%s viewport=%s" % [panel_area, viewport_size])
		check(panel_area.position.x >= 0.0 and panel_area.position.y >= 0.0 and panel_area.end.x <= viewport_size.x + 1.0 and panel_area.end.y <= viewport_size.y + 1.0, "長い名前の一覧を含め、管理画面全体がviewport内に収まる")
	else:
		check(false, "管理画面のPanelContainerがある")
	var name_button: Button = detail._picker._rows[W[2]]
	check(name_button.clip_text and name_button.tooltip_text.contains(W[2].char_name), "一覧の長い名前は幅を制限し、全文をツールチップで保持する")
	check(detail._body.size.x <= detail._scroll.size.x + 1.0, "詳細の長い情報が表示幅を押し広げない")
	check(detail._body.size.y > detail._scroll.size.y, "全個体情報は縦スクロールの対象になる")
	detail._scroll.scroll_vertical = 100000
	await _layout()
	var last: Control = detail._body.get_child(detail._body.get_child_count() - 1)
	var area: Rect2 = detail._scroll.get_global_rect()
	var end: Rect2 = last.get_global_rect()
	check(detail._scroll.scroll_vertical > 0 and end.position.y >= area.position.y - 1.0 and end.end.y <= area.end.y + 1.0, "スクロールすると末尾の優先度操作まで到達する")

	print("-- 個体操作と一括操作を取り違えない --")
	W[2].priorities[GameData.Job.GATHER] = 2
	var other_priority: int = W[0].priorities.get(GameData.Job.GATHER, 0)
	detail._update_live()
	var row: HBoxContainer = detail._live["prio_%d" % GameData.Job.GATHER].get_parent()
	for child in row.get_children():
		if child is Button and child.text == "＋":
			child.pressed.emit()
	check(W[2].priorities[GameData.Job.GATHER] == 3 and W[0].priorities.get(GameData.Job.GATHER, 0) == other_priority, "優先度ボタンは詳細を見ている1人だけ変更する")
	detail._set_filter(-1)
	detail._picker.clear_selection()
	detail._picker._set_selected(W[0], true)
	detail._picker._set_selected(W[1], true)
	var focused = detail._worker
	var focused_dept: int = focused.dept
	var target_dept: int = (focused_dept + 1) % GameData.Field.size()
	detail._move(detail._picker.selected_list(), target_dept)
	check(W[0].dept == target_dept and W[1].dept == target_dept and focused.dept == focused_dept, "まとめて配属はチェックした2人だけ変更し、閲覧中の個体は変えない")
	check(detail._picker.selected_list().size() == 2 and detail._members(target_dept).has(W[0]) and detail._members(target_dept).has(W[1]), "一括選択と配属後の部署一覧を保持する")
	detail._set_tab(1)
	check(_has_text("部署Lv") and _has_text("解放"), "部署タブに既存の部署Lv・解放情報が残る")
	detail._picker.set_focus(W[0])
	check(detail._tab == 0 and detail._worker == W[0] and detail._live.has("view"), "部署タブからメンバーを選ぶと、その個体情報を表示する")
