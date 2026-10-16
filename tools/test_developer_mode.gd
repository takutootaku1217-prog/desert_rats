extends "res://tools/test_quarry.gd"
func labels(node:Node)->String:
 var text:=""
 if node is Label or node is Button:text+=node.text+"\n"
 for c in node.get_children():text+=labels(c)
 return text
func _initialize():
 await fresh()
 var ui:PolicyUI
 for c in main.get_children():
  if c is PolicyUI:ui=c
 check(ui!=null,"通常の運営画面を取得")
 var dev:bool=OS.get_cmdline_user_args().has("--developer-mode")
 check(main.developer_mode()==dev,"明示的な起動引数だけで開発者モード判定")
 ui._page=0;ui._rebuild();await process_frame
 check(labels(ui._body).contains("テスト用: 生物を購入")==dev,"通常画面に生物購入を出さない・開発者だけ表示")
 ui._page=2;ui._rebuild();await process_frame
 check(labels(ui._body).contains("テスト用: 道具を倉庫に入れる")==dev,"通常画面に道具投入を出さない・開発者だけ表示")
 var before:Dictionary=main.storage.inventory.counts.duplicate()
 main.test_purchase("hare")
 check((main.storage.inventory.counts!=before)==dev,"購入APIも通常起動では在庫を変更しない")
 var count:int=main.storage.count_of(GameData.Item.PICKAXE)
 main.test_add_tool(GameData.Item.PICKAXE)
 check(main.storage.count_of(GameData.Item.PICKAXE)==count+(1 if dev else 0),"道具投入APIも通常起動では無効")
 var saved:=SaveGame.capture(main)
 check(not saved.has("developer_mode"),"セーブで開発者モードを持ち越さない")
 main.test_purchase("unknown");main.test_add_tool(-999)
 check(SaveGame.capture(main)==saved,"開発用APIも無効IDを拒否")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
