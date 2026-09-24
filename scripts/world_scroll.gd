class_name WorldScroll
extends Node2D
## 砂漠の横スクロール背景（視差スクロール）。
## 拠点は画面内に留まり、世界のほうが右から左へ流れることで「前進している」ように見せる。

var game
var scroll_x := 0.0

const PX := GameData.PX
## [ファイル名, 画像を置く行(ドット単位), スクロール倍率]
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


func _draw() -> void:
	for l in LAYERS:
		var t := GameData.tex("res://assets/environment/%s.png" % l[0])
		var w := float(t.get_width() * PX)
		var h := float(t.get_height() * PX)
		var off := floorf(fposmod(scroll_x * float(l[2]), w) / PX) * PX   # ドットの格子に合わせる
		var y := float(l[1] * PX)
		draw_texture_rect(t, Rect2(-off, y, w, h), false)
		if off > 0.0:
			draw_texture_rect(t, Rect2(-off + w, y, w, h), false)
