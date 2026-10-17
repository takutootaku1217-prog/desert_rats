extends "res://tools/test_town_ui.gd"
func _initialize():
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.world.sync();main.world._archive();main.world.region="central_trade";main.world.phase="stopped";main.world._ensure_location()
 for w in main.workers:w.stop_work();w.floor_i=1;w.position=Vector2(700,GameData.LO_Y);w._climb_dest=null
 main.operations.set_stance("recall")
 main.storage.inventory.counts.clear();main.processor.stock.counts.clear();main.base.fuel=0
 check(main.town.execute(main.town.quote("accept_help")),"資源0・燃料0・所持金0の勤務を受注")
 main.town_ui.open()
 var before:=SaveGame.capture(main)
 var started:=Time.get_ticks_msec()
 main.town_ui.run_shift()
 while main.town.help=="working" and Time.get_ticks_msec()-started<35000:
  await process_frame
 var elapsed:=float(Time.get_ticks_msec()-started)/1000
 var after:=SaveGame.capture(main)
 check(elapsed>=29.5 and main.town.help=="ready" and main.town.credits==0,"30実秒の勤務後も報酬は未受領")
 check(before.crew==after.crew and before.base==after.base and before.inventory==after.inventory and before.processor==after.processor and before.director==after.director,"勤務中は維持費も通常作業も進まない")
 check(main.town.execute(main.town.quote("claim_help")) and main.town.credits==24,"明示受領で初めて24 Cr")
 print("REAL_SHIFT seconds=",elapsed," net_credits=",main.town.credits," inventory=",main.storage.inventory.counts)
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
