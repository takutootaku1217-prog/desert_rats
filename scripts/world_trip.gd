class_name WorldTrip
extends RefCounted
## 地理の進捗と有限の屋外記録。拠点・仲間・屋内加工は交換しない。
var game
var active := true
var region := "south_oasis"
var phase := "stopped" # stopped / departing / travel / arriving / turning
var road := ""
var origin := ""
var destination := ""
var progress := 0.0 # 道路のa端からの座標。復路でも燃料用の走行量は正。
var direction := 1
var locations := {} # location -> {entity-id: {type,data,anchor,spent}}
var ecosystem_epoch := {}
## A claimed town reward renews one subsequently visited normal-world region.
## It is saved so claiming, quitting, and returning later cannot lose or repeat
## the renewal.
var reward_replenish_pending := false
## Returning to the reward city after a turnback is not the subsequent normal
## region visit that consumes this reservation.
var reward_replenish_excluded_region := ""
const FAUNA_RETURN_SECONDS := 120.0
var next_id := 0
const FIELDS := ["active","region","phase","road","origin","destination","progress","direction","locations","next_id","ecosystem_epoch","reward_replenish_pending","reward_replenish_excluded_region"]

func setup(g) -> void:
 game = g
 # 旧ループの診断だけ明示的に互換経路を使う。通常の起動は必ず地図モード。
 active = not OS.get_cmdline_user_args().has("legacy-world-test")
 if active: _ensure_location()

func key() -> String:
 return "road:" + road if phase in ["travel","arriving","turning"] else "region:" + region
func recalling() -> bool:
 return phase=="legacy_recall" or (active and phase in ["departing","arriving","turning"])
func ready_reason() -> String:
 if region==TownDB.RECOVERY_TO and game.town.recovery in ["site","loading","carried"]:
  return "回収依頼が未完了：現地で完了または断念を選んでください"
 if game.quarry.hostile(): return "襲撃・敵への対処が終わるまで待機"
 if game.expedition.state == "running": return "遠征隊の帰還待ち"
 if not game.quarry.loose.is_empty(): return "鉱床の残置品が未回収"
 for w in game.workers:
  if w.away or w.floor_i == 0 or w._climb_dest != null or w.carrying >= 0 or not w.carry_bonus.is_empty() or game.town.recovery_carried_by(w): return "仲間と荷物の帰還・荷卸し待ち"
  for target in [w.ai.res,w.ai.prey,w.ai.enemy]:
   if is_instance_valid(target): return "屋外作業の予約解除待ち"
 return ""
func request(to: String, planned := false) -> bool:
 if not active or phase != "stopped" or game.quarry.state != "road" or game.game_over: return false
 if region==TownDB.RECOVERY_TO and game.town.recovery_blocks_departure(): return false
 var r := WorldMapDB.road_between(region,to)
 if not WorldMapDB.public_road(r): return false
 # 都市を出る瞬間だけ、出発前の完全な checkpoint を確定する。
 # 書き込みに失敗しても旧 checkpoint は残し、既存の出発可否は変えない。
 if region == "central_trade" and not SaveGame.write_checkpoint(game): game.director.note("チェックポイント保存失敗: " + SaveGame.last_error)
 if not planned:game.journey.clear()
 origin = region; destination = to; road = r; phase = "departing"
 return true

func schedule_mission_replenishment() -> void:
 reward_replenish_pending=true
 reward_replenish_excluded_region=region

## Do not create new IDs. Reset only the stored normal-world entities for the
## region just reached; _spawn_visible then materializes each existing ID once.
## This never runs at the town where the reward was claimed, so no entity can
## respawn instantly at the current location.
func _apply_reward_replenishment() -> void:
 if not reward_replenish_pending:return
 if region==reward_replenish_excluded_region:return
 for id in locations.get(key(),{}):
  var row:Dictionary=locations[key()][id]
  match row.type:
   "gather":
    row.spent=false
    row.data.remaining=row.data.max_amount
    row.data.work=0.0
   "creature":
    row.spent=false
    row.data.dead=false
    row.data.hp=row.data.max_hp
    row.data._fleeing=false
    row.data._wander=0.0
    row.data._wander_t=1.0
    row.erase("return_at")
 reward_replenish_pending=false
 reward_replenish_excluded_region=""

func cancel_or_return() -> bool:
 if game.game_over: return false
 game.journey.clear()
 if phase=="legacy_recall": phase="stopped"; _release_waiters(); return true
 match phase:
  "departing": phase = "stopped"; road = ""; origin = ""; destination = ""
  "travel", "arriving": phase = "turning"
  "turning": phase = "travel"
  _: return false
 _release_waiters()
 return true
func _release_waiters() -> void:
 for w in game.workers:
  if w.ai.state == CharacterAI.State.RETURN_BASE: w.ai._set_state(CharacterAI.State.SEARCH)
func speed_limit(speed: float,delta: float) -> float:
 if phase=="legacy_recall": return 0.0
 if not active or game.quarry.state != "road": return speed
 if phase != "travel": return 0.0
 var left := WorldMapDB.LENGTH-progress if direction==1 else progress
 return minf(speed,left/maxf(delta,0.00001))
func tick(dist: float) -> void:
 if phase=="legacy_recall" and ready_reason()=="":
  active=true; region="south_oasis"; phase="stopped"
  locations[key()]={}; sync() # 明示同意した旧街道を村の位置として保持。初期物資を再配布しない。
 if not active: return
 sync()
 _update_ecosystem()
 if game.quarry.state != "road": return
 if phase == "travel":
  progress = clampf(progress + dist*direction,0.0,WorldMapDB.LENGTH)
  if (direction==1 and progress>=WorldMapDB.LENGTH) or (direction==-1 and progress<=0): phase="arriving"
 if recalling() and ready_reason()=="":
  _archive()
  match phase:
   "departing":
    start_leg()
   "arriving":
    region=destination; phase="stopped"; road=""; origin=""; destination=""
    game.journey.arrived()
    _ensure_location()
    _apply_reward_replenishment()
    game.director.note(("通過：" if phase=="travel" else "停車：")+WorldMapDB.name_of(region))
   "turning":
    var previous := origin; origin=destination; destination=previous
    direction *= -1; phase="travel"
  _release_waiters()
  _ensure_location()
 _spawn_visible()
func start_leg() -> void:
 direction=1 if WorldMapDB.ROADS[road][0]==origin else -1
 progress=0.0 if direction==1 else WorldMapDB.LENGTH
 phase="travel"
 game.journey.leg_started()
func status_text() -> String:
 if not active: return "旧形式の街道（地域移行前）"
 if phase=="stopped": return WorldMapDB.name_of(region)+"に停泊中"
 var left := WorldMapDB.LENGTH-progress if direction==1 else progress
 return "%s → %s\n%s%s" % [WorldMapDB.name_of(origin),WorldMapDB.name_of(destination),
  "走行中：残り %.0f / %.0f" % [left,WorldMapDB.LENGTH] if phase=="travel" else {"departing":"出発準備","arriving":"到着待ち","turning":"引返し準備"}.get(phase,phase),
  ("\n"+ready_reason()) if recalling() else ""]
func tint() -> Color:
 if not active: return Color.WHITE
 if phase in ["travel","arriving","turning"]:
  var ends: Array=WorldMapDB.ROADS[road]
  return WorldMapDB.REGIONS[ends[0]].tint.lerp(WorldMapDB.REGIONS[ends[1]].tint,progress/WorldMapDB.LENGTH)
 return WorldMapDB.REGIONS[region].tint

func _anchor(x: float) -> float:
 return progress+(x-1330.0)*direction if key().begins_with("road:") else x
func _x(anchor: float) -> float:
 return 1330.0+(anchor-progress)*direction if key().begins_with("road:") else anchor
func _all_nodes() -> Array:
 return game.resources_root.get_children()+game.creatures_root.get_children()+game.enemies_root.get_children()
func _record(n) -> Dictionary:
 if n is GatherPoint: return {"type":"gather","data":SaveGame.fields(n,SaveGame.RESOURCE+SaveGame.GATHER)}
 if n is ResourceNode: return {"type":"resource","data":SaveGame.fields(n,SaveGame.RESOURCE)}
 if n is Creature: return {"type":"creature","data":SaveGame.fields(n,SaveGame.CREATURE)}
 return {"type":"enemy","data":SaveGame.fields(n,SaveGame.ENEMY)}
func remember(n,spent := false) -> void:
 if not active or n.has_meta("quarry_id"): return
 if not locations.has(key()): locations[key()]={}
 if n.world_id=="":
  n.world_id="entity_%d" % next_id; next_id+=1
 var row := _record(n)
 var old: Dictionary=locations[key()].get(n.world_id,{})
 row["anchor"]=old.get("anchor",_anchor(n.position.x)) if n is ResourceNode and game.quarry.state=="road" else _anchor(n.position.x)
 row["spent"]=spent
 if n is Creature:
  row["home_anchor"]=old.get("home_anchor",WorldMapDB.LENGTH*0.5 if key().begins_with("road:") else 1170.0)
  if old.has("return_at"): row["return_at"]=old.return_at
 locations[key()][n.world_id]=row
# 画面外でも同じ有限個体。時間は保存するので再訪連打では帰らない。
func shelter_creature(n) -> void:
 remember(n)
 if active and locations.get(key(),{}).has(n.world_id):
  locations[key()][n.world_id]["return_at"]=game.director.elapsed+FAUNA_RETURN_SECONDS

func _return_fauna(present: Dictionary) -> void:
 for id in locations.get(key(),{}):
  var row:Dictionary=locations[key()][id]
  if row.type!="creature" or row.spent or row.data.dead or row.data.hp<=0 or present.has(id):continue
  if not row.has("return_at"):
   # 旧保存の画面外生存個体にも同じ待機を一度だけ設定。
   var x:=_x(row.anchor)
   if x>=game.camera_left()-50 and x<=game.camera_left()+1330:continue
   row["return_at"]=game.director.elapsed+FAUNA_RETURN_SECONDS
  if game.director.elapsed<float(row.return_at):continue
  row.anchor=row.get("home_anchor",WorldMapDB.LENGTH*0.5 if key().begins_with("road:") else 1170.0)
  row.data.position.x=_x(row.anchor)
  row.data._fleeing=false
  row.data._wander=0.0
  row.data._wander_t=1.0
  row.erase("return_at")

func sync() -> void:
 if not active: return
 for n in _all_nodes():
  if not n.is_queued_for_deletion(): remember(n)
func consume(n) -> void:
 remember(n,true)
func project_resource(n) -> bool:
 if not active or game.quarry.state!="road" or n.world_id=="" or n.has_meta("quarry_id"): return false
 var row: Dictionary=locations.get(key(),{}).get(n.world_id,{})
 if row.is_empty(): return false
 n.position.x=_x(row.anchor)
 return true
func _archive() -> void:
 for n in _all_nodes():
  if n.has_meta("quarry_id"): continue
  n.get_parent().remove_child(n); n.queue_free()
func _ensure_location() -> void:
 if locations.has(key()): return
 locations[key()]={}
 var kinds: Array=WorldMapDB.REGIONS[region].points
 var travelling:=key().begins_with("road:")
 if travelling: kinds=["rock","vein","rock","tree"] if road=="06" else ["tree","rock","tree","vein"]
 var count := WorldMapDB.ROAD_POINTS if travelling else kinds.size()
 for i in count:
  var p:=GatherPoint.new(); p.setup(game,kinds[i%kinds.size()])
  var anchor := i*WorldMapDB.LENGTH/float(count) if travelling else 1070.0+i*90.0
  if not travelling and region=="south_oasis" and p.kind=="tree": p.max_amount=36;p.remaining=36
  if not travelling and region=="south_oasis" and p.kind=="vein": p.max_amount=4;p.remaining=4
  p.position=Vector2(_x(anchor),630.0+(i%3)*20.0)
  remember(p); locations[key()][p.world_id].anchor=anchor; p.free()
 # 既存の野生生物も有限枠。出入りで新しい獲物を配らない。
 if region!="old_mine" or travelling:
  var species:String=("lizard" if road in ["01","04"] else "hump") if travelling else WorldMapDB.REGIONS[region].get("creature","hare")
  var c:=Creature.new(); c.setup(game,species)
  var anchor:=WorldMapDB.LENGTH*0.5 if travelling else 1170.0
  c.position=Vector2(_x(anchor),680)
  remember(c); locations[key()][c.world_id].anchor=anchor; c.free()
 # 固定個体枠。死亡後は補充しない。120秒ごとに生きている個体の滞在範囲だけ変化。
 if not travelling:
  var roster:Array={"south_oasis":[],"east_sands":["dust_guard","dune_horn"],"central_trade":["paraceratherium"],"old_mine":["sand_stalker","hull_breaker","dust_guard"]}.get(region,[])
  for i in roster.size():
   var e:=Enemy.new();e.setup_kind(game,roster[i]);e.ecological=true
   e.position=Vector2(1080.0 if e.herbivore() else 350.0+i*160.0,680);e.home_x=e.position.x
   remember(e);e.free()
 ecosystem_epoch[key()]=floori(game.director.elapsed/120.0)

func _update_ecosystem() -> void:
 var epoch:=floori(game.director.elapsed/120.0)
 if int(ecosystem_epoch.get(key(),epoch))==epoch:return
 ecosystem_epoch[key()]=epoch
 var roster_index:=0
 for id in locations.get(key(),{}):
  var row:Dictionary=locations[key()][id]
  if row.type!="enemy" or not row.data.get("ecological",false) or row.spent:continue
  if EventDB.ENEMIES[row.data.kind].get("herbivore",false):continue
  var index:=roster_index
  roster_index+=1
  var live=null
  for e in game.enemies_root.get_children():
   if e.world_id==id:live=e;break
  var at:Vector2=row.data.position if live==null else live.position
  if game.workers.any(func(w):return not w.away and w.floor_i==0 and w.position.distance_to(at)<260.0):continue
  if live!=null and (live.target_index>=0 or live.search_left>0):continue
  var present_now:bool=(epoch+index)%3!=0
  var home:float=350.0+index*160.0+float((epoch%3)-1)*35.0
  row.data.present=present_now;row.data.home_x=home;row.data.position.x=home;row.anchor=home
  if live!=null:live.present=present_now;live.home_x=home;live.position.x=home;live.visible=present_now

func _spawn_visible() -> void:
 var present:={}
 for n in _all_nodes():
  if not n.is_queued_for_deletion(): present[n.world_id]=true
 _return_fauna(present)
 for id in locations.get(key(),{}):
  var row:Dictionary=locations[key()][id]
  if row.spent or present.has(id): continue
  var x:=_x(row.anchor)
  if x<game.camera_left()-50 or x>game.camera_left()+1330: continue
  var n
  var parent=game.resources_root
  match row.type:
   "gather": n=GatherPoint.new()
   "resource": n=ResourceNode.new()
   "creature": n=Creature.new(); parent=game.creatures_root
   "enemy": n=Enemy.new(); parent=game.enemies_root
  n.game=game
  SaveGame.put(n,row.data,row.data.keys())
  n.position.x=x
  parent.add_child(n)

func request_legacy_region() -> bool:
 if active or game.quarry.state not in ["road","parked","recall"]: return false
 if game.quarry.sheltered():
  active=true; region="old_mine"; locations[key()]={}; sync()
 else: phase="legacy_recall"
 return true

static func normalized(d: Dictionary) -> Dictionary:
 var result:=d.duplicate(true)
 if not result.has("ecosystem_epoch"):result.ecosystem_epoch={}
 if not result.has("reward_replenish_pending"):result.reward_replenish_pending=false
 if not result.has("reward_replenish_excluded_region"):result.reward_replenish_excluded_region="central_trade" if result.reward_replenish_pending else ""
 return result
static func valid(d, g) -> bool:
 if not d is Dictionary:return false
 d=normalized(d)
 if not SaveGame.shape(d,g.world,FIELDS): return false
 if not WorldMapDB.public_region(d.region) or d.direction not in [-1,1] or d.next_id<0 or d.progress<0 or d.progress>WorldMapDB.LENGTH: return false
 if d.phase not in ["stopped","departing","travel","arriving","turning","legacy_recall"]: return false
 if d.phase=="legacy_recall" and d.active: return false
 if d.phase in ["departing","travel","arriving","turning"]:
  if not WorldMapDB.public_road(d.road) or WorldMapDB.road_between(d.origin,d.destination)!=d.road: return false
 var ids:={}
 for location in d.locations:
  if not location is String: return false
  if location.begins_with("road:"):
   if not WorldMapDB.public_road(location.trim_prefix("road:")): return false
  elif location.begins_with("region:"):
   if not WorldMapDB.public_region(location.trim_prefix("region:")): return false
  else: return false
  if not d.locations[location] is Dictionary: return false
  for id in d.locations[location]:
   if not id is String or not id.begins_with("entity_") or not id.trim_prefix("entity_").is_valid_int() or int(id.trim_prefix("entity_"))<0 or int(id.trim_prefix("entity_"))>=d.next_id or ids.has(id): return false
   ids[id]=true
   var row=d.locations[location][id]
   if not id is String or not row is Dictionary or not row.get("data") is Dictionary or not row.get("spent") is bool or typeof(row.get("anchor")) not in [TYPE_FLOAT,TYPE_INT]: return false
   for field in ["return_at","home_anchor"]:
    if row.has(field) and (typeof(row[field]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(row[field]))):return false
   if row.has("return_at") and row.return_at<0:return false
   var node
   var names:Array
   match row.get("type"):
    "gather": node=GatherPoint.new(); names=SaveGame.RESOURCE+SaveGame.GATHER
    "resource": node=ResourceNode.new(); names=SaveGame.RESOURCE
    "creature": node=Creature.new(); names=SaveGame.CREATURE
    "enemy": node=Enemy.new(); names=SaveGame.ENEMY
    _: return false
   var ok:bool=SaveGame.shape(SaveGame.enemy_data(row.data) if row.type=="enemy" else row.data,node,names) and row.data.get("world_id")==id
   node.free()
   if not ok: return false
   if row.type=="gather" and (not GatherDB.POINTS.has(row.data.kind) or row.data.remaining<0 or row.data.remaining>row.data.max_amount or row.data.work<0): return false
   if row.type in ["resource","gather"] and row.data.item not in GameData.Item.values(): return false
   if row.type=="creature" and not GameData.CREATURES.has(row.data.species): return false
   if row.type=="enemy" and not EventDB.ENEMIES.has(row.data.kind): return false
 return true

## 保存台帳と表示中の実体は一つの所有者。重複ID・消費済み実体の復活を拒否。
static func live_valid(d: Dictionary) -> bool:
 if not d.world.active: return true
 var key:String="road:"+d.world.road if d.world.phase in ["travel","arriving","turning"] else "region:"+d.world.region
 var ledger:Dictionary=d.world.locations.get(key,{})
 var seen:={}
 var rows:Array=[]
 for r in d.resources:
  if r.quarry_id!="": continue
  var data:Dictionary=r.resource.duplicate(true); data.merge(r.gather)
  rows.append(data)
 rows.append_array(d.creatures); rows.append_array(d.enemies)
 for data in rows:
  var id:String=data.world_id
  # 旧v2の鉱床内移行直後のみID未割当。次回captureが記録する。
  if id=="" and d.quarry.state in ["parked","recall"]: continue
  if id=="" or seen.has(id) or not ledger.has(id) or ledger[id].spent or ledger[id].data!=data: return false
  seen[id]=true
 return true
