class_name CrewPicker
extends VBoxContainer
## 仲間の一覧（チェックで複数選択できる）。管理画面のほか、遠征メンバーの選出などでも使い回す部品。
##  - 名前を押す → focused（詳細を見る対象）
##  - チェックを付ける → 選択（まとめて操作する対象）
##  - 「全選択」「解除」「S以上」でまとめて選べる

signal focused(worker)
signal selection_changed

var source: Callable                 # 一覧に出す仲間の配列を返す関数
var number_source: Callable          # 番号表示が必要な管理画面だけが指定する（Noの保存は通知HUDが担当）
var selected := {}                   # Worker -> true
var focus_worker = null

var _box: VBoxContainer
var _count: Label
var _scroll: ScrollContainer
var _rows := {}                      # Worker -> Button
var _refresh_revision := 0
const S_RANK := 5                    # S 以上


func _init() -> void:
	custom_minimum_size = Vector2(290, 0)
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	add_child(head)
	var t := UIKit.lbl("メンバー", 15, UIKit.C_DIM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_count = UIKit.lbl("", 14, UIKit.C_ACCENT)
	head.add_child(_count)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for spec in [["全選択", select_all], ["解除", clear_selection], ["S以上", select_s_up]]:
		var b := UIKit.button(spec[0], spec[1])
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(88, 30)
		bar.add_child(b)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(282, 0)
	_box.add_theme_constant_override("separation", 4)
	_scroll.add_child(_box)


func refresh() -> void:
	for w in selected.keys():
		if not is_instance_valid(w):
			selected.erase(w)
	UIKit.clear(_box)
	_rows.clear()
	var list: Array = source.call() if source.is_valid() else []
	if list.is_empty():
		_box.add_child(UIKit.lbl("所属している仲間はいません", 14, UIKit.C_DIM))
	for w in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_box.add_child(row)
		var cb := CheckBox.new()
		cb.button_pressed = selected.has(w)
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size = Vector2(34, 40)
		cb.toggled.connect(func(on): _set_selected(w, on))
		row.add_child(cb)
		var number: int = int(number_source.call(w)) if number_source.is_valid() else 0
		var prefix: String = "No.%02d " % number if number > 0 else ""
		var b := UIKit.button("%s%s  Lv%d  %s" % [prefix, w.char_name, w.level, w.rank_letter()], func(): set_focus(w))
		b.custom_minimum_size = Vector2(236, 40)
		b.clip_text = true                   # 長い個体名でも、一覧や管理画面全体の最小幅を広げない
		b.tooltip_text = b.text              # 一覧で省略される名前は、詳細とツールチップで全文を読める
		UIKit.style(b, w == focus_worker)
		row.add_child(b)
		_rows[w] = b
	_update_count()
	_refresh_revision += 1
	call_deferred("_ensure_focus_after_layout", _refresh_revision)


func set_focus(w) -> void:
	focus_worker = w
	for k in _rows:
		UIKit.style(_rows[k], k == w)
	_ensure_focus_visible()
	focused.emit(w)


## 行の再生成や絞り込みで変わる最小サイズ・スクロール範囲の配置が済んでから合わせる。
func _ensure_focus_after_layout(revision: int, remaining_frames: int = 2) -> void:
	if revision != _refresh_revision or not is_inside_tree():
		return
	if remaining_frames > 0:
		# 名前付きメソッドへの接続は、この一覧が解放されたとき自動で解除される。
		get_tree().process_frame.connect(_ensure_focus_after_layout.bind(revision, remaining_frames - 1), CONNECT_ONE_SHOT)
		return
	_ensure_focus_visible()


## 開き直したときも、閲覧中の仲間の行がスクロール範囲内に見えるようにする。
func _ensure_focus_visible() -> void:
	if not is_instance_valid(focus_worker) or not _rows.has(focus_worker) or not _scroll.is_visible_in_tree():
		return
	_scroll.ensure_control_visible(_rows[focus_worker])


func _visible_workers() -> Array:
	return _rows.keys()


func _set_selected(w, on: bool) -> void:
	if on:
		selected[w] = true
	else:
		selected.erase(w)
	_update_count()
	selection_changed.emit()


func select_all() -> void:
	for w in _visible_workers():
		selected[w] = true
	refresh()
	selection_changed.emit()


func select_s_up() -> void:
	for w in _visible_workers():
		if w.best_rank() >= S_RANK:
			selected[w] = true
	refresh()
	selection_changed.emit()


func clear_selection() -> void:
	selected.clear()
	refresh()
	selection_changed.emit()


func selected_list() -> Array:
	var l: Array = []
	for w in selected.keys():
		if is_instance_valid(w):
			l.append(w)
	return l


func _update_count() -> void:
	_count.text = "選択 %d人" % selected.size() if selected.size() > 0 else ""
