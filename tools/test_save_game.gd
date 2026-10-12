extends "res://tools/test_equipment_ui.gd"
const TEST_PATH := "user://save-test.json"
func roundtrip(label: String) -> Dictionary:
	var d := SaveGame.capture(main)
	check(SaveGame.validate(d,main),label + " schema")
	check(SaveGame.write(main,TEST_PATH,true),label + " write " + SaveGame.last_error)
	check(SaveGame.apply(main,SaveGame.read(TEST_PATH)),label + " apply " + SaveGame.last_error)
	var after := SaveGame.capture(main)
	check(d == after,label + " 全持続値・在庫・重量・進捗が一致")
	return d

func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await main.ready
	paused = true
	if OS.get_cmdline_user_args().has("restart"):
		var d := SaveGame.read(TEST_PATH)
		check(not d.is_empty() and SaveGame.apply(main,d),"別プロセスから続き再開")
		check(SaveGame.capture(main) == d,"プロセス再起動後の全持続値一致")
		var left: float = main.expedition.step_left
		main.expedition.tick(0.1)
		check(is_equal_approx(main.expedition.step_left,left-0.1),"再起動後も遠征残り時間から継続")
		print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
		quit(1 if fails else 0)
		return
	for suffix in ["", ".bak", ".damaged", ".tmp"]:
		if SaveGame.exists(TEST_PATH + suffix): DirAccess.remove_absolute(TEST_PATH + suffix)
	roundtrip("初期状態")
	var bytes := FileAccess.get_file_as_bytes(TEST_PATH)
	check(not SaveGame.write(main,TEST_PATH) and FileAccess.get_file_as_bytes(TEST_PATH) == bytes,"未確認上書きを拒否")
	main.base.add_facility("workbench",true)
	main.base.add_facility("cargo_rack",true)
	main.base.add_facility("bed",true)
	main.storage.capacity_bonus = 60
	main.room_layout["u3"] = "infirmary"
	main.base.apply_layout()
	main.storage.inventory.counts = {GameData.Item.WOOD:90}
	main.processor.stock.add(GameData.Item.IRON,1)
	main.processor.current = GameData.recipe_by_id("smelt").duplicate(true)
	main.processor.progress = 1.25
	main.processor.output = [GameData.Item.FOOD]
	main.base.fuel = 75
	main.base.parts[GameData.Part.HULL] = 52.0
	main.director.elapsed = 145.25
	main.director.distance = 4567.5
	main.quarry.select()
	main.quarry._arrive()
	var w = main.workers[0]
	w.weapon = GameData.Item.SIMPLE_SPEAR
	w.ai.state = CharacterAI.State.HAUL_MOVE
	w.ai.haul_recipe = GameData.recipe_by_id("repair_stone").duplicate(true)
	w.carrying = GameData.Item.STONE
	w.carry_source = Inventory.SOURCE_TRANSFER
	w.hp = 43.0; w.fatigue = 55.0; w.hunger = 21.0
	w.position = Vector2(630,GameData.LO_Y)
	var gatherer = main.workers[1]
	gatherer.ai.state = CharacterAI.State.GATHER
	gatherer.ai.res = main.quarry.points[0]
	gatherer.ai.res.remaining = 8
	gatherer.ai.res.work = 0.35
	gatherer.ai.bag_limit = 5
	gatherer.ai.gather_ev = gatherer.gather_eval("vein")
	gatherer.carrying = GameData.Item.IRON_ORE
	gatherer.carry_n = 4
	gatherer.position = main.quarry.points[0].position
	gatherer.floor_i = 0
	var sleeper = main.workers[2]
	sleeper.ai.state = CharacterAI.State.REST
	sleeper.bed_index = 0
	sleeper.fatigue = 60.0
	main.quarry.visit_generated = {GameData.Item.IRON_ORE:4}
	main.quarry.loose = {GameData.Item.STONE:2}
	main.request_build("supply_cache")
	var complex := roundtrip("加工・運搬・採取・就寝・装備・部屋")
	check(main.processor.incoming.size() == 1 and main.base.beds[0] == sleeper and main.quarry.points[0].claimed_by == gatherer,"参照と予約を再構築")
	for i in 3: roundtrip("繰返し保存 %d" % i)
	check(main.processor.progress == 1.25 and main.quarry.points[0].work == 0.35 and w.hp == 43,"繰返しで加工・採取・回復が進まない")
	main.quarry.request_departure()
	roundtrip("帰還中")
	# 継続したら時間を消費して初めて回復。保存時点で回復させない。
	var hp: float = sleeper.hp
	sleeper._process(0.1)
	check(sleeper.fatigue < 60.0 and sleeper.hp >= hp,"復元後に通常の休憩が進行")
	# 満載でも容量判定で既存物資を落とさない。
	main.storage.inventory.counts[GameData.Item.WOOD] += 20
	roundtrip("容量を超える既存所有物も欠損なく保持")
	main.storage.inventory.counts[GameData.Item.WOOD] -= 20
	# 生活行動の所有物・残り秒数と予約。
	gatherer.ai.res = null
	gatherer.ai.state = CharacterAI.State.EAT
	gatherer.ai.timer = 0.45
	gatherer.carrying = GameData.Item.FOOD
	gatherer.carry_n = 1
	w.ai.state = CharacterAI.State.REPAIR_MOVE
	w.ai.haul_recipe = {}
	w.ai.repair_part = GameData.Part.HULL
	w.carrying = GameData.Item.REPAIR_KIT
	roundtrip("食事・修理運搬")
	check(main.base.repair_reserved[GameData.Part.HULL] == w,"修理予約復元")
	w.ai.state = CharacterAI.State.REFUEL
	w.ai.timer = 0.25
	w.ai.haul_item = GameData.Item.FUEL
	w.carrying = GameData.Item.FUEL
	roundtrip("補給中")
	check(main.base.refuel_reserved,"補給予約復元")
	var loose_node := ResourceNode.new()
	loose_node.game = main
	loose_node.item = GameData.Item.WOOD
	main.resources_root.add_child(loose_node)
	w.ai.state = CharacterAI.State.MOVE_TO_RESOURCE
	w.ai.res = loose_node
	w.ai.bag_limit = 5 # 過去の採取袋の値は単品拾いに引き継がない
	w.carrying = -1
	main.quarry.points[0].work = 1.35 # 遅いフレームの端数も切り捨てない
	roundtrip("地面の単品予約・1単位を超える蓄積進捗")
	check(w.ai.res.reserved == 1 and main.quarry.points[0].work == 1.35,"単品は1個だけ予約・採取進捗維持")
	# 遠征は関門・残り時間・参加者・所持修理板を保持し、報酬を再付与しない。
	main.quarry.state = "parked"
	main.storage.store_owned(GameData.Item.FOOD,10)
	main.storage.store_owned(GameData.Item.REPAIR_KIT,1)
	main.expedition.offer(ExpeditionDB.SITES.keys()[0])
	check(main.expedition.start([w],"normal",true),"遠征fixtureを正規APIで出発")
	roundtrip("遠征中")
	check(main.expedition.party[0] == w and w.away,"遠征参加者の参照復元")
	var before := SaveGame.capture(main)
	var invalid := before.duplicate(true)
	invalid.inventory[GameData.Item.WOOD] = -1
	check(not SaveGame.apply(main,invalid) and SaveGame.capture(main) == before,"負の在庫は適用前に拒否")
	invalid = before.duplicate(true); invalid.crew[0].res = 999
	check(not SaveGame.apply(main,invalid) and SaveGame.capture(main) == before,"不正な参照を適用前に拒否")
	invalid = before.duplicate(true); invalid.weight += 1
	check(not SaveGame.apply(main,invalid) and SaveGame.capture(main) == before,"重量不一致を拒否")
	check(not SaveGame.write(main,"user://missing-parent/save.json",true),"書込先不存在を拒否")
	bytes = FileAccess.get_file_as_bytes(TEST_PATH)
	DirAccess.make_dir_absolute(TEST_PATH + ".bak.tmp")
	check(not SaveGame.write(main,TEST_PATH,true) and FileAccess.get_file_as_bytes(TEST_PATH) == bytes,"バックアップ書込失敗でも主保存維持")
	DirAccess.remove_absolute(TEST_PATH + ".bak.tmp")
	var envelope = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	envelope.sha256 = "invalid"
	var bad_hash := FileAccess.open(TEST_PATH + ".hash",FileAccess.WRITE)
	bad_hash.store_string(JSON.stringify(envelope)); bad_hash.close()
	check(SaveGame.read(TEST_PATH + ".hash").is_empty(),"内容ハッシュ不一致を拒否")
	var backup := FileAccess.get_file_as_bytes(TEST_PATH + ".bak")
	var f := FileAccess.open(TEST_PATH,FileAccess.WRITE); f.store_string("broken"); f.close()
	check(SaveGame.read(TEST_PATH).is_empty() and not SaveGame.read(TEST_PATH + ".bak").is_empty(),"破損時はバックアップ読込可能")
	f = FileAccess.open(TEST_PATH,FileAccess.WRITE); f.store_string('{"version":1,"crew":[{}]}'); f.close()
	check(SaveGame.read(TEST_PATH).is_empty(),"旧形式を推測で変換しない")
	check(SaveGame.write(main,TEST_PATH,true) and SaveGame.exists(TEST_PATH + ".damaged") and FileAccess.get_file_as_bytes(TEST_PATH + ".bak") == backup,"旧形式を別保全して新保存・有効バックアップ維持")
	# OS.execute は別Godotプロセス。テスト専用user://だけを使用。
	var output := []
	var code := OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"-s","res://tools/test_save_game.gd","--","restart"],output,true)
	for line in output: print(line)
	check(code == 0,"別プロセス終了コード成功")
	check(complex.processor.progress == 1.25,"snapshotは復元先と共有されない")
	print("== 結果: %s ==" % ("すべて成功" if fails == 0 else "%d 件失敗" % fails))
	quit(1 if fails else 0)
