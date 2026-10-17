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
var _route_options: Button
var _stop_box: VBoxContainer
var _check_each: CheckBox
var _path_index := 0
var _paths: Array=[]
var _path: Array=[]
var _reserved: Array=[]
var _resume: Button
var _clear_route: Button
func _ready() -> void:
 layer=35
 process_mode=Node.PROCESS_MODE_ALWAYS
 var buttons:=CanvasLayer.new(); buttons.layer=12; add_child(buttons)
 _entry=UIKit.button("エリアマップ / 行先 (M)",open)
 _entry.position=Vector2(1000,602); _entry.custom_minimum_size=Vector2(272,34); buttons.add_child(_entry)
 _overlay=ColorRect.new(); _overlay.color=Color(0,0,0,0.8); _overlay.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(_overlay)
 var panel:=PanelContainer.new(); panel.position=Vector2(35,35); panel.custom_minimum_size=Vector2(1210,635)
 panel.add_theme_stylebox_override("panel",UIKit.box(Color("202329"),UIKit.C_ACCENT,4,20)); _overlay.add_child(panel)
 var root:=VBoxContainer.new(); root.add_theme_constant_override("separation",14); panel.add_child(root)
 root.add_child(UIKit.lbl("エリアマップ  /  砂漠交易圏",24,UIKit.C_ACCENT))
 root.add_child(UIKit.lbl("閲覧中は時間停止。目的地と経路を選択 → 横スクロールで移動。中間地点は基本通過、最終地点は必ず停車。",16))
 var cols:=HBoxContainer.new(); root.add_child(cols)
 var map:=Control.new(); map.custom_minimum_size=Vector2(690,440); cols.add_child(map)
 var terrain:=AreaBackdrop.new();terrain.custom_minimum_size=Vector2(690,440);map.add_child(terrain)
 for id in WorldMapDB.ROADS:
  if not WorldMapDB.public_road(id): continue
  var ends:Array=WorldMapDB.ROADS[id]
  var line:=Line2D.new(); line.width=5; line.default_color=Color("99724c")
  line.add_point(WorldMapDB.REGIONS[ends[0]].pos+Vector2(40,20)); line.add_point(WorldMapDB.REGIONS[ends[1]].pos+Vector2(40,20)); map.add_child(line); _roads[id]=line
 for id in WorldMapDB.REGIONS:
  if not WorldMapDB.public_region(id): continue
  var region_id:String=id
  var b:=MapPointButton.new();b.kind=WorldMapDB.NODE_KIND[id];b.pressed.connect(func():select_region(region_id))
  b.tooltip_text=WorldMapDB.name_of(id)
  var style:=UIKit.box(Color("49594a"),Color("ead19a"),3,8)
  style.set_corner_radius_all(24);b.add_theme_stylebox_override("normal",style)
  b.add_theme_stylebox_override("hover",UIKit.box(Color("697c5a"),Color("fff4ca"),3,8))
  b.position=WorldMapDB.REGIONS[id].pos+Vector2(16,-4); b.custom_minimum_size=Vector2(48,48); map.add_child(b); _nodes[id]=b
  var label:=UIKit.lbl(WorldMapDB.name_of(id),16,Color("fff1c9"));label.position=Vector2(-78,51);label.custom_minimum_size=Vector2(204,24);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(label)
 _marker=Polygon2D.new(); _marker.polygon=PackedVector2Array([Vector2(-13,-8),Vector2(6,-8),Vector2(6,-4),Vector2(13,-4),Vector2(13,5),Vector2(-13,5)]); _marker.color=Color("ffe36a"); map.add_child(_marker)
 _where=UIKit.lbl("現在地",14,Color("ffe36a")); map.add_child(_where)
 var detail:=VBoxContainer.new(); detail.custom_minimum_size=Vector2(450,0); detail.add_theme_constant_override("separation",7); cols.add_child(detail)
 _info=UIKit.lbl("",17); _info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _info.custom_minimum_size=Vector2(440,120); detail.add_child(_info)
 _route_options=UIKit.button("",_next_route);detail.add_child(_route_options)
 _stop_box=VBoxContainer.new();detail.add_child(_stop_box)
 _check_each=CheckBox.new();_check_each.text="各地点で停車して確認";detail.add_child(_check_each)
 _check_each.toggled.connect(func(value):game.journey.confirm_each=value)
 _resume=UIKit.button("予約経路を再開して閉じる",func():if game.journey.resume():close())
 detail.add_child(_resume)
 _clear_route=UIKit.button("経路を解除（道中なら次の地点で停車）",func():game.journey.cancel_route();_target="";_path=[];_refresh())
 detail.add_child(_clear_route)
 _confirm=UIKit.button("出発して閉じる",_go); detail.add_child(_confirm)
 _cancel=UIKit.button("引き返す / 移動要求を取り消す",_return); detail.add_child(_cancel)
 detail.add_child(UIKit.button("閉じる / 時間を進める",close))
 root.add_child(UIKit.lbl("凡例：家＝村・採取　樹＝枯れ木の帯　塔＝都市・街画面　つるはし＝鉱山入口（Gで鉱床へ）　車体＝現在地",15,UIKit.C_DIM))
 root.add_child(UIKit.lbl("各道路2400・標準60で約40秒。未実装の地域は今回の地図に含めません。地形は固定傾向、現地の生物・敵は表示しません。",14,UIKit.C_DIM))
 _overlay.hide()
func open() -> void:
 if not is_open():
  game.close_other_panels(self); _was_paused=get_tree().paused; get_tree().paused=true
 _overlay.show(); _target="";_path=[];_paths=[];_reserved=[]; _refresh()
func close() -> void:
 if not is_open(): return
 _overlay.hide(); _target=""; get_tree().paused=_was_paused
func is_open() -> bool: return _overlay!=null and _overlay.visible
func select_region(id: String) -> void:
 _target=id;_paths=WorldMapDB.paths(game.journey.anchor(),id);_path=[];_reserved=[]
 _path_index=0
 if not _paths.is_empty():_path=_paths[0].duplicate()
 _refresh()
func _next_route() -> void:
 if _paths.size()<2:return
 _path_index=(_path_index+1)%_paths.size();_path=_paths[_path_index].duplicate();_reserved=[];_refresh()
func _refresh() -> void:
 var w=game.world
 var on_road:bool=w.phase in ["travel","arriving","turning"]
 var selected_roads:Array=[]
 var at:String=game.journey.anchor()
 var shown:Array=_path if not _path.is_empty() else game.journey.remaining
 if _path.is_empty() and w.phase in ["departing","travel","arriving"]:at=w.origin
 for node in shown:
  selected_roads.append(WorldMapDB.road_between(at,node));at=node
 for id in _roads:
  _roads[id].default_color=Color("ffe36a") if id==w.road and w.phase!="stopped" else (Color("75dacb") if id in selected_roads else Color("99724c"))
  _roads[id].width=8 if (id==w.road and w.phase!="stopped") or id in selected_roads else 5
 _marker.visible=w.active; _where.visible=w.active
 if w.active:
  var pos:Vector2=WorldMapDB.REGIONS[w.region].pos+Vector2(45,-18)
  if on_road:
   var ends:Array=WorldMapDB.ROADS[w.road]
   pos=(WorldMapDB.REGIONS[ends[0]].pos+Vector2(45,24)).lerp(WorldMapDB.REGIONS[ends[1]].pos+Vector2(45,24),w.progress/WorldMapDB.LENGTH)
  _marker.position=pos; _where.position=pos+Vector2(12,-10)
  _where.text="現在地"
 for id in _nodes:
  _nodes[id].disabled=not w.active or w.phase not in ["stopped","departing","travel","arriving"] or WorldMapDB.paths(game.journey.anchor(),id).is_empty() or game.quarry.state!="road"
  _nodes[id].modulate=Color("75dacb") if id==_target else (Color("ffd86e") if id==w.region and w.phase=="stopped" else Color.WHITE)
 _info.text=w.status_text()
 if w.active and w.phase=="stopped" and _target=="": _info.text+="\n"+WorldMapDB.MAP_HINTS.get(w.region,"")
 _route_options.visible=not _paths.is_empty()
 _route_options.text="経路 %d / %d　次の経路を表示"%[_path_index+1,_paths.size()]
 _route_options.disabled=_paths.size()<2
 _check_each.set_pressed_no_signal(game.journey.confirm_each)
 _resume.visible=_target=="" and w.phase=="stopped" and not game.journey.remaining.is_empty()
 _resume.disabled=game.journey.hold_reason()!=""
 _resume.tooltip_text=game.journey.hold_reason()
 _clear_route.visible=_target=="" and not game.journey.remaining.is_empty()
 for child in _stop_box.get_children():_stop_box.remove_child(child);child.queue_free()
 for i in maxi(0,_path.size()-1):
  var stop:String=_path[i]
  var check:=CheckBox.new();check.text=WorldMapDB.name_of(stop)+"で停車";check.button_pressed=stop in _reserved;_stop_box.add_child(check)
  check.toggled.connect(func(value):
   if value and stop not in _reserved:_reserved.append(stop)
   elif not value:_reserved.erase(stop))
 _confirm.disabled=true
 _confirm.text="出発して閉じる" if w.phase=="stopped" else "この先の経路を更新して閉じる"
 if not w.active:
  _confirm.text="鉱床を大鉱山入口に対応付ける" if game.quarry.sheltered() else "同意して村を出発地点にする"
  _confirm.disabled=game.quarry.state not in ["road","parked","recall"] or w.phase=="legacy_recall"
  _info.text+="\n旧保存には地域情報がありません。村への対応付けは仲間と荷物の帰還後に行います。物資・距離・鉱床残量は保持し、初期物資を配り直しません。"
 elif _target!="":
  _info.text+="\n行先："+WorldMapDB.name_of(_target)+"\n"+WorldMapDB.MAP_HINTS.get(_target,"")
  var distance:float=_path.size()*WorldMapDB.LENGTH
  if w.phase in ["departing","travel","arriving"]:distance+=WorldMapDB.LENGTH-w.progress if w.direction==1 else w.progress
  _info.text+="\n経由："+" → ".join(_path.map(func(node):return WorldMapDB.name_of(node)))
  _info.text+="\n距離 %.0f / 標準走行 約%.0f秒 / 燃料 約%.1f"%[distance,distance/60.0,distance*GameData.FUEL_PER_PX]
  _info.text+="\n暖房・精錬・天候は別消費。帰還待ちや採取時間は別。"
  _confirm.disabled=_nodes[_target].disabled
 if _target=="" and not game.journey.remaining.is_empty():
  _info.text+="\n予定："+" → ".join(game.journey.remaining.map(func(node):return WorldMapDB.name_of(node)))
  _info.text+="\n停車予約："+(", ".join(game.journey.stops.map(func(node):return WorldMapDB.name_of(node))) if not game.journey.stops.is_empty() else "最終地点のみ")
 if w.active and w.region=="old_mine" and w.phase=="stopped":
  _info.text+="\n\n採取地点(G)から既存の鉱床へ。地域移動は鉱床から街道へ戻ってから選べます。"
 _cancel.disabled=w.phase=="stopped"
 if w.recalling(): _info.text+="\n"+w.ready_reason()
func _go() -> void:
 var ok:bool=game.journey.plan(_path,_reserved) if game.world.active else game.world.request_legacy_region()
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
