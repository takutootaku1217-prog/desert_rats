class_name CraftDB
extends RefCounted
## 制作画面（ui/craft_ui.gd）の一覧と、「いま作れるか」の判定。**レシピそのものは、既存の GameData.RECIPES（加工）と FacilityDB（建設）**のまま。
## ここは、それを「制作」として並べるための見せ方（分類・判定・数量の選び方）だけ。分類は増減してよい（エントリのない分類は画面に出さない）。
##
## 判定（evaluate）:
##  - 加工・道具・料理: 必要な材料は、**作業場（BaseProcessor.stock）にある分**で数える（倉庫にあっても、運ぶまでは使えない）。
##      足りないときは、倉庫にあるか（運べば作れる）・倉庫にも足りないか（採取・加工が要る）を示す。必要設備（ワークベンチなど）がなければ「解放待ち」。
##  - 建設: これまでの建設の依頼（Main.request_build）のまま。材料は、仲間が倉庫から自動で運ぶので、倉庫の量で数える。

## 分類の並び（画面の切り替え）。エントリのないものは出さない
const CATEGORIES := ["道具", "建設", "料理", "加工", "装備", "その他"]
## 運搬の依頼（倉庫 ⇄ 作業場）を、同時に引き受ける仲間の数。ほかの仲間は、これまでの仕事（自動の加工の運搬など）を続ける
const TRANSFER_WORKERS := 1
## 運搬の1回に運べる個数（採取の袋と同じ）
const TRANSFER_TRIP := GatherDB.CARRY_MAX
## 手動の制作を、作業場の材料から加工設備の注文にする確認の間隔（秒）
const FEED_SECONDS := 0.5
## 数量の選び方（-1 = 全部）
const QUANTITIES := [1, 5, -1]


static func category_of_recipe(r: Dictionary) -> String:
	var out: int = int(r["out"])
	if out in GameData.TOOL_ITEMS:
		return "道具"
	if out == GameData.Item.FOOD:
		return "料理"
	return "加工"


## 制作の一覧（加工のレシピ → 建設の順）。{key, kind "recipe"/"build", id, name, cat, in, out, n, time, station, recipe}
static func entries() -> Array:
	var l: Array = []
	for r in GameData.RECIPES:
		l.append({"key": r["id"], "kind": "recipe", "id": r["id"], "name": r["name"], "cat": category_of_recipe(r), "in": r["in"], "out": int(r["out"]),
				"n": int(r["n"]), "time": float(r["time"]), "station": GameData.recipe_station(r), "recipe": r})
	for id in FacilityDB.ids():
		var d: Dictionary = FacilityDB.def(id)
		l.append({"key": "build:" + id, "kind": "build", "id": id, "name": d["name"], "cat": "建設", "in": d["cost"], "out": -1,
				"n": 0, "time": float(d["time"]), "station": String(d["requires"]), "recipe": FacilityDB.recipe_of(id)})
	return l


## 画面に出す分類（エントリのあるものだけ、CATEGORIES の順）
static func categories_in_use() -> Array:
	var used := {}
	for e in entries():
		used[e["cat"]] = true
	var l: Array = []
	for c in CATEGORIES:
		if used.has(c):
			l.append(c)
	return l


static func entries_of(cat: String) -> Array:
	var l: Array = []
	for e in entries():
		if e["cat"] == cat:
			l.append(e)
	return l


static func entry_of(key: String) -> Dictionary:
	for e in entries():
		if e["key"] == key:
			return e
	return {}


## いまの状態の判定。qty = 作る回数（材料の必要数は 回数×1回分）。
## 返す辞書: state（"ok" 作れる／"short" 材料不足／"blocked" 置き場がいっぱい／"locked" 解放待ち／"done" 建設済み／"queued" 建設の依頼中）、
##   rows（材料ごとの {item, need, have, ok, in_storage}）、reason（解放待ち・不可の理由）、hint（何をすれば解放・解決するか）、
##   max_qty（いま作れる最大の回数。建設は 0/1）、max_with_storage（倉庫の材料も作業場へ運べば作れる最大の回数）、source（材料を数えている場所 "作業場"／"倉庫"）、can_transfer（足りない分が倉庫にある）、missing（足りない分 {item: 個数}）。
static func evaluate(e: Dictionary, game, qty: int = 1) -> Dictionary:
	qty = maxi(1, qty)
	var res := {"state": "short", "rows": [], "reason": "", "hint": "", "max_qty": 0, "source": "作業場", "can_transfer": false, "missing": {}}
	if e["kind"] == "build":
		return _evaluate_build(e, game, res)
	var st: String = e["station"]
	var maxq := 1000000
	var maxq_all := 1000000                                     # 倉庫の材料も作業場へ運べば、作れる最大の回数
	var missing := {}
	for it in e["in"]:
		var per: int = int(e["in"][it])
		var have: int = game.workshop_available(it)
		var need: int = per * qty
		var ok: bool = have >= need
		res["rows"].append({"item": it, "need": need, "have": have, "ok": ok, "in_storage": game.storage.count_of(it)})
		maxq = mini(maxq, have / maxi(1, per))
		maxq_all = mini(maxq_all, (have + game.storage.count_of(it)) / maxi(1, per))
		if not ok:
			missing[it] = need - have
	# 作った物の置き場（倉庫の枠）。いっぱいで入らないなら、作らせない（捨てないため）
	var out: int = int(e["out"])
	var room_ok := true
	if out >= 0:
		var free: int = game.storage.free_for(out)
		maxq = mini(maxq, free / maxi(1, int(e["n"])))
		maxq_all = mini(maxq_all, free / maxi(1, int(e["n"])))
		room_ok = free >= int(e["n"]) * qty
	res["max_qty"] = maxi(0, maxq)
	res["max_with_storage"] = maxi(0, maxq_all)
	res["missing"] = missing
	if st != "" and not game.has_facility(st):
		res["state"] = "locked"
		res["reason"] = "%sが必要" % FacilityDB.name_of(st)
		res["hint"] = "建設で%sを作ると解放される" % FacilityDB.name_of(st)
		return res
	if not missing.is_empty():
		res["state"] = "short"
		var all_in_storage := true
		for it in missing:
			if game.storage.count_of(it) < int(missing[it]):
				all_in_storage = false
		res["can_transfer"] = all_in_storage
		res["hint"] = "倉庫から作業場へ運ぶと作れる" if all_in_storage else "倉庫にも足りない（採取・加工が必要）"
		return res
	if not room_ok:
		res["state"] = "blocked"
		res["reason"] = "置き場がいっぱい"
		res["hint"] = "倉庫の枠を空ける（使う・枠を増やす）"
		return res
	res["state"] = "ok"
	return res


static func _evaluate_build(e: Dictionary, game, res: Dictionary) -> Dictionary:
	var id: String = e["id"]
	res["source"] = "倉庫"
	var missing := {}
	for it in e["in"]:
		var need: int = int(e["in"][it])
		var have: int = game.storage.count_of(it)
		res["rows"].append({"item": it, "need": need, "have": have, "ok": have >= need, "in_storage": have})
		if have < need:
			missing[it] = need - have
	res["missing"] = missing
	var reason: String = game.build_blocked_reason(id)
	if reason == "完成":
		res["state"] = "done"
		res["reason"] = "建設済み"
		return res
	if reason == "建設の依頼中":
		res["state"] = "queued"
		res["reason"] = reason
		res["hint"] = "仲間が材料を運んで作る"
		return res
	if reason != "":
		res["state"] = "locked"
		res["reason"] = reason
		res["hint"] = "先に「%s」を用意する" % reason.trim_suffix("が必要")
		return res
	res["max_qty"] = 1
	if not missing.is_empty():
		res["state"] = "short"
		res["hint"] = "材料が集まるまで、依頼して待てる（回収が優先される）"
		return res
	res["state"] = "ok"
	return res