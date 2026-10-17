class_name WorldMapDB
extends RefCounted
## 正本10地域12接続。試作公開は4地域4道路のみ。サービスは未実装。
const REGIONS := {
 "south_oasis":{"name":"オアシスの交易村","creature":"hare","open":true,"pos":Vector2(80,300),"tint":Color("f3ead0"),"points":["tree","rock","vein"],"description":"安全寄りの村。木36・石と少量の鉄鉱石4。有限で再訪補充なし。基本の鉄道具を準備できます。"},
 "east_sands":{"name":"東部砂原","creature":"lizard","open":true,"pos":Vector2(440,300),"tint":Color("f4dba8"),"points":["tree","tree","rock"],"description":"砂丘と道標。枯れ木と、皮・骨を得られるトゲトカゲ。"},
 "central_trade":{"name":"中央交易都市","creature":"hump","open":true,"pos":Vector2(230,110),"tint":Color("e5d7c3"),"points":["tree","rock"],"description":"門と天幕が目印。街道には皮・骨・脂肪を得られるコブ獣。停泊し全員帰還後、拠点メニューから街へ。"},
 "old_mine":{"name":"大鉱山入口","open":true,"pos":Vector2(520,110),"tint":Color("cfcbd1"),"points":[],"description":"危険な鉱山。採取地点に鉄鉱石84。木材を準備し、生物を目視して判断してください。"},
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
static func road_between(a: String,b: String) -> String:
 for id in ROADS:
  if a in ROADS[id] and b in ROADS[id] and a != b: return id
 return ""
static func public_region(id: String) -> bool:
 return REGIONS.has(id) and REGIONS[id]["open"]
static func public_road(id: String) -> bool:
 return ROADS.has(id) and public_region(ROADS[id][0]) and public_region(ROADS[id][1])
static func name_of(id: String) -> String:
 return REGIONS.get(id,{}).get("name",id)
