extends SceneTree
## Separate battle fixture: real route, pointer entry and existing battle logic.
## Priorities/director disabled for determinism. Injury/down cases explicitly
## adjust HP only to test safeguards, not to claim a normal survival playthrough.
var main
var failures := 0
const STEP := 0.2
func _init() -> void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print("%s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func fresh()->void:
 paused=false
 if is_instance_valid(main):main.queue_free();await process_frame
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for worker in main.workers:
  worker.stop_work()
  for job in GameData.job_list():worker.priorities[job]=0
 for dest in ["b_forest","c_quarry"]:
  check(main.world.request(dest),"request real route leg "+dest)
  for unused in range(300):
   main._process(STEP);await process_frame
   if main.world.region==dest and main.world.phase=="stopped":break
 check(main.mine_arrival_gate.visible_state()=="arrival_choice","normal C arrival offers choices")
func pointer(button:Button)->void:
 var p:Vector2=button.get_global_transform_with_canvas()*(button.size/2.0)
 var window=button.get_viewport()
 if window!=root:
  p=Vector2(window.position)+window.get_final_transform()*p
 var move:=InputEventMouseMotion.new();move.position=p;root.push_input(move,true);await process_frame
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=p;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
  root.push_input(event,true);await process_frame
func consent_to_outpost()->bool:
 var gate=main.mine_arrival_gate
 await pointer(gate._outpost_button)
 var awaiting:bool=gate.is_outpost_confirmation_open() and gate._outpost_dialog.visible and gate.field==null and paused
 check(awaiting,"pointer danger request waits for explicit consent without a session")
 if not awaiting:return false
 await pointer(gate._outpost_dialog.get_ok_button())
 check(not gate.is_outpost_confirmation_open(),"pointer confirmation consumes pending consent")
 return not gate.is_outpost_confirmation_open()
func enter_outpost(pending := false)->bool:
 var gate=main.mine_arrival_gate
 var button=gate.get("_outpost_button")
 check(button!=null,"optional dangerous outpost entry button exists")
 if button==null:return false
 var rescue_guidance:Label=gate._panel.find_child("RescueGuidance",true,false)
 check(gate._outpost_warning.text.contains("前哨地") and gate._outpost_warning.text.contains("3体") and rescue_guidance!=null and rescue_guidance.is_visible_in_tree() and rescue_guidance.text.contains("手動") and rescue_guidance.text.contains("未救助者") and rescue_guidance.tooltip_text.contains("期限切れ後"),"warning separates outpost enemies, manual rescue and remaining limits")
 check(button.get_global_rect().end.y<720,"outpost button remains inside viewport")
 var old_floor:int=main.workers[0].floor_i
 if pending:main.workers[0].floor_i=0
 if not await consent_to_outpost():return false
 if pending:
  check(gate.visible_state()=="entry_wait" and gate._outpost_button.disabled and gate._enter_button.disabled,"outpost shares pending recall and locks both choices")
  check(not gate.enter_mine() and bool(gate._entry_options.get("outpost_enabled",false)),"repeated safe input cannot replace pending dangerous choice")
  main.workers[0].floor_i=old_floor
  gate._process(STEP)
 check(gate.field!=null,"pointer enters existing field adapter")
 if gate.field==null:return false
 gate.field.set_process(false) # Deterministic session ticks, real HUD input.
 check(gate.field.session.outpost_enabled and gate.field.session.outpost_enemy_total()==3,"chosen session enables exactly three existing enemies")
 return true
func advance(session,predicate:Callable,seconds:float)->bool:
 for unused in range(ceili(seconds/STEP)):
  session.tick(STEP);session.apply_projection_to_workers(main)
  if predicate.call():return true
 return predicate.call()
func run()->void:
 # Embedded-window fixture: root routes pointer hover/events to confirmation.
 # This remains synthetic viewport input, not a native OS playthrough.
 root.gui_embed_subwindows=true
 if OS.get_cmdline_user_args().has("hull-failure"):
  await fresh()
  if not await enter_outpost():finish();return
  main.base.parts[GameData.Part.HULL]=0.0 # Explicit existing gameover boundary.
  main.mine_arrival_gate.field.life_clock.tick(STEP)
  check(main.mine_arrival_gate.field==null and main.game_over and paused and main.save_ui._field_failure_lock,"field clock HULL loss uses common safe failure cleanup")
  finish();return
 if OS.get_cmdline_user_args().has("failure-recovery"):
  await failure_recovery();return
 if OS.get_cmdline_user_args().has("normal-director"):
  await normal_director_route();return
 await fresh()
 if not await enter_outpost(true):finish();return
 var gate=main.mine_arrival_gate
 var session=gate.field.session
 var entry_hp:float=session.actors["worker:2"].hp
 check(advance(session,func():return session.actors["worker:2"].state=="combat",60),"existing escort reaches real battle")
 check(advance(session,func():return session.actors["worker:2"].hp<entry_hp,15),"existing enemies inflict actual HP damage")
 session.request_recall()
 check(advance(session,func():return session.phase=="ready_to_exit",90),"early withdrawal returns all actors")
 var stock:Dictionary=main.storage.inventory.counts.duplicate(true)
 gate.field._update_controls();await process_frame
 var return_hud=gate.field.get_node("FieldVehicleStatus/Contents/Actions/Return")
 print("RETURN_HUD before ",return_hud.get_global_rect()," disabled=",return_hud.disabled," text=",return_hud.text," current=",gate.field._return_context_current())
 await pointer(return_hud)
 if gate.field!=null:print("RETURN_HUD after phase=",session.phase," reason=",gate.field._return_failure," hover=",root.gui_get_hovered_control())
 check(gate.field==null and main.visible,"early withdrawal commits and restores horizontal view")
 check(main.workers[2].hp<entry_hp,"battle damage persists after return")
 check(main.storage.inventory.counts==stock,"early battle-only retreat creates no reward resources")
 await fresh()
 if not await enter_outpost():finish();return
 gate=main.mine_arrival_gate;session=gate.field.session
 # Deliberate down-state boundary fixture, no recovery injection.
 session.actors["worker:2"].hp=0.0;session.actors["worker:2"].down=false
 session.tick(STEP);session.apply_projection_to_workers(main);session.request_recall()
 var result:Dictionary=session.commit_to_game(main)
 check(not result.get("ok",false) and str(result.get("reason","")).contains("戦闘不能"),"down actor explicitly blocks unsafe commit until recovery")
 check(gate.has_method("fail_field_to_menu"),"down field has a safe failure-menu escape")
 if gate.has_method("fail_field_to_menu"):
  check(gate.fail_field_to_menu("戦闘不能：検証失敗"),"failed field closes without commit")
  check(gate.field==null and main.game_over and paused and main.save_ui.is_open(),"failure exposes existing load/new menu and pauses")
  main.save_ui.close()
  check(main.save_ui.is_open() and paused,"closing failed menu cannot resume incomplete run")
  main.save_ui.ask("save")
  check(main.save_ui._action=="" and SaveGame.disabled,"failed run cannot be saved")
 await fresh()
 gate=main.mine_arrival_gate
 var original_floor:int=main.workers[0].floor_i
 main.workers[0].floor_i=0
 if not await consent_to_outpost():finish();return
 await pointer(gate._cancel_button)
 main.workers[0].floor_i=original_floor
 check(gate.visible_state()=="arrival_choice" and gate._entry_options.is_empty(),"cancel discards dangerous-entry option")
 await pointer(gate._enter_button)
 check(gate.field!=null and not gate.field.session.outpost_enabled,"ordinary entry remains safe after dangerous choice cancellation")
 finish()
func normal_director_route()->void:
 var previous_scale:=Engine.time_scale
 Engine.time_scale=20.0;SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729);root.add_child(main);await process_frame
 main.map_ui.open();main.map_ui.select_region("c_quarry");main.map_ui._go()
 for unused in range(3600):
  await process_frame
  if main.mine_arrival_gate.visible_state()=="arrival_choice":break
 var gate=main.mine_arrival_gate
 check(gate.visible_state()=="arrival_choice" and main.director.enabled,"normal priorities and enabled director reach C")
 if gate.visible_state()!="arrival_choice":Engine.time_scale=previous_scale;finish();return
 if not await consent_to_outpost():Engine.time_scale=previous_scale;finish();return
 for unused in range(2400):
  await process_frame
  if gate.field!=null:break
 check(gate.field!=null,"normal pointer outpost entry resolves readiness")
 if gate.field==null:Engine.time_scale=previous_scale;finish();return
 var session=gate.field.session
 var hp_before:float=session.actors["worker:2"].hp
 var clock_before:float=main.director.elapsed
 var food_before:int=main.storage.count_of(GameData.Item.FOOD)
 var fuel_before:float=main.base.fuel
 for unused in range(2400):
  await process_frame
  if session.actors["worker:2"].hp<hp_before or main.game_over:break
 check(main.director.enabled and not main.game_over and session.actors["worker:2"].hp<hp_before,"enabled director and live field produce battle injury")
 session.request_recall()
 for unused in range(2400):
  await process_frame
  if session.phase=="ready_to_exit" or main.game_over:break
 check(session.phase=="ready_to_exit" and not main.game_over,"enabled director early retreat reaches exit")
 if session.phase=="ready_to_exit":gate.field._commit_and_exit();await process_frame
 check(gate.field==null and main.visible,"enabled director retreat commits to horizontal view")
 check(main.director.elapsed>clock_before,"normal world clock advances during battle and retreat")
 print("NORMAL_OUTPOST_LEDGER ",JSON.stringify({"director_enabled":main.director.enabled,"director_before":clock_before,"director_after":main.director.elapsed,"fuel_before":fuel_before,"fuel_after":main.base.fuel,"food_before":food_before,"food_after":main.storage.count_of(GameData.Item.FOOD),"escort_hp_before":hp_before,"escort_hp_after":main.workers[2].hp,"game_over":main.game_over}))
 Engine.time_scale=previous_scale
 finish()
func failure_recovery()->void:
 await fresh()
 var path:="user://v3-failure-restore.json"
 SaveGame.disabled=false
 check(SaveGame.write(main,path,true),"write isolated valid pre-entry save through real API")
 var saved_hash:=FileAccess.get_sha256(path)
 var saved_stock:Dictionary=main.storage.inventory.counts.duplicate(true)
 var saved_hp:float=main.workers[2].hp
 main.save_ui.path=path
 if not await enter_outpost():finish();return
 var gate=main.mine_arrival_gate
 var session=gate.field.session
 session.actors["worker:2"].hp=0.0;session.actors["worker:2"].down=false
 session.tick(STEP);session.apply_projection_to_workers(main)
 gate._process(STEP)
 check(gate._field_failure_button.visible,"down state exposes failure exit control")
 session.tick(FieldOperations.RESCUE_SECONDS + FieldOperations.POST_EXPIRY_INCAPACITATION_SECONDS)
 gate._process(STEP)
 check(session.rescue_ledger.case_for("worker:2").is_empty() and session.expired_recovery.owns("worker:2") and gate._field_failure_button.visible,"post-expiry failure control stays usable without forced waiting")
 await pointer(gate._field_failure_button)
 check(gate.field==null and main.game_over and paused and main.save_ui.layer>70,"failure pointer opens topmost paused recovery menu")
 main.save_ui.close()
 check(main.save_ui.is_open() and paused,"cancel cannot resume failed session")
 check(not SaveGame.write(main,path,true) and FileAccess.get_sha256(path)==saved_hash,"failed state cannot overwrite existing save")
 main.save_ui.path=path+".missing"
 main.save_ui.ask("load");main.save_ui.execute();await process_frame
 check(main.game_over and paused and main.save_ui._field_failure_lock and FileAccess.get_sha256(path)==saved_hash,"failed read keeps failure lock and existing file unchanged")
 main.save_ui.path=path
 main.save_ui.ask("load");main.save_ui.execute();await process_frame
 check(not main.game_over and not main.save_ui._field_failure_lock and not SaveGame.disabled,"real load releases failure lock only after success")
 check(main.storage.inventory.counts==saved_stock and main.workers[2].hp==saved_hp,"load restores prior inventory and HP without adding field reward")
 main.save_ui.close()
 check(not paused,"successful recovery can resume normally")
 gate._process(STEP)
 check(gate.visible_state()=="arrival_choice","load resets failed gate for a new explicit decision")
 check(gate.enter_mine(true),"new deliberate outpost entry works after load")
 check(gate.fail_field_to_menu("新規開始検証"),"second failed run enters the same safe menu")
 current_scene=main
 var old_id:int=main.get_instance_id()
 main.save_ui.ask("new");main.save_ui.execute()
 await process_frame
 await process_frame
 main=current_scene
 check(is_instance_valid(main) and main.get_instance_id()!=old_id and not main.game_over and not paused,"confirmed new game reloads a fresh playable scene")
 check(not SaveGame.disabled and FileAccess.get_sha256(path)==saved_hash,"new game restores save permission without modifying prior file")
 finish()
func finish()->void:
 if is_instance_valid(main):main.queue_free()
 await process_frame
 SaveGame.disabled=false
 print("C optional outpost entry: %s"%("passed" if failures==0 else "%d failures"%failures))
 quit(1 if failures else 0)
