extends SceneTree
const PATH := "user://c-rescue-runtime.json"
var main
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
 assertions+=1;print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures+=1
func fresh() -> void:
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true;main.set_meta("diagnostic_seed",104729)
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for worker in main.workers:
  worker.stop_work()
  for job in GameData.job_list():worker.priorities[job]=0
func select_id(option: OptionButton,id: String) -> void:
 for i in option.item_count:
  if str(option.get_item_metadata(i))==id:option.select(i);option.item_selected.emit(i);return
 check(false,"selector has "+id)
func down_and_bind(field) -> Callable:
 field.process_mode=Node.PROCESS_MODE_DISABLED
 for i in 100:
  field.life_clock.tick(0.05)
  if field.session.actors["worker:0"].state=="harvesting":break
 field.session._begin_outpost_down("worker:0",field.session.actors["worker:0"])
 var panel=field.rescue_panel;panel.open_panel()
 select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 return panel.assign_button.get_signal_connection_list("pressed")[0].callable
func run() -> void:
 var home:=OS.get_environment("FLUID_TEST_HOME").simplify_path().trim_suffix("/")
 if home.is_empty() or not OS.get_user_data_dir().simplify_path().begins_with(home+"/"):quit(2);return
 SaveGame.disabled=true;paused=false
 await fresh()
 for dest in ["b_forest","c_quarry"]:
  check(main.world.request(dest),"normal trip requests "+dest)
  for i in 400:
   main._process(0.25);await process_frame
   if main.world.region==dest and main.world.phase=="stopped":break
 SaveGame.disabled=false
 check(SaveGame.write(main,PATH,true),"actual safe pre-field save written")
 var saved:=SaveGame.read(PATH)
 var digest:=FileAccess.get_sha256(PATH)
 var old_main_id:int=main.get_instance_id()
 var gate=main.mine_arrival_gate;gate._process(0.0)
 check(gate.enter_mine(),"first actual default field opens")
 var old_field=gate.field
 var old_session=old_field.session
 var old_clock=old_field.life_clock
 var old_callback:=down_and_bind(old_field)
 var old_panel=old_field.rescue_panel
 var old_token:String=old_session.life_clock_token
 check(old_callback.is_valid() and old_clock.is_current(),"original callback and clock are live")
 check(gate.fail_field_to_menu("runtime teardown characterization"),"supported failure handoff removes field")
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var old_snapshot:Dictionary=old_session.to_dict()
 old_callback.call()
 check(old_session.to_dict()==old_snapshot,"queued valid callback after detach rejects before deletion")
 await process_frame
 check(not is_instance_valid(old_field) and not is_instance_valid(old_panel),"actual adapter and panel destroyed")
 check(not old_callback.is_valid(),"freed callback is invalid and must not be dispatched")
 paused=false
 main.free();main=null
 await process_frame
 check(not is_instance_id_valid(old_main_id),"old Main actually destroyed")
 await fresh()
 check(main.get_instance_id()!=old_main_id and SaveGame.apply(main,saved),"new Main applies real prior save")
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var restored:=SaveGame.capture(main)
 for key in ["world","inventory","operations","main","town","crew"]:
  check(restored[key]==saved[key],"literal recreation restores exact "+key)
 var new_gate=main.mine_arrival_gate;new_gate._process(0.0)
 check(new_gate.enter_mine(),"recreated Main opens new actual field")
 var field=new_gate.field
 field.process_mode=Node.PROCESS_MODE_DISABLED
 var session=field.session
 var current_callback:=down_and_bind(field)
 check(session.life_clock_token!=old_token and field.life_clock.is_current(),"new field has independent current runtime identity")
 var new_snapshot:Dictionary=session.to_dict()
 var game_snapshot:=SaveGame.capture(main)
 # A retained RefCounted clock is valid even after its owner Node is freed.
 # Calling it is distinct from dispatching a known-invalid freed Node callback.
 check(not old_clock.is_current(),"retained clock detects freed original Main")
 old_clock.tick(2.0)
 check(not old_clock.bound,"retained stale clock becomes unbound without dereferencing freed Main")
 check(old_session.to_dict()==old_snapshot and session.to_dict()==new_snapshot,"old tick changes neither old nor recreated session")
 check(SaveGame.capture(main)==game_snapshot,"old tick changes no recreated people/resources/time")
 check(current_callback.is_valid(),"current rescue callback remains callable")
 current_callback.call()
 check(session.rescue_ledger.case_for("worker:0").phase=="assigned","new runtime still accepts its own manual rescue")
 check(old_session.to_dict()==old_snapshot,"new rescue does not alter old session")
 var before_time:float=session.elapsed
 field.life_clock.tick(0.1)
 check(session.elapsed>before_time and field.life_clock.is_current(),"new runtime clock advances normally")
 check(FileAccess.get_sha256(PATH)==digest,"runtime teardown and callbacks never rewrite saved file")
 SaveGame.disabled=true
 field.rescue_panel.refresh_status()
 var queued_cancel:Callable=field.rescue_panel.cancel_button.get_signal_connection_list("pressed")[0].callable
 var retiring_clock=field.life_clock
 var retiring_snapshot:Dictionary=session.to_dict()
 main.queue_free()
 queued_cancel.call()
 check(session.to_dict()==retiring_snapshot,"valid current rescue cancellation is rejected when Main is queued")
 check(not retiring_clock.is_current(),"queued Main is no longer a current runtime")
 retiring_clock.tick(0.2)
 check(not retiring_clock.bound and session.to_dict()==retiring_snapshot,"queued owner cannot advance its retained clock before destruction")
 await process_frame
 check(not is_instance_valid(main),"queued Main actually finishes destruction")
 main=null
 retiring_clock.tick(0.2)
 check(session.to_dict()==retiring_snapshot,"same retained clock remains inert after queued destruction")
 await fresh()
 check(SaveGame.apply(main,saved),"third Main loads same safe save for detach boundary")
 main.process_mode=Node.PROCESS_MODE_DISABLED
 var detach_gate=main.mine_arrival_gate;detach_gate._process(0.0)
 check(detach_gate.enter_mine(),"detach boundary has real current field")
 var detach_clock=detach_gate.field.life_clock
 var detach_session=detach_gate.field.session
 var detach_before:Dictionary=detach_session.to_dict()
 root.remove_child(main)
 check(is_instance_valid(main) and not main.is_inside_tree(),"owner remains live but detached")
 check(not detach_clock.is_current(),"detached Main is not a current runtime")
 detach_clock.tick(0.2)
 check(not detach_clock.bound and detach_session.to_dict()==detach_before,"detached owner clock is inert without null-tree access")
 main.free();main=null
 await process_frame
 print("C RESCUE RECREATED RUNTIME assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
