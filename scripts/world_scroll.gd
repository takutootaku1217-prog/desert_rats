class_name WorldScroll
extends Node2D
## 砂漠の横スクロール背景（視差スクロール）。
## 拠点は画面内に留まり、世界のほうが右から左へ流れることで「前進している」ように見せる。

var game
var scroll_x := 0.0

const PX := GameData.PX
const VIEW_W := 1280.0    # 画面の幅（project.godot の基準解像度と同じ。カメラの可視範囲の計算に使う）
const VIEW_H := 720.0
const GAP_FILL := Color("fbe6ac")   # 層と層の隙間に見えてしまう色の保険（skyの最も明るい帯と同じ色。BG-02対策）
## [ファイル名, 画像を置く行(ユニット単位。画面上は ×PX), スクロール倍率]。背景の1枚の基準の幅は ArtSpec.BACKGROUND_W（画面幅ぴったり）。
const LAYERS := [
	["sky", 0, 0.0],
	["clouds", 20, 0.04],
	["mesa_far", 60, 0.10],
	["mesa_mid", 85, 0.22],
	["dunes", 110, 0.40],
	["ground", 134, 1.0],
	["props", 118, 1.0],
]


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	scroll_x += game.scroll_speed * delta
	queue_redraw()


## いまカメラに見えている世界座標の左端（カメラなし・position=0 のときは 0.0 で、これまでと同じ）
func _cam_left() -> float:
	if game != null and game.camera != null:
		return game.camera.position.x
	return 0.0


## カメラが動いても見えている範囲（cam_left 〜 cam_left+VIEW_W）を過不足なく覆うタイル番号の範囲 [k_min, k_max] を返す
## （タイル k は x = -off + k*w に置く）。BG-01: 以前はカメラの position を考えず、常に2枚しか並べていなかった。
## 純粋な計算だけの関数にして、ヘッドレスの自己診断からも確認できるようにした（tools/test_qa_camera_bg.gd）。
static func tile_range(cam_left: float, off: float, w: float) -> Vector2i:
	var k_min: int = int(floor((cam_left + off) / w))
	var k_max: int = int(floor((cam_left + VIEW_W - 0.01 + off) / w))
	return Vector2i(k_min, k_max)


func _draw() -> void:
	var cam_left := _cam_left()
	# 層の絵に隙間（透明）があっても、灰色ではなくこの色が見える保険（BG-02）。このあと全レイヤーを上に重ねて描く
	draw_rect(Rect2(cam_left, 0.0, VIEW_W, VIEW_H), GAP_FILL)
	for l in LAYERS:
		var t := GameData.tex("res://assets/environment/%s.png" % l[0])
		var dot := ArtSpec.dot_px(t, float(ArtSpec.BACKGROUND_W))         # この絵の1ドットの大きさ（px）。細かい絵ほど小さい
		var w := float(t.get_width()) * dot                              # 画面上の大きさ（絵の細かさに依存しない）
		var h := float(t.get_height()) * dot
		var off := floorf(fposmod(scroll_x * float(l[2]), w) / dot) * dot   # 絵のドットの格子に合わせる
		var y := float(l[1] * PX)
		var k_range := tile_range(cam_left, off, w)
		for k in range(k_range.x, k_range.y + 1):
			draw_texture_rect(t, Rect2(-off + float(k) * w, y, w, h), false)
