class_name ResourceNode
extends Node2D
## 砂漠に落ちている回収対象の物資。拠点が進むにつれて右から現れ、左へ流れていく。
## （物資自体が動いているのではなく、世界が相対的にスクロールしている表現）

const GATHER_TIME := 0.9

var game
var item: int = GameData.Item.WOOD
var species := ""       # item が獲物（CARCASS）のときの生物の種類
var claimed_by = null   # 回収予約している Worker
var gather_progress := 0.0
var age := 0.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	age += delta
	position.x -= game.scroll_speed * delta
	if position.x < -60.0:
		queue_redraw()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var snap := ((position / 4.0).round() * 4.0) - position
	# 影
	draw_rect(Rect2(snap + Vector2(-24, -8), Vector2(48, 8)), Color(0.35, 0.22, 0.1, 0.35))
	draw_rect(Rect2(snap + Vector2(-16, -12), Vector2(32, 4)), Color(0.35, 0.22, 0.1, 0.25))
	if item == GameData.Item.CARCASS:
		GameData.draw_creature(self, species, 0, snap, 1.0, true)
	else:
		GameData.draw_item(self, item, snap + Vector2(0, -28), 1.0)
	if claimed_by == null:
		# 見つけてもらうまで小さな目印を点滅
		if int(age * 4.0) % 2 == 0:
			var y := snap.y - 66.0
			draw_rect(Rect2(snap.x - 8, y, 16, 4), Color("ffe36a"))
			draw_rect(Rect2(snap.x - 4, y + 4, 8, 4), Color("ffe36a"))
	if gather_progress > 0.0:
		var r := clampf(gather_progress / GATHER_TIME, 0.0, 1.0)
		draw_rect(Rect2(snap + Vector2(-24, 4), Vector2(48, 8)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(snap + Vector2(-20, 6), Vector2(40.0 * r, 4)), Color("7be07b"))
	var label: String = GameData.ITEM_NAMES[item]
	if item == GameData.Item.CARCASS:
		label = "獲物（%s）" % GameData.CREATURES[species]["name"]
	GameData.draw_text(self, snap + Vector2(0, -72), label, 12, Color("fff7dc"), 150.0)
