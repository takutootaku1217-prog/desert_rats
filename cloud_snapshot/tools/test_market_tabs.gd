extends SceneTree
var main
var failures := 0
func _init() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
 print("%s %s" % ["ok" if ok else "FAIL", message])
 if not ok: failures += 1
func _icons_present(buttons: Array) -> bool:
 return buttons.all(func(b):return is_instance_valid(b) and b.icon != null)
func _run() -> void:
 SaveGame.disabled = true
 main = load("res://scenes/main.tscn").instantiate()
 main.first_region_a_pilot = true
 main.set_meta("diagnostic_seed", 104729)
 root.add_child(main)
 await process_frame
 main.process_mode = Node.PROCESS_MODE_DISABLED
 main.director.enabled = false
 # Boundary UI fixture only: add known saleable stock. The separate full-cycle test never injects resources.
 main.storage.add_item(GameData.Item.STONE, 3)
 var ui = main.town_ui
 ui.open()
 ui.show_facility("market")
 _check(ui.has_method("select_market_tab"), "market has two independent tab controls")
 if not ui.has_method("select_market_tab"):
  ui.close();main.free();quit(1);return
 var before: Dictionary = main.storage.inventory.counts.duplicate(true)
 var credits: int = main.town.credits
 _check(ui.market_mode() == "buy", "first market visit defaults to buy")
 _check(ui.market_visible_items() == TownDB.BUY.keys(), "buy mode contains only buy goods")
 _check(ui._market_tabs.size() == 2 and _icons_present(ui._market_tabs), "buy and sell tabs each have an icon")
 _check(_icons_present(ui._market_buttons), "all visible market goods have icons")
 ui._market_tabs[1].pressed.emit()
 _check(ui.market_mode() == "sell", "sell tab Button signal selects sell")
 for item in ui.market_visible_items():
  _check(TownDB.SELL.has(item) and main.town.available(item) > 0, "sell list contains only available unreserved stock")
 _check(before == main.storage.inventory.counts and credits == main.town.credits, "switching tabs cannot mutate stock or money")
 ui._market_buttons[0].pressed.emit()
 _check(ui._action == "sell" and ui._item == GameData.Item.STONE, "visible sell item Button signal selects its own item")
 var ticket: Dictionary = ui._quote.duplicate(true)
 ui._quantity.value = 2
 ui.select_market_tab("buy")
 _check(ui._quote.is_empty() and ui._action.is_empty() and int(ui._quantity.value) == 1, "tab switch clears selection, amount and quote")
 _check(not main.town.execute(ticket), "a quote cancelled by tab switch cannot be executed")
 _check(ui._confirm.disabled, "tab switch leaves confirmation disabled")
 ui.preview("buy", GameData.Item.FOOD)
 _check(ui._confirm.disabled, "zero funds disables purchase")
 ui.confirm()
 _check(before == main.storage.inventory.counts and credits == main.town.credits, "insufficient purchase is non-mutating")
 ui.select_market_tab("sell")
 ui.preview("sell", GameData.Item.IRON_ORE)
 _check(ui._confirm.disabled, "absent stock cannot be sold")
 ui.preview("sell", GameData.Item.STONE)
 _check(not ui._confirm.disabled, "fixture stone can be sold in UI fixture")
 var stone_before: int = main.storage.count_of(GameData.Item.STONE)
 ui.confirm();ui.confirm()
 _check(main.storage.count_of(GameData.Item.STONE) == stone_before - 1 and main.town.credits == credits + TownDB.SELL[GameData.Item.STONE], "double confirmation executes only once")
 ui.preview("sell", GameData.Item.STONE)
 var stale_quote: Dictionary = ui._quote.duplicate(true)
 main.storage.inventory.take_n(GameData.Item.STONE, main.storage.count_of(GameData.Item.STONE))
 var stale_credits: int = main.town.credits
 ui.confirm()
 _check(main.town.credits == stale_credits and main.storage.count_of(GameData.Item.STONE) == 0, "inventory changed after preview rejects stale sale")
 _check(not main.town.execute(stale_quote), "rejected stale ticket cannot be replayed")
 _check(ui.market_visible_items().is_empty(), "empty saleable inventory shows no misleading products")
 main.storage.add_item(GameData.Item.STONE, 1)
 ui.select_market_tab("sell")
 ui.preview("sell", GameData.Item.STONE)
 var cancel_ticket: Dictionary = ui._quote.duplicate(true)
 ui.show_street()
 _check(not main.town.execute(cancel_ticket), "back to street cancels economy quote")
 ui.show_facility("market")
 _check(ui._quote.is_empty() and ui._confirm.disabled, "reopening market cannot retain a previous quote")
 for item in TownDB.SELL:
  main.storage.add_item(item, 1)
 ui.select_market_tab("sell")
 await process_frame
 await process_frame
 var panel_bottom: float = ui._panel.position.y + ui._panel.size.y
 _check(panel_bottom <= 720.0, "full sell catalogue and confirmation fit 720px viewport")
 _check(ui._panel.position.x + ui._panel.size.x <= 1280.0, "market fits 1280px viewport")
 _check(_icons_present(ui._market_buttons), "all sellable goods retain visible item icons")
 print("market panel rect: ", ui._panel.get_global_rect())
 main.production_orders.append({"id":"bed_pack","n":1,"batch":false})
 ui.select_market_tab("sell")
 _check(not ui.market_visible_items().has(GameData.Item.HIDE) and not ui.market_visible_items().has(GameData.Item.BONE), "materials held for a bed order are not offered for sale")
 main.production_orders.clear()
 ui.close();main.free()
 SaveGame.disabled=false
 print("== market tabs: %s ==" % ("passed" if failures == 0 else str(failures)+" failures"))
 quit(1 if failures else 0)
