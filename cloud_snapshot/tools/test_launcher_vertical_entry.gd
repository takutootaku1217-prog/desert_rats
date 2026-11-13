extends SceneTree
## Regression: the interactive bridge launcher must keep its fresh validation
## party idle, otherwise normal auto-work can make the C-site entry reject the
## vertical slice before the player reaches its controls.

var launcher
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", message])
	if not ok:
		fails += 1

func _run() -> void:
	launcher = load("res://scenes/recovery_route_bridge_launcher.tscn").instantiate()
	root.add_child(launcher)
	for unused in 4:
		await process_frame
	var game = launcher.game
	_check(game != null, "launcher creates its isolated A-region game")
	if game != null:
		_check(not game.tool_auto, "vertical-slice launcher keeps automatic jobs idle before A→C entry")
		for worker in game.workers:
			_check(not worker.away and worker.carrying < 0 and worker.carry_bonus.is_empty(), "launcher starts each validation worker without carried or reserved cargo")
			for job in GameData.job_list():
				_check(int(worker.priorities.get(job, 0)) == 0, "launcher disables automatic job priority before validation travel")
	launcher.queue_free()
	print("== launcher vertical-entry result: %s ==" % ("passed" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)
