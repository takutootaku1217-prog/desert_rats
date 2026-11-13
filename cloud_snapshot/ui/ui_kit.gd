class_name UIKit
extends RefCounted
## 管理画面などで共通に使う、ボタン・ラベル・枠の部品。見た目をここに一本化する。

const C_TEXT := Color("ffe9b0")
const C_DIM := Color("9aa3b2")
const C_ACCENT := Color("f2c14e")

## アイコンゲージ（ui/icon_gauge.gd）の色の表。[[割合の上限, 色], ...]（小さい順。割合 ≦ 上限 の最初の色を使う）。
## ここを書き換えるだけで、ゲージの色の設計を変えられる（tools/art_ui.py の確認用の色も同じ値）。
## 積載重量: 増えるほど濃くなる（0〜25% 薄い → 25〜50% 少し濃い → 50〜75% 中間 → 75〜90% 濃い → 90〜100% 非常に濃い）。
const GAUGE_STAGES_LOAD := [
	[0.25, Color("e6dcb4")], [0.50, Color("e3c072")], [0.75, Color("d99a3a")], [0.90, Color("c2691f")], [1.01, Color("9c3512")],
]


## 拠点の耐久（盾）・燃料（ジェリカン）のアイコンゲージの色の表。個体のHP（ハート）と同じ向き（少ないほど危険）。
## 赤 = 「不調」の線（GameData.PART_BAD。これ以下で設備の効果が半分になる）まで、黄 = 半分まで、緑 = それ以上。
const GAUGE_STAGES_BASE := [
	[GameData.PART_BAD / 100.0, Color("e0533d")], [0.5, Color("f0c040")], [1.01, Color("7be07b")],
]
## 危険域: この割合より少ないと、そのアイコンだけが赤く点滅する（個体のHPの危険域と同じ考え方）
const GAUGE_BLINK_BELOW := 0.15

## アイコンゲージの数字の表示（プレイヤー設定。true = アイコンの中に数字、false = アイコンだけ）。仲間・拠点・積載のすべてのアイコンゲージに共通。
## OFF にしても、アイコンだけで状態が分かること。設定の画面ができたら、ここへつなぐ。
static var show_icon_numbers := true


static func box(bg: Color, edge: Color, border: int = 2, margin: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border)
	sb.border_color = edge
	sb.set_corner_radius_all(0)          # ドット絵に合わせて角丸にしない
	sb.anti_aliasing = false
	sb.set_content_margin_all(margin)
	return sb


static func style(b: Button, selected: bool) -> void:
	var edge := C_ACCENT if selected else Color("636b7a")
	b.add_theme_stylebox_override("normal", box(Color("4b5262") if selected else Color("3a3f4a"), edge, 3 if selected else 2))
	b.add_theme_stylebox_override("hover", box(Color("4b5262"), C_ACCENT))
	b.add_theme_stylebox_override("pressed", box(Color("22252b"), C_ACCENT))
	b.add_theme_stylebox_override("disabled", box(Color("25282e"), Color("3a3f4a")))


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", GameData.font())
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color("6b7280"))
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	style(b, false)
	b.pressed.connect(cb)
	return b


static func lbl(text: String, size: int = 15, color: Color = C_TEXT, minw: float = 0.0) -> Label:
	var l := GameData.make_label(text, size, color)
	if minw > 0.0:
		l.custom_minimum_size = Vector2(minw, 0)
	return l


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
