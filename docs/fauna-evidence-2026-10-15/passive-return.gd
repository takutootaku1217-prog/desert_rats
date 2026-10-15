extends "res://tools/test_world_fauna.gd"
func _initialize():
 for test_seed in [501,502,503]:
  seed(test_seed)
  main=load("res://scenes/main.tscn").instantiate();root.add_child(main);main.process_mode=Node.PROCESS_MODE_DISABLED
  await process_frame
  main.target_speed=0;main.scroll_speed=0
  for w in main.workers:
   w.stop_work()
   for j in GameData.job_list(): w.priorities[j]=0
  main.world._spawn_visible()
  var id:String=main.creatures_root.get_child(0).world_id
  var gone_at:float=-1
  for i in 9000:
   main.world.sync()
   for c in main.creatures_root.get_children():
    if not c.is_queued_for_deletion():c._process(0.2)
   await process_frame
   main.world._spawn_visible()
   if main.creatures_root.get_child_count()==0:
    gone_at=float(i+1)*0.2;break
  var row:Dictionary=main.world.locations["region:south_oasis"][id]
  print("IDLE seed=%d gone_at=%.1f spent=%s anchor=%.1f live=%d" % [test_seed,gone_at,row.spent,row.anchor,main.creatures_root.get_child_count()])
  main.world._archive();main.world._spawn_visible()
  print("REVISIT spawn_count=%d same_anchor=%.1f"%[main.creatures_root.get_child_count(),row.anchor])
  var old_hp:float=row.data.hp
  main.director.elapsed+=121
  main.world._spawn_visible()
  var returned=main.creatures_root.get_children().filter(func(c):return c.world_id==id)
  print("RETURN seed=%d same_id=%s hp_preserved=%s total_ids=%d"%[test_seed,returned.size()==1,returned.size()==1 and returned[0].hp==old_hp,main.world.next_id])
  root.remove_child(main);main.free();main=null
 quit()
