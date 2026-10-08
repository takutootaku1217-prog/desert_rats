class_name BaseHPGauge
extends IconGauge
## 外装と同じ車体・車輪・パーツから、現在の拠点のシルエットを作る。
## HPや修理の計算は行わない。外観が変わったときだけ形を更新する。

const SIZE_UNITS := Vector2i(36, 16)       # 144×64px。燃料・積載は従来の48pxを維持
const RASTER := Vector2i(72, 32)           # HUD内のシルエットは2pxのドットで表示
const CAPTION := "拠点"

var _appearance_key := ""
var _sources: Array = []


func update_appearance(game) -> void:
	var parts: Array = ExteriorDB.visible_parts(game, ["wall", "armor", "roof"])
	var engine_unit := -1.0
	if game.base.room_slot("engine") != "":
		engine_unit = (game.base.engine_point().x - GameData.HULL_POS.x) / float(ArtSpec.UNIT_PX)
	var placements: Array = []
	for entry in parts:
		var at := ExteriorDB.at_of(entry["part"], entry["slot"], engine_unit)
		placements.append([entry["part"]["id"], entry["slot"], at])
	var key := str([Rooms.STYLE, ArtSpec.root_override, ExteriorDB.geo(), placements])
	if key == _appearance_key:
		return
	_appearance_key = key
	_sources = []
	_add_image(_load_image(ExteriorDB.dir() + "body.png"), Vector2i.ZERO, ArtSpec.HULL)
	# ガラスの穴はシルエットの穴にしない（外装でもガラスで埋まる）。
	for slot in Rooms.SLOT_ORDER:
		_add_solid(ExteriorDB.window_rect(slot))
	_add_solid(ExteriorDB.cab_rect())
	var wheel_tex := GameData.tex(ExteriorDB.WHEEL_SHEET)
	var wheel := _load_image(ExteriorDB.WHEEL_SHEET).get_region(Rect2i(ArtSpec.frame_src(wheel_tex, ArtSpec.WHEELS, 0)))
	var wheel_units: Vector2i = ArtSpec.WHEELS["cell"]
	for wx in MobileBase.WHEEL_X:
		var at := Vector2i((Vector2(wx, MobileBase.WHEEL_Y) - GameData.HULL_POS) / float(ArtSpec.UNIT_PX)) - wheel_units / 2
		_add_image(wheel, at, wheel_units)
	for entry in parts:
		var part: Dictionary = entry["part"]
		var sheet := _load_image(ExteriorDB.dir() + String(ExteriorDB.geo()["sheets"][part["sheet"]]["file"]))
		_add_image(sheet.get_region(ExteriorDB.frame_of(part)), ExteriorDB.at_of(part, entry["slot"], engine_unit), ExteriorDB.frame_units(part))
	# 外装と同じ斜路。煙・走行時の揺れ・車輪のアニメーションは形に含めない。
	_add_image(_load_image(ExteriorDB.RAMP_SHEET), Vector2i((ExteriorDB.RAMP_POS - GameData.HULL_POS) / float(ArtSpec.UNIT_PX)), ArtSpec.RAMP)
	_build_shape()


func _add_image(source: Image, at: Vector2i, units: Vector2i) -> void:
	var image := source.duplicate() as Image
	image.resize(units.x, units.y, Image.INTERPOLATE_NEAREST)
	_sources.append({"image": image, "at": at, "units": units})


func _add_solid(rect: Rect2i) -> void:
	var image := Image.create(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_sources.append({"image": image, "at": rect.position, "units": rect.size})


func _build_shape() -> void:
	var bounds := Rect2i(Vector2i.ZERO, ArtSpec.HULL)
	for entry in _sources:
		bounds = bounds.merge(Rect2i(entry["at"], entry["units"]))
	var canvas := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	for entry in _sources:
		var image: Image = entry["image"]
		canvas.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), entry["at"] - bounds.position)
	var used := canvas.get_used_rect()
	var shape := canvas.get_region(used)
	var scale_factor := minf(float(RASTER.x - 4) / float(used.size.x), float(RASTER.y - 4) / float(used.size.y))
	var fitted := Vector2i(maxi(1, roundi(used.size.x * scale_factor)), maxi(1, roundi(used.size.y * scale_factor)))
	shape.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
	var offset := (RASTER - fitted) / 2
	var silhouette := Image.create(RASTER.x, RASTER.y, false, Image.FORMAT_RGBA8)
	silhouette.blit_rect(shape, Rect2i(Vector2i.ZERO, fitted), offset)
	var frame := Image.create(RASTER.x, RASTER.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(RASTER.x, RASTER.y, false, Image.FORMAT_RGBA8)
	for y in RASTER.y:
		for x in RASTER.x:
			if not _opaque(silhouette, Vector2i(x, y)):
				continue
			var inside := true
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if not _opaque(silhouette, Vector2i(x, y) + d):
					inside = false
			if inside:
				mask.set_pixel(x, y, Color.WHITE)
			else:
				frame.set_pixel(x, y, Color("aab4c4"))
	set_shape(ImageTexture.create_from_image(frame), mask, SIZE_UNITS)
	# 文字は屋根の突起や斜路を含む全体の中心でなく、車体内の中央へ。
	var body_center := Vector2(ArtSpec.HULL) / 2.0 - Vector2(bounds.position + used.position)
	_text_center = Vector2(offset) + body_center * Vector2(float(fitted.x) / used.size.x, float(fitted.y) / used.size.y)


static func _opaque(image: Image, at: Vector2i) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x < image.get_width() and at.y < image.get_height() and image.get_pixelv(at).a > 0.5


func _draw_text() -> void:
	var center := _text_center * pixel
	var font := GameData.font()
	var width := display_size.x
	var pos := Vector2(center.x - width / 2.0, center.y - 6.0)
	draw_string_outline(font, pos, CAPTION, HORIZONTAL_ALIGNMENT_CENTER, width, 11, 2, Color("161a20"))
	draw_string(font, pos, CAPTION, HORIZONTAL_ALIGNMENT_CENTER, width, 11, Color.WHITE)
	if text != "":
		pos.y = center.y + 7.0
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, 2, Color("161a20"))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, Color.WHITE)
