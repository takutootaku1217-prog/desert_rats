extends "res://tools/test_equipment_ui.gd"
func reveal(control):
 var scroll=find_scroll(main.craft_ui._detail.get_parent())
 if scroll!=null:scroll.ensure_control_visible(control)
 await frames()
func named(name_: String):
 return main.craft_ui._detail.find_child(name_,true,false)
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.set_process(false);main.director.enabled=false
 for w in main.workers:w.set_process(false)
 main.processor.stock.add(GameData.Item.MEAT,6)
 await key(KEY_F)
 for b in main.craft_ui._cat_row.get_children():
  if b.text=="料理":await click(b);break
 await reveal(main.craft_ui._qty)
 await click(main.craft_ui._qty._btns[5])
 check(main.craft_ui._qty_val==5 and named("BatchSummary").text.contains("12.5秒"),"既存5ボタンで合計時間/成果を表示")
 # 素材運搬ボタンの連打境界。材料在庫だけfixtureで変更する。
 main.processor.stock.counts.clear();main.storage.store_owned(GameData.Item.MEAT,12)
 main.craft_ui._refresh(true);await frames()
 await reveal(main.craft_ui._carry_btn);await click(main.craft_ui._carry_btn)
 await click(main.craft_ui._carry_btn)
 check(main.workshop_incoming(GameData.Item.MEAT)==5,"不足5個の素材運搬を連打しても10個にしない")
 main.cancel_transfers();main.storage.inventory.counts.clear();main.processor.stock.add(GameData.Item.MEAT,6)
 main.craft_ui._refresh(true);await frames()
 await reveal(main.craft_ui._craft_btn);await click(main.craft_ui._craft_btn)
 check(main.craft_queue.size()==1 and main.craft_queue[0].n==5 and main.craft_queue[0].batch,"同じ制作ボタンがまとめ注文を予約")
 main._feed_crafts();main.processor.work(1.0,func(_f):return 1.0)
 await frames();main.craft_ui._refresh(true);await frames()
 check(named("BatchStatus").text.contains("未投入 2回") and named("BatchStatus").text.contains("投入済・未着手 2回") and named("BatchStatus").text.contains("加工中 1回"),"未投入/投入/加工中を分離表示")
 await reveal(named("CancelUnstarted"));await click(named("CancelUnstarted"))
 check(main.craft_queue.is_empty() and main.processor.orders.is_empty() and main.processor.progress==1.0 and main.processor.stock.count(GameData.Item.MEAT)==5,"実入力取消は未着手4回を戻し現行1回と時間を保持")
 await click(named("CancelUnstarted"));check(main.processor.stock.count(GameData.Item.MEAT)==5,"取消連打でも無増殖")
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("/workspace/desert-rats-checks/batch-ui.png")
 await reveal(main.craft_ui._qty);await click(main.craft_ui._qty._btns[1])
 check(main.craft_ui._qty_val==1 and main.craft_ui._craft_btn.text=="1回制作","少量1回に戻せる")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
