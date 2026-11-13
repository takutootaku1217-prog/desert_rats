extends SceneTree
const PATH := "user://resource-regeneration-field.json"
const RECEIPT := "user://resource-regeneration-receipt.json"
var g
var checks:=0
var failures:=0
func _init() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
 checks+=1;print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func advance(clock,seconds:float) -> void:
 for unused in ceili(seconds/0.05):clock.tick(0.05)
func run() -> void:
 var home:=OS.get_environment("FLUID_TEST_HOME")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").begins_with(home.replace("\\","/")):quit(2);return
 SaveGame.disabled=true
 g=load("res://scenes/main.tscn").instantiate();g.first_region_a_pilot=true;g.set_meta("diagnostic_seed",104729)
 root.add_child(g);await process_frame
 g.process_mode=Node.PROCESS_MODE_DISABLED;g.director.enabled=false
 for w in g.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for destination in ["b_forest","c_quarry"]:
  check(g.world.request(destination),"request normal trip "+destination)
  for unused in 300:
   g._process(0.25);await process_frame
   if g.world.region==destination and g.world.phase=="stopped":break
  check(g.world.region==destination and g.world.phase=="stopped","arrive "+destination)
 # Explicit depleted source fixture, with ordinary gate/path/clock thereafter.
 for p in g.resources_root.get_children():
  if p is GatherPoint:
   p.remaining=0;g.world.consume(p);p.get_parent().remove_child(p);p.queue_free()
 for row in g.world.locations["region:c_quarry"].values():
  if row.type=="gather":
   row.data.remaining=0;row.spent=true
   row.regeneration=ResourceRegeneration.create(row.data.max_amount,g.director.elapsed)
 g.world.set_c_quarry_cart_shortcut_cleared(true) # Legacy empty inspection was allowed only after clearance.
 var gate=g.mine_arrival_gate;gate._process(0.0)
 SaveGame.disabled=false
 check(gate.enter_mine(),"ordinary depleted C can enter and wait for game-time regrowth")
 if gate.field==null:await finish();return
 var a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED
 var s=a.session;var c=a.life_clock
 var initial_world:Dictionary=g.world.locations["region:c_quarry"].duplicate(true)
 var stock:Dictionary=g.storage.inventory.counts.duplicate(true)
 advance(c,119.0)
 check(s.total_source_remaining()==0,"C 119 seconds remains depleted")
 var legacy:Dictionary=SaveGame.capture(g)
 legacy.world.erase("resource_regeneration_version")
 for rows in legacy.world.locations.values():
  for row in rows.values():row.erase("regeneration")
 legacy.field_snapshot.session.schema=9;legacy.field_snapshot.session.resources={}
 # Authentic old schema has no independent encounter extension.
 legacy.field_snapshot.session.erase("encounter_id");legacy.field_snapshot.session.erase("encounter_entry")
 for actor in legacy.field_snapshot.session.actors.values():
  if actor.state=="idle":actor.wait_reason=""
 var migrated:Dictionary=CFieldSnapshot.prepare(legacy)
 check(not migrated.is_empty(),"old depleted C inspection snapshot migrates through full boundary")
 if not migrated.is_empty():
  migrated.session.tick(120.0)
  check(migrated.session.actors["worker:0"].state!="idle","legacy exhausted local harvester resumes on regenerated ground")
 advance(c,1.0)
 check(s.total_source_remaining()==s.resources.size(),"C each ordinary deposit regrows exactly once")
 check(s.initial_total()==0 and s.conservation_ok(),"entry amount stays immutable; regenerated amount balances cargo")
 for row in s.resource_ledger_by_item().values():check(row.conservation_ok,"per-item regenerated conservation")
 g.world.sync()
 check(g.world.locations["region:c_quarry"]==initial_world,"Main C ledger is frozen while session owns regeneration")
 check(g.storage.inventory.counts==stock,"field regeneration grants no warehouse inventory")
 check(s.actors["worker:0"].state!="idle","resource-wait harvest actor restarts through ordinary path")
 advance(c,30.0)
 check(s._stock_total(s.depot_stock)>0 and s.conservation_ok(),"regenerated minerals naturally harvest, relay and dock")
 var saved:Dictionary=SaveGame.capture(g)
 check(SaveGame.validate(saved,g),"regenerated complete field snapshot validates")
 var id=s.resources.keys()[0]
 var bad:Dictionary=saved.duplicate(true);bad.field_snapshot.session.resources[id].regenerated+=1
 check(not SaveGame.validate(bad,g),"forged extra regenerated cargo rejected")
 bad=saved.duplicate(true);bad.world.locations["region:c_quarry"][id].regeneration.revision+=1
 check(not SaveGame.validate(bad,g),"changed entry revision rejected")
 bad=saved.duplicate(true);bad.field_snapshot.session.schema=Vector2(1,2)
 check(not SaveGame.validate(bad,g),"noninteger session regeneration schema safely rejected")
 check(SaveGame.write_field(g,PATH),"real field save with regeneration written")
 if SaveGame.exists(PATH):
  var receipt:=FileAccess.open(RECEIPT,FileAccess.WRITE)
  receipt.store_string(JSON.stringify({"pid":OS.get_process_id(),"hash":FileAccess.get_sha256(PATH),"elapsed":g.director.elapsed,"initial":s.initial_total(),"accounted":s.total_source_remaining()+s.carried_total()+s._stock_total(s.relay_stock)+s._stock_total(s.depot_stock)}));receipt.close()
 await finish()
func finish() -> void:
 SaveGame.disabled=true
 if is_instance_valid(g):g.queue_free()
 await process_frame
 print("resource_regeneration_field: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
