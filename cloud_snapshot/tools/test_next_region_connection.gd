extends SceneTree
## Real Main/world/save integration. Explicit completion/time fixtures, not GUI evidence.
const ENTRY := "next_greenway"
const Guide = preload("res://ui/first_loop_guide.gd")
var g
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks+=1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func boss_fixture() -> Dictionary:
 return {"cleared":true,"enemies":{FirstRegionCompletion.BOSS_ID:{"id":FirstRegionCompletion.BOSS_ID,"kind":FirstRegionCompletion.BOSS_KIND,"lane":FirstRegionCompletion.BOSS_LANE,"home_x":842.0,"home_y":326.0,"x":842.0,"y":326.0,"hp":0.0,"max_hp":72.0,"attack_left":0.0,"target":"","engager":"","dead":true}}}
func travel(to: String) -> bool:
 if not g.world.request(to):return false
 for unused in 400:
  g._process(0.25)
  if g.world.region==to and g.world.phase=="stopped":return true
 return false
func reject_atomically(bad: Dictionary,label: String) -> void:
 var before:=SaveGame.capture(g)
 check(not SaveGame.apply(g,bad) and SaveGame.capture(g)==before,label)
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 g=load("res://scenes/main.tscn").instantiate();g.first_region_a_pilot=true
 g.set_meta("diagnostic_seed",104729);root.add_child(g);await process_frame
 g.process_mode=Node.PROCESS_MODE_DISABLED;g.director.enabled=false
 for w in g.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 var exists:bool=WorldMapDB.public_region(ENTRY,g.world.map_profile)
 check(exists,"next-region entrance is a real known destination in the same campaign")
 if not exists:await finish();return
 check(travel("d_yard"),"ordinary old A-D route still travels")
 var legacy:=SaveGame.capture(g)
 check(SaveGame.validate(legacy,g) and not legacy.world.locations.has("region:"+ENTRY),"old save needs no new node ledger or schema migration")
 for flags in [[false,false],[true,false],[false,true]]:
  check(SaveGame.apply(g,legacy),"restore pre-clear fixture")
  g.world.region_state.roads.bd.cleared=flags[1]
  if flags[0]:g.world.region_completion.encounters[FirstRegionCompletion.ENCOUNTER_ID]=boss_fixture()
  var locked:=SaveGame.capture(g)
  check(SaveGame.validate(locked,g),"partial-completion fixture is valid")
  check(not g.world.request(ENTRY) and SaveGame.capture(g)==locked,"direct next-region departure refuses without mutation")
  check(not g.journey.plan([ENTRY]) and SaveGame.capture(g)==locked,"planned next-region departure refuses without mutation")
  g.map_ui.open();g.map_ui.select_region(ENTRY)
  check(g.map_ui._path.is_empty() and g.map_ui._confirm.disabled and g.map_ui._info.text.contains("未解放"),"map shows locked requirement, not a usable path")
  g.map_ui.close()
  for kind in ["current","region_ledger","road_ledger","travel","journey"]:
   var bad:=locked.duplicate(true)
   match kind:
    "current":bad.world.region=ENTRY
    "region_ledger":bad.world.locations["region:"+ENTRY]={}
    "road_ledger":bad.world.locations["road:dn"]={}
    "travel":bad.world.phase="travel";bad.world.road="dn";bad.world.origin="d_yard";bad.world.destination=ENTRY
    "journey":bad.journey.remaining=[ENTRY]
   reject_atomically(bad,"locked saved "+kind+" rejected atomically")
  check(g.world.request("a_start"),"old departure allowed before new gate unlocks")
  check(not g.journey.plan(["d_yard",ENTRY]),"in-transit plan replacement cannot schedule locked entrance")
 check(SaveGame.apply(g,legacy),"restore original old stopped save")
 g.world.region_state.roads.bd.cleared=true
 g.world.region_completion.encounters[FirstRegionCompletion.ENCOUNTER_ID]=boss_fixture()
 check(g.world.refresh_region_completion(),"existing two goals complete first region")
 var completed:=SaveGame.capture(g)
 check(SaveGame.validate(completed,g) and SaveGame.apply(g,completed),"old completed save loads without a new location ledger")
 g.map_ui.open();g.map_ui.select_region(ENTRY)
 check(g.map_ui._path==[ENTRY] and not g.map_ui._confirm.disabled,"same map instance unlocks actual next entry route")
 check(not g.world.region_goal_snapshot().detail.contains("次地域は未実装"),"clear goal no longer denies the implemented entrance")
 var read_before:=SaveGame.capture(g);var help:=Guide.snapshot(g)
 check(str(help.next_step.body).contains("旧緑道") and SaveGame.capture(g)==read_before,"guide names reachable next step without changing state")
 g.map_ui.close()
 check(travel(ENTRY),"normal state machine reaches next-region entrance")
 check(not g.world.is_safe_town() and not g.town.location_ok(),"new resource entrance does not silently gain town services")
 for key in ["map_profile","region_state","site_stores","npc_facilities","region_completion"]:
  check(SaveGame.fields(g.world,WorldTrip.FIELDS)[key]==completed.world[key],"travel preserves old campaign "+key)
 var point=null
 for p in g.resources_root.get_children():
  if p is GatherPoint and p.kind=="tree":point=p;break
 check(point!=null,"new entrance has an ordinary finite gather point")
 if point==null:await finish();return
 var id:String=point.world_id
 # Boundary fixture: lower a ground quantity to prove return/reload does not reseed.
 point.remaining=point.max_amount-3;g.world.sync()
 var quantity:int=point.remaining
 var first:=SaveGame.capture(g)
 check(SaveGame.validate(first,g),"new entrance complete save validates")
 check(SaveGame.apply(g,first),"new entrance complete save restores")
 check(g.world.locations["region:"+ENTRY][id].data.remaining==quantity,"same node remaining survives restore")
 var rows:Dictionary=g.world.locations["region:"+ENTRY].duplicate(true)
 check(travel("d_yard") and travel(ENTRY),"next region returns and can be revisited")
 check(g.world.locations["region:"+ENTRY].keys()==rows.keys(),"revisit retains entity IDs without duplicate allocation")
 check(g.world.locations["region:"+ENTRY][id].data.remaining==quantity,"short round trip does not refill finite node")
 var saved:=SaveGame.capture(g)
 check(SaveGame.validate(saved,g),"revisited save validates")
 var growth:Dictionary=saved.world.locations["region:"+ENTRY][id].regeneration.duplicate(true)
 check(SaveGame.apply(g,saved) and g.world.locations["region:"+ENTRY][id].regeneration==growth,"revisit regeneration credit and revision restore exactly")
 g.director.elapsed+=120.0;g.world.tick(0.0)
 check(g.world.locations["region:"+ENTRY][id].data.remaining==quantity+1,"normal game-time regeneration adds one unit, not a full reset")
 var grown:=SaveGame.capture(g)
 check(SaveGame.validate(grown,g) and SaveGame.apply(g,grown),"regenerated next-entry save remains valid")
 check(g.world.request("d_yard"),"return departure remains available")
 g.world.tick(0.0)
 var moving:=SaveGame.capture(g)
 check(moving.world.phase=="travel" and SaveGame.validate(moving,g) and SaveGame.apply(g,moving),"new connecting road traveling snapshot restores")
 check(SaveGame.apply(g,saved),"restore next-entry stopped snapshot")
 var bad:=saved.duplicate(true);bad.world.region_completion=FirstRegionCompletion.empty()
 reject_atomically(bad,"removing unlock while next-entry progress exists is rejected")
 await finish()
func finish() -> void:
 paused=false;SaveGame.disabled=true
 if g!=null and is_instance_valid(g):g.queue_free()
 await process_frame
 print("NEXT REGION checks=",checks," failures=",failures)
 quit(1 if failures else 0)
