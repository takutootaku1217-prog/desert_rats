"""採取ポイント（岩場・鉱床・枯れ木）と、採取の道具のアイコンを生成する（オリジナルのドット絵。PILのみ）。
使い方: python tools/art_gather.py            … assets/ に書き出す（gen_art.py からも呼ばれる）
        python tools/art_gather.py --preview  … 拡大した確認用の画像を tools/_preview_gather.png に書く
採取ポイントの絵は3コマ: 0=たっぷり 1=減った 2=枯れた（がれき）。足元が下端の中央。"""
import os
import sys
from pxlib import *

OUT = hexc("2a1c1a")
S = 12   # 道具アイコンのサイズ（art_items.py と同じ）

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


# ---------------------------------------------------------------- 道具のアイコン（12x12）
WOOD = hexc("9a6a3a"); WOOD_D = hexc("6e4726"); WOOD_L = hexc("c99a5c")
STONE = hexc("8d8a86"); STONE_L = hexc("b8b4ae"); STONE_D = hexc("5f5c59")
IRON = hexc("a9b1b9"); IRON_L = hexc("dfe5ea"); IRON_D = hexc("6d757d")
STEEL = hexc("6fb7c9"); STEEL_L = hexc("b9ecf5"); STEEL_D = hexc("3f7f93"); GLOW = hexc("f0c040")


def hammer():   # 簡易ハンマー: 木の柄＋石の頭
    p = Px(S, S)
    p.line(1, 10, 7, 4, WOOD); p.line(2, 10, 8, 4, WOOD_D)
    p.rect(6, 1, 5, 4, STONE)
    p.hline(6, 1, 5, STONE_L); p.hline(6, 4, 5, STONE_D); p.set(10, 2, STONE_D)
    return p.outline(OUT)


def pickaxe():   # 鉄製ピッケル: 木の柄＋鉄の曲がった頭
    p = Px(S, S)
    p.line(2, 10, 8, 4, WOOD); p.line(3, 10, 9, 4, WOOD_D)
    p.poly([(2, 3), (5, 1), (9, 1), (11, 3), (9, 3), (6, 2), (3, 4)], IRON)
    p.hline(5, 1, 4, IRON_L); p.set(2, 3, IRON_D); p.set(10, 3, IRON_D)
    return p.outline(OUT)


def adv_pick():   # 高性能ピッケル: 青みのある鋼＋光る先端
    p = Px(S, S)
    p.line(2, 10, 8, 4, hexc("5a6470")); p.line(3, 10, 9, 4, hexc("3c444e"))
    p.poly([(1, 3), (4, 1), (9, 1), (11, 3), (9, 4), (6, 3), (3, 5)], STEEL)
    p.hline(4, 1, 5, STEEL_L); p.set(1, 3, STEEL_D); p.set(11, 3, STEEL_D); p.set(6, 3, STEEL_D)
    p.set(1, 3, GLOW); p.set(11, 3, GLOW)
    p.set(3, 9, GLOW)
    return p.outline(OUT)


def axe():   # 簡易の斧: 木の柄＋石の刃
    p = Px(S, S)
    p.line(2, 10, 8, 3, WOOD); p.line(3, 10, 9, 3, WOOD_D)
    p.poly([(6, 1), (9, 1), (11, 0), (11, 6), (9, 5), (6, 4)], STONE)      # 外へ広がる刃（ハンマーと見分けがつくように）
    p.hline(6, 1, 4, STONE_L); p.vline(11, 1, 5, STONE_L); p.hline(7, 4, 3, STONE_D)
    return p.outline(OUT)


def iron_axe():   # 鉄の斧: 木の柄＋鉄の刃
    p = Px(S, S)
    p.line(2, 10, 8, 3, WOOD); p.line(3, 10, 9, 3, WOOD_D)
    p.poly([(5, 1), (9, 1), (11, 0), (11, 6), (9, 5), (5, 4)], IRON)
    p.hline(5, 1, 5, IRON_L); p.vline(11, 1, 5, IRON_L); p.hline(7, 4, 3, IRON_D); p.set(9, 2, IRON_L)
    return p.outline(OUT)


TOOLS = {"hammer": hammer, "pickaxe": pickaxe, "adv_pick": adv_pick, "axe": axe, "iron_axe": iron_axe}


# ---------------------------------------------------------------- 採取ポイント（3コマ）
def _sheet(w, h, frames):
    sh = Px(w * len(frames), h)
    for i, f in enumerate(frames):
        sh.im.alpha_composite(f.im, (i * w, 0))
    return sh


def rock():   # 岩場（20x12）
    w, h = 20, 12
    g = hexc("8d8a86"); l = hexc("b8b4ae"); d = hexc("5f5c59"); dd = hexc("46433f")

    def full():
        p = Px(w, h)
        p.poly([(0, 11), (1, 6), (5, 2), (10, 1), (15, 3), (19, 7), (19, 11)], g)
        p.poly([(3, 6), (6, 3), (10, 2), (13, 4), (9, 5), (6, 7)], l)
        p.poly([(11, 6), (14, 4), (18, 8), (18, 10), (12, 10)], d)
        p.hline(1, 10, 18, d); p.set(8, 8, dd); p.set(4, 9, dd); p.set(15, 9, dd)
        p.set(9, 3, hexc("dcd8d2")); p.set(5, 5, hexc("dcd8d2"))
        return p.outline(OUT)

    def worn():
        p = Px(w, h)
        p.poly([(1, 11), (2, 8), (6, 5), (10, 5), (14, 7), (18, 9), (18, 11)], g)
        p.poly([(4, 8), (7, 6), (10, 6), (8, 8)], l)
        p.poly([(12, 8), (15, 8), (17, 10), (12, 10)], d)
        p.hline(2, 10, 16, d); p.set(9, 9, dd); p.set(5, 10, dd)
        p.line(8, 6, 10, 9, dd)           # ひび
        return p.outline(OUT)

    def gone():
        p = Px(w, h)
        for (x, y, r) in ((4, 9, 1.6), (9, 10, 1.4), (14, 9, 1.8), (17, 10, 1.1)):
            p.ellipse(x, y, r + 0.4, r, g)
        p.set(4, 8, l); p.set(14, 8, l); p.hline(2, 11, 16, d)
        return p.outline(OUT)

    return _sheet(w, h, [full(), worn(), gone()])


def vein():   # 鉱床（20x13）: 暗い岩に鉄の錆色の鉱石がのぞく
    w, h = 20, 13
    g = hexc("6f5f58"); l = hexc("927d72"); d = hexc("4a3d38"); o = hexc("c46a3a"); ol = hexc("f0a469"); dd = hexc("352a26")

    def full():
        p = Px(w, h)
        p.poly([(0, 12), (1, 7), (4, 3), (9, 1), (15, 2), (19, 6), (19, 12)], g)
        p.poly([(3, 6), (6, 3), (10, 2), (14, 4), (9, 6), (5, 8)], l)
        p.poly([(12, 7), (16, 5), (18, 9), (18, 11), (11, 11)], d)
        p.hline(1, 11, 18, d)
        for (x, y) in ((5, 8), (8, 5), (11, 8), (14, 6), (7, 10), (16, 9), (4, 6)):
            p.set(x, y, o)
        for (x, y) in ((8, 4), (12, 9), (5, 9)):
            p.set(x, y, ol)
        return p.outline(OUT)

    def worn():
        p = Px(w, h)
        p.poly([(1, 12), (2, 9), (6, 6), (11, 5), (15, 7), (18, 10), (18, 12)], g)
        p.poly([(5, 9), (8, 7), (11, 7), (9, 9)], l)
        p.poly([(12, 9), (16, 9), (17, 11), (12, 11)], d)
        p.hline(2, 11, 16, d)
        for (x, y) in ((6, 10), (10, 8), (14, 10)):
            p.set(x, y, o)
        p.set(9, 8, ol)
        p.line(8, 7, 10, 10, dd)
        return p.outline(OUT)

    def gone():
        p = Px(w, h)
        for (x, y, r) in ((4, 10, 1.6), (9, 11, 1.3), (14, 10, 1.8), (17, 11, 1.1)):
            p.ellipse(x, y, r + 0.4, r, g)
        p.set(4, 9, l); p.set(14, 9, l); p.set(9, 11, o); p.hline(2, 12, 16, d)
        return p.outline(OUT)

    return _sheet(w, h, [full(), worn(), gone()])


def tree():   # 枯れ木（16x24）: 砂漠の乾いた木。葉はわずか
    w, h = 16, 24
    b = hexc("9a6a3a"); bl = hexc("c99a5c"); bd = hexc("6e4726")
    gr = hexc("4f9a4a"); gl = hexc("7fc46a"); gd = hexc("2f6a3a")

    def full():
        p = Px(w, h)
        p.rect(6, 12, 4, 11, b); p.vline(7, 12, 11, bl); p.vline(9, 13, 10, bd)
        p.poly([(5, 23), (6, 20), (10, 20), (11, 23)], b)            # 根もと
        p.line(7, 13, 2, 7, b); p.line(8, 13, 3, 7, bd)              # 左の枝
        p.line(9, 12, 14, 5, b); p.line(8, 12, 13, 5, bd)            # 右の枝
        p.line(8, 9, 7, 3, b); p.line(9, 9, 8, 3, bd)                # 上の枝
        p.ellipse(3, 6, 3, 2, gr); p.ellipse(3, 5, 2, 1, gl)
        p.ellipse(13, 4, 3, 2, gr); p.ellipse(13, 3, 2, 1, gl)
        p.ellipse(7, 2, 3, 2, gr); p.ellipse(7, 1, 2, 1, gl)
        p.set(3, 7, gd); p.set(13, 5, gd); p.set(8, 3, gd)
        return p.outline(OUT)

    def worn():
        p = Px(w, h)
        p.rect(6, 13, 4, 10, b); p.vline(7, 13, 10, bl); p.vline(9, 14, 9, bd)
        p.poly([(5, 23), (6, 21), (10, 21), (11, 23)], b)
        p.line(7, 14, 3, 9, b); p.line(9, 13, 13, 8, b)
        p.ellipse(3, 8, 2, 1.4, gr); p.set(3, 7, gl)
        p.set(7, 12, bd); p.set(8, 16, bd)
        return p.outline(OUT)

    def gone():
        p = Px(w, h)
        p.rect(5, 19, 6, 4, b); p.hline(5, 19, 6, bl); p.hline(5, 22, 6, bd)
        p.set(7, 20, bd); p.set(9, 21, bd)
        p.line(1, 22, 4, 21, b); p.line(11, 22, 14, 21, b)          # 倒れた枝
        return p.outline(OUT)

    return _sheet(w, h, [full(), worn(), gone()])


# 採取ポイントの絵: 種類 -> (作る関数, 1コマの幅, 高さ)
POINTS = {"rock": (rock, 20, 12), "vein": (vein, 20, 13), "tree": (tree, 16, 24)}


def write_all(root=ROOT):
    """道具のアイコン（assets/resources/item_*.png）と採取ポイントの絵（assets/gather/*.png）を書き出す。"""
    d1 = os.path.join(root, "resources")
    d2 = os.path.join(root, "gather")
    os.makedirs(d1, exist_ok=True)
    os.makedirs(d2, exist_ok=True)
    for k, fn in TOOLS.items():
        fn().save(os.path.join(d1, f"item_{k}.png"))
        print("wrote resources", f"item_{k}.png", S, "x", S)
    for k, (fn, w, h) in POINTS.items():
        sh = fn()
        sh.save(os.path.join(d2, f"{k}.png"))
        print("wrote gather", f"{k}.png", sh.w, "x", sh.h)


def preview(path):
    bg = hexc("d9a95f")
    pad = 4
    tools = list(TOOLS.values())
    W = max(len(tools) * (S + pad), sum(w * 3 + pad for (_, w, _) in POINTS.values())) + pad
    H = S + 28 + pad * 3
    big = Px(W, H, bg)
    for i, fn in enumerate(tools):
        big.im.alpha_composite(fn().im, (pad + i * (S + pad), pad))
    x = pad
    for (fn, w, h) in POINTS.values():
        big.im.alpha_composite(fn().im, (x, S + pad * 2))
        x += w * 3 + pad
    big.save(path, 8)


if __name__ == "__main__":
    if "--preview" in sys.argv:
        out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_preview_gather.png")
        preview(out)
        print("preview:", out)
    else:
        write_all()
