class_name BaseProcessor
extends Node2D
## 加工設備（上の階の加工室）。レシピ単位の「注文」を受けて加工する。
##   運搬: 倉庫から材料一式を運び込む → orders に積まれる
##   加工: 作業者が orders を順に加工 → output（完成品）→ 作業者が倉庫へ運ぶ
## 精錬のように炉を使うレシピは、拠点の燃料タンクから燃料を使う。

const ORDER_CAP := 3

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


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


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
	# 待っている注文の材料
	for i in orders.size():
		GameData.draw_item(self, _first_input(orders[i]), Vector2(-40 + i * 14, -70), 0.5)
	if not current.is_empty():
		GameData.draw_item(self, _first_input(current), Vector2(-20, -50), 0.5)
	# 出力トレイの完成品
	for i in mini(output.size(), 4):
		GameData.draw_item(self, output[i], Vector2(70 + i * 26, -14), 0.5)
	# 状態: 加工前 → 加工中 → 完成
	var stage := "待機中"
	var col := Color("d1d5db")
	if not current.is_empty():
		stage = "%s %d%%" % [current["name"], int(r * 100.0)]
		col = Color("fde68a")
	elif waiting_fuel and not orders.is_empty():
		stage = "燃料待ち"
		col = Color("ff8a70")
	elif not output.is_empty():
		stage = "加工完了!"
		col = Color("86efac")
	GameData.draw_text(self, Vector2(0, -102), "待ち %d ▶ %s ▶ 完成 %d" % [orders.size(), stage, output.size()],
			13, col, 360.0)
