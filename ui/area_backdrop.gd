class_name AreaBackdrop
extends Control
## 小さな砂漠交易圏の地形ボード。ローカル乱数で装飾し、ゲームの抽選に触れない。
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func polygon(p:Array,c:String) -> void:draw_colored_polygon(PackedVector2Array(p),Color(c))
func _draw() -> void:
 draw_set_transform(Vector2.ZERO,0,Vector2(2,2))
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
