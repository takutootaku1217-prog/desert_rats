class_name MapPointButton
extends Button
var kind := "village"
func _draw() -> void:
 var c:=Color("fff1ca") if not disabled else Color("9f9987")
 var center:=size/2
 match kind:
  "city":
   for x in [-10,0,10]:draw_rect(Rect2(center+Vector2(x-3,-9),Vector2(6,18)),c)
   draw_line(center+Vector2(-13,9),center+Vector2(13,9),c,3)
  "grove":
   draw_line(center+Vector2(0,11),center+Vector2(0,-10),c,3)
   draw_line(center+Vector2(0,0),center+Vector2(-10,-8),c,3)
   draw_line(center+Vector2(0,-3),center+Vector2(9,-12),c,3)
  "mine":
   draw_line(center+Vector2(-10,10),center+Vector2(10,-10),c,4)
   draw_polyline(PackedVector2Array([center+Vector2(-4,-12),center+Vector2(7,-9),center+Vector2(13,3)]),c,3)
  "yard":
   draw_rect(Rect2(center+Vector2(-13,-5),Vector2(26,16)),c,false,3)
   for x in [-8,0,8]:draw_line(center+Vector2(x,-5),center+Vector2(x,11),c,2)
   draw_line(center+Vector2(-15,12),center+Vector2(15,12),c,3)
  _:
   draw_colored_polygon(PackedVector2Array([center+Vector2(-13,-1),center+Vector2(0,-12),center+Vector2(13,-1)]),c)
   draw_rect(Rect2(center+Vector2(-8,0),Vector2(16,11)),c)
   draw_rect(Rect2(center+Vector2(-2,5),Vector2(4,6)),Color("474f43"))
