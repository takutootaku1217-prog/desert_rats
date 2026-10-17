class_name TownBackdrop
extends Control
## 自作の低解像度・斜め俯瞰の街。既存の車体と外装定義を参照する。
var game
func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
func poly(points:Array,color:String) -> void:
 draw_colored_polygon(PackedVector2Array(points),Color(color))
func block(x:float,y:float,w:float,d:float,h:float,c:String) -> void:
 var a:=Vector2(x,y);var b:=a+Vector2(w,-w*0.38);var e:=a+Vector2(d,d*0.55);var f:=b+Vector2(d,d*0.55)
 poly([a,b,f,e],c)
 poly([a,e,e+Vector2(0,h),a+Vector2(0,h)],"a86c42")
 poly([e,f,f+Vector2(0,h),e+Vector2(0,h)],"754d39")
func _draw() -> void:
 draw_set_transform(Vector2.ZERO,0,Vector2(4,4))
 draw_rect(Rect2(0,0,320,180),Color("d6ad71"))
 poly([Vector2(0,110),Vector2(148,35),Vector2(320,76),Vector2(320,126),Vector2(120,80),Vector2(0,145)],"e8c997")
 poly([Vector2(110,180),Vector2(145,75),Vector2(167,75),Vector2(210,180)],"e8c997")
 # 城壁と奥の門。遠方の街並み。
 for i in 7:
  block(45+i*33,39+i*2,18,11,13,"dabc82")
 block(113,33,20,15,32,"edcc91");block(164,35,20,15,32,"edcc91")
 draw_rect(Rect2(147,45,21,22),Color("4b463d"));block(132,32,40,8,9,"f1d8a0")
 for i in 5:draw_rect(Rect2(137+i*7,30,4,5),Color("e5c38b"))
 # 左の交易所、掲示板、積まれた荷物。
 block(25,73,44,27,28,"eac591")
 poly([Vector2(25,73),Vector2(69,56),Vector2(96,71),Vector2(52,88)],"5d9390")
 for i in 5:draw_line(Vector2(28+i*8,72-i*3),Vector2(54+i*8,87-i*3),Color("8bb3a2"),2)
 draw_rect(Rect2(57,93,11,20),Color("513f32"));draw_rect(Rect2(26,103,21,14),Color("75563a"))
 for i in 3:draw_rect(Rect2(29+i*5,106,3,6),Color("ecd7a9"))
 block(80,105,11,8,8,"b88a54");block(90,111,9,7,7,"c99b62")
 # 右の市場、日除け、樽・品物。
 for i in 3:
  var x:=208.0+i*26;var y:=83.0+i*10
  block(x,y,23,14,18,"e3bd82")
  poly([Vector2(x-2,y-5),Vector2(x+21,y-14),Vector2(x+38,y-4),Vector2(x+15,y+5)],"bd5c42" if i%2==0 else "d6aa4e")
  for j in 3:draw_line(Vector2(x+j*8,y-6-j*3),Vector2(x+16+j*8,y+4-j*3),Color("f1daa6"),3)
  for j in 3:draw_rect(Rect2(x+19+j*5,y+13,4,4),Color("829655"))
 # 整備ヤードの床と縁石。
 poly([Vector2(39,139),Vector2(134,106),Vector2(242,149),Vector2(149,179)],"8b8067")
 for i in 6:draw_line(Vector2(51+i*18,136-i*6),Vector2(151+i*18,176-i*6),Color("aa9b7b"),1)
 # 給油タンク、ホース、クレーン。
 block(45,125,19,13,22,"75a5a0")
 draw_rect(Rect2(51,132,17,8),Color("4e7777"));draw_rect(Rect2(57,122,6,4),Color("465c59"))
 draw_polyline(PackedVector2Array([Vector2(64,144),Vector2(71,151),Vector2(91,151),Vector2(102,144)]),Color("3b4140"),2)
 draw_rect(Rect2(192,100,4,49),Color("d4a34d"));draw_rect(Rect2(151,98,45,4),Color("e0b858"))
 draw_line(Vector2(193,100),Vector2(167,87),Color("dfb568"),2);draw_line(Vector2(167,87),Vector2(153,100),Color("dfb568"),2)
 draw_line(Vector2(155,101),Vector2(155,121),Color("41463f"),1);draw_line(Vector2(155,121),Vector2(160,124),Color("41463f"),2)
 draw_rect(Rect2(189,147,13,4),Color("4c5148"))
 # 実際の拠点と同じ車体・部屋の窓・進行による外装パーツ。
 var at:=Vector2(90,116);var scale_:=0.12
 draw_rect(Rect2(at+Vector2(5,26),Vector2(88,8)),Color("3d403a"))
 for i in 5:
  draw_rect(Rect2(at+Vector2(9+i*16,29),Vector2(11,9)),Color("343936"));draw_rect(Rect2(at+Vector2(12+i*16,31),Vector2(5,5)),Color("897c60"))
 for slot in Rooms.SLOT_ORDER:
  var r:=ExteriorDB.window_rect(slot)
  draw_rect(Rect2(at+Vector2(r.position)*ArtSpec.UNIT_PX*scale_,Vector2(r.size)*ArtSpec.UNIT_PX*scale_),ExteriorDB.glass_color(game.room_layout.get(slot,"empty")))
 draw_texture_rect(ExteriorDB.body_tex(),Rect2(at,ArtSpec.px_size(ArtSpec.HULL)*scale_),false)
 for e in ExteriorDB.visible_parts(game,["wall","armor","roof"]):
  var part:Dictionary=e.part
  var pt:=ExteriorDB.at_of(part,e.slot,-1.0)
  draw_texture_rect_region(ExteriorDB.sheet_tex(part.sheet),Rect2(at+Vector2(pt)*ArtSpec.UNIT_PX*scale_,Vector2(ExteriorDB.frame_units(part))*ArtSpec.UNIT_PX*scale_),Rect2(ExteriorDB.frame_of(part)))
 # ランプ・足跡・砂漠の低木。
 for pos in [Vector2(105,90),Vector2(199,69),Vector2(17,146),Vector2(280,157)]:
  draw_rect(Rect2(pos,Vector2(2,10)),Color("60533c"));draw_rect(Rect2(pos-Vector2(2,2),Vector2(6,4)),Color("ffe4a3"))
 for i in 18:draw_rect(Rect2(10+(i*47)%300,160+(i*7)%15,3,1),Color("ad8a58"))
