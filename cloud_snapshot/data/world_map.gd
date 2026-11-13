class_name WorldMapDB
extends RefCounted
## 正本10地域12接続。試作公開は4地域4道路のみ。サービスは未実装。
const REGIONS := {
 "south_oasis":{"name":"オアシスの交易村","creature":"hare","open":true,"pos":Vector2(80,300),"tint":Color("f3ead0"),"points":["tree","rock","vein"],"description":"安全寄りの村。木36・石と少量の鉄鉱石4。有限で再訪補充なし。基本の鉄道具を準備できます。"},
 "east_sands":{"name":"東部砂原","creature":"lizard","open":true,"pos":Vector2(440,300),"tint":Color("f4dba8"),"points":["tree","tree","rock"],"description":"砂丘と道標。枯れ木と、皮・骨を得られるトゲトカゲ。"},
 "central_trade":{"name":"中央交易都市","creature":"hump","open":true,"pos":Vector2(230,110),"tint":Color("e5d7c3"),"points":["tree","rock"],"description":"門と天幕が目印。街道には皮・骨・脂肪を得られるコブ獣。停泊し全員帰還後、拠点メニューから街へ。"},
 "old_mine":{"name":"大鉱山入口","open":true,"pos":Vector2(520,110),"tint":Color("cfcbd1"),"points":[],"description":"危険な鉱山。採取地点に鉄鉱石84。石のハンマーが必要です（木材→木製採掘具→石2＋木材1）。生物は目視して判断してください。"},
 "west_salt":{"name":"白い塩湖","open":false},
 "poison_marsh":{"name":"毒沼と錬金術の廃墟","open":false},
 "ancient_gate":{"name":"古代の大水門","open":false},
 "frozen_highlands":{"name":"氷竜の雪山","open":false},
 "volcano_forge":{"name":"火山と鍛冶の里","open":false},
 "elder_domain":{"name":"古竜の領域","open":false},
}
const ROADS := {
 "01":["south_oasis","east_sands"], "02":["south_oasis","west_salt"],
 "03":["south_oasis","central_trade"], "04":["east_sands","central_trade"],
 "05":["west_salt","central_trade"], "06":["central_trade","old_mine"],
 "07":["central_trade","poison_marsh"], "08":["old_mine","ancient_gate"],
 "09":["poison_marsh","ancient_gate"], "10":["ancient_gate","frozen_highlands"],
 "11":["old_mine","volcano_forge"], "12":["volcano_forge","elder_domain"],
}
## 調整用: 既存鉱床の片道1200×2。速度60なら40秒。最終地理距離ではない。
const LENGTH := QuarryDB.TRAVEL_DISTANCE * 2.0
const ROAD_POINTS := 8 # 同じ8地点を往復で共有。初回だけ既存の残量範囲で決定。

## 今回は既存4地点だけの小さなエリアマップ。世界概観や新地域は追加しない。
const NODE_KIND := {"south_oasis":"village","east_sands":"grove","central_trade":"city","old_mine":"mine"}
const MAP_HINTS := {
 "south_oasis":"オアシスと村。木材・石・少量の鉄鉱石。",
 "east_sands":"砂丘と枯れ木の帯。木材と石を採取。",
 "central_trade":"街道の集まる都市。停泊し、全員帰還後に街へ。",
 "old_mine":"岩山の坑口。鉄鉱石には石のハンマーが必要（木材→木製採掘具→石2＋木材1）。停泊後、採取地点(G)から鉱床へ。",
}

## 同一キャンペーンに次地域の入口だけを接続。地理と距離は暫定。
## 別の砂漠プロフィールや未実装の広域構想とは統合しない。
const FIRST_REGION_A := "first_region_a"
const DESERT := "desert"
const NEXT_REGION_ENTRY := "next_greenway"
const FIRST_REGION_A_REGIONS := {
 "a_start":{"name":"A はじまりの街","open":true,"pos":Vector2(82,292),"tint":Color("bcd0aa"),"points":["tree","tree","rock"],"creature":"hare","description":"緑に呑まれた旧街。最初の燃料・木製採掘具と、木材・石材を既存の採取でまかなえます。"},
 "b_forest":{"name":"B 近郊の森","open":true,"pos":Vector2(255,105),"tint":Color("9fbd8b"),"points":["tree","tree","rock"],"creature":"hare","description":"倒木の多い森。木材・石材を残したまま、空き地を補給/保管場所へ転用できます。"},
 "c_quarry":{"name":"C 古い採石場","open":true,"pos":Vector2(502,112),"tint":Color("b5b6a0"),"points":["rock","rock","vein","tree"],"creature":"hare","description":"崩れかけた採石場。石材と少量の鉄鉱石、木材を採取できます。"},
 "d_yard":{"name":"D 廃貨物ヤード","open":true,"pos":Vector2(592,310),"tint":Color("bc9d82"),"points":["tree","rock","rock"],"creature":"hare","description":"錆びた貨物設備が残る終点。採取を残したまま、貨物受渡し設備を復興できます。"},
 "next_greenway":{"name":"次地域入口・旧緑道","open":true,"pos":Vector2(365,350),"tint":Color("8baea0"),"points":["tree","rock","vein"],"creature":"hare","description":"再接続した貨物道の先。旧設備を緑が覆う次地域の入口です。停車して木材・石材・鉄鉱石を回収し、Dへ戻れます。地域の奥と終幕は未実装です。"},
}
const FIRST_REGION_A_ROADS := {
 "ab":["a_start","b_forest"], "bc":["b_forest","c_quarry"],
 "cd":["c_quarry","d_yard"], "da":["d_yard","a_start"],
 "bd":["b_forest","d_yard"], # 倒木を処理するまで地図上では見えるが通行不可。
 "dn":["d_yard","next_greenway"], # 第1地域突破から導出。独立の開通フラグは保存しない。
}
const FIRST_REGION_A_ROAD_META := {
 "ab":{"length":1200.0,"gradeable":true}, "bc":{"length":1200.0},
 "cd":{"length":1200.0}, "da":{"length":1200.0}, "bd":{"length":840.0,"blocked_by":"fallen_trees"},
 "dn":{"length":1200.0,"blocked_by":"first_region_completion"},
}
const FIRST_REGION_A_NODE_KIND := {"a_start":"village","b_forest":"grove","c_quarry":"mine","d_yard":"yard","next_greenway":"grove"}
## Survival-loop prototype fauna roster.  It remains separate from the map art
## data so the temporary species/quantity pass can be replaced without moving
## regions or changing route rules.
const FIRST_REGION_A_FAUNA := {
 "a_start":["dodo","sand_paca","mossback"],
 "b_forest":["dodo","hare"],
 "c_quarry":["sand_paca","mossback"],
 "d_yard":["dodo","hare"],
 "next_greenway":["hare"],
}
const FIRST_REGION_A_ROAD_FAUNA := ["dodo"]
const FIRST_REGION_A_HINTS := {
 "a_start":"採取：木材・石材。出発と帰還の基準地点。",
 "b_forest":"採取：木材・石材。倒木近道の処理、または補給/保管場所への土地転用を選べます。",
 "c_quarry":"採取：石材・鉄鉱石・木材。A〜D周回の中継地点。",
 "d_yard":"採取：木材・石材。貨物設備を復興すると地点別の受渡し/保管ができます。",
 "next_greenway":"旧設備の収納ボックス1個を回収（再生なし）。空き42を用意→仲間が倉庫へ運搬→作成/建設で設置して積載+60（最大3個）。木・石・鉱石も採取可。売買・補給はAへ。奥地・終幕は未実装。",
}

static func is_first_region(profile: String) -> bool:
 return profile==FIRST_REGION_A
static func regions(profile := DESERT) -> Dictionary:
 return FIRST_REGION_A_REGIONS if is_first_region(profile) else REGIONS
static func roads(profile := DESERT) -> Dictionary:
 return FIRST_REGION_A_ROADS if is_first_region(profile) else ROADS
static func hints(profile := DESERT) -> Dictionary:
 return FIRST_REGION_A_HINTS if is_first_region(profile) else MAP_HINTS

## Display-only comparison data for the early-region road-planning spike.
## The existing WorldTrip land actions remain the sole authority that can
## consume resources or change `region_state`; this pure helper intentionally
## cannot decide a journey or a risk outcome.
static func first_region_route_study(state: Dictionary) -> Array:
 var roads: Dictionary = Dictionary(state.get("roads", {}))
 var ab: Dictionary = Dictionary(roads.get("ab", {}))
 var bd: Dictionary = Dictionary(roads.get("bd", {}))
 var graded := bool(ab.get("graded", false))
 var cleared := bool(bd.get("cleared", false))
 return [
  {
   "id": "safe_detour",
   "kind": "route",
   "available": true,
   "preview_only": false,
   "state": "available",
   "route": ["a_start", "b_forest", "c_quarry"],
   "alternate_route": ["a_start", "d_yard", "c_quarry"],
   "cost": {},
   "title": "安全迂回",
   "effect": "既存の経路候補を切り替えて、通常の横1レーン移動へ出発します。",
  },
  {
   "id": "grade_ab",
   "kind": "work",
   "available": not graded,
   "preview_only": false,
   "state": "complete" if graded else "available",
   "route": ["a_start", "b_forest"],
   "cost": {GameData.Item.WOOD: 2, GameData.Item.STONE: 3},
   "title": "A-B 整地",
   "effect": "実在庫を使う既存整備。距離と燃料見込みを28%短縮します。" if not graded else "整備済み。既存の短縮効果が有効です。",
  },
  {
   "id": "clear_bd",
   "kind": "work",
   "available": cleared,
   "preview_only": false,
   "state": "complete" if cleared else "blocked",
   "route": ["b_forest", "d_yard"],
   "cost": {GameData.Item.WOOD: 2, GameData.Item.STONE: 1},
   "title": "B-D 倒木撤去",
   "effect": "倒木を撤去するとB-D直通が再訪後も使えます。" if not cleared else "撤去済み。B-D直通が使用可能です。",
  },
  {
   "id": "risk_candidate",
   "kind": "future",
   "available": false,
   "preview_only": true,
   "state": "future",
   "route": [],
   "cost": {},
   "title": "低コスト・不安定な強行案",
   "effect": "比較用の将来案です。荷物損傷・喪失や強行通行は今回の試作では発生しません。",
  },
 ]
static func node_kind(id: String,profile := DESERT) -> String:
 return (FIRST_REGION_A_NODE_KIND if is_first_region(profile) else NODE_KIND).get(id,"village")
static func road_ends(id: String,profile := DESERT) -> Array:
 return roads(profile).get(id,[])
static func region_data(id: String,profile := DESERT) -> Dictionary:
 return regions(profile).get(id,{})
## Known wildlife only.  This is intentionally not a discovery or abundance API.
static func fauna_of(id: String,profile := DESERT) -> Array:
 if is_first_region(profile): return FIRST_REGION_A_FAUNA.get(id,[]).duplicate()
 var species:String=String(region_data(id,profile).get("creature",""))
 return [species] if GameData.CREATURES.has(species) else []
static func road_fauna(profile := DESERT) -> Array:
 return FIRST_REGION_A_ROAD_FAUNA.duplicate() if is_first_region(profile) else []
## A pure link from a known material to already revealed region data.  It does
## not promise current stock, an accessible road, or a new destination.
static func known_regions_for_item(profile: String,item: int) -> Array:
 var found:Array=[]
 for id in regions(profile):
  if not public_region(id,profile): continue
  var region:Dictionary=region_data(id,profile)
  var has_item:=false
  for kind in region.get("points",[]):
   if GatherDB.POINTS.has(kind) and int(GatherDB.POINTS[kind].item)==item:
    has_item=true
  for species in fauna_of(id,profile):
   if GameData.CREATURES.get(species,{}).get("drops",{}).has(item):
    has_item=true
  if has_item:found.append(id)
 return found
static func road_between(a: String,b: String,profile := DESERT) -> String:
 for id in roads(profile):
  var ends:Array=roads(profile)[id]
  if a in ends and b in ends and a != b:return id
 return ""
static func public_region(id: String,profile := DESERT) -> bool:
 return regions(profile).has(id) and bool(regions(profile)[id].get("open",false))
static func next_region_unlocked(state: Dictionary,completion: Dictionary) -> bool:
 return bool(completion.get("completed",false)) and FirstRegionCompletion.boss_returned(completion) and FirstRegionCompletion.route_connected(state)
static func region_accessible(id: String,profile := DESERT,state: Dictionary = {},completion: Dictionary = {}) -> bool:
 return public_region(id,profile) and (not is_first_region(profile) or id!=NEXT_REGION_ENTRY or next_region_unlocked(state,completion))
static func road_available(id: String,profile := DESERT,state: Dictionary = {},completion: Dictionary = {}) -> bool:
 if not roads(profile).has(id):return false
 var ends:Array=roads(profile)[id]
 if not public_region(ends[0],profile) or not public_region(ends[1],profile):return false
 if is_first_region(profile) and id=="dn":return next_region_unlocked(state,completion)
 if is_first_region(profile) and id=="bd":
  return bool(state.get("roads",{}).get("bd",{}).get("cleared",false))
 return true
static func public_road(id: String,profile := DESERT,state: Dictionary = {},completion: Dictionary = {}) -> bool:
 return road_available(id,profile,state,completion)
static func map_road_visible(id: String,profile := DESERT) -> bool:
 if is_first_region(profile): return roads(profile).has(id)
 return public_road(id,profile)
static func road_length(id: String,profile := DESERT,state: Dictionary = {}) -> float:
 if not is_first_region(profile):return LENGTH
 var base:float=float(FIRST_REGION_A_ROAD_META.get(id,{}).get("length",LENGTH))
 # 整地は一度だけ。戦闘・敵や採取抽選には影響せず、移動距離と燃料だけを短縮する。
 if id=="ab" and bool(state.get("roads",{}).get("ab",{}).get("graded",false)):return base*0.72
 return base
static func road_is_graded(id: String,profile := DESERT,state: Dictionary = {}) -> bool:
 return is_first_region(profile) and id=="ab" and bool(state.get("roads",{}).get("ab",{}).get("graded",false))
static func name_of(id: String,profile := DESERT) -> String:
 return region_data(id,profile).get("name",id)
static func paths(start:String,goal:String,profile := DESERT,state: Dictionary = {},completion: Dictionary = {}) -> Array:
 if start==goal or not region_accessible(start,profile,state,completion) or not region_accessible(goal,profile,state,completion):return []
 var found:Array=[]
 _walk(start,goal,[start],found,profile,state,completion)
 found.sort_custom(func(a,b):return a.size()<b.size())
 return found
static func _walk(at:String,goal:String,visited:Array,found:Array,profile:String,state:Dictionary,completion:Dictionary) -> void:
 if at==goal:
  var path:=visited.duplicate();path.pop_front();found.append(path);return
 for id in roads(profile):
  if not public_road(id,profile,state,completion) or at not in roads(profile)[id]:continue
  var next:String=roads(profile)[id][1] if roads(profile)[id][0]==at else roads(profile)[id][0]
  if next in visited:continue
  var branch:=visited.duplicate();branch.append(next);_walk(next,goal,branch,found,profile,state,completion)
