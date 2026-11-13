extends SceneTree
## Explicit world/inventory/time fixtures; actual worker/processor ownership, not GUI.
const LOCATION := "region:next_greenway"
const FIELD := "next_greenway_salvage_id"
const BOX := GameData.Item.STORAGE_BOX
const Guide = preload("res://ui/first_loop_guide.gd")
var g
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func boss_fixture() -> Dictionary:
 return {"cleared":true,"enemies":{FirstRegionCompletion.BOSS_ID:{"id":FirstRegionCompletion.BOSS_ID,"kind":FirstRegionCompletion.BOSS_KIND,"lane":FirstRegionCompletion.BOSS_LANE,"home_x":842.0,"home_y":326.0,"x":842.0,"y":326.0,"hp":0.0,"max_hp":72.0,"attack_left":0.0,"target":"","engager":"","dead":true}}}
func step() -> void:
 g._process(0.2)
 for w in g.workers:w._process(0.2)
func advance_until(predicate:Callable, seconds:float) -> bool:
 for i in ceili(seconds/0.2):
  step()
  if predicate.call():return true
  if i%40==0:await process_frame
 return bool(predicate.call())
func live_box(id:String):
 for n in g.resources_root.get_children():
  if not n.is_queued_for_deletion() and n.world_id==id:return n
 return null
func owned() -> int:
 var n:int=g.storage.count_of(BOX)+g.workshop_count(BOX)+g.processor.pending_of(BOX)
 for w in g.workers:
  if w.carrying==BOX:n+=w.carry_n
 return n
func reject_atomically(d:Dictionary,label:String) -> void:
 var before:=SaveGame.capture(g)
 check(not SaveGame.apply(g,d) and SaveGame.capture(g)==before,label)
func roundtrip(label:String) -> Dictionary:
 var d:=SaveGame.capture(g)
 check(SaveGame.validate(d,g),label+" validates")
 check(SaveGame.apply(g,d),label+" restores")
 check(SaveGame.capture(g)==d,label+" exact in-memory ownership/state")
 return d
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 g=load("res://scenes/main.tscn").instantiate();g.first_region_a_pilot=true
 g.set_meta("diagnostic_seed",104729);root.add_child(g);await process_frame
 g.process_mode=Node.PROCESS_MODE_DISABLED;g.director.enabled=false;g.refill_settings={}
 for w in g.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for item in GameData.Item.values():g.gather_policy[item]=0
 g.gather_policy[BOX]=5
 var unvisited:=SaveGame.capture(g)
 var legacy_unvisited:=unvisited.duplicate(true);legacy_unvisited.world.erase(FIELD)
 check(SaveGame.validate(legacy_unvisited,g) and SaveGame.apply(g,legacy_unvisited),"legacy unvisited profile loads without reward")
 check(g.storage.count_of(BOX)==0 and not g.world.locations.has(LOCATION),"no pre-unlock inventory or location award")
 g.world.region_state.roads.bd.cleared=true
 g.world.region_completion.encounters[FirstRegionCompletion.ENCOUNTER_ID]=boss_fixture()
 g.world.refresh_region_completion()
 g.world._archive();g.world.region="next_greenway";g.world._ensure_location();g.world._spawn_visible()
 var fresh:=SaveGame.capture(g)
 var id:String=fresh.world.get(FIELD,"")
 check(id!="" and fresh.world.locations[LOCATION].has(id),"first visit seeds exactly one identified recoverable equipment")
 if id=="" or not fresh.world.locations[LOCATION].has(id):await finish();return
 var row:Dictionary=fresh.world.locations[LOCATION][id]
 check(row.type=="resource" and row.data.item==BOX and not row.spent and not row.has("regeneration"),"salvage is finite non-regenerative physical resource")
 check(g.storage.count_of(BOX)==0 and g.storage.capacity_bonus==0,"discovery awards neither inventory nor capacity")
 var next:int=g.world.next_id
 g.world._ensure_location();g.world._spawn_visible();g.world._spawn_visible()
 check(g.world.next_id==next and g.resources_root.get_children().filter(func(n):return not n.is_queued_for_deletion() and n.world_id==id).size()==1,"repeated ensure/spawn allocates no second equipment")
 var legacy:=fresh.duplicate(true)
 legacy.world.erase(FIELD);legacy.world.locations[LOCATION].erase(id)
 legacy.resources=legacy.resources.filter(func(r):return r.resource.world_id!=id)
 legacy.world.next_id-=1
 var old_world:Dictionary=legacy.world.duplicate(true)
 check(SaveGame.validate(legacy,g) and legacy.world==old_world,"legacy visited validation is pure")
 check(SaveGame.apply(g,legacy),"legacy stopped-at-entry save migrates")
 var migrated:=SaveGame.capture(g)
 check(migrated.world[FIELD]==id and migrated.world.next_id==legacy.world.next_id+1,"migration allocates one normal numeric identity")
 for loc in old_world.locations:
  for old_id in old_world.locations[loc]:check(migrated.world.locations[loc][old_id]==old_world.locations[loc][old_id],"migration preserves old entity "+old_id)
 for key in ["ecosystem_epoch","region_state","site_stores","npc_facilities","region_completion"]:
  check(migrated.world[key]==old_world[key],"migration preserves "+key)
 check(WorldTrip.normalized(migrated.world)==migrated.world,"normalization is idempotent")
 g.world.tick(0.0)
 check(live_box(id)!=null,"legacy paused Continue gets exactly one live box on normal tick")
 var ground:=roundtrip("ground equipment")
 var away:=legacy.duplicate(true);away.world.region="d_yard";away.resources=[];away.creatures=[];away.enemies=[]
 check(SaveGame.validate(away,g) and SaveGame.apply(g,away),"legacy visited entry saved elsewhere migrates")
 check(g.world.locations[LOCATION].size()==old_world.locations[LOCATION].size()+1,"offscreen migration adds only the one equipment row")
 check(SaveGame.apply(g,ground),"restore ground fixture")
 # Legacy migration must also preserve a real old gather claim/reference.
 g.gather_policy[BOX]=0;g.gather_policy[GameData.Item.WOOD]=5
 check(g.workers[0].ai._try_start(GameData.Job.GATHER),"ordinary AI reserves an existing tree before migration")
 var active_legacy:=SaveGame.capture(g)
 var target_id:String=g.workers[0].ai.res.world_id
 active_legacy.world.erase(FIELD);active_legacy.world.locations[LOCATION].erase(id)
 active_legacy.resources=active_legacy.resources.filter(func(r):return r.resource.world_id!=id)
 active_legacy.world.next_id-=1
 check(SaveGame.validate(active_legacy,g) and SaveGame.apply(g,active_legacy),"active-reference legacy save migrates")
 check(g.workers[0].ai.res.world_id==target_id and g.workers[0].ai.res.claimed_by==g.workers[0],"old resource reference and claim survive migration")
 check(SaveGame.capture(g).crew==active_legacy.crew,"migration preserves all old worker and AI fields")
 check(SaveGame.apply(g,ground),"restore neutral ground after legacy claim test")
 for defect in ["missing","empty","wrong_type","wrong_item","wrong_location","regeneration","duplicate_live","spent_live","wrong_counter"]:
  var bad:=ground.duplicate(true)
  match defect:
   "missing":bad.world.locations[LOCATION].erase(id)
   "empty":bad.world[FIELD]=""
   "wrong_type":bad.world[FIELD]=1
   "wrong_item":bad.world.locations[LOCATION][id].data.item=GameData.Item.WOOD
   "wrong_location":bad.world.locations["region:a_start"][id]=bad.world.locations[LOCATION][id];bad.world.locations[LOCATION].erase(id)
   "regeneration":bad.world.locations[LOCATION][id]["regeneration"]=ResourceRegeneration.create(1,0.0)
   "duplicate_live":
    for r in bad.resources:
     if r.resource.world_id==id:bad.resources.append(r.duplicate(true));break
   "spent_live":bad.world.locations[LOCATION][id].spent=true
   "wrong_counter":bad.world.next_id=0
  reject_atomically(bad,"malformed "+defect+" rejected without mutation")
 var bad_legacy:=legacy.duplicate(true);bad_legacy.world.next_id=0
 reject_atomically(bad_legacy,"legacy bad counter is not repaired or overwritten")
 # 359/360 weight leaves less than a packed box's 42. Fixtures are explicit.
 g.storage.inventory.counts={GameData.Item.WOOD:89,GameData.Item.FOOD:3}
 var cap:int=g.storage.max_weight();var weight:int=g.storage.current_weight()
 check(cap-weight<42 and not g.has_room_for(live_box(id),g.gather_room()),"insufficient space refuses actual pickup eligibility")
 g.workers[0].priorities[GameData.Job.GATHER]=5
 for i in 30:step()
 check(not g.world.locations[LOCATION][id].spent and owned()==0,"full hold leaves equipment on ground")
 var before_hint:=SaveGame.capture(g)
 var help:=Guide.snapshot(g)
 check(str(help.next_step.body).contains("42") and str(help.next_step.body).contains("収納") and SaveGame.capture(g)==before_hint,"guide exposes packed-space requirement without granting anything")
 # Free capacity, then advance normal worker AI to physical ownership.
 g.storage.inventory.counts={}
 check(g.workers[0].ai._try_start(GameData.Job.GATHER),"box can be claimed while capacity is free")
 g.storage.inventory.counts={GameData.Item.WOOD:89,GameData.Item.FOOD:3}
 check(await advance_until(func():return g.workers[0].ai.res==null,120.0),"capacity filled after claim releases collection")
 check(not g.world.locations[LOCATION][id].spent and owned()==0,"late capacity refusal retains ground item and zero owners")
 g.storage.inventory.counts={GameData.Item.WOOD:79,GameData.Item.HIDE:1}
 g.processor.stock.counts={GameData.Item.FAT:1}
 check(g.storage.max_weight()-g.storage.current_weight()==42 and g.workers[0].ai._try_start(GameData.Job.GATHER),"exact42 free capacity accepts one equipment reservation")
 check(g.request_craft("tallow",1)==0 and g.craft_queue.is_empty(),"normal positive-growth craft cannot steal capacity reserved by equipment pickup")
 g.workers[0].stop_work();g.processor.stock.counts={}
 g.storage.inventory.counts={}
 check(await advance_until(func():return g.workers[0].carrying==BOX,120.0),"ordinary worker collects one equipment")
 check(g.world.locations[LOCATION][id].spent and g.storage.count_of(BOX)==0 and owned()==1,"carry ownership consumes ground, not teleport to warehouse")
 check(g.storage.current_weight()==42 and g.storage.max_weight()==cap,"packed carry weighs42 but grants no capacity")
 roundtrip("carried equipment")
 check(await advance_until(func():return g.storage.count_of(BOX)==1,120.0),"worker physically unloads at base")
 check(owned()==1 and g.storage.current_weight()==42,"warehouse transfer retains one box and weight")
 var stored:=roundtrip("warehoused equipment")
 # Independently queued production must be visible before recommending more work.
 g.finish_build("workbench")
 g.processor.stock.counts={GameData.Item.WOOD:6,GameData.Item.IRON:3}
 check(g.request_craft("storage_box",1)==1,"normal craft request coexists with recovered warehouse equipment")
 var craft_before:=SaveGame.capture(g)
 check(not g.world.salvage_status().contains("で設置を依頼") and g.world.salvage_status().contains("製作") and SaveGame.capture(g)==craft_before,"pending box production is reported before offering another action")
 check(SaveGame.apply(g,stored),"restore recovered-only warehouse fixture")
 check(g.build_cost("cargo_rack")=={BOX:1},"finished equipment substitutes one box for recipe materials")
 check(g.request_build("cargo_rack") and g.cancel_build("cargo_rack") and g.storage.count_of(BOX)==1,"cancel before installation retains finished equipment")
 check(g.request_build("cargo_rack"),"recovered finished box can be installed without workbench or raw materials")
 var queued_before:=SaveGame.capture(g)
 var queued_help:String=g.world.salvage_status()
 check(not queued_help.contains("で設置を依頼") and queued_help.contains("依頼済み") and SaveGame.capture(g)==queued_before,"queued installation guidance waits instead of offering duplicate request")
 for i in 2:g.finish_build("cargo_rack")
 var limited_before:=SaveGame.capture(g)
 check(not g.request_build("cargo_rack") and not g.world.salvage_status().contains("で設置を依頼") and g.world.salvage_status().contains("依頼済み") and SaveGame.capture(g)==limited_before,"two installed plus pending third reports occupied final slot read-only")
 check(SaveGame.apply(g,queued_before),"restore queued single-install fixture")
 g.workers[0].priorities[GameData.Job.GATHER]=0;g.workers[0].priorities[GameData.Job.HAUL]=5
 check(await advance_until(func():return g.workers[0].ai.state==CharacterAI.State.HAUL_MOVE,120.0),"installation uses physical material transfer")
 roundtrip("installation hauling")
 check(g.world.salvage_status().contains("依頼済み"),"active installation stays marked requested")
 check(await advance_until(func():return not g.processor.orders.is_empty(),120.0),"installation material arrives before processor commit")
 # Zero-duration installation commits in one work() call. Explicitly exercise
 # its valid current-recipe save boundary without pretending natural elapsed assembly.
 g.processor._start_next()
 check(g.processor.current.get("build","")=="cargo_rack" and g.processor.current.time==0.0,"zero-time installation current recipe owns the packed input")
 roundtrip("active zero-time installation boundary")
 g.workers[1].priorities[GameData.Job.PROCESS]=5
 check(await advance_until(func():return g.base.facility_count("cargo_rack")==1,120.0),"workers finish installation")
 check(g.storage.count_of(BOX)==0 and g.storage.max_weight()==cap+60 and g.storage.capacity_bonus==60,"one installation consumes one box and adds capacity60 once")
 check(g.storage.current_weight()==0 and g.storage.count_of(GameData.Item.WOOD)==0 and g.storage.count_of(GameData.Item.IRON)==0,"installation releases packed42 without second material fee")
 var installed:=roundtrip("installed equipment")
 g.director.elapsed+=10000.0;g.world.tick(0.0);g.world._ensure_location();g.world._spawn_visible()
 check(live_box(id)==null and g.world.locations[LOCATION][id].spent and g.storage.max_weight()==cap+60,"time and refresh never regrow equipment or bonus")
 check(SaveGame.apply(g,installed) and SaveGame.apply(g,installed) and g.storage.capacity_bonus==60,"repeated load never stacks installation bonus")
 # Preserve existing facility maximum; ordinary completed boxes are separate from environmental grant.
 check(SaveGame.apply(g,stored),"restore warehouse fixture for max boundary")
 for i in 3:g.finish_build("cargo_rack")
 check(not g.request_build("cargo_rack") and g.storage.count_of(BOX)==1 and g.storage.capacity_bonus==180,"max3 rejects fourth installation without consuming recovery")
 check(SaveGame.apply(g,installed),"restore final installed fixture")
 await finish()
func finish() -> void:
 paused=false
 if g!=null and is_instance_valid(g):g.queue_free()
 await process_frame
 print("GREENWAY SALVAGE checks=",checks," failures=",failures)
 quit(1 if failures else 0)
