extends "res://tools/test_consumption_loop.gd"
## 正規の採取・運搬・建設・加工APIを単独AIで通す。資源地点の配置だけ診断用。
## 同時間比較・満載・旧保存は明示的な境界fixture。通常世界の進行は tool_flow で別に確認。
func snapshot(label: String) -> void:
 var d := SaveGame.capture(main)
 check(SaveGame.write(main,"user://tool-progression.json",true),label+" 保存")
 check(SaveGame.apply(main,SaveGame.read("user://tool-progression.json")),label+" 復元")
 check(SaveGame.capture(main)==d,label+" 資産・途中進捗一致")
 w=main.workers[0]
 st=main.storage

func _initialize() -> void:
 FacilityDB.start_all=false
 main=load("res://scenes/main.tscn").instantiate()
 main.set_meta("diagnostic_seed",501)
 root.add_child(main)
 await main.ready
 main.process_mode=Node.PROCESS_MODE_DISABLED
 main.director.enabled=false
 main.director.active.clear()
 main.director.forecast.clear()
 main.tool_auto=false
 main.scroll_speed=0.0
 main.target_speed=0.0
 st=main.storage
 for worker in main.workers:
  worker.stop_work()
  for j in GameData.job_list(): worker.priorities[j]=0
 for parent in [main.resources_root,main.creatures_root]:
  for node in parent.get_children(): node.free()
 for setting in main.refill_settings.values(): setting.enabled=false
 w=main.workers[0]
 w.priorities[GameData.Job.GATHER]=3
 w.floor_i=1
 w.position=Vector2(600,GameData.LO_Y)
 w.slot_offset=Vector2.ZERO
 check(GameData.TOOL_ITEMS.all(func(it):return st.count_of(it)==0) and main.workers.all(func(worker):return worker.tools.is_empty()),"新規開始は全員素手・支給道具なし")
 check(st.count_of(GameData.Item.IRON)==0 and st.count_of(GameData.Item.STONE)==0,"新規開始に鉄・石の支給なし")
 check(not main.has_facility("workbench"),"初期作業台なし")
 check(GatherDB.evaluate("rock",-1,7,5.0).eff==0 and GatherDB.evaluate("vein",-1,7,5.0).eff==0,"高能力の素手でも石・鉱石は採れない")
 check(not main.has_facility(GameData.recipe_station(GameData.recipe_by_id("tool_wood_pick"))),"木製道具には作業台が必要")
 for i in 6: gather("tree")
 check(st.count_of(GameData.Item.WOOD)==18,"素手で木材18を採取・収納")
 check(main.request_build("workbench"),"木材のみの作業台建設を依頼")
 check(job(GameData.Job.HAUL) and job(GameData.Job.PROCESS),"実AIで木材を運び作業台を組立")
 check(main.has_facility("workbench") and st.count_of(GameData.Item.WOOD)==15 and st.count_of(GameData.Item.IRON)==0,"作業台は木3のみ消費、鉄不要")
 craft("tool_wood_pick")
 craft("tool_wood_axe")
 check(main.equip_tool(w,GameData.Item.WOOD_PICK) and main.equip_tool(w,GameData.Item.WOOD_AXE),"製作した木製道具を両枠へ装備")
 check(w.gather_eval("rock").eff>0 and w.gather_eval("vein").eff==0,"木製で石を解放、鉱石は未解放")
 snapshot("木製段階")
 gather("rock")
 craft("tool_hammer")
 craft("tool_axe")
 check(main.equip_tool(w,GameData.Item.HAMMER) and main.equip_tool(w,GameData.Item.AXE),"製作した石製道具へ更新")
 check(st.count_of(GameData.Item.WOOD_PICK)==1 and st.count_of(GameData.Item.WOOD_AXE)==1,"旧道具は倉庫に保全")
 snapshot("石製段階")
 gather("vein")
 craft("smelt")
 craft("tool_pick")
 craft("smelt")
 craft("tool_iron_axe")
 check(main.equip_tool(w,GameData.Item.PICKAXE) and main.equip_tool(w,GameData.Item.IRON_AXE),"採った鉱石→精錬→鉄製道具を製作して装備")
 snapshot("鉄製段階")
 # 旧版で加工中だった石道具/作業台のレシピを厳密に受理。資産や支払済材料を変換しない。
 var old_tool:Dictionary=GameData.recipe_by_id("tool_hammer").duplicate(true)
 old_tool.erase("station")
 var old_bench:=FacilityDB.recipe_of("workbench")
 old_bench["in"]={GameData.Item.WOOD:3,GameData.Item.IRON:1}
 check(SaveGame.recipe(old_tool) and SaveGame.recipe(old_bench),"旧版の投入済レシピを受理")
 var corrupt:=old_bench.duplicate(true);corrupt["in"][GameData.Item.IRON]=2
 check(not SaveGame.recipe(corrupt),"未知のレシピ改変は拒否")
 main.processor.current=old_tool
 main.processor.progress=1.25
 snapshot("旧版の加工中石道具")
 check(job(GameData.Job.PROCESS) and st.count_of(GameData.Item.HAMMER)==2,"旧加工は二重消費なしで完了")
 main.base.built.erase("workbench")
 main.processor.current=old_bench
 main.processor.progress=2.5
 snapshot("旧版の鉄入り作業台組立中")
 check(job(GameData.Job.PROCESS) and main.has_facility("workbench"),"旧作業台も投入済み材料を二重消費せず完成")
 normal_bag_benchmark()
 # 同じ仲間・同じ地点・同じ採取時間。採取部分だけを測るため袋を診断上拡大。
 st.inventory.counts.clear()
 var rates:Array=[]
 for tool in [-1,GameData.Item.WOOD_AXE,GameData.Item.AXE,GameData.Item.IRON_AXE]:
  w.stop_work();w.tools={}
  if tool>=0:w.tools["chop"]=tool
  w.ranks[GameData.Field.GATHERER]=5
  var pt:=GatherPoint.new();pt.setup(main,"tree");pt.remaining=50;pt.max_amount=50
  main.resources_root.add_child(pt)
  w.ai.res=pt;pt.claimed_by=w;w.ai.bag_limit=50
  w.ai.state=CharacterAI.State.GATHER
  var duration:float=0.9/(GatherDB.BASE_YIELD_RATE*w.field_mult(GameData.Field.GATHERER))
  for i in 100:w.ai._work_point(duration/100.0)
  var n:int=0 if w.carrying<0 else w.carry_n
  rates.append(n)
  check(pt.remaining+n==50,"有限残量と取得量の保存: "+str(tool))
  w.stop_work();w.carrying=-1;w.carry_n=1;w.carry_bonus={};pt.free()
 check(rates[0]<rates[1] and rates[1]<rates[2] and rates[2]<rates[3],"同じ採取時間の実取得数が素手→木→石→鉄で増加 "+str(rates))
 # 通常の袋上限と容量を使う。最後1個、満載、古い採取性能キャッシュ。
 w.tools={"mine":GameData.Item.PICKAXE}
 st.inventory.counts={GameData.Item.STONE:st.max_weight()/CargoDB.size_of(GameData.Item.STONE)-1}
 var p:=GatherPoint.new();p.setup(main,"rock");p.position=Vector2(650,610);p.remaining=1;p.max_amount=1
 main.resources_root.add_child(p)
 check(job(GameData.Job.GATHER) and p.remaining==0 and st.free_for(GameData.Item.STONE)==0,"最後の残量1・積載空き1を厳守")
 p.free()
 var blocked:=GatherPoint.new();blocked.setup(main,"rock");blocked.position=Vector2(650,610)
 main.resources_root.add_child(blocked)
 check(not w.ai._try_start(GameData.Job.GATHER),"満載では採取開始しない")
 st.inventory.counts.clear();w.tools={}
 w.ai.res=blocked;w.ai.bag_limit=3;w.ai.state=CharacterAI.State.GATHER
 w.ai.gather_ev={"eff":0.35,"seconds":1.0,"bonus":{}}
 var left:int=blocked.remaining
 w.ai._work_point(20.0)
 check(blocked.remaining==left and w.carrying<0,"旧保存の素手石採取キャッシュで解放条件を迂回しない")
 blocked.free()
 # 素手制限は採取だけ。完成品運搬・狩猟・解体へ波及しない。
 gather("tree")
 craft("firewood")
 check(w.tools.is_empty(),"素手のまま材料運搬・加工・完成品収納")
 var prey:=Creature.new();prey.setup(main,"hare");prey.position=Vector2(650,610)
 main.creatures_root.add_child(prey)
 var meat_before:int=st.count_of(GameData.Item.MEAT)
 check(job(GameData.Job.HUNT) and st.count_of(GameData.Item.MEAT)>meat_before,"素手でも狩猟→獲物運搬→解体（生物の配置・静止は診断fixture）")
 main.recipe_priority.erase("tool_wood_pick");main.recipe_priority.erase("tool_wood_axe") # 旧保存の欠落キーを再現
 # 旧保存には新規レシピの方針キーがない。新規開始の支給変更をロードへ適用しない。
 st.add_item(GameData.Item.IRON,2);st.add_item(GameData.Item.HAMMER,1);st.add_item(GameData.Item.WORKBENCH_PACK,1)
 snapshot("新方針キーのない旧形式・鉄/旧道具/撤去品の所有")
 check(st.count_of(GameData.Item.IRON)==2 and st.count_of(GameData.Item.HAMMER)==1 and st.count_of(GameData.Item.WORKBENCH_PACK)==1,"旧資産を削除せず復元")
 # 生物が消えたフレームと次のAI更新の間でセーブする境界。
 w.stop_work();w.ai.state=CharacterAI.State.HUNT_MOVE;w.ai.prey=null
 var lost:=SaveGame.capture(main)
 check(lost.crew[0].ai.state==CharacterAI.State.SEARCH and w.ai.state==CharacterAI.State.HUNT_MOVE,"失効した追跡先は保存コピーだけ正規化、ライブAIは変更しない")
 check(SaveGame.apply(main,lost) and SaveGame.capture(main)==lost,"失効参照の保存再開でも全資産と持続値が一致")
 # 鉄を必要とする建設依頼が、前提となる最初の採取道具を塞がない。
 w=main.workers[0];w.stop_work();w.ai.state=CharacterAI.State.SEARCH;w.tools={}
 st.inventory.counts.clear();main.processor.stock.counts.clear()
 for worker in main.workers:
  worker.tools={}
 for setting in main.refill_settings.values(): setting.enabled=false
 st.add_item(GameData.Item.WOOD,2) # 競合境界fixture: 箱の木6には届かない量
 check(main.request_build("cargo_rack"),"先に鉄を使う箱の建設を依頼")
 check(main.choose_recipe().is_empty(),"道具は明示注文するまで作らない")
 craft("tool_wood_pick")
 check(st.count_of(GameData.Item.WOOD)==0 and main.build_pending("cargo_rack")==1,"箱の取り置きから最初の木製採掘具だけを製作、建設依頼は維持")
 check(not main.build_needs_gather_tool(GameData.Item.WOOD_PICK),"倉庫に採取可能な道具があれば重複する前提製作は不要")
 check(main.equip_tool(w,GameData.Item.WOOD_PICK),"前提の木製採掘具を装備")
 gather("rock");gather("tree")
 craft("tool_hammer")
 check(main.equip_tool(w,GameData.Item.HAMMER),"箱の木材取り置きを保ったまま最初の石採掘具へ進む")
 check(not main.build_needs_gather_tool(GameData.Item.HAMMER),"一人が鉱石を採れるようになれば例外を終了")
 check(main.reserved_for_builds().is_empty(),"不足建設は他の注文用材料を取り置きしない")
 check(main.cancel_build("cargo_rack"),"境界fixtureの箱依頼を通常APIで取消")
 # 製作画面を実際に開く。描画ありの実行時は同じ画面を保存。
 main.craft_ui.open_entry("tool_wood_pick")
 await process_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("/workspace/tool-progression-evidence/wood-craft.png")
 print("== 結果: %s ==" % ("すべて成功" if fails==0 else "%d 件失敗"%fails))
 quit(1 if fails else 0)

func normal_bag_benchmark() -> void:
 for parent in [main.resources_root,main.creatures_root]:
  for node in parent.get_children():node.free()
 var times:Array=[]
 for tool in [-1,GameData.Item.WOOD_AXE,GameData.Item.AXE,GameData.Item.IRON_AXE]:
  w.stop_work();w.tools={};w.ranks[GameData.Field.GATHERER]=5;w.work_support=-1
  w.floor_i=1;w.position=st.access_point();w.slot_offset=Vector2.ZERO;w.hunger=100;w.fatigue=0
  w.ai.state=CharacterAI.State.SEARCH;w.priorities[GameData.Job.GATHER]=3
  if tool>=0:w.tools["chop"]=tool
  st.inventory.counts.clear()
  var pt:=GatherPoint.new();pt.setup(main,"tree");pt.position=Vector2(650,610);pt.remaining=100;pt.max_amount=100
  main.resources_root.add_child(pt)
  var ticks:=0;var work_ticks:=0;var maxbag:=0
  while st.count_of(GameData.Item.WOOD)<60 and ticks<48000:
   if w.ai.state==CharacterAI.State.GATHER:work_ticks+=1
   w.ai.tick(0.05);ticks+=1
   maxbag=maxi(maxbag,w.ai._bag_n())
  var seconds:float=ticks*0.05
  times.append(seconds)
  check(st.count_of(GameData.Item.WOOD)==60 and maxbag<=3 and pt.remaining==40,"通常袋3・20往復で60個を過不足なく収納 "+str(tool))
  print("NORMAL_BAG tool=",tool," elapsed=",seconds," work_seconds=",work_ticks*0.05," maximum_bag=",maxbag)
  w.stop_work();pt.free()
 check(times[0]>times[1] and times[1]>times[2] and times[2]>times[3],"通常袋と実運搬でも上位ほど同じ60個の所要時間が短い "+str(times))
