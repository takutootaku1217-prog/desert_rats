extends SceneTree
func _init() -> void:
 var ok:bool = GameData.ITEM_FILES[GameData.Item.BED_PACK] == "bed"
 print("%s bed item uses its dedicated icon, not rolled sleeping bag" % ("ok" if ok else "FAIL"))
 var texture:Texture2D = load("res://assets/resources/item_bed.png")
 var image:Image = texture.get_image()
 ok = ok and image != null and image.get_size() == Vector2i(48,48) and image.get_pixel(0,0).a == 0.0
 print("%s dedicated icon is 48x48 and transparent" % ("ok" if ok else "FAIL"))
 quit(0 if ok else 1)
