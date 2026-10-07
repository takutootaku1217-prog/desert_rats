extends SceneTree
## 仲間の警告HUDと簡易確認画面のUI境界診断。
## Godot --headless --path . -s res://tools/test_crew_alerts.gd
## seed=20261007、AI・走行・出来事は停止。30人は診断中だけ追加し、初期人数は変更しない。
## 実際のOSクリックではなく、表示の配置とUIコールバックを検証する。

var fails := 0
var main
var alerts
var W: Array


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
	main.director.active.clear()
	main.target_speed = 0.0
	main.scroll_speed = 0.0
	main.tool_auto = false
	main.set_process(false)
	W = main.workers
	for w in W:
		w.stop_work()
		w.set_process(false)
		_normal(w)
		w.ai._set_state(CharacterAI.State.SEARCH)
	alerts = main.crew_alerts
	alerts.set_process(false)
	_refresh()
	print("  条件: seed=20261007、AI/走行/出来事停止、初期3人から診断限定30人、入力はUIコールバック")
	await _test_thresholds()
	await _test_numbering_and_read_only()
	await _test_life_controls()
	await _test_thirty_workers()
	await _test_removed_references()
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails > 0 else 0)


func _layout() -> void:
	for i in 5:
		await process_frame


func _refresh() -> void:
	alerts._process(1.0)


func _normal(w) -> void:
	w.hp = 100.0
	w.hunger = 100.0
	w.fatigue = 0.0
	w.mental = CrewStatusDB.Mental.NORMAL
	w.away = false
	w.down = false
	w.sleeping = false
	w.resting = false
	w.ai.life_request = ""
	w.ai.eat_wait = 0.0


func _warning(w, stat: String) -> Dictionary:
	for item in alerts.warnings_for(w):
		if item["stat"] == stat:
			return item
	return {}


func _within(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0 \
		and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0


func _textures(node: Node) -> int:
	var n := 0
	if node is TextureRect and node.texture != null:
		n = 1
	for child in node.get_children():
		n += _textures(child)
	return n


func _snapshot(include_pending: bool = true) -> Dictionary:
	var workers: Dictionary = {}
	for w in W:
		var values: Dictionary = {"hp": w.hp, "hunger": w.hunger, "fatigue": w.fatigue,
			"mental": w.mental, "stress": w.stress, "calm": w.calm, "dept": w.dept,
			"level": w.level, "gender": w.gender, "skills": w.skills.duplicate(true),
			"ranks": w.ranks.duplicate(true), "priorities": w.priorities.duplicate(true),
			"tools": w.tools.duplicate(true), "state": w.ai.state, "timer": w.ai.timer,
			"eat_claimed": w.ai._eat_claimed, "bed_index": w.bed_index,
			"position": w.position, "target": w.target, "carrying": w.carrying,
			"selected": w.selected,
			"carry_n": w.carry_n, "carry_bonus": w.carry_bonus.duplicate(true),
			"away": w.away, "down": w.down, "sleeping": w.sleeping, "resting": w.resting}
		if include_pending:
			values["life_request"] = w.ai.life_request
		workers[w.get_instance_id()] = values
	return {"workers": workers, "food_claims": main.food_claims,
		"stock": main.storage.inventory.counts.duplicate(true),
		"workshop": main.processor.stock.counts.duplicate(true),
		"beds": main.base.beds.duplicate(), "repair_reserved": main.base.repair_reserved.duplicate(),
		"refuel_reserved": main.base.refuel_reserved, "parts": main.base.parts.duplicate(true),
		"fuel": main.base.fuel, "orders": main.processor.orders.duplicate(true),
		"incoming": main.processor.incoming.duplicate(true), "current": main.processor.current.duplicate(true),
		"progress": main.processor.progress, "output": main.processor.output.duplicate(true),
		"totals": [main.total_gathered, main.total_hunted, main.total_eaten,
			main.base.total_refuel, main.base.total_repair, main.processor.total_done,
			main.storage.total_butchered]}


func _report_changes(before: Dictionary, after: Dictionary, path: String = "model") -> void:
	for key in before:
		var field := "%s.%s" % [path, str(key)]
		if not after.has(key):
			print("  変化: %s は消失" % field)
		elif before[key] is Dictionary and after[key] is Dictionary:
			_report_changes(before[key], after[key], field)
		elif before[key] != after[key]:
			print("  変化: %s: %s → %s" % [field, str(before[key]), str(after[key])])


func _test_thresholds() -> void:
	print("-- 悪い側の向きと閾値の境界 --")
	var w = W[0]
	for stat in ["hp", "hunger"]:
		for spec in [[25.0, false, false], [24.99, true, false], [15.0, true, false], [14.99, true, true]]:
			_normal(w)
			w.set(stat, spec[0])
			var found: Dictionary = _warning(w, stat)
			check((not found.is_empty()) == bool(spec[1]) and (found.is_empty() or bool(found["strong"]) == bool(spec[2])), "%s=%s の警告/強警告は境界を正しく扱う" % [stat, spec[0]])
	for spec in [[74.99, false, false], [75.0, true, false], [89.99, true, false], [90.0, true, true]]:
		_normal(w)
		w.fatigue = spec[0]
		var found: Dictionary = _warning(w, "fatigue")
		check((not found.is_empty()) == bool(spec[1]) and (found.is_empty() or bool(found["strong"]) == bool(spec[2])), "疲労度=%s は高い側で警告を出す" % spec[0])
	for mental in CrewStatusDB.Mental.values():
		_normal(w)
		w.mental = mental
		var found: Dictionary = _warning(w, "mental")
		check((not found.is_empty()) == (mental >= CrewStatusDB.Mental.BAD) and (found.is_empty() or bool(found["strong"]) == (mental == CrewStatusDB.Mental.LIMIT)), "精神状態%sの警告と強警告" % CrewStatusDB.MENTAL_NAMES[mental])
	_normal(w)
	w.hp = 10.0
	w.hunger = 20.0
	w.fatigue = 90.0
	w.mental = CrewStatusDB.Mental.LIMIT
	check(alerts.warnings_for(w).size() == 4, "複数の悪い状態は1つに丸めず4種類とも保持する")
	_refresh()
	check(alerts._entries.size() == 1, "同じ個体の4警告は1人分のエントリにまとめる")
	_normal(w)
	_refresh()
	var all_hidden := true
	for card in alerts._cards:
		all_hidden = all_hidden and not card.visible
	check(alerts._entries.is_empty() and all_hidden and not alerts._overflow.visible, "全員正常なら上部の警告カードと追加人数ボタンを隠す")


func _test_numbering_and_read_only() -> void:
	print("-- 通常時の採番と、読取専用の表示更新 --")
	var numbers: Array[int] = []
	for w in W:
		numbers.append(alerts.number_of(w))
	check(numbers == [1, 2, 3], "警告が出ていない初期3人にも先にNoを割り当てる")
	W[0].hp = 20.0
	W[1].hunger = 10.0
	W[2].fatigue = 80.0
	W[2].mental = CrewStatusDB.Mental.BAD
	var before: Dictionary = _snapshot()
	_refresh()
	await _layout()
	check(_snapshot() == before, "警告を表示しても個体・優先度・能力・在庫・予約・AI状態・累計を変更しない")
	check(alerts._entries.size() == 3 and alerts._entries[0]["worker"] == W[1] and alerts._entries[0]["urgent"], "強い警告を通常警告より先に示す")
	var first = W[0]
	var second = W[1]
	var third = W[2]
	W.reverse()
	_refresh()
	check(alerts.number_of(first) == 1 and alerts.number_of(second) == 2 and alerts.number_of(third) == 3, "名簿の並べ替えでも個体のNoは変わらない")
	W.reverse()
	var old_dept: int = first.dept
	first.dept = GameData.Field.COOK
	_refresh()
	check(alerts.number_of(first) == 1, "配属を変えてもNoは変わらない")
	first.dept = old_dept
	_normal(first)
	_refresh()
	first.hp = 20.0
	_refresh()
	check(alerts.number_of(first) == 1, "正常化で警告が消えて再び出てもNoは同じ")
	var old_follow = main.follow_target
	var selected: Array = []
	for w in W:
		selected.append(w.selected)
	before = _snapshot()
	alerts.open_worker(third)
	_refresh()
	await _layout()
	var after_selected: Array = []
	for w in W:
		after_selected.append(w.selected)
	check(alerts._overlay.visible and alerts._mode == "brief" and alerts._brief_worker == third, "警告カードから対象の簡易確認を開く")
	check(main.follow_target == old_follow and selected == after_selected and _snapshot() == before, "簡易確認の閲覧・更新だけでは選択・追従・ゲームデータを変えない")
	check(is_equal_approx(alerts._view.gauge("fatigue").ratio, 0.2), "簡易確認の疲労度80は余力20%として表示する")
	alerts._details.pressed.emit()
	await _layout()
	check(main.detail._overlay.visible and main.detail._worker == third and main.follow_target == old_follow and not alerts._overlay.visible, "詳細入口は同じ個体のC管理画面を開き、追従先を変えない")
	main.detail.close()


func _test_life_controls() -> void:
	print("-- 生活の促しは既存AIへの1件の受付だけ --")
	var w = W[0]
	_normal(w)
	w.ai._set_state(CharacterAI.State.SEARCH)
	w.fatigue = 80.0
	w.hunger = 20.0
	main.storage.inventory.counts[GameData.Item.FOOD] = 2
	alerts.open_worker(w)
	_refresh()
	await _layout()
	check(not alerts._rest.disabled and not alerts._eat.disabled, "休憩・食事が必要で利用可能なら促しを使える")
	var before: Dictionary = _snapshot(false)
	alerts._rest.pressed.emit()
	check(w.ai.life_request == "rest" and _snapshot(false) == before, "休憩の受付は保留1件だけを置き、食料・ベッド・状態・予約を変えない")
	alerts._rest.pressed.emit()
	alerts._eat.pressed.emit()
	check(w.ai.life_request == "rest" and _snapshot(false) == before, "連打や別の促しで重複・上書き・先取りを起こさない")
	w.ai.life_request = ""
	_refresh()
	before = _snapshot(false)
	alerts._eat.pressed.emit()
	check(w.ai.life_request == "eat" and _snapshot(false) == before, "食事の受付も保留だけで、食料消費と予約はAIの実行開始まで行わない")
	w.ai.life_request = ""
	_refresh()
	main.storage.inventory.counts.erase(GameData.Item.FOOD)
	before = _snapshot()
	alerts._eat.pressed.emit()
	check(w.ai.life_request.is_empty() and _snapshot() == before, "表示後に食料が尽きた場合もコールバックで再確認して拒否する")
	for state in [CharacterAI.State.REST, CharacterAI.State.REST_HERE]:
		w.ai._set_state(state)
		w.sleeping = state == CharacterAI.State.REST
		w.resting = state == CharacterAI.State.REST_HERE
		_refresh()
		check(_warning(w, "fatigue").size() > 0 and alerts._rest.disabled, "休憩中の疲労警告は回復まで残り、重複した休憩を促せない：%s" % state)
		before = _snapshot()
		alerts._rest.pressed.emit()
		check(_snapshot() == before, "休憩中の直接コールバックでも予約や状態を変えない：%s" % state)
	w.ai._set_state(CharacterAI.State.SEARCH)
	w.sleeping = false
	w.resting = false
	main.storage.inventory.counts[GameData.Item.FOOD] = 1
	for unavailable in ["away", "down"]:
		w.set(unavailable, true)
		if unavailable == "down":
			w.ai._set_state(CharacterAI.State.DOWN)
		_refresh()
		before = _snapshot()
		alerts._rest.pressed.emit()
		alerts._eat.pressed.emit()
		check(_snapshot() == before and w.ai.life_request.is_empty(), "%sでは表示後の変化でも促しを受け付けない" % unavailable)
		w.set(unavailable, false)
		w.ai._set_state(CharacterAI.State.SEARCH)
	_normal(w)
	w.fatigue = 80.0
	w.hunger = 20.0
	alerts.open_worker(w)
	await _layout()
	var old_rest: Button = alerts._rest
	var old_eat: Button = alerts._eat
	var old_details: Button = alerts._details
	var next = W[1]
	_normal(next)
	next.fatigue = 80.0
	next.hunger = 20.0
	alerts.open_worker(next)
	# 旧Buttonはqueue_free実行前の同フレームに押す。新しい閲覧対象へ要求を転送してはいけない。
	before = _snapshot()
	old_rest.pressed.emit()
	old_eat.pressed.emit()
	old_details.pressed.emit()
	check(_snapshot() == before and alerts._overlay.visible and alerts._brief_worker == next and not main.detail._overlay.visible, "個体Aの古い促し・詳細ボタンを個体Bの閲覧中に呼んでも、どちらにも作用しない")
	await _layout()
	alerts._rest.pressed.emit()
	check(next.ai.life_request == "rest" and w.ai.life_request.is_empty(), "切替後の新しい促しボタンは、現在の個体Bだけを対象にする")
	_normal(w)
	_normal(next)
	alerts.close()


func _fixture_worker(index: int) -> Worker:
	var definition: Dictionary = main.WORKER_DEFS[0]
	var profile: Dictionary = definition["profile"].duplicate(true)
	profile["level"] = 1
	profile["dept"] = GameData.Field.GATHERER
	var w := Worker.new()
	w.setup(main, "警告診断の仲間%02d" % index, definition["palette"], definition["prio"], index, profile)
	w.position = Vector2(1800.0 + index * 70.0, GameData.LO_Y)
	W[0].get_parent().add_child(w)
	# _processの自動有効化は_ready前に行われるため、ツリー追加後に止める。
	w.set_process(false)
	W.append(w)
	_normal(w)
	return w


func _test_thirty_workers() -> void:
	print("-- 30人が同時に不調でも上部を覆い尽くさない --")
	for i in range(W.size(), 30):
		_fixture_worker(i + 1)
	for w in W:
		_normal(w)
		w.hp = 10.0
		w.hunger = 10.0
		w.fatigue = 90.0
		w.mental = CrewStatusDB.Mental.LIMIT
	var fixture_stopped := true
	for w in W:
		fixture_stopped = fixture_stopped and not w.is_processing()
	check(fixture_stopped, "診断用に追加した個体を含む30人全員のAI処理が停止している")
	_refresh()
	await _layout()
	check(alerts._entries.size() == 30 and alerts._cards.size() == 3 and alerts._overflow.visible and alerts._overflow.text.contains("27"), "30人の不調は最大3カードと残り27人の入口へまとめる")
	var cards_fit := true
	var textures_present := true
	for card in alerts._cards:
		var area: Rect2 = card.get_global_rect()
		cards_fit = cards_fit and area.size.is_equal_approx(Vector2(112, 44)) and area.end.x <= 558.0 and area.end.y <= 52.0
		textures_present = textures_present and _textures(card) >= 2
	check(cards_fit and alerts._overflow.get_global_rect().end.x <= 558.0, "同時警告でも上部の固定範囲内に収まり、画面中央へ伸びない")
	check(textures_present, "カードには個体の見た目と警告アイコンがあり、文字だけの一覧にならない")
	var before: Dictionary = _snapshot()
	var old_follow = main.follow_target
	alerts._overflow.pressed.emit()
	await _layout()
	check(alerts._overlay.visible and alerts._mode == "list" and alerts._list_rows.size() == 27, "追加人数の入口から上部3人以外の残り27人を確認できる")
	alerts._list_scroll.scroll_vertical = 100000
	await _layout()
	var last = W[29]
	var row: Button = alerts._list_rows[last]
	check(alerts._list_scroll.scroll_vertical > 0 and _within(row.get_global_rect(), alerts._list_scroll.get_global_rect()), "警告一覧の末尾の30人目までスクロールできる")
	var scroll_before: int = alerts._list_scroll.scroll_vertical
	last.fatigue = 89.0
	before = _snapshot()
	_refresh()
	await _layout()
	row = alerts._list_rows[last]
	check(alerts._list_scroll.scroll_vertical == scroll_before and _within(row.get_global_rect(), alerts._list_scroll.get_global_rect()), "症状が変わって一覧を更新しても末尾のスクロール位置を保持する")
	row.pressed.emit()
	await _layout()
	var after: Dictionary = _snapshot()
	var right_target: bool = alerts._brief_worker == last and alerts._mode == "brief"
	var same_follow: bool = main.follow_target == old_follow
	check(right_target and same_follow and after == before, "末尾の行から正しい個体の簡易確認を開き、選択やモデルを変えない")
	if not right_target or not same_follow or after != before:
		print("  詳細: 対象/画面=%s, 追従保持=%s, モデル保持=%s" % [right_target, same_follow, after == before])
		_report_changes(before, after)
	alerts._details.pressed.emit()
	await _layout()
	check(main.detail._worker == last and main.detail._overlay.visible and main.follow_target == old_follow, "30人目の警告から同じ個体の詳細管理へ進める")
	main.detail.close()


func _test_removed_references() -> void:
	print("-- 離脱・解放された参照を押しても別個体へ作用しない --")
	var removed = W[29]
	var old_number: int = alerts.number_of(removed)
	alerts.open_worker(removed)
	await _layout()
	W.erase(removed)
	var before: Dictionary = _snapshot()
	alerts._rest.pressed.emit()
	alerts._eat.pressed.emit()
	check(_snapshot() == before and removed.ai.life_request.is_empty(), "名簿から外れたvalidな個体への古い促しボタンは拒否する")
	alerts._details.pressed.emit()
	check(not main.detail._overlay.visible, "名簿から外れた個体の古い詳細ボタンで管理画面を開かない")
	_refresh()
	check(not alerts._overlay.visible, "閲覧中の個体が名簿から外れたら簡易確認を閉じる")
	var added := _fixture_worker(31)
	added.hp = 10.0
	_refresh()
	check(alerts.number_of(added) > old_number, "同じセッションで離脱したNoを新規加入者へ再利用しない")
	alerts.open_worker(added)
	await _layout()
	W.erase(added)
	added.free()
	_refresh()
	check(not alerts._overlay.visible, "閲覧中のWorkerを解放しても警告更新で落ちずに確認画面を閉じる")
	removed.free()
	alerts.close()
