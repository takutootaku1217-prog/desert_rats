extends "res://tools/test_world_flow.gd"
func _initialize():
 FacilityDB.start_all=false
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",501);root.add_child(main)
 if not main.is_node_ready():await main.ready
 Engine.time_scale=12
 print("JOURNEY_FLOW seed501・初期物資・既定優先度・出来事あり。資源/速度/耐久の注入なし。時間のみ12倍。")
 if not main.director.enabled or not main.world.active:fail("既定世界でない");finish();return
 if not main.journey.plan(["east_sands","central_trade"],["east_sands"]):fail("寄り道の予約拒否");finish();return
 if not await wait_for("砂原へ実走行して予約停車",func():return main.world.phase=="stopped" and main.world.region=="east_sands",600):finish();return
 var gathered:int=main.total_gathered
 if not await wait_for("砂原で既定AIが3個以上採取",func():return main.total_gathered>=gathered+3,300):finish();return
 # 再開は帰還・荷卸し後。既存の呼戻し操作を使い、その意思を自動解除しない。
 main.operations.stance="recall"
 if not await wait_for("採取した仲間と荷物を帰還",func():return main.world.ready_reason()=="",300):finish();return
 if main.journey.resume():fail("呼戻し方針を勝手に解除");finish();return
 main.operations.stance="normal"
 if not main.journey.resume():fail("帰還後の再開拒否");finish();return
 if not await wait_for("都市に最終停車",func():return main.world.phase=="stopped" and main.world.region=="central_trade",600):finish();return
 if not main.town.location_ok():fail("都市に入れない");finish();return
 main.operations.stance="recall"
 if not await wait_for("都市で仲間を戻して街へ入る準備",func():return main.world.ready_reason()=="",300):finish();return
 main.town_ui.open()
 if not main.town_ui.is_open():fail("街画面が開かない");finish();return
 main.town_ui.close()
 print("JOURNEY_FINAL distance=",main.director.distance," gathered=",main.total_gathered," fuel=",main.base.fuel," crew=",main.workers.size()," remaining=",main.journey.remaining)
 finish()
