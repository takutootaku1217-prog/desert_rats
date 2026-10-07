class_name CrewStatusView
extends HBoxContainer
## 仲間1人のステータス表示: HP・満腹度・疲労度の「アイコン自体がゲージ」（ui/icon_gauge.gd）＋ 精神状態の顔。
## 表示だけを担当し、Worker のデータを読むだけ（update_from に渡す）。ゲームの処理は変えない。
## 簡易情報（32px）と仲間の管理画面（64px）で同じ部品を使い回す。アイコンの大きさは size_units（ユニット）。
##  - 絵は assets/ui/<名前>.png（枠）と <名前>_mask.png（充填範囲）。tools/art_ui.py が作る。差し替えるだけで形を変えられる。
##  - 色・点滅の基準・精神状態の色は data/crew_status.gd（CrewStatusDB）。危険域（値が悪い側の線を越えた）では、そのアイコンだけが赤く点滅する。
##  - 疲労度の塗りは「余力（100 − 疲労度）」: 疲れるほど中身が減る。数字は疲労度そのもの（高いほど疲れている）。
##  - 数字はアイコンの中に出す（拠点の耐久・燃料・積載重量と同じルール）。数字のON/OFFは UIKit.show_icon_numbers（OFF でもアイコンだけで状態が分かる）。

var _gauges := {}                     # ステータス名 -> IconGauge
var _face: TextureRect
var _face_label: Label
var _faces: Array = []                # 精神状態ごとの顔の絵
var _icon_px := 48.0
var _t := 0.0
var _limit := false                   # 精神状態が限界（顔が点滅する）
var _show_name := false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## 部品を作る。size_units = アイコン1つの基準の大きさ（ユニット。1ユニット = UNIT_PX）。font_size = 精神状態の名前の文字の大きさ。
## show_mental_name = 精神状態の名前を顔の下に出すか（カードでは顔の色と形だけ。管理画面では名前も）。
func setup(size_units: Vector2i = Vector2i(12, 12), font_size: int = 12, show_mental_name := false) -> CrewStatusView:
	add_theme_constant_override("separation", 6)
	_icon_px = ArtSpec.px_size(size_units).x
	_show_name = show_mental_name
	for stat in CrewStatusDB.STATS:
		var g := IconGauge.new().setup(String(CrewStatusDB.ICON_FILES[stat]), size_units)
		g.color_stages = CrewStatusDB.GAUGE_STAGES[stat]
		g.dark_empty = true                                           # 減った部分は、いまの色の暗い色（どれだけ減ったかが見える）
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		add_child(col)
		col.add_child(g)
		if show_mental_name:
			var name_label := UIKit.lbl(String(CrewStatusDB.STAT_NAMES[stat]), font_size, UIKit.C_TEXT, _icon_px)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(name_label)
		_gauges[stat] = g
	# 精神状態: 顔のアイコン（色で状態が分かる）
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
	_face_label.visible = show_mental_name
	fcol.add_child(_face_label)
	return self


## Worker の値を表示に反映する（毎フレーム呼んでよい。アイコンは、充填の数か色が変わったときだけ作り直す）
func update_from(w) -> void:
	for stat in CrewStatusDB.STATS:
		var v: float = CrewStatus.gauge_value(w, stat)
		var g: IconGauge = _gauges[stat]
		g.set_value(v, CrewStatusDB.max_of(stat), str(int(round(float(w.get(stat))))) if UIKit.show_icon_numbers else "")
		g.set_blink(CrewStatus.is_blinking(w, stat))
		g.tooltip_text = tooltip_of(w, stat)
	var m: int = w.mental
	_face.texture = _faces[m]
	_face.modulate = CrewStatusDB.MENTAL_COLORS[m]
	_face.tooltip_text = "精神状態: %s" % CrewStatusDB.MENTAL_NAMES[m]
	_face_label.visible = _show_name and UIKit.show_icon_numbers
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


func face_label() -> Label:
	return _face_label
