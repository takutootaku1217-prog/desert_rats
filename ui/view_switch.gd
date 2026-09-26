class_name ViewSwitchUI
extends CanvasLayer
## 外装 ⇄ 内装の切り替え（右のボタン列の上の [外装 (O)] [内装 (I)]。Oキー・Iキー）。UIは増やさず、いま見ている側が光る。
## 中身は scripts/base_view.gd。ここはボタンとキーだけ（ゲームの状態には触れない）。見た目は検証用で、後で変える前提。

var game
var _b_ext: Button
var _b_int: Button


func _ready() -> void:
	layer = 12                                        # 右のボタンは低い層（ほかの画面を開いたとき、その下に隠れる）
	_b_ext = UIKit.button("外装 (O)", func(): game.base_view.set_mode(BaseView.Mode.EXTERIOR))
	_b_int = UIKit.button("内装 (I)", func(): game.base_view.set_mode(BaseView.Mode.INTERIOR))
	for i in 2:
		var b: Button = [_b_ext, _b_int][i]
		b.position = Vector2(1000 + i * 140, 208)
		b.custom_minimum_size = Vector2(132, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(b)
	_refresh(BaseView.START_MODE)
	if game != null and game.base_view != null:
		game.base_view.changed.connect(_refresh)


## いま見ている側を光らせる
func _refresh(m: int) -> void:
	UIKit.style(_b_ext, m == BaseView.Mode.EXTERIOR)
	UIKit.style(_b_int, m == BaseView.Mode.INTERIOR)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			game.base_view.set_mode(BaseView.Mode.EXTERIOR)
		elif event.keycode == KEY_I:
			game.base_view.set_mode(BaseView.Mode.INTERIOR)
