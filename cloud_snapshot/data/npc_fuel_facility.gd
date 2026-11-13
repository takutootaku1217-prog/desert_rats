class_name NpcFuelFacility
extends RefCounted
## Developer-provisional single-facility experiment. Not a finalized world layout
## or economy. Player-owned freight lots and NPC ownership remain independent.
const ID := "d_fuel"
const SITE := "d_yard"
const NAME := "NPC給油所（試作）"
const MATERIALS := {GameData.Item.WOOD:4,GameData.Item.STONE:2}
const CREDITS := 12
static func empty() -> Dictionary:
 return {"version":1,"facilities":{ID:{"restored":false}}}
static func valid(value:Variant,first:bool) -> bool:
 if not value is Dictionary:return false
 if not first:return value.is_empty()
 if value.size()!=2 or typeof(value.get("version"))!=TYPE_INT or value.version!=1:return false
 var facilities:Variant=value.get("facilities")
 if not facilities is Dictionary or facilities.size()!=1 or not facilities.get(ID) is Dictionary:return false
 var row:Dictionary=facilities[ID]
 return row.size()==1 and row.get("restored") is bool
