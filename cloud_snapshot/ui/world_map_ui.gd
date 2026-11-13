class_name WorldMapUI
extends CanvasLayer
var game
var _overlay: ColorRect
var _info: Label
var _departure_error := ""
var _confirm: Button
var _cancel: Button
var _target := ""
var _was_paused := false
var _nodes := {}
var _entry: Button
var _roads := {}
var _road_outlines := {}
var _node_labels := {}
var _marker: Polygon2D
var _pilot_marker: Line2D
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
var _land_box: VBoxContainer
var _land_action := ""
var _npc_action := ""
var _land_site := ""
var _land_revision := 0 # Transient UI generation; never saved.
var _title: Label
var _terrain: AreaBackdrop
var _target_marker: Label
var _summary_scroll: ScrollContainer
var _land_scroll: ScrollContainer
var _route_study_toggle: Button
var _route_study_box: VBoxContainer
var _route_study_open := false
var _c_reopen: Button
func _ready() -> void:
 var profile:String=game.world.map_profile
 var first_region:=WorldMapDB.is_first_region(profile)
 layer=35
 process_mode=Node.PROCESS_MODE_ALWAYS
 var buttons:=CanvasLayer.new(); buttons.layer=12; add_child(buttons)
 _entry=UIKit.button("A地域マップ（検証） / 行先 (M)" if WorldMapDB.is_first_region(profile) else "エリアマップ / 行先 (M)",open)
 _entry.position=Vector2(1000,602); _entry.custom_minimum_size=Vector2(272,34); buttons.add_child(_entry)
 _overlay=ColorRect.new(); _overlay.color=Color(0,0,0,0.8); _overlay.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(_overlay)
 var panel:=PanelContainer.new(); panel.position=Vector2(35,35); panel.custom_minimum_size=Vector2(1210,635)
 panel.add_theme_stylebox_override("panel",UIKit.box(Color("202329"),UIKit.C_ACCENT,4,20)); _overlay.add_child(panel)
 var root:=VBoxContainer.new(); root.add_theme_constant_override("separation",14); panel.add_child(root)
 _title=UIKit.lbl("第1地域 A〜D ＋ 次地域入口（試遊版）" if WorldMapDB.is_first_region(profile) else "エリアマップ  /  砂漠交易圏",24,UIKit.C_ACCENT);root.add_child(_title)
 root.add_child(UIKit.lbl("閲覧中は時間停止。目的地と経路を選択 → 横スクロールで移動。中間地点は基本通過、最終地点は必ず停車。",16))
 var cols:=HBoxContainer.new(); root.add_child(cols)
 var map:=Control.new(); map.custom_minimum_size=Vector2(690,440); cols.add_child(map)
 _terrain=AreaBackdrop.new();_terrain.profile=profile;_terrain.region_state=game.world.region_state;_terrain.custom_minimum_size=Vector2(690,440);map.add_child(_terrain)
 for id in WorldMapDB.roads(profile):
  if not WorldMapDB.map_road_visible(id,profile): continue
  var ends:Array=WorldMapDB.road_ends(id,profile)
  if first_region:
   var outline:=Line2D.new(); outline.width=9; outline.default_color=Color("294137")
   outline.add_point(WorldMapDB.region_data(ends[0],profile).pos+Vector2(40,20)); outline.add_point(WorldMapDB.region_data(ends[1],profile).pos+Vector2(40,20)); map.add_child(outline); _road_outlines[id]=outline
  var line:=Line2D.new(); line.width=5; line.default_color=Color("99724c")
  line.add_point(WorldMapDB.region_data(ends[0],profile).pos+Vector2(40,20)); line.add_point(WorldMapDB.region_data(ends[1],profile).pos+Vector2(40,20)); map.add_child(line); _roads[id]=line
 for id in WorldMapDB.regions(profile):
  if not WorldMapDB.public_region(id,profile): continue
  var region_id:String=id
  var b:=MapPointButton.new();b.kind=WorldMapDB.node_kind(id,profile);b.pressed.connect(func():select_region(region_id))
  b.tooltip_text=WorldMapDB.name_of(id,profile)
  var style:=UIKit.box(Color("49594a"),Color("ead19a"),3,8)
  style.set_corner_radius_all(24);b.add_theme_stylebox_override("normal",style)
  b.add_theme_stylebox_override("hover",UIKit.box(Color("697c5a"),Color("fff4ca"),3,8))
  b.position=WorldMapDB.region_data(id,profile).pos+Vector2(16,-4); b.custom_minimum_size=Vector2(48,48); map.add_child(b); _nodes[id]=b
  var label:=UIKit.lbl(WorldMapDB.name_of(id,profile),16,Color("fff1c9"));var label_width:=204.0
  var label_x:=clampf(-78.0,4.0-b.position.x,map.custom_minimum_size.x-4.0-b.position.x-label_width)
  label.position=Vector2(label_x,51);label.custom_minimum_size=Vector2(label_width,24);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(label);_node_labels[id]=label
 _marker=Polygon2D.new(); _marker.polygon=PackedVector2Array([Vector2(-13,-8),Vector2(6,-8),Vector2(6,-4),Vector2(13,-4),Vector2(13,5),Vector2(-13,5)]); _marker.color=Color("ffe36a"); map.add_child(_marker)
 _pilot_marker=Line2D.new();_pilot_marker.width=3;_pilot_marker.default_color=Color("ffe36a");_pilot_marker.add_point(Vector2(-29,-29));_pilot_marker.add_point(Vector2(29,-29));_pilot_marker.add_point(Vector2(29,29));_pilot_marker.add_point(Vector2(-29,29));_pilot_marker.add_point(Vector2(-29,-29));_pilot_marker.hide();map.add_child(_pilot_marker)
 _where=UIKit.lbl("現在地",14,Color("ffe36a")); map.add_child(_where)
 _target_marker=UIKit.lbl("行先",14,Color("75dacb"));_target_marker.mouse_filter=Control.MOUSE_FILTER_IGNORE;map.add_child(_target_marker)
 var summary_parent:Container
 var controls_parent:Container
 var normal_detail:VBoxContainer
 if first_region:
  # A地域では、移動の要点と出発/取消/閉じるを固定し、件数が増える地点保管だけを
  # 独立してスクロールさせる。通常地図の既存クリック位置は変えない。
  var pilot_detail:=VBoxContainer.new();pilot_detail.custom_minimum_size=Vector2(450,440);pilot_detail.add_theme_constant_override("separation",7);cols.add_child(pilot_detail)
  _summary_scroll=ScrollContainer.new();_summary_scroll.custom_minimum_size=Vector2(450,176);_summary_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;pilot_detail.add_child(_summary_scroll)
  var summary:=VBoxContainer.new();summary.custom_minimum_size=Vector2(430,0);summary.add_theme_constant_override("separation",7);_summary_scroll.add_child(summary);summary_parent=summary
  var primary:=VBoxContainer.new();primary.add_theme_constant_override("separation",4);pilot_detail.add_child(primary);controls_parent=primary
  _land_scroll=ScrollContainer.new();_land_scroll.custom_minimum_size=Vector2(450,96);_land_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_land_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;pilot_detail.add_child(_land_scroll)
  _land_box=VBoxContainer.new();_land_box.custom_minimum_size=Vector2(430,0);_land_box.add_theme_constant_override("separation",4);_land_scroll.add_child(_land_box)
 else:
  normal_detail=VBoxContainer.new();normal_detail.custom_minimum_size=Vector2(450,0);normal_detail.add_theme_constant_override("separation",7);cols.add_child(normal_detail);summary_parent=normal_detail;controls_parent=normal_detail
 _info=UIKit.lbl("",17); _info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _info.custom_minimum_size=Vector2(440,120); summary_parent.add_child(_info)
 _route_options=UIKit.button("",_next_route);summary_parent.add_child(_route_options)
 if first_region:
  _route_study_toggle=UIKit.button("経路比較（試作）",_toggle_route_study);summary_parent.add_child(_route_study_toggle)
  _route_study_box=VBoxContainer.new();_route_study_box.name="RouteStudy";_route_study_box.add_theme_constant_override("separation",4);summary_parent.add_child(_route_study_box)
 _stop_box=VBoxContainer.new();summary_parent.add_child(_stop_box)
 if not first_region:
  _land_box=VBoxContainer.new();_land_box.add_theme_constant_override("separation",4);normal_detail.add_child(_land_box)
 _check_each=CheckBox.new();_check_each.text="各地点で停車して確認";summary_parent.add_child(_check_each)
 _check_each.toggled.connect(func(value):game.journey.confirm_each=value)
 _resume=UIKit.button("予約経路を再開して閉じる",_resume_departure)
 summary_parent.add_child(_resume)
 _clear_route=UIKit.button("経路を解除（道中なら次の地点で停車）",func():game.journey.cancel_route();_target="";_path=[];_refresh())
 summary_parent.add_child(_clear_route)
 if first_region:controls_parent.add_child(UIKit.lbl("移動（地点を選択して出発）",14,UIKit.C_ACCENT))
 if first_region:
  _c_reopen=UIKit.button("Cの入場選択を開く",_reopen_c_choice)
  _c_reopen.name="CReopenChoice"
  _c_reopen.tooltip_text="現在停車中のC入口へ戻ります。採掘・ボス等の選択画面を開くだけで、入場や予約経路の変更は行いません。"
  controls_parent.add_child(_c_reopen)
 _confirm=UIKit.button("出発して閉じる",_go); controls_parent.add_child(_confirm)
 _cancel=UIKit.button("引き返す / 移動要求を取り消す",_return); controls_parent.add_child(_cancel)
 controls_parent.add_child(UIKit.button("閉じる / 時間を進める",close))
 root.add_child(UIKit.lbl("凡例：家＝開始地点　樹＝森　つるはし＝採石場　貨物＝ヤード　車体＝現在地　青緑＝行先" if WorldMapDB.is_first_region(profile) else "凡例：家＝村・採取　樹＝枯れ木の帯　塔＝都市・街画面　つるはし＝鉱山入口（Gで鉱床へ）　車体＝現在地",15,UIKit.C_DIM))
 root.add_child(UIKit.lbl("茶＝通行可　赤茶＝未解放　黄緑＝整地済み　青緑＝選択経路　黄＝走行中。B–Dは倒木撤去、旧緑道は第1地域突破で解放。" if first_region else "各道路2400・標準60で約40秒。未実装の地域は今回の地図に含めません。地形は固定傾向、現地の生物・敵は表示しません。",14,UIKit.C_DIM))
 _overlay.hide()
func open() -> void:
 _departure_error=""
 if not is_open():
  game.close_other_panels(self); _was_paused=get_tree().paused; get_tree().paused=true
 _overlay.show(); _target="";_path=[];_paths=[];_reserved=[]; _refresh()
 if _summary_scroll!=null:_summary_scroll.scroll_vertical=0
 if _land_scroll!=null:_land_scroll.scroll_vertical=0
func close() -> void:
 _land_revision+=1
 _npc_action="";game.world.npc_service.cancel_quote()
 _land_action="";_land_site=""
 if not is_open(): return
 _overlay.hide(); _target=""; game.set_source_focus(-1); get_tree().paused=_was_paused
func is_open() -> bool: return _overlay!=null and _overlay.visible
func _reopen_c_choice() -> void:
 if not is_open() or game.mine_arrival_gate==null:return
 game.mine_arrival_gate.reopen_from_map()
func select_region(id: String) -> void:
 _target=id;_paths=WorldMapDB.paths(game.journey.anchor(),id,game.world.map_profile,game.world.region_state,game.world.region_completion);_path=[];_reserved=[]
 _path_index=0
 if not _paths.is_empty():_path=_paths[0].duplicate()
 _refresh()
func _next_route() -> void:
 if _paths.size()<2:return
 _path_index=(_path_index+1)%_paths.size();_path=_paths[_path_index].duplicate();_reserved=[];_refresh()
func _refresh() -> void:
 var w=game.world
 if _c_reopen!=null:
  _c_reopen.visible=game.mine_arrival_gate!=null and game.mine_arrival_gate.can_reopen_from_map()
 var profile:String=w.map_profile
 var source_focus: int = game.source_focus_item
 var source_regions: Array = WorldMapDB.known_regions_for_item(profile, source_focus) if source_focus >= 0 else []
 if _terrain!=null:
  _terrain.region_state=w.region_state
  _terrain.queue_redraw()
 var on_road:bool=w.phase in ["travel","arriving","turning"]
 var selected_roads:Array=[]
 var at:String=game.journey.anchor()
 var shown:Array=_path if not _path.is_empty() else game.journey.remaining
 if _path.is_empty() and w.phase in ["departing","travel","arriving"]:at=w.origin
 for node in shown:
  selected_roads.append(WorldMapDB.road_between(at,node,profile));at=node
 for id in _roads:
  var blocked:bool=not WorldMapDB.public_road(id,profile,w.region_state,w.region_completion)
  var graded:bool=WorldMapDB.road_is_graded(id,profile,w.region_state)
  var road_color:=Color("ffe36a") if id==w.road and w.phase!="stopped" else (Color("75dacb") if id in selected_roads else (Color("d8f29c") if graded else (Color("9a5544") if blocked else Color("99724c"))))
  var road_width:=8 if (id==w.road and w.phase!="stopped") or id in selected_roads else (7 if graded and WorldMapDB.is_first_region(profile) else 5)
  _roads[id].default_color=road_color;_roads[id].width=road_width
  if _road_outlines.has(id):_road_outlines[id].width=road_width+4;_road_outlines[id].default_color=Color("294137")
 var pilot:=WorldMapDB.is_first_region(profile)
 _marker.visible=w.active and not pilot; _pilot_marker.visible=w.active and pilot; _where.visible=w.active
 if w.active:
  var pos:Vector2=WorldMapDB.region_data(w.region,profile).pos+Vector2(45,-18)
  if on_road:
   var ends:Array=WorldMapDB.road_ends(w.road,profile)
   pos=(WorldMapDB.region_data(ends[0],profile).pos+Vector2(45,24)).lerp(WorldMapDB.region_data(ends[1],profile).pos+Vector2(45,24),w.progress/w.road_length())
  if pilot:
   if not on_road:pos=WorldMapDB.region_data(w.region,profile).pos+Vector2(40,20)
   else:
    var pilot_ends:Array=WorldMapDB.road_ends(w.road,profile)
    pos=(WorldMapDB.region_data(pilot_ends[0],profile).pos+Vector2(40,20)).lerp(WorldMapDB.region_data(pilot_ends[1],profile).pos+Vector2(40,20),w.progress/w.road_length())
   _pilot_marker.position=pos;_where.position=pos+Vector2(-20,-43)
  else:
   _marker.position=pos;_where.position=pos+Vector2(12,-10)
  _where.text="現在地"
 _target_marker.visible=_target!=""
 if _target_marker.visible:
  _target_marker.position=WorldMapDB.region_data(_target,profile).pos+Vector2(44,-24)
 for id in _nodes:
  _nodes[id].disabled=not w.active or w.phase not in ["stopped","departing","travel","arriving"] or WorldMapDB.paths(game.journey.anchor(),id,profile,w.region_state,w.region_completion).is_empty() or game.quarry.state!="road"
  _nodes[id].modulate=Color("75dacb") if id==_target else (Color("ffb75d") if id in source_regions else (Color.WHITE if pilot else (Color("ffd86e") if id==w.region and w.phase=="stopped" else Color.WHITE)))
  var node_tip := WorldMapDB.name_of(id, profile)
  var locked:bool=not WorldMapDB.region_accessible(id,profile,w.region_state,w.region_completion)
  _node_labels[id].text=WorldMapDB.name_of(id,profile)+("\n[未解放：第1地域突破後]" if locked else "")
  if locked:node_tip+="\n未解放：ボス撃破・帰還確定＋B–D再接続が必要です。"
  if id in source_regions:
   node_tip += "\n" + ItemDB.name_of(source_focus) + " の採取候補"
  _nodes[id].tooltip_text=node_tip
 _info.text=w.status_text()
 if pilot:
  var goal:Dictionary=w.region_goal_snapshot()
  _info.text+="\n"+goal.title+"\n"+goal.text
 if _departure_error!="":_info.text+="\n"+_departure_error
 if source_focus >= 0:
  var source_names: Array = source_regions.map(func(region): return WorldMapDB.name_of(region, profile))
  _info.text += "\n採取先を確認中: %s / 既知: %s" % [ItemDB.name_of(source_focus), ", ".join(source_names) if not source_names.is_empty() else "なし"]
 if w.active and w.phase=="stopped" and _target=="": _info.text+="\n"+WorldMapDB.hints(profile).get(w.region,"")
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
  var check:=CheckBox.new();check.text=WorldMapDB.name_of(stop,profile)+"で停車";check.button_pressed=stop in _reserved;_stop_box.add_child(check)
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
  _info.text+="\n行先："+WorldMapDB.name_of(_target,profile)+"\n"+WorldMapDB.hints(profile).get(_target,"")
  if not WorldMapDB.region_accessible(_target,profile,w.region_state,w.region_completion):_info.text+="\n未解放：ボス撃破・帰還確定＋B–D再接続が必要です。"
  var distance:float=_path_distance(_path,game.journey.anchor(),profile,w.region_state)
  if w.phase in ["departing","travel","arriving"]:distance+=w.road_length()-w.progress if w.direction==1 else w.progress
  _info.text+="\n経由："+" → ".join(_path.map(func(node):return WorldMapDB.name_of(node,profile)))
  if WorldMapDB.is_first_region(profile):
   _info.text+="\n距離 %.0f / 標準走行 約%.0f秒"%[distance,distance/60.0]
   _info.text+="\n"+_fuel_estimate_text(distance)
   _info.text+="\n未来の天候、暖房・精錬・燃料漏れは別消費。帰還待ちや採取時間は別。"
  else:
   _info.text+="\n距離 %.0f / 標準走行 約%.0f秒 / 燃料 約%.1f"%[distance,distance/60.0,distance*GameData.FUEL_PER_PX]
   _info.text+="\n暖房・精錬・天候は別消費。帰還待ちや採取時間は別。"
  _confirm.disabled=_nodes[_target].disabled
 if _target=="" and not game.journey.remaining.is_empty():
  _info.text+="\n予定："+" → ".join(game.journey.remaining.map(func(node):return WorldMapDB.name_of(node,profile)))
  _info.text+="\n停車予約："+(", ".join(game.journey.stops.map(func(node):return WorldMapDB.name_of(node,profile))) if not game.journey.stops.is_empty() else "最終地点のみ")
 if w.active and w.region=="old_mine" and w.phase=="stopped":
  _info.text+="\n\n採取地点(G)から既存の鉱床へ。地域移動は鉱床から街道へ戻ってから選べます。"
 _cancel.disabled=w.phase=="stopped"
 if w.recalling(): _info.text+="\n"+w.ready_reason()
 _refresh_route_study()
 _refresh_land()
func _toggle_route_study() -> void:
 _route_study_open=not _route_study_open
 _refresh_route_study()
 if _route_study_open:
  call_deferred("_focus_route_study")
func _focus_route_study() -> void:
 if _summary_scroll!=null:
  _summary_scroll.scroll_vertical=1000000
func _refresh_route_study() -> void:
 if _route_study_box==null:return
 for child in _route_study_box.get_children():
  _route_study_box.remove_child(child);child.queue_free()
 if not game.world.first_region():
  _route_study_box.hide()
  return
 _route_study_box.visible=_route_study_open
 if _route_study_toggle!=null:
  _route_study_toggle.text="経路比較（試作）: 閉じる" if _route_study_open else "経路比較（試作）: 開く"
 if not _route_study_open:return
 _route_study_box.add_child(UIKit.lbl("経路比較（表示のみ）",14,UIKit.C_ACCENT))
 for raw_card in WorldMapDB.first_region_route_study(game.world.region_state):
  var card:Dictionary=Dictionary(raw_card)
  var status:String=str(card.get("state","available"))
  var title:String=str(card.get("title",card.get("id","route")))
  var effect:String=str(card.get("effect",""))
  var cost:Dictionary=Dictionary(card.get("cost",{}))
  var suffix:String="将来案・未実装" if bool(card.get("preview_only",false)) else ("完了" if status=="complete" else ("要整備" if status=="blocked" else "比較可"))
  var row:=UIKit.lbl("%s  [%s]\n%s%s"%[title,suffix,effect,("\n"+_cost_text(cost)) if not cost.is_empty() else ""],12,UIKit.C_DIM)
  row.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.custom_minimum_size=Vector2(420,0);_route_study_box.add_child(row)
func _path_distance(path:Array,start:String,profile:String,state:Dictionary) -> float:
 var distance:=0.0
 var at:=start
 for node in path:
  distance+=WorldMapDB.road_length(WorldMapDB.road_between(at,node,profile),profile,state)
  at=node
 return distance
func _fuel_estimate(distance:float) -> float:
 var event_mult:float=game.director.burn_mult() if game.director!=null else 1.0
 var vehicle_mult:float=game.base.vehicle_fuel_mult() if game.base!=null else 1.0
 return distance*GameData.FUEL_PER_PX*event_mult*vehicle_mult
func _fuel_estimate_text(distance:float) -> String:
 var estimate:float=_fuel_estimate(distance)
 var tank:float=game.base.fuel if game.base!=null else 0.0
 var event_mult:float=game.director.burn_mult() if game.director!=null else 1.0
 var vehicle_mult:float=game.base.vehicle_fuel_mult() if game.base!=null else 1.0
 var shortage:=maxf(0.0,estimate-tank)
 var warning: String="　不足 %.1f"%shortage if shortage>0.0001 else "　足ります"
 return "走行燃料見込 %.1f / タンク %.1f（現在倍率 x%.2f）%s"%[estimate,tank,event_mult*vehicle_mult,warning]
func _clear_land_box() -> void:
 for child in _land_box.get_children():
  _land_box.remove_child(child);child.queue_free()
func _item_name(item:int) -> String:
 return GameData.ITEM_NAMES.get(item,str(item))
func _cost_text(cost:Dictionary) -> String:
 if cost.is_empty():return "費用なし"
 var rows:Array=[]
 for item in cost:rows.append(_item_name(item)+"×"+str(cost[item]))
 return "費用："+" / ".join(rows)
func _cost_availability_text(cost:Dictionary) -> String:
 if cost.is_empty():return "車両在庫：費用なし"
 var rows:Array=[]
 for item in cost:
  var needed:int=int(cost[item])
  var available:int=game.warehouse_discard_available(item)
  var shortage:=maxi(0,needed-available)
  rows.append(_item_name(item)+" "+str(available)+"/"+str(needed)+("（不足"+str(shortage)+"）" if shortage>0 else ""))
 return "車両在庫（予約分を除く）："+" / ".join(rows)
func _offer_land_preview(action:String,label:String) -> void:
 var site:String=game.world.region
 var revision:=_land_revision
 _land_box.add_child(UIKit.button(label,func():
  if not _land_context_current(site,revision):
   _refresh();return
  _land_action=action;_land_site=site
  _refresh()
  call_deferred("_reveal_land_preview",site,action,_land_revision)))
func _reveal_land_preview(site:String,action:String,revision:int) -> void:
 if not _land_reveal_current(site,action,revision):return
 # The rebuilt VBox may have grown while the ScrollContainer still has its old
 # range. Sort the parent, then scroll on the following frame, even while paused.
 _land_scroll.queue_sort()
 await get_tree().process_frame
 if not _land_reveal_current(site,action,revision):return
 _land_scroll.scroll_vertical=1000000
func _land_reveal_current(site:String,action:String,revision:int) -> bool:
 return _land_scroll!=null and is_open() and _land_action==action and _land_site==site and _land_context_current(site,revision)
func _land_context_current(site:String,revision:int) -> bool:
 return revision==_land_revision and game.world.land_operation_reason(site).is_empty()
func _refresh_land() -> void:
 if _land_box==null:return
 _land_revision+=1
 _clear_land_box()
 var w=game.world
 if _land_site!="" and _land_site!=w.region:_land_action="";_land_site=""
 if _land_action!="" and _land_site=="":_land_site=w.region
 if not w.first_region():return
 if w.region!=NpcFuelFacility.SITE:_npc_action="";w.npc_service.cancel_quote()
 var header:=UIKit.lbl("土地利用・地点保管（検証）",15,UIKit.C_ACCENT);_land_box.add_child(header)
 var reason:String=w.land_operation_reason()
 if not reason.is_empty():
  _land_box.add_child(UIKit.lbl(reason,13,UIKit.C_DIM));return
 var site:String=w.region
 var revision:=_land_revision
 if w.region==NpcFuelFacility.SITE:_refresh_npc(site,revision)
 if w.region in ["b_forest","d_yard"]:
  if w.site_built(w.region):
   var title:String=WorldTrip.REGION_A_BUILD[w.region].name
   _land_box.add_child(UIKit.lbl(title+"　保管 "+str(w.site_store_total(w.region))+" / "+str(w.site_capacity(w.region))+"個（車両は重量制）",13,Color("dcebc9")))
   var fuel_amount:float=GameData.FUEL_ITEMS[GameData.Item.FUEL]
   var fuel_note:=UIKit.lbl("予備燃料の引出先は車両倉庫です。\nタンク%.0f以下で運搬担当が1個を運び、%.0f給油します。"%[GameData.FUEL_CAP-fuel_amount,fuel_amount],12,UIKit.C_DIM)
   fuel_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
   _land_box.add_child(fuel_note)
   for item in [GameData.Item.WOOD,GameData.Item.STONE,GameData.Item.FOOD,GameData.Item.FUEL]:
    var local:int=game.warehouse_discard_available(item)
    var remote:int=int(w.site_store(w.region).get(item,0))
    var deposit:=UIKit.button(_item_name(item)+"を1預ける（車両・未予約 "+str(local)+"）",func():
     if _land_context_current(site,revision):w.deposit_to_site(item,1)
     _refresh())
    deposit.disabled=local<=0 or w.site_store_total(w.region)>=w.site_capacity(w.region)
    _land_box.add_child(deposit)
    var withdraw:=UIKit.button(_item_name(item)+"を1引出す（地点 "+str(remote)+"）",func():
     if _land_context_current(site,revision):w.withdraw_from_site(item,1)
     _refresh())
    withdraw.disabled=remote<=0 or game.storage.free_for(item)<=0
    _land_box.add_child(withdraw)
   _offer_land_preview("remove","保管庫を撤去（空のときだけ）")
  else:
   _offer_land_preview("build",WorldTrip.REGION_A_BUILD[w.region].name+"の計画を確認")
 if w.region in ["b_forest","d_yard"] and not bool(w.region_state.roads.bd.cleared):
  _offer_land_preview("clear_shortcut","B–D倒木近道の処理を確認")
 if w.region in ["a_start","b_forest"] and not bool(w.region_state.roads.ab.graded):
  _offer_land_preview("grade_ab","A–B整地の計画を確認")
 if _land_action=="":return
 var preview:Dictionary=w.land_preview(_land_action)
 if preview.is_empty():
  _land_action="";return
 _land_box.add_child(UIKit.lbl("確認："+str(preview.gain),13,Color("ffe3a0")))
 _land_box.add_child(UIKit.lbl(_cost_text(preview.cost)+"\n"+_cost_availability_text(preview.cost)+"\n"+str(preview.kept),12,UIKit.C_DIM))
 var can_confirm:bool=bool(preview.available)
 for item in preview.cost:
  if game.warehouse_discard_available(item)<int(preview.cost[item]): can_confirm=false
 var action:=_land_action
 var confirm:=UIKit.button("この計画を実行",func():
  if _land_context_current(site,revision) and _land_action==action:_confirm_land()
  else:_refresh())
 confirm.disabled=not can_confirm;_land_box.add_child(confirm)
 _land_box.add_child(UIKit.button("計画を取消（状態は変えない）",func():
  if revision==_land_revision:_land_action="";_land_site=""
  _refresh()))
func _refresh_npc(site:String,revision:int) -> void:
 var service=game.world.npc_service
 var status:="営業中・現金給油のみ" if service.restored() else "未復旧・休業中"
 _land_box.add_child(UIKit.lbl(NpcFuelFacility.NAME+"  "+status,14,UIKit.C_ACCENT))
 var note:=UIKit.lbl("備蓄がなくてもCrでタンクへ補給。街へ戻らずCへ再出発できます。\n所有・運営はNPC。下の自設保管庫とは別です。\n種類・D配置・復旧費は開発者暫定の試作です。",12,UIKit.C_DIM)
 note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_land_box.add_child(note)
 var action:="fuel_cash" if service.restored() else "restore"
 var label:="給油の見積り（最大%.0f / %d Cr）"%[TownDB.SERVICE_UNIT,TownDB.SERVICE_PRICE] if service.restored() else "復旧支援を確認（木%d・石%d・%d Cr）"%[NpcFuelFacility.MATERIALS[GameData.Item.WOOD],NpcFuelFacility.MATERIALS[GameData.Item.STONE],NpcFuelFacility.CREDITS]
 _land_box.add_child(UIKit.button(label,func():
  if _land_context_current(site,revision):_npc_action=action;_land_action=""
  _refresh()))
 if _npc_action!=action:return
 var q:Dictionary=service.quote(action)
 var detail:=UIKit.lbl(q.text+("\n"+q.reason if not q.ok else ""),12,UIKit.C_DIM)
 detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_land_box.add_child(detail)
 var confirm:=UIKit.button("復旧して営業開始" if action=="restore" else "この金額で給油",func():
  if _land_context_current(site,revision) and _npc_action==action:
   service.execute(q);_npc_action=""
  _refresh())
 confirm.disabled=not q.ok;_land_box.add_child(confirm)
 _land_box.add_child(UIKit.button("NPC見積りを取消",func():
  if revision==_land_revision:_npc_action="";service.cancel_quote()
  _refresh()))

func _confirm_land() -> void:
 var w=game.world
 if not w.land_operation_reason(_land_site).is_empty():_refresh();return
 var ok:=false
 match _land_action:
  "build":ok=w.build_current_site()
  "clear_shortcut":ok=w.clear_shortcut()
  "grade_ab":ok=w.grade_ab()
  "remove":ok=w.remove_current_site()
 if ok:_land_action="";_land_site=""
 _refresh()
func _go() -> void:
 _departure_error="";game.world.departure_error=""
 var ok:bool=game.journey.plan(_path,_reserved) if game.world.active else game.world.request_legacy_region()
 if ok: close()
 else:
  _departure_error=game.world.departure_error
  _refresh()
func _resume_departure() -> void:
 _departure_error="";game.world.departure_error=""
 if game.journey.resume():close()
 else:
  _departure_error=game.world.departure_error
  _refresh()
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
