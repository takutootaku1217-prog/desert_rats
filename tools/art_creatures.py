"""砂漠の生物（オリジナルのドット絵）。すべて無害で、追われると逃げる弱い生物。
各シートは [歩き0, 歩き1, 驚き] の3コマ、右向き。"""
from pxlib import *

OUT = hexc("2a1c1a")
EYE = hexc("1c1414")


def hare_frame(f):   # スナウサギ 14x12
    p = Px(14, 12)
    b = hexc("d8b27a"); l = hexc("f2dcb0"); d = hexc("a8824e"); e = hexc("f0a0a8")
    by = 1 if f == 1 else 0
    # 耳
    p.rect(8, 0 + by, 1, 4, b); p.rect(10, 0 + by, 1, 4, b); p.set(10, 1 + by, e)
    if f == 2:
        p.rect(8, 0, 1, 4, b); p.rect(10, 0, 1, 4, b)
    # 体
    p.ellipse(5.5, 7 + by, 4, 2.8, b)
    p.ellipse(5.5, 8 + by, 3, 1.4, l)
    p.ellipse(9.5, 5 + by, 2.3, 2, b)
    p.set(11, 5 + by, d); p.set(10, 4 + by, EYE)
    p.set(1, 6 + by, l); p.set(1, 7 + by, l)   # しっぽ
    # 脚
    if f == 0:
        p.rect(3, 10, 2, 2, d); p.rect(7, 10, 2, 2, d)
    elif f == 1:
        p.rect(2, 10, 3, 1, d); p.rect(8, 10, 3, 1, d)
    else:
        p.rect(3, 10, 2, 2, d); p.rect(8, 10, 2, 2, d)
    return p.outline(OUT)


def lizard_frame(f):   # トゲトカゲ 18x9
    p = Px(18, 9)
    g = hexc("9a8a4a"); l = hexc("c8b870"); d = hexc("6a5c30"); s = hexc("d86a3a")
    p.rect(3, 4, 10, 3, g)
    p.hline(3, 6, 10, l)
    p.rect(13, 3, 4, 3, g); p.set(16, 5, d); p.set(15, 3, EYE)
    p.line(0, 6, 3, 5, g); p.set(0, 7, g)          # しっぽ
    for x in (5, 8, 11):
        p.set(x, 3, s)                            # 背中のトゲ
    lg = [(4, 11), (5, 10)] if f != 1 else [(3, 12), (6, 9)]
    for a, b2 in lg:
        p.rect(a, 7, 1, 2, d); p.rect(b2, 7, 1, 2, d)
    if f == 2:
        p.set(15, 2, EYE); p.set(15, 3, hexc("ffffff"))
    return p.outline(OUT)


def hump_frame(f):   # コブ獣 22x16（大きくて遅い。脂肪が多い）
    p = Px(22, 16)
    b = hexc("a07458"); l = hexc("c89a78"); d = hexc("6e4a36"); h = hexc("d8c0a0")
    by = 1 if f == 1 else 0
    p.ellipse(10, 9 + by, 7.5, 4.2, b)
    p.ellipse(8, 5 + by, 4, 3.2, l)                # コブ
    p.ellipse(10, 11 + by, 6, 1.4, h)
    p.rect(16, 6 + by, 4, 4, b)                    # 頭
    p.set(19, 8 + by, d); p.set(18, 7 + by, EYE)
    p.set(17, 5 + by, hexc("e8e0c8")); p.set(16, 4 + by, hexc("e8e0c8"))  # 角
    p.set(2, 8 + by, d); p.set(1, 9 + by, d)       # しっぽ
    if f == 0:
        xs = (5, 8, 12, 15)
    elif f == 1:
        xs = (4, 9, 11, 16)
    else:
        xs = (5, 8, 12, 15)
    for i, x in enumerate(xs):
        p.rect(x, 13, 2, 3, d if i % 2 == 0 else b)
    return p.outline(OUT)


def sheet(fn, w, h):
    s = Px(w * 3, h)
    for i in range(3):
        s.paste(fn(i), i * w, 0)
    return s


CREATURES = {
    "hare": (hare_frame, 14, 12),
    "lizard": (lizard_frame, 18, 9),
    "hump": (hump_frame, 22, 16),
}
