class_name CrewStatusView
extends HBoxContainer
## 仲間1人のステータス表示: HP・スタミナ・満腹度・疲労度の「アイコン自体がゲージ」（ui/icon_gauge.gd）＋ 精神状態の顔。
## 表示だけを担当し、Worker のデータを読むだけ（update_from に渡す）。ゲームの処理は変えない。
## 上部の仲間カード（小さいアイコン）と、仲間の管理画面（大きいアイコン）で同じ部品を使い回す。アイコンの大きさは size_units（ユニット）。
##  - 絵は assets/ui/<名前>.png（枠）と <名前>_mask.png（充填範囲）。tools/art_ui.py が作る。差し替えるだけで形を変えられる。
##  - 色・点滅の基準・精神状態の色は data/crew_status.gd（CrewStatusDB）。危険域（値が悪い側の線を越えた）では、そのアイコンだけが赤く点滅する。
##  - 疲労度は「余力（100 − 疲労度）」で表す: 疲れるほどアイコンの中身が減る（ほかのステータスと同じ向き）。数字も余力。
##  - 数字はアイコンの下に出す。数値の表示ON/OFF は show_numbers（プレイヤー設定。OFF でもアイコンだけで状態が分かる）。

## 数値の表示（true = アイコン＋数字、false = アイコンのみ）。設定画面ができたら、そこへつなぐ
static var show_numbers := true

var _gauges := {}                     # ステータス名 -> IconGauge
var _labels := {}                     # ステータス名 -> 数字のラベル
var _face: TextureRect
var _face_label: Label
var _faces: Array = []                # 精神状態ごとの顔の絵
var _icon_px := 32.0
var _t := 0.0
var _limit := false                   # 精神状態が限界（顔が点滅する）


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## 部品を作る。size_units = アイコン1つの基準の大きさ（ユニット。1ユニット = UNIT_PX）。font_size = 数字・名前の文字の大きさ。
func setup(size_units: Vector2i = Vector2i(8, 8), font_size: int = 12) -> CrewStatusView:
	add_theme_constant_override("separation", 6)
	_icon_px = ArtSpec.px_size(size_units).x
	for stat in CrewStatusDB.STATS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		add_child(col)
		var g := IconGauge.new().setup(String(CrewStatusDB.ICON_FILES[stat]), size_units)
		g.color_stages = CrewStatusDB.GAUGE_STAGES[stat]
		g.dark_empty = true                                           # 減った部分は、いまの色の暗い色（どれだけ減ったかが見える）
		col.add_child(g)
		var l := UIKit.lbl("", font_size, UIKit.C_TEXT, _icon_px)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		_gauges[stat] = g
		_labels[stat] = l
	# 精神状態: 顔のアイコン（色で状態が分かる）＋ 名前
	for f in CrewStatusDB.MENTAL_ICON_FILES:
		_faces.append(GameData.tex("res://assets/ui/%s.png" % f))
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", 0)
	add_child(fcol)
	_face = TextureRect.new()
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_face.custom_minimum_size = ArtSpec.px_size(size_units)
	_face.mouse_filter = Control.MOUSE_FILTER_STOP
	fcol.add_child(_face)
	_face_label = UIKit.lbl("", font_size, UIKit.C_TEXT, _icon_px)
	_face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fcol.add_child(_face_label)
	return self


## Worker の値を表示に反映する（毎フレーム呼んでよい。アイコンは、充填の数か色が変わったときだけ作り直す）
func update_from(w) -> void:
	for stat in CrewStatusDB.STATS:
		var v: float = CrewStatus.gauge_value(w, stat)
		var g: IconGauge = _gauges[stat]
		g.set_value(v, CrewStatusDB.max_of(stat))
		g.set_blink(CrewStatus.is_blinking(w, stat))
		g.tooltip_text = tooltip_of(w, stat)
		var l: Label = _labels[stat]
		l.visible = show_numbers
		l.text = str(int(round(v)))
	var m: int = w.mental
	_face.texture = _faces[m]
	_face.modulate = CrewStatusDB.MENTAL_COLORS[m]
	_face.tooltip_text = "精神状態: %s" % CrewStatusDB.MENTAL_NAMES[m]
	_face_label.visible = show_numbers
	_face_label.text = CrewStatusDB.MENTAL_NAMES[m]
	_limit = m == CrewStatusDB.Mental.LIMIT
	set_process(_limit)
	if not _limit:
		_face.modulate.a = 1.0


func _process(delta: float) -> void:
	_t += delta
	if _limit:
		_face.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 8.0))      # 限界: 顔が点滅する


## アイコンにマウスを載せたときの説明（正確な値）。疲労度は、疲労度そのものと余力の両方
static func tooltip_of(w, stat: String) -> String:
	var name: String = CrewStatusDB.STAT_NAMES[stat]
	var v: float = float(w.get(stat))
	if stat == "fatigue":
		return "%s %d / 100（高いほど疲れている。余力 %d）" % [name, int(round(v)), int(round(100.0 - v))]
	return "%s %d / 100" % [name, int(round(v))]


## 各アイコンを返す（診断ツールが読む）
func gauge(stat: String) -> IconGauge:
	return _gauges[stat]


func face() -> TextureRect:
	return _face


func number_label(stat: String) -> Label:
	return _labels[stat]
