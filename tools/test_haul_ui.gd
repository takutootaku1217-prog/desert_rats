extends "res://tools/test_weapon_ui.gd"
func shot(path: String):
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(path)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.set_process(false);main.director.enabled=false
 for w in main.workers: w.set_process(false)
 main.base.add_facility("workbench",true)
 for it in GameData.recipe_by_id("haul_frame")["in"]: main.processor.stock.add(it,GameData.recipe_by_id("haul_frame")["in"][it])
 await key(KEY_F)
 for button in main.craft_ui._cat_row.get_children():
  if button.text=="装備": await click(button);break
 for row in main.craft_ui._list.get_children():
  if row.tooltip_text.begins_with("背負いフレーム"):
   await mouse(row.get_global_rect().get_center(),MOUSE_BUTTON_LEFT);break
 check(main.craft_ui.selected_entry().get("id","")=="haul_frame","Fの装備分類でフレーム選択")
 await click(main.craft_ui._craft_btn)
 check(main.craft_queue.any(func(q):return q.id=="haul_frame"),"実入力で製作依頼")
 # 在庫はUI境界fixture。製作から完成はhaul_support/haul_flowで検査。
 main.storage.store_owned(GameData.Item.HAUL_FRAME,1)
 await key(KEY_C)
 # 個人装備は「装備・荷物」カテゴリで変更する。
 await click(main.detail._tab_btns[1])
 await frames()
 var a=main.detail._worker
 await reveal(main.detail._live["work_support_equip"])
 await click(main.detail._live["work_support_equip"])
 check(a.work_support==GameData.Item.HAUL_FRAME and main.storage.count_of(GameData.Item.HAUL_FRAME)==0,"C独立枠で装備")
 await click(main.detail._live["work_support_equip"])
 check(main.storage.count_of(GameData.Item.HAUL_FRAME)==0,"実入力連打は無増殖")
 check(main.status._weight.tooltip_text.contains("装備中の仕事補助 15"),"重量内訳にも装備中15を表示")
 main.detail._scroll.scroll_vertical+=150
 await frames()
 await shot("/workspace/desert-rats-checks/haul-ui.png")
 await click(main.detail._live["work_support_off"])
 check(a.work_support==-1 and main.storage.count_of(GameData.Item.HAUL_FRAME)==1,"実入力で解除")
 var b=main.workers[1];await click(main.detail._picker._rows[b])
 await click(main.detail._tab_btns[1]);await frames()
 await reveal(main.detail._live["work_support_equip"]);await click(main.detail._live["work_support_equip"])
 check(b.work_support==GameData.Item.HAUL_FRAME and a.work_support==-1,"別個体へ持替え")
 await key(KEY_C)
 # 見た目fixture: 背面両向き・最大荷物でも頭上に塔を作らない。
 for w in main.workers: w.position=Vector2(500+main.workers.find(w)*85,510);w.floor_i=0
 b.carrying=GameData.Item.WOOD;b.carry_n=5;b.facing=-1;b.queue_redraw()
 await frames();await shot("/workspace/desert-rats-checks/haul-back.png")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
