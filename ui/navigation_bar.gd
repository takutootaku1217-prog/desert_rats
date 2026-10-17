class_name NavigationBar
extends CanvasLayer
## 常設の入口だけを集約。ゲーム処理・各画面のキー操作は既存UIへ委譲する。
var game
var bar: PanelContainer
var popup: PanelContainer
var dismiss: Control
var buttons := {}
var groups := {}
var selected := ""
var field_status: Label
var return_result: Label

func _ready() -> void:
 layer = 14
 process_mode = Node.PROCESS_MODE_ALWAYS
 # 旧入口は画面本体から分離されている。モーダル内の操作には触れない。
 for owner in [game.policy,game.expedition_ui,game.build_ui,game.room_ui,game.inventory_ui,game.craft_ui,game.quarry_ui,game.save_ui,game.map_ui,game.view_switch,game.ui]:
  for child in owner.get_children():
   if child is Button: child.hide()
   if child is CanvasLayer:
    for entry in child.get_children():
     if entry is Button: entry.hide()
 dismiss = Control.new()
 dismiss.set_anchors_preset(Control.PRESET_FULL_RECT)
 dismiss.mouse_filter = Control.MOUSE_FILTER_STOP
 dismiss.gui_input.connect(func(event):
  if event is InputEventMouseButton and event.pressed:
   close(); get_viewport().set_input_as_handled())
 add_child(dismiss); dismiss.hide()
 popup = PanelContainer.new()
 popup.add_theme_stylebox_override("panel",UIKit.box(Color("1b1e24",0.98),UIKit.C_ACCENT,2,10))
 add_child(popup); popup.hide()
 bar = PanelContainer.new()
 bar.position = Vector2(352,650)
 bar.custom_minimum_size = Vector2(916,62)
 bar.add_theme_stylebox_override("panel",UIKit.box(Color("1b1e24",0.97),Color("636b7a"),2,6))
 add_child(bar)
 var row := HBoxContainer.new(); row.add_theme_constant_override("separation",6);bar.add_child(row)
 var labels := ["地図","探索","拠点","仲間","物資","メニュー"]
 var icons := ["shield_drive","fatigue","shield_hull","mental_normal","weight","shield_machine"]
 for i in labels.size():
  var label:String=labels[i]
  var b := UIKit.button(label,func(): activate(label))
  b.icon=GameData.tex("res://assets/ui/%s.png"%icons[i]);b.expand_icon=true;b.add_theme_constant_override("icon_max_width",28)
  b.alignment=HORIZONTAL_ALIGNMENT_CENTER;b.custom_minimum_size=Vector2(144,48);b.add_theme_font_size_override("font_size",17)
  row.add_child(b);buttons[label]=b
 buttons["地図"].tooltip_text="地図 / 行先 (M)"
 buttons["仲間"].tooltip_text="仲間の管理 (C)"
 _group("探索",[["採取地点 (G)",game.quarry_ui.open],["遠征 (X)",game.expedition_ui.open]])
 var field_group:VBoxContainer=groups["探索"]
 field_status=UIKit.lbl("",15);field_group.add_child(field_status)
 var controls:=HBoxContainer.new();field_group.add_child(controls)
 for entry in [["通常・再開","normal"],["後退（警戒）","alert"],["撤退・呼戻し","recall"]]:
  var mode:String=entry[1]
  var b:=UIKit.button(entry[0],func():game.operations.set_stance(mode))
  b.custom_minimum_size=Vector2(150,40);controls.add_child(b)
 var hint:=UIKit.lbl("警戒は近場の採取を継続。撤退は荷物を持って帰還。仲間を選び生物を右クリックすると明示攻撃（近距離のみ）。",13,UIKit.C_DIM)
 hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.custom_minimum_size.x=470;field_group.add_child(hint)
 return_result=UIKit.lbl("",13);return_result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;return_result.custom_minimum_size.x=470;field_group.add_child(return_result)
 _group("拠点",[["街 / 中央都市",game.town_ui.request_open],["建設 (B)",game.build_ui.open],["部屋 (R)",game.room_ui.open],["製作 (F)",game.craft_ui.open],["内外装",func(): activate("内外装")]])
 _group("内外装",[["外装 (O)",func(): game.base_view.set_mode(BaseView.Mode.EXTERIOR)],["内装 (I)",func(): game.base_view.set_mode(BaseView.Mode.INTERIOR)],["戻る",func(): activate("拠点")]])
 _group("物資",[["倉庫 (Tab)",game.inventory_ui.open],["製作 (F)",game.craft_ui.open]])
 var stock_group:VBoxContainer=groups["物資"]
 game.status._stock.reparent(stock_group);stock_group.move_child(game.status._stock,0)
 game.status._totals.reparent(stock_group);stock_group.move_child(game.status._totals,1)
 _group("メニュー",[["運営の方針 (P)",game.policy.toggle],["保存 / 続きから",game.save_ui.open]])

func _group(id:String, actions:Array) -> void:
 var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);popup.add_child(box);groups[id]=box
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);box.add_child(row)
 for action in actions:
  var callback:Callable=action[1]
  var b:=UIKit.button(action[0],func(): close();callback.call())
  b.custom_minimum_size=Vector2(140,44);b.alignment=HORIZONTAL_ALIGNMENT_CENTER;row.add_child(b)
 box.hide()

func activate(id:String) -> void:
 if game.game_over: return
 if id=="地図": close();game.map_ui.open();return
 if id=="仲間": close();game.detail.toggle();return
 if selected==id: close();return
 game.close_other_panels(self)
 selected=id
 for name_ in groups: groups[name_].visible=name_==id
 popup.reset_size();popup.show();dismiss.show()
 _position_popup()
 for name_ in buttons: UIKit.style(buttons[name_],name_==id or (name_=="拠点" and id=="内外装"))

func _position_popup() -> void:
 var anchor:String="拠点" if selected=="内外装" else selected
 var x:float=buttons[anchor].get_global_rect().position.x if buttons.has(anchor) else bar.position.x
 popup.position=Vector2(clampf(x,352,1268-popup.size.x),642-popup.size.y)

func close() -> void:
 selected=""
 if popup!=null: popup.hide();dismiss.hide()
 for name_ in buttons: UIKit.style(buttons[name_],false)

func _process(_delta:float) -> void:
 var modal:=false
 for owner in [game.policy,game.expedition_ui,game.build_ui,game.room_ui,game.inventory_ui,game.craft_ui,game.quarry_ui,game.save_ui,game.map_ui,game.town_ui,game.detail,game.crew_alerts]:
  if owner._overlay.visible: modal=true;break
 bar.visible=not modal and not game.game_over
 if modal or game.game_over: close()
 if popup.visible: _position_popup()
 if field_status!=null: field_status.text=game.operations.status_text()
 if return_result!=null: return_result.text=game.operations.result_text()
 buttons["仲間"].tooltip_text="仲間 %d人 (C)"%game.workers.size()
 buttons["物資"].modulate=Color("ffb078") if game.hungry or game.storage.weight_ratio()>=0.9 else Color.WHITE

func _unhandled_input(event:InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE and popup.visible:
  close();get_viewport().set_input_as_handled()
