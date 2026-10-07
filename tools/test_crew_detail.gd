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


## text に文字があっても高さ0なら描画されない。配置後の実寸を別に確かめる。
func _text_has_height(needle: String) -> bool:
	for l in _labels(detail._body):
		if l.text.contains(needle) and l.is_visible_in_tree() and l.size.y > 0.0:
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
	check(_text_has_height("プロフィール"), "プロフィール見出しの文字に、表示できる実高さがある")
	check(_text_has_height(W[0].char_name), "プロフィールの個体名に、表示できる実高さがある")
	check(_text_has_height("武器・防具：未実装"), "武器・防具の未実装案内に、表示できる実高さがある")
	check(main.ui.layer == 10 and detail.layer == 27 and detail._overlay.get_parent() == detail, "固定の管理入口は通常HUD、管理画面は他の管理画面より上の別レイヤー")
	check(main.ui._button.text == "仲間 %d人 (C)" % W.size() and main.ui._button.custom_minimum_size == Vector2(280, 36), "上部HUDは仲間人数を示す固定サイズの管理入口")
	check(detail._tab_btns.size() == 2 and detail._tab_btns[0].text == "個体情報" and detail._tab_btns[1].text == "部署", "個体情報と部署の2タブ")
	for text in ["個体ランク", "得意分野", "分野ランク", "スキル", "採取道具", "仕事の効率", "仕事の優先度"]:
		check(_has_text(text), "個体情報に%sがある" % text)
	check(detail._live["view"]._gauges.size() == 3 and not detail._live["view"]._gauges.has("stamina"), "HP・満腹度・疲労度と精神状態を表示し、スタミナはない")
	check(_has_text("武器・防具：未実装"), "未実装の装備は機能があるように表示しない")
	check(_has_text("休憩・食事は自動で行います。必要なら早めに促せます。"), "生活行動は自動で、促しは補助だと案内する")
	check(not detail._live.has("prio_%d" % GameData.Job.REST), "個体情報の仕事の星に休憩を含めない")
	check(not ("_cards" in main.ui) and main.ui.has_signal("management_requested") and not main.ui.has_signal("worker_selected"), "上部HUDは個体カードや個体選択を持たず、管理画面への入口にする")
	_test_hidden_departments()
	_test_life_controls()
	_test_tool_controls()
	_test_policy_entry()

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
	detail.close()
	main.ui._button.pressed.emit()
	check(detail._overlay.visible and detail._worker == W[0] and main.follow_target == W[0], "固定HUDの管理要求で現在選択中の個体を開き、追従先は変えない")
	detail._picker.set_focus(W[1])
	check(detail._worker == W[1] and main.follow_target == W[0] and W[0].selected, "別の個体を閲覧しても、明示的な追従操作までは世界の選択を保持する")
	var follow: Button = detail._live["follow"]
	check(not follow.disabled, "拠点にいて表示されている個体は、明示的に追従できる")
	follow.pressed.emit()
	check(not detail._overlay.visible and main.follow_target == W[1] and W[1].selected and not W[0].selected, "追従ボタンはmain._select経由で世界の選択を切り替え、管理画面を閉じる")
	detail.open_worker(W[2])
	W[2].away = true
	detail._update_live()
	check(detail._live["follow"].disabled and not detail._live["follow"].tooltip_text.is_empty(), "遠征中の仲間を閲覧できても、追従は無効にして理由を示す")
	detail._live["follow"].pressed.emit()
	check(main.follow_target == W[1] and detail._overlay.visible, "遠征中への古い追従イベントでも、選択や画面を変更しない")
	W[2].away = false
	W[2].visible = false
	detail._update_live()
	check(detail._live["follow"].disabled, "外装等で絵が見えない仲間への追従は無効にする")
	detail._live["follow"].pressed.emit()
	check(main.follow_target == W[1] and detail._overlay.visible, "見えない個体への古い追従イベントでも、選択や画面を変更しない")
	W[2].visible = true
	W[2].away = false
	detail._update_live()
	check(not detail._live["follow"].disabled, "個体が拠点で再表示されれば追従ボタンも有効へ戻る")
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
	var wrapped_name_height := false
	for l in _labels(detail._body):
		if l.text == W[2].char_name:
			wrapped_name = l.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and l.get_line_count() > 1
			var single_line_height: float = l.get_theme_font("font").get_height(l.get_theme_font_size("font_size"))
			wrapped_name_height = l.is_visible_in_tree() and l.size.y > single_line_height and l.size.y + 1.0 >= l.get_minimum_size().y
	check(wrapped_name, "長い個体名が折り返される")
	check(wrapped_name_height, "長い個体名は複数行の実高さを持ち、必要な表示高さを確保する")
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
	check(detail._scroll.scroll_vertical > 0 and end.position.y >= area.position.y - 1.0 and end.end.y <= area.end.y + 1.0, "スクロールすると末尾の個体情報まで到達する")

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
	var target_dept: int = GameData.Field.COOK if focused_dept != GameData.Field.COOK else GameData.Field.COMBAT
	detail._move(detail._picker.selected_list(), target_dept)
	check(W[0].dept == target_dept and W[1].dept == target_dept and focused.dept == focused_dept, "まとめて配属はチェックした2人だけ変更し、閲覧中の個体は変えない")
	check(detail._picker.selected_list().size() == 2 and detail._members(target_dept).has(W[0]) and detail._members(target_dept).has(W[1]), "一括選択と配属後の部署一覧を保持する")
	detail._set_tab(1)
	check(_has_text("部署Lv") and _has_text("解放"), "部署タブに既存の部署Lv・解放情報が残る")
	detail._picker.set_focus(W[0])
	check(detail._tab == 0 and detail._worker == W[0] and detail._live.has("view"), "部署タブからメンバーを選ぶと、その個体情報を表示する")


func _test_life_controls() -> void:
	print("-- 個体への促しはAIへ伝え、選択や仕事を直接変更しない --")
	var w = W[1]
	# 診断用の状態だけを用意する。UIコールバックはrequest_life_actionを呼ぶのみ。
	w.stop_work()
	w.ai._set_state(CharacterAI.State.SEARCH)
	w.ai.life_request = ""
	w.ai.eat_wait = 0.0
	w.hp = CrewStatusDB.MAX_HP
	w.fatigue = 30.0
	w.hunger = 50.0
	w.away = false
	w.down = false
	W[0].ai.life_request = ""
	main._select(W[0])
	detail._picker.set_focus(w)
	var priorities: Dictionary = w.priorities.duplicate()
	var old_state: int = w.ai.state
	var food_before: int = main.storage.count_of(GameData.Item.FOOD)
	var claims_before: int = main.food_claims
	var rest_button: Button = detail._live["life_rest"]
	check(not rest_button.disabled, "回復の余地がある仲間へ早めに休憩を促せる")
	rest_button.pressed.emit()
	check(w.ai.life_request == "rest" and W[0].ai.life_request.is_empty(), "休憩の促しは追従中の仲間でなく、表示中の仲間へ届く")
	check(main.follow_target == W[0] and W[0].selected and detail._worker == w and w.priorities == priorities, "促しで追従・選択・仕事の優先度を変えない")
	check(w.ai.state == old_state and main.food_claims == claims_before and main.storage.count_of(GameData.Item.FOOD) == food_before, "促しの受理時に作業状態・予約・食料を変更しない")
	check(rest_button.disabled and not rest_button.tooltip_text.is_empty() and detail._live["life_pending"].visible and detail._live["life_pending"].text.contains("休憩を促しています"), "重複要求を無効にし、保留中の促しと理由を表示する")
	rest_button.pressed.emit()       # 古いUIイベントが到着した場合も、APIが重複を拒否する。
	check(w.ai.life_request == "rest" and main.food_claims == claims_before, "重複イベントでも要求や予約を増やさない")

	w.ai.life_request = ""
	w.fatigue = 0.0
	w.hunger = CrewStatusDB.MAX_HUNGER
	detail._update_live()
	check(detail._live["life_rest"].disabled and not detail._live["life_rest"].tooltip_text.is_empty(), "回復が不要なら休憩を促せず、理由を表示する")
	check(detail._live["life_eat"].disabled and not detail._live["life_eat"].tooltip_text.is_empty(), "満腹なら食事を促せず、理由を表示する")
	check(not detail._live["life_pending"].visible, "要求がなくなれば保留中の表示を消す")
	w.hunger = 50.0
	var reserved_before: int = main.food_claims
	main.food_claims = main.storage.count_of(GameData.Item.FOOD)
	detail._update_live()
	check(detail._live["life_eat"].disabled and not detail._live["life_eat"].tooltip_text.is_empty(), "食べられる食料がなければ食事を促せず、理由を表示する")
	main.food_claims = reserved_before
	detail._update_live()
	var eat_button: Button = detail._live["life_eat"]
	check(not eat_button.disabled, "食料が使えるようになれば食事ボタンもライブ更新で有効になる")
	eat_button.pressed.emit()
	check(w.ai.life_request == "eat" and main.follow_target == W[0] and w.priorities == priorities, "食事の促しも表示中の個体への要求だけを変える")
	check(eat_button.disabled and detail._live["life_pending"].text.contains("食事を促しています"), "食事の促しも重複を防ぎ、保留内容を表示する")
	w.ai.life_request = ""
	main._select(W[0])


func _buttons(node: Node) -> Array[Button]:
	var list: Array[Button] = []
	if node is Button:
		list.append(node)
	for child in node.get_children():
		list.append_array(_buttons(child))
	return list


func _test_hidden_departments() -> void:
	print("-- 開発部署だけを隠し、個体と能力を保持する --")
	var depts: Array = W.map(func(w): return w.dept)
	var points: int = GameData.field_points(W, GameData.Field.DEV)
	check(GameData.Field.values().has(GameData.Field.DEV) and not GameData.visible_departments().has(GameData.Field.DEV), "開発の定義を残し、表示・配属先から外す")
	check(not detail._dept_btns.has(GameData.Field.DEV) and detail._dept_btns.size() == GameData.visible_departments().size() + 1, "左の部署一覧に開発部署を表示しない")
	check(detail._members(-1).size() == W.size(), "非表示部署の所属者も全員一覧から消えない")
	var hidden = null
	for w in W:
		if w.dept == GameData.Field.DEV:
			hidden = w
	check(hidden != null, "既存の開発所属個体を確認できる")
	if hidden != null:
		detail.open_worker(hidden)
		check(not detail._live.status.text.contains("配属: " + GameData.FIELD_NAMES[GameData.Field.DEV]), "個体の行動状態に非表示の開発部署名を出さない")
		check(_has_text("開発者") and _has_text("分野ランク"), "開発の個体能力ランクは消さない")
		for button in _buttons(detail._body):
			check(button.text != GameData.FIELD_NAMES[GameData.Field.DEV], "配属先・一括配属先に開発を表示しない")
		var rank: Dictionary = hidden.ranks.duplicate()
		detail._move([W[0]], GameData.Field.DEV)
		check(W.map(func(w): return w.dept) == depts and hidden.ranks == rank, "非表示部署への古い操作でも、配属・能力を変更しない")
	detail._set_filter(GameData.Field.DEV)
	detail._set_tab(1)
	check(detail._filter == -1 and not _has_text("開発者"), "非表示部署フィルタを全員へ戻し、部署タブにも開発を出さない")
	check(GameData.field_points(W, GameData.Field.DEV) == points, "表示を隠しても加工・修理に使う部署計算を変えない")
	detail.open_worker(W[0])


func _test_tool_controls() -> void:
	print("-- 個体情報の道具操作と、在庫のライブ更新 --")
	var w = W[1]
	w.away = false
	w.down = false
	w.tools.clear()
	for item in GameData.TOOL_ITEMS:
		main.storage.inventory.counts[item] = 0
	main.storage.add_item(GameData.Item.HAMMER, 1)
	main.storage.add_item(GameData.Item.PICKAXE, 1)
	main._select(W[0])
	detail.open_worker(w)
	main.tool_auto = true
	detail._update_live()
	check(detail._live.tool_auto.text.contains("全員共通") and detail._live.tool_equip_mine.disabled and detail._live.tool_select_mine.disabled, "自動割当の範囲を明示し、ONでは手動装備を無効にする")
	var stock_before: int = main.storage.count_of(GameData.Item.HAMMER)
	detail._live.tool_equip_mine.pressed.emit()
	check(w.tools.is_empty() and main.storage.count_of(GameData.Item.HAMMER) == stock_before, "古い装備イベントでも自動ON中は在庫・装備を変更しない")
	detail._live.tool_auto.pressed.emit()
	check(not main.tool_auto and not detail._live.tool_select_mine.disabled, "既存の全員共通自動設定を明示的にOFFへ切り替えられる")
	var choices: OptionButton = detail._live.tool_select_mine
	choices.select(choices.get_item_index(GameData.Item.HAMMER))
	detail._update_live()
	var priorities: Dictionary = w.priorities.duplicate()
	var other_tools: Dictionary = W[0].tools.duplicate()
	var requested: String = w.ai.life_request
	detail._live.tool_equip_mine.pressed.emit()
	check(w.tools.get("mine", -1) == GameData.Item.HAMMER and main.storage.count_of(GameData.Item.HAMMER) == 0, "表示中の個体へ倉庫のハンマー1個を持たせる")
	check(W[0].tools == other_tools and main.follow_target == W[0] and W[0].selected and w.priorities == priorities and w.ai.life_request == requested, "装備で他個体・追従先・仕事・生活の促しを変更しない")
	check(detail._live.tool_equip_mine.disabled and detail._live.tool_select_mine.get_item_text(choices.get_item_index(GameData.Item.HAMMER)).contains("装備中"), "同じ装備の重複取得を防ぎ、現在装備と在庫を更新する")
	choices.select(choices.get_item_index(GameData.Item.PICKAXE))
	detail._update_live()
	check(not detail._live.tool_equip_mine.disabled, "在庫のある上位道具を選べる")
	main.storage.take_item(GameData.Item.PICKAXE)
	detail._update_live()
	check(detail._live.tool_equip_mine.disabled and not detail._live.tool_equip_mine.tooltip_text.is_empty(), "他の操作で選択候補の在庫が消えたら、装備を無効にする")
	detail._live.tool_equip_mine.pressed.emit()
	check(w.tools["mine"] == GameData.Item.HAMMER and main.storage.count_of(GameData.Item.HAMMER) == 0, "古い装備ボタンでも在庫不足なら既存装備を失わない")
	main.storage.add_item(GameData.Item.PICKAXE, 1)
	detail._update_live()
	check(choices.get_selected_id() == GameData.Item.PICKAXE and not detail._live.tool_equip_mine.disabled, "候補とスクロールを再構築せず、在庫補充で装備ボタンを有効へ戻す")
	detail._live.tool_equip_mine.pressed.emit()
	check(w.tools["mine"] == GameData.Item.PICKAXE and main.storage.count_of(GameData.Item.PICKAXE) == 0 and main.storage.count_of(GameData.Item.HAMMER) == 1, "道具を交換すると旧道具は倉庫へ戻り、数を保存する")
	detail._live.tool_unequip_mine.pressed.emit()
	check(not w.tools.has("mine") and main.storage.count_of(GameData.Item.PICKAXE) == 1, "外す操作で倉庫へ戻し、素手の表示へ更新する")
	w.away = true
	detail._update_live()
	check(detail._live.tool_equip_mine.disabled, "遠征中の個体は閲覧でき、道具の変更は促せない")
	w.away = false
	w.down = true
	detail._update_live()
	check(detail._live.tool_equip_mine.disabled, "戦闘不能中は道具の変更を受け付けない")
	w.down = false
	detail._update_live()
	detail.open_worker(W[0])


func _test_policy_entry() -> void:
	print("-- 運営の方針から、指定個体の管理へ移る --")
	main._select(W[0])
	detail.close()
	detail._set_filter(GameData.Field.GATHERER)
	main.policy._page = 2
	main.policy._overlay.visible = true
	main.policy._rebuild()
	var entries: Array[Button] = []
	for button in _buttons(main.policy._body):
		if button.text == "個体情報で管理":
			entries.append(button)
		check(button.text != "外す", "方針ページに個体の装備解除操作を重複させない")
	check(entries.size() == W.size(), "各個体の道具説明から個体情報へ移れる")
	if entries.size() > 1:
		entries[1].pressed.emit()
		check(detail._overlay.visible and detail._worker == W[1] and detail._tab == 0 and detail._filter == -1, "部署フィルタ外の指定個体も、個体タブで確実に表示する")
		check(not main.policy._overlay.visible and main.follow_target == W[0] and W[0].selected, "旧画面を閉じ、表示中個体だけ変えて世界の選択・追従先を保持する")
	detail.open_worker(W[0])
