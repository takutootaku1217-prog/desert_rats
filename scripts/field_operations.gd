class_name FieldOperations
extends RefCounted
## 屋外方針と一往復の結果。倉庫間移動を取得に数えない。
const NEAR_DISTANCE := 240.0
const NOTICE_DISTANCE := 180.0
const RECOVER_HP := 75.0
const RETRY_SECONDS := 15.0
const FIELDS := ["stance","outing","delivered","baseline","last_report","fuel_spent","outside_seen"]
var game
var stance := "normal"
var outing := false
var outside_seen := false
var delivered := {}
var baseline := {}
var last_report := {}
var fuel_spent := 0.0
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
func tick() -> void:
 if outing and game.workers.any(func(w):return w.floor_i==0 and not w.away):outside_seen=true
 if outing and outside_seen and returned_count()==game.workers.size():
  last_report={"items":delivered.duplicate(),"seconds":game.director.elapsed-baseline.time,"food":game.total_eaten-baseline.food,"fuel":fuel_spent-baseline.fuel,"refuel":game.base.total_refuel-baseline.refuel,"repair":game.base.total_repair-baseline.repair}
  outing=false
func can_depart(w,position: Vector2) -> bool:
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
 return "%s　帰還 %d/%d人・危険待機%d人" % [{"normal":"通常","alert":"警戒：近場優先","recall":"撤退：呼戻し中"}[stance],returned_count(),game.workers.size(),game.workers.filter(func(w):return w.ai.danger_hold).size()]
func result_text() -> String:
 if last_report.is_empty():return "帰還結果：まだありません"
 var parts:=[]
 for it in last_report.items:parts.append("%s%d"%[ItemDB.name_of(it),last_report.items[it]])
 return "直近 %.0f秒／持帰り %s\n消費 食料%d・燃料%.1f・修理板%d（燃料補給%d回）" % [last_report.seconds,"、".join(parts) if not parts.is_empty() else "なし",last_report.food,last_report.fuel,last_report.repair,last_report.refuel]
