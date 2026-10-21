extends SceneTree
var main
func frames(n: int) -> void:
 for i in n: await process_frame
func shot(out: String, name_: String) -> void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(out + "/" + name_ + ".png")
func _initialize() -> void:
 main = load("res://scenes/main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 main.director.enabled = false
 main.target_speed = 0.0
 main.follow_target = null
 main.apply_vehicle_combat_preset()
 var arrivals = {}
 var deadline = Time.get_ticks_msec() + 10000
 while arrivals.size() < main.workers.size() and Time.get_ticks_msec() < deadline:
  for i in main.workers.size():
   var w = main.workers[i]
   if w.prototype_walk_target == null and not arrivals.has(i):
    assert(w.floor_i == 3 and w.position.distance_to(LargeVehicleLayout.top_room_anchor(i)) <= 4.1)
    arrivals[i] = w.position
    w.set_process(false)
  await process_frame
 assert(arrivals.size() == main.workers.size())
 print("actual walkthrough arrivals: ", arrivals)
 var out = OS.get_cmdline_user_args()[0]
 main.base_view.set_mode(BaseView.Mode.EXTERIOR, true)
 await frames(30)
 await shot(out, "exterior")
 main.base_view.set_mode(BaseView.Mode.INTERIOR, true)
 await frames(30)
 await shot(out, "interior-arrivals")
 # Visual fixture for a real room change using the ordinary construction API.
 main.storage.inventory.counts[GameData.Item.WOOD] = 10
 main.storage.inventory.counts[GameData.Item.FOOD] = 10
 assert(main.build_room("l3", "mess"))
 await frames(2)
 await shot(out, "room-change")
 main.storage.inventory.counts[GameData.Item.HIDE] = 6
 main.storage.inventory.counts[GameData.Item.BONE] = 2
 assert(main.build_room("u3", "bedroom"))
 assert(main.build_room("u2", "infirmary"))
 await frames(2)
 await shot(out, "ladder-room-change")
 for w in main.workers: w.set_process(true)
 await frames(180)
 await shot(out, "interior-normal-ai")
 main.vehicle_ui.open()
 await frames(3)
 await shot(out, "customization")
 quit()
