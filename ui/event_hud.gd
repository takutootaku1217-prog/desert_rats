class_name EventHUD
extends CanvasLayer
## 左下の「旅の出来事」表示。予報・発生中の天候と襲撃（最大2つ）と対処方針の切り替え・最近の出来事の記録・走行距離。
## 対処方針のボタンを押すと、その場で効き、次に同じ出来事が来たときの自動対処にもなる（放置しても回る）。
## 「テスト」で、出来事をその場で起こして確かめられる（ゲームの進行には関係ない確認用）。

var game
var _panel: PanelContainer
var _dist: Label
var _slots: Array = []           # 出来事の枠 {title, row, note, btns, id, stance}
var _log: Label
var _test_box: VBoxContainer
var _exp_box: VBoxContainer
var _exp_label: Label
var _exp_btn: Button

const W := 420.0
const LOG_SHOW_SEC := 40.0       # これより古い記録は消す
const SLOT_COUNT := 2


func _ready() -> void:
	layer = 12
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.box(Color("1b1e24", 0.86), Color("636b7a"), 3, 8))
	_panel.custom_minimum_size = Vector2(W, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_dist = UIKit.lbl("", 13, Color("cfe6ff"))
	_dist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_dist)
	var tb := UIKit.button("テスト", func(): _test_box.visible = not _test_box.visible)
	tb.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tb.custom_minimum_size = Vector2(64, 24)
	top.add_child(tb)
	for i in SLOT_COUNT:
		_slots.append(_make_slot(v))
	# 遺跡（遠征）の欄
	_exp_box = VBoxContainer.new()
	_exp_box.add_theme_constant_override("separation", 2)
	_exp_box.visible = false
	v.add_child(_exp_box)
	_exp_label = _wrapped("", 14, Color("9fd6ff"))
	_exp_box.add_child(_exp_label)
	_exp_btn = UIKit.button("調査隊を編成する (X)", func(): game.expedition_ui.open())
	_exp_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exp_btn.custom_minimum_size = Vector2(0, 28)
	_exp_box.add_child(_exp_btn)
	_log = _wrapped("", 13, Color("fff7dc"))
	v.add_child(_log)
	_test_box = VBoxContainer.new()
	_test_box.visible = false
	_test_box.add_theme_constant_override("separation", 2)
	v.add_child(_test_box)
	_build_test_buttons()


func _make_slot(parent: Control) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.visible = false
	parent.add_child(box)
	var title := UIKit.lbl("", 15, Color("fde68a"))
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	var note := _wrapped("", 12, UIKit.C_DIM)
	box.add_child(note)
	return {"box": box, "title": title, "row": row, "note": note, "btns": {}, "id": "", "stance": ""}


func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := UIKit.lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(W - 20.0, 0)
	return l


func _build_test_buttons() -> void:
	_test_box.add_child(UIKit.lbl("出来事を起こす（確認用。天候・襲撃は予報から）", 12, UIKit.C_DIM))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	row.custom_minimum_size = Vector2(W - 20.0, 0)
	_test_box.add_child(row)
	for id in EventDB.EVENTS:
		var eid: String = id
		var b := UIKit.button(EventDB.EVENTS[eid]["name"], func(): game.director.trigger(eid, true))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, 26)
		row.add_child(b)


func _process(_delta: float) -> void:
	if game == null or game.director == null:
		return
	var d: Director = game.director
	var secs := int(d.elapsed)
	_dist.text = "走行 %.1f km　経過 %d:%02d" % [d.distance / 2500.0, floori(secs / 60.0), secs % 60]
	var focus := d.focus_list()
	for i in SLOT_COUNT:
		_update_slot(_slots[i], focus[i] if i < focus.size() else {})
	_update_expedition()
	# 記録（新しいものだけ）
	var lines: Array = []
	for e in d.log:
		if d.elapsed - e["at"] < LOG_SHOW_SEC:
			lines.append("・" + e["text"])
	_log.visible = not lines.is_empty()
	_log.text = "\n".join(PackedStringArray(lines))
	# 左下に張り付ける
	_panel.position = Vector2(12.0, 708.0 - _panel.size.y)


## 遺跡の発見・調査隊の進行・結果の欄
func _update_expedition() -> void:
	var ex: Expedition = game.expedition
	_exp_box.visible = ex.state != "idle"
	match ex.state:
		"offered":
			_exp_label.text = "🗺 遺跡を発見: %s（あと %d秒）" % [ex.site()["name"], int(ceil(ex.offer_left))]
			_exp_btn.visible = true
		"running":
			var names: Array = []
			for w in ex.party:
				names.append(w.char_name)
			_exp_label.text = "調査隊 探索中 %d%%（%s）\n%s" % [int(ex.progress() * 100.0), "・".join(PackedStringArray(names)),
					ex.log.back() if not ex.log.is_empty() else ""]
			_exp_btn.visible = false
		"done":
			_exp_label.text = "調査隊が戻った: " + ex.summary()
			_exp_btn.visible = false


func _update_slot(s: Dictionary, f: Dictionary) -> void:
	if f.is_empty():
		s["box"].visible = false
		s["id"] = ""
		return
	var def := EventDB.def(f["id"])
	s["box"].visible = true
	var title: Label = s["title"]
	title.text = ("⚠ %s（予報） あと %d秒" if not f["active"] else "%s 発生中  残り %d秒") % [def["name"], int(ceil(f["left"]))]
	var hot: bool = def["kind"] == "attack"
	title.add_theme_color_override("font_color",
			(Color("ff8a70") if hot else Color("ffb070")) if f["active"] else Color("fde68a"))
	if s["id"] != f["id"]:
		_rebuild_stances(s, f["id"])
	if s["stance"] != f["stance"]:
		s["stance"] = f["stance"]
		for sid in s["btns"]:
			UIKit.style(s["btns"][sid], sid == s["stance"])
	var st := EventDB.stance_of(f["id"], f["stance"])
	s["note"].text = "%s\n%s" % [st.get("note", ""), EventDB.stance_summary(st)]


func _rebuild_stances(s: Dictionary, id: String) -> void:
	UIKit.clear(s["row"])
	s["btns"].clear()
	s["id"] = id
	s["stance"] = ""
	for st in EventDB.def(id)["stances"]:
		var sid: String = st["id"]
		var b := UIKit.button(st["name"], func(): game.director.set_stance(id, sid))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s["row"].add_child(b)
		s["btns"][sid] = b
