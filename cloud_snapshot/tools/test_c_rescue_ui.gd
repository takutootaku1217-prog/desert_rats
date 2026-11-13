extends SceneTree
const Session = preload("res://bridge/route_connection_session.gd")
var assertions := 0
var failures := 0
var main
var field
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 assertions += 1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures += 1
func click(button: Control) -> void:
 await process_frame
 await process_frame
 var point := button.get_global_rect().get_center()
 var motion := InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
 await process_frame
 for down in [true,false]:
  var event := InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
  root.push_input(event,true);await process_frame
func select_id(option: OptionButton, actor_id: String) -> void:
 for i in option.item_count:
  if str(option.get_item_metadata(i)) == actor_id:
   option.select(i)
   option.item_selected.emit(i)
   return
 check(false,"selector contains actor " + actor_id)
func pressed_callback(button: Button) -> Callable:
 return button.get_signal_connection_list("pressed")[0].callable
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
 for dest in ["b_forest","c_quarry"]:
  check(main.world.request(dest),"fixture reaches " + dest)
  for i in 400:
   main._process(0.25);await process_frame
   if main.world.region==dest and main.world.phase=="stopped":break
 var gate=main.mine_arrival_gate
 gate._process(0.0)
 check(gate.enter_mine(true),"normal arrival entry opens existing outpost field")
 await process_frame
 field=gate.field
 field.set_process(false)
 var panel=field.get_node_or_null("CRescuePanel")
 var toggle=field.get_node_or_null("RescueToggle")
 check(panel!=null and toggle!=null,"ordinary field exposes manual rescue panel and toggle")
 if panel==null or toggle==null:finish();return
 var s=field.session
 s.outpost_cleared=true
 for enemy in s.outpost_enemies.values():enemy.dead=true;enemy.hp=0.0;enemy.engager=""
 for actor in s.actors.values():actor.state="idle";actor.path=[];actor.combat_target="";actor.x=150.0;actor.y=535.0
 s.actors["worker:0"].x=1030.0;s.actors["worker:0"].y=235.0
 s._begin_outpost_down("worker:0",s.actors["worker:0"])
 check(not panel.visible,"rescue details are opt-in")
 await click(toggle)
 check(panel.visible and not paused,"opening rescue details does not auto-pause")
 select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 var stale_start:=pressed_callback(panel.assign_button)
 var untouched:Dictionary=s.to_dict()
 select_id(panel.carrier_option,"worker:1");stale_start.call()
 check(s.to_dict()==untouched,"changing selected carrier invalidates the earlier binding")
 select_id(panel.carrier_option,"worker:2")
 stale_start=pressed_callback(panel.assign_button)
 print("ASSIGN_RECT ", panel.assign_button.get_global_rect(), " panel ",panel.get_global_rect())
 await click(panel.assign_button)
 check(s.rescue_ledger.case_for("worker:0").phase=="assigned","viewport pointer command assigns selected target and carrier")
 var after:Dictionary=s.to_dict()
 stale_start.call()
 check(s.to_dict()==after,"double or queued old assignment cannot reset route/deadline")
 check("接近" in panel.status_label.text and "完了" not in panel.status_label.text,"assignment status is approach, not completed rescue")
 for i in 300:
  field.life_clock.tick(0.05)
  if s.rescue_ledger.case_for("worker:0").phase=="carried":break
 panel.refresh_status()
 check("保持" in panel.status_label.text,"exact pickup is shown as holding")
 var old_return:=pressed_callback(panel.return_button)
 await click(panel.refresh_button)
 after=s.to_dict();old_return.call()
 check(s.to_dict()==after,"refresh invalidates queued prior return callback")
 await click(panel.return_button)
 check(s.actors["worker:2"].state=="rescue_return","viewport pointer starts physical entrance transport")
 field.life_clock.tick(0.25);panel.refresh_status()
 var point:=Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)
 await click(panel.cancel_button)
 check(s.rescue_ledger.case_for("worker:0").phase=="waiting" and Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)==point,"pointer interruption drops at current transport position")
 select_id(panel.carrier_option,"worker:2")
 var old_assign:=pressed_callback(panel.assign_button)
 await click(panel.close_button)
 after=s.to_dict();old_assign.call()
 check(not panel.visible and s.to_dict()==after,"close invalidates queued actor command")
 await click(toggle)
 select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 old_assign=pressed_callback(panel.assign_button)
 paused=true;old_assign.call();paused=false
 check(s.to_dict()==after,"explicit pause rejects mutating rescue callback")
 main.save_ui.open();old_assign.call();main.save_ui.close();paused=false
 check(s.to_dict()==after,"save modal rejects mutating rescue callback")
 panel.refresh_status()
 # Same strings do not identify an object/runtime generation.
 old_assign=pressed_callback(panel.assign_button)
 var original_session=field.session
 var clone=Session.new();clone.session_id=s.session_id;clone.actors=s.actors.duplicate(true)
 field.session=clone
 old_assign.call()
 check(s.to_dict()==after and clone.rescue_ledger.to_dict().cases.is_empty(),"same session string with a replacement object rejects old callback")
 field.session=original_session
 var original_clock=field.life_clock
 field.life_clock=FieldSurvivalClock.new()
 old_assign.call()
 check(s.to_dict()==after,"replacement clock rejects old callback")
 field.life_clock=original_clock
 var token:Variant=main.get_meta(FieldSurvivalClock.TOKEN_META)
 main.set_meta(FieldSurvivalClock.TOKEN_META,"recreated-runtime")
 old_assign.call()
 check(s.to_dict()==after,"invalid actual clock runtime token rejects old callback")
 main.set_meta(FieldSurvivalClock.TOKEN_META,token)
 var paid:Dictionary=main.get_meta(FieldSurvivalClock.LEDGER_META).duplicate(true)
 var newer:Dictionary=paid.duplicate(true);newer[s.session_id]=s.life_clock_paid+1.0
 main.set_meta(FieldSurvivalClock.LEDGER_META,newer);old_assign.call()
 check(s.to_dict()==after,"newer clock payment invalidates old view with the same session string")
 main.set_meta(FieldSurvivalClock.LEDGER_META,paid)
 field.hide();old_assign.call();field.show()
 check(s.to_dict()==after,"hidden adapter cannot accept a queued command")
 main.set_meta("c_rescue_current_adapter",-1)
 old_assign.call()
 check(s.to_dict()==after,"noncurrent adapter rejects old callback even when session/clock match")
 main.set_meta("c_rescue_current_adapter",field.get_instance_id())
 panel.rebuild()
 select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 old_assign=pressed_callback(panel.assign_button)
 var actor=s.actors["worker:2"]
 s.actors.erase("worker:2");old_assign.call()
 check(s.rescue_ledger.case_for("worker:0").phase=="waiting","missing live carrier rejects cached selected identity")
 s.actors["worker:2"]=actor
 panel.rebuild();select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 s.mine_path_engineering=true
 var old_position:=Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)
 s.actors["worker:0"].x=613.0;s.actors["worker:0"].y=271.0
 after=s.to_dict();panel.refresh_status();pressed_callback(panel.assign_button).call()
 check(s.to_dict()==after and ("直線" in panel.status_label.text or "記録" in panel.status_label.text),"ordinary mine_path explains unreachable geometry and never takes a straight shortcut")
 s.actors["worker:0"].x=old_position.x;s.actors["worker:0"].y=old_position.y
 s.mine_path_engineering=false
 panel.refresh_status()
 check(panel.get_global_rect().end.x<=507 and panel.get_global_rect().end.y<=486,"rescue panel stays outside existing controls and viewport bounds")
 check(field.canyon_hub.activity_label_for({"state":"rescue_move"})=="救助へ接近" and field.canyon_hub.activity_label_for({"state":"rescue_return"})=="救助搬送" and field.canyon_hub.activity_label_for({"state":"rescue_treatment"})=="治療待ち","rescue activity labels do not misreport generic waiting")
 s.actors["worker:2"].hp=30.0
 panel.rebuild();select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 panel.assign_button.pressed.emit()
 await process_frame;await process_frame
 check("担ぎ手" in panel.status_label.text and s.rescue_ledger.case_for("worker:0").phase=="waiting","rejected carrier reason survives ordinary status refresh")
 s.actors["worker:2"].hp=100.0
 panel.rebuild();select_id(panel.target_option,"worker:0");select_id(panel.carrier_option,"worker:2")
 await click(panel.assign_button)
 for i in 500:
  if s.rescue_ledger.case_for("worker:0").phase=="carried":break
  field.life_clock.tick(0.05)
 panel.refresh_status();await click(panel.return_button)
 s.request_recall()
 for i in 1500:
  if s.phase=="ready_to_exit":break
  field.life_clock.tick(0.05)
 panel.refresh_status()
 check(s.phase=="ready_to_exit" and "帰還確定後に治療" in panel.status_label.text,"ready-to-exit view retains delivered treatment status")
 check(panel.assign_button.disabled and panel.return_button.disabled and panel.cancel_button.disabled,"ready treatment view offers no new rescue mutation")
 old_assign=pressed_callback(panel.assign_button)
 after=s.to_dict();old_assign.call()
 check(s.to_dict()==after,"ready-to-exit callback cannot start work")
 check(gate.fail_field_to_menu("rescue UI lifecycle fixture"),"existing failure handoff remains available")
 after=s.to_dict();old_assign.call()
 check(s.to_dict()==after and main.save_ui.is_open(),"failed/removed field callback cannot mutate old session or close recovery menu")
 finish()
func finish() -> void:
 paused=false
 if main!=null and is_instance_valid(main):main.free()
 print("C RESCUE UI assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
