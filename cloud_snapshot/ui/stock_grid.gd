class_name StockGrid
extends Control
## 倉庫の中身を、アイテムのアイコンと個数で並べる表示（文字の一覧の代わり）。個数はアイコンの右下の内側。
## アイコンは assets/resources のアイテムの絵（差し替えられる素材）。倉庫のデータは読むだけ。
##  - 枠がいっぱい（満）: 個数が赤く、アイコンに赤い枠。8割を超えたら個数が橙。
##  - 空腹の仲間がいるとき: 食料のアイコンが赤く点滅する。
##  - マウスを載せると、名前・個数・（満）が出る。
## 数字の見せ方は UIKit.show_icon_numbers（false ならアイコンだけ）。

const CELL := Vector2(28.0, 26.0)
const ICON_S := 0.5                       # アイコンの倍率（基準の大きさ×0.5 = 24px。絵のドットが整数pxになる）
const C_NUM := Color("fff7dc")
const C_NEAR := Color("ffb347")
const C_FULL := Color("ff6a55")

var _rows: Array = []                     # 行ごとのアイテムの並び
var _cells: Array = []                    # [{item, n, quota, full, near, alert, pos}]
var _hungry := false
var _t := 0.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP


## item_rows = 行ごとのアイテムの並び（例: [[食料, 燃料], [生肉, 皮]]）。1行に置ける数の最大で、幅が決まる。
func setup(item_rows: Array) -> StockGrid:
	_rows = item_rows
	var widest := 0
	for r in _rows:
		widest = maxi(widest, r.size())
	custom_minimum_size = Vector2(CELL.x * float(widest), CELL.y * float(_rows.size()))
	size = custom_minimum_size
	return self


## 倉庫の中身と、空腹の仲間がいるかを反映する
func update_from(st, hungry: bool) -> void:
	_hungry = hungry
	_cells.clear()
	for y in _rows.size():
		for x in _rows[y].size():
			var it: int = _rows[y][x]
			var n: int = st.count_of(it)
			var q: int = st.quota_of(it) if CargoDB.bay_of(it) >= 0 else 0
			_cells.append({"item": it, "n": n, "quota": q, "full": st.is_full(it), "near": q > 0 and float(n) >= 0.8 * float(q),
					"pos": Vector2(CELL.x * float(x), CELL.y * float(y))})
	set_process(hungry)
	queue_redraw()


## 表示している内容の文字（診断ツール・説明用。画面には出さない）。例: 「食料 8 ／ 燃料 2 ／ … 肉0 皮0 木8満」
func summary() -> String:
	var parts: Array = []
	for c in _cells:
		var name: String = GameData.ITEM_NAMES[c["item"]]
		parts.append("%s %d%s" % [name, c["n"], "満" if c["full"] else ""])
	return " ／ ".join(PackedStringArray(parts))


## 個数を返す（診断ツールが、表示と倉庫の個数が合っているかを見る）
func shown_count(item: int) -> int:
	for c in _cells:
		if c["item"] == item:
			return int(c["n"])
	return -1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var isz := ArtSpec.px_size(ArtSpec.ITEM) * ICON_S
	for c in _cells:
		var pos: Vector2 = c["pos"]
		var rect := Rect2(pos + Vector2(1.0, 1.0), isz)
		var tint := Color.WHITE
		if _hungry and int(c["item"]) == GameData.Item.FOOD:
			var k := 0.5 + 0.5 * sin(_t * 7.0)
			tint = Color(1.0, 0.55 + 0.35 * k, 0.5 + 0.35 * k)         # 食料が足りない: 赤く点滅
		draw_texture_rect(GameData.item_tex(int(c["item"])), rect, false, tint)
		if c["full"]:
			draw_rect(rect.grow(1.0), C_FULL, false, 2.0)                 # いっぱい（満）
		if UIKit.show_icon_numbers:
			var col: Color = C_FULL if c["full"] else (C_NEAR if c["near"] else C_NUM)
			var f := GameData.font()
			var txt := str(c["n"])
			var at := Vector2(pos.x, pos.y + isz.y)
			draw_string_outline(f, at, txt, HORIZONTAL_ALIGNMENT_RIGHT, isz.x + 2.0, 11, 4, Color(0.1, 0.06, 0.04, 0.9))
			draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_RIGHT, isz.x + 2.0, 11, col)


func _get_tooltip(at_position: Vector2) -> String:
	for c in _cells:
		var pos: Vector2 = c["pos"]
		if Rect2(pos, CELL).has_point(at_position):
			var s := "%s %d" % [GameData.ITEM_NAMES[c["item"]], c["n"]]
			if int(c["quota"]) > 0:
				s += " / %d" % c["quota"]
			if c["full"]:
				s += "（いっぱい）"
			if _hungry and int(c["item"]) == GameData.Item.FOOD:
				s += "\n空腹の仲間がいる"
			return s
	return ""
