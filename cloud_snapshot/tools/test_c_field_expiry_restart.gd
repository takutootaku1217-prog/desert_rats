extends SceneTree
const Owners = preload("res://bridge/c_field_snapshot_owners.gd")
const STAGES = ["expired_return","expired_closed","expired_dock","expired_wait","expired_invalid"]
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
 if stage=="expired_return":
  var malformed=saved.duplicate(true)
  malformed.field_snapshot.plans["worker:0"].witness.target_trace=Vector2(4,5)
  reject_file(malformed,"scalar absent-target witness rejected cleanly",saved)
  malformed=saved.duplicate(true)
  malformed.field_snapshot.session.actors["worker:0"].expired_self_return=Vector2(4,5)
  reject_file(malformed,"scalar expiry flag rejected cleanly",saved)
  malformed=saved.duplicate(true)
  malformed.field_snapshot.session.actors["worker:0"].state="safe_wait"
  malformed.field_snapshot.session.actors["worker:0"].resume_state="injured_return"
  reject_file(malformed,"blocked expiry cannot retain a moving path",saved)
  field=gate.field
  s=field.session
  clock=field.life_clock
 if stage=="expired_invalid":
  check(s.expired_recovery._records["worker:0"].invalid,"invalid tombstone remains invalid after fresh identity bind")
  field._toggle_field_pause()
  var before_position=Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)
  clock.tick(10.0)
  check(Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)==before_position and s.phase!="ready_to_exit","invalid owner never moves or grants exit")
  return
 field._toggle_field_pause()
 check(not paused,stage+": actual resume callback")
 if s.all_routes_closed:
  var before_position=Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)
  clock.tick(1.0)
  check(Vector2(s.actors["worker:0"].x,s.actors["worker:0"].y)==before_position,"closed restored owner stays stopped")
  s.set_all_routes_closed(false)
 for id in s.expired_recovery._records:
  check(s.actors[id].hp==CrewStatusDB.HP_REVIVE_AT and not s.actors[id].down and s.rescue_ledger.case_for(id).is_empty(),"expiry resumes without new incapacitation or manual treatment "+id)
 s.request_recall()
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
 print("C FIELD EXPIRY RESTART assertions=",assertions," failures=",failures)
 quit(0 if failures==0 else 1)
