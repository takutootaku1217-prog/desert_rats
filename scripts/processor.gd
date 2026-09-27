class_name BaseProcessor
extends Node2D
## 加工設備（上の階の加工室）。レシピ単位の「注文」を受けて加工する。
##   運搬: 倉庫から材料一式を運び込む → orders に積まれる
##   加工: 作業者が orders を順に加工 → output（完成品）→ 作業者が倉庫へ運ぶ
## 精錬のように炉を使うレシピは、拠点の燃料タンクから燃料を使う。
## 見た目（文字ではなく、絵と動きで状態が分かる）: 待っている材料は投入口の上に並ぶ → 材料が投入口へ落ちる（砂ぼこり）→ 機械が動き、煙突から湯気が出る →
##   作っている物のアイコンが下から明るく満ちていく（進み具合）→ 完成すると「きらり」と光り、出口のトレイに完成品が弾んで置かれる。
##   燃料が足りず止まっているときは、燃料のアイコンが赤く点滅する。湯気・砂ぼこり・きらめきは効果の素材（data/effects.gd）で、図形はコードで描かない。

const ORDER_CAP := 3
## 機械まわりの位置（足元の中心からのワールドのpx。機械の絵 assets/base/machine.png に合わせた場所）
const HOPPER := Vector2(-32.0, -96.0)      # 投入口（左上のじょうご）の口
const VENT := Vector2(20.0, -92.0)         # 煙突の先（湯気）
const CHUTE := Vector2(46.0, -14.0)        # 出口（完成品が出てくる所）
const TRAY_X := 70.0                       # 出力トレイの左端
const GAUGE_POS := Vector2(90.0, -68.0)    # 「作っている物」のアイコン（進み具合）の中心
const DROP_SECONDS := 0.4                  # 材料が投入口へ落ちるアニメの長さ
const POP_SECONDS := 0.35                  # 完成品がトレイに弾んで現れる長さ

var orders: Array = []       # 加工待ちのレシピ（Dictionary）
var incoming: Array = []     # 運搬中のレシピ（予約）
var current := {}            # 加工中のレシピ（空 = なし）
var progress := 0.0
var output: Array = []       # 完成して取り出し待ちの加工品（Item）
var worker = null            # 作業中の Worker
var total_done := 0          # 加工した回数（確認用）
var waiting_fuel := false    # 燃料がなくて炉のレシピが止まっている
var _last_work_ms := -10000
var _last_station := ""      # いま（直前に）作業していた設備（"" = 加工設備。レシピの "station"）
var _steam: FxSprite         # 煙突の湯気（加工中だけ出る。効果の素材）
var _drops: Array = []       # 投入口へ落ちている材料 [{item, t0（ms）}]（見た目だけ）
var _out_times: Array = []   # output と同じ並び。その完成品が出てきた時刻（ms。弾んで現れる動き用。見た目だけ）


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_steam = FxSprite.spawn(self, "proc_steam", VENT)
	if _steam != null:
		_steam.set_playing(false)


func base():
	return get_parent()


## 空き枠。燃料待ちで止まっている注文は数えない（燃料を作る注文が入れなくなって詰むのを防ぐ）。
func free_slots() -> int:
	var active := 0
	for r in orders:
		if r["tank_fuel"] <= 0.0 or base().fuel >= r["tank_fuel"]:
			active += 1
	return ORDER_CAP - active - incoming.size()


func reserve(recipe: Dictionary) -> void:
	incoming.append(recipe)


## 運搬をやめた（材料は倉庫に残る／戻る）。建設の依頼は、待ちに戻す（依頼が消えないように）。
func cancel_reservation(recipe: Dictionary) -> void:
	_drop_reservation(recipe)
	if recipe.has("build"):
		base().game.requeue_build(recipe["build"])


func _drop_reservation(recipe: Dictionary) -> void:
	var i := incoming.find(recipe)
	if i >= 0:
		incoming.remove_at(i)


func receive(recipe: Dictionary) -> void:
	_drop_reservation(recipe)
	orders.append(recipe)
	# 材料が入った見た目（投入口へ落ちる／設備の場所で砂ぼこり）
	if recipe.get("station", "") == "":
		_drops.append({"item": _first_input(recipe), "t0": Time.get_ticks_msec()})
		FxSprite.spawn(self, "proc_drop", HOPPER + Vector2(0.0, 8.0))
	else:
		FxSprite.spawn(self, "proc_drop", to_local(station_point(recipe)))


## これから出来上がる予定の数（作りすぎないための計算に使う）
func pending_of(item: int) -> int:
	var n := 0
	for r in orders + incoming:
		if r["out"] == item:
			n += r["n"]
	if not current.is_empty() and current["out"] == item:
		n += current["n"]
	for o in output:
		if o == item:
			n += 1
	return n


## 運搬中・加工待ち・作業中の、設備 id の建設の数（建てすぎないための計算に使う）
func pending_build(id: String) -> int:
	var n := 0
	for r in orders + incoming:
		if r.get("build", "") == id:
			n += 1
	if current.get("build", "") == id:
		n += 1
	return n


## 設備 station で作業する場所（足元）。"" は加工設備。
func station_point(recipe: Dictionary) -> Vector2:
	var st: String = recipe.get("station", "")
	return global_position if st == "" else base().facility_point(st)


## 作業者がいま向かう場所（作業中のレシピ、なければ次に始まるレシピの設備）
func work_point() -> Vector2:
	var r: Dictionary = current if not current.is_empty() else _peek_next()
	return station_point(r) if not r.is_empty() else global_position


func has_work_for_worker() -> bool:
	if worker != null:
		return false
	if not output.is_empty() or not current.is_empty():
		return true
	return not orders.is_empty() and not only_blocked()


func take_output() -> int:
	if not _out_times.is_empty():
		_out_times.pop_front()
	return output.pop_front()


## 作業者がいる間だけ呼ばれる。speed_of(field) = 作業者の腕前などの倍率。
func work(delta: float, speed_of: Callable) -> void:
	_last_work_ms = Time.get_ticks_msec()
	if current.is_empty():
		_start_next()
		if current.is_empty():
			return
	_last_station = current.get("station", "")
	var b = base()
	var mult: float = speed_of.call(current["field"])
	if b.condition(GameData.Part.MACHINE) < GameData.PART_BAD:
		mult *= 0.5                      # 加工設備が傷んでいると遅い
	progress += delta * mult
	b.wear(GameData.Part.MACHINE, GameData.MACHINE_WEAR_PER_SEC * delta)
	if progress >= current["time"]:
		var done: Dictionary = current
		if done.has("build"):
			b.game.finish_build(done["build"])            # 建設: 設備が拠点にできる（アイテムは出ない）
		else:
			for i in done["n"]:
				output.append(done["out"])
				_out_times.append(Time.get_ticks_msec())
			# 完成の見た目（きらり）。加工設備なら出口、ワークベンチなどならその設備の場所
			if done.get("station", "") == "":
				FxSprite.spawn(self, "proc_done", CHUTE + Vector2(0.0, -6.0))
			else:
				FxSprite.spawn(self, "proc_done", to_local(station_point(done)) + Vector2(0.0, -30.0))
		total_done += 1
		current = {}
		progress = 0.0


## 次に始まる注文（燃料が足りて、すぐ始められる先頭のもの。なければ空）。作業者が向かう設備を決めるのに使う。
func _peek_next() -> Dictionary:
	for r in orders:
		if r["tank_fuel"] <= 0.0 or base().fuel >= r["tank_fuel"]:
			return r
	return {}


## 次に加工する注文を選ぶ。炉を使うレシピは燃料が足りる時だけ。
func _start_next() -> void:
	waiting_fuel = false
	for i in orders.size():
		var r: Dictionary = orders[i]
		if r["tank_fuel"] > 0.0 and base().fuel < r["tank_fuel"]:
			waiting_fuel = true
			continue
		if r["tank_fuel"] > 0.0:
			base().fuel -= r["tank_fuel"]
		current = r
		progress = 0.0
		orders.remove_at(i)
		return


## 燃料待ちの注文しか残っていないか（作業者が張り付かないように）
func only_blocked() -> bool:
	if not current.is_empty() or not output.is_empty():
		return false
	for r in orders:
		if r["tank_fuel"] <= 0.0 or base().fuel >= r["tank_fuel"]:
			return false
	return true


func is_active() -> bool:
	return Time.get_ticks_msec() - _last_work_ms < 250


## いま設備 id（"" = 加工設備）で作業中か（設備の動きの表示に使う）
func is_active_at(id: String) -> bool:
	return is_active() and _last_station == id


func access_point() -> Vector2:
	return global_position


func _process(_delta: float) -> void:
	if _steam != null:
		_steam.set_playing(is_active_at(""))              # 加工設備が動いている間だけ、煙突から湯気
	queue_redraw()


func _first_input(r: Dictionary) -> int:
	return r["in"].keys()[0]


func _draw() -> void:
	var active := is_active_at("")               # ワークベンチで作業しているときは、加工設備は動かさない
	var frame := 0
	if active:
		frame = 1 + (int(Time.get_ticks_msec() / 220) % 2)
	var sheet := GameData.tex("res://assets/base/machine.png")
	var mspec := ArtSpec.MACHINE                                    # 基準の大きさ（ユニット）。絵の細かさは絵の幅から自動で決まる
	var msize := ArtSpec.px_size(mspec["cell"])
	draw_texture_rect_region(sheet, Rect2(Vector2(-msize.x / 2.0, -msize.y), msize), ArtSpec.frame_src(sheet, mspec, frame))
	# 進捗バー（作業している設備の足元。加工設備なら床の上、ワークベンチならその足元）
	var r := progress / float(current["time"]) if not current.is_empty() else 0.0
	var bx := 0.0
	var bw := 112.0
	if not current.is_empty() and current.get("station", "") != "":
		bx = station_point(current).x - global_position.x
		bw = 64.0
	draw_rect(Rect2(bx - bw / 2.0, 3, bw, 8), Color(0.08, 0.07, 0.06, 0.9))
	draw_rect(Rect2(bx - bw / 2.0 + 4.0, 5, (bw - 8.0) * r, 4), Color("7be07b"))
	var now := Time.get_ticks_msec()
	# 待っている材料: 投入口（じょうご）の中に並ぶ（アイコン。文字ではない）
	for i in mini(orders.size(), 4):
		GameData.draw_item(self, _first_input(orders[i]), HOPPER + Vector2(-15.0 + i * 15.0, 12.0), 0.5)
	# 材料が投入口へ落ちていく
	for d in _drops.duplicate():
		var age := float(now - int(d["t0"])) / 1000.0
		if age >= DROP_SECONDS:
			_drops.erase(d)
			continue
		var u := age / DROP_SECONDS
		var sz := ArtSpec.px_size(ArtSpec.ITEM) * 0.5 * (1.0 - 0.4 * u)
		var at := HOPPER + Vector2(0.0, -12.0 + 30.0 * u * u)
		draw_texture_rect(GameData.item_tex(int(d["item"])), Rect2(at - sz / 2.0, sz), false, Color(1, 1, 1, 1.0 - 0.6 * u))
	# 作っている物: アイコンそのものが進み具合（下から明るく満ちる）。個数は下の点。
	# 燃料が足りず止まっているときは、燃料のアイコンが赤く点滅する。
	if not current.is_empty() and int(current["out"]) >= 0:
		_draw_gauge_plate(Color(0.99, 0.9, 0.55, 0.9))
		GameData.draw_item_fill(self, int(current["out"]), GAUGE_POS, 0.75, r)
		var n := int(current["n"])
		for k in n:
			draw_rect(Rect2(GAUGE_POS.x + (float(k) - (n - 1) / 2.0) * 8.0 - 2.0, GAUGE_POS.y + 27.0, 4, 4), Color("fde68a"))
	elif current.is_empty() and waiting_fuel and not orders.is_empty():
		var blink := 0.5 + 0.5 * sin(float(now) / 130.0)
		_draw_gauge_plate(Color(0.95, 0.35, 0.28, 0.9))
		GameData.draw_item_fill(self, GameData.Item.FUEL, GAUGE_POS, 0.75, 1.0, Color(1.0, 0.45 + 0.4 * blink, 0.4 + 0.3 * blink))
	# 出力トレイの完成品: 出てきたときに弾んで現れ、取りに来るまで、ゆらゆら揺れて目立つ
	for i in mini(output.size(), 4):
		var age2 := 999.0
		if i < _out_times.size():
			age2 = float(now - int(_out_times[i])) / 1000.0
		var scale := 0.6
		var lift := 0.0
		if age2 < POP_SECONDS:
			var u2 := age2 / POP_SECONDS
			scale = 0.6 * (0.3 + 0.7 * u2) + 0.1 * sin(u2 * PI)
			lift = -10.0 * sin(u2 * PI)
		else:
			lift = -2.0 * sin(float(now) / 260.0 + float(i))
		GameData.draw_item(self, output[i], Vector2(TRAY_X + i * 26.0, -14.0 + lift), scale)


## 「作っている物」のアイコンの下地（仮。将来、画像の枠に差し替えられる）。edge = 枠の色
func _draw_gauge_plate(edge: Color) -> void:
	var box := Rect2(GAUGE_POS - Vector2(22.0, 22.0), Vector2(44.0, 44.0))
	draw_rect(box, Color(0.08, 0.09, 0.11, 0.7))
	draw_rect(box, edge, false, 2.0)