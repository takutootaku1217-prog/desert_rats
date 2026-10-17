class_name RouteNotice
extends CanvasLayer
var game
var panel:PanelContainer
var label:Label
func _ready() -> void:
 layer=16;process_mode=Node.PROCESS_MODE_ALWAYS
 panel=PanelContainer.new();panel.position=Vector2(850,195);panel.custom_minimum_size=Vector2(410,90)
 panel.add_theme_stylebox_override("panel",UIKit.box(Color("20332c",0.97),Color("e5c57c"),2,10));add_child(panel)
 var box:=VBoxContainer.new();panel.add_child(box)
 label=UIKit.lbl("",17);box.add_child(label)
 var row:=HBoxContainer.new();box.add_child(row)
 row.add_child(UIKit.button("立ち寄る",func():game.journey.set_stop(game.journey.notice,true)))
 row.add_child(UIKit.button("そのまま通過",func():game.journey.notice=""))
 panel.hide()
func _process(_delta:float) -> void:
 panel.visible=game.journey.notice!="" and not game.game_over and game.navigation!=null and game.navigation.bar.visible and not get_tree().paused
 if panel.visible:label.text="まもなく "+WorldMapDB.name_of(game.journey.notice)
