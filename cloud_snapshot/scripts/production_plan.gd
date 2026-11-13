class_name ProductionPlan
extends RefCounted

static func defaults() -> Dictionary:
	return {GameData.Item.FOOD:{"enabled":true,"target":12},GameData.Item.FUEL:{"enabled":true,"target":8},GameData.Item.REPAIR_KIT:{"enabled":true,"target":6}}

static func urgent(g, item:int) -> bool:
	if item==GameData.Item.FOOD: return g.hungry and g.storage.count_of(item)==0
	if item==GameData.Item.FUEL: return g.base.fuel<30.0 and g.storage.count_of(item)==0
	return item==GameData.Item.REPAIR_KIT and g.base.has_critical_part() and g.storage.count_of(item)==0

static func rank(g,r:Dictionary) -> int:
	if urgent(g,r.out): return 3
	return 2 if r.get("manual",false) or r.has("build") or r.get("build_request",false) else 1

static func ready(g,r:Dictionary) -> bool:
	return not r.is_empty() and g.has_facility(GameData.recipe_station(r)) and AutoCraftGuard.allows(g,r) and g.storage.transform_limit(r)>0 and (r.tank_fuel<=0.0 or g.base.fuel>=25.0)

static func finished(g,item:int) -> int:
	var n:int=g.storage.count_of(item)+g.workshop_count(item)
	for w in g.workers:
		if w.carrying==item and w.ai.state not in [CharacterAI.State.HAUL_TAKE,CharacterAI.State.HAUL_MOVE]: n+=w.carry_n
	return n

static func future(g,item:int) -> int:
	var n:int=g.processor.pending_of(item)
	for q in g.craft_queue:
		var r:=GameData.recipe_by_id(q.id)
		if r.out==item:n+=int(q.n)*int(r.n)
	return n

## 待ち注文の次の1回分を通常補充から保護する。物理予約ではなく再計算する。
## 他の明示注文・緊急維持には適用しないため、精錬や初期道具を相互に塞がない。
static func held_for_orders(g) -> Dictionary:
	var needed:Dictionary={}
	var seen:Dictionary={}
	for q in g.production_orders:
		if seen.has(q.id):continue
		seen[q.id]=true
		var r:=GameData.recipe_by_id(q.id)
		for it in r["in"]:needed[it]=int(needed.get(it,0))+int(r["in"][it])
	for id in g.build_queue:
		var packed:=FacilityDB.packed_item_of(id)
		if packed>=0 and g.packed_in_transit(packed)>0:continue
		for it in g.build_cost(id):needed[it]=int(needed.get(it,0))+int(g.build_cost(id)[it])
	for it in needed:needed[it]=maxi(0,int(needed[it])-g.workshop_available(it))
	return needed

static func spares_orders(g,r:Dictionary,claimant=null) -> bool:
	var held:=held_for_orders(g)
	for it in r["in"]:
		if AutoCraftGuard.available(g,it,claimant)-int(held.get(it,0))<int(r["in"][it]):return false
	return true

static func refill_recipes() -> Array:
	# 消耗品間の既存順は維持。同じ修理板だけ石・皮骨を鉄より先に試す。
	var recipes:Array=[]
	for r in GameData.RECIPES:
		if r.out!=GameData.Item.REPAIR_KIT:recipes.append(r)
	for id in ["repair_stone","repair_hide","repair_iron"]:recipes.append(GameData.recipe_by_id(id))
	return recipes

static func refill(g, emergency_only:bool) -> Dictionary:
	for r in refill_recipes():
		if not g.refill_settings.has(r.out): continue
		var setting:Dictionary=g.refill_settings[r.out]
		if not setting.enabled or setting.target<=0: continue
		if emergency_only and not urgent(g,r.out): continue
		var have:int=finished(g,r.out)+future(g,r.out)
		if have>=int(setting.target) or not ready(g,r): continue
		if not urgent(g,r.out) and not spares_orders(g,r):continue
		var unit:Dictionary=r.duplicate(true)
		unit["automatic"]=true
		return unit
	return {}

static func valid(d) -> bool:
	if not d is Dictionary or not d.get("orders",[]) is Array or not d.get("refill",{}) is Dictionary or not d.get("goals",{}) is Dictionary:return false
	for q in d.get("orders",[]):
		if not q is Dictionary or not q.get("id") is String or GameData.recipe_by_id(q.id).is_empty() or not q.get("n") is int or q.n<=0 or q.n>999 or not q.get("batch") is bool:return false
	for it in d.get("refill",{}):
		var s=d.refill[it]
		if not defaults().has(it) or not s is Dictionary or not s.get("enabled") is bool or not s.get("target") is int or s.target<0 or s.target>999:return false
	for it in d.get("goals",{}):
		if not it is int or not GameData.ITEM_NAMES.has(it) or not d.goals[it] is int or d.goals[it]<=0 or d.goals[it]>999:return false
	return true

static func legacy_settings(priorities: Dictionary) -> Dictionary:
	var result:=defaults()
	for it in result:
		result[it].enabled=GameData.RECIPES.any(func(r):return r.out==it and int(priorities.get(r.id,0))>0)
	return result

static func order_reason(g,r:Dictionary) -> String:
	var station:=GameData.recipe_station(r)
	if not g.has_facility(station):return FacilityDB.name_of(station)+"が必要"
	if not AutoCraftGuard.allows(g,r):return "素材不足"
	if g.storage.transform_limit(r)<=0:return "積載満杯"
	if r.tank_fuel>0.0 and g.base.fuel<25.0:return "加工用燃料不足"
	var emergency:=refill(g,true)
	if not emergency.is_empty():return "緊急"+ItemDB.name_of(emergency.out)+"を優先中"
	if g.processor.free_slots()<=0:return "加工枠待ち"
	return "搬入待ち"

## 全候補を説明する。自動で道具注文や地域移動は行わない。
static func refill_reason(g,item:int) -> String:
	var setting:Dictionary=g.refill_settings[item]
	if not setting.enabled:return "補充OFF"
	if finished(g,item)+future(g,item)>=int(setting.target):return "補充中" if future(g,item)>0 else "目標達成"
	var reasons:PackedStringArray=[]
	for r in refill_recipes():
		if r.out!=item:continue
		if ready(g,r):
			if not urgent(g,item) and not spares_orders(g,r):reasons.append(r.name+"：注文の材料を確保中")
			else:return r.name+"：搬入・加工枠待ち（緊急維持→注文→通常補充の順）"
		else:
			var missing:PackedStringArray=[]
			for it in r["in"]:
				var n:=maxi(0,int(r["in"][it])-AutoCraftGuard.available(g,it))
				if n>0:missing.append("%s%d"%[ItemDB.name_of(it),n])
			reasons.append(r.name+"："+("不足 "+"・".join(missing) if not missing.is_empty() else order_reason(g,r)))
	if item==GameData.Item.REPAIR_KIT:
		reasons.append("石・鉱石を採れない場合はFの道具で木製採掘具→石のハンマーを注文。鉄は精錬注文。地域移動・道具製作は任意です")
	return " / ".join(reasons)
