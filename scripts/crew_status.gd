class_name CrewStatus
extends RefCounted
## 仲間1人のステータスの計算（HP・スタミナ・満腹度・疲労度・精神状態）。データは Worker が持ち、ここは計算だけ。UI は読むだけ。
## 流れ: Worker（データ）→ ここ（増減・疲労度・精神状態の計算）→ 自動行動AI（scripts/character_ai.gd が「休む・食べる」を選ぶ）→ UI（ui/）。
## 数値・基準は、すべて data/crew_status.gd（CrewStatusDB）。ここに数字を直接書かない。
## Worker._process が、毎フレーム tick(w, delta) を呼ぶ（調査隊に出ている間は呼ばれない＝ステータスは止まる）。


static func tick(w, delta: float) -> void:
	_tick_stamina(w, delta)
	_tick_hunger(w, delta)
	_tick_fatigue(w, delta)
	_tick_hp(w, delta)
	_tick_mental(w, delta)


## 休憩の回復の倍率。ベッドで眠っている = 1.0、その場での簡易休憩 = REST_IN_PLACE_RATE、休んでいない = 0
static func rest_factor(w) -> float:
	if w.sleeping:
		return 1.0
	if w.resting:
		return CrewStatusDB.REST_IN_PLACE_RATE
	return 0.0


# ------------------------------------------------------------------
# スタミナ（以前の「元気」）。増減の数字は以前と同じ（酷暑などの疲れやすさ・食堂・医務室の効果もそのまま）。
# ------------------------------------------------------------------
static func _tick_stamina(w, delta: float) -> void:
	var g = w.game
	var rf := 1.0 if w.down else rest_factor(w)
	if rf > 0.0:                                                # 眠っている・その場で休んでいる・倒れている間は回復する
		# 車体が傷んでいると（居住区が傷んで）よく休めない
		var rec := CrewStatusDB.STAMINA_REST_RATE if g.base.condition(GameData.Part.HULL) >= GameData.PART_BAD else CrewStatusDB.STAMINA_REST_RATE_HULL_BAD
		rec *= 1.0 + g.room_effect("rest_rate")                 # 医務室（部屋の変更。data/rooms.gd）で回復が早くなる
		w.stamina = minf(CrewStatusDB.MAX_STAMINA, w.stamina + rec * rf * delta)
	elif w.ai.state == CharacterAI.State.IDLE:
		w.stamina = maxf(0.0, w.stamina - CrewStatusDB.STAMINA_DRAIN_IDLE * g.director.energy_mult() * (1.0 - g.room_effect("drain_cut")) * delta)
	else:
		# 酷暑などで疲れやすくなる。食堂で減る
		w.stamina = maxf(0.0, w.stamina - CrewStatusDB.STAMINA_DRAIN_ACTIVE * g.director.energy_mult() * (1.0 - g.room_effect("drain_cut")) * delta)


# ------------------------------------------------------------------
# 満腹度。時間で減る（天候の「食料の減り」の倍率が掛かる）。回復は食事（eat）だけ。
# ------------------------------------------------------------------
static func _tick_hunger(w, delta: float) -> void:
	var g = w.game
	w.hunger = maxf(0.0, w.hunger - CrewStatusDB.HUNGER_DECAY_PER_MIN / 60.0 * g.director.food_mult() * delta)


## 食事をとる。食料アイテムごとの効果（CrewStatusDB.FOOD_EFFECTS）を、満腹度・疲労度・ストレスへ反映する。
static func eat(w, item: int) -> void:
	var fx: Dictionary = CrewStatusDB.FOOD_EFFECTS.get(item, {})
	w.hunger = clampf(w.hunger + float(fx.get("hunger", 0.0)), 0.0, CrewStatusDB.MAX_HUNGER)
	w.fatigue = clampf(w.fatigue + float(fx.get("fatigue", 0.0)), 0.0, CrewStatusDB.MAX_FATIGUE)
	w.stress = maxf(0.0, w.stress + float(fx.get("stress", 0.0)))


## 自分から食事に向かうほど空腹か
static func wants_to_eat(w) -> bool:
	return w.hunger < CrewStatusDB.EAT_BELOW


## 仕事や休憩より先に食べる（加工などを中断してでも）ほど空腹か
static func needs_to_eat_now(w) -> bool:
	return w.hunger < CrewStatusDB.EAT_URGENT_BELOW

# ------------------------------------------------------------------
# 疲労度（高いほど悪い）。仕事や移動を続けると溜まり、眠ると下がる。待機中は変わらない。
# スタミナ・満腹度・HP が低い状態で動き続けると、溜まりが速くなる（3つのうち、いちばん大きい倍率だけ）。
# ------------------------------------------------------------------
static func _tick_fatigue(w, delta: float) -> void:
	var g = w.game
	if w.down:
		w.fatigue = maxf(0.0, w.fatigue - CrewStatusDB.FATIGUE_DOWN_RATE * delta)
	elif rest_factor(w) > 0.0:
		w.fatigue = maxf(0.0, w.fatigue - CrewStatusDB.FATIGUE_REST_RATE * (1.0 + g.room_effect("rest_rate")) * rest_factor(w) * delta)
	elif w.ai.state != CharacterAI.State.IDLE:
		var m := maxf(_low_mult(CrewStatusDB.FATIGUE_MULT_STAMINA, w.stamina),
				maxf(_low_mult(CrewStatusDB.FATIGUE_MULT_HUNGER, w.hunger), _low_mult(CrewStatusDB.FATIGUE_MULT_HP, w.hp)))
		w.fatigue = minf(CrewStatusDB.MAX_FATIGUE, w.fatigue + CrewStatusDB.FATIGUE_GAIN_ACTIVE * m * g.director.energy_mult() * delta)


## 表 [[基準の値, 倍率], ...]（小さい基準から）で、値 < 基準 の最初の行の倍率。どれにも当たらなければ 1.0
static func _low_mult(table: Array, value: float) -> float:
	for row in table:
		if value < float(row[0]):
			return float(row[1])
	return 1.0


# ------------------------------------------------------------------
# HP。眠っている間に回復する（医務室で早い）。0 になると戦闘不能（死亡ではない）。倒れている間も、ゆっくり回復して起き上がる。
# ------------------------------------------------------------------
static func _tick_hp(w, delta: float) -> void:
	var g = w.game
	if w.down:
		w.hp = minf(CrewStatusDB.MAX_HP, w.hp + CrewStatusDB.HP_DOWN_RATE * delta)
		if w.hp >= CrewStatusDB.HP_REVIVE_AT:
			w.down = false                                          # 起き上がる（AI が探し直す）
	elif rest_factor(w) > 0.0:
		w.hp = minf(CrewStatusDB.MAX_HP, w.hp + CrewStatusDB.HP_REST_RATE * (1.0 + g.room_effect("rest_rate")) * rest_factor(w) * delta)


## ダメージを受ける（敵の攻撃・狩りの事故・出来事）。stress_gain はそのときのストレス。HP が 0 になったら戦闘不能。
## 調査隊に出ている間・すでに倒れているときは受けない。
static func damage(w, amount: float, stress_gain := 0.0) -> void:
	if w.away or w.down:
		return
	w.hp = maxf(0.0, w.hp - amount)
	w.stress += stress_gain
	if w.hp <= 0.0:
		w.down = true
		w.ai.on_down()


## 狩りで獲物を倒したときの事故（確率で、少しケガをする）。表は CrewStatusDB.HUNT_INJURY
static func hunt_injury(w, species: String) -> void:
	var row: Array = CrewStatusDB.HUNT_INJURY.get(species, [])
	if row.is_empty() or randf() >= float(row[0]):
		return
	damage(w, randf_range(float(row[1]), float(row[2])), CrewStatusDB.RAID_HIT_STRESS * 0.5)


# ------------------------------------------------------------------
# 精神状態。疲労度を中心に、満腹度・HP・ストレスから計算される状態（独立した数値ではない）。
# 好調の条件（疲れておらず、空腹でなく、健康で、ストレスが小さい）が CALM_SECONDS 続くと「好調」になる。
# ------------------------------------------------------------------
static func _tick_mental(w, delta: float) -> void:
	w.stress = maxf(0.0, w.stress - CrewStatusDB.STRESS_DECAY * delta)
	if _meets_good(w):
		w.calm += delta
	else:
		w.calm = 0.0
	w.mental = mental_of(w)


static func mental_of(w) -> int:
	if _worse_than(w, CrewStatusDB.MENTAL_LIMIT):
		return CrewStatusDB.Mental.LIMIT
	if _worse_than(w, CrewStatusDB.MENTAL_BAD):
		return CrewStatusDB.Mental.BAD
	if _worse_than(w, CrewStatusDB.MENTAL_ANXIOUS):
		return CrewStatusDB.Mental.ANXIOUS
	if w.calm >= CrewStatusDB.CALM_SECONDS:
		return CrewStatusDB.Mental.GOOD
	return CrewStatusDB.Mental.NORMAL


## 表のどれかの基準に達している（疲労度・ストレスは 以上、HP・満腹度は 未満）
static func _worse_than(w, th: Dictionary) -> bool:
	return w.fatigue >= float(th["fatigue"]) or w.stress >= float(th["stress"]) or w.hp < float(th["hp"]) or w.hunger < float(th["hunger"])


static func _meets_good(w) -> bool:
	var th := CrewStatusDB.MENTAL_GOOD
	return w.fatigue < float(th["fatigue"]) and w.stress < float(th["stress"]) and w.hp >= float(th["hp"]) and w.hunger >= float(th["hunger"])

# ------------------------------------------------------------------
# 速度への影響（STEP 7）。悪いステータスは効率を少し落とす。掛け算はせず、いちばん悪いものだけで決める。
# 精神状態は小さな補正: 「不安」以下は、他のステータスより悪いときだけ効く。「好調」は、他が良好なときだけ上乗せ。
# 完全に止まるのは戦闘不能（HP 0）だけ。ほかは、いちばん悪くても作業 0.5・移動 0.6。
# ------------------------------------------------------------------
## ステータス stat の値 value による [作業速度の倍率, 移動速度の倍率]（悪くなければ [1, 1]）
static func _effect(stat: String, value: float) -> Array:
	var e: Dictionary = CrewStatusDB.EFFECTS[stat]
	var high_bad: bool = String(e["dir"]) == "high_is_bad"
	for step in e["steps"]:
		if (high_bad and value >= float(step[0])) or (not high_bad and value < float(step[0])):
			return [float(step[1]), float(step[2])]
	return [1.0, 1.0]


## 作業の速さの倍率（Worker.field_mult が掛ける）
static func work_mult(w) -> float:
	var m := 1.0
	for s in CrewStatusDB.STATS:
		m = minf(m, float(_effect(s, float(w.get(s)))[0]))
	var mm: float = CrewStatusDB.MENTAL_WORK[w.mental]
	if mm < 1.0:
		m = minf(m, mm)
	elif m >= 1.0:
		m = mm                                                       # 好調: ほかが良好なら少し速い
	return m


## 移動の速さの倍率（Worker.current_speed が掛ける）
static func move_mult(w) -> float:
	var m := 1.0
	for s in CrewStatusDB.STATS:
		m = minf(m, float(_effect(s, float(w.get(s)))[1]))
	return m


# ------------------------------------------------------------------
# 自動行動（STEP 8）。仕事の優先度（★0〜5）はそのまま。ここは「仕事より先に休む・食べる」の判断材料。
# 順番: HPがとても低い → 休む／満腹度がとても低い → 食べる／疲労度がとても高い → 休む／スタミナがとても低い → 休む／
#        精神状態が限界 → 休む／満腹度が低い → 食べる。そのあと、いつもの仕事。
# ------------------------------------------------------------------
## いま必要な生活行動を、急ぎの順に並べる（"rest" / "eat"）。実際に行けるか（ベッド・食料・休憩の優先度）は AI が見る。
static func life_needs(w) -> Array:
	var l: Array = []
	if w.hp < CrewStatusDB.REST_HP_URGENT:
		l.append("rest")
	if w.hunger < CrewStatusDB.EAT_URGENT_BELOW:
		l.append("eat")
	if w.fatigue >= CrewStatusDB.REST_FATIGUE_URGENT:
		l.append("rest")
	if w.stamina < CrewStatusDB.REST_STAMINA_URGENT:
		l.append("rest")
	if w.mental == CrewStatusDB.Mental.LIMIT:
		l.append("rest")
	if w.hunger < CrewStatusDB.EAT_BELOW:
		l.append("eat")
	return l


## 休憩に入ってよい状態か（スタミナが減った・疲労度が高い・HPが減っている）。眠っても良くならない状態では入らない（休憩のループ防止）
static func can_rest(w) -> bool:
	return w.stamina < CrewStatusDB.REST_JOB_STAMINA_BELOW or w.fatigue > CrewStatusDB.REST_JOB_FATIGUE_ABOVE or w.hp < CrewStatusDB.REST_JOB_HP_BELOW


## 休憩をやめてよいか。スタミナが戻っても、疲労度・HPが回復するまでは休み続ける
static func rest_done(w) -> bool:
	return w.stamina >= CrewStatusDB.REST_END_STAMINA and w.fatigue <= CrewStatusDB.REST_END_FATIGUE and w.hp >= CrewStatusDB.REST_END_HP


## 危険なほど休みが必要か（加工などの途中でも、基本的に仕事を続けない）
static func rest_critical(w) -> bool:
	return w.hp < CrewStatusDB.REST_HP_CRITICAL or w.fatigue >= CrewStatusDB.REST_FATIGUE_CRITICAL or w.stamina < CrewStatusDB.REST_STAMINA_CRITICAL

# ------------------------------------------------------------------
# 表示のための読み取り（ui/ は、Worker のデータを、ここを通して読むだけ。値は書き換えない）
# ------------------------------------------------------------------
## アイコンゲージに渡す値（0〜100。大きいほど良い側）。疲労度だけは、疲れるほど減る「余力（100 − 疲労度）」で表す
static func gauge_value(w, stat: String) -> float:
	var v: float = float(w.get(stat))
	return CrewStatusDB.MAX_FATIGUE - v if stat == "fatigue" else v


## そのステータスのアイコンが点滅する（危険域）か。点滅はそのアイコンだけ
static func is_blinking(w, stat: String) -> bool:
	var v: float = float(w.get(stat))
	var line: float = CrewStatusDB.BLINK_LINE[stat]
	return v >= line if CrewStatusDB.is_high_bad(stat) else v < line


## 頭上に出す警告。危険ラインに達したステータスのうち、いちばん危険なものを1つだけ（CrewStatusDB.WARN_ORDER の順）。
## 返す: {"stat": ステータス名 or "mental", "strong": 点滅させるほど危険か}。なければ空
static func warning(w) -> Dictionary:
	for s in CrewStatusDB.WARN_ORDER:
		if s == "mental":
			if w.mental == CrewStatusDB.Mental.LIMIT:
				return {"stat": "mental", "strong": true}
			continue
		var v: float = float(w.get(s))
		var line: float = CrewStatusDB.WARN_LINE[s]
		var strong_line: float = CrewStatusDB.WARN_STRONG[s]
		if CrewStatusDB.is_high_bad(s):
			if v >= line:
				return {"stat": s, "strong": v >= strong_line}
		elif v < line:
			return {"stat": s, "strong": v < strong_line}
	return {}