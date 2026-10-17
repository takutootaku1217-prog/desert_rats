class_name BuildUI
extends CanvasLayer
## 建設・製作の画面（Bキーまたは右の「建設 (B)」ボタン）。検証用の簡単な画面。見た目は後で大きく変える前提。
## 建設 = 部屋の中に設備を足す（ワークベンチは加工室、ベッドは寝室の中）。車体の区画そのものを変える「部屋の変更」は別の画面（ui/base_ui.gd。Rキー）。
##  左: 建設（拠点に設備を建てる）。材料の在庫・必要設備・状態を見て、［建設を依頼する］。あとは仲間が材料を運んで作る。
##  右: 製作（仲間が自動で作る物）。手作業（加工設備）でできる物と、設備が必要な物（設備ができるまで「まだ作れない」）。
## 表の中身は data/facilities.gd（設備）と GameData.RECIPES（製作物。"station" が必要設備）。行は最初に一度だけ作り、
## 画面を開いている間は数字と色だけを更新する（押している最中にボタンが作り直されないように）。

var game
var _overlay: Control
var _fac_rows := {}          # 設備 id -> {state, costs {Item: Label}, req, build, cancel}
var _station_heads := {}     # 必要設備 id（"" = 手作業）-> 見出しの Label
var _recipe_rows: Array = [] # {recipe, name, stars}
var _t := 0.0
var _pack_dialog: ColorRect
var _pack_info: Label
var _pack_slots: OptionButton
var _pack_yes: Button
var _pack_no: Button
var _pack_id := ""
var _pack_snapshot := {}

const C_OK := Color("7be07b")
const C_SHORT := Color("ffc266")
const C_BAD := Color("ff8a70")


func _ready() -> void:
	layer = 23
	_build_pack_dialog.call_deferred()
	# 右のボタンは低い層に置く（ほかの画面を開いたとき、その下に隠れるように）
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 12
	add_child(btn_layer)
	var btn := UIKit.button("建設 (B)", toggle)
	btn.position = Vector2(1000, 362)
	btn.custom_minimum_size = Vector2(272, 32)
	btn_layer.add_child(btn)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close())
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(Color("1b1e24", 0.98), Color("636b7a"), 4, 12))
	panel.position = Vector2(40, 18)
	panel.custom_minimum_size = Vector2(1200, 660)
	_overlay.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UIKit.lbl("建設・製作", 22, UIKit.C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UIKit.button("部屋の変更へ (R)", func():
		close()
		game.room_ui.open()))                      # 車体の区画そのものを変える画面（ui/base_ui.gd）。建設は「部屋の中に設備を足す」
	top.add_child(UIKit.button("閉じる (B / Esc)", close))
	root.add_child(UIKit.lbl("何を作るかを決めると、仲間が材料を運んで作ります。材料が足りないうちは、集まるまで取っておきます。", 13, UIKit.C_DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	scroll.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(560, 0)
	right.add_theme_constant_override("separation", 3)
	cols.add_child(right)
	_build_left(left)
	_build_right(right)


func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		open()


func open() -> void:
	game.close_other_panels(self)
	_overlay.visible = true
	_refresh()


func close() -> void:
	_cancel_pack()
	_overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			toggle()
		elif event.keycode == KEY_ESCAPE and _overlay.visible:
			if _pack_dialog!=null and _pack_dialog.visible: _cancel_pack()
			else: close()


func _process(delta: float) -> void:
	if not _overlay.visible:
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		_refresh()


# ---------------------------------------------------------------- 左: 建設
func _build_left(col: VBoxContainer) -> void:
	col.add_child(UIKit.lbl("── 建設（拠点に設備を建てる） ──", 15, UIKit.C_ACCENT))
	for id in FacilityDB.ids():
		var d: Dictionary = FacilityDB.def(id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.box(Color("23272f"), Color("4b5262"), 2, 8))
		col.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		card.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		var name_l := UIKit.lbl(d["name"], 17, UIKit.C_TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_l)
		var state := UIKit.lbl("", 14, UIKit.C_DIM)
		head.add_child(state)
		head.add_child(UIKit.button("効果・手順", func(): game.craft_ui.open_entry("build:" + id)))
		var pack:=UIKit.button("撤去…",func(): _ask_pack(id))
		head.add_child(pack)
		v.add_child(UIKit.lbl(d["desc"], 12, UIKit.C_DIM))
		var cost_row := HBoxContainer.new()
		cost_row.add_theme_constant_override("separation", 12)
		v.add_child(cost_row)
		cost_row.add_child(UIKit.lbl("新規製作材料（完成品が倉庫なら不要）", 13, UIKit.C_DIM))
		var costs := {}
		for it in d["cost"]:
			var l := UIKit.lbl("", 14)
			cost_row.add_child(l)
			costs[it] = l
		var req := UIKit.lbl("", 13, UIKit.C_DIM)
		v.add_child(req)
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		v.add_child(btns)
		var b_build := UIKit.button("", func():
			game.request_build(id)
			_refresh())
		b_build.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b_build.custom_minimum_size = Vector2(300, 28)
		btns.add_child(b_build)
		var b_cancel := UIKit.button("依頼を取り消す", func():
			game.cancel_build(id)
			_refresh())
		b_cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b_cancel.custom_minimum_size = Vector2(130, 28)
		btns.add_child(b_cancel)
		_fac_rows[id] = {"state": state, "costs": costs, "req": req, "build": b_build, "cancel": b_cancel, "pack": pack}


# ---------------------------------------------------------------- 右: 製作
func _build_right(col: VBoxContainer) -> void:
	col.add_child(UIKit.lbl("── 製作一覧（個別依頼 F ／ 自動優先 P） ──", 15, UIKit.C_ACCENT))
	# 手作業 → 製作設備の順（設備は data/facilities.gd で "station": true のもの）
	var stations: Array = [""]
	for id in FacilityDB.ids():
		if FacilityDB.def(id)["station"]:
			stations.append(id)
	for sid in stations:
		var head := UIKit.lbl("", 14, UIKit.C_TEXT)
		col.add_child(head)
		_station_heads[sid] = head
		for r in GameData.RECIPES:
			if GameData.recipe_station(r) != sid:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			col.add_child(row)
			var row_name: String = ItemDB.name_of(r["out"]) + "（未設置）" if r["out"] in GameData.PACKED_ITEMS else r["name"]
			var nm := UIKit.lbl(row_name, 14, UIKit.C_TEXT, 190)
			row.add_child(nm)
			row.add_child(UIKit.lbl(GameData.recipe_text(r), 12, UIKit.C_DIM))
			var stars := UIKit.lbl("", 13, UIKit.C_ACCENT)
			row.add_child(stars)
			_recipe_rows.append({"recipe": r, "name": nm, "stars": stars})
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 6)
		col.add_child(sp)


# ---------------------------------------------------------------- 更新
func _refresh() -> void:
	if game == null or game.base == null:
		return
	var st = game.storage
	for id in _fac_rows:
		var row: Dictionary = _fac_rows[id]
		var d: Dictionary = FacilityDB.def(id)
		var packed:int=FacilityDB.packed_item_of(id)
		row["pack"].disabled=game.base.facility_count(id)==0
		var built: int = game.base.facility_count(id)
		var mx: int = int(d["max"])
		var queued: int = game.build_queue.count(id)
		var working: int = game.processor.pending_build(id)
		var reason: String = game.build_blocked_reason(id)
		var state := "未建設 %d/%d" % [built, mx]
		var scol: Color = UIKit.C_TEXT
		if built >= mx:
			state = ("設置済み %d/%d" if d.has("packed_item") else "完成 %d/%d") % [built, mx]
			scol = C_OK
		elif not game.facility_unlocked(id):
			state = "まだ建てられない"
			scol = UIKit.C_DIM
		elif working > 0:
			state = "運搬・組み立て中 %d/%d" % [built, mx]
			scol = Color("fde68a")
		elif queued > 0:
			state = "材料集め中 %d/%d" % [built, mx]
			scol = Color("fde68a")
		row["state"].text = state
		row["state"].add_theme_color_override("font_color", scol)
		for it in row["costs"]:
			var need: int = int(d["cost"][it])
			var have: int = st.count_of(it)
			var l: Label = row["costs"][it]
			l.visible = st.count_of(packed) == 0
			l.text = "%s %d/%d%s" % [GameData.ITEM_NAMES[it], have, need, "（枠不足）" if st.quota_of(it) < need else ""]
			l.add_theme_color_override("font_color", UIKit.C_DIM if (built >= mx or not game.facility_unlocked(id)) else \
					(C_BAD if st.quota_of(it) < need else (C_OK if have >= need else C_SHORT)))    # 完成済み・まだ建てられない設備の材料は薄く
		var rq: String = d["requires"]
		row["req"].text = "必要設備: %s" % ("なし（手作業でできる）" if rq == "" else "%s（%s）" % [FacilityDB.name_of(rq), "ある" if game.has_facility(rq) else "まだない"])
		if packed>=0:
			row["req"].text += " ／ 未設置%d個" % st.count_of(packed)
			if st.count_of(packed)>0: row["req"].text="完成品の設置：素材・作業台不要 ／ 未設置%d個" % st.count_of(packed)
		var b: Button = row["build"]
		b.disabled = reason != ""
		b.text = "建設を依頼する（仲間が材料を運んで作る）" if reason == "" else reason
		if packed>=0 and reason == "":
			b.text = "完成品を設置する" if st.count_of(packed)>0 else "製作して設置（材料を自動運搬）"
		row["cancel"].visible = queued > 0
	for sid in _station_heads:
		var have_station: bool = game.has_facility(sid)
		var head: Label = _station_heads[sid]
		if sid == "":
			head.text = "%s でできる物" % FacilityDB.BASE_STATION_NAME
			head.add_theme_color_override("font_color", C_OK)
		else:
			head.text = "%s でできる物　%s" % [FacilityDB.name_of(sid), "（建設済み）" if have_station else "（まだ作れない。先に建設）"]
			head.add_theme_color_override("font_color", C_OK if have_station else UIKit.C_DIM)
	for rr in _recipe_rows:
		var r: Dictionary = rr["recipe"]
		var ok: bool = game.has_facility(GameData.recipe_station(r))
		rr["name"].add_theme_color_override("font_color", UIKit.C_TEXT if ok else UIKit.C_DIM)
		var mode: String = "Fから注文"
		if game.refill_settings.has(r.out):mode="補充ON" if game.refill_settings[r.out].enabled else "補充OFF"
		rr["stars"].text = mode if ok else "作れない"
		rr["stars"].add_theme_color_override("font_color", UIKit.C_ACCENT if ok else C_BAD)


func _build_pack_dialog() -> void:
	_pack_dialog=ColorRect.new(); _pack_dialog.color=Color(0,0,0,0.85)
	_pack_dialog.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(_pack_dialog)
	var panel:=PanelContainer.new(); panel.position=Vector2(200,135); panel.custom_minimum_size=Vector2(880,440)
	panel.add_theme_stylebox_override("panel",UIKit.box(Color("202329"),UIKit.C_ACCENT,4,20)); _pack_dialog.add_child(panel)
	var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",16); panel.add_child(box)
	box.add_child(UIKit.lbl("設備を完成品として撤去",23,UIKit.C_ACCENT))
	_pack_slots=OptionButton.new(); _pack_slots.custom_minimum_size=Vector2(0,38); box.add_child(_pack_slots)
	_pack_slots.item_selected.connect(func(_index): _select_pack_slot())
	_pack_info=UIKit.lbl("",17); _pack_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _pack_info.custom_minimum_size=Vector2(830,190); box.add_child(_pack_info)
	_pack_yes=UIKit.button("確認した1台を撤去して倉庫へ戻す",_execute_pack); box.add_child(_pack_yes)
	_pack_no=UIKit.button("取り消す（撤去しない）",_cancel_pack); box.add_child(_pack_no)
	_pack_dialog.hide()

func _ask_pack(id: String) -> void:
	_pack_id=id; _pack_slots.clear()
	for slot in game.base.built.get(id,[]): _pack_slots.add_item("%s ／ 設置枠 %d" % [FacilityDB.name_of(id),slot+1],slot)
	if _pack_slots.item_count==0: return
	_pack_dialog.show(); _pack_slots.select(0); _select_pack_slot()

func _select_pack_slot() -> void:
	var slot:=_pack_slots.get_selected_id()
	_pack_snapshot=game.facility_pack_request(_pack_id,slot)
	var reason:String=game.facility_pack_reason(_pack_id,slot)
	_pack_yes.disabled=not reason.is_empty()
	_pack_info.text="%s・設置枠%dを完成品1個として倉庫へ戻します。原材料は別途返しません。
再設置はBから、素材・作業台不要です。撤去中はこの1台の効果がなくなります。
" % [FacilityDB.name_of(_pack_id),slot+1]
	if reason!="":
		_pack_info.text+="
撤去できません："+reason+"
状況が変わったら開き直してください。"
	else:
		var d:Dictionary=_pack_snapshot
		_pack_info.text+="
保有重量%d＋予約%d＋返却品%d＝%d
撤去後容量%d（現在%d）。この1台だけ撤去しますか？" % [d.owned,d.reserved,CargoDB.size_of(d.item),d.owned+d.reserved+CargoDB.size_of(d.item),d.after,d.before]

func _execute_pack() -> void:
	var snapshot:=_pack_snapshot.duplicate(true); _pack_snapshot.clear()
	_pack_yes.disabled=true
	if not game.pack_facility(snapshot):
		_pack_info.text="使用状況・予約・在庫・容量が変わったため撤去していません。取り消して確認し直してください。"
		return
	_pack_info.text="完成品1個を倉庫へ戻しました。再設置は建設画面から依頼できます。"
	_refresh()

func _cancel_pack() -> void:
	if _pack_dialog!=null: _pack_dialog.hide()
	_pack_snapshot.clear()
	if game!=null: game.cancel_facility_pack()
