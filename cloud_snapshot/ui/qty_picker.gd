class_name QtyPicker
extends HBoxContainer
## 数量の選び方の部品: [1] [5] [全部] と [－] 数 [＋]。インベントリの運搬・分割、制作の回数で使い回す。
## 値は 1〜max_value。「全部」は max_value。値が変わると changed を出す。

signal changed(value: int)

var value := 1
var max_value := 1
var all_value := 0                # 「全部」が選ぶ数（0 なら max_value）。制作では、いま作れる最大の回数
var _label: Label
var _btns := {}


func _init() -> void:
	add_theme_constant_override("separation", 4)


func setup(quick: Array = [1, 5, -1]) -> QtyPicker:
	for q in quick:
		var qq: int = q
		var b := UIKit.button("全部" if qq < 0 else "%d" % qq, func(): set_value((all_value if all_value > 0 else max_value) if qq < 0 else qq))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(52 if qq < 0 else 40, 30)
		add_child(b)
		_btns[qq] = b
	var minus := UIKit.button("－", func(): set_value(value - 1))
	minus.alignment = HORIZONTAL_ALIGNMENT_CENTER
	minus.custom_minimum_size = Vector2(32, 30)
	add_child(minus)
	_label = UIKit.lbl("1", 18, UIKit.C_TEXT, 44)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	var plus := UIKit.button("＋", func(): set_value(value + 1))
	plus.alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.custom_minimum_size = Vector2(32, 30)
	add_child(plus)
	return self


## 選べる最大の数を決める（値は範囲に収める）。all = 「全部」が選ぶ数（省略なら最大）
func set_max(m: int, all: int = 0) -> void:
	max_value = maxi(1, m)
	all_value = mini(all, max_value)
	set_value(value, false)


func set_value(v: int, emit := true) -> void:
	var nv := clampi(v, 1, max_value)
	var changed_now := nv != value
	value = nv
	if _label != null:
		_label.text = str(value)
	if changed_now and emit:
		changed.emit(value)