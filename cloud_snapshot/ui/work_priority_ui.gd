class_name WorkPriorityUI
extends CanvasLayer
## 通常HUDの仲間管理入口。人数が増えても、画面に占める幅と高さは変えない。
## 個体の状態・作業優先度は、Cキーでも開ける仲間の管理画面で確認・操作する。

signal management_requested

var workers: Array = []
var _button: Button
var _last_count := -1


func build(p_workers: Array) -> void:
	workers = p_workers
	layer = 10
	if _button == null:
		_button = UIKit.button("", func(): management_requested.emit())
		_button.position = Vector2(10, 8)
		_button.custom_minimum_size = Vector2(144, 44)
		_button.size = Vector2(144, 44)
		_button.clip_text = true
		_button.add_theme_font_size_override("font_size", 14)
		add_child(_button)
	_update_count()


func _process(_delta: float) -> void:
	_update_count()


func _update_count() -> void:
	var count := workers.size()
	if _button == null or count == _last_count:
		return
	_last_count = count
	_button.text = "仲間 %d人 (C)" % count
	_button.tooltip_text = "仲間 %d人の管理を開く (C)\n状態・装備・仕事の優先度を確認できます。" % count
