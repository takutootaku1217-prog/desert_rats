class_name Department
extends RefCounted
## 部署（分野ごとに1つ）の計算。所属している人数と、所属個体の能力値・ランク・スキルで発展する。
## 数値は data/balance.gd。所属は Worker.dept（-1 = 無所属）で持つので、ここには状態がない。

## 全部署の状態。{分野 -> {members, points, synergy, level, next_points, eff, top_rank}}
static func compute(workers: Array) -> Dictionary:
	var out := {}
	for f in GameData.Field.values():
		out[f] = _one(workers, f)
	return out


static func members_of(workers: Array, field: int) -> Array:
	var m: Array = []
	for w in workers:
		if w.dept == field:
			m.append(w)
	return m


static func level_for_points(points: float) -> int:
	var lv := 1 + int(floor(sqrt(maxf(0.0, points) / Balance.DEPT_POINTS_DIV)))
	return mini(lv, Balance.DEPT_MAX_LEVEL)


static func points_for_level(level: int) -> float:
	return Balance.DEPT_POINTS_DIV * float((level - 1) * (level - 1))


static func _one(workers: Array, field: int) -> Dictionary:
	var m := members_of(workers, field)
	var pts := 0.0
	var top_rank := -1
	var skill_counts := {}
	for w in m:
		var r: int = w.ranks.get(field, 0)
		pts += Balance.DEPT_MEMBER_POINT + w.ability(field) / Balance.DEPT_ABILITY_POINT
		pts += Balance.RANK_DEPT_POINTS[r]
		top_rank = maxi(top_rank, r)
		for s in w.skills:
			skill_counts[s] = skill_counts.get(s, 0) + 1
	# 同じスキルを持つ個体が複数いると相乗効果
	var synergy := 0.0
	for s in skill_counts:
		if skill_counts[s] >= 2:
			synergy += (skill_counts[s] - 1) * Balance.DEPT_SYNERGY_POINT
	pts += synergy
	var lv := level_for_points(pts)
	var eff := 1.0 + Balance.DEPT_EFF_PER_LEVEL * (lv - 1)
	if top_rank > Balance.DEPT_TOP_RANK_BASE:
		eff += Balance.DEPT_TOP_RANK_EFF * (top_rank - Balance.DEPT_TOP_RANK_BASE)
	return {
		"members": m,
		"points": pts,
		"synergy": synergy,
		"level": lv,
		"next_points": points_for_level(lv + 1) if lv < Balance.DEPT_MAX_LEVEL else -1.0,
		"eff": eff,
		"top_rank": top_rank,
	}
