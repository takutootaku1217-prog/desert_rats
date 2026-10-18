extends "res://tools/test_tool_flow.gd"
func _initialize():
 # Keep the normal-map small-crew flow explicit rather than inheriting the
 # five-person default used by new games.
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",diagnostic_seed());main.set_meta("diagnostic_crew_count",3);root.add_child(main);await main.ready
 Engine.time_scale=12
 print("FIRST_CYCLE_FLOW 通常開始3人・有限資源・既定出来事・素材/道具/設備注入なし seed=",diagnostic_seed())
 main.request_build("workbench")
 for id in ["tool_wood_pick","tool_hammer","tool_wood_axe","tool_axe"]:main.request_order(id,1)
 main.request_order("smelt",16)
 if not await wait_for("木のみの作業台",func():return main.has_facility("workbench"),240):finish();return
 if not await wait_for("木製採掘具→石製採掘具",func():return owns_tool(GameData.Item.HAMMER),300):finish();return
 if not await prepare_material(GameData.Item.WOOD,4,"鉄道具の柄用木4を先に確保"):finish();return
 if not await make_item("tool_pick"):finish();return
 if not await wait_for("安全寄りの村で基本鉄採掘具を装備",func():return main.workers.any(func(w):return w.tools.get("mine",-1)==GameData.Item.PICKAXE),120):finish();return
 if not await make_item("tool_iron_axe"):finish();return
 if not await wait_for("安全寄りの村で基本鉄斧を装備",func():return main.workers.any(func(w):return w.tools.get("chop",-1)==GameData.Item.IRON_AXE),120):finish();return
 # 以後の強化は有限の街道・砂原で追加素材を集める。村に無限補充しない。
 main.gather_policy[GameData.Item.STONE]=0
 main.workers[0].set_priority(GameData.Job.HUNT,5)
 if not await go("east_sands"):finish();return
 if not main.world.request("central_trade"):fail("街道選択失敗");finish();return
 main.target_speed=60
 if not await make_item("haul_frame"):finish();return
 var w=main.workers[0]
 if not main.equip_work_support(w):fail("フレーム装備失敗");finish();return
 if not main.request_build("cargo_rack"):fail("箱の設置依頼失敗");finish();return
 if not await wait_for("収納箱を製作設置",func():return main.has_facility("cargo_rack"),600):finish();return
 if not await wait_for("中央交易都市到着",func():return main.world.phase=="stopped",600):finish();return
 main.set_procurement(GameData.Item.IRON_ORE,4)
 if not main.world.request("old_mine"):fail("鉱山への街道選択失敗");finish();return
 if not await wait_for("鉱山入口到着",func():return main.world.phase=="stopped",600):finish();return
 if not main.quarry.select():fail("追加素材の鉱床選択失敗");finish();return
 if not await wait_for("鉱床到着",func():return main.quarry.state=="parked",180):finish();return
 main.operations.set_stance("alert")
 if not await wait_for("警戒中も近場採取を継続",func():return main.workers.any(func(x):return x.ai.state==CharacterAI.State.GATHER),120):finish();return
 if not main.request_build("storage_upgrade"):fail("収納強化依頼失敗");finish();return
 if not await wait_for("収納強化1段階",func():return main.has_facility("storage_upgrade"),420):finish();return
 main.unequip_work_support(w)
 if not await make_item("handcart"):finish();return
 if not main.equip_work_support(w,GameData.Item.HANDCART):fail("手押し車装備失敗");finish();return
 if not main.request_build("parallel_bench"):fail("2枠加工依頼失敗");finish();return
 if not await wait_for("2枠加工台完成",func():return main.has_facility("parallel_bench"),420):finish();return
 main.operations.set_stance("recall")
 if not await wait_for("3人と荷物を呼び戻し",func():return main.operations.returned_count()==3,240):finish();return
 main.operations.tick()
 main.operations.set_stance("normal");main.quarry.near_only=false
 main.gather_policy[GameData.Item.IRON_ORE]=5
 main.gather_policy[GameData.Item.WOOD]=0
 if not await wait_for("奥の生物を目視して危険帰還",func():return main.workers.any(func(x):return x.ai.danger_hold),420):finish();return
 main.operations.set_stance("recall")
 if not await wait_for("危険から3人帰還",func():return main.operations.returned_count()==3,240):finish();return
 main.operations.tick()
 var d:=SaveGame.capture(main)
 if not SaveGame.write(main,"user://cycle-flow.json",true) or not SaveGame.apply(main,SaveGame.read("user://cycle-flow.json")) or SaveGame.capture(main)!=d:fail("強化後の保存不一致")
 print("FIRST_CYCLE_RESULT capacity=",main.storage.max_weight()," cart_limit=",w.carry_limit()," report=",main.operations.result_text())
 finish()
