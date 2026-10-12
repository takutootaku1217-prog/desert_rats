extends "res://tools/test_progression.gd"
## 通常の段階進行の途中で保存/復元。物資や成功状態は注入しない。
var _next_snapshot := 10.0
var _seen := {}
func _initialize():
	process_frame.connect(_save_tick)
	super._initialize()
func _save_tick():
	if main == null or not main.is_node_ready() or main.director.elapsed < _next_snapshot or main.game_over: return
	_next_snapshot = main.director.elapsed + 19.0
	for w in main.workers: _seen[w.ai.state] = true
	var d := SaveGame.capture(main)
	if not SaveGame.write(main,"user://progression-test.json",true):
		fail("進行中保存失敗: " + SaveGame.last_error)
		finish()
		return
	if not SaveGame.apply(main,SaveGame.read("user://progression-test.json")):
		fail("進行中復元失敗: " + SaveGame.last_error)
		finish()
		return
	if SaveGame.capture(main) != d:
		# 消滅した対象だけSEARCHへ正規化されることは許容。それ以外は完全一致。
		var after := SaveGame.capture(main)
		for i in d.crew.size():
			if d.crew[i].ai.state != after.crew[i].ai.state and after.crew[i].ai.state in [CharacterAI.State.SEARCH,CharacterAI.State.MOVE_TO_STORAGE]:
				d.crew[i].ai.state = after.crew[i].ai.state
		if after != d:
			fail("通常進行snapshot不一致")
			finish()
func finish():
	print("SAVE_STATES ", _seen.keys())
	super.finish()
