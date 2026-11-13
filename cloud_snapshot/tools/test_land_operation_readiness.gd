extends SceneTree
## Explicitly seeded real Main/WorldTrip/UI fixtures, not natural travel or OS input.
## Removing any common readiness gate or stale-callback binding must fail here.
var main
var failures := 0
var assertions := 0
var field_sentinel: Node
const WOOD := GameData.Item.WOOD
const STONE := GameData.Item.STONE
const ACTIONS := ["build","clear_shortcut","grade_ab","remove","deposit","withdraw"]
const BLOCKS := ["inactive","profile","departing","travel","arriving","turning","ended","quarry","field","hostile","expedition","loose","outside","away","climb","cargo","bonus","resource","prey","enemy"]

func _init() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
 assertions+=1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures+=1
func _fresh(action := "build",site := "b_forest") -> void:
 paused=false
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",261110)
 root.add_child(main)
 await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 main.director.enabled=false
 main.world.region=site
 main.world.phase="stopped"
 main.storage.inventory.counts={WOOD:20,STONE:20}
 main.transfer_queue.clear()
 for w in main.workers:
  w.stop_work()
  for job in GameData.job_list(): w.priorities[job]=0
 if action in ["remove","deposit","withdraw"]:
  main.world.region_state.lots[site]=WorldTrip.REGION_A_BUILD[site].lot
 if action=="withdraw": main.world.site_stores[site]={WOOD:3}
func _release() -> void:
 paused=false
 if is_instance_valid(field_sentinel):
  main.mine_arrival_gate.field=null
  field_sentinel.free()
  field_sentinel=null
 main.queue_free()
 await process_frame
func _snapshot() -> Dictionary:
 return {"inventory":main.storage.inventory.counts.duplicate(true),"land":main.world.region_state.duplicate(true),"sites":main.world.site_stores.duplicate(true),"resources":main.world.locations.duplicate(true)}
func _act(action: String) -> bool:
 match action:
  "build": return main.world.build_current_site()
  "clear_shortcut": return main.world.clear_shortcut()
  "grade_ab": return main.world.grade_ab()
  "remove": return main.world.remove_current_site()
  "deposit": return main.world.deposit_to_site(WOOD,1)==1
  "withdraw": return main.world.withdraw_from_site(WOOD,1)==1
 return false
func _block(condition: String) -> void:
 var w=main.workers[0]
 match condition:
  "inactive": main.world.active=false
  "profile": main.world.map_profile=WorldMapDB.DESERT
  "departing","travel","arriving","turning": main.world.phase=condition
  "ended": main.game_over=true
  "quarry": main.quarry.state="parked"
  "field":
   field_sentinel=Node.new()
   main.mine_arrival_gate.field=field_sentinel
  "hostile":
   var enemy:=Enemy.new()
   enemy.setup_kind(main,"sand_stalker")
   main.enemies_root.add_child(enemy)
  "expedition": main.expedition.state="running"
  "loose": main.quarry.loose={WOOD:1}
  "outside": w.floor_i=0
  "away": w.away=true
  "climb": w._climb_dest=Vector2(100,100)
  "cargo": w.carrying=WOOD
  "bonus": w.carry_bonus={WOOD:1}
  "resource": w.ai.res=main.resources_root.get_child(0)
  "prey": w.ai.prey=main.creatures_root.get_child(0)
  "enemy":
   var target:=Enemy.new()
   target.setup_kind(main,"sand_stalker")
   target.ecological=true # Not hostile(); test the reservation gate itself.
   main.enemies_root.add_child(target)
   w.ai.enemy=target
func _button(prefix: String) -> Button:
 for node in main.map_ui._land_box.get_children():
  if node is Button and node.text.begins_with(prefix): return node
 return null
func _labels() -> String:
 var value:=""
 for node in main.map_ui._land_box.get_children():
  if node is Label:value+=node.text+"\n"
 return value
func _show_plan(action: String) -> Button:
 main.map_ui._land_action=action
 main.map_ui._refresh_land()
 return _button("この計画を実行")
func _run() -> void:
 if OS.get_environment("FLUID_TEST_HOME")=="":
  push_error("Isolated FLUID_TEST_HOME required");quit(2);return
 SaveGame.disabled=true
 for action in ACTIONS:
  for condition in BLOCKS:
   await _fresh(action)
   _block(condition)
   var before:=_snapshot()
   var signals:={"n":0}
   var observe:=func():signals.n+=1
   main.storage.inventory.changed.connect(observe)
   _check(not _act(action),action+" rejects "+condition)
   _check(_snapshot()==before and signals.n==0,action+"/"+condition+" leaves all ledgers and notifications unchanged")
   main.storage.inventory.changed.disconnect(observe)
   if action not in ["deposit","withdraw"] and condition!="profile":
    var preview:Dictionary=main.world.land_preview(action)
    _check(not bool(preview.get("available",false)) and not str(preview.get("reason","")).is_empty(),action+"/"+condition+" preview has unavailable reason")
   await _release()
  await _fresh(action)
  paused=true
  _check(_act(action),action+" remains usable during explicit map pause at safe stop")
  await _release()
  await _fresh(action)
  main.operations.set_stance("recall")
  main.workers[0].ai.return_request=true
  _check(_act(action),action+" permits returned crew with recall/return order still set")
  await _release()
 # Real control signals must recheck state changed since rendering.
 for action in ACTIONS:
  await _fresh(action)
  var button:Button
  if action in ["deposit","withdraw"]:
   main.map_ui._refresh_land()
   button=_button(main.map_ui._item_name(WOOD)+("を1預ける" if action=="deposit" else "を1引出す"))
  else: button=_show_plan(action)
  _check(button!=null and not button.disabled,action+" safe button enabled")
  main.expedition.state="running"
  var before:=_snapshot()
  if button!=null:button.emit_signal("pressed")
  _check(_snapshot()==before,action+" stale button rejects new expedition")
  _check(_labels().contains("遠征隊の帰還待ち"),action+" UI shows actual blocked reason")
  await _release()
 # B and D support the same actions; old B controls cannot silently act on D.
 for action in ["build","clear_shortcut","remove","deposit","withdraw"]:
  await _fresh(action)
  if action in ["remove","deposit","withdraw"]:
   main.world.region_state.lots.d_yard="freight"
  if action=="withdraw":main.world.site_stores.d_yard={WOOD:2}
  var button:Button
  if action in ["deposit","withdraw"]:
   main.map_ui._refresh_land()
   button=_button(main.map_ui._item_name(WOOD)+("を1預ける" if action=="deposit" else "を1引出す"))
  else:button=_show_plan(action)
  main.world.region="d_yard"
  var before:=_snapshot()
  if button!=null:button.emit_signal("pressed")
  _check(_snapshot()==before,action+" B control cannot target D")
  _check(main.map_ui._land_action=="",action+" stale site plan cleared")
  await _release()
 # Retained callbacks are not authorized by later render/open/plan actions.
 for event in ["refresh","cancel","close","other_plan"]:
  await _fresh()
  main.map_ui.open()
  var button:=_show_plan("build")
  match event:
   "refresh":main.map_ui._refresh_land()
   "cancel":_button("計画を取消").emit_signal("pressed")
   "close":main.map_ui.close()
   "other_plan":_show_plan("grade_ab")
  var before:=_snapshot()
  button.emit_signal("pressed")
  _check(_snapshot()==before,"old confirmation cannot act after "+event)
  if event=="close":
   _check(not paused and main.map_ui._land_action=="","close restores prior pause and discards uncommitted plan")
   main.map_ui.open()
   _check(_snapshot()==before and main.map_ui._land_action=="","reopening does not restore or execute closed plan")
  await _release()
 SaveGame.disabled=false
 print("LAND OPERATION READINESS assertions=",assertions," failures=",failures)
 quit(1 if failures else 0)
