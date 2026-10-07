extends SceneTree
## 人数が増えても通常HUDを広げず、管理一覧から末尾の個体を扱えるかを検証する。
## Godot --headless --path . -s res://tools/test_crew_hud.gd
## 診断中だけ既存の定義を基に27人を追加する。AI・走行・出来事を止めたUIの境界試験で、
## 実際の初期人数や、30人のAI性能・OSの実クリックを検証するものではない。

var fails := 0
var main
var detail
var W: Array
var _hud_rect: Rect2
var _hud_controls := 0


func check(cond: bool, message: String) -> void:
	if cond:
		print("  ok   ", message)
	else:
		fails += 1
		print("  FAIL ", message)


func _initialize() -> void:
	seed(20261007)
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
	await _layout()
	print("  条件: seed=20261007、AI/走行/出来事停止、既存3人＋診断内だけの27人、入力はUIコールバック")
	await _run()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _layout() -> void:
	for i in 5:
		await process_frame


func _control_count(node: Node) -> int:
	var n := 1 if node is Control else 0
	for child in node.get_children():
		n += _control_count(child)
	return n


func _status_view_count(node: Node) -> int:
	var n := 1 if node is CrewStatusView else 0
	for child in node.get_children():
		n += _status_view_count(child)
	return n


func _panel() -> PanelContainer:
	for child in detail._overlay.get_children():
		if child is PanelContainer:
			return child
	return null


func _within(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0 \
		and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0


func _append_fixture() -> void:
	var definition: Dictionary = main.WORKER_DEFS[0]
	var worker_parent: Node = W[0].get_parent()
	for i in range(W.size(), 30):
		var profile: Dictionary = definition["profile"].duplicate(true)
		profile["level"] = 30 - i
		profile["dept"] = GameData.Field.GATHERER if i % 2 == 0 else GameData.Field.COOK
		profile["ranks"] = {}
		for field in GameData.Field.values():
			profile["ranks"][field] = 0
		var label := "診断用の仲間%02d" % (i + 1)
		if i == 29:
			label = "30人目の長い名前を持つ仲間_".repeat(8)
		var w := Worker.new()
		w.setup(main, label, definition["palette"], definition["prio"], i, profile)
		w.position = Vector2(1800.0 + i * 70.0, GameData.LO_Y)
		worker_parent.add_child(w)
		w.set_process(false)
		W.append(w)


func _run() -> void:
	print("-- 通常HUDは人数に依存しない --")
	check(W.size() == 3 and not detail._overlay.visible, "実際の初期人数は3人で、詳細管理は普段閉じている")
	main.ui._process(0.0)
	await _layout()
	_hud_rect = main.ui._button.get_global_rect()
	_hud_controls = _control_count(main.ui)
	check(main.ui._button.text.contains("3人") and _hud_rect.size.is_equal_approx(Vector2(144, 44)), "3人の入口は人数とCキーを示す144×44の固定サイズ")
	check(_status_view_count(main.ui) == 0, "通常HUDに個体別の状態ゲージを常駐させない")
	main.ui._button.pressed.emit()
	await _layout()
	check(detail._overlay.visible and detail._worker == W[0], "上部の管理入口から現在選択中の個体情報を開く")
	detail.close()
	check(not detail._overlay.visible, "閉じたら個体情報が通常画面に残らない")
	_append_fixture()
	main.ui._process(0.0)
	await _layout()
	check(W.size() == 30 and main.ui._button.text.contains("30人"), "診断で追加した人数を管理入口に反映する")
	check(main.ui._button.get_global_rect().is_equal_approx(_hud_rect) and _control_count(main.ui) == _hud_controls, "30人でも通常HUDの位置・寸法・Control数は3人のときと同じ")
	check(_status_view_count(main.ui) == 0 and not detail._overlay.visible, "30人でも個体情報や30組の状態ゲージを通常画面へ並べない")

	print("-- 30人の末尾と長い名前を管理できる --")
	var last = W[29]
	main._select(W[0])
	main.ui._button.pressed.emit()
	detail._set_filter(-1)
	await _layout()
	check(detail._picker._rows.size() == 30, "全員一覧に30人全員がある")
	var last_row: Button = detail._picker._rows[last]
	check(last_row.get_parent().get_index() == detail._picker._box.get_child_count() - 1, "境界試験の対象は実際の一覧の最後の行")
	detail._picker._scroll.scroll_vertical = 100000
	await _layout()
	check(detail._picker._scroll.scroll_vertical > 0 and _within(last_row.get_global_rect(), detail._picker._scroll.get_global_rect()), "一覧をスクロールすると30人目の行全体へ到達する")
	last_row.pressed.emit()
	await _layout()
	check(detail._worker == last and detail._picker.focus_worker == last and detail._live.has("view"), "最後の行から30人目の個体情報を閲覧できる")
	check(main.follow_target == W[0] and W[0].selected, "管理一覧を閲覧するだけではゲーム側の選択・カメラ追従を変えない")
	var panel := _panel()
	check(panel != null and _within(panel.get_global_rect(), root.get_visible_rect()), "30人目の長い名前でも管理画面はviewport内に収まる")
	check(last_row.clip_text and last_row.tooltip_text.contains(last.char_name), "一覧の長い名前は幅を押し広げず、全文はツールチップに残す")
	check(detail._body.size.x <= detail._scroll.size.x + 1.0, "個体情報の長い名前でも詳細の表示幅を押し広げない")
	detail.close()
	detail.open_worker(last)
	await _layout()
	last_row = detail._picker._rows[last]
	check(_within(last_row.get_global_rect(), detail._picker._scroll.get_global_rect()), "一覧を再生成しても閲覧中の末尾の個体が見える位置を維持する")

	print("-- 一括チェック・部署絞り込み・配属を取り違えない --")
	detail._picker.select_all()
	await _layout()
	check(detail._picker.selected_list().size() == 30, "全員表示から30人を一括でチェックできる")
	detail._set_filter(GameData.Field.COOK)
	await _layout()
	check(detail._picker._rows.size() > 0 and detail._picker._rows.size() < 30 and detail._picker.selected_list().size() == 30, "部署の絞り込みは表示だけを絞り、画面外の一括チェックを失わない")
	check(detail._worker == last and main.follow_target == W[0], "部署で絞っても閲覧対象と追従先を勝手に切り替えない")
	detail._set_filter(-1)
	detail._move(detail._picker.selected_list(), GameData.Field.GATHERER)
	await _layout()
	var all_moved := true
	for w in W:
		all_moved = all_moved and w.dept == GameData.Field.GATHERER
	check(all_moved and detail._picker._rows.size() == 30 and detail._picker.selected_list().size() == 30, "一括配属ではチェックした30人だけを移し、配属後もチェックと名簿を保持する")
	check(detail._worker == last and detail._picker.focus_worker == last and main.follow_target == W[0], "一括配属で閲覧中の個体・フォーカス・追従先を混同しない")
	last_row = detail._picker._rows[last]
	check(_within(last_row.get_global_rect(), detail._picker._scroll.get_global_rect()), "一括配属による一覧更新後も末尾の閲覧対象へ到達できる")

	print("-- 明示した追従操作だけがゲーム側の選択を変える --")
	last.visible = true
	last.away = false
	detail._update_live()
	var follow: Button = detail._live["follow"]
	check(not follow.disabled, "見えていて拠点にいる個体の明示的な追従操作は使える")
	follow.pressed.emit()
	await _layout()
	var only_last_selected: bool = last.selected
	for w in W:
		if w != last:
			only_last_selected = only_last_selected and not w.selected
	check(main.follow_target == last and only_last_selected and not detail._overlay.visible, "追従ボタンで30人目だけを選択して管理画面を閉じる")
	detail.open_worker(W[0])
	await _layout()
	check(main.follow_target == last and detail._worker == W[0], "別の個体情報を開いても明示操作をするまでは追従先を保持する")
	W[0].away = true
	detail._update_live()
	follow = detail._live["follow"]
	check(follow.disabled, "遠征中の個体には追従を選べない")
	follow.pressed.emit()
	check(main.follow_target == last and detail._overlay.visible, "遠征中はコールバックを直接呼んでも追従先と管理画面を変えない")
	W[0].away = false
	W[0].visible = false
	detail._update_live()
	check(detail._live["follow"].disabled, "外装等で見えていない個体には追従を選べない")
	detail._live["follow"].pressed.emit()
	check(main.follow_target == last and detail._overlay.visible, "非表示の個体はコールバックを直接呼んでも追従先と管理画面を変えない")
	W[0].visible = true
	detail.close()
	check(not detail._overlay.visible and main.ui._button.get_global_rect().is_equal_approx(_hud_rect), "管理の操作を終えると固定サイズの通常HUDへ戻る")

	print("-- 0人の境界でも古い個体を表示しない --")
	# Workerを解放しないまま名簿だけ空にし、validだが所属しない古い閲覧対象も検証する。
	main.follow_target = null
	W.clear()
	main.ui._process(0.0)
	await _layout()
	check(main.ui._button.text.contains("0人") and main.ui._button.get_global_rect().is_equal_approx(_hud_rect) and _control_count(main.ui) == _hud_controls, "0人でも管理入口の人数だけ変わり、寸法とControl数は一定")
	main.ui._button.pressed.emit()
	await _layout()
	check(not detail._overlay.visible or detail._worker == null, "空の名簿から開いても、名簿外の古い個体を閲覧対象にしない")
	if detail._overlay.visible:
		check(detail._picker._rows.is_empty() and not detail._live.has("view"), "0人の管理画面は空の一覧で、古い個体のゲージを残さない")
	detail.close()
