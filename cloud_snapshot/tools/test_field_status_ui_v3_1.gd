extends SceneTree
var fails:=0
func _init():call_deferred("run")
func check(ok:bool,msg:String):
 print("ok " if ok else "FAIL ",msg)
 if not ok:fails+=1
func click(button):
 var point:Vector2=button.get_global_rect().get_center()
 var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
 await process_frame
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
  root.push_input(event,true);await process_frame
func pointer_edge(button, down:bool):
 var point:Vector2=button.get_global_rect().get_center()
 var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
 var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
 root.push_input(event,true);await process_frame
func settle(field):
 for i in 1200:
  field._process(0.2)
  if field.session.phase=="ready_to_exit":break
 check(field.session.phase=="ready_to_exit","optional fixture gathers actual actors before final approval")
func optional_return_contract(g):
 var gate=g.mine_arrival_gate
 gate._dismissed_here=false;gate._process(0.0)
 check(gate.enter_mine(true),"API fixture enters optional outpost, not a native-entry claim")
 await process_frame
 var f=gate.field
 f.set_process(false) # Explicit fixture clock; keep real button input enabled.
 var session=f.session
 var panel=f.get_node("FieldVehicleStatus")
 var button=panel.get_node("Contents/Actions/Return")
 f._update_controls();await process_frame
 check(button.text=="帰還準備" and not button.disabled,"optional local HUD offers recall only")
 # Hold a recall gesture while another existing action completes recall.
 await pointer_edge(button,true)
 session.request_recall();settle(f)
 await pointer_edge(button,false)
 check(gate.field==f and not session.committed,"recall press cannot become final approval on release")
 f._update_controls();await process_frame
 check(button.text=="帰還→横視点" and not button.disabled,"ready optional HUD visibly offers final return")
 for window_size in [Vector2i(1280,720),Vector2i(1440,900)]:
  root.size=window_size
  for frame in 3:await process_frame
  check(Rect2(Vector2.ZERO,Vector2(window_size)).encloses(panel.get_global_rect()),"ready HUD fits "+str(window_size))
  check(not panel.get_global_rect().intersects(f.controls_panel.get_global_rect()),"ready HUD does not overlap legacy controls")
 root.size=Vector2i(1280,720);await process_frame
 var stock:Dictionary=g.storage.inventory.counts.duplicate(true)
 for i in 3:f._process(0.2)
 check(gate.field==f and not session.committed and g.storage.inventory.counts==stock,"ready waits for explicit input without automatic commit")
 # Stale displayed controls still cannot act behind the save menu.
 g.save_ui.open();button.button_down.emit();button.pressed.emit()
 check(gate.field==f and not session.committed and paused,"menu blocks retained ready HUD callback")
 g.save_ui.close()
 await click(panel.get_node("Contents/Actions/Pause"))
 check(paused,"optional ready HUD can own pause")
 var repeat_probe={"attempted":false,"exits":0,"unchanged":false}
 f.exit_to_horizontal.connect(func(_result):
  repeat_probe.exits+=1
  if repeat_probe.exits==1:
   var first_stock:Dictionary=g.storage.inventory.counts.duplicate(true)
   repeat_probe.attempted=true
   button.pressed.emit() # Synchronous: adapter is queued, not yet freed.
   repeat_probe.unchanged=g.storage.inventory.counts==first_stock
 )
 await click(button)
 check(gate.field==null and session.committed and not paused,"HUD pointer commits return and releases only owned pause")
 check(repeat_probe.attempted,"duplicate final dispatch is actually attempted before object deletion")
 check(repeat_probe.exits==1 and repeat_probe.unchanged,"repeat final signal creates no duplicate cargo or exit")
 if gate.field!=null:gate.field._commit_and_exit()
 await process_frame
 gate._dismissed_here=false;gate._process(0.0)
 check(gate.enter_mine(true),"reenter optional HUD guard fixture")
 await process_frame
 f=gate.field;session=f.session;button=f.get_node("FieldVehicleStatus/Contents/Actions/Return")
 f.set_process(false)
 for mode in ["hidden","discarding","menu"]:
  if mode=="hidden":f.hide()
  elif mode=="discarding":f._discarding_for_load=true
  else:g.save_ui.open()
  button.button_down.emit();button.pressed.emit()
  check(session.phase=="local" and not session.committed,"stale local HUD blocked: "+mode)
  if mode=="hidden":f.show()
  elif mode=="discarding":f._discarding_for_load=false
  else:g.save_ui.close()
 # Existing actors actually move before recall; no injected combat result.
 for i in 10:f._process(0.2)
 f._update_controls();await click(button)
 check(session.phase in ["recall","ready_to_exit"] and not session.committed,"HUD recall does not finalize return")
 if session.phase=="recall":
  check(button.disabled and button.text=="帰還準備中","recall HUD says waiting and cannot be confirmed")
 settle(f);f._update_controls();await process_frame
 # Held final intent becomes stale if the adapter's clock is replaced.
 button.button_down.emit()
 var old_clock=f.life_clock
 f.life_clock=preload("res://bridge/field_survival_clock.gd").new();f.life_clock.setup(g,session)
 button.pressed.emit()
 check(not session.committed and gate.field==f,"ready intent cannot outlive its clock identity")
 f.life_clock=old_clock
 # The established commit gate, not a ready label, checks down ownership.
 session.actors["worker:2"].down=true
 stock=g.storage.inventory.counts.duplicate(true)
 var outposts:Dictionary=g.world.outpost_states.duplicate(true)
 await click(button);f._update_controls()
 check(not session.committed and gate.field==f and g.storage.inventory.counts==stock and g.world.outpost_states==outposts,"HUD cannot bypass unresolved down actor")
 check(not f._return_failure.is_empty() and f._return_failure in f.notice_label.text,"rejected HUD return retains actual refusal reason")
 session.actors["worker:2"].down=false
 # Foreign pause is not owned by this adapter; keyboard commit must retain it.
 paused=true;button.grab_focus()
 for down in [true,false]:
  var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=down;root.push_input(key,true);await process_frame
 check(session.committed and gate.field==null and paused,"Space final return preserves foreign pause")
 paused=false
 if gate.field!=null:gate.field._commit_and_exit()
 await process_frame
func check_crew_health(field, panel):
 # This is a bounded UI fixture, not a natural down/rescue playthrough.
 var health=panel.get_node_or_null("Contents/CrewHealth")
 check(health!=null and health.is_visible_in_tree(),"field shows crew health before a rescue target exists")
 if health==null:return
 var actors:Dictionary=field.session.actors.duplicate(true)
 var phase:String=field.session.phase
 for id in field.session.actors:
  field.session.actors[id].hp=100.0
  field.session.actors[id].down=false
 field._update_controls()
 for actor in field.session.actors.values():
  check(str(actor.name) in health.text,"health identifies each present companion")
 check("100.0" in health.text and "戦闘不能" not in health.text,"healthy display reads current field HP")
 # UI-only injury fixture. Safe mining actors now correctly reject combat hits.
 field.session.actors["worker:2"].hp=98.5
 field._update_controls()
 check("98.5" in health.text and "負傷" in health.text and "帰還準備" in health.text,"ordinary injury is visible and points to recall rather than rescue")
 check("手動救助" not in health.text,"ordinary injury does not imply incapacitation")
 field.session.phase="recall";field._update_controls()
 check("帰還を待機" in health.text,"injured recall says to wait for actual return")
 field.session.phase="ready_to_exit";field._update_controls()
 check("帰還→横視点" in health.text,"ready injured crew points to actual commit button")
 field.session.phase="local"
 field.session.actors["worker:2"].hp=0.0
 field.session.actors["worker:2"].down=true
 var before:String=var_to_str(field.session.actors)
 field._update_controls()
 check("0.0" in health.text and "戦闘不能" in health.text and "手動救助" in health.text and "残秒" in health.text,"down fixture points to existing detailed rescue state and time")
 check(var_to_str(field.session.actors)==before,"health refresh never changes HP or actor ownership")
 field.session.phase=phase
 for id in actors:field.session.actors[id]=actors[id]
 field._update_controls()
func run():
 for event in EventDB.EVENTS.values():
  for stance in event.get("stances",[]):
   check("傷み" not in EventDB.stance_summary(stance),"stance summary hides disabled passive wear")
   var note:String=str(stance.get("note",""))
   check("傷む" not in note and "傷み" not in note and "走行装置を使う" not in note,"stance note matches non-damaging weather/travel")
 SaveGame.disabled=true
 var g=load("res://scenes/main.tscn").instantiate()
 g.first_region_a_pilot=true;root.add_child(g);await process_frame
 g.process_mode=Node.PROCESS_MODE_DISABLED;g.director.enabled=false
 # Standalone runs must not borrow an earlier suite case's manual save.
 if OS.get_environment("FLUID_TEST_HOME")=="":g.free();quit(2);return
 g.save_ui.path="user://field-status-ui-own-seed.json"
 SaveGame.disabled=false
 check(SaveGame.write(g,g.save_ui.path,true),"write this fixture's own valid pre-entry save")
 SaveGame.disabled=true
 for w in g.workers:
  w.stop_work()
  for j in GameData.job_list():w.priorities[j]=0
 for dest in ["b_forest","c_quarry"]:
  g.world.request(dest)
  for i in 1200:
   g._process(0.2)
   if g.world.phase=="stopped" and g.world.region==dest:break
 var gate=g.mine_arrival_gate
 gate._process(0.0)
 check(gate.enter_mine(),"fixture enters safe C")
 await process_frame
 var f=gate.field
 var panel=f.get_node_or_null("FieldVehicleStatus")
 check(panel!=null,"vehicle survival panel exists")
 if panel==null:g.free();quit(1);return
 f._update_controls();await process_frame
 var label=panel.get_node("Contents/Status")
 check("車体" in label.text and "走行" in label.text and "燃料" in label.text,"actual three resources visible")
 check("要修理" not in label.text,"healthy has no repair warning")
 check_crew_health(f,panel)
 f.session.request_recall()
 for i in 1200:
  f._process(0.2)
  if f.session.phase=="ready_to_exit":break
 check(f.session.phase=="ready_to_exit","ready fixture gathers crew")
 await click(panel.get_node("Contents/Actions/Pause"))
 check(paused,"ready field can pause")
 f._commit_and_exit()
 check(not paused and gate.field==null,"normal commit releases own pause")
 paused=false
 await optional_return_contract(g)
 gate._dismissed_here=false;gate._process(0.0);check(gate.enter_mine(),"reenter for status fixture")
 await process_frame
 f=gate.field;panel=f.get_node("FieldVehicleStatus");label=panel.get_node("Contents/Status")
 g.base.parts[GameData.Part.HULL]=0.4;f._update_controls();check("0.4" in label.text,"positive low hull not rounded to zero")
 g.base.parts[GameData.Part.HULL]=12.0;g.base.parts[GameData.Part.DRIVE]=9.0;g.base.fuel=3.0
 g.director.active=[{"id":"sandstorm","left":30.0,"total":40.0,"stance":"push"}]
 g.director._log("検証：車体に被害 -7")
 f._update_controls();await process_frame
 check("12" in label.text and "9" in label.text and "3" in label.text,"low values are actual")
 check("消耗増" not in label.text and "疲労×1.35" in label.text,"weather shows actual fatigue modifier, not passive hull wear")
 check("要修理" in label.text and "補給" in label.text and "砂嵐" in label.text,"text warns beyond color")
 g.director.active=[{"id":"coldsnap","left":30.0,"total":40.0,"stance":"run"}]
 f._update_controls();await process_frame
 check("移動時：燃料×1.05" in label.text and "空腹進行×1.50" in label.text,"travel-only fuel and real hunger modifiers labelled")
 g.director.active=[{"id":"sandstorm","left":30.0,"total":40.0,"stance":"slow"}]
 f._update_controls();await process_frame
 check("移動時：速度×0.50" in label.text and "消耗増" not in label.text,"slow weather remains speed debuff without hull claim")
 check(not panel.get_global_rect().intersects(f.controls_panel.get_global_rect()),"panel does not cover lower controls")
 print("STATUS_RECT ",panel.get_global_rect())
 check(panel.get_global_rect().end.x<=1280 and panel.get_global_rect().end.y<=300,"compact panel fits viewport")
 var pause_button=panel.get_node("Contents/Actions/Pause")
 paused=true;pause_button.pressed.emit();check(paused,"foreign pause is not released");paused=false
 await click(pause_button);check(paused,"pointer pause control pauses")
 g.save_ui.open();pause_button.pressed.emit();check(paused,"save modal pause not released");g.save_ui.close()
 var before:float=f.session.elapsed;f._process(1.0);check(f.session.elapsed==before,"pause stops field clock")
 await click(pause_button);check(not paused,"pointer same button resumes")
 await click(panel.get_node("Contents/Actions/Return"))
 check(f.session.phase in ["recall","ready_to_exit"],"return uses existing recall")
 check(gate.fail_field_to_menu("試験停止"),"failure opens menu")
 check("車体" in g.save_ui._failure_reason and "検証：車体に被害 -7" in g.save_ui._failure_reason,"failure retains actual snapshot and existing log")
 await process_frame
 print("FAIL_MENU_RECT ",g.save_ui._overlay.get_child(0).get_global_rect())
 check(g.save_ui._overlay.get_child(0).get_global_rect().end.y<=720,"failure menu remains on screen")
 var load_button:Button
 for button in g.save_ui._action_buttons:
  if button.get_meta("save_action")=="load":load_button=button
 await click(load_button);check(g.save_ui._action=="load","failure menu load pointer remains usable")
 print("FIELD_STATUS_UI_V3_1 failures=",fails)
 paused=false;g.free();quit(1 if fails else 0)
