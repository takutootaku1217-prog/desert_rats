class_name FacilityPacking
extends RefCounted
## 設置物1台と未設置品1個の交換。原材料は生成しない。
static func reserved_weight(g) -> int:
 return g.storage.processing_reserve()+g.storage.set_weight(g.gather_room())
static func measure(g,id: String,slot: int) -> Dictionary:
 var item:=FacilityDB.packed_item_of(id)
 return {"id":id,"slot":slot,"item":item,"owned":g.storage.current_weight(),"reserved":reserved_weight(g),"before":g.storage.max_weight(),"after":g.storage.max_weight()-int(FacilityDB.def(id).get("capacity_bonus",0)),"item_count":g.storage.count_of(item),"built":g.base.built.duplicate(true),"layout":g.room_layout.duplicate(true)}
static func depends(recipe: Dictionary,id: String) -> bool:
 return recipe.get("station","")==id or recipe.get("build","")==id
static func reason(g,id: String,slot: int) -> String:
 if g.game_over: return "ゲーム終了中は撤去できません"
 if not FacilityDB.has(id) or slot not in g.base.built.get(id,[]): return "この枠には設備がありません"
 if g.world.recalling() or g.quarry.recalling(): return "出発前の集合が終わるまで待ってください"
 if g.expedition.state=="running": return "遠征隊が持ち帰るまで待ってください"
 if id=="parallel_bench":
  var p=g.processor.second
  if p!=null and (p.worker!=null or not p.current.is_empty() or not p.output.is_empty()): return "増設枠の作業・出力回収が終わるまで待ってください"
 if id=="bed":
  if is_instance_valid(g.base.beds[slot]): return "この寝床は休息・予約中です"
  for w in g.workers:
   if w.bed_index==slot and w.ai.state in [CharacterAI.State.REST,CharacterAI.State.REST_MOVE]: return "この寝床は休息・予約中です"
 for w in g.workers:
  if w.carrying>=0 or not w.carry_bonus.is_empty() or w.away: return "仲間の運搬・持帰りが完了するまで待ってください"
  if is_instance_valid(w.ai.prey): return "狩猟の持帰りが完了するまで待ってください"
  if depends(w.ai.haul_recipe,id): return "設備に依存する運搬・予約が完了するまで待ってください"
 if g.build_pending(id)>0: return "同じ設備の建設・設置依頼が残っています"
 for bid in g.build_queue:
  if FacilityDB.def(bid)["requires"]==id: return "この設備を使う建設依頼を完了または取消してください"
 for c in g.craft_queue+g.production_orders:
  if GameData.recipe_station(GameData.recipe_by_id(c.id))==id: return "この設備を使う製作依頼を完了または取消してください"
 var recipes:Array=g.processor.orders+g.processor.incoming
 recipes.append_array(g.processor.active_recipes())
 for r in recipes:
  if depends(r,id): return "設備を使う加工・建設・材料予約が完了するまで待ってください"
 var d:=measure(g,id,slot)
 var needed:int=d.owned+d.reserved+g.storage.item_weight(d.item)
 if needed>d.after: return "撤去後の容量不足：保有%d＋予約%d＋返却品%d＝%d ＞ 容量%d（撤去前%d）" % [d.owned,d.reserved,g.storage.item_weight(d.item),needed,d.after,d.before]
 return ""
