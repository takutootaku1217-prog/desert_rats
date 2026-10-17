class_name TownUI
extends CanvasLayer
var game
var _overlay: ColorRect
var _was_paused := false
var _backdrop: TownBackdrop
var _facilities: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _summary: Label
var _detail: Label
var _confirm: Button
var _quantity: SpinBox
var _quote := {}
var _selection := ""
var _action := ""
var _item := -1
var _waiting := false
var _previous_stance := ""
var _message := ""
func _ready() -> void:
 layer=45;process_mode=Node.PROCESS_MODE_ALWAYS
 _overlay=ColorRect.new();_overlay.color=Color("252e2e");_overlay.set_anchors_preset(Control.PRESET_FULL_RECT);add_child(_overlay)
 _backdrop=TownBackdrop.new();_backdrop.game=game;_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT);_overlay.add_child(_backdrop)
 var title:=UIKit.lbl("街画面  /  中央交易都市",28,Color("ffdf9a"));title.position=Vector2(30,18);_overlay.add_child(title)
 _summary=UIKit.lbl("",18,Color.WHITE);_summary.position=Vector2(30,58);_overlay.add_child(_summary)
 var close_button:=UIKit.button("拠点へ戻る",close);close_button.position=Vector2(1090,20);close_button.custom_minimum_size=Vector2(160,44);_overlay.add_child(close_button)
 var save:=UIKit.button("保存 / 続きから",func():game.save_ui.open());save.position=Vector2(1080,666);save.custom_minimum_size=Vector2(180,36);_overlay.add_child(save)
 var hint:=UIKit.lbl("施設を選択   •   街の画面では時間停止   •   価格・報酬は試作値",16,Color("ffedcc"));hint.position=Vector2(30,680);_overlay.add_child(hint)
 _facilities=Control.new();_facilities.set_anchors_preset(Control.PRESET_FULL_RECT);_facilities.mouse_filter=Control.MOUSE_FILTER_IGNORE;_overlay.add_child(_facilities)
 for row in [["交易所 / ミッション","missions",Vector2(125,430),Vector2(285,44)],["市場 / 売買","market",Vector2(865,470),Vector2(280,44)],["整備ヤード / 給油・修理","service",Vector2(360,620),Vector2(385,44)]]:
  var id:String=row[1]
  var b:=UIKit.button(row[0],func():show_facility(id));b.position=row[2];b.custom_minimum_size=row[3]
  b.add_theme_stylebox_override("normal",UIKit.box(Color("213b3a",0.82),Color("e0bd7a"),2,10));b.add_theme_font_size_override("font_size",22);_facilities.add_child(b)
 _panel=PanelContainer.new();_panel.position=Vector2(160,116);_panel.custom_minimum_size=Vector2(960,535)
 _panel.add_theme_stylebox_override("panel",UIKit.box(Color("202d2b",0.99),Color("e4c58a"),3,18));_overlay.add_child(_panel)
 _body=VBoxContainer.new();_body.add_theme_constant_override("separation",9);_panel.add_child(_body)
 _panel.hide();_overlay.hide()
func is_open() -> bool:return _overlay!=null and _overlay.visible
func request_open() -> void:
 if not game.town.location_ok():game.director.note(game.town.entry_reason());return
 if game.town.entry_reason()=="":open();return
 _previous_stance=game.operations.stance
 game.operations.set_stance("recall");_waiting=true
 game.director.note("街へ入る準備：仲間と荷物の帰還を待っています")
func open() -> void:
 if game.town.entry_reason()!="":game.director.note(game.town.entry_reason());return
 if not is_open():
  game.close_other_panels(self);_was_paused=get_tree().paused;get_tree().paused=true
 _overlay.show();_backdrop.queue_redraw();show_street();_refresh_summary()
func close() -> void:
 _waiting=false
 if _previous_stance!="":
  if game.operations.stance=="recall":game.operations.set_stance(_previous_stance)
  _previous_stance=""
 if not is_open():return
 stop_clock();_quote={};_overlay.hide();get_tree().paused=_was_paused
func stop_clock() -> void:
 _quote={}
func show_street() -> void:
 stop_clock();_selection="";_panel.hide();_facilities.show();_backdrop.show()
func _refresh_summary() -> void:
 _summary.text="%d Cr    |    燃料 %.1f / 100    |    耐久：車体 %.0f ・ 走行 %.0f ・ 加工 %.0f"%[game.town.credits,game.base.fuel,game.base.parts[0],game.base.parts[1],game.base.parts[2]]
func _clear_body() -> void:
 for node in _body.get_children():_body.remove_child(node);node.queue_free()
 _quote={};_action="";_item=-1
func show_facility(id:String) -> void:
 stop_clock();_selection=id;_facilities.hide();_backdrop.show();_clear_body();_panel.show()
 var header:=HBoxContainer.new();_body.add_child(header)
 var title:=UIKit.lbl({"service":"整備ヤード","market":"市場","missions":"交易所 / ミッション"}[id],25,UIKit.C_ACCENT);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
 header.add_child(UIKit.button("街へ戻る",show_street))
 if id=="service":
  _body.add_child(UIKit.lbl("標準走行：満タン%.0f分（試作） / 暖房 0.14〜0.30毎秒、精錬3毎回は別消費"%GameData.FUEL_RANGE_MINUTES,16))
  _row([["クレジットで給油","fuel_cash",-1],["燃料1個で給油","fuel_item",-1]])
  for part in GameData.Part.values():
   var label:String=["車体","走行装置","加工設備"][part]
   _row([[label+"：有料修理","repair_cash",part],[label+"：修理板1個","repair_item",part]])
 elif id=="market":
  _body.add_child(UIKit.lbl("販売は食料・燃料・修理板のみ。売却は倉庫の未予約素材だけ。",16))
  var row:Array=[]
  for it in TownDB.BUY:row.append(["買う：%s %d Cr"%[ItemDB.name_of(it),TownDB.BUY[it]],"buy",it])
  _row(row)
  row=[]
  for it in TownDB.SELL:
   row.append(["売る：%s %d Cr"%[ItemDB.name_of(it),TownDB.SELL[it]],"sell",it])
   if row.size()==4:_row(row);row=[]
  if not row.is_empty():_row(row)
 else:
  _body.add_child(UIKit.lbl("メインクエスト：ストーリー進行（内容は準備中）",16,UIKit.C_DIM))
  _body.add_child(UIKit.lbl("サブクエスト：繰り返し3種。期限・失敗罰金なし。自由探索は受注不要です。",16))
  _body.add_child(UIKit.lbl("調達納品：%s / %d Cr    状態："%[game.town.supply_text(),game.town.supply_reward]+({"idle":"未受注","accepted":"納品待ち"}.get(game.town.supply,"")),16))
  _row([["木材で受注","accept_supply",GameData.Item.WOOD],["石材で受注","accept_supply",GameData.Item.STONE],["納品・受領","claim_supply",-1],["取消","cancel_supply",-1]])
  _body.add_child(UIKit.lbl("預かり荷物の配達（重量%d） / %d Cr    状態："%[TownDB.DELIVERY_PARCEL_WEIGHT,TownDB.DELIVERY_REWARD]+game.town.delivery_status_text(),16))
  _row([["受注","accept_delivery",-1],["報酬受領","claim_delivery",-1],["取消","cancel_delivery",-1]])
  _body.add_child(UIKit.lbl("配達は交易村で停車して引渡し。通過だけでは完了しません。",14,UIKit.C_DIM))
  _body.add_child(UIKit.lbl("遺失物回収（重量%d） / %d Cr    状態："%[TownDB.RECOVERY_PARCEL_WEIGHT,TownDB.RECOVERY_REWARD]+game.town.recovery_status_text(),16))
  _row([["受注","accept_recovery",-1],["報酬受領","claim_recovery",-1],["取消","cancel_recovery",-1]])
  if game.town.legacy_help_credit>0:
   _body.add_child(UIKit.lbl("保存移行：旧荷札整理の未受領報酬 %d Cr"%game.town.legacy_help_credit,15,UIKit.C_DIM))
   _row([["旧報酬を受領","claim_legacy_help",-1]])
 var amount:=HBoxContainer.new();_body.add_child(amount)
 amount.visible=id!="missions"
 amount.add_child(UIKit.lbl("数量（有料整備は%.0f単位）"%TownDB.SERVICE_UNIT,16))
 _quantity=SpinBox.new();_quantity.min_value=1;_quantity.max_value=99;_quantity.value=1;_quantity.custom_minimum_size=Vector2(120,34);amount.add_child(_quantity)
 _quantity.value_changed.connect(func(_v):if _action!="":preview(_action,_item))
 _detail=UIKit.lbl(_message if _message!="" else "操作を選ぶと数量・金額・変更後を確認できます。",16);_detail.custom_minimum_size=Vector2(900,78);_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(_detail)
 _confirm=UIKit.button("確認して実行",confirm);_confirm.disabled=true;_body.add_child(_confirm)
 _refresh_summary()
func _row(entries:Array) -> void:
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);_body.add_child(row)
 for entry in entries:
  var a:String=entry[1];var it:int=entry[2]
  var b:=UIKit.button(entry[0],func():preview(a,it));b.custom_minimum_size.y=34;b.add_theme_font_size_override("font_size",15);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(b)
func preview(action:String,item:int=-1) -> void:
 _action=action;_item=item
 var n:=int(_quantity.value) if action in ["buy","sell","fuel_cash","repair_cash"] else 1
 _quote=game.town.quote(action,item,n)
 _detail.text=_quote.text if _quote.ok else _quote.reason;_confirm.disabled=not _quote.ok
func confirm() -> void:
 _confirm.disabled=true
 var ok:bool=game.town.execute(_quote);_quote={}
 _message="完了しました。次の操作は改めて選択してください。" if ok else "状態が変わったため実行しませんでした。再確認してください。"
 show_facility(_selection)
func _process(delta:float) -> void:
 if _waiting:
  if not game.town.location_ok():close()
  elif game.town.entry_reason()=="":_waiting=false;open()
 if not is_open():return
 _refresh_summary()
func _unhandled_input(event:InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and is_open():
  if event.keycode==KEY_ESCAPE:
   if _panel.visible:show_street()
   else:close()
  get_viewport().set_input_as_handled()
