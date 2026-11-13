class_name VehicleHunt
extends RefCounted
## Temporary vehicle-mounted hunting rig. Explicit orders only; no outside worker dispatch.
const RANGE := 460.0
const SHOT_SECONDS := 0.8
const DAMAGE := 8.0
const RECOVERY_SECONDS := 3.0
var game
var cargo: Dictionary = {}
var cargo_species := ""
var cargo_progress := 0.0
var cargo_origin := Vector2.ZERO
var cargo_source := ""
var cooldown := 0.0
var beam_time := 0.0
var beam_to := Vector2.ZERO
var _text := "狩猟依頼なし"
var _stage := "idle"

func setup(g) -> void:
 game = g

func mount() -> Vector2:
 return Vector2(GameData.RAMP_FOOT.x, TravelLanePresentation.travel_ground_y())

func tick(delta: float) -> void:
 if game == null or delta <= 0.0: return
 beam_time = maxf(0.0, beam_time-delta)
 cooldown = maxf(0.0, cooldown-delta)
 if game.game_over or game.base.hp <= 0.0:
  _stage="disabled";_text="車体停止：回収貨物は保持";return
 if not cargo.is_empty():
  _stage="recovering";_text="獲物を車上回収中"
  cargo_progress=minf(RECOVERY_SECONDS,cargo_progress+delta)
  if cargo_progress>=RECOVERY_SECONDS:
   if game.storage.limits_active() and game.storage.current_weight()+game.storage.processing_reserve()>game.storage.max_weight():
    _stage="capacity";_text="収納満杯：車上の獲物を保持";return
   var delivered:=cargo.duplicate(true)
   cargo.clear();cargo_species="";cargo_progress=0.0;cargo_source=""
   # Already-owned cargo changes location, not mass; provenance stays HUNT.
   for item in delivered:game.storage.store_owned(item,int(delivered[item]),Inventory.SOURCE_HUNT)
   game.storage.total_butchered+=1
   _stage="delivered";_text="獲物を収納・解体 → 料理へ"
  return
 if str(game.world.phase)!="travel" or game.scroll_speed<=0.0:
  _stage="stopped";_text="車上狩猟は走行中のみ";return
 if game.operations.stance in ["recall","shelter"]:
  _stage="retreat";_text="帰還・退避中：新しい狩猟を停止";return
 var ordered:=false
 for species in game.hunt_requests:
  if game.hunt_allowed(species):ordered=true
 if not ordered:
  _stage="idle";_text="狩猟依頼なし";return
 _stage="waiting";_text="依頼した生物が射程に入るのを待つ"
 for creature in game.creatures_root.get_children():
  if not is_instance_valid(creature) or creature.is_queued_for_deletion() or creature.dead or not game.hunt_allowed(creature.species):continue
  if creature.position.distance_to(mount())>RANGE:continue
  if creature.hunted_by!=null:continue
  if game.storage.limits_active() and game.storage.set_weight(GameData.CREATURES[creature.species].drops)>game.storage.max_weight()-game.storage.current_weight()-game.storage.processing_reserve():
   _stage="capacity";_text="積載不足：獲物1体分の空きが必要";continue
  _stage="aiming";_text="車上から狩猟中：%s"%creature.display_name()
  if cooldown>0.0:return
  cooldown=SHOT_SECONDS;beam_time=0.18;beam_to=creature.position
  creature.take_damage(DAMAGE)
  if creature.dead:
   var carcass=game.last_carcass
   if is_instance_valid(carcass) and not carcass.is_queued_for_deletion() and carcass.species==creature.species and carcass.position.distance_to(mount())<=RANGE:
    cargo=GameData.CREATURES[creature.species].drops.duplicate(true)
    cargo_species=creature.species;cargo_origin=carcass.position;cargo_progress=0.0;cargo_source=creature.world_id
    game.world.consume(carcass)
    carcass.queue_free()
    _stage="recovering";_text="獲物を車上回収中"
  return

func status() -> Dictionary:
 return {"text":_text,"stage":_stage,"cargo_species":cargo_species,"progress":cargo_progress/RECOVERY_SECONDS,"range":RANGE}

func snapshot() -> Dictionary:
 return {"cargo":cargo.duplicate(true),"species":cargo_species,"progress":cargo_progress,"origin":cargo_origin,"source":cargo_source,"cooldown":cooldown}

static func valid_snapshot(data) -> bool:
 if not data is Dictionary:return false
 if data.is_empty():return true # old saves
 if data.size()!=6:return false
 for k in ["cargo","species","progress","origin","source","cooldown"]:
  if not data.has(k):return false
 if not data.cargo is Dictionary or not data.species is String or not data.source is String or not data.origin is Vector2:return false
 if not data.progress is float or not data.cooldown is float or not is_finite(data.progress) or not is_finite(data.cooldown):return false
 if data.progress<0.0 or data.progress>RECOVERY_SECONDS or data.cooldown<0.0 or data.cooldown>SHOT_SECONDS:return false
 if data.cargo.is_empty():return data.species=="" and data.progress==0.0
 return GameData.CREATURES.has(data.species) and data.cargo==GameData.CREATURES[data.species].drops

func restore(data:Dictionary) -> void:
 cargo=data.get("cargo",{}).duplicate(true);cargo_species=str(data.get("species",""));cargo_progress=float(data.get("progress",0.0))
 cargo_origin=data.get("origin",Vector2.ZERO);cargo_source=str(data.get("source",""));cooldown=float(data.get("cooldown",0.0));beam_time=0.0
