class_name Expedition
extends RefCounted
## 遺跡の探索（調査隊の派遣）。データは data/expeditions.gd。Main が毎フレーム tick() を呼ぶ。
##  状態: idle（何もない）→ offered（遺跡を見つけた。時間限定）→ running（調査隊が探索中）→ done（結果を表示）→ idle
##  調査隊のあいだ、仲間は拠点にいない（Worker.away）。人手が減るぶん、拠点の作業が回りにくくなる。
##  仲間の疲労度は関門ごとに反映し、戦利品・設計図は帰還時に反映する。設計図は game.blueprints（部署Lvによる解放の枠組みで使う）。

var game
var state := "idle"
var site_id := ""
var offer_left := 0.0
var party: Array = []            # 調査隊の Worker
var approach_id := "normal"
var kit := false                 # 修理資材を1個持たせたか
var steps: Array = []            # 関門の種類の並び
var step_i := 0
var step_left := 0.0
var step_time := 1.0
var loot := {}                   # Item -> 個数（倉庫に持ち帰れた分）
var lost := {}                   # Item -> 個数（積載量がいっぱいで持ち帰れなかった分）
var blueprint := ""              # 見つけた設計図のid
var ok_count := 0
var ng_count := 0
var kit_used := false
var retreated := false
var log: Array = []              # 遠征の記録（文）
var result_left := 0.0
var stats := {"trips": 0, "steps_ok": 0, "steps_ng": 0, "blueprints": 0, "retreats": 0}


func setup(g) -> void:
	game = g


# ---------------------------------------------------------------- 見つける
## 遺跡を見つける（旅の出来事から）。すでに探索中・別の遺跡が出ているときは何もしない。
func offer(id: String) -> void:
	if state == "running" or state == "offered" or not ExpeditionDB.SITES.has(id):
		return
	site_id = id
	offer_left = ExpeditionDB.SITES[id]["stay"]
	state = "offered"
	log.clear()
	game.director.note("遺跡を見つけた！（%s）調査隊を出せる" % ExpeditionDB.SITES[id]["name"])


func site() -> Dictionary:
	return ExpeditionDB.SITES.get(site_id, {})


# ---------------------------------------------------------------- 実力と成功率
## 分野の実力 = メンバーの作業の速さ（Worker.field_mult）の平均 × 人数ボーナス
func power_of(members: Array, field: int) -> float:
	if members.is_empty():
		return 0.0
	var p := 0.0
	for w in members:
		p += w.field_mult(field)
	return p / float(members.size()) * (1.0 + ExpeditionDB.PARTY_BONUS * float(members.size() - 1))


## 関門の種類 step_type の、i番目での成功率（画面の目安にも使う）
func step_chance(members: Array, step_type: String, i: int, appr: String) -> float:
	var field: int = ExpeditionDB.STEPS[step_type]["field"]
	return ExpeditionDB.chance(power_of(members, field), site()["difficulty"], i, appr)


## 派遣できない理由。派遣できるなら ""。
func block_reason(members: Array, appr: String, bring_kit: bool) -> String:
	if state != "offered":
		return "調べられる遺跡がない"
	if members.is_empty():
		return "調査隊のメンバーを選んでください"
	if members.size() > ExpeditionDB.MAX_PARTY:
		return "調査隊は最大%d人まで" % ExpeditionDB.MAX_PARTY
	for w in members:
		if w.away:
			return "%s はすでに出かけている" % w.char_name
		if w.down:
			return "%s は倒れている（戦闘不能）" % w.char_name
	if game.storage.count_of(GameData.Item.FOOD) < members.size() * ExpeditionDB.FOOD_PER_MEMBER:
		return "持たせる食料が足りない（%d個必要）" % (members.size() * ExpeditionDB.FOOD_PER_MEMBER)
	if bring_kit and game.storage.count_of(GameData.Item.REPAIR_KIT) < 1:
		return "修理資材がない"
	return ""


# ---------------------------------------------------------------- 出発・進行
func start(members: Array, appr: String, bring_kit: bool) -> bool:
	if block_reason(members, appr, bring_kit) != "":
		return false
	var d := site()
	party = members.duplicate()
	approach_id = appr
	kit = bring_kit
	kit_used = false
	loot.clear()
	lost.clear()
	blueprint = ""
	ok_count = 0
	ng_count = 0
	retreated = false
	step_i = 0
	log.clear()
	# 持ち物: 食料（人数ぶん）と、任意で修理資材
	for i in members.size() * ExpeditionDB.FOOD_PER_MEMBER:
		game.storage.take_item(GameData.Item.FOOD)
	if bring_kit:
		game.storage.take_item(GameData.Item.REPAIR_KIT)
	# 関門を決める
	steps.clear()
	var types: Array = d["step_weights"].keys()
	var ws: Array = []
	for t in types:
		ws.append(d["step_weights"][t])
	for i in d["steps"]:
		steps.append(types[_pick_weighted(ws)])
	step_time = float(d["duration"]) * float(ExpeditionDB.approach(appr)["time"]) / float(steps.size())
	step_left = step_time
	for w in party:
		w.depart()
	state = "running"
	stats["trips"] += 1
	var names: Array = []
	for w in party:
		names.append(w.char_name)
	_add_log("%s が%sへ出発（%s）" % ["・".join(PackedStringArray(names)), d["name"], ExpeditionDB.approach(appr)["name"]])
	game.director.note("調査隊が出発した（%s）" % "・".join(PackedStringArray(names)))
	return true


func tick(delta: float) -> void:
	match state:
		"offered":
			offer_left -= delta
			if offer_left <= 0.0:
				state = "idle"
				game.director.note("遺跡は遠ざかってしまった")
		"running":
			step_left -= delta
			if step_left <= 0.0:
				_resolve_step()
		"done":
			result_left -= delta
			if result_left <= 0.0:
				state = "idle"


## 進み具合 0〜1
func progress() -> float:
	if state != "running" or steps.is_empty():
		return 0.0
	return clampf((float(step_i) + 1.0 - step_left / step_time) / float(steps.size()), 0.0, 1.0)


func _resolve_step() -> void:
	var d := site()
	var t: String = steps[step_i]
	var def: Dictionary = ExpeditionDB.STEPS[t]
	var chance := step_chance(party, t, step_i, approach_id)
	var success := randf() < chance
	if success:
		ok_count += 1
		stats["steps_ok"] += 1
		_roll_loot(int(def["loot"]))
		_add_log("%s: %s（成功率%d%%）" % [def["name"], def["ok"], int(round(chance * 100.0))])
	else:
		ng_count += 1
		stats["steps_ng"] += 1
		var absorbed := kit and not kit_used and t != "explore"
		if absorbed:
			kit_used = true                       # 修理資材が身代わりになる
			_add_log("%s: %s…修理資材で被害を防いだ" % [def["name"], def["ng"]])
		else:
			for w in party:
				w.fatigue = minf(CrewStatusDB.MAX_FATIGUE, w.fatigue + float(def["penalty"]))
				CrewStatus._tick_mental(w, 0.0)           # 遠征中は通常のtickが止まるので、時間を進めず疲労に合う精神状態へ更新
			_add_log("%s: %s（全員の疲労度 +%d）" % [def["name"], def["ng"], int(def["penalty"])])
	step_i += 1
	# 誰かの疲労度が最大値に達したら撤退
	var max_fatigue := 0.0
	for w in party:
		max_fatigue = maxf(max_fatigue, w.fatigue)
	if max_fatigue >= CrewStatusDB.MAX_FATIGUE and step_i < steps.size():
		retreated = true
		stats["retreats"] += 1
		_add_log("力尽きた者が出たので、撤退した")
		_finish()
	elif step_i >= steps.size():
		_finish()
	else:
		step_left = step_time


## 戦利品を n 回引く（進め方で量が変わる）。
func _roll_loot(n: int) -> void:
	var d := site()
	var items: Array = d["loot"].keys()
	var ws: Array = []
	for it in items:
		ws.append(d["loot"][it][0])
	var mult: float = ExpeditionDB.approach(approach_id)["reward"]
	for i in n:
		var it: int = items[_pick_weighted(ws)]
		var lo: int = d["loot"][it][1]
		var hi: int = d["loot"][it][2]
		var amount := maxi(1, int(round(float(randi_range(lo, hi)) * mult)))
		loot[it] = loot.get(it, 0) + amount


func _finish() -> void:
	var d := site()
	var complete: bool = not retreated and float(ok_count) >= ceil(float(steps.size()) * ExpeditionDB.COMPLETE_RATIO)
	if complete:
		_roll_loot(1)                                # 踏破のおまけ
		if randf() < float(d["blueprint"]) * float(ExpeditionDB.approach(approach_id)["reward"]):
			blueprint = _pick_blueprint()
			if blueprint == "":
				loot[GameData.Item.IRON] = loot.get(GameData.Item.IRON, 0) + 3
		_add_log("遺跡を踏破した！" if not retreated else "")
	# 戦利品を倉庫へ。積載量（枠）がいっぱいの分は持ち帰れない
	lost.clear()
	for it in loot.keys():
		var stored: int = game.storage.add_item(it, loot[it], Inventory.SOURCE_EXPEDITION)
		if stored < loot[it]:
			lost[it] = loot[it] - stored
			loot[it] = stored
		if loot[it] <= 0:
			loot.erase(it)
	if blueprint != "":
		game.blueprints[blueprint] = true
		stats["blueprints"] += 1
	# 仲間の帰還
	for w in party:
		w.arrive(minf(ExpeditionDB.RETURN_FATIGUE_MAX, w.fatigue))
	state = "done"
	result_left = ExpeditionDB.RETURN_SECONDS
	game.director.note("調査隊が戻った！ %s" % summary())


## 結果の文（戦利品・設計図）
func summary() -> String:
	var parts: Array = []
	for it in loot:
		parts.append("%s×%d" % [GameData.ITEM_NAMES[it], loot[it]])
	var s := "成功%d・失敗%d　" % [ok_count, ng_count]
	s += "・".join(PackedStringArray(parts)) if not parts.is_empty() else "戦利品なし"
	if blueprint != "":
		s += "　★設計図「%s」を入手！" % _blueprint_name(blueprint)
	if not lost.is_empty():
		var l: Array = []
		for it in lost:
			l.append("%s×%d" % [GameData.ITEM_NAMES[it], lost[it]])
		s += "　（倉庫がいっぱいで持ち帰れず: %s）" % "・".join(PackedStringArray(l))
	return s


func _blueprint_name(id: String) -> String:
	for u in GameData.UNLOCKS:
		if u["id"] == id:
			return u["name"]
	return id


## まだ持っていない設計図（設計図が必要な解放項目）からひとつ。なければ ""。
func _pick_blueprint() -> String:
	var left: Array = []
	for u in GameData.UNLOCKS:
		if u["blueprint"] and not game.blueprints.has(u["id"]):
			left.append(u["id"])
	if left.is_empty():
		return ""
	return left[randi() % left.size()]


func _add_log(text: String) -> void:
	if text != "":
		log.append(text)


## 重みの配列から添字をひとつ選ぶ
static func _pick_weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1
