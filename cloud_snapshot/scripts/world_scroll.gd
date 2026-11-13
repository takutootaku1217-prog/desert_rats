class_name WorldScroll
extends Node2D
const TravelLanePresentation = preload("res://scripts/travel_lane_presentation.gd")
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


func travel_lane_active() -> bool:
	return TravelLanePresentation.active(game)


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
		# 既存砂漠は従来どおり dunes の下へ地域飾りを描く。A地域だけは
		# 緑地/採石場/ヤードを砂漠絵の後で重ねる。
		if l[0]=="dunes" and not game.world.first_region(): _draw_region_scenery(cam_left)
		var t := GameData.tex("res://assets/environment/%s.png" % l[0])
		var dot := ArtSpec.dot_px(t, float(ArtSpec.BACKGROUND_W))         # この絵の1ドットの大きさ（px）。細かい絵ほど小さい
		var w := float(t.get_width()) * dot                              # 画面上の大きさ（絵の細かさに依存しない）
		var h := float(t.get_height()) * dot
		var off := floorf(fposmod(scroll_x * float(l[2]), w) / dot) * dot   # 絵のドットの格子に合わせる
		var y := float(l[1] * PX)
		var k_range := tile_range(cam_left, off, w)
		for k in range(k_range.x, k_range.y + 1):
			draw_texture_rect(t, Rect2(-off + float(k) * w, y, w, h), false)
	# A地域固有の景観は既存の砂漠レイヤーを塗り替える表示層。以前は dunes
	# より先に描いていたため、その砂レイヤーに完全に隠れていた。
	if game.world.first_region(): _draw_region_scenery(cam_left)
	if travel_lane_active(): _draw_travel_lane(cam_left)


## 道路の実座標に沿って出発地から離れ、到着地の景観へ近づく。
## 地名文字・クリック対象・乱数は持たず、地図/保存の現在状態から毎回描く。
func scenery_weights() -> Dictionary:
	if not game.world.active:return {}
	var world=game.world
	if world.phase in ["travel","arriving","turning"] and WorldMapDB.roads(world.map_profile).has(world.road):
		var ends:Array=WorldMapDB.road_ends(world.road,world.map_profile)
		var t:float=clampf(world.progress/world.road_length(),0,1)
		# A地域は背景自体が「未舗装の移動」を説明するものなので、区間中央でも
		# 出発地/到着地の景観を連続して混ぜる。通常砂漠の既存テストの重みは変えない。
		if world.first_region():
			return {ends[0]:1.0-t,ends[1]:t}
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

## 未舗装の轍と、整地後の締まった路盤。移動の長さ/燃料にも同じWorldTripの
## road_stateが使われ、背景だけが便利になったように見せない。
func _draw_region_roadbed(cam_left:float) -> void:
	if game==null or not game.world.first_region() or game.world.phase not in ["travel","arriving","turning"]:return
	var graded:=WorldMapDB.road_is_graded(game.world.road,game.world.map_profile,game.world.region_state)
	# 車輪の下にも見える低い地面帯に置く。車体の陰で完全に隠れないため、
	# 地図線だけではなく実走行中にも未舗装/整地済みを判別できる。
	var road_y:=548.0
	var base:=Color("668753") if graded else Color("896f4d")
	var edge:=Color("c4db98") if graded else Color("be9a68")
	draw_rect(Rect2(cam_left,road_y,VIEW_W,46),base)
	draw_rect(Rect2(cam_left,road_y,VIEW_W,3),edge)
	draw_rect(Rect2(cam_left,road_y+43,VIEW_W,3),edge)
	for x in range(int(cam_left)-40,int(cam_left+VIEW_W)+40,64 if graded else 36):
		if graded:
			draw_line(Vector2(x,road_y+22),Vector2(x+42,road_y+22),edge,2)
		else:
			draw_line(Vector2(x,road_y+12),Vector2(x+20,road_y+34),edge,2)
			draw_line(Vector2(x+8,road_y+34),Vector2(x+28,road_y+12),edge,1)

func _draw_travel_lane(cam_left: float) -> void:
	if not travel_lane_active():
		return
	# The departure-safety phase can still show stopped-site actors while they
	# return.  Do not add a route or destination landmark until the actual leg
	# begins, otherwise that handoff reads as a second depth row.
	var layout := TravelLanePresentation.road_layout(game)
	if layout.is_empty():
		return
	_draw_mine_landmark(cam_left)
	var composition := TravelLanePresentation.composition(game)
	var danger := composition == "danger"
	var graded: bool = bool(game.world.first_region()) and WorldMapDB.road_is_graded(game.world.road, game.world.map_profile, game.world.region_state)
	# One flat route only.  The former lower shoulder and centre dashed marker
	# made the purely horizontal view read as two depth lanes.  Normal and danger
	# use the same geometry; danger changes only the threat cue below.
	var road_y := float(layout["top"])
	var road_h := float(layout["height"])
	var bed := Color("668753") if graded else Color("896f4d")
	var edge := Color("c4db98") if graded else Color("be9a68")
	draw_rect(Rect2(cam_left, road_y, VIEW_W, road_h), bed)
	draw_rect(Rect2(cam_left, road_y, VIEW_W, 3), edge)
	draw_rect(Rect2(cam_left, road_y + road_h - 3.0, VIEW_W, 3), edge)
	# Sparse scrolling dust is texture, not a lane divider or foreground strip.
	var dust_step := 96.0 if graded else 64.0
	var dust_offset := fposmod(scroll_x, dust_step)
	for x in range(int(cam_left - dust_step), int(cam_left + VIEW_W + dust_step), int(dust_step)):
		var px := float(x) - dust_offset
		draw_rect(Rect2(px, road_y + road_h * 0.72, 7.0, 2.0), Color("d4bd84", 0.28))
	if danger:
		_draw_travel_danger_distance(cam_left, road_y)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(cam_left + 24, 116), "%s  |  乗車・車外表示  |  仮背景" % TravelLanePresentation.phase_label(game), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color("ffe9b0", 0.9))


## A thin cue shows the real nearest hostile's separation from the base.  It is
## deliberately behind the actors and does not become a blocking combat panel.
func _draw_travel_danger_distance(cam_left: float, road_y: float) -> void:
	if game == null or game.enemies_root == null:
		return
	var nearest = null
	var best := INF
	var vehicle := GameData.HULL_POS + Vector2(720.0, 300.0)
	for enemy in game.enemies_root.get_children():
		if not is_instance_valid(enemy) or bool(enemy.get("dead")):
			continue
		var distance := vehicle.distance_to(enemy.position)
		if distance < best:
			best = distance
			nearest = enemy
	if nearest == null:
		return
	var target: Vector2 = nearest.position
	draw_line(vehicle, target, Color("ff9b73", 0.72), 2.0)
	draw_circle(target, 18.0, Color("ff7d61", 0.20))
	draw_circle(target, 5.0, Color("ffb08a", 0.90))
	draw_string(ThemeDB.fallback_font, Vector2(target.x - 38.0, minf(target.y - 26.0, road_y - 18.0)), "THREAT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("ffd2b8", 0.95))


## Placeholder presentation only. It sits behind the one road and vehicle; it
## does not add collision, routing, a second lane, or an art dependency.
func _draw_mine_landmark(cam_left: float) -> void:
	if game == null or game.world == null or not game.world.first_region():
		return
	var w = game.world
	if w.region != "c_quarry" and w.origin != "c_quarry" and w.destination != "c_quarry":
		return
	var x := cam_left + 870.0
	var base_y := 546.0
	draw_colored_polygon(PackedVector2Array([Vector2(x - 165, base_y), Vector2(x - 64, 310), Vector2(x + 52, 350), Vector2(x + 204, base_y)]), Color("727970", 0.92))
	draw_colored_polygon(PackedVector2Array([Vector2(x - 36, base_y), Vector2(x + 44, 362), Vector2(x + 112, base_y)]), Color("565d56", 0.96))
	draw_rect(Rect2(x + 12, 450, 102, 96), Color("313b36", 0.98))
	draw_rect(Rect2(x - 14, 432, 150, 18), Color("aa9677", 0.96))
	draw_rect(Rect2(x + 9, 442, 108, 8), Color("d8c587", 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(x - 8, 416), "C MINE  /  鉱山入口（試作）", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0b5"))

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
	if game!=null and game.world.first_region():
		_draw_first_region_tile(id,alpha)
		return
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

func _draw_first_region_tile(id:String,alpha:float) -> void:
	match id:
		"next_greenway":
			draw_rect(Rect2(0,205,1280,235),_scenery_color("577e6b",alpha))
			for x in [80,360,640,920]:
				draw_rect(Rect2(x,270,20,170),_scenery_color("9aafa4",alpha))
				draw_rect(Rect2(x+140,270,20,170),_scenery_color("9aafa4",alpha))
				draw_rect(Rect2(x,266,160,20),_scenery_color("a6bdb0",alpha))
				draw_colored_polygon(PackedVector2Array([Vector2(x-18,302),Vector2(x+65,235),Vector2(x+190,302)]),_scenery_color("648b58",alpha))
			draw_line(Vector2(0,424),Vector2(1280,424),_scenery_color("a2b19a",alpha),7)
		"a_start":
			draw_rect(Rect2(0,220,1280,220),_scenery_color("789b70",alpha))
			for x in [80,360,690,1000]:
				_building(x,344,88,96,alpha)
				draw_colored_polygon(PackedVector2Array([Vector2(x-8,344),Vector2(x+44,311),Vector2(x+96,344)]),_scenery_color("7ca068",alpha))
			for x in [180,560,920]:
				draw_rect(Rect2(x,390,100,50),_scenery_color("6d8870",alpha))
		"b_forest":
			draw_rect(Rect2(0,205,1280,235),_scenery_color("587a51",alpha))
			for x in range(20,1280,76):
				draw_rect(Rect2(x,310+(x%4)*12,12,130),_scenery_color("456e48",alpha))
				draw_colored_polygon(PackedVector2Array([Vector2(x-42,330),Vector2(x+6,230),Vector2(x+50,330)]),_scenery_color("5b8a53",alpha))
			for x in [150,560,980]:
				draw_rect(Rect2(x,402,150,12),_scenery_color("765f41",alpha))
		"c_quarry":
			draw_rect(Rect2(0,220,1280,220),_scenery_color("74796f",alpha))
			for x in [-30,300,650,1000]:
				draw_colored_polygon(PackedVector2Array([Vector2(x,440),Vector2(x+86,245),Vector2(x+205,440)]),_scenery_color("8a8f82",alpha))
				draw_line(Vector2(x+30,378),Vector2(x+160,334),_scenery_color("c2c2a9",alpha),4)
				draw_line(Vector2(x+12,408),Vector2(x+182,366),_scenery_color("a9aa94",alpha),4)
		"d_yard":
			draw_rect(Rect2(0,220,1280,220),_scenery_color("725d51",alpha))
			for x in [70,350,640,930]:
				draw_rect(Rect2(x,296,150,144),_scenery_color("855f50",alpha))
				for dx in [12,52,92,132]:draw_rect(Rect2(x+dx,326,14,46),_scenery_color("b98b65",alpha))
				draw_line(Vector2(x-24,416),Vector2(x+180,416),_scenery_color("5b5551",alpha),6)
