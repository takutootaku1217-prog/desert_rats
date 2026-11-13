class_name FxSprite
extends Node2D
## 効果の素材（data/effects.gd の表）を再生するだけの部品。湯気・砂ぼこり・きらめき、将来の炎・爆発・銃撃・レーザー・水などにも使い回す。
## 図形はコードで描かず、画像のコマを順に出すだけ。画面上の大きさは「基準の大きさ（ユニット）× UNIT_PX」で決まり、絵の細かさ（ドット数）に依存しない
## （絵を高精細な画像に差し替えても、ここは変えなくてよい）。足元の中心が position。ループしない効果は、1回再生して自分で消える。

var id := ""
var _spec := {}
var _tex: Texture2D
var _t := 0.0
var _loop := false
var _fps := 6.0
var _frames := 1
var playing := true


## 効果 id を parent の下の pos（parent から見た位置）に出す。表にない id なら null。
static func spawn(parent: Node, effect_id: String, pos: Vector2) -> FxSprite:
	if not EffectDB.has(effect_id):
		return null
	var fx := FxSprite.new()
	fx.setup(effect_id)
	fx.position = pos
	parent.add_child(fx)
	return fx


func setup(effect_id: String) -> void:
	id = effect_id
	var e: Dictionary = EffectDB.EFFECTS[id]
	_spec = EffectDB.spec(id)
	_tex = GameData.tex(String(e["sheet"]))
	_loop = bool(e["loop"])
	_fps = float(e["fps"])
	_frames = int(e["frames"])
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3


## 再生を止めて隠す／再開する（ループする効果を、状態に合わせて出し入れする）
func set_playing(on: bool) -> void:
	if playing == on:
		return
	playing = on
	visible = on
	if on:
		_t = 0.0


## いまのコマ番号
func frame() -> int:
	var f := int(_t * _fps)
	return f % _frames if _loop else mini(f, _frames - 1)


func _process(delta: float) -> void:
	if not playing:
		return
	_t += delta
	if not _loop and _t >= float(_frames) / _fps:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _tex == null or not playing:
		return
	var cell: Vector2i = _spec["cell"]
	var size := ArtSpec.px_size(cell)
	var dot := ArtSpec.dot_px(_tex, ArtSpec.sheet_units_w(_spec))
	var snap := ArtSpec.snap_offset(global_position, dot)              # 絵の1ドットの格子に合わせる（ほかの絵と同じ）
	draw_texture_rect_region(_tex, Rect2(snap + Vector2(-size.x / 2.0, -size.y), size), ArtSpec.frame_src(_tex, _spec, frame()))
