extends SceneTree
## v3 read-only investigation. Viewport-injected pointer events, not OS/Windows input.
## Natural route uses normal priorities/director; controlled case disables job
## priorities only to separate readiness gating from click delivery.
var main
var failures := 0
var pressed_count := 0
var gui_count := 0
var observations: Array = []
func _init() -> void: call_deferred("_run")
func check(ok:bool,message:String) -> void:
 print("%s %s" % ["ok" if ok else "FAIL",message])
 if not ok: failures+=1
func fresh(controlled:bool) -> void:
 if is_instance_valid(main):
  main.queue_free(); await process_frame
 paused=false;SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729)
 root.add_child(main);await process_frame
 if controlled:
  for worker in main.workers:
   worker.stop_work()
   for job in GameData.job_list():worker.priorities[job]=0
 main.map_ui.open();main.map_ui.select_region("c_quarry");main.map_ui._go()
func arrival() -> bool:
 for unused in range(3600):
  await process_frame
  if main.world.region=="c_quarry" and main.world.phase=="stopped" and main.mine_arrival_gate.visible_state()=="arrival_choice":return true
 return false
func entry_button() -> Button:
 for node in main.mine_arrival_gate._panel.find_children("*","Button",true,false):
  if node.text=="採掘地に入る":return node
 return null
func click(button:Button) -> void:
 var point:Vector2=button.get_global_rect().get_center()
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
 root.push_input(motion,true)
 await process_frame
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
  event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
  root.push_input(event,true)
  await process_frame
func probe(label:String) -> void:
 var gate=main.mine_arrival_gate
 var button=entry_button()
 check(button!=null,label+" entry Button exists")
 if button==null:return
 await process_frame
 pressed_count=0;gui_count=0
 var press_snapshot := {}
 button.pressed.connect(func():
  pressed_count+=1
  press_snapshot.merge({"state":gate.visible_state(),"notice_visible":gate._notice.visible,"stance":str(main.operations.stance)},true)
 )
 button.gui_input.connect(func(_event):gui_count+=1)
 var prior_stance:=str(main.operations.stance)
 var before:=str(main.world.ready_reason())
 var started:float=main.director.elapsed
 var rect:Rect2=button.get_global_rect()
 await click(button)
 var obs={"case":label,"at_pressed":press_snapshot.duplicate(),"ready_reason_before":before,"pressed":pressed_count,"gui_events":gui_count,"state":gate.visible_state(),"notice":gate._notice.text,"notice_visible":gate._notice.visible,"rect":str(rect),"tree_paused":paused}
 observations.append(obs);print("OBS ",JSON.stringify(obs))
 check(pressed_count==1,label+" pointer reaches button exactly once")
 check(rect.position.x>=0 and rect.end.x<=1280 and rect.end.y<=720,label+" button lies in viewport")
 # Readiness is live between mouse motion, press and release. A completed
 # entry is valid even if it finishes before the click helper returns.
 check(str(press_snapshot.get("state","")) in ["entry_wait","field"],label+" pressed handler accepts pending or completed entry")
 check(gate.visible_state() in ["entry_wait","field"],label+" click starts pending or enters field")
 if str(press_snapshot.get("state",""))=="entry_wait":
  check(bool(press_snapshot.notice_visible),label+" blocked press exposes pending notice")
  check(str(press_snapshot.stance)=="recall",label+" pending press recalls instead of restarting outside work")
 if gate.visible_state() in ["entry_wait","field"]:
  var serial:int=gate._session_serial
  check(not gate.enter_mine() and gate._session_serial==serial,label+" repeated pending entry does not duplicate session")
  for unused in range(2400):
   await process_frame
   if gate.visible_state()=="field":break
  check(gate.visible_state()=="field",label+" one click eventually enters after natural recall")
  check(main.director.elapsed>started,label+" pending entry keeps ordinary clock advancing")
  if gate.field!=null:
   gate.field.session.request_recall()
   for unused in range(1200):
    await process_frame
    if gate.field.session.phase=="ready_to_exit":break
   gate.field._commit_and_exit()
   await process_frame
   check(gate.field==null and main.operations.stance==prior_stance,label+" committed field exit restores original stance")
func pending_cleanup() -> void:
 var gate=main.mine_arrival_gate
 if not gate.has_method("cancel_pending_entry"):
  check(false,"pending cancellation API exists");return
 var worker=main.workers[0]
 main.operations.set_stance("alert")
 var snapshot:Dictionary=SaveGame.capture(main)
 var floor_before:int=worker.floor_i
 worker.floor_i=0 # Explicit cleanup fixture, not the natural route witness.
 check(not gate.enter_mine() and gate.visible_state()=="entry_wait","blocked entry queues pending without reporting actual entry")
 check(gate._cancel_button.visible and gate._notice.visible,"deterministic waiting exposes cancellation and reason")
 gate._cancel_button.pressed.emit()
 check(gate.visible_state()=="arrival_choice" and main.operations.stance=="alert","cancel signal restores previous stance")
 gate.enter_mine()
 main.game_over=true;gate._process(0.1)
 check(gate.visible_state()=="idle" and main.operations.stance=="alert","game over clears pending and restores stance")
 main.game_over=false;gate._process(0.1)
 gate.enter_mine()
 main.world.region="b_forest";gate._process(0.1)
 check(gate.visible_state()=="idle" and main.operations.stance=="alert","leaving C clears pending")
 main.world.region="c_quarry";gate._process(0.1)
 gate.enter_mine()
 var source:Dictionary=main.world.locations["region:c_quarry"].duplicate(true)
 main.world.locations["region:c_quarry"]={}
 worker.floor_i=floor_before
 gate._process(0.1)
 check(gate.visible_state()=="arrival_choice" and gate._notice.visible and gate._notice.text.contains("有限資源"),"non-readiness failure displays finite-resource reason")
 check(main.operations.stance=="alert","failed session creation restores prior stance")
 main.world.locations["region:c_quarry"]=source
 worker.floor_i=0
 gate.enter_mine()
 check(SaveGame.apply(main,snapshot),"real save API accepts pre-wait snapshot")
 check(gate.visible_state()!="entry_wait" and main.operations.stance=="alert","loading same C cancels pending without overwriting loaded stance")
 gate.cancel_pending_entry()
 main.workers[0].floor_i=floor_before
 main.operations.set_stance("normal")
 gate._process(0.1)

func _run() -> void:
 var previous_scale:=Engine.time_scale;Engine.time_scale=20.0
 await fresh(false)
 check(await arrival(),"natural default route reaches C choice")
 if failures==0:
  # Delay simulates reading the arrival card while workers continue naturally.
  var time:=0.0
  while time<3.0:
   await process_frame
   time+=main.get_process_delta_time()
  await probe("default delayed click")
 await fresh(true)
 check(await arrival(),"controlled route reaches C choice")
 if main.mine_arrival_gate.visible_state()=="arrival_choice":
  pending_cleanup()
  await probe("controlled ready click")
 print("C_ENTRY_OBSERVATIONS ",JSON.stringify(observations))
 if is_instance_valid(main):main.queue_free()
 await process_frame
 Engine.time_scale=previous_scale;SaveGame.disabled=false
 print("C entry interaction investigation: %s"%("passed" if failures==0 else "%d failures"%failures))
 quit(1 if failures else 0)
