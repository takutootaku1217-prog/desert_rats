extends SceneTree
const Session=preload("res://bridge/route_connection_session.gd")
const PATH:="user://resource-regeneration-field.json"
const RECEIPT:="user://resource-regeneration-receipt.json"
var g
var checks:=0
var failures:=0
func _init() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
 checks+=1;print("%s %s" % ["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func advance(c,seconds:float) -> void:
 for unused in ceili(seconds/0.05):c.tick(0.05)
func run() -> void:
 var home:=OS.get_environment("FLUID_TEST_HOME")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").begins_with(home.replace("\\","/")):quit(2);return
 SaveGame.disabled=true
 g=load("res://scenes/main.tscn").instantiate();g.first_region_a_pilot=true;g.set_meta("diagnostic_seed",104729)
 root.add_child(g);await process_frame;g.process_mode=Node.PROCESS_MODE_DISABLED
 var saved:=SaveGame.read(PATH)
 var receipt=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
 check(not saved.is_empty() and receipt is Dictionary,"prior-process regeneration save and receipt")
 if failures:await finish();return
 check(receipt.pid!=OS.get_process_id() and receipt.hash==FileAccess.get_sha256(PATH),"independent PID and exact producer file hash")
 SaveGame.disabled=false
 check(SaveGame.apply(g,saved),"fresh process restores regenerated field")
 var gate=g.mine_arrival_gate
 if gate.field==null:await finish();return
 var a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED
 var s=a.session;var c=a.life_clock
 check(s.resources==saved.field_snapshot.session.resources and g.director.elapsed==saved.director.elapsed and is_equal_approx(g.director.elapsed,float(receipt.elapsed)),"restart adds no offline time or resource units")
 var before:Dictionary=s.to_dict();c.tick(10.0)
 check(paused and s.to_dict()==before,"loaded pause halts resource and survival clocks")
 var bad:=saved.duplicate(true);var id=s.resources.keys()[0]
 bad.field_snapshot.session.resources[id].regeneration="wrong type"
 check(not SaveGame.validate(bad,g),"malformed regeneration metadata safely rejected")
 a._toggle_field_pause();advance(c,120.0)
 check(s.ResourceGrowth.total(s)==int(receipt.accounted)+s.resources.size() and s.conservation_ok(),"resumed game-time settles each C source once")
 var duplicate=Session.from_dict(s.to_dict()).session
 duplicate.session_id+="-foreign"
 var foreign_clock:=FieldSurvivalClock.new()
 check(not foreign_clock.setup(g,duplicate).ok and g.world.regeneration_owner==s,"distinct live clock cannot steal C source lease")
 g.world.regeneration_owner=s # Fixture cleanup if the RED operation wrongly stole it.
 duplicate=Session.from_dict(s.to_dict()).session
 var replacement_clock:=FieldSurvivalClock.new()
 check(replacement_clock.setup(g,duplicate).ok,"same-session current snapshot can replace clock owner")
 var before_old_tick:float=g.director.elapsed
 c.tick(0.05)
 check(not c.is_current() and g.director.elapsed==before_old_tick,"replaced same-generation clock cannot tick again")
 check(c.setup(g,s).ok,"unchanged fixture hands source lease back explicitly")
 s.request_recall()
 for unused in 2400:
  c.tick(0.05)
  if s.phase=="ready_to_exit":break
 check(s.phase=="ready_to_exit","regenerated cargo returns through natural recall")
 var replay=Session.from_dict(s.to_dict())
 var stock:Dictionary=g.storage.inventory.counts.duplicate(true)
 var cargo:Dictionary=s.depot_stock.duplicate(true)
 a._commit_and_exit();g.process_mode=Node.PROCESS_MODE_DISABLED
 check(s.committed and gate.field==null and g.world.regeneration_owner==null,"return commits and releases sole C authority")
 for item in cargo:check(g.storage.inventory.count(item)==int(stock.get(item,0))+cargo[item],"only actually transported cargo enters inventory")
 var committed:Dictionary=SaveGame.capture(g)
 check(s.commit_to_game(g).get("already_committed",false) and SaveGame.capture(g)==committed,"same session duplicate return is inert")
 check(replay.ok and not replay.session.commit_to_game(g).ok,"independent stale session replay is rejected")
 check(SaveGame.write(g,"user://resource-regeneration-return.json"),"normal save after regenerated return")
 # Legacy complete snapshot built from an unmodified fresh entry, no new gains.
 gate._dismissed_here=false;gate._process(0.0)
 check(gate.enter_mine(),"normal revisit reopens after committed regeneration")
 if gate.field!=null:
  a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED
  var legacy:Dictionary=SaveGame.capture(g)
  legacy.world.erase("resource_regeneration_version")
  for rows in legacy.world.locations.values():
   for row in rows.values():row.erase("regeneration")
  legacy.field_snapshot.session.schema=9
  # Authentic old schema has no independent encounter extension.
  legacy.field_snapshot.session.erase("encounter_id");legacy.field_snapshot.session.erase("encounter_entry")
  var legacy_resources:Dictionary=legacy.field_snapshot.session.resources
  for key in legacy_resources.keys():
   var r:Dictionary=legacy_resources[key]
   if r.initial==0:legacy_resources.erase(key);continue
   for column in ["regenerated","regeneration","entry_regeneration"]:r.erase(column)
  check(SaveGame.validate(legacy,g),"schema9 complete snapshot explicitly migrates")
  check(SaveGame.apply(g,legacy),"legacy snapshot installs as one current owner")
  a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED;s=a.session;c=a.life_clock
  check(s.ResourceGrowth.total(s)==0 and s.conservation_ok(),"legacy migration grants no pre-save regeneration")
  for r in s.resources.values():check(r.regeneration.last==g.director.elapsed and r.regeneration.credit==0.0,"legacy clock starts at saved game time")
  check(SaveGame.validate(SaveGame.capture(g),g),"migrated snapshot can be captured again")
 await finish()
func finish() -> void:
 SaveGame.disabled=true
 if is_instance_valid(g):g.queue_free()
 await process_frame
 print("resource_regeneration_restart: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
