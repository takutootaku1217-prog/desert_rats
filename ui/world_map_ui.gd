class_name WorldMapUI
extends CanvasLayer
var game
var _overlay: ColorRect
var _info: Label
var _confirm: Button
var _cancel: Button
var _target := ""
var _was_paused := false
var _nodes := {}
var _entry: Button
var _roads := {}
var _marker: Polygon2D
var _where: Label
func _ready() -> void:
 layer=35
 process_mode=Node.PROCESS_MODE_ALWAYS
 var buttons:=CanvasLayer.new(); buttons.layer=12; add_child(buttons)
 _entry=UIKit.button("地図 / 行先 (M)",open)
 _entry.position=Vector2(1000,602); _entry.custom_minimum_size=Vector2(272,34); buttons.add_child(_entry)
 _overlay=ColorRect.new(); _overlay.color=Color(0,0,0,0.8); _overlay.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(_overlay)
 var panel:=PanelContainer.new(); panel.position=Vector2(35,35); panel.custom_minimum_size=Vector2(1210,635)
 panel.add_theme_stylebox_override("panel",UIKit.box(Color("202329"),UIKit.C_ACCENT,4,20)); _overlay.add_child(panel)
 var root:=VBoxContainer.new(); root.add_theme_constant_override("separation",14); panel.add_child(root)
 root.add_child(UIKit.lbl("第1ワールド — 街道の地図",24,UIKit.C_ACCENT))
 root.add_child(UIKit.lbl("地図表示中は時間停止。線でつながる行先を選んで出発。灰色は現在地から直接行けません。",16))
 var cols:=HBoxContainer.new(); root.add_child(cols)
 var map:=Control.new(); map.custom_minimum_size=Vector2(690,415); cols.add_child(map)
 for id in WorldMapDB.ROADS:
  if not WorldMapDB.public_road(id): continue
  var ends:Array=WorldMapDB.ROADS[id]
  var line:=Line2D.new(); line.width=5; line.default_color=Color("99724c")
  line.add_point(WorldMapDB.REGIONS[ends[0]].pos+Vector2(40,20)); line.add_point(WorldMapDB.REGIONS[ends[1]].pos+Vector2(40,20)); map.add_child(line); _roads[id]=line
 for id in WorldMapDB.REGIONS:
  if not WorldMapDB.public_region(id): continue
  var region_id:String=id
  var b:=UIKit.button(WorldMapDB.name_of(id),func(): select_region(region_id))
  b.position=WorldMapDB.REGIONS[id].pos-Vector2(45,0); b.custom_minimum_size=Vector2(180,48); map.add_child(b); _nodes[id]=b
 _marker=Polygon2D.new(); _marker.polygon=PackedVector2Array([Vector2(0,-9),Vector2(9,0),Vector2(0,9),Vector2(-9,0)]); _marker.color=Color("ffe36a"); map.add_child(_marker)
 _where=UIKit.lbl("現在地",14,Color("ffe36a")); map.add_child(_where)
 var detail:=VBoxContainer.new(); detail.custom_minimum_size=Vector2(450,0); detail.add_theme_constant_override("separation",12); cols.add_child(detail)
 _info=UIKit.lbl("",17); _info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _info.custom_minimum_size=Vector2(440,235); detail.add_child(_info)
 _confirm=UIKit.button("出発して閉じる",_go); detail.add_child(_confirm)
 _cancel=UIKit.button("引き返す / 移動要求を取り消す",_return); detail.add_child(_cancel)
 detail.add_child(UIKit.button("閉じる / 時間を進める",close))
 root.add_child(UIKit.lbl("公開範囲：4地域・4道路。残り6地域、購買・給油・修理改造・中継施設は未実装。",15,UIKit.C_DIM))
 root.add_child(UIKit.lbl("暫定設定：道路距離2400（速度60で約40秒）。道中の8採取地点と生物は往復で共有し、再訪で補充しません。",14,UIKit.C_DIM))
 _overlay.hide()
func open() -> void:
 if not is_open():
  game.close_other_panels(self); _was_paused=get_tree().paused; get_tree().paused=true
 _overlay.show(); _target=""; _refresh()
func close() -> void:
 if not is_open(): return
 _overlay.hide(); _target=""; get_tree().paused=_was_paused
func is_open() -> bool: return _overlay!=null and _overlay.visible
func select_region(id: String) -> void:
 _target=id; _refresh()
func _refresh() -> void:
 var w=game.world
 var on_road:bool=w.phase in ["travel","arriving","turning"]
 var selected:String=WorldMapDB.road_between(w.region,_target)
 for id in _roads:
  _roads[id].default_color=Color("ffe36a") if id==w.road and w.phase!="stopped" else (Color("75dacb") if id==selected else Color("99724c"))
  _roads[id].width=8 if (id==w.road and w.phase!="stopped") or id==selected else 5
 _marker.visible=w.active; _where.visible=w.active
 if w.active:
  var pos:Vector2=WorldMapDB.REGIONS[w.region].pos+Vector2(45,-18)
  if on_road:
   var ends:Array=WorldMapDB.ROADS[w.road]
   pos=(WorldMapDB.REGIONS[ends[0]].pos+Vector2(45,24)).lerp(WorldMapDB.REGIONS[ends[1]].pos+Vector2(45,24),w.progress/WorldMapDB.LENGTH)
  _marker.position=pos; _where.position=pos+Vector2(12,-10)
  _where.text="現在地"
 for id in _nodes:
  _nodes[id].disabled=not w.active or w.phase!="stopped" or not WorldMapDB.public_road(WorldMapDB.road_between(w.region,id)) or game.quarry.state!="road"
  _nodes[id].modulate=Color("75dacb") if id==_target else (Color("ffd86e") if id==w.region and w.phase=="stopped" else Color.WHITE)
 _info.text=w.status_text()
 if w.active and w.phase=="stopped": _info.text+="\n"+WorldMapDB.REGIONS[w.region].get("description","")
 _confirm.disabled=true
 _confirm.text="出発して閉じる"
 if not w.active:
  _confirm.text="鉱床を大鉱山入口に対応付ける" if game.quarry.sheltered() else "同意して村を出発地点にする"
  _confirm.disabled=game.quarry.state not in ["road","parked","recall"] or w.phase=="legacy_recall"
  _info.text+="\n旧保存には地域情報がありません。村への対応付けは仲間と荷物の帰還後に行います。物資・距離・鉱床残量は保持し、初期物資を配り直しません。"
 elif _target!="":
  _info.text+="\n\n行先："+WorldMapDB.name_of(_target)+"\n屋外の仲間と荷物が戻ってから出発します。"
  _confirm.disabled=_nodes[_target].disabled
 if w.active and w.region=="old_mine" and w.phase=="stopped":
  _info.text+="\n\n採取地点(G)から既存の鉱床へ。地域移動は鉱床から街道へ戻ってから選べます。"
 _cancel.disabled=w.phase=="stopped"
 if w.recalling(): _info.text+="\n"+w.ready_reason()
func _go() -> void:
 var ok:bool=game.world.request(_target) if game.world.active else game.world.request_legacy_region()
 if ok: close()
 else: _refresh()
func _return() -> void:
 if game.world.cancel_or_return(): close()
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode==KEY_M:
   if is_open(): close()
   else: open()
   get_viewport().set_input_as_handled()
  elif is_open() and event.keycode==KEY_ESCAPE:
   close(); get_viewport().set_input_as_handled()
