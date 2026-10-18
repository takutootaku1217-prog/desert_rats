extends SceneTree

const Model = preload("res://scripts/two_lane_prototype_model.gd")
var fails := 0

func check(ok: bool, text: String) -> void:
	print("  %s %s" % ["ok" if ok else "FAIL", text])
	if not ok:
		fails += 1

func run_collection(mode: String) -> GroundTwoLanePrototypeModel:
	var model: GroundTwoLanePrototypeModel = Model.new()
	model.reset(mode)
	model.run_for(70.0)
	return model

func _initialize() -> void:
	print("-- 屋外固定レーン試作 --")
	var one := run_collection("one")
	var two := run_collection("two")
	check(one.complete() and two.complete(), "一列/二レーンとも同じ鉄鉱石6個を採取・運搬・スロープ帰還・荷卸しまで完了")
	check(one.delivered == two.delivered and one.remaining_resource() == two.remaining_resource(), "比較条件の総量と残量が一致")
	check(one.lane_changes == 0 and two.lane_changes > 0, "一列は接続なし、二レーンは固定接続部を実際に通過")
	check(two.max_depth_step <= Model.WALK_SPEED * 0.05 + 0.01, "レーン移動は1フレームの歩幅以内で、瞬間移動なし")
	check(two.min_worker_distance >= Model.MIN_SPACING - 0.01, "同一レーンで仲間を重ねず、渋滞を作らない")
	print("  比較時間: 一列 %.2fs / 二レーン %.2fs（最小間隔 %.1f / %.1f px）" % [one.completion_time, two.completion_time, one.min_worker_distance, two.min_worker_distance])
	print("  最接近: 一列 %s / 二レーン %s" % [one.closest_pair, two.closest_pair])
	var combat: GroundTwoLanePrototypeModel = Model.new()
	combat.reset("two")
	check(combat.cross_lane_melee_is_blocked(), "同じxでも別レーンの近接攻撃は命中しない")
	check(combat.start_chase(0), "追跡指示を開始")
	combat.run_for(35.0)
	check(combat.combat_hits == 1 and combat.lane_changes > 0, "追跡は接続部経由で対象レーンへ移動後にのみ命中")
	var retreat: GroundTwoLanePrototypeModel = Model.new()
	retreat.reset("two")
	retreat.run_for(4.0)
	check(retreat.start_personal_retreat(1), "個人退却指示を開始")
	retreat.run_for(35.0)
	check(String(retreat.agents[1]["state"]) == "retreated", "個人退却はスロープ経由で拠点へ帰還")
	check(retreat.retreat_violations == 0, "個人退却中に採取・再戦へ戻らない")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d件失敗" % fails))
	quit(1 if fails else 0)
