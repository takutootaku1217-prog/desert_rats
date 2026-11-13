extends SceneTree
const PATH:="user://npc-fuel-field.json"
const RECEIPT:="user://npc-fuel-receipt.json"
var main
var failures:=0
var assertions:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 assertions+=1;print("  %s %s"%["ok" if ok else "FAIL",label])
 if not ok:failures+=1
func run()->void:
 if OS.get_environment("FLUID_TEST_HOME")=="":quit(2);return
 SaveGame.disabled=true
 main=load("res://scenes/main.tscn").instantiate();main.first_region_a_pilot=true
 root.add_child(main);await process_frame;main.process_mode=Node.PROCESS_MODE_DISABLED
 var receipt=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
 check(receipt is Dictionary and int(receipt.pid)!=OS.get_process_id(),"separate producer/consumer process")
 check(receipt.hash==FileAccess.get_sha256(PATH),"exact producer file")
 SaveGame.disabled=false
 check(SaveGame.apply(main,SaveGame.read(PATH)),"field save loads into fresh Main")
 var gate=main.mine_arrival_gate
 check(gate.field!=null and paused and main.world.npc_service.restored(),"restored field is paused and NPC remains restored")
 if failures:await finish();return
 var a=gate.field;a.process_mode=Node.PROCESS_MODE_DISABLED
 a._toggle_field_pause();var s=a.session;s.request_recall()
 for unused in 2400:
  if s.phase=="ready_to_exit":break
  a.life_clock.tick(0.05)
 check(s.phase=="ready_to_exit","ordinary actors return physically")
 a._commit_and_exit();await process_frame
 check(gate.field==null and main.world.npc_service.restored() and main.town.credits==int(receipt.cr),"field commit retains single restored extension without charge")
 main.process_mode=Node.PROCESS_MODE_DISABLED
 check(main.world.request("d_yard"),"return toward restored D")
 for unused in 400:
  main._process(0.25);await process_frame
  if main.world.region=="d_yard" and main.world.phase=="stopped":break
 check(main.world.region=="d_yard" and main.world.phase=="stopped","arrive restored D")
 check(main.world.site_store("d_yard").get(GameData.Item.STONE)==2 and main.world.region_state.lots.d_yard=="freight","freight contents independently persist")
 check(not main.world.npc_service.quote("restore").ok,"cannot pay restoration again after restart")
 var q:Dictionary=main.world.npc_service.quote("fuel_cash")
 check(q.ok and main.world.npc_service.execute(q),"post-restart D paid service works")
 check(main.town.credits==int(receipt.cr)-int(q.cost),"only actual service is charged")
 check(SaveGame.write(main,"user://npc-fuel-returned.json",true),"normal return saves after restart")
 await finish()
func finish()->void:
 main.queue_free();await process_frame;SaveGame.disabled=false
 print("NPC FUEL RESTART assertions=",assertions," failures=",failures)
 quit(1 if failures else 0)
