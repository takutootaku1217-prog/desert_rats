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

const C_OK := Color("7be07b")
const C_SHORT := Color("ffc266")
const C_BAD := Color("ff8a70")


func _ready() -> void:
	layer = 23
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
	root.add_child(cols)
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
	_overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			toggle()
		elif event.keycode == KEY_ESCAPE and _overlay.visible:
			close()


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
		v.add_child(UIKit.lbl(d["desc"], 12, UIKit.C_DIM))
		var cost_row := HBoxContainer.new()
		cost_row.add_theme_constant_override("separation", 12)
		v.add_child(cost_row)
		cost_row.add_child(UIKit.lbl("材料", 13, UIKit.C_DIM))
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
		_fac_rows[id] = {"state": state, "costs": costs, "req": req, "build": b_build, "cancel": b_cancel}


# ---------------------------------------------------------------- 右: 製作
func _build_right(col: VBoxContainer) -> void:
	col.add_child(UIKit.lbl("── 製作（仲間が自動で作る。作る優先は 運営の方針 (P) ） ──", 15, UIKit.C_ACCENT))
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
			var nm := UIKit.lbl(r["name"], 14, UIKit.C_TEXT, 190)
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
		var built: int = game.base.facility_count(id)
		var mx: int = int(d["max"])
		var queued: int = game.build_queue.count(id)
		var working: int = game.processor.pending_build(id)
		var reason: String = game.build_blocked_reason(id)
		var state := "未建設 %d/%d" % [built, mx]
		var scol: Color = UIKit.C_TEXT
		if built >= mx:
			state = "完成 %d/%d" % [built, mx]
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
			var too_heavy: bool = CargoDB.item_weight(it) * need > st.max_weight()   # 最大重量いっぱいでも積めない量（恒常的に不可）
			var l: Label = row["costs"][it]
			l.text = "%s %d/%d%s" % [GameData.ITEM_NAMES[it], have, need, "（最大重量を超える）" if too_heavy else ""]
			l.add_theme_color_override("font_color", UIKit.C_DIM if (built >= mx or not game.facility_unlocked(id)) else \
					(C_BAD if too_heavy else (C_OK if have >= need else C_SHORT)))    # 完成済み・まだ建てられない設備の材料は薄く
		var rq: String = d["requires"]
		row["req"].text = "必要設備: %s" % ("なし（手作業でできる）" if rq == "" else "%s（%s）" % [FacilityDB.name_of(rq), "ある" if game.has_facility(rq) else "まだない"])
		var b: Button = row["build"]
		b.disabled = reason != ""
		b.text = "建設を依頼する（仲間が材料を運んで作る）" if reason == "" else reason
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
		var pr: int = game.recipe_priority.get(r["id"], 0)
		rr["stars"].text = ("★%d" % pr) if ok else "作れない"
		rr["stars"].add_theme_color_override("font_color", UIKit.C_ACCENT if ok else C_BAD)
