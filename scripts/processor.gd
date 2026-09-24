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


func cancel_reservation(recipe: Dictionary) -> void:
	var i := incoming.find(recipe)
	if i >= 0:
		incoming.remove_at(i)


func receive(recipe: Dictionary) -> void:
	cancel_reservation(recipe)
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
	var b = base()
	var mult: float = speed_of.call(current["field"])
	if b.condition(GameData.Part.MACHINE) < GameData.PART_BAD:
		mult *= 0.5                      # 加工設備が傷んでいると遅い
	progress += delta * mult
	b.wear(GameData.Part.MACHINE, GameData.MACHINE_WEAR_PER_SEC * delta)
	if progress >= current["time"]:
		for i in current["n"]:
			output.append(current["out"])
		total_done += 1
		current = {}
		progress = 0.0


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


func access_point() -> Vector2:
	return global_position


func _process(_delta: float) -> void:
	queue_redraw()


func _first_input(r: Dictionary) -> int:
	return r["in"].keys()[0]


func _draw() -> void:
	var active := is_active()
	var frame := 0
	if active:
		frame = 1 + (int(Time.get_ticks_msec() / 220) % 2)
	var sheet := GameData.tex("res://assets/base/machine.png")
	draw_texture_rect_region(sheet, Rect2(-56, -96, 112, 96), Rect2(frame * 30, 0, 28, 24))
	# 進捗バー（床の上）
	var r := progress / float(current["time"]) if not current.is_empty() else 0.0
	draw_rect(Rect2(-56, 3, 112, 8), Color(0.08, 0.07, 0.06, 0.9))
	draw_rect(Rect2(-52, 5, 104.0 * r, 4), Color("7be07b"))
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
