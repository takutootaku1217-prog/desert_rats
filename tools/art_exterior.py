"""移動拠点の外装（外から見た車体）のドット絵を生成する（オリジナル。PILのみ）。
使い方: python tools/art_exterior.py                 … assets/base/exterior/<系統>/ に書き出す（gen_art.py からも同じ関数を呼ぶ）
        python tools/art_exterior.py --preview 出力.png [early|mid|late]  … 車輪・斜路と重ねた確認用の画像を書く（assets/ は変えない）

考え方: 外装は「1枚の完成した車両の絵」ではなく、車体（body.png）と、後から足せる外装パーツ（屋根・壁・装甲）の組み合わせ。
  - body.png: 車体そのもの（外板・窓の穴・運転席・搬入口・車輪の覆い）。窓の穴は透明で、ガラスの色はゲームが後ろから塗る
    （部屋の種類で色が変わる）。車体の大きさと形は、内装の断面図 hull.png と同じ（184x80、区画・車輪・斜路の位置も同じ）。
  - roof_parts.png: 屋根の上の物（旗・アンテナ・木箱・布・タンクなど）。内装の断面図の上にも同じ絵が出る（同じ車両を中から見ても屋根は同じ）。
  - wall_parts.png: 壁に付く物（工具かけ・物干し・十字の看板・燃料の口・後ろの荷台）。外から見たときだけ。
  - armor.png: 装甲（後半）。 windows.png: ガラスの上に重ねる映り込み。
  - parts.json: 上の絵の切り出し位置・置き場所・窓の位置。ゲーム（data/exterior.gd）はこれを読む＝絵と位置が食い違わない。
    置き場所・窓・車輪の位置などは「論理ユニット」（ゲームの基準の長さ。data/art_spec.gd）で書く。絵の切り出し（frames）は画像のピクセル。
    各絵の "units" は、その画像の基準の大きさ（ユニット）。画像のドット数 ÷ units が絵の細かさ（今は 1）。絵を高精細にするときは、
    画像を大きくして frames（ピクセル）だけ増やし、units・置き場所（ユニット）は変えない。
どの絵が、いつ（ゲームがどこまで進んだら）見えるかは、ゲーム側の表 data/exterior.gd。ここでは絵と置き場所だけを決める。
座標はすべて「車体の絵の左上を原点とした論理ユニット」（今は1ユニット=1ドット）。車体の上端の行は 10（屋根の上の物は行9まで）。"""
import json
import math
import os
import random
import sys
from pxlib import *
import art_base
from art_base import C, IW, IH, R0, UP_TOP, UP_FEET, LO_TOP, LO_FEET

STYLE = "desert"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

# ---- 色（砂色・茶・暗い金属・錆・くすんだオレンジ。ピカピカにしない）----
K = dict(
    out=hexc("241a14"),
    sand_l=hexc("e2c48c"), sand=hexc("c9a070"), sand_d=hexc("a67f52"), sand_dd=hexc("7f5d3a"),
    tan_a=hexc("c69a6a"), tan_b=hexc("bb9060"), tan_c=hexc("d0aa78"),
    brown=hexc("8a5c3a"), brown_d=hexc("5c3c26"), brown_l=hexc("a87a4e"),
    steel=hexc("4a4f5a"), steel_d=hexc("2f333b"), steel_m=hexc("5b616d"), steel_l=hexc("77808c"), steel_h=hexc("9aa2ae"),
    rust=hexc("a4522a"), rust_d=hexc("7a3a20"), rust_l=hexc("c27a3c"),
    orange=hexc("b8683a"), orange_d=hexc("8f4d2a"), orange_l=hexc("d08a52"),
    red=hexc("b5573f"), red_d=hexc("8a3f2e"), cream=hexc("e6d9b8"), cream_d=hexc("c2b48e"),
    teal=hexc("4f8c86"), teal_d=hexc("386a66"), olive=hexc("7d7a45"), olive_d=hexc("5a5832"),
    wood=hexc("8b5a32"), wood_l=hexc("b8834a"), wood_d=hexc("5c3d22"),
    wall_d=hexc("43352a"), wall=hexc("5b4736"), lamp=hexc("f6d36a"), lamp_g=hexc("fff0a8"),
    black=hexc("15171b"), yellow=hexc("d8a838"), white=hexc("efe7d2"),
)

# ---- 車体の形（内装の断面図 hull.png と同じ）と、窓・車輪の覆いの位置 ----
SHELL_X0, SHELL_X1 = 2, 181                    # 車体の左右の端（両端を含む）
ARCH_X = [30, 62, 122, 154]                    # 車輪の中心の列（GameData の WHEEL_X から (x-176)/4）
ARCH_Y = 78                                    # 車輪の中心の行
ARCH_R = 15                                    # 車輪の覆いの穴の半径
# 窓（区画ごと）。x, y, 幅, 高さ。位置は各区画の中央付近で、継ぎ目にかからない。
WINDOWS = {
    "u1": (30, 20, 18, 10), "u2": (100, 20, 18, 10),
    "l1": (30, 46, 18, 9), "l2": (107, 46, 18, 9),
}
CAB_SIDE = [(144, 18), (165, 18), (170, 29), (144, 29)]       # 運転席の窓（穴）。前の柱が後ろへ傾いている
UPPER_SEAMS = [22, 54, 72, 81, 96, 122, 138, 150, 166]        # 外板の継ぎ目（上の階）
LOWER_SEAMS = [22, 54, 72, 81, 96, 128, 138, 150, 158]        # 下の階
BAY = (159, 50, 19, 22)                                        # 搬入口（開いた口）x, y, 幅, 高さ。右端の切り欠きは 178..181
FUEL_PORT_ROW = 56                                             # 燃料の口の行（機関室の区画の壁）
FUEL_PORT_FALLBACK_X = 139                                     # 機関室がないときの燃料の口の左端の列（搬入口のそば）


def poly_bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1)


# ======================================================================================
# 車体
# ======================================================================================
def panel(p, x0, y0, x1, y1, base, hi=None, lo=None):
    """外板1枚（x1, y1 は含まない）。上と左を明るく、下と右を暗くして、板の厚みを見せる。"""
    p.rect(x0, y0, x1 - x0, y1 - y0, base)
    if hi is not None:
        p.hline(x0, y0, x1 - x0, hi)
    if lo is not None:
        p.hline(x0, y1 - 1, x1 - x0, lo)


def rivets(p, x0, x1, y, step=5, col=None, off=0):
    for x in range(x0 + off, x1, step):
        p.set(x, y, col or K["steel_d"])


def in_shell(x, y):
    """車体の輪郭の内側か（上の角は丸い）"""
    if x < SHELL_X0 or x > SHELL_X1 or y < R0 or y > IH - 1:
        return False
    if y == R0 and (x <= SHELL_X0 + 1 or x >= SHELL_X1 - 1):
        return False
    if y == R0 + 1 and (x == SHELL_X0 or x == SHELL_X1):
        return False
    return True


def body():
    p = Px(IW, IH)
    rnd = random.Random(23)
    # 1. 輪郭と下地
    for y in range(R0, IH):
        for x in range(SHELL_X0, SHELL_X1 + 1):
            if in_shell(x, y):
                p.set(x, y, K["steel"])
    # 2. 外板（上の階: 砂色の塗装が剥げた板。運転席まわりは別の色の板を継ぎ足した感じ）
    up_tones = [K["tan_a"], K["tan_c"], K["tan_b"], K["tan_a"], K["tan_c"], K["tan_b"], K["tan_a"], K["orange"], K["orange"], K["orange_l"]]
    edges = [SHELL_X0 + 1] + UPPER_SEAMS + [SHELL_X1]
    for i in range(len(edges) - 1):
        tone = up_tones[i % len(up_tones)]
        hi = K["sand_l"] if tone != K["orange"] and tone != K["orange_l"] else K["orange_l"]
        lo = K["sand_d"] if tone != K["orange"] and tone != K["orange_l"] else K["orange_d"]
        panel(p, edges[i] + 1, R0 + 3, edges[i + 1], UP_FEET, tone, hi, lo)
    # 下の階: 重い装甲板（灰色と茶色の板を継ぎ合わせる）
    low_tones = [K["steel_m"], K["brown"], K["steel_m"], K["steel_m"], K["brown"], K["steel_m"], K["brown"], K["steel_m"], K["steel_m"], K["brown"]]
    edges = [SHELL_X0 + 1] + LOWER_SEAMS + [SHELL_X1]
    for i in range(len(edges) - 1):
        tone = low_tones[i % len(low_tones)]
        hi = K["steel_l"] if tone == K["steel_m"] else K["brown_l"]
        lo = K["steel_d"] if tone == K["steel_m"] else K["brown_d"]
        panel(p, edges[i] + 1, LO_TOP + 1, edges[i + 1], LO_FEET, tone, hi, lo)
    # 3. 継ぎ目（暗い線）とリベット。上の階・下の階で位置が違う（手作りで継ぎ足した感じ）
    for s in UPPER_SEAMS:
        p.vline(s, R0 + 3, UP_FEET - (R0 + 3), K["steel_d"])
        p.vline(s + 1, R0 + 3, UP_FEET - (R0 + 3), K["out"])
        rivets(p, s - 1, s + 2, R0 + 5, 2, K["steel_h"])
        rivets(p, s - 1, s + 2, UP_FEET - 3, 2, K["steel_h"])
    for s in LOWER_SEAMS:
        p.vline(s, LO_TOP + 1, LO_FEET - (LO_TOP + 1), K["steel_d"])
        p.vline(s + 1, LO_TOP + 1, LO_FEET - (LO_TOP + 1), K["out"])
        rivets(p, s - 1, s + 2, LO_TOP + 3, 2, K["steel_h"])
        rivets(p, s - 1, s + 2, LO_FEET - 3, 2, K["steel_h"])
    # 4. 屋根の縁（上端の板と雨どい）
    p.hline(SHELL_X0 + 2, R0, SHELL_X1 - SHELL_X0 - 3, K["steel_h"])
    p.hline(SHELL_X0 + 1, R0 + 1, SHELL_X1 - SHELL_X0 - 1, K["steel_l"])
    p.hline(SHELL_X0 + 1, R0 + 2, SHELL_X1 - SHELL_X0 - 1, K["steel_d"])
    for x in range(8, 178, 14):                                  # 屋根の点検口
        p.rect(x, R0 + 1, 6, 1, K["steel_d"])
    # 5. 2つの階の間の梁
    p.rect(SHELL_X0 + 1, UP_FEET, SHELL_X1 - SHELL_X0 - 1, 4, K["steel_m"])
    p.hline(SHELL_X0 + 1, UP_FEET, SHELL_X1 - SHELL_X0 - 1, K["steel_h"])
    p.hline(SHELL_X0 + 1, UP_FEET + 1, SHELL_X1 - SHELL_X0 - 1, K["steel_l"])
    p.hline(SHELL_X0 + 1, UP_FEET + 3, SHELL_X1 - SHELL_X0 - 1, K["steel_d"])
    rivets(p, 6, 180, UP_FEET + 2, 6, K["steel_d"])
    # 6. 下の縁（スカート）と、色あせた注意帯（オレンジと焦げ茶）
    p.rect(SHELL_X0 + 1, LO_FEET, SHELL_X1 - SHELL_X0 - 1, IH - LO_FEET, K["steel_d"])
    p.hline(SHELL_X0 + 1, LO_FEET, SHELL_X1 - SHELL_X0 - 1, K["steel_l"])
    p.hline(SHELL_X0 + 1, IH - 1, SHELL_X1 - SHELL_X0 - 1, K["out"])
    for x in range(8, 176):
        if (x // 4) % 2 == 0:
            p.hline(x, LO_FEET + 4, 1, K["orange"])
            p.hline(x, LO_FEET + 5, 1, K["orange_d"])
        else:
            p.hline(x, LO_FEET + 4, 1, K["brown_d"])
            p.hline(x, LO_FEET + 5, 1, K["out"])
    # 7. 補修跡: 継ぎ足しの板、木の板、溶接の跡（手作り・使い込んだ感じ）
    panel(p, 57, 15, 70, 25, K["brown"], K["brown_l"], K["brown_d"])                       # 上の階の当て板
    for (x, y) in ((58, 16), (68, 16), (58, 23), (68, 23)):
        p.set(x, y, K["steel_h"])
    p.line(60, 24, 68, 17, K["brown_d"])
    for i in range(5):                                                                       # 下の階左の木の板の補修
        col = K["wood_l"] if i % 2 == 0 else K["wood"]
        p.rect(6 + i * 3, LO_TOP + 5, 3, 22, col)
        p.vline(6 + i * 3, LO_TOP + 5, 22, K["wood_d"])
    p.hline(5, LO_TOP + 5, 16, K["wood_d"]); p.hline(5, LO_TOP + 26, 16, K["wood_d"])
    for y in (LO_TOP + 8, LO_TOP + 22):
        p.set(7, y, K["steel_h"]); p.set(19, y, K["steel_h"])
    for (x, y, w) in ((100, 36, 14), (128, 66, 10), (48, 66, 8), (110, 16, 9)):             # 溶接のビード
        for k in range(w):
            p.set(x + k, y + (k % 2), K["steel_d"])
    # 8. 汚れ: 錆の筋・砂ぼこり・小さな傷
    for _ in range(46):
        x = rnd.randint(SHELL_X0 + 2, SHELL_X1 - 2)
        y = rnd.choice([rnd.randint(R0 + 4, UP_FEET - 4), rnd.randint(LO_TOP + 3, LO_FEET - 3)])
        if p.get(x, y)[3] and p.get(x, y) not in (K["out"], K["steel_d"]):
            p.set(x, y, K["rust"])
            if rnd.random() < 0.55:
                p.set(x, y + 1, K["rust_d"])
            if rnd.random() < 0.3:
                p.set(x, y + 2, K["rust_d"])
    for x in range(SHELL_X0 + 2, SHELL_X1 - 1):                                              # 板の下端に積もった砂
        if rnd.random() < 0.5:
            p.set(x, UP_FEET - 1, K["sand"] if p.get(x, UP_FEET - 1) != K["steel_d"] else K["steel_d"])
        if rnd.random() < 0.45:
            p.set(x, LO_FEET - 1, K["sand_d"])
    for _ in range(26):                                                                      # 傷
        x = rnd.randint(SHELL_X0 + 3, SHELL_X1 - 3)
        y = rnd.choice([rnd.randint(R0 + 4, UP_FEET - 4), rnd.randint(LO_TOP + 3, LO_FEET - 3)])
        p.set(x, y, K["sand_dd"] if y < UP_FEET else K["steel_d"])
    # 9. 後ろの端: はしごと排気の配管
    p.rect(3, R0 + 3, 4, LO_FEET - R0 - 3, K["steel_d"])
    p.vline(4, R0 + 3, LO_FEET - R0 - 3, K["steel_l"])
    for y in range(R0 + 5, LO_FEET - 2, 4):
        p.hline(3, y, 4, K["steel_h"])
    p.rect(8, LO_TOP - 4, 2, 30, K["copper_d"] if "copper_d" in K else K["rust_d"])
    p.vline(8, LO_TOP - 4, 30, K["rust_l"])
    for y in (LO_TOP - 2, LO_TOP + 10, LO_TOP + 24):
        p.rect(7, y, 4, 2, K["steel_l"])
    p.set(3, LO_FEET - 7, K["red"]); p.set(3, LO_FEET - 6, K["red_d"])                       # 尾灯
    # 10. 運転席（上の階の右）: 別の色の板・ドア・取っ手・サイドミラー・前のライト
    p.hline(140, R0 + 3, SHELL_X1 - 139, K["orange_d"])
    p.vline(141, 16, UP_FEET - 17, K["steel_d"])                                             # ドアの枠
    p.vline(168, 30, UP_FEET - 31, K["steel_d"])
    p.hline(141, UP_FEET - 2, 28, K["steel_d"])
    p.hline(156, 32, 6, K["steel_d"]); p.hline(156, 33, 6, K["orange_l"])                    # 取っ手
    p.rect(146, 23, 2, 3, K["steel_l"]); p.set(146, 26, K["steel_d"])                         # サイドミラーの根元は窓の下
    p.rect(178, 33, 4, 4, K["lamp"]); p.set(179, 34, K["lamp_g"]); p.rect(178, 37, 4, 1, K["steel_d"])   # 前のライト
    p.rect(173, 31, 6, 7, K["orange_d"]); p.hline(173, 31, 6, K["orange"])                   # 前の柱
    # 11. 搬入口（下の階の右）: 開いた口。中に薄く灯りとクレーンが見える。左の縁は色あせた注意帯
    bx, by, bw, bh = BAY
    p.rect(bx, by, bw, bh, K["wall_d"])
    p.rect(bx, by, bw, 2, K["steel_d"])
    p.hline(bx, by + 2, bw, K["black"])
    for y in range(by + 3, by + bh - 1, 2):
        p.hline(bx + 1, y, bw - 2, K["wall"] if (y // 2) % 3 else K["wall_d"])
    p.vline(bx + 9, by + 3, 12, K["steel_l"]); p.rect(bx + 8, by + 15, 3, 2, K["steel_h"])   # クレーンのフック
    p.hline(bx + 2, by + 3, 14, K["steel_l"])
    p.rect(bx + 4, by + 5, 3, 2, K["lamp"]); p.set(bx + 5, by + 5, K["lamp_g"])              # 灯り
    for y in range(by, by + bh):                                                             # 左の縁
        col = K["yellow"] if ((y - by) // 3) % 2 == 0 else K["black"]
        p.set(bx - 1, y, col); p.set(bx - 2, y, col)
    p.hline(bx - 2, by - 1, bw + 2, K["yellow"])
    p.hline(bx - 2, by - 2, bw + 2, K["steel_d"])
    p.rect(bx + bw, by - 2, SHELL_X1 - (bx + bw) + 1, bh + 2, CLEAR)                          # 右の端は開いている（斜路がつながる）
    p.hline(bx + bw, by - 2, 2, K["steel_d"])
    # 12. 前のバンパー
    p.rect(177, LO_FEET + 1, 7, 5, K["steel_m"]); p.hline(177, LO_FEET + 1, 7, K["steel_l"]); p.hline(177, LO_FEET + 5, 7, K["steel_d"])
    p.set(181, LO_FEET + 3, K["rust"]); p.set(178, LO_FEET + 3, K["steel_h"])
    # 13. 車輪の覆い（穴）と縁
    for cx in ARCH_X:
        for y in range(LO_FEET - 12, IH):
            for x in range(cx - ARCH_R - 3, cx + ARCH_R + 4):
                d = math.hypot(x - cx, y - ARCH_Y)
                if not p.get(x, y)[3]:
                    continue
                if d <= ARCH_R + 2.6 and d > ARCH_R + 1.4:
                    p.set(x, y, K["steel_d"])            # 覆いの外の縁
                elif d <= ARCH_R + 1.4 and d > ARCH_R:
                    p.set(x, y, K["steel_l"] if y < ARCH_Y - 8 else K["steel_m"])
        for y in range(LO_FEET - 12, IH):
            for x in range(cx - ARCH_R - 1, cx + ARCH_R + 2):
                if math.hypot(x - cx, y - ARCH_Y) <= ARCH_R:
                    p.set(x, y, CLEAR)
    # 14. 窓の穴と枠（穴は透明。ガラスの色は、ゲームが後ろから塗る）
    for slot, (x, y, w, h) in WINDOWS.items():
        p.rect(x - 2, y - 2, w + 4, h + 4, K["steel_d"])
        p.rect(x - 1, y - 1, w + 2, h + 2, K["steel_l"])
        p.hline(x - 2, y + h + 1, w + 4, K["out"])
        p.hline(x - 3, y + h + 2, w + 6, K["steel_m"])                                       # 窓台
        p.rect(x, y, w, h, CLEAR)
        for k in range(x + 2, x + w - 1, 4):                                                 # 窓のリベット（枠）
            p.set(k, y - 1, K["steel_h"])
    for dx in range(-2, 3):                                                                  # 運転席の窓の枠（穴を太らせた形）
        for dy in range(-2, 3):
            p.poly([(q[0] + dx, q[1] + dy) for q in CAB_SIDE], K["steel_d"])
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            p.poly([(q[0] + dx, q[1] + dy) for q in CAB_SIDE], K["steel_l"])
    p.poly(CAB_SIDE, CLEAR)
    return p


# ======================================================================================
# 窓の映り込み（ガラスの色の上に重ねる）
# ======================================================================================
def win_overlay(w, h):
    """窓のガラスの上に重ねる: 斜めの映り込みと、下の影"""
    p = Px(w, h)
    for k in range(3):
        x = 3 + k * 2
        p.line(x + 2, 0, x - 2, min(h - 1, 4), hexc("ffffff", 46 - k * 10))
    p.hline(0, h - 1, w, hexc("000000", 60))
    p.vline(w // 2, 0, h, hexc("241a14", 150))                       # 窓の桟
    return p


def cab_overlay(w, h):
    """運転席の窓: 運転席のシルエット（座席とハンドル）と映り込み"""
    p = Px(w, h)
    dark = hexc("241a14", 150)
    p.rect(3, 4, 5, 8, dark)                                   # 座席の背もたれ
    p.rect(3, 9, 9, 3, dark)                                   # 座面
    p.ellipse(15, 8, 2.5, 3, hexc("241a14", 130))              # ハンドル
    p.vline(13, 9, 3, dark)
    for k in range(2):
        p.line(9 + k * 4, 0, 5 + k * 4, min(h - 1, 5), hexc("ffffff", 60 - k * 16))
    p.hline(0, h - 1, w, hexc("000000", 60))
    return p


def windows_sheet():
    frames = {}
    imgs = [("win", win_overlay(18, 10)), ("win_low", win_overlay(18, 9)),
            ("cab_side", cab_overlay(27, 12))]
    return _pack(imgs, frames), frames


# ======================================================================================
# 屋根の上の物（屋上デッキ・荷物・アンテナ・タンク・布・排気管）。足元（絵の下端）が車体の上端の行の上に乗る。
# ======================================================================================
def deck_rail():
    p = Px(176, 4)
    p.hline(0, 0, 176, K["steel_l"])
    p.hline(0, 1, 176, K["steel_d"])
    for x in range(1, 176, 11):
        p.vline(x, 1, 3, K["steel_d"]); p.vline(x + 1, 1, 3, K["steel_m"])
    return p


def stack():
    p = Px(7, 8)
    p.rect(1, 1, 5, 7, K["steel_m"])
    p.hline(0, 0, 7, K["steel_l"])
    p.vline(1, 1, 7, K["steel_l"]); p.vline(5, 1, 7, K["steel_d"])
    p.hline(1, 4, 5, K["rust"])                       # 錆びた継ぎ目
    p.hline(1, 6, 5, K["rust_d"])
    p.hline(1, 1, 5, K["steel_d"])                    # すすの口
    return p


def flag():
    p = Px(10, 10)
    p.vline(1, 0, 10, K["wood_l"])
    for (x, y, c) in ((2, 0, K["red"]), (3, 0, K["red"]), (4, 0, K["red"]), (5, 0, K["red_d"]), (2, 1, K["red"]), (3, 1, K["red"]),
                      (4, 1, K["red_d"]), (5, 1, K["red_d"]), (6, 1, K["red"]), (2, 2, K["red_d"]), (3, 2, K["red_d"]), (4, 2, K["red"]),
                      (5, 2, K["red"]), (2, 3, K["red_d"]), (3, 3, K["red"])):
        p.set(x, y, c)
    p.rect(0, 9, 3, 1, K["steel_d"])
    return p


def antenna_small():
    p = Px(9, 10)
    p.vline(4, 1, 9, K["steel_l"])
    p.set(4, 0, K["red"])
    p.line(1, 9, 4, 4, K["steel_m"]); p.line(7, 9, 4, 4, K["steel_m"])
    p.rect(2, 8, 5, 2, K["steel_d"]); p.hline(2, 8, 5, K["steel_l"])
    return p


def antenna_mast():
    p = Px(15, 13)
    p.rect(6, 2, 3, 11, K["steel_m"])
    p.vline(6, 2, 11, K["steel_l"]); p.vline(8, 2, 11, K["steel_d"])
    p.hline(1, 4, 13, K["steel_l"]); p.hline(3, 7, 9, K["steel_l"])           # 横の腕
    p.vline(1, 2, 3, K["steel_l"]); p.vline(13, 2, 3, K["steel_l"])
    p.vline(3, 5, 3, K["steel_l"]); p.vline(11, 5, 3, K["steel_l"])
    p.vline(7, 0, 2, K["steel_h"]); p.set(7, 0, K["red"])
    p.line(1, 12, 6, 6, K["steel_d"]); p.line(13, 12, 8, 6, K["steel_d"])
    p.rect(4, 11, 7, 2, K["steel_d"]); p.hline(4, 11, 7, K["steel_l"])
    return p


def antenna_comm():
    p = Px(19, 16)
    p.rect(8, 5, 3, 11, K["steel_m"])
    p.vline(8, 5, 11, K["steel_l"]); p.vline(10, 5, 11, K["steel_d"])
    p.ellipse(9, 4, 6, 3, K["steel_h"])                                       # 皿
    p.ellipse(9, 5, 6, 3, K["steel_l"])
    p.ellipse(9, 4, 4, 2, K["steel_m"])
    p.line(9, 0, 9, 4, K["steel_d"]); p.rect(8, 0, 3, 2, K["steel_h"]); p.set(9, 0, K["red"])
    p.hline(3, 9, 13, K["steel_l"]); p.vline(3, 8, 2, K["steel_l"]); p.vline(15, 8, 2, K["steel_l"])
    p.hline(5, 12, 9, K["steel_l"])
    p.rect(5, 14, 9, 2, K["steel_d"]); p.hline(5, 14, 9, K["steel_l"])
    p.rect(13, 10, 4, 3, K["olive"]); p.hline(13, 10, 4, K["olive_d"])       # 無線機の箱
    return p


def crate(p, x, y, w, h, tone=None):
    col = tone or K["wood"]
    p.rect(x, y, w, h, col)
    p.hline(x, y, w, K["wood_l"]); p.hline(x, y + h - 1, w, K["wood_d"])
    p.vline(x, y, h, K["wood_d"]); p.vline(x + w - 1, y, h, K["wood_d"])
    p.line(x + 1, y + 1, x + w - 2, y + h - 2, K["wood_d"])


def crates_small():
    p = Px(14, 8)
    crate(p, 0, 3, 8, 5)
    crate(p, 8, 4, 6, 4, K["olive"])
    crate(p, 2, 0, 5, 3)
    return p


def crates_big():
    p = Px(21, 11)
    crate(p, 0, 5, 9, 6)
    crate(p, 9, 6, 6, 5, K["olive"])
    crate(p, 2, 1, 6, 4)
    p.rect(15, 4, 6, 7, K["rust"]); p.hline(15, 4, 6, K["orange_l"]); p.hline(15, 6, 6, K["steel_l"]); p.hline(15, 9, 6, K["steel_l"])   # ドラム缶
    p.vline(15, 4, 7, K["rust_d"])
    p.rect(9, 2, 5, 4, K["teal_d"]); p.hline(9, 2, 5, K["teal"])                # 金属のケース
    p.set(11, 4, K["steel_h"])
    return p


def cloth_roll():
    p = Px(11, 4)
    p.rect(0, 1, 11, 3, K["cream"])
    p.hline(0, 1, 11, K["cream_d"]); p.hline(0, 3, 11, K["cream_d"])
    p.vline(3, 0, 4, K["brown_d"]); p.vline(8, 0, 4, K["brown_d"])         # 縄
    p.set(0, 2, K["cream_d"]); p.set(10, 2, K["cream_d"])
    return p


def water_tank():
    p = Px(18, 9)
    p.rect(1, 0, 16, 7, K["olive"])
    p.hline(1, 0, 16, K["steel_l"]); p.hline(1, 6, 16, K["olive_d"])
    for x in (4, 9, 14):
        p.vline(x, 0, 7, K["steel_d"])
    p.rect(0, 1, 1, 5, K["olive_d"]); p.rect(17, 1, 1, 5, K["olive_d"])
    p.rect(2, 7, 2, 2, K["steel_d"]); p.rect(14, 7, 2, 2, K["steel_d"])   # 脚
    p.hline(1, 3, 3, K["olive_d"])
    return p


def canopy():
    """屋根の布（日よけ）。2本の柱の間に、色あせた縞の布を張る。"""
    p = Px(32, 9)
    p.vline(1, 2, 7, K["wood_l"]); p.vline(30, 2, 7, K["wood_l"])
    p.vline(2, 2, 7, K["wood_d"]); p.vline(31, 2, 7, K["wood_d"])
    for x in range(0, 32):
        sag = int(2 * math.sin((x / 31.0) * math.pi))
        col = K["red"] if (x // 4) % 2 == 0 else K["cream"]
        dcol = K["red_d"] if (x // 4) % 2 == 0 else K["cream_d"]
        top = 1 - 0 + (1 if 3 < x < 28 else 0)
        for y in range(top, top + 3 + sag):
            p.set(x, y, col)
        p.set(x, top + 2 + sag, dcol)
        if x % 4 == 0:
            p.set(x, top + 3 + sag, dcol)                             # 裾のほつれ
    p.hline(0, 0, 32, K["brown_d"])                                   # 棟の縄
    return p


def fuel_tank_roof():
    p = Px(25, 9)
    p.rect(1, 1, 23, 7, K["rust"])
    p.ellipse(1, 4, 1.5, 3.5, K["rust_d"]); p.ellipse(23, 4, 1.5, 3.5, K["rust_d"])
    p.hline(2, 1, 21, K["orange_l"]); p.hline(2, 7, 21, K["rust_d"])
    for x in (6, 12, 18):
        p.vline(x, 1, 7, K["steel_l"]); p.vline(x + 1, 1, 7, K["steel_d"])   # 締め具
    p.rect(11, 0, 3, 2, K["steel_m"]); p.set(12, 0, K["steel_h"])           # 給油口
    p.rect(3, 8, 3, 1, K["steel_d"]); p.rect(19, 8, 3, 1, K["steel_d"])
    return p


def roof_vent():
    p = Px(7, 8)
    p.vline(3, 3, 5, K["steel_m"]); p.vline(4, 3, 5, K["steel_d"])
    p.rect(1, 0, 6, 3, K["steel_l"]); p.hline(1, 0, 6, K["steel_h"]); p.hline(1, 2, 6, K["steel_d"])
    p.rect(2, 6, 4, 2, K["steel_d"])
    p.set(2, 4, K["rust"])
    return p


ROOF_PARTS = [
    # 名前, 絵, 置き場所 x, 足元の行の上（絵の下端が 行9 に来るように y を決める）
    ("deck_rail", deck_rail, 3),
    ("stack_a", stack, 119),
    ("stack_b", stack, 127),
    ("flag", flag, 6),
    ("antenna_small", antenna_small, 26),
    ("antenna_mast", antenna_mast, 23),
    ("antenna_comm", antenna_comm, 21),
    ("crates_small", crates_small, 44),
    ("crates_big", crates_big, 44),
    ("cloth_roll", cloth_roll, 62),
    ("water_tank", water_tank, 61),
    ("canopy", canopy, 82),
    ("fuel_tank_roof", fuel_tank_roof, 142),
    ("roof_vent", roof_vent, 0),                      # 置き場所は区画ごと（ゲームが決める）
]
ROOF_FOOT_ROW = 9                                      # 屋根の上の物の下端の行


# ======================================================================================
# 壁に付く物・装甲
# ======================================================================================
def tool_rack():
    """工具かけ（つるはし・ハンマー・斧が掛かっている）"""
    p = Px(14, 13)
    p.rect(0, 0, 14, 2, K["wood_d"]); p.hline(0, 0, 14, K["wood"])
    p.vline(3, 2, 8, K["wood"]); p.rect(2, 9, 3, 3, K["steel_l"]); p.hline(2, 9, 3, K["steel_h"])          # ハンマー
    p.vline(7, 2, 10, K["wood"]); p.line(5, 3, 9, 3, K["steel_l"]); p.line(5, 4, 9, 4, K["steel_d"])       # つるはし
    p.vline(11, 2, 9, K["wood"]); p.rect(10, 9, 3, 3, K["steel_m"]); p.set(10, 9, K["steel_h"])           # 斧
    p.set(3, 2, K["steel_d"]); p.set(7, 2, K["steel_d"]); p.set(11, 2, K["steel_d"])
    return p


def wash_line():
    """物干し（洗濯物）"""
    p = Px(16, 12)
    p.vline(0, 0, 12, K["steel_m"]); p.vline(15, 0, 12, K["steel_m"])
    p.hline(0, 1, 16, K["cream_d"])
    for (x, w, h, c, d) in ((2, 4, 6, K["red"], K["red_d"]), (7, 3, 5, K["cream"], K["cream_d"]), (11, 3, 7, K["teal"], K["teal_d"])):
        p.rect(x, 2, w, h, c)
        p.hline(x, 2 + h - 1, w, d)
        p.set(x, 2, K["brown_d"])
    return p


def sign_cross():
    """十字の看板（医務室）"""
    p = Px(9, 9)
    p.rect(0, 0, 9, 9, K["steel_d"])
    p.rect(1, 1, 7, 7, K["white"])
    p.rect(3, 2, 3, 5, K["red"]); p.rect(2, 3, 5, 3, K["red"])
    p.set(1, 1, K["cream_d"]); p.set(7, 7, K["cream_d"])
    return p


def fuel_port():
    """燃料の口（赤い蓋と注ぎ口）"""
    p = Px(9, 6)
    p.rect(0, 0, 9, 6, K["steel_d"])
    p.rect(1, 1, 7, 4, K["steel_m"])
    p.rect(2, 1, 5, 3, K["red"]); p.hline(2, 1, 5, K["orange_l"]); p.hline(2, 3, 5, K["red_d"])
    p.set(4, 2, K["steel_h"])
    p.hline(1, 5, 7, K["out"])
    return p


def rear_rack():
    """後ろの荷台（外部収納。車体の後ろに張り出す）"""
    p = Px(16, 27)
    p.rect(5, 0, 11, 2, K["steel_d"])
    p.line(2, 26, 6, 3, K["steel_m"]); p.line(3, 26, 7, 3, K["steel_l"])          # 斜めの支え
    p.rect(0, 22, 15, 3, K["wood"]); p.hline(0, 22, 15, K["wood_l"]); p.hline(0, 24, 15, K["wood_d"])   # 台
    crate(p, 1, 15, 8, 7, K["olive"])
    crate(p, 9, 17, 6, 5)
    p.ellipse(8, 10, 5, 5, K["black"]); p.ellipse(8, 10, 3, 3, K["steel_m"]); p.set(8, 10, K["steel_d"])   # 予備のタイヤ
    p.hline(3, 10, 3, K["steel_d"])
    p.rect(11, 25, 3, 2, K["steel_d"])
    return p


def armor_side():
    """下の階の側面に重ねる、ボルト留めの装甲板"""
    p = Px(27, 21)
    p.rect(0, 0, 27, 21, K["steel_m"])
    p.hline(0, 0, 27, K["steel_h"]); p.hline(0, 1, 27, K["steel_l"])
    p.hline(0, 20, 27, K["steel_d"]); p.vline(0, 0, 21, K["steel_l"]); p.vline(26, 0, 21, K["steel_d"])
    p.line(1, 19, 25, 2, K["steel_d"])                                           # 補強の斜材
    p.line(2, 19, 25, 3, K["steel_l"])
    for (x, y) in ((2, 2), (24, 2), (2, 18), (24, 18), (13, 2), (13, 18)):
        p.set(x, y, K["steel_h"]); p.set(x + 1, y, K["steel_d"])
    for (x, y) in ((6, 15), (18, 5), (20, 12)):
        p.set(x, y, K["rust"]); p.set(x, y + 1, K["rust_d"])                     # 傷・錆
    return p


def armor_front():
    """前のバンパーの補強"""
    p = Px(8, 18)
    p.rect(0, 0, 8, 18, K["steel_m"])
    p.hline(0, 0, 8, K["steel_h"]); p.vline(0, 0, 18, K["steel_l"]); p.vline(7, 0, 18, K["steel_d"])
    p.hline(0, 17, 8, K["steel_d"])
    p.line(1, 14, 6, 3, K["steel_d"])
    for (x, y) in ((2, 2), (5, 15)):
        p.set(x, y, K["steel_h"])
    p.set(3, 10, K["rust"])
    return p


WALL_PARTS = [
    ("tool_rack", tool_rack, (56, 49)),
    ("wash_line", wash_line, (121, 15)),
    ("sign_cross", sign_cross, (0, 0)),               # 置き場所は区画ごと（窓の下）
    ("fuel_port", fuel_port, (0, 0)),                 # 置き場所は機関室の位置（ゲームが決める）
    ("rear_rack", rear_rack, (-13, 45)),
]
ARMOR_PARTS = [
    ("armor_side", armor_side, (78, 48)),
    ("armor_front", armor_front, (176, 60)),
]
# 区画に付く物の、窓の左上からの位置（ゲームが 区画の窓の位置 ＋ これ で置く）
SLOT_OFFSETS = {"sign_cross": (5, 10)}
ROOF_VENT_X = {"u1": 135, "l1": 135, "u2": 168, "l2": 168}      # 屋根が空いている場所（アンテナ・荷物・布・排気管・タンクを避ける）


# ======================================================================================
# 絵の詰め合わせ（横に並べる）と、出力
# ======================================================================================
def _pack(imgs, frames, pad=2):
    """(名前, Px) の一覧を横に並べた絵にする。frames に 名前 -> [x, y, w, h] を入れる。"""
    w = sum(px.w + pad for _, px in imgs) + pad
    h = max(px.h for _, px in imgs) + 2 * pad
    sheet = Px(w, h)
    x = pad
    for name, px in imgs:
        sheet.paste(px, x, pad)
        frames[name] = [x, pad, px.w, px.h]
        x += px.w + pad
    return sheet


def build_all():
    """出力する全ての絵と、parts.json の中身を返す。"""
    files = {}
    geo = {"style": STYLE, "hull_size": [IW, IH], "foot_row": ROOF_FOOT_ROW, "arches": ARCH_X, "arch_y": ARCH_Y,
           "windows": {k: list(v) for k, v in WINDOWS.items()},
           "cab_side": list(poly_bbox(CAB_SIDE)),
           "fuel_port_row": FUEL_PORT_ROW, "fuel_port_fallback_x": FUEL_PORT_FALLBACK_X,
           "slot_offsets": {k: list(v) for k, v in SLOT_OFFSETS.items()},
           "roof_vent_x": ROOF_VENT_X, "sheets": {}, "at": {}}
    files["body.png"] = body()
    geo["body"] = {"file": "body.png", "units": [IW, IH]}
    sh, fr = windows_sheet()
    files["windows.png"] = sh
    geo["sheets"]["windows"] = {"file": "windows.png", "units": [sh.w, sh.h], "frames": fr}
    frames = {}
    imgs = []
    for name, fn, x in ROOF_PARTS:
        px = fn()
        imgs.append((name, px))
        geo["at"][name] = [x, ROOF_FOOT_ROW + 1 - px.h]
    files["roof_parts.png"] = _pack(imgs, frames)
    geo["sheets"]["roof_parts"] = {"file": "roof_parts.png", "units": [files["roof_parts.png"].w, files["roof_parts.png"].h], "frames": frames}
    frames = {}
    imgs = []
    for name, fn, at in WALL_PARTS:
        imgs.append((name, fn()))
        geo["at"][name] = list(at)
    files["wall_parts.png"] = _pack(imgs, frames)
    geo["sheets"]["wall_parts"] = {"file": "wall_parts.png", "units": [files["wall_parts.png"].w, files["wall_parts.png"].h], "frames": frames}
    frames = {}
    imgs = []
    for name, fn, at in ARMOR_PARTS:
        imgs.append((name, fn()))
        geo["at"][name] = list(at)
    files["armor.png"] = _pack(imgs, frames)
    geo["sheets"]["armor"] = {"file": "armor.png", "units": [files["armor.png"].w, files["armor.png"].h], "frames": frames}
    return files, geo


def write_all(root=ROOT):
    d = os.path.join(root, "base", "exterior", STYLE)
    os.makedirs(d, exist_ok=True)
    files, geo = build_all()
    for name, px in files.items():
        px.save(os.path.join(d, name))
        print("wrote base/exterior/%s" % STYLE, name, px.w, "x", px.h)
    with open(os.path.join(d, "parts.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(geo, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote base/exterior/%s parts.json" % STYLE)


# ---- 確認用の絵（ゲームでの重なり方: 車輪 → ガラス → 車体 → 壁の物 → 屋根の物 → 斜路）----
GLASS = {"u1": "f0a050", "u2": "f6d890", "l1": "e06a30", "l2": "7a6a58"}
STAGES = {
    "early": ["deck_rail", "stack_a", "stack_b", "flag", "antenna_small", "crates_small", "cloth_roll"],
    "mid": ["deck_rail", "stack_a", "stack_b", "flag", "antenna_mast", "crates_big", "water_tank", "canopy"],
    "late": ["deck_rail", "stack_a", "stack_b", "flag", "antenna_comm", "crates_big", "water_tank", "canopy", "fuel_tank_roof"],
}


def preview(path, stage="mid"):
    from PIL import Image
    files, geo = build_all()
    S = 5
    W, H = 232, 118
    ox, oy = 24, 24                           # 車体の左上（プレビュー内のドット）
    sky = Px(W, H, hexc("f0c47c"))
    sky.rect(0, 92, W, 26, hexc("e2ae62"))
    canvas = sky.im
    # 車輪（GameData の WHEEL_X, WHEEL_Y）
    wsheet = Image.open(os.path.join(ROOT, "base", "wheels.png")).convert("RGBA")
    wheel = wsheet.crop((0, 0, 28, 28))
    for cx in ARCH_X:
        canvas.alpha_composite(wheel, (ox + cx - 14, oy + ARCH_Y - 14))
    # ガラス
    gl = Px(W, H)
    for slot, (x, y, w, h) in WINDOWS.items():
        gl.rect(ox + x, oy + y, w, h, hexc(GLASS[slot]))
    x, y, w, h = geo["cab_side"]
    gl.rect(ox + x, oy + y, w, h, hexc("f4c986"))
    canvas.alpha_composite(gl.im)
    canvas.alpha_composite(files["body.png"].im, (ox, oy))

    def put(sheet, name, at):
        fx, fy, fw, fh = geo["sheets"][sheet]["frames"][name]
        canvas.alpha_composite(files[geo["sheets"][sheet]["file"]].im.crop((fx, fy, fx + fw, fy + fh)), (ox + at[0], oy + at[1]))
    for name in ("tool_rack", "fuel_port"):
        if name == "fuel_port":
            put("wall_parts", name, (40, FUEL_PORT_ROW))
        elif stage != "early":
            put("wall_parts", name, geo["at"][name])
    if stage in ("mid", "late"):
        put("wall_parts", "rear_rack", geo["at"]["rear_rack"])
        put("wall_parts", "wash_line", geo["at"]["wash_line"])
    if stage == "late":
        put("armor", "armor_side", geo["at"]["armor_side"])
        put("armor", "armor_front", geo["at"]["armor_front"])
    for name in STAGES[stage]:
        put("roof_parts", name, geo["at"][name])
    # 斜路（GameData: (900,482) → 車体の左上 (176,194) からのドット）
    ramp = Image.open(os.path.join(ROOT, "base", "ramp.png")).convert("RGBA")
    canvas.alpha_composite(ramp, (ox + (900 - 176) // 4, oy + (482 - 194) // 4))
    big = canvas.resize((W * S, H * S), Image.NEAREST)
    big.save(path)
    print("preview:", path, stage)


if __name__ == "__main__":
    if "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        preview(sys.argv[i + 1], sys.argv[i + 2] if len(sys.argv) > i + 2 else "mid")
    else:
        write_all()
