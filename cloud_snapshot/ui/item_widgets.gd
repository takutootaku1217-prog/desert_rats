class_name ItemWidgets
extends RefCounted
## インベントリ・制作の画面で使う小さな部品: アイテムの絵・分類の札・印（✓ × 鍵）・状態の札。
## 絵は assets の素材（アイテム = assets/resources、印 = assets/ui/mark_*.png。差し替えられる）。数字や文字より、絵と色で見せる。
## 絵の表示の大きさは、絵のドットが整数pxになる大きさ（アイテム 12 ドット → 24・48・96 px）を使う。

## 制作の状態の色と印（CraftDB.evaluate の state）
const STATE_COLORS := {
	"ok": Color("7be07b"), "short": Color("ffc266"), "blocked": Color("ff9a5a"), "locked": Color("8a90a0"), "done": Color("7fb4f0"), "queued": Color("f0d060"),
}
const STATE_MARKS := {"ok": "ok", "short": "ng", "blocked": "ng", "locked": "lock", "done": "ok", "queued": "ok"}
const C_OK := Color("7be07b")
const C_NG := Color("f0705a")


## アイテムの絵。px = 表示の大きさ（正方形）
static func icon(item: int, px: float = 48.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = ItemDB.tex(item)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	return r


## 印の絵。kind = "ok"（✓）／"ng"（×）／"lock"（鍵）
static func mark(kind: String, px: float = 16.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = GameData.tex("res://assets/ui/mark_%s.png" % kind)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	return r


## 小さな札（分類・入手先など）
static func chip(text: String, color: Color, size: int = 12) -> Label:
	var l := UIKit.lbl(text, size, color.lightened(0.35))
	l.add_theme_stylebox_override("normal", UIKit.box(color.darkened(0.55), color, 2, 3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## 状態の札（色の枠の中に印）。state は STATE_COLORS のキー。作れる／作れないが、色と印で一瞬で分かる
static func state_plate(state: String, px: float = 20.0) -> PanelContainer:
	var c: Color = STATE_COLORS.get(state, Color("8a90a0"))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(c.darkened(0.6), c, 2, 3))
	p.add_child(mark(String(STATE_MARKS.get(state, "ng")), px))
	p.tooltip_text = state_text(state)
	return p


## 状態の名前（ツールチップ・診断用。画面には文字を並べない）
static func state_text(state: String) -> String:
	match state:
		"ok":
			return "作れる"
		"short":
			return "材料が足りない"
		"blocked":
			return "置き場がいっぱい"
		"locked":
			return "まだ作れない（解放待ち）"
		"done":
			return "建設済み"
		"queued":
			return "建設の依頼中"
	return ""


## アイテムの絵の下に敷く色（分類の色）の札の背景を持つ、アイテムの絵の枠
static func icon_frame(item: int, px: float = 48.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color("14171c"), ItemDB.color_of(item).darkened(0.35), 2, 4))
	p.add_child(icon(item, px))
	return p