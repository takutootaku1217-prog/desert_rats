extends "res://tools/test_equipment_ui.gd"
func sub(label:String) -> Button:
 return main.navigation.groups[main.navigation.selected].find_children("*","Button",true,false).filter(func(b):return b.text==label)[0]
func shot(name_:String):
 if DisplayServer.get_name()=="headless": return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/workspace/bottom-ui-evidence/"+name_+".png")
func _initialize():
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await frames()
 main.set_process(false)
 for w in main.workers:w.set_process(false)
 var nav=main.navigation
 await shot("normal")
 check(nav.buttons.size()==6 and nav.bar.get_global_rect().end.x<=1280 and nav.bar.get_global_rect().end.y<=720,"6入口が1280x720内")
 check(not main.map_ui._entry.is_visible_in_tree() and not main.ui._button.is_visible_in_tree(),"旧常設入口を集約")
 check(main.status._repair.get_global_rect().end.y<180,"右上はゲージと応急修理に集約")
 var follow=main.follow_target
 await click(nav.buttons["拠点"]);await shot("base-menu")
 check(nav.selected=="拠点" and nav.popup.visible and nav.popup.get_global_rect().end.y<=642,"拠点サブメニューは操作バーの直上")
 await click(nav.buttons["拠点"]);check(not nav.popup.visible,"同じ入口の連打で閉じる")
 await click(nav.buttons["拠点"]);await key(KEY_ESCAPE)
 check(not nav.popup.visible and main.follow_target==follow,"Escでメニューだけ閉じ、追従選択を維持")
 await click(nav.buttons["拠点"]);await mouse(Vector2(700,440),MOUSE_BUTTON_LEFT)
 check(not nav.popup.visible and main.follow_target==follow,"外側クリックはメニューを閉じ、ゲームへ貫通しない")
 await click(nav.buttons["拠点"]);await click(sub("建設 (B)"))
 check(main.build_ui._overlay.visible and not nav.popup.visible and not nav.bar.visible,"建設へ遷移し背後メニューを隠す")
 await key(KEY_F);check(main.craft_ui._overlay.visible and not main.build_ui._overlay.visible,"ショートカットでモーダル切替")
 await key(KEY_ESCAPE);await click(nav.buttons["拠点"]);await click(sub("部屋 (R)"))
 check(main.room_ui._overlay.visible,"部屋入口保持");await key(KEY_ESCAPE)
 await click(nav.buttons["拠点"]);await click(sub("内外装"));await click(sub("戻る"))
 check(nav.selected=="拠点","内外装から戻る");await click(sub("内外装"));await click(sub("外装 (O)"))
 check(main.base_view.mode==BaseView.Mode.EXTERIOR,"外装切替保持");await key(KEY_I)
 await click(nav.buttons["物資"])
 check(main.status._stock.is_visible_in_tree() and main.status._totals.is_visible_in_tree(),"資源一覧と累計は物資内に保持")
 await click(sub("倉庫 (Tab)"));check(main.inventory_ui._overlay.visible,"倉庫入口保持");await key(KEY_ESCAPE)
 await click(nav.buttons["探索"]);await click(sub("採取地点 (G)"));check(main.quarry_ui._overlay.visible,"採取地点保持");await key(KEY_ESCAPE)
 await click(nav.buttons["探索"]);await click(sub("遠征 (X)"));check(main.expedition_ui._overlay.visible,"遠征入口保持");await key(KEY_ESCAPE)
 await click(nav.buttons["仲間"]);check(main.detail._overlay.visible,"仲間管理保持");await key(KEY_ESCAPE)
 await click(nav.buttons["地図"]);check(main.map_ui._overlay.visible and paused,"地図の時間停止保持");await key(KEY_ESCAPE)
 check(not paused and nav.bar.visible,"地図閉鎖で復帰")
 await click(nav.buttons["メニュー"]);await click(sub("運営の方針 (P)"));check(main.policy._overlay.visible,"方針入口保持");await key(KEY_ESCAPE)
 await click(nav.buttons["メニュー"]);await click(sub("保存 / 続きから"))
 check(main.save_ui._overlay.visible and paused,"保存入口保持")
 var repairs:int=main.base.total_repair
 await click(main.status._repair);check(main.base.total_repair==repairs,"モーダル背後へ修理クリックが貫通しない")
 main.save_ui.close();await frames();check(not paused and nav.bar.visible,"保存から戻る")
 main.director.trigger("raid_scorpion")
 await frames()
 check(main.event_hud._panel.get_global_rect().end.x<nav.bar.position.x,"危険通知とバーを重ねない")
 await shot("alert")
 main._game_over();await frames()
 await mouse(Vector2(800,300),MOUSE_BUTTON_LEFT)
 check(main.save_ui.is_open() and paused,"ゲーム終了画面から保存/再開へ進める")
 print("== 結果: %s =="%("すべて成功" if fails==0 else "%d 件失敗"%fails));quit(1 if fails else 0)
