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
	modulate = game.world.tint()
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
		if l[0]=="dunes": _draw_region_scenery(cam_left)
		var t := GameData.tex("res://assets/environment/%s.png" % l[0])
		var dot := ArtSpec.dot_px(t, float(ArtSpec.BACKGROUND_W))         # この絵の1ドットの大きさ（px）。細かい絵ほど小さい
		var w := float(t.get_width()) * dot                              # 画面上の大きさ（絵の細かさに依存しない）
		var h := float(t.get_height()) * dot
		var off := floorf(fposmod(scroll_x * float(l[2]), w) / dot) * dot   # 絵のドットの格子に合わせる
		var y := float(l[1] * PX)
		var k_range := tile_range(cam_left, off, w)
		for k in range(k_range.x, k_range.y + 1):
			draw_texture_rect(t, Rect2(-off + float(k) * w, y, w, h), false)


## 道路の実座標に沿って出発地から離れ、到着地の景観へ近づく。
## 地名文字・クリック対象・乱数は持たず、地図/保存の現在状態から毎回描く。
func scenery_weights() -> Dictionary:
	if not game.world.active:return {}
	var world=game.world
	if world.phase in ["travel","arriving","turning"] and WorldMapDB.ROADS.has(world.road):
		var ends:Array=WorldMapDB.ROADS[world.road]
		var t:float=clampf(world.progress/WorldMapDB.LENGTH,0,1)
		return {ends[0]:clampf(1.0-t/0.25,0,1),ends[1]:clampf((t-0.75)/0.25,0,1)}
	return {world.region:1.0}

func _draw_region_scenery(cam_left: float) -> void:
	var weights:=scenery_weights()
	var off:=floorf(fposmod(scroll_x*0.22,VIEW_W)/4.0)*4.0
	var tiles:=tile_range(cam_left,off,VIEW_W)
	for id in weights:
		var alpha:float=weights[id]
		if alpha<=0:continue
		for k in range(tiles.x,tiles.y+1):
			draw_set_transform(Vector2(float(k)*VIEW_W-off,0))
			_draw_region_tile(id,alpha)
	draw_set_transform(Vector2.ZERO)

func _scenery_color(hex: String,alpha: float) -> Color:
	var c:=Color(hex);c.a=alpha;return c

func _building(x:float,y:float,w:float,h:float,alpha:float,tower:=false) -> void:
	var wall:=_scenery_color("b39978",alpha)
	var shade:=_scenery_color("927c62",alpha)
	draw_rect(Rect2(x,y,w,h),wall)
	draw_rect(Rect2(x+w-12,y,12,h),shade)
	draw_rect(Rect2(x-4,y-8,w+8,8),_scenery_color("c6ad87",alpha))
	if tower:
		for dx in range(0,int(w),20):draw_rect(Rect2(x+dx,y-20,12,16),wall)
	for yy in range(int(y+20),int(y+h-12),32):
		for xx in range(int(x+12),int(x+w-16),24):draw_rect(Rect2(xx,yy,8,12),shade)

func _palm(x:float,y:float,alpha:float) -> void:
	var leaf:=_scenery_color("92956b",alpha)
	draw_rect(Rect2(x,y-100,8,100),_scenery_color("ae9166",alpha))
	for side in [-1,1]:
		draw_colored_polygon(PackedVector2Array([Vector2(x+4,y-108),Vector2(x+side*40,y-92),Vector2(x+side*48,y-72),Vector2(x+side*20,y-88)]),leaf)
	draw_colored_polygon(PackedVector2Array([Vector2(x+4,y-108),Vector2(x-8,y-130),Vector2(x+12,y-122),Vector2(x+20,y-94)]),leaf)

func _draw_region_tile(id:String,alpha:float) -> void:
	match id:
		"central_trade":
			# 重なる低層の街並み、城壁、門、天幕。拠点より淡い遠景。
			for i in 10:
				_building(float(i*128),float(268+(i%3)*24),112,172-float((i%3)*24),alpha)
			draw_rect(Rect2(0,368,1280,72),_scenery_color("a58a69",alpha))
			for x in [72,472,920]:
				_building(x,208,64,232,alpha,true)
				_building(x+160,228,64,212,alpha,true)
				draw_rect(Rect2(x+64,320,96,120),_scenery_color("8f795f",alpha))
				draw_colored_polygon(PackedVector2Array([Vector2(x+52,320),Vector2(x+112,272),Vector2(x+172,320)]),_scenery_color("b18b73",alpha))
			for x in [300,740,1170]:
				draw_colored_polygon(PackedVector2Array([Vector2(x-44,400),Vector2(x,368),Vector2(x+44,400)]),_scenery_color("b89077",alpha))
		"south_oasis":
			for x in [100,360,680,1000]:
				_building(x,352,88,88,alpha)
				draw_colored_polygon(PackedVector2Array([Vector2(x-8,352),Vector2(x+44,320),Vector2(x+96,352)]),_scenery_color("bd9e71",alpha))
				_palm(x-44,428,alpha);_palm(x+112,380,alpha)
			draw_rect(Rect2(760,428,140,12),_scenery_color("a0b5a1",alpha))
		"east_sands":
			for x in [40,420,850]:
				draw_colored_polygon(PackedVector2Array([Vector2(x,440),Vector2(x+64,312),Vector2(x+136,340),Vector2(x+188,440)]),_scenery_color("c1a477",alpha))
			for x in [240,720,1120]:
				draw_rect(Rect2(x,280,24,160),_scenery_color("b29c77",alpha))
				draw_rect(Rect2(x-12,272,48,16),_scenery_color("c7ae83",alpha))
				draw_rect(Rect2(x+80,328,20,112),_scenery_color("b29c77",alpha))
				draw_colored_polygon(PackedVector2Array([Vector2(x+4,272),Vector2(x+16,248),Vector2(x+28,272)]),_scenery_color("b29c77",alpha))
		"old_mine":
			for x in [-80,360,800]:
				draw_colored_polygon(PackedVector2Array([Vector2(x,440),Vector2(x+80,248),Vector2(x+164,180),Vector2(x+244,264),Vector2(x+360,440)]),_scenery_color("999287",alpha))
				draw_colored_polygon(PackedVector2Array([Vector2(x+164,180),Vector2(x+244,264),Vector2(x+360,440),Vector2(x+208,440)]),_scenery_color("85837c",alpha))
				draw_rect(Rect2(x+128,344,72,96),_scenery_color("77766f",alpha))
				for dx in [120,200]:draw_rect(Rect2(x+dx,336,8,104),_scenery_color("aa9677",alpha))
				draw_rect(Rect2(x+116,332,96,12),_scenery_color("aa9677",alpha))
				for dx in [240,280]:draw_rect(Rect2(x+dx,296,8,144),_scenery_color("a59478",alpha))
				draw_rect(Rect2(x+232,292,64,12),_scenery_color("a59478",alpha))
