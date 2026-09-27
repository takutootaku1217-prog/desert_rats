class_name IconGauge
extends Control
## アイコン自体がゲージになる表示部品。「アイコンそのものが状態を表す」構造（横長ゲージ＋アイコンの並びではない）。
## 絵はすべてオリジナルのドット絵（tools/art_ui.py が作る。基準の大きさは 16x16 ユニット = ArtSpec.UI_ICON。絵を高精細にしても、画面上の大きさは変わらない）。
##  - 絵は2枚: 枠（assets/ui/<名前>.png。輪郭や縁。中は透明）と、充填してよい範囲（<名前>_mask.png。不透明なドットだけ）。
##    絵を差し替えるだけで、盾・しずく・ハートなど別の形のゲージになる（見た目は後で大きく変えられる）。
##  - 充填は「実際のドットの面積」が基準。範囲のドットを下の行から順に埋め、埋めた数 = 割合 × 範囲のドット数（fill_count）。
##    底が広く上が細い形でも、50% は見た目に半分の量になる。途中の行は、中心から左右へ埋める。
##  - 色は割合で変わる（color_stages。既定は UIKit.GAUGE_STAGES_LOAD。既存の色設計に合わせて差し替えられる）。
##  - 数字は絵の内側（範囲の中心）に出す。数値をゲージの外に出さない。
## 重さ・HP・満腹度など、割合で表せるものに使い回す。値の出どころは呼び出し側で、ここは表示だけ（set_value に渡す）。

var ratio := 0.0                              # 充填率 0〜1（set_value が決める）
var text := ""                                # 絵の内側に出す数字
var pixel := float(GameData.PX)              # 絵のドット1つを画面の何pxで描くか（表示の大きさ ÷ 絵の幅。絵の細かさから自動で決まる）
var display_size := Vector2.ZERO             # 画面上の大きさ（px）= 基準の大きさ（ユニット）× UNIT_PX。絵の細かさに依存しない
var color_stages: Array = UIKit.GAUGE_STAGES_LOAD
var empty_color := Color(0.07, 0.08, 0.10, 0.92)   # 充填していない範囲の色
var dark_empty := false                       # true なら、充填していない範囲を「いまの充填の色の暗い色」にする（どれだけ減ったかが色つきで見える）
var blink := false                            # true なら点滅する（危険域のゲージ用）

var _frame: Texture2D
var _order: Array = []                        # 充填する順（Vector2i のドット座標。下の行から）
var _icon_size := Vector2i(16, 16)
var _text_center := Vector2.ZERO              # 数字を置く位置（ドット座標。範囲の中心）
var _interior: ImageTexture
var _interior_img: Image                      # _interior の元の画像（診断ツールが読む。ヘッドレスではテクスチャから読み戻せない）
var _key := ""
var _t := 0.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP   # ツールチップを出すため


## 絵（assets/ui/<icon_name>.png と <icon_name>_mask.png）を読み込む。size_units = 絵の基準の大きさ（ユニット）。
## 画面上の大きさは size_units × UNIT_PX で決まり、絵のドット数には依存しない（充填は絵のドットの面積が基準なので、細かい絵ほど細かく埋まる）。
func setup(icon_name: String, size_units: Vector2i = ArtSpec.UI_ICON) -> IconGauge:
	_frame = GameData.tex("res://assets/ui/%s.png" % icon_name)
	var mask := _load_image("res://assets/ui/%s_mask.png" % icon_name)
	_icon_size = Vector2i(mask.get_width(), mask.get_height())
	display_size = ArtSpec.px_size(size_units)
	pixel = display_size.x / float(maxi(1, _icon_size.x))
	_order = fill_order(mask)
	_text_center = _center_of(mask)
	custom_minimum_size = display_size
	size = custom_minimum_size
	_refresh()
	return self


## 値を渡す。current / maximum が充填率、label が絵の内側の数字。
func set_value(current: float, maximum: float, label: String = "") -> void:
	ratio = clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	text = label
	_refresh()


## 点滅の切り替え（危険域のゲージ用）
func set_blink(on: bool) -> void:
	blink = on
	set_process(on)


## いま埋めているドット数
func filled_count() -> int:
	return fill_count(ratio, _order.size())


## いまの充填の色（割合の段階で決まる）
func current_color() -> Color:
	return stage_color(color_stages, ratio)


## 充填の順（画面に出す前の確認用）
func fill_dots() -> Array:
	return _order


## いま作っている充填の画像（範囲のドットに、埋めた色／空の色が入っている）。確認用
func interior_image() -> Image:
	return _interior_img


# ---------------------------------------------------------------- 充填の規則（static。診断ツールからも使う）
## 充填する順: 下の行から上へ。1つの行の中では、行の中心から左右へ（水面が中央から広がる見た目）。
static func fill_order(mask: Image) -> Array:
	var order: Array = []
	for y in range(mask.get_height() - 1, -1, -1):
		var xs: Array = []
		for x in mask.get_width():
			if mask.get_pixel(x, y).a > 0.5:
				xs.append(x)
		if xs.is_empty():
			continue
		var cx := (float(xs.min()) + float(xs.max())) / 2.0
		xs.sort_custom(func(a, b):
			var da := absf(float(a) - cx)
			var db := absf(float(b) - cx)
			if da != db:
				return da < db
			return a < b)
		for x in xs:
			order.append(Vector2i(x, y))
	return order


## 割合 r のとき埋めるドット数（実際のドットの面積が基準）。少しでも積んでいれば1ドットは見せ、ちょうど満杯のときだけ全部を埋める。
static func fill_count(r: float, total: int) -> int:
	if total <= 0 or r <= 0.0:
		return 0
	if r >= 1.0:
		return total
	return clampi(roundi(r * float(total)), 1, maxi(1, total - 1))


## 割合 r の色。stages は [[割合の上限, 色], ...]（小さい順）。割合 ≦ 上限 の最初の色。
static func stage_color(stages: Array, r: float) -> Color:
	for s in stages:
		if r <= float(s[0]):
			return s[1]
	return stages[stages.size() - 1][1]


# ---------------------------------------------------------------- 内部
static func _load_image(path: String) -> Image:
	var t := GameData.tex(path)
	var img: Image = t.get_image() if t != null else null
	if img == null or img.is_empty():
		img = Image.new()
		img.load(path)
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## 範囲の外接矩形の中心（ドット座標。ドットの中心ではなく端を基準にする）
static func _center_of(mask: Image) -> Vector2:
	var x0 := mask.get_width()
	var y0 := mask.get_height()
	var x1 := -1
	var y1 := -1
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Vector2(mask.get_width(), mask.get_height()) / 2.0
	return Vector2(float(x0 + x1 + 1) / 2.0, float(y0 + y1 + 1) / 2.0)


func _refresh() -> void:
	var n := filled_count()
	var col := current_color()
	var key := "%d|%s|%s" % [n, col.to_html(), str(dark_empty)]
	if key != _key:                                # 充填の数か色の段階が変わったときだけ、絵を作り直す
		_key = key
		var img := Image.create(_icon_size.x, _icon_size.y, false, Image.FORMAT_RGBA8)
		for i in _order.size():
			var p: Vector2i = _order[i]
			img.set_pixel(p.x, p.y, col if i < n else _empty_of(col))
		_interior_img = img
		_interior = ImageTexture.create_from_image(img)
	queue_redraw()


## 充填していないドットの色
func _empty_of(fill: Color) -> Color:
	if dark_empty:
		return Color(fill.r * 0.28, fill.g * 0.28, fill.b * 0.28, 0.92)
	return empty_color


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if _interior == null or _frame == null:
		return
	var sz := display_size
	var a := 1.0
	if blink:
		a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 8.0))
	draw_texture_rect(_interior, Rect2(Vector2.ZERO, sz), false, Color(1, 1, 1, a))
	draw_texture_rect(_frame, Rect2(Vector2.ZERO, sz), false)
	if text != "":
		var fs := maxi(10, int(display_size.x * 0.24))                 # 数字の大きさは、画面上の表示の大きさに合わせる（絵のドット数に依存しない。48px なら 11・64px なら 15）
		var c := _text_center * pixel
		GameData.draw_text(self, Vector2(c.x, c.y + float(fs) * 0.36), text, fs, Color.WHITE, sz.x, HORIZONTAL_ALIGNMENT_CENTER)
