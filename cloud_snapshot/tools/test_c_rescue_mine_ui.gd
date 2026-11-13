extends SceneTree
## Actual default C gate and headless viewport pointer commands, not OS input.
const Session = preload("res://bridge/route_connection_session.gd")
var main
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
 assertions+=1;print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures+=1
func click(button: Control) -> void:
 await process_frame;await process_frame
 var point:=button.get_global_rect().get_center()
 var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
 await process_frame
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
  root.push_input(event,true);await process_frame
func select_id(option: OptionButton,id: String) -> void:
 for i in option.item_count:
  if str(option.get_item_metadata(i))==id:option.select(i);option.item_selected.emit(i);return
 check(false,"selector contains "+id)
func advance(clock,predicate: Callable) -> bool:
 for i in 1200:
  if predicate.call():return true
  clock.tick(0.05)
 return predicate.call()
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true;main.set_meta("diagnostic_seed",104729)
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"normal trip requests "+destination)
  for i in 400:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
 var gate=main.mine_arrival_gate;gate._process(0.0)
 check(gate.enter_mine(),"actual normal gate opens default C session")
 if gate.field==null:await finish();return
 var adapter=gate.field
 adapter.set_process(false)
 var s=adapter.session
 check(s.mine_path_engineering and not s.outpost_enabled and not s.vertical_slice,"default field uses ordinary mine corridors, not outpost override")
 var clock=adapter.life_clock
 var panel=adapter.rescue_panel
 # Keep the actual carrier entry formation; no actor position injection for it.
 for a in s.actors.values():a.state="idle";a.path=[]
 var formation:=Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)
 var count:int=main.workers.size()
 var original_cases:Dictionary=main.operations.rescue_cases.duplicate(true)
 var source_before:Dictionary=main.world.locations.duplicate(true)
 var enemies_before:Dictionary=main.world.outpost_states.duplicate(true)
 var rewards:int=main.total_gathered
 var credits:int=main.town.credits
 var resource_id:String=s.resources.keys()[0]
 var item:int=s.resources[resource_id].item
 var remaining:int=s.resources[resource_id].remaining
 var stock:int=main.storage.inventory.count(item)
 s.resources[resource_id].remaining-=2
 s.actors["worker:0"].carry_n=2;s.actors["worker:0"].carry_item=item
 s.actors["worker:0"].x=Session.RESOURCE.x;s.actors["worker:0"].y=Session.RESOURCE.y
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 check(s.conservation_ok(),"loaded down fixture conserves actual finite resources")
 await click(adapter.rescue_toggle)
 select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 check(not panel.assign_button.disabled,"default mine panel enables reachable manual assignment")
 await click(panel.assign_button)
 check(s.actors["worker:2"].state=="rescue_move","viewport pointer assigns default mine rescue")
 if s.actors["worker:2"].state!="rescue_move":await finish();return
 check(Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y)==formation and s.actors["worker:2"].path[0]==s._point_array(Session.BASE),"real entry formation connects via staging BASE without teleport")
 check(advance(clock,func():return s.actors["worker:2"].state=="rescue_hold"),"real default clock physically reaches holding target")
 check(s.actors["worker:0"].carry_n==2 and s.actors["worker:0"].down,"pickup preserves person and cargo")
 panel.refresh_status();await click(panel.return_button)
 check(s.actors["worker:2"].state=="rescue_return","viewport pointer starts actual mine entrance transport")
 clock.tick(0.3)
 var dropped:=Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)
 panel.refresh_status();await click(panel.cancel_button)
 check(s.rescue_ledger.case_for("worker:0").phase=="waiting" and Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)==dropped,"pointer interruption drops at exact intermediate mine position")
 select_id(panel.carrier_option,"worker:2")
 await click(panel.assign_button)
 check(s.actors["worker:2"].state=="rescue_move" and not s.rescue_approach.has_mine_return("worker:2"),"new manual assignment transfers released carrier ownership exactly once")
 check(advance(clock,func():return s.actors["worker:2"].state=="rescue_hold"),"same-position re-pickup holds without teleport")
 panel.refresh_status();await click(panel.return_button)
 check(advance(clock,func():return s.actors["worker:0"].state=="rescue_treatment"),"default mine real transport reaches entrance treatment")
 check(main.operations.rescue_cases==original_cases and main.world.locations==source_before and main.storage.inventory.count(item)==stock,"normal Worker/inventory/source authority waits for safe commit")
 check(SaveGame.disabled and not SaveGame.write(main,"user://mine-rescue-forbidden.json",true),"default mine rescue keeps field save forbidden")
 s.request_recall()
 check(advance(clock,func():return s.phase=="ready_to_exit"),"normal timed dock and recall permit exit")
 check(s.conservation_ok() and s.depot_stock.get(item,0)==2 and s.actors["worker:0"].carry_n==0,"default mine cargo docks once")
 adapter._commit_and_exit();main.process_mode=Node.PROCESS_MODE_DISABLED
 check(s.committed and gate.field==null,"actual adapter exit commits default mine treatment")
 check(main.workers.size()==count and main.workers[0].hp==CrewStatusDB.HP_REVIVE_AT and not main.workers[0].down and main.operations.rescue_phase_for(main.workers[0])=="recovering","handoff preserves people and existing recovery state")
 check(main.storage.inventory.count(item)==stock+2 and main.world.locations[Session.SOURCE_KEY][resource_id].data.remaining==remaining-2,"default commit conserves finite source and cargo")
 check(main.world.outpost_states==enemies_before and main.total_gathered==rewards and main.town.credits==credits,"normal mine rescue changes no enemy fixture, rewards or credits")
 var after:=SaveGame.capture(main)
 check(s.commit_to_game(main).get("already_committed",false) and SaveGame.capture(main)==after,"default repeated commit does not replay state")
 await finish()
func finish() -> void:
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("C RESCUE MINE UI assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
