extends SceneTree
var main
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
 assertions+=1;print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures+=1
func label_text(node: Node) -> String:
 var text:String = node.text if node is Label else ""
 for child in node.get_children():text+="\n"+label_text(child)
 return text
func settle(gate) -> void:
 await process_frame;await process_frame;gate._process(0.0);await process_frame
func layout(gate,waiting: bool) -> void:
 var rect:Rect2=gate._panel.get_global_rect()
 check(rect.position.x>=0 and rect.end.x<=1280 and rect.end.y<=720,"entry panel stays in viewport")
 var controls:Array[Control]=[]
 for child in gate._panel.get_child(0).get_children():
  if child is Control and child.visible: controls.append(child)
 for i in controls.size()-1:
  check(not controls[i].get_global_rect().intersects(controls[i+1].get_global_rect()),"visible explanation and controls do not overlap")
 if waiting:
  check(gate._notice.get_global_rect().position.y>=rect.end.y and gate._notice.get_global_rect().end.y<=720,"entry notice stays below panel inside viewport")
func run() -> void:
 if OS.get_environment("FLUID_TEST_HOME").is_empty():quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true;main.set_meta("diagnostic_seed",104729)
 root.add_child(main);await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED;main.director.enabled=false
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list():w.priorities[job]=0
 for destination in ["b_forest","c_quarry"]:
  check(main.world.request(destination),"normal request "+destination)
  for i in 400:
   main._process(0.25);await process_frame
   if main.world.region==destination and main.world.phase=="stopped":break
 var gate=main.mine_arrival_gate;await settle(gate)
 var guidance:Label=gate._panel.find_child("RescueGuidance",true,false)
 check(guidance!=null and guidance.is_visible_in_tree(),"common rescue guidance is visible at choice")
 check(guidance!=null and guidance.mouse_filter!=Control.MOUSE_FILTER_IGNORE and "期限切れ後" in guidance.tooltip_text and "自力回復" in guidance.tooltip_text,"expiry qualification permits normal hover tooltip")
 var text:=label_text(gate._panel)
 check(not "救助は未対応" in text,"entry no longer denies implemented manual rescue")
 check("手動" in text and "入口へ搬送" in text and "残り時間" in text,"entry explains manual timed transport")
 check("経路・装備" in text and "未救助者" in text and "帰還確定" in text,"entry retains reachability and return restrictions")
 check("前哨地" in gate._outpost_warning.text and "敵3体" in gate._outpost_warning.text,"enemy count clearly belongs to optional outpost")
 layout(gate,false)
 main.workers[0].carrying=GameData.Item.WOOD
 check(not gate.enter_mine(false) and gate.visible_state()=="entry_wait","normal cargo readiness starts genuine pending entry")
 await settle(gate)
 check(not gate._outpost_warning.visible,"normal pending entry hides optional enemy warning")
 check(guidance!=null and guidance.is_visible_in_tree() and "手動" in guidance.text,"normal pending entry retains rescue guidance")
 layout(gate,true)
 gate.cancel_pending_entry();await settle(gate)
 check(gate._outpost_warning.visible and not gate._enter_button.disabled and not gate._outpost_button.disabled,"cancel restores optional choice and both buttons")
 check(not gate.enter_mine(true) and gate.visible_state()=="entry_wait","outpost readiness starts genuine pending entry")
 await settle(gate)
 check(gate._outpost_warning.visible,"outpost pending entry retains its enemy warning")
 check(guidance!=null and guidance.is_visible_in_tree(),"outpost pending entry retains visible common rescue guidance")
 layout(gate,true)
 gate.cancel_pending_entry();main.workers[0].carrying=-1
 check(gate.enter_mine(false) and gate.field!=null and gate.field.session.mine_path_engineering,"normal entry remains functional after mode switch cancellation")
 main.queue_free();await process_frame;await process_frame
 print("C RESCUE ENTRY GUIDANCE assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
