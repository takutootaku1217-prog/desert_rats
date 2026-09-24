class_name WeatherFX
extends CanvasLayer
## 天候の見た目（砂嵐・酷暑・寒波）。世界の上に薄く重ねる。ゲームの状態は変えない（見た目だけ）。
## 予報の間はうっすら、発生すると濃くなり、終わるとゆっくり消える。

var game
var _ctl: Control
var _lv := {"sandstorm": 0.0, "heatwave": 0.0, "coldsnap": 0.0}     # 各天候の濃さ 0〜1
var _grains: Array = []          # 砂・雪の粒 {p: Vector2, v: Vector2, s: float}
var _t := 0.0

const MAX_GRAINS := 160
const FADE_PER_SEC := 0.45


func _ready() -> void:
	layer = 3                      # 世界（0）より上、UI（10〜）より下
	_ctl = Control.new()
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctl.draw.connect(_on_draw)
	add_child(_ctl)


## 天候ごとの目標の濃さ。予報中は 0.25、発生中は 1.0。
func _target(id: String) -> float:
	var d = game.director
	for a in d.active:
		if a["id"] == id:
			return 1.0
	for f in d.forecast:
		if f["id"] == id:
			return 0.25
	return 0.0


func _process(delta: float) -> void:
	if game == null or game.director == null:
		return
	_t += delta
	for id in _lv:
		_lv[id] = move_toward(_lv[id], _target(id), FADE_PER_SEC * delta)
	# 粒の数は、砂嵐（砂）と寒波（雪）の濃さで決まる
	var want := int(MAX_GRAINS * maxf(_lv["sandstorm"], _lv["coldsnap"]))
	while _grains.size() < want:
		_grains.append({"p": Vector2(randf_range(0, 1280), randf_range(0, 720)), "v": Vector2.ZERO, "s": randf_range(0.6, 1.4)})
	while _grains.size() > want:
		_grains.pop_back()
	var sand: float = _lv["sandstorm"]
	for g in _grains:
		if sand >= _lv["coldsnap"]:
			g["v"] = Vector2(-(520.0 + game.scroll_speed * 3.0) * g["s"], 40.0 * g["s"])       # 横なぐりの砂
		else:
			g["v"] = Vector2(-30.0 * g["s"], 70.0 * g["s"])                                     # ゆっくり降る雪
		g["p"] += g["v"] * delta
		if g["p"].x < -20.0 or g["p"].y > 740.0:
			g["p"] = Vector2(1300.0 + randf_range(0, 80), randf_range(0, 720)) if sand >= _lv["coldsnap"] \
					else Vector2(randf_range(0, 1300), -10.0)
	_ctl.queue_redraw()


func _on_draw() -> void:
	var full := Rect2(0, 0, 1280, 720)
	var sand: float = _lv["sandstorm"]
	var heat: float = _lv["heatwave"]
	var cold: float = _lv["coldsnap"]
	if sand > 0.0:
		_ctl.draw_rect(full, Color(0.78, 0.56, 0.28, 0.42 * sand))
	if heat > 0.0:
		var pulse := 0.5 + 0.5 * sin(_t * 1.6)
		_ctl.draw_rect(full, Color(1.0, 0.55, 0.15, (0.10 + 0.05 * pulse) * heat))
		# 地平線のゆらぎ（熱気）
		for i in 6:
			var y := 470.0 + i * 9.0 + sin(_t * 2.0 + i) * 3.0
			_ctl.draw_rect(Rect2(0, y, 1280, 2), Color(1, 0.9, 0.6, 0.10 * heat))
	if cold > 0.0:
		_ctl.draw_rect(full, Color(0.55, 0.72, 1.0, 0.16 * cold))
	# 粒
	for g in _grains:
		var p: Vector2 = g["p"]
		if sand >= cold:
			var seg: float = 16.0 * float(g["s"])
			_ctl.draw_rect(Rect2(p.x, p.y, seg, 2), Color(0.95, 0.82, 0.55, 0.55 * sand))
		else:
			_ctl.draw_rect(Rect2(p.x, p.y, 3, 3), Color(1, 1, 1, 0.75 * cold))
