class_name WorldTrip
extends RefCounted
const PrototypeTownLoop = preload("res://data/prototype_town_loop.gd")
## 地理の進捗と有限の屋外記録。拠点・仲間・屋内加工は交換しない。
var game
var active := true
## 通常砂漠と検証用A〜Dを混在させない。profile は保存され、異なるprofileの
## 保存は拒否するため、通常save.jsonを検証版が読んだり上書きしたりしない。
var map_profile := WorldMapDB.DESERT
var region := "south_oasis"
var phase := "stopped" # stopped / departing / travel / arriving / turning
var road := ""
var origin := ""
var destination := ""
var progress := 0.0 # 道路のa端からの座標。復路でも燃料用の走行量は正。
var direction := 1
var locations := {} # location -> {entity-id: {type,data,anchor,spent}}
var ecosystem_epoch := {}
var resource_regeneration_version := 1
# Transient C source owner; never serialized or inferred from wall time.
var regeneration_owner = null
## First-phase pilot only: one completed delivery can reserve one later visit to
## South Oasis.  The reservation records existing ids; it never invents nodes.
var respawn_reservation := {}
## A〜Dの道路/土地利用は、有限資源の locations 台帳とは別。専用lotだけを
## 変え、既存の採取地点を消さない。
var region_state := {}
var site_stores := {}
var guide_progress := {} # Bounded successful-action history, separate from current stock.
var outpost_states := {} # Site-keyed committed return state, never an active sortie.
var region_completion := {} # Versioned independent boss/route endpoint; no rewards.
var npc_facilities := {} # Independent NPC ownership, never inferred from lots.
var npc_service := NpcFuelService.new()
# Shared land/site mutation guard, held through synchronous inventory signals.
# Transient only: never persisted in FIELDS.
var _land_payment_active := false
var departure_error := ""
const FAUNA_RETURN_SECONDS := 120.0
var next_id := 0
var next_greenway_salvage_id := "" # Permanent environmental grant identity, including spent row.
const SALVAGE_LOCATION := "region:next_greenway"
const RESPAWN_MISSION := "delivery"
const RESPAWN_LOCATION := "region:south_oasis"
const FIELDS := ["active","map_profile","region","phase","road","origin","destination","progress","direction","locations","next_id","ecosystem_epoch","respawn_reservation","region_state","site_stores","outpost_states","guide_progress","resource_regeneration_version","region_completion","npc_facilities","next_greenway_salvage_id"]

const GUIDE_EVENT_LABELS := {
 "wood_gathered":"環境由来の木材を倉庫へ搬入",
 "tool_crafted":"木製採掘具を製作完了",
 "stone_gathered":"環境由来の石を倉庫へ搬入",
 "repair_crafted":"石＋木材の応急修理板を製作完了",
 "quarry_returned":"Cの回収物を帰還確定",
 "frame_crafted":"背負いフレームを製作完了",
 "frame_equipped":"仲間画面で背負いフレームを装備・交換",
 "returned_a":"C回収後、Aに停車して帰還",
}
const C_OUTPOST_KIND := "sand_stalker"
const C_OUTPOST_LAYOUT := [
 {"id":"outpost:front","position":Vector2(842,326),"lane":"正面入口"},
 {"id":"outpost:bypass","position":Vector2(855,520),"lane":"迂回入口"},
 {"id":"outpost:yard","position":Vector2(973,270),"lane":"資源置場"},
]
const REGION_A_BUILD := {
 "b_forest":{"lot":"supply","name":"補給・保管場所","cost":{GameData.Item.WOOD:4,GameData.Item.STONE:2},"capacity":24,"footprint":Rect2(720,570,100,140),
  "benefit":"地点別に木材・石材・食料を預け、実際に受け渡せます。"},
 "d_yard":{"lot":"freight","name":"貨物設備","cost":{GameData.Item.WOOD:3,GameData.Item.STONE:3},"capacity":36,"footprint":Rect2(720,570,100,140),
  "benefit":"地点別の貨物受渡しと保管が使えます。"},
}
const REGION_A_CLEAR_COST := {GameData.Item.WOOD:2,GameData.Item.STONE:1}
const REGION_A_GRADE_COST := {GameData.Item.WOOD:2,GameData.Item.STONE:3}

static func first_region_state() -> Dictionary:
 return {"roads":{"ab":{"graded":false},"bd":{"cleared":false}},"lots":{"b_forest":"wild","d_yard":"wild"},"mines":{"c_quarry":{"cart_shortcut_cleared":false}}}
static func first_region_stores() -> Dictionary:
 return {"b_forest":{},"d_yard":{}}

func first_region() -> bool:
 return map_profile==WorldMapDB.FIRST_REGION_A
func region_goal_snapshot() -> Dictionary:
 return FirstRegionCompletion.snapshot(region_completion,region_state) if first_region() else {}
func refresh_region_completion() -> bool:
 if not first_region() or region_completion.completed or not FirstRegionCompletion.boss_returned(region_completion) or not FirstRegionCompletion.route_connected(region_state):return false
 region_completion.completed=true
 _announce_region_completion()
 return true
func _announce_region_completion() -> void:
 game.director.note("第1地域突破：採石場の主を撃破して帰還、B–Dを再接続。Dから次地域入口・旧緑道へ往復できます。奥地・終幕は未実装です。")
func c_quarry_cart_shortcut_cleared() -> bool:
 return first_region() and bool(region_state.get("mines",{}).get("c_quarry",{}).get("cart_shortcut_cleared",false))
func set_c_quarry_cart_shortcut_cleared(cleared: bool) -> bool:
 if not first_region() or not region_state.get("mines",{}) is Dictionary:return false
 var mines:Dictionary=region_state.mines
 if not mines.get("c_quarry",{}) is Dictionary:return false
 mines.c_quarry.cart_shortcut_cleared=cleared
 return true
func is_safe_town() -> bool:
 return PrototypeTownLoop.is_safe_town(game)
func road_length(id := road) -> float:
 return WorldMapDB.road_length(id,map_profile,region_state)
func _region_data(id := region) -> Dictionary:
 return WorldMapDB.region_data(id,map_profile)

func setup(g) -> void:
 game = g
 npc_service.setup(g)
 outpost_states={}
 map_profile=WorldMapDB.FIRST_REGION_A if bool(g.first_region_a_pilot) or OS.get_cmdline_user_args().has("first-region-a") or OS.get_cmdline_user_args().has("--first-region-a") else WorldMapDB.DESERT
 if first_region():
  npc_facilities=NpcFuelFacility.empty()
  region_completion=FirstRegionCompletion.empty()
  guide_progress=empty_guide_progress()
  region="a_start"
  region_state=first_region_state()
  site_stores=first_region_stores()
 else:
  npc_facilities={}
  region_completion={}
  guide_progress={}
  region_state={}
  site_stores={}
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
 if _land_payment_active:return false
 departure_error=""
 if game.mine_arrival_gate != null and is_instance_valid(game.mine_arrival_gate.field): return false
 if not active or phase != "stopped" or game.quarry.state != "road" or game.game_over: return false
 if region==TownDB.RECOVERY_TO and game.town.recovery_blocks_departure(): return false
 var r := WorldMapDB.road_between(region,to,map_profile)
 if not WorldMapDB.public_road(r,map_profile,region_state,region_completion):
  if first_region() and r=="dn":departure_error="未解放：ボス撃破・帰還確定とB–D再接続が必要です。"
  return false
 # A normal departure cannot silently replace the independent retry point.
 # Diagnostic fixtures deliberately disable persistence; their no-op checkpoint
 # still permits their existing state-machine coverage.
 if ((first_region() and region=="a_start") or (not first_region() and region=="central_trade")) and not SaveGame.write_checkpoint(game):
  departure_error="出撃前checkpointを作成できないため出発しません: "+SaveGame.last_error
  game.director.note(departure_error)
  return false
 if not planned:game.journey.clear()
 npc_service.cancel_quote()
 origin = region; destination = to; road = r; phase = "departing"
 return true

func _pilot_target_ids() -> Dictionary:
 var site:Dictionary=locations.get(RESPAWN_LOCATION,{})
 var vein_id := ""
 var creature_id := ""
 var vein_number := 2147483647
 var creature_number := 2147483647
 # Initial world rows are allocated before any later dynamic records.  Choosing
 # the earliest matching fixed row lets old valid saves participate without
 # reseeding their finite ledgers or selecting a carcass ResourceNode.
 for id in site:
  if not id is String or not id.begins_with("entity_") or not id.trim_prefix("entity_").is_valid_int(): continue
  var row:Dictionary=site[id]
  var number:=int(id.trim_prefix("entity_"))
  if row.type=="gather" and row.data.get("kind")=="vein" and row.data.get("item")==GameData.Item.IRON_ORE and number<vein_number:
   vein_id=id;vein_number=number
  elif row.type=="creature" and row.data.get("species")=="hare" and number<creature_number:
   creature_id=id;creature_number=number
 return {"vein_id":vein_id,"creature_id":creature_id} if vein_id!="" and creature_id!="" else {}

## Called only after the signed delivery claim has been revalidated.  A single
## pending slot is deliberate pilot scope: later claims before the next visit do
## not accumulate an unspecified second refill.
func schedule_delivery_respawn(claim: int) -> bool:
 if not respawn_reservation.is_empty(): return true
 var targets:=_pilot_target_ids()
 if targets.is_empty(): return false
 respawn_reservation={"mission":RESPAWN_MISSION,"claim":claim,"location":RESPAWN_LOCATION,
  "vein_id":targets.vein_id,"creature_id":targets.creature_id}
 return true

func _apply_delivery_respawn(arrived_region: String) -> void:
 if respawn_reservation.is_empty() or arrived_region!="south_oasis": return
 if not respawn_reservation_valid(respawn_reservation,locations):
  respawn_reservation={}
  game.director.note("補充予約の対象を検証できないため安全に破棄しました")
  return
 var reservation:Dictionary=respawn_reservation
 var site:Dictionary=locations[RESPAWN_LOCATION]
 var vein:Dictionary=site[reservation.vein_id]
 var creature:Dictionary=site[reservation.creature_id]
 # GatherPoint depletion normally remains spent=false, so restore its quantity
 # and work directly on the same fixed ledger id.
 vein.spent=false
 vein.data.remaining=vein.data.max_amount
 vein.data.work=0.0
 # A living or merely off-screen hare remains the same creature.  Only a dead
 # fixed row is reset; ResourceNode/CARCASS and every other row are excluded.
 if creature.spent or creature.data.dead or creature.data.hp<=0:
  var restored:=Creature.new()
  restored.setup(game,creature.data.species)
  restored.world_id=reservation.creature_id
  restored.position=creature.data.position
  creature.data=SaveGame.fields(restored,SaveGame.CREATURE)
  restored.free()
  creature.spent=false
  creature.erase("return_at")
 respawn_reservation={}
func cancel_or_return() -> bool:
 if game.game_over: return false
 npc_service.cancel_quote()
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
 var left := road_length()-progress if direction==1 else progress
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
  progress = clampf(progress + dist*direction,0.0,road_length())
  if (direction==1 and progress>=road_length()) or (direction==-1 and progress<=0): phase="arriving"
 if recalling() and ready_reason()=="":
  _archive()
  match phase:
   "departing":
    start_leg()
   "arriving":
    var arrived_region:=destination
    var first_city_arrival:bool=not first_region() and arrived_region=="central_trade" and not locations.has("region:central_trade")
    region=arrived_region; phase="stopped"; road=""; origin=""; destination=""
    _ensure_location()
    _apply_delivery_respawn(arrived_region)
    game.journey.arrived()
    if first_region() and region=="a_start" and phase=="stopped":record_guide_event("returned_a")
    # If a multi-leg plan continued automatically, request() has already made
    # the city checkpoint while the route was stopped.  Otherwise save this
    # first city arrival after JourneyPlan consumed its arrival entry.
    if first_city_arrival and phase=="stopped" and not SaveGame.write_checkpoint(game):
     game.director.note("初回都市checkpointを作成できません: "+SaveGame.last_error)
    game.director.note(("通過：" if phase=="travel" else "停車：")+WorldMapDB.name_of(region,map_profile))
   "turning":
    var previous := origin; origin=destination; destination=previous
    direction *= -1; phase="travel"
  _release_waiters()
  _ensure_location()
 _spawn_visible()
func start_leg() -> void:
 var ends:Array=WorldMapDB.road_ends(road,map_profile)
 direction=1 if ends[0]==origin else -1
 progress=0.0 if direction==1 else road_length()
 phase="travel"
 game.journey.leg_started()
func status_text() -> String:
 if not active: return "旧形式の街道（地域移行前）"
 if phase=="stopped": return WorldMapDB.name_of(region,map_profile)+"に停泊中"
 var left := road_length()-progress if direction==1 else progress
 return "%s → %s\n%s%s" % [WorldMapDB.name_of(origin,map_profile),WorldMapDB.name_of(destination,map_profile),
  "走行中：残り %.0f / %.0f" % [left,road_length()] if phase=="travel" else {"departing":"出発準備","arriving":"到着待ち","turning":"引返し準備"}.get(phase,phase),
  ("\n"+ready_reason()) if recalling() else ""]
func tint() -> Color:
 if not active: return Color.WHITE
 if phase in ["travel","arriving","turning"]:
  var ends: Array=WorldMapDB.road_ends(road,map_profile)
  return _region_data(ends[0]).tint.lerp(_region_data(ends[1]).tint,progress/road_length())
 return _region_data().tint

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
 if regeneration_owned(key()): return
 var old: Dictionary=locations[key()].get(n.world_id,{})
 if n is GatherPoint and old.has("regeneration"):
  var before:=int(old.data.remaining)
  var after:=ResourceRegeneration.settle(old.regeneration,before,float(game.director.elapsed),regeneration_blocked(key(),old))
  n.remaining=mini(n.max_amount,n.remaining+after-before)
 var row := _record(n)
 row["anchor"]=old.get("anchor",_anchor(n.position.x)) if n is ResourceNode and game.quarry.state=="road" else _anchor(n.position.x)
 row["spent"]=spent if not n is GatherPoint or n.remaining<=0 else false
 if ResourceRegeneration.eligible(row):
  row["regeneration"]=old.get("regeneration",ResourceRegeneration.create(n.max_amount,float(game.director.elapsed)))
  if n.remaining==n.max_amount:row.regeneration.credit=0.0
 if n is Creature:
  row["home_anchor"]=old.get("home_anchor",road_length()*0.5 if key().begins_with("road:") else 1170.0)
  if old.has("return_at"): row["return_at"]=old.return_at
  if old.has("respawn_at"): row["respawn_at"]=old.respawn_at
 locations[key()][n.world_id]=row
# 画面外でも同じ有限個体。時間は保存するので再訪連打では帰らない。
func shelter_creature(n) -> void:
 remember(n)
 if active and locations.get(key(),{}).has(n.world_id):
  locations[key()][n.world_id]["return_at"]=game.director.elapsed+FAUNA_RETURN_SECONDS

func _return_fauna(present: Dictionary) -> void:
 # A killed prototype animal returns only from its original ledger row, after
 # its species-specific delay. Re-entry/repaint cannot allocate a new id.
 for id in locations.get(key(),{}):
  var spent_row:Dictionary=locations[key()][id]
  if spent_row.type!="creature" or not spent_row.spent or not spent_row.has("respawn_at") or present.has(id):continue
  if game.director.elapsed<float(spent_row.respawn_at):continue
  var restore_at:Vector2=spent_row.data.position
  if game.workers.any(func(w):return not w.away and w.position.distance_to(restore_at)<180.0):continue
  var restored:=Creature.new();restored.setup(game,String(spent_row.data.species));restored.world_id=id;restored.position=restore_at
  spent_row.data=SaveGame.fields(restored,SaveGame.CREATURE);restored.free()
  spent_row.spent=false;spent_row.erase("respawn_at");spent_row.erase("return_at")
 for id in locations.get(key(),{}):
  var row:Dictionary=locations[key()][id]
  if row.type!="creature" or row.spent or row.data.dead or row.data.hp<=0 or present.has(id):continue
  if not row.has("return_at"):
   # 旧保存の画面外生存個体にも同じ待機を一度だけ設定。
   var x:=_x(row.anchor)
   if x>=game.camera_left()-50 and x<=game.camera_left()+1330:continue
   row["return_at"]=game.director.elapsed+FAUNA_RETURN_SECONDS
  if game.director.elapsed<float(row.return_at):continue
  row.anchor=row.get("home_anchor",road_length()*0.5 if key().begins_with("road:") else 1170.0)
  row.data.position.x=_x(row.anchor)
  row.data._fleeing=false
  row.data._wander=0.0
  row.data._wander_t=1.0
  row.erase("return_at")

func sync() -> void:
 if not active: return
 for n in _all_nodes():
  if not n.is_queued_for_deletion(): remember(n)
 settle_regeneration()
func regeneration_owned(location: String) -> bool:
 return regeneration_owner!=null and not regeneration_owner.committed and location=="region:c_quarry"
func regeneration_blocked(location: String,row: Dictionary) -> bool:
 var site:=location.trim_prefix("region:")
 return first_region() and REGION_A_BUILD.has(site) and site_built(site) and ResourceRegeneration.within_footprint(row,REGION_A_BUILD[site].footprint)
func settle_regeneration() -> void:
 if not active:return
 for location in locations:
  if regeneration_owned(location):continue
  for row in locations[location].values():
   if not row.has("regeneration"):continue
   row.data.remaining=ResourceRegeneration.settle(row.regeneration,int(row.data.remaining),float(game.director.elapsed),regeneration_blocked(location,row))
   if row.data.remaining>0:row.spent=false
 # Keep the same live node, claim and work. A spent offscreen node is spawned
 # by the existing stable-ID path, never by setup()/a capacity reroll.
 for n in game.resources_root.get_children():
  if n is GatherPoint and not n.is_queued_for_deletion() and not regeneration_owned(key()):
   var row:Dictionary=locations.get(key(),{}).get(n.world_id,{})
   if row.has("regeneration"):n.remaining=int(row.data.remaining)
func settle_building_footprint(site: String) -> void:
 if not first_region() or not REGION_A_BUILD.has(site):return
 var location:="region:"+site
 for id in locations.get(location,{}).keys():
  var row:Dictionary=locations[location][id]
  if not row.has("regeneration") or not ResourceRegeneration.within_footprint(row,REGION_A_BUILD[site].footprint):continue
  var live=null
  if key()==location:
   for n in game.resources_root.get_children():
    if n is GatherPoint and n.world_id==id and not n.is_queued_for_deletion():live=n;break
  if live!=null:
   remember(live)
   row=locations[location][id]
  row.data.remaining=ResourceRegeneration.settle(row.regeneration,int(row.data.remaining),float(game.director.elapsed),regeneration_blocked(location,row))
  if row.data.remaining>0:row.spent=false
  if live!=null:live.remaining=int(row.data.remaining)
func release_regeneration(owner, discard := false) -> void:
 if regeneration_owner!=owner:return
 if discard:
  for row in locations.get("region:c_quarry",{}).values():
   if row.has("regeneration"):row.regeneration.last=float(game.director.elapsed)
 regeneration_owner=null
func consume(n) -> void:
 remember(n,true)
 if n is Creature and active and locations.get(key(),{}).has(n.world_id):
  var seconds:=GameData.creature_respawn_seconds(n.species)
  if seconds>0.0:locations[key()][n.world_id]["respawn_at"]=game.director.elapsed+seconds
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
 var kinds: Array=_region_data().points
 var travelling:=key().begins_with("road:")
 if travelling:
  kinds=["tree","rock","tree","rock"] if first_region() else (["rock","vein","rock","tree"] if road=="06" else ["tree","rock","tree","vein"])
 var count := WorldMapDB.ROAD_POINTS if travelling else kinds.size()
 for i in count:
  var p:=GatherPoint.new(); p.setup(game,kinds[i%kinds.size()])
  # 地点に止まっている採取場は、既存AIの画面内・到達可能範囲へ全数を置く。
  # 通常砂漠の既存位置は変えず、A地域だけ3〜4個の木石を端で失わない配置にする。
  var anchor := i*road_length()/float(count) if travelling else (960.0+i*80.0 if first_region() else 1070.0+i*90.0)
  if not travelling and region=="south_oasis" and p.kind=="tree": p.max_amount=36;p.remaining=36
  if not travelling and region=="south_oasis" and p.kind=="vein": p.max_amount=4;p.remaining=4
  p.position=Vector2(_x(anchor),630.0+(i%3)*20.0)
  remember(p); locations[key()][p.world_id].anchor=anchor; p.free()
 # 既存の野生生物も有限枠。出入りで新しい獲物を配らない。
 if first_region() or region!="old_mine" or travelling:
  var fauna:Array=WorldMapDB.road_fauna(map_profile) if travelling else WorldMapDB.fauna_of(region,map_profile)
  if fauna.is_empty():fauna=[("lizard" if road in ["01","04"] else "hump") if travelling else String(_region_data().get("creature","hare"))]
  for i in fauna.size():
   var species:String=String(fauna[i])
   if not GameData.CREATURES.has(species):continue
   var c:=Creature.new(); c.setup(game,species)
   var anchor:=road_length()*(0.35+0.2*float(i)) if travelling else (960.0+float(i)*105.0 if first_region() else 1070.0+float(i)*90.0)
   # Road fauna share the one flat travel route with the vehicle.  Stopped
   # resource-site fauna keep their existing field placement.
   c.position=Vector2(_x(anchor),TravelLanePresentation.travel_ground_y() if travelling else 680.0)
   remember(c); locations[key()][c.world_id].anchor=anchor; c.free()
 # 固定個体枠。死亡後は補充しない。120秒ごとに生きている個体の滞在範囲だけ変化。
 if not travelling and not first_region():
  var roster:Array={"south_oasis":[],"east_sands":["dust_guard","dune_horn"],"central_trade":["paraceratherium"],"old_mine":["sand_stalker","hull_breaker","dust_guard"]}.get(region,[])
  for i in roster.size():
   var e:=Enemy.new();e.setup_kind(game,roster[i]);e.ecological=true
   e.position=Vector2(1080.0 if e.herbivore() else 350.0+i*160.0,680);e.home_x=e.position.x
   remember(e);e.free()
 ecosystem_epoch[key()]=floori(game.director.elapsed/120.0)
 if first_region() and key()==SALVAGE_LOCATION and next_greenway_salvage_id=="":
  next_greenway_salvage_id="entity_%d" % next_id;next_id+=1
  locations[key()][next_greenway_salvage_id]=_salvage_row(next_greenway_salvage_id)

static func _salvage_row(id:String) -> Dictionary:
 return {"type":"resource","data":{"world_id":id,"position":Vector2(1160,710),"item":GameData.Item.STORAGE_BOX,"species":"","gather_progress":0.0,"age":0.0},"anchor":1160.0,"spent":false}

## Read-only guidance: discovery is not ownership, installation is not automatic.
func salvage_status() -> String:
 var intro:="旧緑道の旧設備：収納ボックス1個（再生なし）。回収には積載の空き42が必要。設置で積載上限+60、最大3個です。"
 if not first_region():return ""
 var count:int=game.base.facility_count("cargo_rack")
 if count>=FacilityDB.max_of("cargo_rack"):
  return intro+"\n設置済み%d/3：上限のため追加設置できません。回収品は保管できます。" % count
 var row:Dictionary=locations.get(SALVAGE_LOCATION,{}).get(next_greenway_salvage_id,{})
 if row.is_empty():return intro+"\nDから旧緑道へ。現地で仲間が回収し、車両倉庫まで運びます。"
 if not row.spent:
  var available:int=maxi(0,game.storage.max_weight()-game.storage.current_weight()-game.storage.processing_reserve())
  return intro+"\n未回収。現在の積載空き%d（他の採取予約は別）。足りなければAで売却、またはB/Dの地点保管へ。停車後、仲間の採取担当と回収優先を確認してください。" % available
 var pending:int=game.build_pending("cargo_rack")
 if pending>0:
  return intro+"\n設置は依頼済み%d件（設置済み%d/3、依頼込み%d/3）。追加依頼せず、作成で材料・運搬・組立を確認してください。" % [pending,count,count+pending]
 var crafting:Dictionary=game.processor.manual_status("storage_box")
 if int(crafting.queued)+int(crafting.loaded)+int(crafting.active)+int(crafting.output)>0:
  return intro+"\n別の収納ボックスを製作予約中・作業中です。回収品と重複しないよう、作成で注文と必要数を確認してください。倉庫の完成品%d個。" % game.storage.count_of(GameData.Item.STORAGE_BOX)
 if game.storage.count_of(GameData.Item.STORAGE_BOX)>0:
  return intro+"\n倉庫に完成品あり。「作成 → 建設 → 収納ボックス」で設置を依頼。完成品1個だけを使い、木材・鉄の再消費はありません。"
 if game.packed_in_transit(GameData.Item.STORAGE_BOX)>0:
  return intro+"\n運搬・設置待ち。仲間が荷卸し・組立を行います。作業場に移した箱は所持品から倉庫へ戻してください。"
 return intro+"\n旧設備は回収済み。現在の収納ボックス%d/3、積載上限%d。設置後は増えた空きを使って採取へ。回収品の再配布はありません。" % [count,game.storage.max_weight()]

## Read-only expedition-prep summary of B/D site storage and vehicle room.
## Never moves goods: stock stays at its site until withdrawn while stopped there.
func depot_status() -> String:
 if not first_region():return ""
 var lines:PackedStringArray=[]
 for site in REGION_A_BUILD:
  if not site_built(site):continue
  var stock:Dictionary=site_stores.get(site,{})
  var items:PackedStringArray=[]
  for item in ItemDB.ORDER:
   if int(stock.get(item,0))>0:items.append("%s%d" % [GameData.ITEM_NAMES[item],int(stock[item])])
  lines.append("%s（%s）：%s（%d/%d）" % [WorldMapDB.name_of(site,map_profile),REGION_A_BUILD[site].name,"、".join(items) if not items.is_empty() else "空",site_store_total(site),site_capacity(site)])
 if lines.is_empty():return "地点保管：未設置。BまたはDの空き地を転用すると、増えた積載の余りを預けられます。"
 var room:int=maxi(0,game.storage.max_weight()-game.storage.current_weight()-game.storage.processing_reserve())
 return "地点保管\n"+"\n".join(lines)+"\n車両の積載空き%d。保管品は、その地点に停車中だけ取り出せます。遠出先へ自動では運ばれないので、出発前に必要な分を積み、余りは預けてください。" % room

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
 if first_region(): return false
 if game.quarry.sheltered():
  active=true; region="old_mine"; locations[key()]={}; sync()
 else: phase="legacy_recall"
 return true

# ------------------------------------------------------------------
# 第1地域A: 点ごとの土地利用と実在庫。UIはこの純粋な操作だけを呼ぶ。
# locations（採取台帳）を触らないので、建設で最後の木石供給を潰さない。
func land_operation_reason(expected_site := "") -> String:
 # This is a commit boundary, not a departure request. A departure must still
 # be able to start recalling outside crew; ready_reason itself is unchanged.
 if not first_region() or not active:return "第一地域の地図が有効な間だけ操作できます"
 if expected_site!="" and region!=expected_site:return "現在地が変わりました。計画を開き直してください"
 if phase!="stopped":return "停車中だけ、土地利用と実物資の受渡しができます"
 if game.game_over:return "終了後は土地利用と物資の受渡しはできません"
 if game.mine_arrival_gate!=null and is_instance_valid(game.mine_arrival_gate.field):return "採石場から帰還してから操作してください"
 if game.quarry.state!="road":return "鉱床から帰還してから操作してください"
 # Pause, recall stance and return_request are not blockers on their own.
 # Interior production reservations still use warehouse_discard_available.
 return ready_reason()
func _pilot_stopped_at(site: String) -> bool:
 return land_operation_reason(site).is_empty() and REGION_A_BUILD.has(site)
func site_built(site: String) -> bool:
 return first_region() and region_state.get("lots",{}).get(site,"wild")!= "wild"
func site_capacity(site: String) -> int:
 if not site_built(site): return 0
 return int(REGION_A_BUILD[site].capacity)
func site_store(site: String) -> Dictionary:
 return site_stores.get(site,{}).duplicate(true) if first_region() else {}
func site_store_total(site: String) -> int:
 var total:=0
 for item in site_stores.get(site,{}): total+=int(site_stores[site][item])
 return total
func land_preview(action: String) -> Dictionary:
 if not first_region(): return {}
 var reason:=land_operation_reason()
 if action=="build" and REGION_A_BUILD.has(region):
  var d:Dictionary=REGION_A_BUILD[region]
  return {"action":action,"site":region,"reason":reason,"available":reason.is_empty() and not site_built(region),"cost":d.cost.duplicate(true),"gain":d.benefit,
   "kept":"建設用の空き地だけを使います。木材・石材の採取場は残ります。"}
 if action=="clear_shortcut":
  return {"action":action,"site":region,"reason":reason,"available":reason.is_empty() and region in ["b_forest","d_yard"] and not bool(region_state.roads.bd.cleared),"cost":REGION_A_CLEAR_COST.duplicate(true),"gain":"B–Dの倒木近道を恒久開通します。以後は倒木を復活させません。","kept":"森とヤードの採取場は残ります。"}
 if action=="grade_ab":
  return {"action":action,"site":region,"reason":reason,"available":reason.is_empty() and region in ["a_start","b_forest"] and not bool(region_state.roads.ab.graded),"cost":REGION_A_GRADE_COST.duplicate(true),"gain":"A–Bを整地し、移動距離と燃料を28%減らします。敵や採取抽選は変えません。","kept":"道沿いと地点の採取場は残ります。"}
 if action=="remove" and REGION_A_BUILD.has(region):
  return {"action":action,"site":region,"reason":reason,"available":reason.is_empty() and site_built(region) and site_store(region).is_empty(),"cost":{},"gain":"空の保管庫を撤去し、空き地へ戻します。資源は即時に満タン再生しません。","kept":"在庫が残る間は撤去できません。"}
 return {}
func _commit_land_payment(action: String) -> bool:
 if _land_payment_active: return false
 var preview:=land_preview(action)
 if preview.is_empty() or not preview.available: return false
 var cost:Dictionary=preview.cost
 for item in cost:
  if game.warehouse_discard_available(item)<int(cost[item]): return false
 var old_state:Dictionary=region_state.duplicate(true)
 var old_stores:Dictionary=site_stores.duplicate(true)
 var old_completed:bool=region_completion.completed
 if action=="build":settle_building_footprint(str(preview.site))
 _land_payment_active=true
 # Inventory.take_set emits synchronously. Observers must see the outcome and
 # payment together, and cannot start another land mutation during notification.
 match action:
  "build":
   var site:String=preview.site
   region_state.lots[site]=REGION_A_BUILD[site].lot
   if not site_stores.has(site): site_stores[site]={}
  "clear_shortcut": region_state.roads.bd.cleared=true
  "grade_ab": region_state.roads.ab.graded=true
  _:
   _land_payment_active=false
   return false
 if action=="clear_shortcut":region_completion.completed=FirstRegionCompletion.boss_returned(region_completion)
 var paid:bool=game.storage.inventory.take_set(cost)
 if not paid:
  region_state=old_state
  site_stores=old_stores
  region_completion.completed=old_completed
 _land_payment_active=false
 return paid
func build_current_site() -> bool:
 var site:String=region
 if not _commit_land_payment("build"): return false
 game.director.note(WorldMapDB.name_of(site,map_profile)+"を"+REGION_A_BUILD[site].name+"へ転用しました")
 return true
func clear_shortcut() -> bool:
 if not _commit_land_payment("clear_shortcut"): return false
 if region_completion.completed:_announce_region_completion()
 game.director.note("B–Dの倒木を処理し、近道を恒久開通しました")
 return true
func grade_ab() -> bool:
 if not _commit_land_payment("grade_ab"): return false
 game.director.note("A–Bを整地しました。距離と燃料が減ります")
 return true
func remove_current_site() -> bool:
 if _land_payment_active: return false
 var preview:=land_preview("remove")
 if preview.is_empty() or not preview.available: return false
 settle_building_footprint(region) # No blocked-time catch-up on demolition.
 region_state.lots[region]="wild"
 game.director.note(WorldMapDB.name_of(region,map_profile)+"の土地利用を空き地へ戻しました")
 return true
func deposit_to_site(item: int,n := 1) -> int:
 if _land_payment_active or not _pilot_stopped_at(region) or not site_built(region) or n<=0 or item not in ItemDB.ORDER:return 0
 var site:=region
 var room:=site_capacity(site)-site_store_total(site)
 var moved:=mini(n,mini(room,game.warehouse_discard_available(item)))
 if moved<=0:return 0
 var previous:Dictionary=site_stores[site].duplicate(true)
 _land_payment_active=true
 # take_set checks the whole debit before emitting changed. Observers see both
 # ledgers committed, and cannot reenter any land/site mutation during delivery.
 site_stores[site][item]=int(site_stores[site].get(item,0))+moved
 if not game.storage.inventory.take_set({item:moved}):
  site_stores[site]=previous
  moved=0
 _land_payment_active=false
 return moved
func withdraw_from_site(item: int,n := 1) -> int:
 if _land_payment_active or not _pilot_stopped_at(region) or not site_built(region) or n<=0 or item not in ItemDB.ORDER:return 0
 var site:=region
 var moved:=mini(n,mini(int(site_stores[site].get(item,0)),game.storage.free_for(item)))
 if moved<=0:return 0
 # 先に量を確定してから一回だけ両台帳を更新する。満載なら地点在庫も減らない。
 _land_payment_active=true
 site_stores[site][item]-=moved
 if site_stores[site][item]<=0:site_stores[site].erase(item)
 game.storage.store_owned(item,moved,Inventory.SOURCE_TRANSFER)
 _land_payment_active=false
 return moved

static func normalized(d: Dictionary, saved_time := -1.0) -> Dictionary:
 var result:=d.duplicate(true)
 if not result.has("resource_regeneration_version"):
  result.resource_regeneration_version=0
 if not result.resource_regeneration_version is int:return result
 if result.resource_regeneration_version==0 and saved_time>=0.0 and result.get("locations") is Dictionary:
  # Only a whole legacy extension migrates. Missing rows in version 1 reject.
  for rows in result.get("locations",{}).values():
   if not rows is Dictionary:continue
   for row in rows.values():
    if row is Dictionary and ResourceRegeneration.eligible(row) and not row.has("regeneration") and row.data.get("max_amount") is int and row.data.max_amount>0:
     row["regeneration"]=ResourceRegeneration.create(row.data.max_amount,saved_time)
  result.resource_regeneration_version=1
 if not result.has("map_profile"):result.map_profile=WorldMapDB.DESERT
 if not result.has("ecosystem_epoch"):result.ecosystem_epoch={}
 if not result.has("respawn_reservation"):result.respawn_reservation={}
 if not result.has("region_state"):result.region_state=first_region_state() if result.map_profile==WorldMapDB.FIRST_REGION_A else {}
 if result.map_profile==WorldMapDB.FIRST_REGION_A:result.region_state=_normalize_first_region_state(result.region_state)
 if not result.has("guide_progress"):result.guide_progress=empty_guide_progress() if result.map_profile==WorldMapDB.FIRST_REGION_A else {}
 if not result.has("outpost_states"):result.outpost_states={}
 if not result.has("npc_facilities"):result.npc_facilities=NpcFuelFacility.empty() if result.map_profile==WorldMapDB.FIRST_REGION_A else {}
 if not result.has("region_completion"):result.region_completion=FirstRegionCompletion.empty() if result.map_profile==WorldMapDB.FIRST_REGION_A else {}
 if not result.has("site_stores"):result.site_stores=first_region_stores() if result.map_profile==WorldMapDB.FIRST_REGION_A else {}
 if not result.has("next_greenway_salvage_id"):
  # Absent extension only. Never repair a missing reference in a new save.
  result.next_greenway_salvage_id=""
  if result.map_profile==WorldMapDB.FIRST_REGION_A and result.get("locations") is Dictionary and result.locations.get(SALVAGE_LOCATION) is Dictionary and _salvage_counter_valid(result):
   var id:="entity_%d" % result.next_id
   result.locations[SALVAGE_LOCATION][id]=_salvage_row(id)
   result.next_greenway_salvage_id=id;result.next_id+=1
 return result
static func _salvage_counter_valid(d:Dictionary) -> bool:
 if not d.get("next_id") is int or d.next_id<0:return false
 for rows in d.locations.values():
  if not rows is Dictionary:return false
  for id in rows:
   if not id is String or not id.begins_with("entity_") or not id.trim_prefix("entity_").is_valid_int():return false
   var n:=int(id.trim_prefix("entity_"))
   if n<0 or n>=d.next_id:return false
 return true
static func _normalize_first_region_state(state: Variant) -> Variant:
 if not state is Dictionary:return state
 if state.size()==2 and state.get("roads") is Dictionary and state.get("lots") is Dictionary:
  var migrated:Dictionary=state.duplicate(true)
  migrated["mines"]={"c_quarry":{"cart_shortcut_cleared":false}}
  return migrated
 return state
static func first_region_state_valid(state: Variant,stores: Variant) -> bool:
 if not state is Dictionary or not stores is Dictionary or state.size()!=3 or not state.get("roads") is Dictionary or not state.get("lots") is Dictionary or not state.get("mines") is Dictionary:return false
 if state.roads.size()!=2 or state.lots.size()!=2 or not state.roads.get("ab") is Dictionary or not state.roads.get("bd") is Dictionary:return false
 if state.mines.size()!=1 or not state.mines.get("c_quarry") is Dictionary or state.mines.c_quarry.size()!=1 or not state.mines.c_quarry.get("cart_shortcut_cleared") is bool:return false
 # B/D以外の不可視在庫を保存から受け入れない。地点別在庫はこの2地点だけで、
 # 未実装地点や削除済み地点に物資を隠せないよう台帳のキー集合も厳密に見る。
 if stores.size()!=REGION_A_BUILD.size():return false
 if not state.roads.ab.get("graded") is bool or not state.roads.bd.get("cleared") is bool:return false
 for site in REGION_A_BUILD:
  if state.lots.get(site) not in ["wild",String(REGION_A_BUILD[site].lot)]:return false
  if not stores.get(site) is Dictionary or not SaveGame.counts(stores[site]):return false
  if state.lots[site]=="wild" and not stores[site].is_empty():return false
  var total:=0
  for item in stores[site]:total+=int(stores[site][item])
  if total>int(REGION_A_BUILD[site].capacity):return false
 return true
static func empty_guide_progress() -> Dictionary:return {"version":1,"completed":{}}
static func guide_progress_valid(progress:Variant,first:bool) -> bool:
 if not progress is Dictionary:return false
 if not first:return progress.is_empty()
 if progress.size()!=2 or typeof(progress.get("version"))!=TYPE_INT or progress.version!=1 or not progress.get("completed") is Dictionary:return false
 for event in progress.completed:
  if not GUIDE_EVENT_LABELS.has(event) or not progress.completed[event] is bool or not progress.completed[event]:return false
 return not progress.completed.has("returned_a") or progress.completed.has("quarry_returned")
func record_guide_event(event:String) -> bool:
 if not first_region() or not active or game.game_over or not GUIDE_EVENT_LABELS.has(event):return false
 if event=="returned_a" and not guide_progress.completed.has("quarry_returned"):return false
 if guide_progress.completed.has(event):return false
 guide_progress.completed[event]=true
 return true
func record_material_delivery(item:int,amount:int,source:String) -> void:
 if amount<=0 or source!=Inventory.SOURCE_ENVIRONMENT:return
 if item==GameData.Item.WOOD:record_guide_event("wood_gathered")
 elif item==GameData.Item.STONE:record_guide_event("stone_gathered")
func record_quarry_return(cargo:Dictionary) -> void:
 var positive:=false
 for item in cargo:
  if int(cargo[item])>0:
   positive=true
   record_material_delivery(int(item),int(cargo[item]),Inventory.SOURCE_ENVIRONMENT)
 if positive:record_guide_event("quarry_returned")
func record_recipe_completed(recipe:Dictionary) -> void:
 match recipe.get("id",""):
  "tool_wood_pick":record_guide_event("tool_crafted")
  "repair_stone":record_guide_event("repair_crafted")
  "haul_frame":record_guide_event("frame_crafted")

static func outpost_states_valid(states: Variant,crew_count: int) -> bool:
 if not states is Dictionary:return false
 if states.is_empty():return true
 if states.size()!=1 or not states.get("c_quarry") is Dictionary:return false
 var row:Dictionary=states.c_quarry
 if row.size()!=2 or not row.get("enemies") is Dictionary or not row.get("cleared") is bool:return false
 if row.enemies.size()!=C_OUTPOST_LAYOUT.size():return false
 var all_dead:=true
 var max_hp:float=float(EventDB.ENEMIES[C_OUTPOST_KIND].hp)
 var keys:=["id","kind","lane","home_x","home_y","x","y","hp","max_hp","attack_left","target","engager","dead"]
 for definition in C_OUTPOST_LAYOUT:
  if not row.enemies.get(definition.id) is Dictionary:return false
  var enemy:Dictionary=row.enemies[definition.id]
  if enemy.size()!=keys.size():return false
  for key in keys:
   if not enemy.has(key):return false
  if enemy.id!=definition.id or enemy.kind!=C_OUTPOST_KIND or enemy.lane!=definition.lane:return false
  for key in ["home_x","home_y","x","y","hp","max_hp","attack_left"]:
   if typeof(enemy[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(enemy[key])):return false
  if enemy.home_x!=definition.position.x or enemy.home_y!=definition.position.y or enemy.max_hp!=max_hp:return false
  if enemy.hp<0 or enemy.hp>max_hp or not enemy.dead is bool or enemy.dead!=(enemy.hp==0):return false
  for key in ["target","engager"]:
   if not enemy[key] is String:return false
   if enemy[key]!="":
    var id:String=enemy[key]
    if not id.begins_with("worker:") or not id.trim_prefix("worker:").is_valid_int():return false
    var index:=int(id.trim_prefix("worker:"))
    if index<0 or index>=crew_count or id!="worker:"+str(index):return false
  all_dead=all_dead and enemy.dead
 return row.cleared==all_dead
static func respawn_reservation_valid(reservation: Variant, all_locations: Dictionary) -> bool:
 if reservation is Dictionary and reservation.is_empty(): return true
 if not reservation is Dictionary or reservation.size()!=5:return false
 if reservation.get("mission")!=RESPAWN_MISSION or reservation.get("location")!=RESPAWN_LOCATION or not reservation.get("claim") is int or reservation.claim<1:return false
 for key in ["vein_id","creature_id"]:
  if not reservation.get(key) is String or not reservation[key].begins_with("entity_"):return false
 var site:Variant=all_locations.get(RESPAWN_LOCATION,{})
 if not site is Dictionary or not site.has(reservation.vein_id) or not site.has(reservation.creature_id):return false
 var vein:Dictionary=site[reservation.vein_id]
 var creature:Dictionary=site[reservation.creature_id]
 return vein.get("type")=="gather" and vein.get("data",{}).get("kind")=="vein" and vein.data.get("item")==GameData.Item.IRON_ORE and creature.get("type")=="creature" and creature.get("data",{}).get("species")=="hare"
static func valid(d, g) -> bool:
 if not d is Dictionary:return false
 d=normalized(d)
 if not SaveGame.shape(d,g.world,FIELDS): return false
 if d.resource_regeneration_version not in [0,1]:return false
 if d.map_profile not in [WorldMapDB.DESERT,WorldMapDB.FIRST_REGION_A] or d.map_profile!=g.world.map_profile:return false
 if not outpost_states_valid(d.outpost_states,g.workers.size()):return false
 if not guide_progress_valid(d.guide_progress,d.map_profile==WorldMapDB.FIRST_REGION_A):return false
 if not NpcFuelFacility.valid(d.npc_facilities,d.map_profile==WorldMapDB.FIRST_REGION_A):return false
 if not FirstRegionCompletion.valid(d.region_completion,d.region_state,d.map_profile==WorldMapDB.FIRST_REGION_A,g.workers.size()):return false
 if d.map_profile==WorldMapDB.FIRST_REGION_A:
  if not first_region_state_valid(d.region_state,d.site_stores) or not d.respawn_reservation.is_empty():return false
 elif not d.region_state.is_empty() or not d.site_stores.is_empty() or not d.outpost_states.is_empty():return false
 var max_progress:=WorldMapDB.road_length(d.road,d.map_profile,d.region_state) if WorldMapDB.roads(d.map_profile).has(d.road) else WorldMapDB.LENGTH
 if not WorldMapDB.region_accessible(d.region,d.map_profile,d.region_state,d.region_completion) or d.direction not in [-1,1] or d.next_id<0 or d.progress<0 or d.progress>max_progress: return false
 if d.phase not in ["stopped","departing","travel","arriving","turning","legacy_recall"]: return false
 if d.phase=="legacy_recall" and d.active: return false
 if d.map_profile==WorldMapDB.FIRST_REGION_A and d.phase=="legacy_recall":return false
 if d.phase in ["departing","travel","arriving","turning"]:
  if not WorldMapDB.public_road(d.road,d.map_profile,d.region_state,d.region_completion) or WorldMapDB.road_between(d.origin,d.destination,d.map_profile)!=d.road: return false
 var ids:={}
 for location in d.locations:
  if not location is String: return false
  if location.begins_with("road:"):
   if not WorldMapDB.public_road(location.trim_prefix("road:"),d.map_profile,d.region_state,d.region_completion): return false
  elif location.begins_with("region:"):
   if not WorldMapDB.region_accessible(location.trim_prefix("region:"),d.map_profile,d.region_state,d.region_completion): return false
  else: return false
  if not d.locations[location] is Dictionary: return false
  for id in d.locations[location]:
   if not id is String or not id.begins_with("entity_") or not id.trim_prefix("entity_").is_valid_int() or int(id.trim_prefix("entity_"))<0 or int(id.trim_prefix("entity_"))>=d.next_id or ids.has(id): return false
   ids[id]=true
   var row=d.locations[location][id]
   if not id is String or not row is Dictionary or not row.get("data") is Dictionary or not row.get("spent") is bool or typeof(row.get("anchor")) not in [TYPE_FLOAT,TYPE_INT]: return false
   for field in ["return_at","respawn_at","home_anchor"]:
    if row.has(field) and (typeof(row[field]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(row[field]))):return false
   if row.has("return_at") and row.return_at<0:return false
   if row.has("respawn_at") and row.respawn_at<0:return false
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
   if ResourceRegeneration.eligible(row):
    if d.resource_regeneration_version==1 and (not ResourceRegeneration.valid(row.get("regeneration"),int(row.data.remaining),INF) or row.regeneration.capacity!=row.data.max_amount):return false
   elif row.has("regeneration"):return false
   if row.type=="gather" and (not GatherDB.POINTS.has(row.data.kind) or row.data.remaining<0 or row.data.remaining>row.data.max_amount or row.data.work<0): return false
   if row.type in ["resource","gather"] and row.data.item not in GameData.Item.values(): return false
   if row.type=="creature" and not GameData.CREATURES.has(row.data.species): return false
   if row.type=="enemy" and not EventDB.ENEMIES.has(row.data.kind): return false
 if not respawn_reservation_valid(d.respawn_reservation,d.locations): return false
 var salvage:String=d.next_greenway_salvage_id
 if d.map_profile!=WorldMapDB.FIRST_REGION_A or not d.locations.has(SALVAGE_LOCATION):
  if salvage!="":return false
 else:
  var row:Dictionary=d.locations[SALVAGE_LOCATION].get(salvage,{})
  if salvage=="" or row.is_empty() or row.type!="resource" or row.data.item!=GameData.Item.STORAGE_BOX or row.data.species!="":return false
  if row.has("regeneration") or row.has("respawn_at") or row.has("return_at"):return false
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
