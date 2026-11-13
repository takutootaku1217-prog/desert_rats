class_name FieldOperations
extends RefCounted
const TravelLanePresentation = preload("res://scripts/travel_lane_presentation.gd")
## 屋外方針と一往復の結果。倉庫間移動を取得に数えない。
const NEAR_DISTANCE := 240.0
const NOTICE_DISTANCE := 180.0
## 採用済みの一次循環: HP30%以下では、本人を新しい仕事へ出さず帰還・回復を優先する。
const RETREAT_HP := 30.0
const RECOVER_HP := 75.0
const RETRY_SECONDS := 15.0
## 戦闘不能から手で救助するまでの猶予。不可逆な喪失・費用は未決のため、これは
## 死亡タイマーではない。
const RESCUE_SECONDS := 90.0
## 暫定採用（2026-10-23）: 救助期限を過ぎた仲間は、すぐ通常AIへ戻さず
## このゲーム内秒数だけ行動不能にする。後日のバランス変更ではこの値だけを
## 差し替える。保存済みの残秒は維持するため、進行中の保存を再計算しない。
const POST_EXPIRY_INCAPACITATION_SECONDS := 600.0
const RESCUE_CASE_FIELDS := ["target","carrier","phase","left","resume_return","resume_manual_job","deferred_return"]
const RESCUE_PHASES := ["waiting","assigned","carried","recovering","incapacitated"]
const FIELDS := ["stance","outing","delivered","baseline","last_report","fuel_spent","outside_seen","rescue_cases"]
var game
var stance := "normal"
var outing := false
var outside_seen := false
var delivered := {}
var baseline := {}
var last_report := {}
var fuel_spent := 0.0
## key = target worker index (String), value contains only serializable worker indexes.
## Object references intentionally remain outside saves and are rebuilt from these indexes.
var rescue_cases := {}
func setup(g) -> void:
 game=g
 game.storage.inventory.item_added.connect(_received)
func set_stance(value: String) -> bool:
 if value not in ["normal","alert","recall"] or game.game_over: return false
 stance=value
 for w in game.workers:
  if value in ["alert","recall"] and w.ai.state in [CharacterAI.State.COMBAT_MOVE,CharacterAI.State.COMBAT]:w.ai.begin_retreat()
  if value=="normal" and w.hp>=RECOVER_HP:w.ai.danger_hold=false
  if w.ai.state==CharacterAI.State.RETURN_BASE and w.floor_i!=0: w.ai._set_state(CharacterAI.State.SEARCH)
 return true
func start_outing() -> void:
 if outing:return
 outing=true;outside_seen=false;delivered={}
 baseline={"time":game.director.elapsed,"food":game.total_eaten,"fuel":fuel_spent,"refuel":game.base.total_refuel,"repair":game.base.total_repair}
func _received(item: int,n: int,source: String) -> void:
 if outing and source in [Inventory.SOURCE_ENVIRONMENT,Inventory.SOURCE_HUNT,Inventory.SOURCE_ENEMY_DROP,Inventory.SOURCE_EXPEDITION]:
  delivered[item]=int(delivered.get(item,0))+n
func returned(w) -> bool:
 return not w.away and w.floor_i!=0 and w._climb_dest==null and w.carrying<0 and w.carry_bonus.is_empty()
func returned_count() -> int:
 return game.workers.filter(func(w):return returned(w)).size()
## All rescue state changes live here rather than in the town lost-parcel recovery flow.
## That keeps a person rescue independent from cargo recovery and lets SaveGame validate it as
## one compact state machine.
func tick(delta := 0.0) -> void:
 # Main._process does not run while the game is paused. Keep this guard as well
 # so direct callers cannot advance a rescue or long-incapacitation timer during
 # a UI pause.
 if game != null and game.get_tree() != null and game.get_tree().paused:
  return
 _tick_low_hp_retreat()
 _tick_rescue_cases(delta)
 if outing and game.workers.any(func(w):return w.floor_i==0 and not w.away):outside_seen=true
 if outing and outside_seen and returned_count()==game.workers.size():
  last_report={"items":delivered.duplicate(),"seconds":game.director.elapsed-baseline.time,"food":game.total_eaten-baseline.food,"fuel":fuel_spent-baseline.fuel,"refuel":game.base.total_refuel-baseline.refuel,"repair":game.base.total_repair-baseline.repair}
  outing=false


func _worker_index(w) -> int:
 return game.workers.find(w) if game != null else -1


func _case_key(index: int) -> String:
 return str(index)


func _case_for_index(index: int) -> Dictionary:
 if index < 0:
  return {}
 var row = rescue_cases.get(_case_key(index), {})
 return row.duplicate(true) if row is Dictionary else {}


func rescue_case_for(w) -> Dictionary:
 return _case_for_index(_worker_index(w))


func rescue_phase_for(w) -> String:
 return String(rescue_case_for(w).get("phase", ""))


func _case_key_for_carrier(w) -> String:
 var index := _worker_index(w)
 if index < 0:
  return ""
 for key in rescue_cases:
  var row = rescue_cases[key]
  if row is Dictionary and int(row.get("carrier", -1)) == index:
   return String(key)
 return ""


func rescue_carrier_phase(w) -> String:
 var key := _case_key_for_carrier(w)
 return String(rescue_cases[key].get("phase", "")) if not key.is_empty() else ""


func rescue_target_for(carrier):
 var key := _case_key_for_carrier(carrier)
 if key.is_empty():
  return null
 var target_i := int(rescue_cases[key].get("target", -1))
 return game.workers[target_i] if target_i >= 0 and target_i < game.workers.size() else null


func rescue_carried_by(carrier) -> bool:
 return rescue_carrier_phase(carrier) == "carried"


## This is deliberately only the rescue deadline.  The main simulation never
## pauses its world clock while a teammate is being carried.
func rescue_deadline_paused() -> bool:
 for row in rescue_cases.values():
  if row is Dictionary and row.get("phase", "") == "carried":
   return true
 return false


func blocks_natural_down_recovery(w) -> bool:
 var phase := rescue_phase_for(w)
 return phase in ["waiting", "assigned", "carried", "incapacitated"]


## Current cases block natural recovery until their own transition completes.
## Retain cleanup for a malformed legacy live row so a standing worker never
## retains stale rescue state.
func on_natural_recovery(w) -> void:
 var index := _worker_index(w)
 if index < 0:
  return
 var key := _case_key(index)
 var row = rescue_cases.get(key, {})
 if row is Dictionary and row.get("phase", "") in ["expired", "incapacitated"]:
  rescue_cases.erase(key)


## Called before CharacterAI drops the normal work state, so an explicit return or repair
## request can be resumed after the adopted 75% recovery gate.
func on_worker_down(w) -> void:
 if game == null:
  return
 _interrupt_carrier(w)
 var index := _worker_index(w)
 if index < 0 or not _case_for_index(index).is_empty():
  return
 rescue_cases[_case_key(index)] = {
  "target": index,
  "carrier": -1,
  "phase": "waiting",
  "left": RESCUE_SECONDS,
  "resume_return": bool(w.ai.return_request),
  "resume_manual_job": int(w.ai.manual_job),
  "deferred_return": false,
 }


func rescue_reason(target, carrier) -> String:
 if target == null or carrier == null:
  return "救助対象または担当者が見つかりません"
 var target_i := _worker_index(target)
 var carrier_i := _worker_index(carrier)
 var row := _case_for_index(target_i)
 if row.is_empty() or row.get("phase", "") != "waiting" or not target.down:
  return "この仲間は救助を待っていません"
 if target_i == carrier_i:
  return "戦闘不能の仲間自身は救助担当にできません"
 if carrier.away or carrier.down:
  return "戦闘不能または遠征中の仲間は救助担当にできません"
 if carrier.carrying >= 0 or not carrier.carry_bonus.is_empty() or game.town.recovery_carried_by(carrier):
  return "荷物を運搬中の仲間は、先に安全な区切りまで届ける必要があります"
 if not _case_key_for_carrier(carrier).is_empty():
  return "その仲間はすでに別の救助を担当しています"
 return ""


## 手動で対象と救助者を一人ずつ選ぶ。自動割当ては未採用のままにする。
func request_rescue(target, carrier) -> bool:
 var reason := rescue_reason(target, carrier)
 if not reason.is_empty():
  return false
 var key := _case_key(_worker_index(target))
 var row: Dictionary = rescue_cases[key]
 row["carrier"] = _worker_index(carrier)
 row["phase"] = "assigned"
 rescue_cases[key] = row
 carrier.ai.begin_rescue()
 return true


## A return order issued while carrying is retained and applied only after delivery.
## Other work commands keep their existing safe-boundary behavior; this narrowly avoids
## inventing a general-purpose command queue for the first rescue pilot.
func defer_return_for_carrier(carrier) -> bool:
 var key := _case_key_for_carrier(carrier)
 if key.is_empty() or rescue_cases[key].get("phase", "") not in ["assigned", "carried"]:
  return false
 var row: Dictionary = rescue_cases[key]
 row["deferred_return"] = true
 rescue_cases[key] = row
 return true


func pickup_rescue(carrier) -> bool:
 var key := _case_key_for_carrier(carrier)
 if key.is_empty():
  return false
 var row: Dictionary = rescue_cases[key]
 var target = rescue_target_for(carrier)
 if row.get("phase", "") != "assigned" or target == null or not target.down:
  return false
 row["phase"] = "carried"
 rescue_cases[key] = row
 follow_carrier(carrier)
 return true


func follow_carrier(carrier) -> void:
 var target = rescue_target_for(carrier)
 if target == null or not rescue_carried_by(carrier):
  return
 # The target remains an actual downed Worker, not an invisible inventory item.
 target.position = carrier.position + Vector2(0, -14)
 target.target = target.position
 target.floor_i = carrier.floor_i
 target._climb_dest = null


func deliver_rescue(carrier) -> bool:
 var key := _case_key_for_carrier(carrier)
 if key.is_empty():
  return false
 var row: Dictionary = rescue_cases[key]
 var target = rescue_target_for(carrier)
 if row.get("phase", "") != "carried" or target == null:
  return false
 target.position = game.storage.access_point() + target.slot_offset
 target.target = target.position
 target.floor_i = GameData.floor_of_y(target.position.y)
 target.down = false
 target.hp = maxf(target.hp, CrewStatusDB.HP_REVIVE_AT)
 target.ai._set_state(CharacterAI.State.RESCUE_RECOVER)
 row["carrier"] = -1
 row["phase"] = "recovering"
 rescue_cases[key] = row
 if bool(row.get("deferred_return", false)):
  carrier.ai.return_request = true
 return true


func finish_rescue_recovery(target) -> bool:
 var index := _worker_index(target)
 var key := _case_key(index)
 var row := _case_for_index(index)
 if row.is_empty() or row.get("phase", "") != "recovering" or target.hp < RECOVER_HP:
  return false
 target.ai.return_request = bool(row.get("resume_return", false))
 target.ai.manual_job = int(row.get("resume_manual_job", -1))
 rescue_cases.erase(key)
 # This can be called by the Main rescue ledger before the Worker's own AI
 # frame. Clear the dedicated recovery state here as well, so that frame sees
 # the restored instruction rather than an orphaned RESCUE_RECOVER state.
 target.ai._set_state(CharacterAI.State.SEARCH)
 return true


## The temporary post-expiry state reuses the existing safe DOWN -> SEARCH
## transition: HP is restored only to the established wake threshold, and the
## next AI frame leaves DOWN in the same way as ordinary natural recovery.
func finish_post_expiry_incapacitation(target) -> bool:
 var index := _worker_index(target)
 var key := _case_key(index)
 var row := _case_for_index(index)
 if row.is_empty() or row.get("phase", "") != "incapacitated" or not target.down:
  return false
 target.hp = maxf(target.hp, CrewStatusDB.HP_REVIVE_AT)
 target.down = false
 rescue_cases.erase(key)
 return true


func _interrupt_carrier(carrier) -> void:
 var key := _case_key_for_carrier(carrier)
 if key.is_empty():
  return
 var row: Dictionary = rescue_cases[key]
 var target = rescue_target_for(carrier)
 if target != null:
  target.position = carrier.position
  target.target = target.position
  target.floor_i = carrier.floor_i
 row["carrier"] = -1
 row["phase"] = "waiting"
 rescue_cases[key] = row


func _tick_low_hp_retreat() -> void:
 for w in game.workers:
  if w.away or w.down or rescue_carrier_phase(w) in ["assigned", "carried"]:
   continue
  if w.hp <= RETREAT_HP and not w.ai.low_hp_retreat:
   w.ai.begin_low_hp_retreat()
  elif w.ai.low_hp_retreat and w.floor_i != 0 and w._climb_dest == null and w.hp >= RECOVER_HP:
   w.ai.finish_low_hp_retreat()


func _tick_rescue_cases(delta: float) -> void:
 for key in rescue_cases.keys().duplicate():
  var row = rescue_cases.get(key, {})
  if not row is Dictionary:
   rescue_cases.erase(key)
   continue
  var target_i := int(row.get("target", -1))
  if target_i < 0 or target_i >= game.workers.size():
   rescue_cases.erase(key)
   continue
  var target = game.workers[target_i]
  var phase := String(row.get("phase", ""))
  if phase in ["waiting", "assigned"]:
   if not target.down:
    rescue_cases.erase(key)
    continue
   var carrier_i := int(row.get("carrier", -1))
   if carrier_i >= 0 and (carrier_i >= game.workers.size() or game.workers[carrier_i].down or game.workers[carrier_i].away):
    row["carrier"] = -1
    row["phase"] = "waiting"
   row["left"] = maxf(0.0, float(row.get("left", RESCUE_SECONDS)) - maxf(0.0, delta))
   if row["left"] <= 0.0:
    # Latest temporary direction: no loss, fee, or facility requirement; retain
    # the person as DOWN for a configurable long recovery period instead.
    var expiry_carrier_i := int(row.get("carrier", -1))
    if expiry_carrier_i >= 0 and expiry_carrier_i < game.workers.size():
     var expiry_carrier = game.workers[expiry_carrier_i]
     if not expiry_carrier.down and not expiry_carrier.away:
      expiry_carrier.ai._set_state(CharacterAI.State.SEARCH)
    row["carrier"] = -1
    row["phase"] = "incapacitated"
    row["left"] = POST_EXPIRY_INCAPACITATION_SECONDS
   rescue_cases[key] = row
  elif phase == "carried":
   var carrier_i := int(row.get("carrier", -1))
   if carrier_i < 0 or carrier_i >= game.workers.size() or game.workers[carrier_i].down or game.workers[carrier_i].away:
    row["carrier"] = -1
    row["phase"] = "waiting"
    rescue_cases[key] = row
  elif phase == "recovering":
   if target.hp >= RECOVER_HP:
    finish_rescue_recovery(target)
  elif phase == "incapacitated":
   if not target.down:
    rescue_cases.erase(key)
    continue
   row["left"] = maxf(0.0, float(row.get("left", POST_EXPIRY_INCAPACITATION_SECONDS)) - maxf(0.0, delta))
   if row["left"] <= 0.0:
    finish_post_expiry_incapacitation(target)
   else:
    rescue_cases[key] = row


func restore_rescue_state() -> void:
 for key in rescue_cases.keys().duplicate():
  var row = rescue_cases[key]
  var target_i := int(row.get("target", -1))
  if target_i < 0 or target_i >= game.workers.size():
   rescue_cases.erase(key)
   continue
  var target = game.workers[target_i]
  match String(row.get("phase", "")):
   "waiting", "expired", "incapacitated":
    target.down = true
    target.ai._set_state(CharacterAI.State.DOWN)
   "assigned":
    target.down = true
    target.ai._set_state(CharacterAI.State.DOWN)
    var carrier_i := int(row.get("carrier", -1))
    if carrier_i >= 0 and carrier_i < game.workers.size():
     game.workers[carrier_i].ai._set_state(CharacterAI.State.RESCUE_MOVE)
   "carried":
    target.down = true
    target.ai._set_state(CharacterAI.State.DOWN)
    var carrier_i := int(row.get("carrier", -1))
    if carrier_i >= 0 and carrier_i < game.workers.size():
     game.workers[carrier_i].ai._set_state(CharacterAI.State.RESCUE_RETURN)
     follow_carrier(game.workers[carrier_i])
   "recovering":
    target.down = false
    target.ai._set_state(CharacterAI.State.RESCUE_RECOVER)


static func rescue_cases_valid(cases, worker_count: int) -> bool:
 if not cases is Dictionary:
  return false
 var targets := []
 var carriers := []
 for key in cases:
  if not key is String or not String(key).is_valid_int() or not cases[key] is Dictionary:
   return false
  var row: Dictionary = cases[key]
  if row.size() != RESCUE_CASE_FIELDS.size():
   return false
  for field in RESCUE_CASE_FIELDS:
   if not row.has(field):
    return false
  if not row.target is int or not row.carrier is int or not row.phase is String or typeof(row.left) not in [TYPE_FLOAT, TYPE_INT] or not row.resume_return is bool or not row.resume_manual_job is int or not row.deferred_return is bool:
   return false
  if int(key) != row.target or row.target < 0 or row.target >= worker_count or row.target in targets:
   return false
  # A saved incapacitation countdown keeps its exact remaining value even if a
  # later balance pass changes the default for newly-expired cases.  Other
  # rescue phases are bounded by their fixed 90-second window.
  if row.carrier < -1 or row.carrier >= worker_count or row.carrier == row.target or row.phase not in RESCUE_PHASES or not is_finite(float(row.left)) or row.left < 0.0 or (row.phase != "incapacitated" and row.left > RESCUE_SECONDS) or row.resume_manual_job not in [-1, GameData.Job.REPAIR]:
   return false
  if row.phase in ["assigned", "carried"] and row.carrier < 0:
   return false
  if row.phase in ["waiting", "recovering", "incapacitated"] and row.carrier != -1:
   return false
  if row.carrier >= 0 and row.carrier in carriers:
   return false
  targets.append(row.target)
  if row.carrier >= 0:
   carriers.append(row.carrier)
 return true
func can_depart(w,position: Vector2) -> bool:
 if TravelLanePresentation.blocks_outdoor_work(game):
  return false
 if stance=="recall" or w.ai.retreating or w.ai.danger_hold or game.director.elapsed<w.ai.safe_after:return false
 if stance=="alert" and position.distance_to(GameData.RAMP_FOOT)>NEAR_DISTANCE:return false
 # 自分から見える距離だけ。敵一覧をHUDへ公開しない。
 # 地上の敵は地上の仲間だけを止める。デッキ上の水平移動やスロープへの接近を、垂直距離の銀で不当に禁止しない。
 if w.floor_i==0:
  for e in game.enemies_root.get_children():
   if GameData.floor_of_y(e.position.y)==0 and not e.dead and e.threatens(w) and w.position.distance_to(e.position)<NOTICE_DISTANCE:
    return false
 return true
func status_text() -> String:
 var rescue := ""
 if not rescue_cases.is_empty():
  var carrying := rescue_cases.values().filter(func(row): return row is Dictionary and row.get("phase", "") == "carried").size()
  var waiting := rescue_cases.values().filter(func(row): return row is Dictionary and row.get("phase", "") in ["waiting", "assigned"]).size()
  rescue = "・救助 搬送%d／待機%d" % [carrying, waiting]
 return "%s　帰還 %d/%d人・危険待機%d人%s" % [{"normal":"通常","alert":"警戒：近場優先","recall":"撤退：呼戻し中"}[stance],returned_count(),game.workers.size(),game.workers.filter(func(w):return w.ai.danger_hold).size(),rescue]
func result_text() -> String:
 if last_report.is_empty():return "帰還結果：まだありません"
 var parts:=[]
 for it in last_report.items:parts.append("%s%d"%[ItemDB.name_of(it),last_report.items[it]])
 return "直近 %.0f秒／持帰り %s\n消費 食料%d・燃料%.1f・修理板%d（燃料補給%d回）" % [last_report.seconds,"、".join(parts) if not parts.is_empty() else "なし",last_report.food,last_report.fuel,last_report.repair,last_report.refuel]
