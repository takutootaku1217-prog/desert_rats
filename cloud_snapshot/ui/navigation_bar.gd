class_name NavigationBar
extends CanvasLayer
const TravelLanePresentation = preload("res://scripts/travel_lane_presentation.gd")
const FirstLoopGuide = preload("res://ui/first_loop_guide.gd")
const GUIDE := "はじめの一周"
const PURPOSE_ENTRIES := ["作成", "移動", "所持品", "仲間"]
## 常設の入口だけを集約。ゲーム処理・各画面のキー操作は既存UIへ委譲する。
var game
var bar: PanelContainer
var popup: PanelContainer
var dismiss: Control
var buttons := {}
var groups := {}
var selected := ""
var field_status: Label
var mission_status: Label
var return_result: Label
var recovery_cancel: Button
var guide_text: Label
var guide_scroll: ScrollContainer
var guide_hint: PanelContainer
var guide_next: Label
var guide_preparation_actions: HBoxContainer
var guide_town: Button
var _guide_was_paused := false

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
 var icons := ["shield_machine", "shield_drive", "weight", "mental_normal", "shield_hull", "fatigue"]
 labels = PURPOSE_ENTRIES + ["拠点・街", "その他"]
 for i in labels.size():
  var label:String=labels[i]
  var b := UIKit.button(label,func(): activate(label))
  b.icon=GameData.tex("res://assets/ui/%s.png"%icons[i]);b.expand_icon=true;b.add_theme_constant_override("icon_max_width",28)
  b.alignment=HORIZONTAL_ALIGNMENT_CENTER;b.custom_minimum_size=Vector2(144,48);b.add_theme_font_size_override("font_size",17)
  row.add_child(b);buttons[label]=b
 # Compatibility aliases keep the existing status and tooltip plumbing while
 # the visible labels use the new purpose-first language.
 buttons["地図"] = buttons["移動"]
 buttons["物資"] = buttons["所持品"]
 buttons["地図"].tooltip_text="地図 / 行先 (M)"
 buttons["仲間"].tooltip_text="仲間の管理 (C)"
 buttons["作成"].tooltip_text="作成: 最初は作業台から"
 buttons["移動"].tooltip_text="移動 / 目的地 (M)"
 buttons["所持品"].tooltip_text="所持品: 個体携行と拠点収納 (Tab)"
 buttons["仲間"].tooltip_text="仲間の管理 / 装備変更 (C)"
 _group("探索",[["採取地点 (G)",game.quarry_ui.open],["遠征 (X)",game.expedition_ui.open]])
 var field_group:VBoxContainer=groups["探索"]
 field_status=UIKit.lbl("",15);field_group.add_child(field_status)
 mission_status=UIKit.lbl("",13,Color("ffe2a5"));mission_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;mission_status.custom_minimum_size.x=470;field_group.add_child(mission_status)
 var controls:=HBoxContainer.new();field_group.add_child(controls)
 for entry in [["通常・再開","normal"],["後退（警戒）","alert"],["撤退・呼戻し","recall"]]:
  var mode:String=entry[1]
  var b:=UIKit.button(entry[0],func():game.operations.set_stance(mode))
  b.custom_minimum_size=Vector2(150,40);controls.add_child(b)
 var hint:=UIKit.lbl("警戒は近場の採取を継続。撤退は荷物を持って帰還。仲間を選び生物を右クリックすると明示攻撃（近距離のみ）。",13,UIKit.C_DIM)
 hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.custom_minimum_size.x=470;field_group.add_child(hint)
 return_result=UIKit.lbl("",13);return_result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;return_result.custom_minimum_size.x=470;field_group.add_child(return_result)
 recovery_cancel=UIKit.button("回収を断念して帰還",func():game.town.abandon_recovery_from_field())
 recovery_cancel.custom_minimum_size=Vector2(220,36);field_group.add_child(recovery_cancel)
 _group("拠点",[["街に入る",game.town_ui.request_open],["大型車両・改造 (V)",game.vehicle_ui.open],["建設 (B)",game.build_ui.open],["部屋 (R)",game.room_ui.open],["製作 (F)",game.craft_ui.open],["内外装",func(): activate("内外装")]])
 _group("内外装",[["外装 (O)",func(): game.base_view.set_mode(BaseView.Mode.EXTERIOR)],["内装 (I)",func(): game.base_view.set_mode(BaseView.Mode.INTERIOR)],["戻る",func(): activate("拠点")]])
 _group("物資",[["倉庫 (Tab)",game.inventory_ui.open],["製作 (F)",game.craft_ui.open]])
 var stock_group:VBoxContainer=groups["物資"]
 game.status._stock.reparent(stock_group);stock_group.move_child(game.status._stock,0)
 game.status._totals.reparent(stock_group);stock_group.move_child(game.status._totals,1)
 _group("メニュー",[["運営の方針 (P)",game.policy.toggle],["保存 / 続きから",game.save_ui.open]])

 # Purpose-first bar keeps field/policy/save functions reachable without
 # recreating their underlying panels.
 _group("その他",[["探索・現地",func(): activate("探索")],["方針の変更 (P)",game.policy.toggle],["肉アイコン見本（検証）",open_meat_icon_preview],["保存 / 設定など",game.save_ui.open]])
 var guide_entry:=UIKit.button(GUIDE,func(): activate(GUIDE))
 guide_entry.name="FirstLoopGuideEntry"
 guide_entry.custom_minimum_size=Vector2(180,40)
 groups["その他"].add_child(guide_entry)
 _build_guide()
 _build_guide_hint()

func _build_guide_hint() -> void:
 guide_hint=PanelContainer.new();guide_hint.name="NextStepHint"
 guide_hint.position=Vector2(352,598);guide_hint.custom_minimum_size=Vector2(916,44)
 guide_hint.add_theme_stylebox_override("panel",UIKit.box(Color("1b1e24",0.95),Color("636b7a"),2,6))
 add_child(guide_hint)
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);guide_hint.add_child(row)
 guide_next=UIKit.lbl("",16,UIKit.C_ACCENT)
 guide_next.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 guide_next.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 row.add_child(guide_next)
 var entry:=UIKit.button("手引き",func():activate(GUIDE))
 entry.name="NextStepGuideEntry";entry.custom_minimum_size=Vector2(100,32)
 entry.tooltip_text="現在の一手と操作方法。開いている間は一時停止します。"
 row.add_child(entry)
 guide_hint.hide()

func _build_guide() -> void:
 var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8)
 popup.add_child(box);groups[GUIDE]=box;box.hide()
 box.add_child(UIKit.lbl("はじめの一周  ·  現在の状態を確認",22,UIKit.C_ACCENT))
 box.add_child(UIKit.lbl("読んでいる間は一時停止。成功した操作の記録と現在の所持品を分けて表示。開くだけでは進行しません。",14,UIKit.C_DIM))
 guide_scroll=ScrollContainer.new();guide_scroll.name="FirstLoopGuideScroll"
 guide_scroll.custom_minimum_size=Vector2(780,340)
 guide_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 box.add_child(guide_scroll)
 guide_text=UIKit.lbl("",17)
 guide_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 guide_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 guide_scroll.add_child(guide_text)
 var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",6);box.add_child(actions)
 for action in [
  ["map","地図 (M)",game.map_ui.open],
  ["prepare","準備・作業台",func():game.craft_ui.open_entry("build:workbench")],
  ["repair","修理材",func():game.craft_ui.open_entry("repair_stone")],
  ["upgrade","フレーム",func():game.craft_ui.open_entry("haul_frame")],
  ["crew","仲間・装備",game.detail.toggle],
  ["save","保存",game.save_ui.open]]:
  var callback:Callable=action[2]
  var button:=UIKit.button(action[1],func():close();callback.call())
  button.name="GuideAction_"+action[0]
  button.custom_minimum_size=Vector2(124,40)
  actions.add_child(button)
 guide_preparation_actions=HBoxContainer.new();guide_preparation_actions.add_theme_constant_override("separation",6)
 box.add_child(guide_preparation_actions)
 for action in [
  ["smelt","精錬",func():game.craft_ui.open_entry("smelt")],
  ["armor_recipe","鉄板を製作",func():game.craft_ui.open_entry("armor_plate_kit")],
  ["armor","装甲画面",game.vehicle_ui.open],
  ["town","街・補給",_open_guide_town]]:
  var callback:Callable=action[2]
  var button:=UIKit.button(action[1],func():close();callback.call())
  button.name="GuideAction_"+action[0];button.custom_minimum_size=Vector2(188,40)
  guide_preparation_actions.add_child(button)
  if action[0]=="town": guide_town=button
 box.add_child(UIKit.button("閉じる (Esc)",close))
 _refresh_guide()

func guide_snapshot() -> Dictionary:
 return FirstLoopGuide.snapshot(game)

func _open_guide_town() -> void:
 # A stale help link must not recall workers or create an unavailable-town log.
 if game.town.entry_reason().is_empty(): game.town_ui.open()

func _refresh_guide() -> void:
 var snapshot:=guide_snapshot()
 guide_preparation_actions.visible=bool(snapshot.preparation.get("visible",false))
 guide_town.disabled=not bool(snapshot.town_ready)
 var paragraphs:PackedStringArray=[]
 for section in snapshot.sections:
  paragraphs.append(str(section.title)+"\n"+str(section.body))
 guide_text.text="\n\n".join(paragraphs)

func _group(id:String, actions:Array) -> void:
 var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);popup.add_child(box);groups[id]=box
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);box.add_child(row)
 for action in actions:
  var callback:Callable=action[1]
  var b:=UIKit.button(action[0],func(): close();callback.call())
  b.custom_minimum_size=Vector2(140,44);b.alignment=HORIZONTAL_ALIGNMENT_CENTER;row.add_child(b)
 box.hide()


func open_meat_icon_preview() -> void:
 close()
 if game.meat_icon_preview != null:
  game.meat_icon_preview.open()

func purpose_entry_ids() -> Array:
 return PURPOSE_ENTRIES.duplicate()

func activate(id:String) -> void:
 if game.game_over: return
 if selected==GUIDE and id!=GUIDE: close()
 if id=="作成":
  close()
  if not game.has_facility("workbench"):
   game.craft_ui.open_entry("build:workbench")
  else:
   game.craft_ui.open()
  return
 if id=="移動": close();game.map_ui.open();return
 if id=="所持品": close();game.inventory_ui.open();return
 if id=="地図": close();game.map_ui.open();return
 if id=="仲間": close();game.detail.toggle();return
 var group_id := "拠点" if id=="拠点・街" else id
 if selected==group_id: close();return
 game.close_other_panels(self)
 selected=group_id
 if selected==GUIDE:
  _guide_was_paused=get_tree().paused
  get_tree().paused=true
  guide_scroll.scroll_vertical=0
  _refresh_guide()
 for name_ in groups: groups[name_].visible=name_==group_id
 popup.reset_size();popup.show();dismiss.show()
 _position_popup()
 for name_ in buttons: UIKit.style(buttons[name_],name_==id or (name_=="拠点" and id=="内外装"))

func _position_popup() -> void:
 if selected=="拠点" or selected=="探索":
  var purpose_anchor:String="拠点・街" if selected=="拠点" else "その他"
  var purpose_x:float=buttons[purpose_anchor].get_global_rect().position.x
  popup.position=Vector2(clampf(purpose_x,352,1268-popup.size.x),642-popup.size.y)
  return
 var anchor:String="拠点" if selected=="内外装" else selected
 var x:float=buttons[anchor].get_global_rect().position.x if buttons.has(anchor) else bar.position.x
 popup.position=Vector2(clampf(x,352,1268-popup.size.x),642-popup.size.y)

func close() -> void:
 if selected==GUIDE: get_tree().paused=_guide_was_paused
 selected=""
 if popup!=null: popup.hide();dismiss.hide()
 for name_ in buttons: UIKit.style(buttons[name_],false)

func _process(_delta:float) -> void:
 var modal:=false
 for owner in [game.policy,game.expedition_ui,game.build_ui,game.room_ui,game.inventory_ui,game.craft_ui,game.meat_icon_preview,game.vehicle_ui,game.quarry_ui,game.save_ui,game.map_ui,game.town_ui,game.detail,game.crew_alerts,game.region_clear_ui]:
  if owner != null and owner._overlay.visible: modal=true;break
 var road_travel:bool=TravelLanePresentation.active(game)
 bar.visible=not modal and not game.game_over and not road_travel
 if modal or game.game_over or road_travel: close()
 if popup.visible: _position_popup()
 if selected==GUIDE: _refresh_guide()
 var mine_ui:bool=game.mine_arrival_gate!=null and game.mine_arrival_gate.visible_state()!="idle"
 guide_hint.visible=bar.visible and not popup.visible and game.world.first_region() and not mine_ui
 if guide_hint.visible:
  var next_step:Dictionary=guide_snapshot().next_step
  guide_next.text="次の一手（任意）: "+str(next_step.title)
  guide_next.tooltip_text=str(next_step.body)
 if field_status!=null: field_status.text=game.operations.status_text()
 if mission_status!=null: mission_status.text=game.town.field_status_text()
 if recovery_cancel!=null:
  recovery_cancel.visible=game.town.recovery in ["site","loading"]
  recovery_cancel.disabled=not game.town.recovery_site_ok()
 if return_result!=null: return_result.text=game.operations.result_text()
 buttons["仲間"].tooltip_text="仲間 %d人 (C)"%game.workers.size()
 buttons["物資"].modulate=Color("ffb078") if game.hungry or game.storage.weight_ratio()>=0.9 else Color.WHITE

func _unhandled_input(event:InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE and popup.visible:
  close();get_viewport().set_input_as_handled()
