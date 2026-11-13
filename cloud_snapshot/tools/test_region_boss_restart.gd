extends SceneTree
const PATH:="user://region-boss-field.json"
const RECEIPT:="user://region-boss-receipt.json"
var main
var assertions:=0
var failures:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1
 print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func advance(clock,predicate:Callable,seconds:float)->bool:
 for unused in ceili(seconds/0.05):
  if predicate.call():return true
  clock.tick(0.05)
 return predicate.call()
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 var receipt=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
 check(receipt is Dictionary and int(receipt.pid)!=OS.get_process_id(),"consumer uses a distinct real engine process")
 if not receipt is Dictionary:await finish();return
 check(FileAccess.get_sha256(PATH)==receipt.hash,"file unchanged since producer")
 var snapshot:=SaveGame.read(PATH)
 SaveGame.disabled=false
 check(SaveGame.apply(main,snapshot),"real-file mid-boss load installs one runtime")
 var gate=main.mine_arrival_gate
 if gate.field==null:await finish();return
 var a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED
 var s=a.session
 check(paused and s.outpost_enemies.size()==1 and s.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp==float(receipt.hp),"loaded paused with exact one damaged boss")
 check(s.outpost_enemies==snapshot.field_snapshot.session.outpost_enemies,"all combat identity/target/HP values survive restart")
 check(main.world.regeneration_owner==s and a.life_clock.is_current(),"new process has one source and life-clock owner")
 var before:Dictionary=s.to_dict()
 a.life_clock.tick(1.0)
 check(s.to_dict()==before,"paused load cannot move/heal/regenerate")
 a._toggle_field_pause()
 # Explicit down injection, after natural combat motion. Rescue itself uses its
 # public assignment/return APIs and actual paths; not an OS combat-down claim.
 s._begin_outpost_down("worker:2",s.actors["worker:2"]);a.life_clock.tick(0.05)
 check(SaveGame.validate(SaveGame.capture(main),main),"down boss fighter saves without losing timer/identity")
 check(s.request_rescue("worker:2","worker:0",s.session_id).ok,"independent boss uses existing manual rescue on witnessed path")
 a.life_clock.tick(0.05)
 var rescue:=SaveGame.capture(main)
 check(SaveGame.validate(rescue,main),"active boss rescue owner/path validates")
 var old_clock=a.life_clock
 check(SaveGame.apply(main,rescue),"rescue snapshot installs without duplicate carrier")
 a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED;s=a.session
 check(not old_clock.is_current() and s.rescue_approach._owned=={"worker:0":"worker:2"},"old clock expires and exact manual carrier restored")
 a._toggle_field_pause()
 check(advance(a.life_clock,func():return s.rescue_ledger.case_for("worker:2").get("phase")=="carried",60.0),"rescuer physically reaches downed boss fighter")
 check(SaveGame.validate(SaveGame.capture(main),main),"carried fighter/boss snapshot keeps one owner")
 check(s.request_rescue_return("worker:2",s.session_id).ok,"manual rescue return begins")
 s.request_recall()
 check(advance(a.life_clock,func():return s.phase=="ready_to_exit",100.0),"physical rescue and all crew/cargo return")
 check(SaveGame.validate(SaveGame.capture(main),main),"rescued ready-to-exit boss snapshot validates")
 var partial_hp:float=s.outpost_enemies[FirstRegionCompletion.BOSS_ID].hp
 a._commit_and_exit();await process_frame
 check(gate.field==null and s.committed and not main.world.region_goal_snapshot().boss_returned,"rescued retreat commits partial damage, not victory")
 check(main.world.region_completion.encounters[FirstRegionCompletion.ENCOUNTER_ID].enemies[FirstRegionCompletion.BOSS_ID].hp==partial_hp,"rescue return preserves enemy damage independently")
 check(SaveGame.write(main,"user://region-boss-rescued.json",true),"rescued committed normal save writes")
 # Explicit road-first fixture; paid road gameplay is exercised in return test.
 var road_first:=snapshot.duplicate(true);road_first.world.region_state.roads.bd.cleared=true
 check(SaveGame.apply(main,road_first),"road-first saved state remains valid before victory")
 a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED;s=a.session;a._toggle_field_pause()
 check(advance(a.life_clock,func():return s.outpost_cleared,60.0),"resumed real fight defeats boss")
 check(SaveGame.validate(SaveGame.capture(main),main),"just-defeated snapshot remains valid before return")
 check(not main.world.region_goal_snapshot().completed,"road plus unreturned defeat is still incomplete")
 s.request_recall()
 check(advance(a.life_clock,func():return s.phase=="ready_to_exit",80.0),"resumed victory physically returns")
 var stale=s.to_dict()
 a._commit_and_exit();await process_frame
 check(gate.field==null and main.world.region_goal_snapshot().completed,"road-first then victory return completes region")
 for unused in 3:await process_frame
 check(main.region_clear_ui.is_open() and paused,"road-first acknowledgement waits until horizontal return")
 main.region_clear_ui.acknowledge()
 for unused in 3:await process_frame
 var done:=SaveGame.capture(main)
 check(SaveGame.validate(done,main),"completed return save validates")
 var restored=load("res://bridge/route_connection_session.gd").from_dict(stale)
 check(restored.ok and not restored.session.commit_to_game(main).ok,"stale battle replay cannot publish/duplicate after return")
 check(not main.world.refresh_region_completion() and SaveGame.capture(main)==done,"repeat completion does not emit or mutate")
 check(SaveGame.write(main,"user://region-completed.json",true),"completed real normal save writes")
 check(SaveGame.apply(main,SaveGame.read("user://region-completed.json")) and main.world.region_goal_snapshot().completed,"completed normal reload stays completed")
 check(main.world.request("b_forest"),"free travel remains available after endpoint")
 await finish()
func finish()->void:
 SaveGame.disabled=true
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("REGION BOSS RESTART assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
