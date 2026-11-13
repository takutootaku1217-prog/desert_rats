class_name AreaBackdrop
extends Control
## 小さな砂漠交易圏の地形ボード。ローカル乱数で装飾し、ゲームの抽選に触れない。
var profile := WorldMapDB.DESERT
## 地図の道路状態はWorldTripだけが正本。背景はその表示を追従するだけで、
## ここから道路を開通/閉鎖したり保存内容を持ったりしない。
var region_state: Dictionary = {}
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func polygon(p:Array,c:String) -> void:draw_colored_polygon(PackedVector2Array(p),Color(c))
func _draw() -> void:
 draw_set_transform(Vector2.ZERO,0,Vector2(2,2))
 if WorldMapDB.is_first_region(profile):
  _draw_first_region_a()
  return
 draw_rect(Rect2(0,0,345,220),Color("bca477"))
 polygon([Vector2(3,27),Vector2(47,5),Vector2(151,11),Vector2(186,33),Vector2(277,9),Vector2(338,25),Vector2(329,165),Vector2(280,212),Vector2(170,201),Vector2(67,214),Vector2(8,166)],"d7bc84")
 # 山地・岩棚。通行不能領域を新しい道として描かない。
 for row in [[18,35,22],[48,26,15],[80,28,20],[245,20,24],[278,25,32],[307,48,21],[288,96,14],[26,110,13]]:
  var x:float=row[0];var y:float=row[1];var h:float=row[2];y=maxf(y,h+4)
  polygon([Vector2(x-h,y+h),Vector2(x,y-h),Vector2(x+h,y+h)],"8f8065")
  polygon([Vector2(x,y-h),Vector2(x+5,y+8),Vector2(x+h,y+h)],"706953")
  draw_line(Vector2(x-3,y-4),Vector2(x,y-h),Color("e1c898"),2)
 # 道路に沿う風紋と砂利。固定の地形のみ。
 var rng:=RandomNumberGenerator.new();rng.seed=4107
 for i in 160:
  var p:=Vector2(rng.randf_range(12,332),rng.randf_range(20,210))
  draw_line(p,p+Vector2(rng.randf_range(2,8),-1),Color("c6a974"),1)
 # オアシス、南の畑。
 draw_circle(Vector2(45,174),20,Color("789b83"));draw_circle(Vector2(43,174),13,Color("6a9695"));draw_circle(Vector2(40,171),8,Color("9eb9a6"))
 for i in 6:draw_line(Vector2(67+i*4,178),Vector2(64+i*4,196),Color("94864f"),2)
 # 枯れ木と低木の帯（既存の東部砂原の木材）。常緑の新地域ではない。
 for i in 30:
  var x:=185.0+float((i*19)%112);var y:=126.0+float((i*17)%67)
  draw_line(Vector2(x,y+7),Vector2(x,y-3),Color("6d7251"),2)
  draw_line(Vector2(x,y),Vector2(x-4,y-5),Color("6d7251"),1)
  draw_line(Vector2(x,y-1),Vector2(x+4,y-7),Color("6d7251"),1)
  if i%3==0:draw_circle(Vector2(x+3,y-5),3,Color("8d9967"))
 # 中央都市の壁・天幕、鉱山の坑口。
 draw_rect(Rect2(115,42,36,27),Color("8a7254"));draw_rect(Rect2(119,45,28,20),Color("d9ca9c"))
 for i in 5:draw_rect(Rect2(114+i*8,40,4,6),Color("e9d6a4"))
 polygon([Vector2(125,56),Vector2(132,49),Vector2(139,56)],"a45e45")
 draw_rect(Rect2(272,48,15,11),Color("514f45"));draw_line(Vector2(272,48),Vector2(287,48),Color("c99d64"),3)
 draw_line(Vector2(280,59),Vector2(293,79),Color("77735f"),1)
 # 枠、方位記号。
 draw_rect(Rect2(2,2,341,216),Color("796b51"),false,2)
 polygon([Vector2(322,13),Vector2(315,29),Vector2(322,25),Vector2(329,29)],"565d51")

## A地域の実プレイ用ボード。構想図そのものを切り出さず、固定の地形記号だけを
## 描く。地点/道路の正本は WorldMapDB、見た目は乱数もゲーム状態も持たない。
func _draw_first_region_a() -> void:
 draw_rect(Rect2(0,0,345,220),Color("789b78"))
 polygon([Vector2(6,24),Vector2(82,9),Vector2(159,20),Vector2(220,8),Vector2(337,25),Vector2(337,206),Vector2(246,214),Vector2(159,200),Vector2(62,214),Vector2(8,175)],"9fc38d")
 # 北の雪山、川と湖。道やクリック対象ではなく、地域の傾向を示す下地。
 for row in [[44,29,24],[88,22,30],[144,31,22],[203,23,28],[270,35,24]]:
  var x:float=row[0];var y:float=row[1];var h:float=row[2]
  polygon([Vector2(x-h,y+h),Vector2(x,y-h),Vector2(x+h,y+h)],"75877f")
  polygon([Vector2(x,y-h),Vector2(x+7,y+10),Vector2(x+h,y+h)],"60736e")
  polygon([Vector2(x-7,y-2),Vector2(x,y-h+7),Vector2(x+8,y-1)],"e7eee8")
 polygon([Vector2(18,76),Vector2(92,86),Vector2(142,111),Vector2(198,126),Vector2(266,152),Vector2(326,178),Vector2(326,191),Vector2(250,165),Vector2(185,141),Vector2(130,124),Vector2(76,101),Vector2(18,94)],"6da8b0")
 draw_circle(Vector2(262,159),24,Color("6da8b0"));draw_circle(Vector2(262,159),16,Color("85bdc0"))
 # B-D近道の倒木は、実際のB-D線上だけに描く。開通後に残して別の道路を
 # 塞いで見せないよう、WorldTripの恒久状態へ表示だけを連動させる。
 if bd_blocked():
  var b:Vector2=(WorldMapDB.region_data("b_forest",WorldMapDB.FIRST_REGION_A).pos+Vector2(40,20))/2.0
  var d:Vector2=(WorldMapDB.region_data("d_yard",WorldMapDB.FIRST_REGION_A).pos+Vector2(40,20))/2.0
  var mid:=b.lerp(d,0.5)
  var along:Vector2=(d-b).normalized()
  var left:=mid-along*15.0
  var right:=mid+along*15.0
  var cross:=Vector2(-along.y,along.x)
  draw_line(left,right,Color("625745"),5)
  for t in [0.15,0.42,0.69,0.9]:
   var p:=left.lerp(right,t);draw_line(p-cross*4.0,p+cross*4.0,Color("b28c5b"),2)
 # 森、石切り場、錆びた貨物ヤード。
 for i in 34:
  var x:=32.0+float((i*23)%145);var y:=108.0+float((i*29)%86)
  draw_line(Vector2(x,y+7),Vector2(x,y-8),Color("416a48"),2)
  draw_circle(Vector2(x,y-9),5,Color("4d8052"))
 for x in [220,238,256,274]:
  polygon([Vector2(x-10,137),Vector2(x,116),Vector2(x+14,137)],"757b72")
  draw_line(Vector2(x-11,138),Vector2(x+14,138),Color("c3c0aa"),2)
 for x in [286,306,326]:
  draw_rect(Rect2(x,172,10,18),Color("8f624d"));draw_line(Vector2(x-4,172),Vector2(x+14,172),Color("c8985e"),2)
 draw_rect(Rect2(2,2,341,216),Color("4f6753"),false,2)
 polygon([Vector2(322,13),Vector2(315,29),Vector2(322,25),Vector2(329,29)],"31524a")

func bd_blocked() -> bool:
 return not bool(region_state.get("roads",{}).get("bd",{}).get("cleared",false))
