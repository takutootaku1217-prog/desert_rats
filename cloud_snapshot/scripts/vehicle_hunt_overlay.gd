class_name VehicleHuntOverlay
extends Node2D
var game
func _process(_delta:float) -> void:queue_redraw()
func _draw() -> void:
 if game==null or game.vehicle_hunt==null:return
 var rig=game.vehicle_hunt
 var start:=Vector2(GameData.RAMP_FOOT.x,GameData.LO_Y-55.0)
 if rig.beam_time>0.0:draw_line(start,rig.beam_to,Color("f8da86"),3.0)
 if not rig.cargo.is_empty():
  var end:Vector2=rig.cargo_origin.lerp(start,clampf(rig.cargo_progress/rig.RECOVERY_SECONDS,0.0,1.0))
  draw_line(start,end,Color("d6ba88"),2.0)
  GameData.draw_creature(self,rig.cargo_species,0,end,1.0,true)
