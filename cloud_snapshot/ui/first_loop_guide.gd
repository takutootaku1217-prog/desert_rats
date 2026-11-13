extends RefCounted
## Read-only help. Current counts and recorded successful actions are separate.

static func snapshot(game) -> Dictionary:
	var state := {
		"mode": "current_state", "supported": game.world.first_region(),
		"location": game.world.status_text(), "workbench": game.has_facility("workbench"),
		"town_ready": game.town.entry_reason().is_empty(),
		"at_quarry": game.world.active and game.world.region == "c_quarry" and game.world.phase == "stopped",
		"hunted": game.total_hunted, "frame_equipped": 0, "mining_equipped": 0,
		"frame_stock": game.storage.count_of(GameData.Item.HAUL_FRAME),
		"wood": game.storage.count_of(GameData.Item.WOOD), "stone": game.storage.count_of(GameData.Item.STONE),
		"ore": game.storage.count_of(GameData.Item.IRON_ORE), "iron": game.storage.count_of(GameData.Item.IRON),
		"hide": game.storage.count_of(GameData.Item.HIDE), "food": game.storage.count_of(GameData.Item.FOOD),
		"repair": game.storage.count_of(GameData.Item.REPAIR_KIT), "fuel": game.base.fuel,
		"sections": [], "history":game.world.guide_progress.duplicate(true), "next_step": {}, "preparation":{"visible":false},
	}
	for worker in game.workers:
		if int(worker.work_support) == GameData.Item.HAUL_FRAME: state.frame_equipped += 1
		if int(worker.tools.get("mine", -1)) >= 0: state.mining_equipped += 1
	if not state.supported:
		state.sections = [{"title": "第一地域 A〜D 用の手引き", "body": "現在は別の地図です。この周回の案内は適用しません。移動先は既存の地図で確認してください。\n現在: " + str(state.location)}]
		return state
	state.preparation = preparation_snapshot(game, state)
	var town_status: String = "街を利用できます" if state.town_ready else (game.world.ready_reason() if game.town.location_ok() else "A に停車し、全員と荷物の帰還後に街へ")
	state.sections = [
		{"title": "1 まずは 木材 → 採掘具 → 石 → 修理材", "body":
			"停車中に木材を採取。作成でワークベンチを建設し、木製採掘具を作って仲間に装備します。石を採取できたら、応急修理板（石＋木材）を作れます。作成画面の不足素材から採取先を確認できます。\n現在の倉庫: 木材 %d / 石 %d / 応急修理板 %d\nワークベンチ: %s / 採掘具の装備者: %d人" % [state.wood, state.stone, state.repair, "設置済み" if state.workbench else "未設置", state.mining_equipped]},
		{"title": "2 次に試せる周回: 移動と車上狩猟（任意）", "body":
			"移動で C を選び、経由地・停車予約・燃料見込みを確認して出発。A → B → C が基本の行き方です。走行中は左上の「車上狩猟」で対象を1体依頼できます。勝手には狩らず、徒歩採取は停車後です。生肉は作成の料理で食料にします。\n現在: %s\nタンク燃料 %.1f / 倉庫の食料 %d / 累計狩猟 %d体（この周回だけの記録ではありません）" % [state.location, state.fuel, state.food, state.hunted]},
		{"title": "3 C で採取・運搬", "body":
			"C 到着時に「採掘地に入る」を選択。入口の車体は固定で、クォータービューの採掘役と運搬役が中継を使います。鉄鉱石に備えて石のハンマーなどを用意し、仲間の装備を確認してください。「経路案内図」で背負いの段差近道と手押し車の迂回を確認できます。\n現在: %s / 倉庫の鉄鉱石 %d（産地・採取達成の判定ではありません）" % ["C に停車中" if state.at_quarry else "C 以外、または移動中", state.ore]},
		{"title": "4 荷物を確定して街へ戻る", "body":
			"現地の「帰還準備」で全員と荷物を集め、「帰還→横視点」で搬入を確定します。その後、移動で A を選び、停車後に「拠点・街 → 街に入る」。購買店では資源の売却や必要品の購入ができます。\n現在の街利用: %s\nB–D の倒木近道は開通するまで通れません。地図で通れる経路を確認してください。" % town_status},
		{"title": "5 持ち帰った物で製作・装備", "body":
			"強化の例は背負いフレーム。ワークベンチで木材・皮・鉄から作り、「仲間」の装備画面で仕事補助に持たせます。鉄鉱石は鉄そのものではなく、作成の精錬が必要です。精錬はタンク燃料も使います。材料不足や運搬待ちは既存の作成画面で確認できます。\n現在の倉庫: 木材 %d / 皮 %d / 鉄 %d\n背負いフレーム: 倉庫 %d / 装備中 %d人（製作した履歴を示すものではありません）" % [state.wood, state.hide, state.iron, state.frame_stock, state.frame_equipped]},
		{"title": "6 次の遠征を楽にする改善（任意）", "body":
			"B/Dの保管庫は自分の備蓄、DのNPC給油所は資源とCrで復旧する有料給油です。Aの売買・修理・給油も引き続き使えます。Cの手押し車近道やA–B整地は運搬・移動を改善します。段差は背負い用で、車体の停車場所は変わりません。\n地域突破に必要なのは独立ボスの撃破・帰還確定とB–Dの倒木処理だけです。施設復旧・全舗装・前哨地の戦闘検証は必須ではありません。橋の修理・補強やドリル開拓はこの試遊版には未実装です。"},
		{"title": "保存してから終える", "body":
			"通常Cの採掘中・ボス挑戦中も「保存 → 手動で保存 → 実行する」で途中保存できます。再開時は一時停止し、戦闘・救助も続きから再開します。途中保存は荷物や撃破の帰還確定ではありません。前哨地の専用検証など一部の任意モードは途中保存非対応です。帰還確定後は通常保存でき、A の街へ戻ると補給もできます。画面を開くだけでは保存されません。終了時の自動保存・オフライン進行はありません。A から出発を決めた時に、出発前の状態を専用checkpointへ保存します。作成に失敗した場合は出発しません。手動保存とは別枠で、敗北後も保存画面から戻れます（所持金の10%控除）。"},
	]
	var goal:Dictionary=game.world.region_goal_snapshot()
	state.sections.push_front({"title":goal.title,"body":goal.text+"\n"+goal.detail+"\nボス・HP72・B–D条件は調整用の暫定仕様です。"})
	var records:PackedStringArray=[]
	for event in WorldTrip.GUIDE_EVENT_LABELS:
		var mark:String="記録済み" if state.history.completed.get(event,false) else "未記録"
		records.append(mark+"："+WorldTrip.GUIDE_EVENT_LABELS[event])
	state.sections.push_front({"title":"実際に成功した操作の記録", "body":"この版で記録した操作だけを表示します。旧保存の過去の達成は推定しません。各記録は別々の操作で、同じ材料の由来や順番どおりの一周を証明するものではありません。現在の所持数は下の案内で別に確認できます。\n"+"\n".join(records)})
	state.next_step = recommendation(game, state)
	if state.next_step.id == "town_upgrade":
		state.sections.push_front({"title":"先に地域目標へ進むなら", "body":regional_recommendation(game, goal).body})
	if state.preparation.visible:
		state.sections.push_front({"title":"A帰還後の遠征準備（任意）", "body":state.preparation.body})
	state.sections.push_front({"title":"次の一手（任意）: " + state.next_step.title, "body":state.next_step.body + "\nこれは現在の状態からの提案です。順番を強制するものではありません。"})
	return state

static func recommendation(game, state: Dictionary) -> Dictionary:
	# No quest flags or inferred achievements. Existing state remains authority.
	if state.food == 0:
		return {"id":"food", "title":"食料を補充しよう", "body":"倉庫の食料が0です。Aで停車して全員が戻ったら「拠点・街 → 街に入る → 購買店」で購入できます。生肉があれば「作成 → 料理」で食料に加工できます。満腹度はAでも進むので、席を離れるときは保存画面を開いて一時停止してください。"}
	var goal: Dictionary = game.world.region_goal_snapshot()
	if goal.completed:
		return {"id":"free_play", "title":"地域突破後の設備回収", "body":goal.text + "\n" + game.world.salvage_status() + "\n" + game.world.depot_status() + "\n" + goal.detail + "\n席を離れる前に保存し、一時停止してください。"}
	if goal.boss_returned or goal.route_connected:
		return regional_recommendation(game, goal)
	if not state.workbench:
		if game.build_pending("workbench") > 0:
			return {"id":"workbench_wait", "title":"作業台は依頼済み。材料と作業を確認", "body":"「作成 → 建設」で不足材料や作業待ちを確認できます。画面を閉じると仲間が採取・搬入・組み立てを進めます。この手引きを読んでいる間は一時停止しています。"}
		return {"id":"workbench", "title":"まずは「作成」で作業台を建てよう", "body":"停車中の木材採取から始めます。「作成」でワークベンチを依頼してください。必要な木材は%d個です。依頼後は画面を閉じ、仲間の搬入・組み立てを待ちます。" % int(FacilityDB.def("workbench").cost.get(GameData.Item.WOOD, 0))}
	if state.mining_equipped == 0:
		return {"id":"mining_tool", "title":"採掘具を用意して仲間の装備を確認", "body":"「作成 → 道具」で木製採掘具を用意し、「仲間」で装備を確認してください。製作を依頼済みなら完了を待ちます。石が集まったら石のハンマーを用意すると鉄鉱石も狙えます。"}
	var completed: Dictionary = state.history.get("completed", {})
	if completed.get("quarry_returned", false) and not completed.get("returned_a", false):
		return {"id":"return_a", "title":"荷物を持ってAへ帰り、売買・補給", "body":"「移動」でAへ。停車して全員が戻ったら「拠点・街 → 街に入る」。購買店で余った資源を売り、食料を補充し、車両ヤードで給油できます。現在の所持数と価格を見て必要な分だけ取引してください。"}
	if not completed.get("quarry_returned", false):
		if state.at_quarry:
			return {"id":"enter_c", "title":"「採掘地に入る」でCの採取へ", "body":"通常の採掘入口から入ります。選択画面を閉じた後は「移動 → Cの入場選択を開く」で開き直せます。帰るときは「帰還準備」で全員と荷物を集め、「帰還→横視点」で持ち帰りを確定してください。独立ボス挑戦は準備後の目標です。"}
		return {"id":"visit_c", "title":"「移動」でCを選び、採取に出発", "body":"A → B → Cが基本の行き方です。地図で経路と燃料見込みを確認して出発します。車上狩猟は任意です。Cに着いたら「採掘地に入る」を選びます。"}
	if state.preparation.visible and state.town_ready and (state.frame_equipped == 0 or state.preparation.armor_status != "installed"):
		return {"id":"town_upgrade", "title":"回収品で強化・補給しよう", "body":"下の遠征準備と画面下のボタンから、加工・装備・補給へ進めます。強化は任意です。先に地域目標（ボス撃破・帰還確定＋B–D開通）へ進む場合は地図へ。具体的な残りの操作も下に案内しています。"}
	return regional_recommendation(game, goal)

static func preparation_snapshot(game, state: Dictionary) -> Dictionary:
	# Current ownership only. Never open/invalidate a preview or infer old actions.
	var kit := GameData.Item.ARMOR_PLATE_KIT
	var available: int = game.warehouse_discard_available(kit)
	var stored: int = game.storage.count_of(kit)
	var installed: String = str(game.base.vehicle_loadout.armor)
	var status: Dictionary = game.processor.manual_status("armor_plate_kit")
	var returning: int = game._queued_transfer(kit, "to_storage")
	var parked: int = maxi(0, game.workshop_count(kit) - returning)
	var waiting: int = int(status.queued) + game.processor.pending_of(kit) + returning
	var min_hp := 100.0
	for worker in game.workers:
		if worker.carrying == kit: waiting += int(worker.carry_n)
		waiting += int(worker.carry_bonus.get(kit, 0))
		min_hp = minf(min_hp, worker.hp)
	var stage := "craft"
	var armor_help := "「鉄板を製作」で素材・不足分の入手先を確認。鉄鉱石は先に精錬して鉄にします。"
	if installed != "none":
		stage = "installed"
		armor_help = "装着済み（%s）。交換・取り外しは未対応で、既存装甲を保持します。" % str(VehicleLoadout.part("armor", installed).get("name", installed))
	elif available > 0:
		stage = "compare"
		armor_help = "未予約のキットがあります。「装甲画面」の鉄板で比較し、積載等の条件を確認して確定。表示だけでは装着しません。"
	elif stored > 0:
		stage = "reserved"
		armor_help = "倉庫のキットは予約中です。搬送依頼を確認し、未予約の倉庫在庫になるまで装着できません。"
	elif parked > 0:
		stage = "workshop"
		armor_help = "作業場にキットがあります。「所持品 → 作業場 → 倉庫へ戻す」で運搬を依頼してください。閉じて待つだけでは倉庫へ戻りません。"
	elif waiting > 0:
		stage = "waiting"
		armor_help = "製作・運搬・収納待ちです。「鉄板を製作」で進み具合を確認し、画面を閉じて作業を進めます。追加注文は不要です。"
	var completed: Dictionary = state.history.get("completed", {})
	var visible: bool = game.world.phase == "stopped" and game.world.region == "a_start" and bool(completed.get("quarry_returned", false))
	var smelt: Dictionary = game.processor.manual_status("smelt")
	var body := "現在の倉庫：鉄鉱石 %d / 鉄 %d / 皮 %d\n「精錬」は鉄鉱石を鉄に加工し、タンク燃料を使います。依頼済み %d / 加工中 %d / 完成品未回収 %d。\n鉄板装甲：%s\nキット：倉庫 %d / 未予約 %d。装甲は左右共通で車体の被害を軽減し、仲間のHPを回復・強化する装備ではありません。\n背負いフレーム：倉庫 %d / 装備中 %d人。「フレーム」で製作し、収納後に「仲間・装備」で仕事補助へ。\n補給：食料 %d / タンク %.1f / 所持金 %d Cr / 仲間の最少HP %.0f。\n「街・補給」で余剰を売却し、食料・燃料を購入、ヤードで給油・修理。仲間の食事・休憩も確認してから地図で次の行先を選びます。\n%s\nここは現在の状態で、今回製作した履歴ではありません。装甲・フレーム・施設復旧はボスやB–D開通の必須条件ではありません。" % [state.ore,state.iron,state.hide,int(smelt.queued)+int(smelt.loaded),smelt.active,smelt.output,armor_help,stored,available,state.frame_stock,state.frame_equipped,state.food,state.fuel,game.town.credits,min_hp,"街を利用できます。" if state.town_ready else "街は仲間と荷物の帰還・荷卸し後に利用できます。案内から勝手に呼び戻しません。"]
	return {"visible":visible,"armor_status":stage,"armor_available":available,"armor_stock":stored,"ore":state.ore,"iron":state.iron,"food":state.food,"body":body}

static func regional_recommendation(game, goal: Dictionary) -> Dictionary:
	# Optional road-first suggestion, never an unlock or a new quest condition.
	# Reuse the actual payment cost and reservation-aware inventory authority.
	if not goal.route_connected:
		var costs: PackedStringArray = []
		var missing := false
		for item in WorldTrip.REGION_A_CLEAR_COST:
			var need: int = int(WorldTrip.REGION_A_CLEAR_COST[item])
			var available: int = game.warehouse_discard_available(item)
			var shortage := maxi(0, need - available)
			missing = missing or shortage > 0
			costs.append("%s %d/%d%s" % [GameData.ITEM_NAMES[item], available, need, "（不足%d）" % shortage if shortage > 0 else ""])
		var local: bool = game.world.phase == "stopped" and game.world.region in ["b_forest", "d_yard"]
		var body: String = "採石場の主は撃破・帰還確定済み。残る目標はB–Dの再接続です。" if goal.boss_returned else "次はB–Dの倒木近道を開くと、往復の経路が増えます。ボスから先に挑んでも構いません。"
		body += "\n開通材料：車両在庫（予約分を除く）/必要数\n" + " / ".join(costs)
		if missing:
			body += "\n不足分は停車中の木材・石材採取で集めます。石には採掘具が必要です。倉庫にあっても建設・搬送に予約した分は使えないので、作業の完了を待つか依頼を見直してください。"
		body += "\nBまたはDに停車し、全員と荷物が帰還したら「移動 → 土地利用・地点保管 → B–D倒木近道の処理を確認」。費用を見て「この計画を実行」で開通します。保管庫がある時は保管欄を下へスクロールしてください。"
		body += "\n表示値は調整用の暫定費用です。施設復旧・A–B整地・橋の修理はこの目標の条件ではありません。"
		return {"id":"route_materials" if missing else ("route_open" if local else "route_travel"), "title":"B–D開通の材料を集めよう" if missing else ("地図でB–Dの倒木を処理しよう" if local else "BまたはDへ、近道を開こう"), "body":body}
	var at_quarry: bool = game.world.phase == "stopped" and game.world.region == "c_quarry"
	var weapon_category: String = CraftDB.entry_of("simple_spear").cat
	var reopen_help := "\nCに停車中、入口を閉じた後や帰還後は「移動 → Cの入場選択を開く」で選択画面へ戻れます。"
	return {"id":"boss_enter" if at_quarry else "boss_prepare", "title":"Cの独立ボス入口へ" if at_quarry else "補給・装備を整えてCのボスへ", "body":
		"B–Dは開通済み。残る目標は採石場の主の撃破・帰還確定です。\n食料・燃料・HPを確認し、「仲間」で護衛にする人の武器を確認。武器の例は「作成 → %s」の簡易槍です。材料が足りなければ通常採取へ戻れます。背負いフレームは運搬用で、武器や必須条件ではありません。\n「移動」でCへ。C入口の「採石場の主に挑む（地域目標）」が独立ボスです。「危険な前哨地・戦闘検証」とは別です。現地で護衛を担当させ、負傷が増えたら「帰還準備」で撤退。戦闘不能者は手動救助の案内を確認してください。\n撃破だけでは確定しません。全員と荷物を入口へ戻し「帰還→横視点」で確定してから保存します。施設復旧や全舗装は不要です。" % weapon_category + reopen_help}
