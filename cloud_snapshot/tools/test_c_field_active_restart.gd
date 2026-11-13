extends SceneTree
const Owners = preload("res://bridge/c_field_snapshot_owners.gd")
const STAGES = ["waiting","assigned","released_return","hold","return","treatment","treatment_ready","return_correction"]
var main
var assertions := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
 assertions+=1
 print("  %s %s" % ["ok" if ok else "FAIL",label])
 if not ok: failures+=1
func advance(clock,predicate: Callable,seconds: float) -> bool:
 for unused in ceili(seconds/0.05):
  if predicate.call(): return true
  clock.tick(0.05)
 return predicate.call()
func run() -> void:
 var home:=OS.get_environment("FLUID_TEST_HOME").replace("\\","/").simplify_path().trim_suffix("/")
 if home.is_empty() or not OS.get_user_data_dir().replace("\\","/").simplify_path().begins_with(home+"/"): quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot=true
 main.set_meta("diagnostic_seed",104729)
 root.add_child(main)
 await process_frame
 main.process_mode=Node.PROCESS_MODE_DISABLED
 SaveGame.disabled=false
 for stage in STAGES:
  await consume(stage)
 await finish()
func consume(stage: String) -> void:
 var path="user://c-field-owner-"+stage+".json"
 var saved=SaveGame.read(path)
 check(not saved.is_empty(),stage+": read producer file")
 if saved.is_empty(): return
 var receipt=JSON.parse_string(FileAccess.get_file_as_string(path+".receipt"))
 check(receipt is Dictionary and int(receipt.pid)!=OS.get_process_id() and receipt.hash==FileAccess.get_sha256(path),stage+": separate PID and exact file hash")
 var before_failures=failures
 check(SaveGame.apply(main,saved),stage+": complete owner bundle applies")
 var gate=main.mine_arrival_gate
 check(gate.field!=null and paused,stage+": paused field installed")
 if failures>before_failures:return
 var field=gate.field
 field.process_mode=Node.PROCESS_MODE_DISABLED
 var s=field.session
 var clock=field.life_clock
 check(clock.is_current() and s.life_clock_token!=saved.field_snapshot.session.life_clock_token,stage+": fresh live clock")
 check(Owners.capture(s)==saved.field_snapshot.owners,stage+": exact private ownership restored")
 check(s.rescue_ledger.to_dict()==saved.field_snapshot.session.rescue and s.elapsed==saved.field_snapshot.session.elapsed,stage+": residual timer unchanged on load")
 for id in s.rescue_approach._owned:
  check(s.rescue_approach._mine_binding_current(s,id,s.rescue_approach._owned[id]),stage+": fresh identity binding "+id)
 for id in saved.field_snapshot.plans:
  check(s.mine_rescue_traces.plan_current(id,s.actors[id]),stage+": active plan has fresh actor identity "+id)
 for id in saved.field_snapshot.traces:
  check(s.mine_rescue_traces._rows[id].points==saved.field_snapshot.traces[id].points,stage+": current trace vertices unchanged "+id)
 if stage=="assigned":
  var bad=saved.duplicate(true)
  bad.field_snapshot.owners.owned["worker:1"]="worker:0"
  check(not SaveGame.apply(main,bad) and gate.field==field and clock.is_current(),"duplicate carrier rejected without replacing live owner")
  bad=saved.duplicate(true)
  bad.field_snapshot.session.actors["worker:0"]["expired_self_return"]=true
  check(not SaveGame.apply(main,bad) and gate.field==field,"expiry flag cannot appear without an owner")
  bad=saved.duplicate(true)
  var proof: Dictionary=bad.field_snapshot.plans["worker:2"].witness
  if proof.source_trace.get("points",[]).size()>2:
   proof.source_trace.points.remove_at(1)
   check(not SaveGame.apply(main,bad) and gate.field==field,"dropped creation-trace vertex cannot keep a stale route")
  bad=saved.duplicate(true)
  bad.field_snapshot.session.actors["worker:2"].path=[[777.0,888.0]]
  bad.field_snapshot.session.actors["worker:2"].path_index=0
  bad.field_snapshot.plans["worker:2"].path=[[777.0,888.0]]
  bad.field_snapshot.plans["worker:2"].index=0
  check(not SaveGame.apply(main,bad) and gate.field==field,"matching duplicated chord cannot replace approved route")
 if stage=="assigned":
  var malformed=saved.duplicate(true)
  malformed.field_snapshot.plans["worker:2"].witness.goal="not a point"
  reject_file(malformed,"malformed witness goal rejected cleanly",saved)
  malformed=saved.duplicate(true)
  malformed.field_snapshot.session.actors["worker:2"].path=[]
  malformed.field_snapshot.session.actors["worker:2"].path_index=0
  malformed.field_snapshot.plans.erase("worker:2")
  reject_file(malformed,"moving owner cannot lose both path and witness",saved)
  malformed=saved.duplicate(true)
  malformed.field_snapshot.schema="not a schema"
  reject_file(malformed,"malformed field schema rejected cleanly",saved)
 if stage in ["released_return","treatment","treatment_ready"]:
  var malformed=saved.duplicate(true)
  var id="worker:2" if stage=="released_return" else "worker:0"
  var rid=malformed.field_snapshot.session.resources.keys()[0]
  malformed.field_snapshot.session.resources[rid].reservation=id
  malformed.field_snapshot.session.reservations[rid]=id
  malformed.field_snapshot.session.actors[id].resource_id=rid
  reject_file(malformed,"controller cannot acquire competing resource reservation "+stage,saved)
 if stage=="hold":
  var malformed=saved.duplicate(true)
  malformed.field_snapshot.traces["worker:0"].transported_by="worker:1"
  reject_file(malformed,"carried trace metadata must name its actual carrier",saved)
  malformed=saved.duplicate(true)
  malformed.field_snapshot.traces["worker:0"].transport_gear=GameData.Item.HANDCART
  reject_file(malformed,"carried trace transport gear must match actual carrier",saved)
  malformed=saved.duplicate(true)
  malformed.field_snapshot.traces["worker:2"]=0
  reject_file(malformed,"scalar carrier trace rejected cleanly",saved)
 field=gate.field
 field.process_mode=Node.PROCESS_MODE_DISABLED
 s=field.session
 clock=field.life_clock
 if stage=="return_correction":
  check(s.mine_rescue_traces._plans["worker:2"].correction and s.actors["worker:2"].path==saved.field_snapshot.session.actors["worker:2"].path,"fresh runtime preserves saved final-correction plan")
  check(Vector2(s.actors["worker:2"].x,s.actors["worker:2"].y).distance_to(s.BASE)>0.0 and s.rescue_ledger.case_for("worker:0").get("phase")=="carried","load does not snap final correction or start treatment early")
 field._toggle_field_pause()
 check(not paused,stage+": actual resume callback")
 var row: Dictionary=s.rescue_ledger.case_for("worker:0")
 if row.get("phase")=="waiting":
  check(s.request_rescue("worker:0","worker:2",s.session_id).get("ok",false),stage+": request rescue normally")
 s.request_recall()
 row=s.rescue_ledger.case_for("worker:0")
 if row.get("phase")=="assigned":
  check(advance(clock,func():return s.rescue_ledger.case_for("worker:0").get("phase")=="carried",60.0),stage+": physical approach reaches held target")
 row=s.rescue_ledger.case_for("worker:0")
 if row.get("phase")=="carried" and s.actors["worker:2"].state=="rescue_hold":
  check(s.request_rescue_return("worker:0",s.session_id).get("ok",false),stage+": explicit transport request")
 check(advance(clock,func():return s.phase=="ready_to_exit",90.0),stage+": real movement and docking reach safe commit")
 if failures>before_failures:return
 field._commit_and_exit()
 main.process_mode=Node.PROCESS_MODE_DISABLED
 check(s.committed and gate.field==null and main.workers.size()==saved.crew.size(),stage+": one commit keeps person count")
 for rid in s.resources:
  check(main.world.locations[s.SOURCE_KEY][rid].data.remaining==s.resources[rid].remaining,stage+": committed source remainder "+rid)
 for item in s.depot_stock:
  check(main.storage.inventory.count(item)==int(saved.inventory.get(item,0))+int(s.depot_stock[item]),stage+": cargo deposited once")
 check(main.total_gathered==saved.main.total_gathered and main.town.credits==saved.town.credits,stage+": no invented rewards or fees")
 var committed=SaveGame.capture(main)
 check(s.commit_to_game(main).get("already_committed",false) and SaveGame.capture(main)==committed,stage+": second commit is inert")
 check(FileAccess.get_sha256(path)==receipt.hash,stage+": producer file remains unchanged")
 await process_frame
func reject_file(bad: Dictionary,label: String,recovery: Dictionary) -> void:
 var old=main.mine_arrival_gate.field
 var old_clock=old.life_clock
 var before=SaveGame.capture(main)
 var accepted=SaveGame.apply(main,bad)
 check(not accepted,label)
 if accepted:
  check(SaveGame.apply(main,recovery),"reset fixture after unexpected acceptance")
 else:
  check(main.mine_arrival_gate.field==old and old_clock.is_current() and SaveGame.capture(main)==before,label+": live state unchanged")

func finish() -> void:
 SaveGame.disabled=true
 if main!=null and is_instance_valid(main):main.queue_free()
 await process_frame
 print("C FIELD ACTIVE RESTART assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
