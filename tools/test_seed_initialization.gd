extends SceneTree
## 初期生成前のseed注入を検査。ゲームtickなしの全保存状態を3回ずつ比較する。
func _initialize():
 var all_equal:=true
 for chosen_seed in [501,502,503]:
  var fingerprints:Array=[]
  for repeat in 3:
   seed(chosen_seed)
   var main=load("res://scenes/main.tscn").instantiate()
   main.process_mode=Node.PROCESS_MODE_DISABLED
   main.set_meta("diagnostic_seed",chosen_seed)
   root.add_child(main)
   if not main.is_node_ready(): await main.ready
   var serialized=JSON.stringify(SaveGame.capture(main))
   fingerprints.append(serialized.sha256_text())
   print("INITIAL seed=",chosen_seed," repeat=",repeat," hash=",fingerprints[-1]," state=",serialized)
   main.queue_free()
   await process_frame
  var equal=fingerprints[0]==fingerprints[1] and fingerprints[1]==fingerprints[2]
  all_equal=all_equal and equal
  print("INITIAL_EQUAL seed=",chosen_seed," ",equal)
 print("== 結果: %s ==" % ("すべて成功" if all_equal else "初期生成不一致"))
 quit(0 if all_equal else 1)
