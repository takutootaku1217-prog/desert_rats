extends SceneTree
# Observational probe: only visible workbench request and optional map destinations.
var main
var previous := {}
var next_snapshot := 0.0
var next_trip := 300.0
var route_index := 0
var scenario := "stay"
var seed_value := 501
var duration := 3600.0
var old_states := {}
var violations := []
var receipts := {}
var initial_recipe_priority := {}
var initial_gather_policy := {}
var initial_worker_priorities := []
func emit_record(kind:String, data:Dictionary):
 data["kind"]=kind;data["time"]=snappedf(main.director.elapsed,0.01)
 print(JSON.stringify(data))
func inventory_changed():
 var now:Dictionary=main.storage.inventory.counts.duplicate()
 var delta:={}
 for it in [GameData.Item.WOOD,GameData.Item.REPAIR_KIT,GameData.Item.IRON]:
  var change:int=int(now.get(it,0))-int(previous.get(it,0))
  if change!=0:delta[ItemDB.name_of(it)]=change
 previous=now
 if delta.is_empty():return
 var callers:=[]
 for frame in get_stack():callers.append(str(frame.get("function",""))+":"+str(frame.get("line",0)))
 emit_record("inventory",{"delta":delta,"stack":callers,"workers":workers()})
func workers()->Array:
 var result:=[]
 for w in main.workers:result.append({"name":w.char_name,"state":CharacterAI.State.keys()[w.ai.state],"recipe":w.ai.haul_recipe.get("id",""),"tools":w.tools,"hp":w.hp,"satiety":w.hunger,"priorities":w.priorities})
 return result
func resources_left()->Dictionary:
 var live:={}
 for n in main.world._all_nodes():
  if n is GatherPoint:live[n.world_id]=n.remaining
 var regions:={}
 for location in main.world.locations:
  var kinds:={}
  for id in main.world.locations[location]:
   var row:Dictionary=main.world.locations[location][id]
   if row.type!="gather":continue
   var kind:String=row.data.kind
   var amount:float=0 if row.spent else float(live.get(id,row.data.remaining))
   kinds[kind]=float(kinds.get(kind,0))+amount
  regions[location]=kinds
 return regions
func snapshot():
 var creatures:=[]
 for c in main.creatures_root.get_children():creatures.append({"species":c.species,"hp":c.hp,"x":c.position.x,"hunted":c.hunted_by!=null,"fleeing":c._fleeing,"allowed":main.hunt_allowed(c.species),"room":main.hunt_has_room(c.species)})
 emit_record("snapshot",{"scenario":scenario,"region":main.world.region,"phase":main.world.phase,"stock":main.storage.inventory.counts,"parts":main.base.parts,"fuel":main.base.fuel,"hunted":main.total_hunted,"repair":main.base.total_repair,"events":main.director.log,"workers":workers(),"creatures":creatures,"resources_left":resources_left(),"receipts":receipts,"crafting":{"orders":main.processor.orders,"incoming":main.processor.incoming,"active":main.processor.active_recipes(),"build_queue":main.build_queue},"weight":main.storage.current_weight(),"capacity":main.storage.max_weight()})
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--seed="):seed_value=int(arg.get_slice("=",1))
  if arg.begins_with("--scenario="):scenario=arg.get_slice("=",1)
  if arg.begins_with("--seconds="):duration=float(arg.get_slice("=",1))
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",seed_value);root.add_child(main);await main.ready
 Engine.time_scale=12
 previous=main.storage.inventory.counts.duplicate();main.storage.inventory.changed.connect(inventory_changed)
 initial_recipe_priority=main.recipe_priority.duplicate();initial_gather_policy=main.gather_policy.duplicate()
 for w in main.workers:initial_worker_priorities.append(w.priorities.duplicate())
 main.storage.inventory.item_added.connect(func(it,n,source):
  var key:String=source+":"+ItemDB.name_of(it)
  receipts[key]=int(receipts.get(key,0))+n
  if source==Inventory.SOURCE_PURCHASE:violations.append("開発用物資の注入"))
 if not main.world.active or not main.director.enabled or main.workers.size()!=3:violations.append("既定開始条件の不一致")
 emit_record("start",{"seed":seed_value,"scenario":scenario,"requested_seconds":duration,"events_enabled":main.director.enabled,"map_active":main.world.active,"recipe_priority":main.recipe_priority})
 emit_record("action",{"request":"workbench","accepted":main.request_build("workbench")})
 while main.director.elapsed<duration and not main.game_over:
  await process_frame
  if main.storage.current_weight()+main.storage.processing_reserve()>main.storage.max_weight():
   violations.append("総積載＋加工予約が容量超過");break
  for w in main.workers:
   var state:String=CharacterAI.State.keys()[w.ai.state]
   if old_states.get(w.char_name,"")!=state and (state.begins_with("HUNT") or str(old_states.get(w.char_name,"")).begins_with("HUNT")):
    var prey=w.ai.prey
    emit_record("hunt_transition",{"worker":w.char_name,"state":state,"position":w.position,"speed":w.current_speed(),"camera_left":main.camera_left(),"prey":{} if prey==null or not is_instance_valid(prey) else {"x":prey.position.x,"hp":prey.hp,"flee_speed":prey._flee_speed}})
   old_states[w.char_name]=state
  if main.director.elapsed>=next_snapshot:snapshot();next_snapshot+=30
  if scenario=="route" and main.director.elapsed>=next_trip and main.world.phase=="stopped":
   var route:=["east_sands","central_trade","old_mine","central_trade","south_oasis"]
   var target:String=route[route_index%route.size()]
   var accepted:bool=main.world.request(target)
   emit_record("action",{"request":"travel","destination":target,"accepted":accepted})
   if accepted:route_index+=1
   next_trip=main.director.elapsed+300
 if main.recipe_priority!=initial_recipe_priority or main.gather_policy!=initial_gather_policy:violations.append("既定方針の変更")
 for i in main.workers.size():
  if main.workers[i].priorities!=initial_worker_priorities[i]:violations.append("仕事優先度の変更")
 snapshot();emit_record("result",{"game_over":main.game_over,"reached_60_minutes":main.director.elapsed>=3600,"requested_seconds":duration,"seed":seed_value,"scenario":scenario,"accepted_trips":route_index,"violations":violations})
 # 生存合格ではなく観測の整合性。敗北時刻・未完走をresultに残す。
 print("== 観測完了: 整合性違反なし ==" if violations.is_empty() else "FAIL 観測の整合性違反")
 quit(0 if violations.is_empty() else 1)
