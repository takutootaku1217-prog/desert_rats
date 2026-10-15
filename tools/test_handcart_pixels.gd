extends "res://tools/test_artscale.gd"
## 描画ありで実行。生産コードの通常/半透明充填アイコンと装備中の仲間を比較。
## godot --rendering-method gl_compatibility -s res://tools/test_handcart_pixels.gd -- --screenshots=/tmp/cart-pixels
class Icons extends Node2D:
 func _draw():
  GameData.draw_item(self,GameData.Item.HANDCART,Vector2(56,60))
  GameData.draw_item(self,GameData.Item.HANDCART,Vector2(56,124),0.5)
  GameData.draw_item_fill(self,GameData.Item.HANDCART,Vector2(120,60),1.0,0.5)
func rendered(v:SubViewport) -> Image:
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 return v.get_texture().get_image()
func save_picture(img:Image,label:String):
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--screenshots="):img.save_png(arg.trim_prefix("--screenshots=").path_join(label+".png"))
func _initialize():
 if DisplayServer.get_name()=="headless":
  print("FAIL requires a rendering display");quit(1);return
 await _new_game();main.process_mode=Node.PROCESS_MODE_DISABLED
 var viewport:=SubViewport.new();viewport.size=Vector2i(320,180);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 var icons:=Icons.new();icons.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;viewport.add_child(icons)
 var w=main.workers[0];w.reparent(viewport);w.process_mode=Node.PROCESS_MODE_DISABLED
 w.position=Vector2(224,124);w.work_support=GameData.Item.HANDCART;w.carrying=-1;w.carry_bonus.clear();w.sleeping=false;w.down=false;w.selected=false;w._t=0;w.queue_redraw()
 var original:=await rendered(viewport)
 check(not original.is_empty() and original.get_pixel(224,110).a>0,"実際の仲間と装備を空でない画面へ描画")
 save_picture(original,"handcart-native")
 for factor in [2,3]:
  var fixture:=_make_fixture(factor,["items"])
  ArtSpec.set_root_override(fixture);icons.queue_redraw();w.queue_redraw()
  var changed:=await rendered(viewport)
  check(GameData.item_tex(GameData.Item.HANDCART).get_size()==Vector2(24*factor,24*factor),"実際の差し替え画像を使用 x%d"%factor)
  check(original.get_data()==changed.get_data(),"アイコン・充填・仲間の装備の全ピクセル一致 x%d"%factor)
  save_picture(changed,"handcart-x%d"%factor)
  ArtSpec.set_root_override("")
 icons.queue_redraw();w.queue_redraw()
 var restored:=await rendered(viewport)
 check(original.get_data()==restored.get_data(),"原画像へ戻しても全ピクセル一致")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
