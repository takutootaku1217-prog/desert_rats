from pxlib import *

OUT = hexc("2a1c1a")
S = 12   # アイコンのサイズ


def scrap():
    p = Px(S, S)
    p.poly([(1, 8), (2, 3), (6, 1), (10, 3), (10, 8), (7, 10), (3, 10)], hexc("8f979f"))
    p.poly([(2, 4), (5, 2), (8, 3), (6, 5), (3, 6)], hexc("c3cad0"))
    p.hline(6, 8, 4, hexc("6a7178"))
    p.set(3, 8, hexc("b5652e")); p.set(4, 9, hexc("b5652e")); p.set(9, 5, hexc("b5652e"))
    p.set(5, 6, hexc("2a1c1a"))
    return p.outline(OUT)


def cloth():
    p = Px(S, S)
    p.ellipse(6, 6, 4.5, 3.6, hexc("b04a3c"))
    p.ellipse(6, 5, 3.4, 2.2, hexc("d2705a"))
    for x in range(2, 10, 3):
        p.vline(x, 4, 5, hexc("e8c25a"))
    p.rect(9, 8, 2, 2, hexc("b04a3c"))
    p.set(10, 10, hexc("b04a3c"))
    return p.outline(OUT)


def bone():
    p = Px(S, S)
    w = hexc("efe7d2"); sh = hexc("c9bfa4")
    p.line(3, 9, 9, 3, w)
    p.line(4, 9, 10, 3, w)
    p.line(3, 10, 9, 4, sh)
    p.rect(1, 8, 3, 3, w); p.rect(8, 1, 3, 3, w)
    p.set(2, 10, sh); p.set(9, 2, sh)
    p.set(1, 8, CLEAR); p.set(10, 1, CLEAR)
    return p.outline(OUT)


def cactus():
    p = Px(S, S)
    g = hexc("4f9a4a"); gl = hexc("7fc46a"); gd = hexc("2f6a3a")
    p.rect(4, 2, 4, 9, g)
    p.rect(1, 4, 2, 4, g); p.rect(1, 7, 4, 2, g)
    p.rect(9, 3, 2, 4, g); p.rect(7, 6, 4, 2, g)
    p.vline(5, 2, 9, gl)
    p.vline(7, 3, 8, gd)
    p.set(5, 1, hexc("f07aa0")); p.set(6, 1, hexc("f07aa0"))
    for (x, y) in ((4, 4), (7, 5), (4, 8), (2, 5)):
        p.set(x, y, hexc("e8e0b0"))
    return p.outline(OUT)


def wood():
    p = Px(S, S)
    b = hexc("9a6a3a"); d = hexc("6e4726"); l = hexc("c99a5c")
    p.rect(1, 6, 10, 3, b); p.hline(1, 8, 10, d); p.hline(1, 6, 10, l)
    p.rect(2, 3, 8, 3, b); p.hline(2, 5, 8, d); p.hline(2, 3, 8, l)
    p.ellipse(10, 7, 1.6, 1.6, l); p.set(10, 7, d)
    p.set(3, 4, d); p.set(6, 7, d)
    return p.outline(OUT)


def metal():   # 金属板
    p = Px(S, S)
    p.poly([(1, 8), (3, 3), (11, 3), (9, 8)], hexc("cfd6dc"))
    p.rect(1, 8, 9, 2, hexc("8f979f"))
    p.hline(3, 3, 8, hexc("f4f7fa"))
    p.set(4, 5, hexc("9aa3ad")); p.set(8, 5, hexc("9aa3ad"))
    return p.outline(OUT)


def fabric():  # 布地
    p = Px(S, S)
    p.rect(1, 3, 10, 7, hexc("d2705a"))
    p.hline(1, 3, 10, hexc("ecb19a"))
    p.hline(1, 6, 10, hexc("e8c25a"))
    p.hline(1, 9, 10, hexc("8f3a30"))
    p.rect(9, 4, 2, 5, hexc("b04a3c"))
    return p.outline(OUT)


def bone_prod():  # 骨材
    p = Px(S, S)
    w = hexc("efe7d2"); sh = hexc("c9bfa4")
    for i, x in enumerate((2, 5, 8)):
        p.rect(x, 2, 2, 8, w)
        p.vline(x + 1, 2, 8, sh)
        p.rect(x - 1 if i != 1 else x, 1, 3, 1, w)
    p.hline(1, 6, 10, hexc("8b5a32"))
    return p.outline(OUT)


def food():  # サボテン食
    p = Px(S, S)
    p.ellipse(6, 7, 5, 3, hexc("8b5a32"))
    p.ellipse(6, 6, 4.6, 2.2, hexc("e8c25a"))
    p.rect(3, 4, 3, 2, hexc("7fc46a")); p.rect(7, 5, 2, 2, hexc("7fc46a"))
    p.set(6, 3, hexc("f07aa0")); p.set(5, 6, hexc("f07aa0"))
    return p.outline(OUT)


def plank():
    p = Px(S, S)
    b = hexc("dba868"); d = hexc("a8763c"); l = hexc("f0cc8c")
    p.rect(1, 3, 10, 3, b); p.hline(1, 3, 10, l); p.hline(1, 5, 10, d)
    p.rect(2, 6, 9, 3, b); p.hline(2, 6, 9, l); p.hline(2, 8, 9, d)
    p.set(4, 4, d); p.set(8, 7, d)
    return p.outline(OUT)


# ---------------- 第1段階（生物資源）で使う素材・加工品 ----------------

def meat():   # 生肉
    p = Px(S, S)
    r = hexc("c8453c"); rl = hexc("e27a66"); rd = hexc("8e2a26"); w = hexc("f3e6d6")
    p.ellipse(5.5, 6.5, 4.6, 3.6, r)
    p.ellipse(5, 5.5, 3, 2, rl)
    p.hline(3, 8, 5, rd); p.set(2, 7, rd)
    p.rect(9, 3, 2, 2, w); p.set(10, 2, w); p.set(8, 5, w)   # 骨の先
    p.set(4, 6, w); p.set(6, 7, w)                            # 脂のさし
    return p.outline(OUT)


def hide():   # 皮
    p = Px(S, S)
    b = hexc("b88550"); l = hexc("d8aa70"); d = hexc("8a5e34")
    p.poly([(1, 3), (4, 2), (8, 2), (11, 3), (10, 6), (11, 9), (7, 10), (4, 10), (1, 9), (2, 6)], b)
    p.ellipse(6, 5, 3, 1.6, l)
    p.set(3, 8, d); p.set(8, 8, d); p.set(6, 7, d); p.set(4, 4, d)
    return p.outline(OUT)


def fat():    # 脂肪
    p = Px(S, S)
    y = hexc("f1e2a8"); yl = hexc("fff6d4"); yd = hexc("d4bd78")
    p.ellipse(6, 7, 4.6, 3.4, y)
    p.ellipse(5, 6, 2.6, 1.6, yl)
    p.hline(3, 9, 6, yd); p.set(9, 7, yd)
    p.set(7, 4, yl)
    return p.outline(OUT)


def stone():  # 石
    p = Px(S, S)
    g = hexc("8d8a86"); l = hexc("b8b4ae"); d = hexc("5f5c59")
    p.poly([(1, 9), (2, 5), (5, 2), (9, 3), (11, 6), (10, 10), (4, 10)], g)
    p.poly([(3, 5), (5, 3), (8, 4), (6, 6)], l)
    p.hline(3, 9, 7, d); p.set(9, 7, d); p.set(6, 7, d)
    return p.outline(OUT)


def iron_ore():  # 鉄鉱石
    p = Px(S, S)
    g = hexc("6f5f58"); l = hexc("927d72"); d = hexc("4a3d38"); o = hexc("c46a3a"); ol = hexc("e89a62")
    p.poly([(1, 9), (2, 4), (6, 2), (10, 4), (11, 8), (8, 10), (3, 10)], g)
    p.poly([(3, 4), (6, 3), (8, 5), (5, 6)], l)
    for (x, y) in ((4, 7), (7, 6), (8, 8), (3, 5)):
        p.set(x, y, o)
    p.set(7, 5, ol); p.set(5, 8, ol)
    p.hline(3, 9, 6, d)
    return p.outline(OUT)


def iron():   # 鉄（インゴット）
    p = Px(S, S)
    m = hexc("a9b1b9"); l = hexc("dfe5ea"); d = hexc("6d757d")
    p.poly([(1, 9), (3, 5), (10, 5), (11, 9)], m)
    p.hline(3, 5, 8, l); p.hline(2, 6, 9, l)
    p.hline(1, 9, 11, d); p.set(11, 8, d)
    p.poly([(2, 5), (4, 2), (9, 2), (10, 5)], m)
    p.hline(4, 2, 6, l)
    return p.outline(OUT)


def food_ration():   # 食料（干し肉）
    p = Px(S, S)
    b = hexc("8e4a2c"); l = hexc("b86a3e"); d = hexc("5e2e1a"); s = hexc("e8c25a")
    p.poly([(1, 5), (5, 2), (11, 4), (10, 7), (6, 10), (2, 9)], b)
    p.line(3, 6, 8, 4, l); p.line(3, 8, 9, 6, l)
    p.hline(2, 9, 4, d)
    p.rect(5, 1, 1, 10, s)   # ひも
    return p.outline(OUT)


def fuel():   # 燃料（燃料缶）
    p = Px(S, S)
    r = hexc("c9502e"); rl = hexc("e57a4a"); rd = hexc("8a3220"); y = hexc("f0c040")
    p.rect(2, 3, 8, 8, r)
    p.vline(3, 3, 8, rl); p.vline(9, 3, 8, rd)
    p.rect(6, 1, 3, 2, hexc("6d757d"))
    p.rect(4, 5, 4, 3, y)
    p.set(5, 6, rd); p.set(6, 6, rd)
    return p.outline(OUT)


def repair_kit():   # 修理資材（束ねた板とボルト）
    p = Px(S, S)
    b = hexc("dba868"); d = hexc("a8763c"); m = hexc("a9b1b9"); md = hexc("6d757d")
    p.rect(1, 4, 10, 3, b); p.hline(1, 6, 10, d)
    p.rect(1, 7, 10, 3, b); p.hline(1, 9, 10, d)
    p.vline(3, 3, 8, hexc("8a5e34")); p.vline(8, 3, 8, hexc("8a5e34"))
    p.rect(9, 1, 2, 3, m); p.set(10, 3, md)
    p.rect(5, 1, 2, 2, m)
    return p.outline(OUT)


ITEMS = {
    "scrap": scrap, "cloth": cloth, "bone": bone, "cactus": cactus, "wood": wood,
    "metal": metal, "fabric": fabric, "bone_prod": bone_prod, "food": food, "plank": plank,
    "meat": meat, "hide": hide, "fat": fat, "stone": stone, "iron_ore": iron_ore,
    "iron": iron, "ration": food_ration, "fuel": fuel, "repair_kit": repair_kit,
}

if __name__ == "__main__":
    import os
    os.makedirs("/tmp/pxprev", exist_ok=True)
    W = (S + 2) * len(ITEMS)
    big = Px(W, S + 2, hexc("d9a95f"))
    for i, (k, fn) in enumerate(ITEMS.items()):
        big.im.alpha_composite(fn().im, (i * (S + 2), 0))
    big.save("/tmp/pxprev/items.png", 8)
