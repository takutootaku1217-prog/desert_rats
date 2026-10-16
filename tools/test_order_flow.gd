extends "res://tools/test_tool_flow.gd"
func order_and_wait(id:String)->bool:
 var r:=GameData.recipe_by_id(id)
 if main.request_order(id,1)!=1:fail("注文拒否 "+id);return false
 for it in r["in"]:main.set_procurement(it,int(r["in"][it]))
 return await wait_for("注文→搬入→加工→収納 "+id,func():return owns_tool(r.out) if r.out in GameData.TOOL_ITEMS else main.storage.count_of(r.out)>0,480)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed());root.add_child(main);await main.ready
 Engine.time_scale=12
 print("ORDER_FLOW 初期3人・既定出来事・物資/設備/道具注入なし。採取目標・有限注文・狩猟優先・手動行先のみ。")
 main.set_procurement(GameData.Item.WOOD,5)
 main.request_build("workbench")
 if not await wait_for("木材採取→作業台",func():return main.has_facility("workbench"),240):finish();return
 if not await order_and_wait("tool_wood_pick"):finish();return
 if not await order_and_wait("tool_wood_axe"):finish();return
 if not await order_and_wait("tool_hammer"):finish();return
 if not await order_and_wait("tool_axe"):finish();return
 main.refill_settings[GameData.Item.REPAIR_KIT].target=1 # 方針画面で成長準備中の備蓄量を指定
 main.request_order("smelt",8)
 if not await wait_for("収納・運搬用の鉄4を精錬",func():return main.storage.count_of(GameData.Item.IRON)>=4,480):finish();return
 main.gather_policy[GameData.Item.STONE]=0
 main.workers[0].set_priority(GameData.Job.HUNT,5)
 if not await go("east_sands"):finish();return
 main.request_build("cargo_rack")
 if not main.world.request("central_trade"):fail("行先拒否");finish();return
 if not await order_and_wait("haul_frame"):finish();return
 if not await wait_for("フレーム装備可能",func():return main.work_support_change_reason(main.workers[0],true)=="",180):finish();return
 if not main.equip_work_support(main.workers[0]):fail("フレーム装備拒否");finish();return
 if not await wait_for("収納箱設置",func():return main.has_facility("cargo_rack"),480):finish();return
 if not await order_and_wait("tool_pick"):finish();return
 if not await order_and_wait("tool_iron_axe"):finish();return
 var d:=SaveGame.capture(main)
 if not SaveGame.apply(main,d) or SaveGame.capture(main)!=d:fail("注文進行後の保存不一致")
 print("ORDER_RESULT capacity=",main.storage.max_weight()," carry=",main.workers[0].carry_limit()," hunger=",main.workers.map(func(w):return w.hunger)," hull=",main.base.parts)
 finish()
