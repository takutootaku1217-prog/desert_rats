class_name BaseView
extends Node
## 拠点の見え方の切り替え（外装 ⇄ 内装）。Main が持つ。ゲームの状態は何も変えない（同じ世界を、外から見るか中から見るかだけ）。
##   内装 = 横から見た断面（部屋・仲間・設備。今までの画面）／外装 = 外から見た車両（車体・窓・外装パーツ。scripts/base_exterior.gd）。
## 切り替え中に、仲間・加工設備・倉庫・資源・生物・出来事は止まらない。作り直さず、描き方と、仲間の見え方だけを変える:
##   外装のとき、車体の中にいる仲間は姿が見えない（外の地面・斜路にいる仲間は見える。中に入るときに搬入口で消える）。
## 切り替えは、車体が一瞬すっと消えて、別の見え方で現れる（FADE_SECONDS）。画面のボタンは ui/view_switch.gd（Iキー・Oキー）。

enum Mode { INTERIOR, EXTERIOR }

## 起動したときの見え方。これまでの画面（内装）のまま始める。外装から始めたいときは EXTERIOR にする。
const START_MODE := Mode.INTERIOR
const FADE_SECONDS := 0.13                # 消えるとき・現れるとき、それぞれの長さ

signal changed(new_mode: int)

var game
var mode: int = START_MODE               # 見ている（見ようとしている）画面
var _shown: int = START_MODE             # いま実際に描いている画面（切り替えの途中は、消えきるまで前のまま）
var _phase := 0                          # 0 = 切り替え中でない / 1 = 消えていく / 2 = 現れる
var _t := 0.0
var _alpha := 1.0


func _init() -> void:
	process_priority = 100                    # 仲間の移動のあとに、見え方を決める（同じフレームの位置で「中か外か」を判定する）


func _ready() -> void:
	_apply(START_MODE)


func is_exterior() -> bool:
	return mode == Mode.EXTERIOR


## 切り替え中か
func is_fading() -> bool:
	return _phase != 0


func alpha() -> float:
	return _alpha


## 画面を切り替える。instant = true なら、演出なしですぐに切り替える（確認用）。
func set_mode(m: int, instant := false) -> void:
	if m == mode and _phase == 0:
		return
	mode = m
	changed.emit(m)
	if instant:
		_phase = 0
		_alpha = 1.0
		_apply(m)
	elif _phase == 0 or _phase == 2:
		_phase = 1                                           # 消えていく → 切り替わる → 現れる
		_t = (1.0 - _alpha) * FADE_SECONDS


func toggle() -> void:
	set_mode(Mode.INTERIOR if mode == Mode.EXTERIOR else Mode.EXTERIOR)


func _apply(m: int) -> void:
	_shown = m
	if game != null and game.base != null:
		game.base.set_view_exterior(m == Mode.EXTERIOR)
	_update()


func _process(delta: float) -> void:
	if _phase == 1:
		_t += delta
		_alpha = clampf(1.0 - _t / FADE_SECONDS, 0.0, 1.0)
		if _t >= FADE_SECONDS:
			_apply(mode)
			_phase = 2
			_t = 0.0
	elif _phase == 2:
		_t += delta
		_alpha = clampf(_t / FADE_SECONDS, 0.0, 1.0)
		if _t >= FADE_SECONDS:
			_phase = 0
			_alpha = 1.0
	_update()


## 車体と、車体の中にいる仲間の見え方を、毎フレーム決める（仲間の位置・動きには触れない）。
func _update() -> void:
	if game == null or game.base == null:
		return
	var base: MobileBase = game.base
	base.modulate.a = _alpha
	for w in game.workers:
		var inside: bool = base.is_inside(w.position)
		w.visible = not w.away and (_shown == Mode.INTERIOR or not inside)        # 調査隊に出ている間は、どちらでも見えない
		w.modulate.a = _alpha if inside else 1.0
