extends "res://tools/test_tool_flow.gd"
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();main.set_meta("diagnostic_seed",501);root.add_child(main);await main.ready
 Engine.time_scale=12
 if not await go("central_trade"):finish();return
 if OS.get_cmdline_user_args().has("--screenshots"):
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("/workspace/fauna-fix-evidence/natural_encounter.png")
 var selected=null
 var grazer=null
 for e in main.enemies_root.get_children():
  if e.kind=="paraceratherium":grazer=e
 if grazer==null:fail("新規都市に大型がいない");finish();return
 if not await wait_for("通常の採取/狩猟で大型の近くへ",func():
  for w in main.workers:
   if w.floor_i==0 and w.carrying<0 and w.position.distance_to(grazer.position)<180 and w.hp>=75:return true
  return false,240):finish();return
 for w in main.workers:
  if w.floor_i==0 and w.carrying<0 and w.position.distance_to(grazer.position)<180 and w.hp>=75:selected=w;break
 var hp:float=grazer.hp
 if not selected.ai.order_attack(grazer):fail("近接した仲間への明示命令拒否");finish();return
 if not await wait_for("大型へ実攻撃し中立の反撃開始",func():return grazer.hp<hp and selected.hp<100 and grazer.provoked_index==main.workers.find(selected),20):finish();return
 main.operations.set_stance("alert")
 if not await wait_for("後退命令で指示した仲間が帰還",func():return main.operations.returned(selected),120):finish();return
 print("NATURAL_GRAZER no_injection=true hp=",grazer.hp," worker_hp=",selected.hp)
 finish()
