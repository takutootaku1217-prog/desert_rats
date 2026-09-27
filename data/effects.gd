class_name EffectDB
extends RefCounted
## 効果（湯気・砂ぼこり・きらめき・将来の炎・爆発・銃撃・レーザー・水など）の一覧。**素材（コマが横に並んだ画像）を再生するだけ**で、図形はコードで描かない。
## 再生するのは scripts/fx_sprite.gd（FxSprite）。新しい効果は、絵を tools/art_effects.py に足して、この表に1行足すだけ。
## 絵を高精細な素材に差し替えるときは、同じ基準の大きさ（cell。ユニット）で、幅が整数倍の画像を置くだけ（ゲーム側は変えない）。
##   sheet = 画像 / cell = 1コマの基準の大きさ（ユニット。1ユニット = 4px）/ frames = コマ数 / fps = 1秒に進むコマ数 / loop = 繰り返すか（false なら1回で消える）
## 効果を出す位置は、呼ぶ側が決める（足元の中心が基準）。効果そのものは、ゲームの状態を持たない（見た目だけ）。

const EFFECTS := {
	"proc_steam": {"sheet": "res://assets/effects/proc_steam.png", "cell": Vector2i(8, 8), "frames": 6, "fps": 5.0, "loop": true},     # 加工設備の煙突の湯気（加工中）
	"proc_drop": {"sheet": "res://assets/effects/proc_drop.png", "cell": Vector2i(10, 6), "frames": 5, "fps": 14.0, "loop": false},    # 材料が投入口へ落ちた
	"proc_done": {"sheet": "res://assets/effects/proc_done.png", "cell": Vector2i(8, 8), "frames": 6, "fps": 12.0, "loop": false},     # 加工が終わった（きらり）
}


static func has(id: String) -> bool:
	return EFFECTS.has(id)


## 絵の基準（ArtSpec の spec の形。frame_src に渡せる）
static func spec(id: String) -> Dictionary:
	var e: Dictionary = EFFECTS[id]
	return ArtSpec.spec_of(e["cell"], int(e["frames"]))


static func duration(id: String) -> float:
	var e: Dictionary = EFFECTS[id]
	return float(e["frames"]) / float(e["fps"])
