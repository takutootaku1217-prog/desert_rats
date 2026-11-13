class_name BaseHPGauge
extends IconGauge
## 拠点の輪郭そのものをゲージにする。窓・タイヤの描き込みは省く。
## HPや修理の計算は行わない。形は一定とし、素材の参照先が変わったときだけ読み直す。

const SIZE_UNITS := Vector2i(28, 12)       # 112×48px。燃料・積載と高さを揃える
const RASTER := Vector2i(56, 24)           # HUD内のシルエットは2pxのドットで表示
const ICON_ART := "res://assets/ui/base_hp_cartoon.png" # 後から差し替える仮素材。白い車体がHPの充填範囲
const CAPTION := "拠点"

var _appearance_key := ""


func update_appearance(_game) -> void:
	var key := str([ICON_ART, ArtSpec.root_override])
	if key == _appearance_key:
		return
	_appearance_key = key
	_build_shape()


func _build_shape() -> void:
	# 白い車体と下側の小さな凹凸を一続きのHPマスクにする。
	# 輪郭は値と独立し、HP0や点滅中にも残る。世界側の外観は変更しない。
	var art := _load_image(ICON_ART)
	art = art.get_region(art.get_used_rect())
	art.resize(RASTER.x - 2, RASTER.y - 2, Image.INTERPOLATE_NEAREST)
	var frame := Image.create(RASTER.x, RASTER.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(RASTER.x, RASTER.y, false, Image.FORMAT_RGBA8)
	for y in art.get_height():
		for x in art.get_width():
			var color := art.get_pixel(x, y)
			if color.a <= 0.5:
				continue
			var at := Vector2i(x + 1, y + 1)
			if minf(color.r, minf(color.g, color.b)) > 0.9:
				mask.set_pixelv(at, Color.WHITE)
			else:
				color.a = 1.0
				frame.set_pixelv(at, color)
	set_shape(ImageTexture.create_from_image(frame), mask, SIZE_UNITS)
	# 文字用に空けた中央の車体へ2行を収める。
	_text_center = Vector2(31.0, 12.0)


func _draw_text() -> void:
	var center := _text_center * pixel
	var font := GameData.font()
	var width := display_size.x
	var pos := Vector2(center.x - width / 2.0, center.y - 4.0)
	draw_string_outline(font, pos, CAPTION, HORIZONTAL_ALIGNMENT_CENTER, width, 11, 2, Color("161a20"))
	draw_string(font, pos, CAPTION, HORIZONTAL_ALIGNMENT_CENTER, width, 11, Color.WHITE)
	if text != "":
		pos.y = center.y + 9.0
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, 2, Color("161a20"))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, Color.WHITE)
