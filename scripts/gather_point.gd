class_name GatherPoint
extends ResourceNode
## 採取ポイント（岩場・鉱床・枯れ木）。砂漠に現れて後ろへ流れる（流れる動きは ResourceNode と同じ）。
## 残量があり、仲間が道具で掘るぶんだけ減る。結果（何個取れるか）は data/gathering.gd の evaluate() で決まる。
## 種類と絵は GatherDB.POINTS / assets/gather/*.png（tools/art_gather.py）。

var kind := "rock"
var remaining := 10        # 残量（掘り出せる量）
var max_amount := 10
var work := 0.0            # いまの1単位を掘る進み（0〜1）


func setup(g, k: String) -> void:
	game = g
	kind = k
	var d: Dictionary = GatherDB.POINTS[k]
	item = d["item"]
	max_amount = randi_range(d["amount"][0], d["amount"][1])
	remaining = max_amount


func available() -> bool:
	return remaining > 0


func display_name() -> String:
	return GatherDB.POINTS[kind]["name"]


## 絵のコマ: 0 = たっぷり / 1 = 減った / 2 = 枯れた
func frame() -> int:
	if remaining <= 0:
		return 2
	if float(remaining) <= ceil(float(max_amount) * GatherDB.WORN_RATIO):
		return 1
	return 0


func _draw() -> void:
	var snap := ((position / 4.0).round() * 4.0) - position
	var sz: Vector2i = GatherDB.POINTS[kind]["size"]
	var w := float(sz.x * GameData.PX)
	var h := float(sz.y * GameData.PX)
	# 影
	draw_rect(Rect2(snap + Vector2(-w / 2.0 - 4.0, -8), Vector2(w + 8.0, 8)), Color(0.35, 0.22, 0.1, 0.30))
	var t := GameData.tex("res://assets/gather/%s.png" % kind)
	draw_texture_rect_region(t, Rect2(snap + Vector2(-w / 2.0, -h), Vector2(w, h)), Rect2(frame() * sz.x, 0, sz.x, sz.y))
	if remaining <= 0:
		return
	if claimed_by == null:
		# 見つけてもらうまで小さな目印を点滅
		if int(age * 4.0) % 2 == 0:
			var y := snap.y - h - 14.0
			draw_rect(Rect2(snap.x - 8, y, 16, 4), Color("ffe36a"))
			draw_rect(Rect2(snap.x - 4, y + 4, 8, 4), Color("ffe36a"))
	# 残量のバーと名前
	var r := clampf(float(remaining) / float(maxi(1, max_amount)), 0.0, 1.0)
	draw_rect(Rect2(snap + Vector2(-24, 4), Vector2(48, 8)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(snap + Vector2(-20, 6), Vector2(40.0 * r, 4)), Color("7be07b") if r > 0.4 else Color("f0c040"))
	GameData.draw_text(self, snap + Vector2(0, -h - 20.0), "%s 残り%d" % [display_name(), remaining], 12, Color("fff7dc"), 150.0)
