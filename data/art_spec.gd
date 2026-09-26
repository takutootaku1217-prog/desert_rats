class_name ArtSpec
extends RefCounted
## 絵（アート）の細かさと、ゲームの座標・大きさを切り離すための決まり（プロトタイプ）。
## 目的: 将来、ドット絵を高精細にしても（1ドット=4px → 2px → もっと細かく）、ゲームの仕組み・配置・当たり・部屋のデータを作り直さない。
##
## 座標は3つの層に分ける:
##  1. ワールド座標（画面のpx。1280x720）… 仲間の位置・速度・行き先・当たり。ゲームロジックは、この座標だけを使う。
##  2. 論理ユニット（unit）… 部屋・設備・外装パーツ・スプライトの「基準の大きさ・置き場所」を決める単位。1ユニット = UNIT_PX（4px）。
##     data/rooms.gd・data/facilities.gd・外装の parts.json の座標や、下のスプライトの基準の大きさは、すべてユニットで書く。
##     ユニットは「今の絵の1ドット」と同じ大きさだが、意味は「ゲーム上の基準の長さ」で、絵の細かさとは関係がない。
##  3. 絵のドット（texture px）… 画像のピクセル。1ユニットを何ドットで描いているか（dpu = dots per unit）は、絵ごとに違ってよい。
##     dpu は「画像の幅（ドット）÷ その絵の基準の幅（ユニット）」で自動的に決まる（今は全部 1。手で設定する数値はない）。
## → 絵を2倍の細かさに差し替えても（同じ基準の大きさで、幅が2倍の画像を置くだけ）、ゲーム側は何も変えなくてよい。
##    絵ごとに細かさが違っても動く（車体だけ先に高精細にする、など。段階的な差し替え）。
##
## 描くとき: 画面の大きさ = 基準の大きさ（ユニット）× UNIT_PX（画像の大きさには依存しない）。
##           画像の切り出し = 基準の大きさ × dpu（ArtSpec.frame_src など）。4pxの格子に合わせる処理 = 絵の1ドットの大きさ（dot_px）。
## 変える値は UNIT_PX（画面上の基準の長さ。変えると全部の大きさが変わる）だけ。絵の細かさは、絵を差し替えるだけ。

const UNIT_PX := 4                       # 論理ユニット1つ = 画面（ワールド座標）の何px。GameData.PX と同じ

# ---- スプライトの基準の大きさ（ユニット）。cell = 1コマ / stride = コマの間隔 / frames = コマ数（1コマだけの絵は stride 0）----
const WORKER := {"cell": Vector2i(16, 16), "stride": 16, "frames": 13}       # 仲間（assets/characters/mouse_*.png）
const WHEELS := {"cell": Vector2i(28, 28), "stride": 30, "frames": 4}        # 車輪（assets/base/wheels.png）
const MACHINE := {"cell": Vector2i(28, 24), "stride": 30, "frames": 3}       # 加工機（assets/base/machine.png）
const HULL := Vector2i(184, 80)                                              # 車体の断面図・外装の車体（assets/base/hull.png ほか）
const RAMP := Vector2i(24, 18)                                               # 斜路
const ITEM := Vector2i(12, 12)                                               # アイテムのアイコン（assets/resources/item_*.png）
const UI_ICON := Vector2i(16, 16)                                            # UIのアイコンゲージ（assets/ui/*.png。積載重量など。将来のHP・満腹度も同じ）
const CREATURE_FRAMES := 3                                                   # 生物の絵は3コマ（1コマの大きさは GameData.CREATURES の "size"）
const GATHER_FRAMES := 3                                                     # 採取ポイントの絵は3コマ（大きさは GatherDB.POINTS の "size"）
const BACKGROUND_W := 320                                                    # 背景の1枚の幅（画面幅 1280px ÷ UNIT_PX）

## テスト用: 絵の置き場所。空でなければ、res://assets/ の代わりに、ここにある同じ相対パスの絵を先に探す
## （高精細な絵に差し替えたときの動作確認用。tools/make_dpu_fixture.py で作る）。コマンドラインの --art-root=<フォルダ> でも指定できる。
static var root_override := ""
static var _args_read := false


# ------------------------------------------------------------------
# 座標・大きさ
# ------------------------------------------------------------------
## ユニット → ワールド座標（px）
static func world(u: Vector2) -> Vector2:
	return u * float(UNIT_PX)


## スプライトの基準の大きさ（ユニット）→ 画面上の大きさ（px）。絵の細かさには依存しない。
static func px_size(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(UNIT_PX)


## 絵の詰め合わせ（横に並べた絵）の基準の幅（ユニット）
static func sheet_units_w(spec: Dictionary) -> float:
	var cell: Vector2i = spec["cell"]
	var stride: int = int(spec.get("stride", 0))
	return float(cell.x) if stride <= 0 else float(stride * int(spec.get("frames", 1)))


# ------------------------------------------------------------------
# 絵の細かさ（dpu）
# ------------------------------------------------------------------
## この絵の細かさ = 1ユニットあたりのドット数。画像の幅 ÷ 基準の幅（ユニット）。
static func dpu(tex: Texture2D, units_w: float) -> float:
	return float(tex.get_width()) / maxf(units_w, 0.001)


## 絵の1ドットの、画面上の大きさ（px）。4pxの格子に合わせる処理に使う。
static func dot_px(tex: Texture2D, units_w: float) -> float:
	return float(UNIT_PX) / dpu(tex, units_w)


## スプライトの index コマ目の、画像の切り出し範囲（画像のピクセル。dpu をかけてある）。
static func frame_src(tex: Texture2D, spec: Dictionary, index: int) -> Rect2:
	var d := dpu(tex, sheet_units_w(spec))
	var cell: Vector2i = spec["cell"]
	var stride: int = int(spec.get("stride", 0))
	return Rect2(float(index * stride) * d, 0.0, float(cell.x) * d, float(cell.y) * d)


## スプライトの spec（基準の大きさ）を、生物・採取ポイントのように「1コマの大きさだけ決まっていて、コマ数は共通」の形で作る。
static func spec_of(cell: Vector2i, frames: int) -> Dictionary:
	return {"cell": cell, "stride": cell.x, "frames": frames}


## pos を、絵のドットの格子（dot px 刻み）に合わせるための、ずらし量。
static func snap_offset(pos: Vector2, dot: float) -> Vector2:
	return ((pos / dot).round() * dot) - pos


# ------------------------------------------------------------------
# 絵の置き場所（テスト用の差し替え）
# ------------------------------------------------------------------
static func _read_args() -> void:
	if _args_read:
		return
	_args_read = true
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--art-root="):
			root_override = String(a).substr("--art-root=".length())


## path（res://assets/…）の、差し替え先のファイルのパス。差し替えがなければ ""。
static func overridden(path: String) -> String:
	_read_args()
	if root_override == "" or not path.begins_with("res://assets/"):
		return ""
	var p := root_override.path_join(path.trim_prefix("res://assets/"))
	return p if FileAccess.file_exists(p) else ""


## 差し替え先を変える（絵のキャッシュも捨てる）。空にすると通常に戻る。
static func set_root_override(dir: String) -> void:
	root_override = dir
	_args_read = true
	GameData.clear_tex_cache()
	ExteriorDB.reload()


## テキスト（外装の parts.json など）を読む。差し替え先があればそちら。
static func read_text(path: String) -> String:
	var p := overridden(path)
	return FileAccess.get_file_as_string(p if p != "" else path)
