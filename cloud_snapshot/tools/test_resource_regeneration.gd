extends SceneTree
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func run() -> void:
 var home:=OS.get_environment("FLUID_TEST_HOME")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").begins_with(home.replace("\\","/")): quit(2); return
 var path:="res://data/resource_regeneration.gd"
 check(ResourceLoader.exists(path),"ordinary game-time regeneration calculator exists")
 if not ResourceLoader.exists(path): finish(); return
 var regen=load(path)
 var state:Dictionary=regen.create(5,0.0)
 var amount:=2
 amount=regen.settle(state,amount,119.0,false)
 check(amount==2 and is_equal_approx(state.credit,119.0),"119 seconds retains fraction without a unit")
 amount=regen.settle(state,amount,120.0,false)
 check(amount==3 and is_zero_approx(state.credit),"120 seconds returns one ground unit")
 amount=regen.settle(state,amount,360.0,false)
 check(amount==5 and is_zero_approx(state.credit),"capacity clamps and drops excess time")
 amount=regen.settle(state,amount,2000.0,false)
 amount-=1
 amount=regen.settle(state,amount,2001.0,false)
 check(amount==4 and is_equal_approx(state.credit,1.0),"full time cannot refill a later harvest")
 state=regen.create(5,0.0)
 amount=regen.settle(state,0,60.0,false)
 amount=regen.settle(state,amount,600.0,true)
 amount=regen.settle(state,amount,659.0,false)
 check(amount==0 and is_equal_approx(state.credit,119.0),"footprint suppression discards blocked time but retains fraction")
 check(regen.settle(state,amount,660.0,false)==1,"demolition resumes after remaining game-time interval")
 var whole:Dictionary=regen.create(8,0.0)
 var split:Dictionary=regen.create(8,0.0)
 var split_amount:=1
 for i in 2400: split_amount=regen.settle(split,split_amount,float(i+1)*0.1,false)
 check(split_amount==regen.settle(whole,1,240.0,false) and is_equal_approx(split.credit,whole.credit),"tick partition does not change ground amount or credit")
 check(not regen.valid({"version":2,"capacity":5,"last":0.0,"credit":0.0,"revision":0},0,0.0),"unknown extension rejected")
 var bad:Dictionary=regen.create(5,0.0);bad.credit=NAN
 check(not regen.valid(bad,0,0.0),"nonfinite credit rejected")
 SaveGame.disabled=true
 var g=load("res://scenes/main.tscn").instantiate()
 g.first_region_a_pilot=true;g.set_meta("diagnostic_seed",104729)
 root.add_child(g);await process_frame
 g.process_mode=Node.PROCESS_MODE_DISABLED;g.director.enabled=false
 for w in g.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 g.world._spawn_visible()
 var point=null
 for p in g.resources_root.get_children():
  if p is GatherPoint:point=p;break
 check(point!=null,"normal first-region live gather point")
 if point!=null:
  var id:String=point.world_id
  point.remaining=point.max_amount-2;point.work=0.37;point.claimed_by=g.workers[0]
  g.world.sync()
  var before:Dictionary=g.storage.inventory.counts.duplicate(true)
  var start:float=g.director.elapsed
  g.director.elapsed=start+120.0;g.world.tick(0.0)
  check(point.remaining==point.max_amount-1,"normal WorldTrip tick regenerates live ground")
  check(point.work==0.37 and point.claimed_by==g.workers[0],"live node work and claim survive settlement")
  check(g.storage.inventory.counts==before,"regrowth never deposits inventory")
  point.claimed_by=null;point.remaining=0;g.world.sync()
  var empty_live:Dictionary=SaveGame.capture(g)
  check(SaveGame.validate(empty_live,g),"ordinary exhausted live point remains saveable before regrowth")
  if SaveGame.validate(empty_live,g):
   SaveGame.disabled=false
   check(SaveGame.write(g,"user://regeneration-empty-live.json"),"empty live point writes through normal save API")
   check(SaveGame.apply(g,SaveGame.read("user://regeneration-empty-live.json")),"empty live point reloads without duplication")
   point=null
   for p in g.resources_root.get_children():
    if p.world_id==id and not p.is_queued_for_deletion():point=p;break
   check(point!=null and point.remaining==0,"reloaded live exhausted node retains exact stable identity")
   SaveGame.disabled=true
  g.world.consume(point)
  point.get_parent().remove_child(point);point.free()
  g.director.elapsed+=120.0;g.world.tick(0.0)
  var same=[]
  for p in g.resources_root.get_children():
   if p.world_id==id:same.append(p)
  check(same.size()==1 and same[0].remaining==1,"depleted point returns once under same stable ID")
  var saved:Dictionary=SaveGame.capture(g)
  check(SaveGame.validate(saved,g),"new regeneration snapshot passes full validation")
  var legacy:Dictionary=saved.duplicate(true)
  legacy.world.erase("resource_regeneration_version")
  for rows in legacy.world.locations.values():
   for row in rows.values():row.erase("regeneration")
  check(SaveGame.validate(legacy,g),"legacy save remains valid without retrospective credit")
  var malformed:Dictionary=saved.duplicate(true)
  malformed.world.locations[g.world.key()][id].regeneration.last=g.director.elapsed+1.0
  check(not SaveGame.validate(malformed,g),"future game-time resource clock rejected")
  malformed=saved.duplicate(true);malformed.world.resource_regeneration_version=Vector2(1,2)
  check(not SaveGame.validate(malformed,g),"noninteger world regeneration version safely rejected")
  check(SaveGame.apply(g,legacy),"old normal save migrates without inventory or ground gifts")
  check(g.world.locations[g.world.key()][id].data.remaining==legacy.world.locations[g.world.key()][id].data.remaining,"legacy migration preserves old remaining")
  check(g.world.locations[g.world.key()][id].regeneration.last==g.director.elapsed and g.world.locations[g.world.key()][id].regeneration.credit==0.0,"old normal save begins credit at saved time")
 # Build and remove using existing public payment APIs. Only this synthetic
 # fixture relocates one anchor inside the explicit vacant lot.
 paused=false;g.world._archive();g.world.region="b_forest";g.world._ensure_location();g.world._spawn_visible()
 var points=[]
 for p in g.resources_root.get_children():
  if p is GatherPoint and not p.is_queued_for_deletion():points.append(p)
 check(points.size()>=2,"B has ordinary resource sources outside its vacant lot")
 if points.size()>=2:
  for p in points:p.remaining=p.max_amount-3
  g.world.sync()
  for p in points:check(not g.world.regeneration_blocked(g.world.key(),g.world.locations[g.world.key()][p.world_id]),"existing B source is not inside vacant building footprint")
  var inside=points[0];var outside=points[1]
  inside.position=Vector2(760,640)
  g.world.locations[g.world.key()][inside.world_id].anchor=760.0
  g.world.sync();g.director.elapsed+=60.0;g.world.tick(0.0)
  g.storage.inventory.counts={GameData.Item.WOOD:4,GameData.Item.STONE:2}
  check(g.world.build_current_site(),"normal construction payment succeeds")
  var inside_before:int=inside.remaining;var outside_before:int=outside.remaining
  g.director.elapsed+=600.0;g.world.tick(0.0)
  check(inside.remaining==inside_before and outside.remaining>outside_before,"built footprint alone blocks growth; other B resources continue")
  check(g.world.remove_current_site(),"normal empty-site removal succeeds")
  check(inside.remaining==inside_before,"demolition grants no immediate full deposit")
  g.director.elapsed+=59.0;g.world.tick(0.0)
  check(inside.remaining==inside_before,"blocked elapsed time is not backfilled")
  g.director.elapsed+=1.0;g.world.tick(0.0)
  check(inside.remaining==inside_before+1,"demolished footprint resumes preserved fractional credit")
  var d_row:Dictionary=g.world.locations[g.world.key()][outside.world_id]
  check(not regen.within_footprint(d_row,WorldTrip.REGION_A_BUILD.d_yard.footprint),"D vacant-lot bounds likewise exclude normal resource anchors")
 # Growth helper cannot commandeer rescue, injury or player withdrawal.
 var session=load("res://bridge/route_connection_session.gd").new()
 var base_resource:={"item":GameData.Item.STONE,"kind":"rock","initial":0,"remaining":0,"reservation":""}
 base_resource.regeneration=regen.create(3,0.0);base_resource.entry_regeneration=regen.create(3,0.0);base_resource.regenerated=0
 session.resources={"fixture":base_resource}
 session.actors={"down":{"state":"down","down":true,"hp":0.0,"role":"harvest","wait_reason":session.ResourceGrowth.WAIT_REASON},"injured":{"state":"injured_wait","down":false,"hp":1.0,"role":"harvest","wait_reason":""},"rescue":{"state":"rescue_hold","down":false,"hp":10.0,"role":"harvest","wait_reason":""}}
 var actors_before:Dictionary=session.actors.duplicate(true)
 session.elapsed=120.0;session.ResourceGrowth.tick(session)
 check(session.actors==actors_before,"regeneration does not change down, injured or rescue owners")
 session.phase="recall";session.actors={"recall":{"state":"idle","down":false,"hp":20.0,"role":"harvest","wait_reason":session.ResourceGrowth.WAIT_REASON}}
 actors_before=session.actors.duplicate(true);session.elapsed=240.0;session.ResourceGrowth.tick(session)
 check(session.actors==actors_before,"regeneration cannot cancel manual recall")
 g.free()
 finish()
func finish() -> void:
 print("resource_regeneration: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
