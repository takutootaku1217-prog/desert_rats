extends "res://tools/test_artscale.gd"
func _initialize():
 _test_contracts({},1.0,"背景を生成しない既存画像の契約検査")
 print("ASSET_ONLY_FAILURES=",fails)
 quit(1 if fails else 0)
