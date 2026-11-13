extends SceneTree
const Session=preload("res://bridge/route_connection_session.gd")
func _init(): call_deferred("run")
var fails:=0
func check(ok:bool,msg:String):
 print("ok " if ok else "FAIL ",msg)
 if not ok:fails+=1
func run():
 SaveGame.disabled=true
 var g=load("res://scenes/main.tscn").instantiate()
 g.first_region_a_pilot=true
 root.add_child(g)
 g.process_mode=Node.PROCESS_MODE_DISABLED
 await process_frame
 g.director.enabled=false
 for w in g.workers:
  w.stop_work()
  for job in GameData.job_list(): w.priorities[job]=0
 for dest in ["b_forest","c_quarry"]:
  g.world.request(dest)
  for i in 1200:
   g._process(0.2)
   if g.world.phase=="stopped" and g.world.region==dest:break
 var path="res://bridge/field_survival_clock.gd"
 check(ResourceLoader.exists(path),"FieldSurvivalClock exists")
 if not ResourceLoader.exists(path):g.free();quit(1);return
 var s=Session.create_from_game(g,"life-test",{}).session
 var c=load(path).new()
 check(c.setup(g,s).ok,"bind clock")
 var h:float=g.workers[0].hunger
 var fat:float=g.workers[0].fatigue
 var t:float=g.director.elapsed
 var fuel:float=g.base.fuel
 var distance:float=g.director.distance
 var food:int=g.storage.count_of(GameData.Item.FOOD)
 g.director.forecast.append({"id":"raid_scorpion","left":1000.0}) # no spawn; countdown witness
 for i in 50:c.tick(0.2)
 check(g.workers[0].hunger<h and s.actors["worker:0"].hunger==g.workers[0].hunger,"hunger advances and stays actor-authoritative")
 check(is_equal_approx(g.director.elapsed,t+10.0),"world time advances exactly once")
 check(is_equal_approx(float(g.director.forecast[0].left),990.0),"event countdown continues")
 check(g.workers[0].fatigue>fat,"active field collection gains fatigue")
 check(g.director.distance==distance and g.base.fuel<=fuel,"stationary distance unchanged; no travel fuel")
 check(g.storage.count_of(GameData.Item.FOOD)==food,"no automatic food consumption or cooking")
 var snap=s.to_dict()
 var fixture_name="field-life-v3-%d.json"%Time.get_ticks_usec()
 check(s.save_project_fixture(fixture_name).ok,"actual local field fixture writes")
 var fixture=Session.load_project_fixture(fixture_name)
 check(fixture.ok,"actual JSON field fixture reads numeric mental safely")
 var restored=Session.from_dict(snap)
 check(restored.ok,"new life snapshot validates")
 var c2=load(path).new()
 check(c2.setup(g,restored.session).ok,"latest snapshot rebinds same runtime")
 check(c.setup(g,s).ok,"explicit unchanged snapshot handback restores original sole owner")
 var corrupt=snap.duplicate(true);corrupt.life_clock_paid=INF
 check(not Session.from_dict(corrupt).ok,"nonfinite paid time rejected")
 var bad_hunger=snap.duplicate(true);bad_hunger.actors["worker:0"].hunger=-1.0
 check(not Session.from_dict(bad_hunger).ok,"invalid actor hunger rejected")
 var wrong_game=snap.duplicate(true);wrong_game.life_clock_token="another-runtime"
 var wrong_session=Session.from_dict(wrong_game)
 var wrong_clock=load(path).new()
 check(wrong_session.ok and not wrong_clock.setup(g,wrong_session.session).ok,"partial field save from other runtime rejected")
 var old_schema=snap.duplicate(true);old_schema.schema=6;old_schema.erase("life_clock_paid");old_schema.erase("life_clock_token");old_schema.erase("rescue")
 for actor in old_schema.actors.values():actor.erase("hunger");actor.erase("calm");actor.erase("mental")
 check(Session.from_dict(old_schema).ok,"legacy schema6 remains readable")
 var paused_h:float=g.workers[0].hunger
 var paused_t:float=g.director.elapsed
 paused=true;c.tick(1.0);paused=false
 check(g.workers[0].hunger==paused_h and g.director.elapsed==paused_t,"tree pause halts field life")
 c.tick(1.0)
 var duplicate_time:float=g.director.elapsed
 c2.tick(1.0)
 check(g.director.elapsed==duplicate_time,"duplicate/reopened older adapter cannot advance time twice")
 var stale=load(path).new()
 check(not stale.setup(g,restored.session).ok,"stale partial save rejected rather than rolling back survival")
 s.actors["worker:0"].hunger=5.0
 s.actors["worker:0"].fatigue=10.0
 s.actors["worker:0"].hp=25.0
 c.tick(0.2)
 check(g.workers[0].hp==25.0 and s.actors["worker:0"].hp==25.0,"no phantom HP healing from sleeping/old Worker state")
 var multiplier:float=maxf(CrewStatus._low_mult(CrewStatusDB.FATIGUE_MULT_HUNGER,g.workers[0].hunger),CrewStatus._low_mult(CrewStatusDB.FATIGUE_MULT_HP,25.0))
 var expected_fatigue:float=10.0+CrewStatusDB.FATIGUE_GAIN_ACTIVE*multiplier*g.director.energy_mult()*(1.0-g.room_effect("drain_cut"))*0.2
 check(is_equal_approx(g.workers[0].fatigue,expected_fatigue),"existing hunger/HP fatigue penalty formula retained")
 check(g.workers[0].mental==CrewStatus.mental_of(g.workers[0]),"existing hunger mental penalty retained")
 check(is_equal_approx(float(s.actors["worker:0"].get("life_move_mult",1.0)),CrewStatus.move_mult(g.workers[0])) and float(s.actors["worker:0"].get("life_move_mult",1.0))<1.0,"existing low-status movement multiplier updates in field")
 var move_fixture={"x":0.0,"y":0.0,"path":[[1000.0,0.0]],"path_index":0,"path_speed":100.0,"life_move_mult":CrewStatus.move_mult(g.workers[0])}
 s._advance(move_fixture,1.0)
 check(is_equal_approx(float(move_fixture.x),100.0*CrewStatus.move_mult(g.workers[0])),"actual field step applies existing status speed coefficient")
 s.request_recall()
 for i in 3000:
  c.tick(0.2)
  if s.phase=="ready_to_exit":break
 var ready_time:float=g.director.elapsed
 c.tick(3.0)
 check(g.director.elapsed==ready_time and c.status_text().contains("一時停止"),"return-ready summary pauses life and explicitly labels the pause")
 var before:float=g.director.elapsed
 var ready_clone=Session.from_dict(s.to_dict()).session
 var clone_clock=load(path).new()
 check(clone_clock.setup(g,ready_clone).ok,"same-time clone binds before original commit")
 check(c.setup(g,s).ok,"explicit ready-state handback authorizes original commit")
 var result=s.commit_to_game(g)
 check(result.ok and is_equal_approx(g.director.elapsed,before),"commit does not double-pay life clock")
 var after_commit_hunger:float=g.workers[0].hunger
 clone_clock.tick(1.0)
 check(not clone_clock.is_current() and g.workers[0].hunger==after_commit_hunger,"prebound uncommitted clone loses projection authority after original commit")
 check(c.is_current(),"original committed clock retains teardown authority")
 check(str(ready_clone.commit_to_game(g).get("reason", "")).contains("生命時計"),"second clone of same life session cannot commit twice")
 s.commit_to_game(g)
 check(is_equal_approx(g.director.elapsed,before),"repeat commit does not advance time")
 c.tick(10)
 check(is_equal_approx(g.director.elapsed,before),"committed clock cannot continue")
 var full_save=SaveGame.capture(g)
 check(SaveGame.validate(full_save,g),"normal returned snapshot validates")
 var old_token=g.get_meta("field_life_generation")
 var invalid_save=full_save.duplicate(true);invalid_save.version=-99
 check(not SaveGame.apply(g,invalid_save) and g.get_meta("field_life_generation")==old_token,"invalid full save preserves runtime generation")
 check(SaveGame.apply(g,full_save) and not g.has_meta("field_life_generation") and not g.has_meta("field_life_paid"),"valid normal SaveGame.apply resets field generation")
 var adapter_script=load("res://bridge/route_connection_adapter.gd")
 var invalid_adapter=adapter_script.new()
 var worker_parent=g.workers[0].get_parent()
 invalid_adapter.configure(g,Session.from_dict(snap).session)
 root.add_child(invalid_adapter)
 check(not invalid_adapter.life_clock.bound and g.workers[0].get_parent()==worker_parent,"bind-failed adapter does not take or project workers")
 invalid_adapter.free()
 var adapter_session=Session.from_dict(snap).session
 adapter_session.session_id="adapter-life-test"
 adapter_session.life_clock_token=""
 adapter_session.life_clock_paid=0.0
 adapter_session.elapsed=0.0
 var valid_adapter=adapter_script.new()
 valid_adapter.configure(g,adapter_session)
 root.add_child(valid_adapter)
 load(path).reset_runtime(g)
 g.workers[0].hp=17.0
 adapter_session.phase="ready_to_exit"
 for actor in adapter_session.actors.values():
  actor.state="idle";actor.carry_n=0
 adapter_session.reservations.clear();adapter_session.relay_stock.clear();adapter_session.dock_queue.clear();adapter_session.dock_busy.clear()
 valid_adapter._process(0.2)
 check(str(adapter_session.commit_to_game(g).get("reason", "")).contains("生命時計") and g.workers[0].hp==17.0,"direct stale life session commit cannot overwrite loaded HP")
 valid_adapter._commit_and_exit()
 check(g.workers[0].hp==17.0,"stale adapter commit callback is inert")
 check(g.workers[0].hp==17.0 and not valid_adapter._apply_worker_projection().ok,"stale adapter stops before old actor projection")
 valid_adapter.free()
 check(g.workers[0].hp==17.0 and g.workers[0].get_parent()==worker_parent,"stale adapter teardown preserves loaded life values")
 # Existing game-over UI must stay available above field layer; no new survival actions.
 var end_session=Session.from_dict(snap).session
 end_session.session_id="life-end"
 end_session.life_clock_token=""
 end_session.life_clock_paid=0.0
 end_session.elapsed=0.0
 var end_clock=load(path).new()
 check(end_clock.setup(g,end_session).ok,"fresh field binds after normal return")
 g.base.parts[GameData.Part.HULL]=0.0
 end_clock.tick(0.2)
 check(g.game_over and g._over_layer!=null and g._over_layer.layer>70,"existing game-over overlay appears above field")
 check(g.save_ui.layer>g._over_layer.layer,"fallback save/load UI stays above game-over overlay")
 var end_time:float=g.director.elapsed
 end_clock.tick(2.0)
 check(g.director.elapsed==end_time,"game-over halts clock")
 load(path).reset_runtime(g)
 check(not g.has_meta("field_life_generation") and not g.has_meta("field_life_paid"),"normal-load reset discards old runtime ledger")
 g.free()
 print("FIELD LIFE failures=",fails)
 quit(1 if fails else 0)
