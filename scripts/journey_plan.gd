class_name JourneyPlan
extends RefCounted
## 地域の状態機械はWorldTripに任せ、残り経路・停車意思だけを保持する。
const NOTICE_SECONDS := 10.0 # 試作。敵の予告ではなく、既知地点への接近案内。
const FIELDS := ["remaining","stops","confirm_each","notified","notice","notice_count","last_arrival"]
var game
var remaining: Array = []
var stops: Array = []
var confirm_each := false
var notified := false
var notice := ""
var notice_count := 0
var last_arrival := ""
func setup(g) -> void:game=g
func clear() -> void:
 remaining.clear();stops.clear();notified=false;notice=""
func anchor() -> String:
 return game.world.destination if game.world.phase in ["departing","travel","arriving"] else game.world.region
func plan(path:Array,reservations:Array=[]) -> bool:
 var w=game.world
 if not w.active or game.game_over or game.quarry.state!="road" or w.phase not in ["stopped","departing","travel","arriving"]:return false
 if not valid_path(anchor(),path) or path.is_empty():return false
 for id in reservations:
  if id not in path and id!=w.destination:return false
 var next:Array=path.duplicate()
 if w.phase!="stopped":next.push_front(w.destination)
 else:
  if not w.request(next[0]):return false
 remaining=next;stops=reservations.duplicate();last_arrival=""
 if w.phase=="departing" and game.world.progress==0.0:notified=false;notice=""
 return true
func resume() -> bool:
 if remaining.is_empty() or game.world.phase!="stopped" or hold_reason()!="":return false
 return game.world.request(remaining[0],true)
func cancel_route() -> void:
 remaining=[game.world.destination] if game.world.phase in ["departing","travel","arriving"] else []
 stops.clear();notice=""
func set_stop(id:String,enabled:bool) -> bool:
 if id not in remaining:return false
 if enabled and id not in stops:stops.append(id)
 if not enabled:stops.erase(id)
 if id==notice:notice=""
 return true
func hold_reason() -> String:
 if game.target_speed<=0:return "手動停車中（速度を戻してから再開）"
 if game.operations.stance=="recall":return "呼戻し方針を維持中"
 if game.director.speed_mult()<=0:return "天候への停止対応中"
 if game.workers.any(func(w):return w.ai.retreating or w.ai.danger_hold):return "仲間の撤退・危険待機を維持中"
 return game.world.ready_reason()
func leg_started() -> void:
 notified=false;notice=""
func tick(delta:float) -> void:
 var w=game.world
 if w.phase!="travel" or remaining.size()<2 or notified:return
 var speed:float=game.scroll_speed
 if speed<=0:return
 var left:float=WorldMapDB.LENGTH-w.progress if w.direction==1 else w.progress
 if left/speed<=NOTICE_SECONDS+delta:
  notified=true;notice_count+=1
  if w.destination not in stops and not confirm_each:notice=w.destination
func arrived() -> void:
 var w=game.world
 notice=""
 if remaining.is_empty():return
 var reached:String=remaining.pop_front()
 var stop_here:bool=remaining.is_empty() or reached in stops or confirm_each or hold_reason()!=""
 stops.erase(reached)
 if stop_here:
  last_arrival="停車："+WorldMapDB.name_of(reached)
  return
 last_arrival="通過："+WorldMapDB.name_of(reached)
 if w.request(remaining[0],true):w.start_leg()
func snapshot() -> Dictionary:return SaveGame.fields(self,FIELDS)
func restore(d:Dictionary) -> void:
 var defaults:=JourneyPlan.new()
 SaveGame.put(self,SaveGame.fields(defaults,FIELDS) if d.is_empty() else d,FIELDS)
static func valid_path(start:String,path:Array) -> bool:
 var seen:Array=[start]
 for id in path:
  if not id is String or id in seen or not WorldMapDB.public_road(WorldMapDB.road_between(start,id)):return false
  seen.append(id);start=id
 return path.size()<=WorldMapDB.REGIONS.size()
static func valid(d,world:Dictionary) -> bool:
 if not d is Dictionary:return false
 if d.is_empty():return true
 for key in FIELDS:
  if not d.has(key):return false
 if not d.remaining is Array or not d.stops is Array or not d.confirm_each is bool or not d.notified is bool or not d.notice is String or not d.last_arrival is String or not d.notice_count is int or d.notice_count<0:return false
 var path:Array=d.remaining.duplicate()
 var start:String=world.region
 if not path.is_empty() and world.phase in ["travel","departing","arriving"]:
  if path.pop_front()!=world.destination:return false
  start=world.destination
 elif not path.is_empty() and world.phase!="stopped":return false
 if not valid_path(start,path):return false
 var seen:Array=[]
 for id in d.stops:
  if not id is String or id not in d.remaining or id in seen:return false
  seen.append(id)
 if d.notice!="" and (world.phase not in ["travel","arriving"] or d.remaining.size()<2 or d.notice!=world.destination or not d.notified):return false
 return true
