class_name CrewPicker
extends VBoxContainer
## 仲間の一覧（チェックで複数選択できる）。管理画面のほか、遠征メンバーの選出などでも使い回す部品。
##  - 名前を押す → focused（詳細を見る対象）
##  - チェックを付ける → 選択（まとめて操作する対象）
##  - 「全選択」「解除」「S以上」でまとめて選べる

signal focused(worker)
signal selection_changed

var source: Callable                 # 一覧に出す仲間の配列を返す関数
var selected := {}                   # Worker -> true
var focus_worker = null

var _box: VBoxContainer
var _count: Label
var _rows := {}                      # Worker -> Button
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
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(282, 0)
	_box.add_theme_constant_override("separation", 4)
	sc.add_child(_box)


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
		var b := UIKit.button("%s  Lv%d  %s" % [w.char_name, w.level, w.rank_letter()], func(): set_focus(w))
		b.custom_minimum_size = Vector2(236, 40)
		UIKit.style(b, w == focus_worker)
		row.add_child(b)
		_rows[w] = b
	_update_count()


func set_focus(w) -> void:
	focus_worker = w
	for k in _rows:
		UIKit.style(_rows[k], k == w)
	focused.emit(w)


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
