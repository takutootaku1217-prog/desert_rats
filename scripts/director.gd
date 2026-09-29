class_name Director
extends RefCounted
## 旅の出来事の進行役（data/events.gd の表を使う）。Main が毎フレーム tick() を呼ぶ。
##  - 一定間隔で出来事を選ぶ。天候と襲撃は 予報（warn 秒前）→ 発生 → 終了。トラブルと好機は即発生。
##  - 発生中の天候・襲撃の「対処方針」で、速度・傷み・疲れ・食料・燃料・資源の出現・屋外作業・車体の被害・作業速度の倍率が変わる。
##  - 他のスクリプトは、この倍率を読むだけ（speed_mult() など）。出来事の中身はここに閉じている。
## 新しい出来事は EventDB.EVENTS に足すだけでよい（種類が増えるときだけ _apply_instant や _begin_timed に分岐を足す）。

var game
var active: Array = []           # 発生中の天候・襲撃 {id, left, total, stance, flee_t, spawned}
var forecast: Array = []         # 予報中の天候・襲撃 {id, left}
var default_stance := {}         # 出来事のid -> 最後に選んだ対処方針のid（次からの自動対処に使う）
var log: Array = []              # 記録 {text, at}
var elapsed := 0.0               # 経過時間（秒）
var distance := 0.0              # 走行距離（px）
var stats := {"weather": 0, "attack": 0, "trouble": 0, "chance": 0, "repelled": 0, "escaped": 0, "kills": 0}
var enabled := true
var _next_in := EventDB.FIRST_DELAY


func setup(g) -> void:
	game = g


## Main から毎フレーム。dist はこのフレームに進んだ距離。
func tick(delta: float, dist: float) -> void:
	elapsed += delta
	distance += dist
	# 予報 → 発生
	for f in forecast.duplicate():
		f["left"] -= delta
		if f["left"] <= 0.0:
			forecast.erase(f)
			_begin_timed(f["id"])
	# 発生中 → 終了。暖房などの燃料消費もここで払う。
	for a in active.duplicate():
		a["left"] -= delta
		var st := _stance_of(a)
		var heat: float = st.get("heat", 0.0)
		if heat > 0.0 and game != null and game.base != null:
			game.base.fuel = maxf(0.0, game.base.fuel - heat * delta)
		var reason := ""
		if EventDB.def(a["id"])["kind"] == "attack":
			reason = _tick_attack(a, st, delta)
		if reason != "" or a["left"] <= 0.0:
			_end(a, reason)
	# 次の出来事
	if enabled:
		_next_in -= delta
		if _next_in <= 0.0:
			_next_in = randf_range(EventDB.GAP_MIN, EventDB.GAP_MAX)
			var id := _pick()
			if id != "":
				trigger(id, true)


## 出来事を起こす。天候・襲撃は with_forecast が true なら予報から、false なら即発生。
func trigger(id: String, with_forecast := false) -> void:
	var d := EventDB.def(id)
	if d.is_empty():
		return
	if EventDB.is_timed(id):
		if with_forecast:
			forecast.append({"id": id, "left": d["warn"]})
			_log(d["warn_text"] + "…")
		else:
			_begin_timed(id)
	else:
		_apply_instant(id, d)


func _begin_timed(id: String) -> void:
	var d := EventDB.def(id)
	var total := randf_range(d["dur"][0], d["dur"][1])
	var entry := {"id": id, "left": total, "total": total, "stance": default_stance.get(id, d["default"]),
			"flee_t": 0.0, "spawned": 0}
	active.append(entry)
	stats[d["kind"]] += 1
	_log(d["start_text"])
	if d["kind"] == "attack":
		entry["spawned"] = _spawn_enemies(d)
		if game != null:
			for w in game.workers:                             # 襲撃が始まると、全員が緊張する（ストレス。精神状態に影響）
				w.stress += CrewStatusDB.RAID_START_STRESS


func _end(a: Dictionary, reason: String) -> void:
	active.erase(a)
	var d := EventDB.def(a["id"])
	if d["kind"] == "attack":
		if reason == "":                        # 時間切れ: 残った敵は去っていく
			var alive := _alive_enemies()
			if alive.is_empty():
				_log(d["end_text"])
			else:
				for e in alive:
					e.queue_free()
				_log("%sは去っていった" % EventDB.ENEMIES[d["enemy"]]["name"])
	else:
		_log(d["end_text"])


## 襲撃の進行。撃退したら "repelled"、振り切ったら "escaped"、続くなら ""。
func _tick_attack(a: Dictionary, st: Dictionary, delta: float) -> String:
	var alive := _alive_enemies()
	if st.get("flee", false):
		a["flee_t"] += delta
		if a["flee_t"] >= EventDB.FLEE_SECONDS and not alive.is_empty():
			for e in alive:
				e.queue_free()
			stats["escaped"] += 1
			_log("襲撃を振り切った！")
			return "escaped"
	if a["spawned"] > 0 and alive.is_empty():
		stats["repelled"] += 1
		_log("襲撃を撃退した！")
		return "repelled"
	return ""


## 敵が拠点に取りついて攻撃している最中か（仲間が迎撃に向かう合図）
func raid_pressing() -> bool:
	for e in _alive_enemies():
		if e.is_attacking():
			return true
	return false


func _alive_enemies() -> Array:
	var l: Array = []
	if game == null or game.enemies_root == null:
		return l
	for e in game.enemies_root.get_children():
		if not e.dead and not e.is_queued_for_deletion():
			l.append(e)
	return l


func _spawn_enemies(d: Dictionary) -> int:
	var n := randi_range(d["count"][0], d["count"][1]) + int(distance / d["count_per_distance"])
	n = clampi(n, 1, EventDB.MAX_ENEMIES)
	for i in n:
		var e := Enemy.new()
		e.setup_kind(game, d["enemy"])
		e.position = Vector2(game.SPAWN_X + i * 80.0, randf_range(game.SPAWN_Y_MIN + 10.0, game.SPAWN_Y_MAX - 10.0))
		game.enemies_root.add_child(e)
	return n


## 敵を倒したときの戦利品（Main.on_enemy_killed から）。確率 p は「期待する個数」（1.0 以上なら確実にその数）。
func enemy_killed(e) -> void:
	stats["kills"] += 1
	var drops: Dictionary = EventDB.ENEMIES[e.kind]["drops"]
	for it in drops:
		var p: float = drops[it]
		var n := int(floor(p)) + (1 if randf() < p - floor(p) else 0)
		for i in n:
			var r := ResourceNode.new()
			r.game = game
			r.item = it
			r.position = e.position + Vector2(randf_range(-30, 30), randf_range(-10, 10))
			r.position.y = clampf(r.position.y, game.SPAWN_Y_MIN, game.SPAWN_Y_MAX)
			game.resources_root.call_deferred("add_child", r)


## 画面に出す対象（最大2つ）。発生中の襲撃 → 発生中の天候 → 予報の襲撃 → 予報の天候 の順。
func focus_list() -> Array:
	var out: Array = []
	for kind in ["attack", "weather"]:
		for a in active:
			if EventDB.def(a["id"])["kind"] == kind:
				out.append({"id": a["id"], "active": true, "left": a["left"], "stance": a["stance"]})
	for kind in ["attack", "weather"]:
		for f in forecast:
			if EventDB.def(f["id"])["kind"] == kind:
				out.append({"id": f["id"], "active": false, "left": f["left"],
						"stance": default_stance.get(f["id"], EventDB.def(f["id"])["default"])})
	return out.slice(0, 2)


## 先頭の1つ（互換用）。なければ空。
func focus_weather() -> Dictionary:
	var l := focus_list()
	return l[0] if not l.is_empty() else {}


## 対処方針を変える。発生中なら即座に効き、次に同じ出来事が来たときの自動対処にもなる。
func set_stance(id: String, stance_id: String) -> void:
	if EventDB.stance_of(id, stance_id).is_empty():
		return
	default_stance[id] = stance_id
	for a in active:
		if a["id"] == id:
			a["stance"] = stance_id


func _stance_of(a: Dictionary) -> Dictionary:
	return EventDB.stance_of(a["id"], a["stance"])


# ---- 倍率（他のスクリプトはここを読む） ----
func _mult(key: String) -> float:
	var m := 1.0
	for a in active:
		m *= float(_stance_of(a).get(key, 1.0))
	return m


func speed_mult() -> float:
	return _mult("speed")


func energy_mult() -> float:
	return _mult("energy")


func food_mult() -> float:
	return _mult("food")


func burn_mult() -> float:
	return _mult("burn")


func spawn_mult() -> float:
	return _mult("spawn")


func outdoor_mult() -> float:
	return _mult("outdoor")


## 敵から車体が受ける被害の倍率
func hull_dmg_mult() -> float:
	return _mult("hull_dmg")


## 仲間の作業全体の速さ
func work_mult() -> float:
	return _mult("work")


## 屋外作業（狩猟・回収）が完全に禁止されているか
func outdoor_blocked() -> bool:
	return outdoor_mult() <= 0.0


func wear_mult(part: int) -> float:
	var m := 1.0
	for a in active:
		var w: Dictionary = _stance_of(a).get("wear", {})
		m *= float(w.get(part, 1.0))
	return m


# ---- 選ぶ・起こす ----
func _busy(kind: String) -> bool:
	for a in active:
		if EventDB.def(a["id"])["kind"] == kind:
			return true
	for f in forecast:
		if EventDB.def(f["id"])["kind"] == kind:
			return true
	return false


func _pick() -> String:
	var ids: Array = []
	var weights: Array = []
	for id in EventDB.EVENTS:
		var d: Dictionary = EventDB.EVENTS[id]
		if EventDB.is_timed(id) and _busy(d["kind"]):
			continue                          # 天候と襲撃は、それぞれ同時に1つだけ
		if d.get("min_distance", 0.0) > distance:
			continue                          # 序盤には起きない出来事
		ids.append(id)
		weights.append(d["weight"])
	if ids.is_empty():
		return ""
	return ids[_weighted(weights)]


func _weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1


## トラブルと好機の即時の効果。
func _apply_instant(id: String, d: Dictionary) -> void:
	stats[d["kind"]] = stats.get(d["kind"], 0) + 1
	match id:
		"breakdown":
			var keys: Array = d["parts"].keys()
			var ws: Array = []
			for k in keys:
				ws.append(d["parts"][k])
			var part: int = keys[_weighted(ws)]
			var dmg := randf_range(d["damage"][0], d["damage"][1])
			game.base.parts[part] = maxf(0.0, game.base.parts[part] - dmg)
			_log("%s（-%d）" % [d["text"][part], int(dmg)])
		"herd":
			var n := randi_range(d["count"][0], d["count"][1])
			for i in n:
				var c := Creature.new()
				c.setup(game, d["species"])
				c.position = Vector2(game.SPAWN_X + i * 55.0, randf_range(game.SPAWN_Y_MIN + 20.0, game.SPAWN_Y_MAX - 10.0))
				game.creatures_root.add_child(c)
			_log(d["text"])
		"salvage":
			var n2 := randi_range(d["count"][0], d["count"][1])
			var items: Array = d["items"].keys()
			var ws2: Array = []
			for k in items:
				ws2.append(d["items"][k])
			for i in n2:
				var r := ResourceNode.new()
				r.game = game
				r.item = items[_weighted(ws2)]
				r.position = Vector2(game.SPAWN_X + i * 60.0, randf_range(game.SPAWN_Y_MIN + 4.0, game.SPAWN_Y_MAX - 4.0))
				game.resources_root.add_child(r)
			_log(d["text"])
		_:
			_log(d.get("text", d["name"]) if typeof(d.get("text", "")) == TYPE_STRING else d["name"])


## 記録に一文を足す（ほかのシステムからも使える）。
func note(text: String) -> void:
	_log(text)


func _log(text: String) -> void:
	log.append({"text": text, "at": elapsed})
	while log.size() > EventDB.LOG_KEEP:
		log.pop_front()
