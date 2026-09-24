import math, random
from pxlib import *

W = 320


def per(x, k, ph=0.0):
    """幅Wで継ぎ目なく繰り返す正弦"""
    return math.sin(2 * math.pi * k * x / W + ph)


def sky():
    p = Px(W, 100)
    stops = [hexc("d98a52"), hexc("e8a25e"), hexc("f2bd72"), hexc("f8d68e"), hexc("fbe6ac")]
    for y in range(100):
        t = y / 99.0 * (len(stops) - 1)
        i = min(int(t), len(stops) - 2)
        f = t - i
        c0, c1 = stops[i], stops[i + 1]
        for x in range(W):
            # 帯の境目をディザで混ぜる
            th = ((x % 2) + 2 * (y % 2)) / 4.0
            p.set(x, y, c1 if f > th else c0)
    # 太陽（ディザのハロー付き）
    cx, cy = 246, 34
    for r, c in ((26, hexc("f6c878")), (20, hexc("fadb92")), (15, hexc("fdeab0"))):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                d = math.hypot(x - cx, y - cy)
                if d <= r and (r >= 20 and (x + y) % 2 == 0 or r < 20):
                    p.set(x, y, c)
    for y in range(cy - 11, cy + 12):
        for x in range(cx - 11, cx + 12):
            if math.hypot(x - cx, y - cy) <= 10.5:
                p.set(x, y, hexc("fff6d0"))
    return p


def clouds():
    p = Px(W, 40)
    rnd = random.Random(7)
    for i in range(7):
        cx = int(i * W / 7 + rnd.randint(-6, 6))
        cy = rnd.randint(10, 30)
        ln = rnd.randint(22, 40)
        for x in range(-ln // 2, ln // 2):
            hh = int(2 + 1.4 * math.sin(x / ln * math.pi) * 2)
            for y in range(-hh + 1, 1):
                p.set((cx + x) % W, cy + y, hexc("fbe0b0", 200))
            p.set((cx + x) % W, cy + 1, hexc("e9a868", 200))
    return p


def mesa(h, base_col, top_col, seed, step=5, amp=0.55, ruin=False):
    p = Px(W, h)
    rnd = random.Random(seed)
    heights = []
    for x in range(W):
        v = (per(x, 2, seed) * 0.5 + per(x, 5, seed * 2) * 0.3 + per(x, 11, seed * 3) * 0.15 + 1.0) / 2.0
        v = v * amp + 0.15
        hh = int(v * h)
        hh = (hh // step) * step   # 段々の台地状
        heights.append(hh)
    for x in range(W):
        for y in range(h - heights[x], h):
            p.set(x, y, base_col)
        if heights[x] > 0:
            top = h - heights[x]
            p.set(x, top, top_col)
            p.set(x, top + 1, top_col)
    # 崖の縦縞（岩肌）
    dark = tuple(max(0, c - 22) for c in base_col[:3]) + (255,)
    for x in range(0, W, 3):
        hh = heights[x]
        if hh > 6:
            for y in range(h - hh + 3, h - 1, 2):
                if rnd.random() < 0.55:
                    p.set(x, y, dark)
    if ruin:
        sil = tuple(max(0, c - 55) for c in base_col[:3]) + (255,)
        for i in range(6):
            x = int(i * W / 6 + rnd.randint(-8, 8)) % W
            hh = heights[x]
            top = h - hh
            kind = rnd.choice(["tower", "pylon", "pipe", "silo"])
            if kind == "tower":
                tw, th = rnd.randint(4, 6), rnd.randint(10, 18)
                p.rect(x, top - th, tw, th, sil)
                for wy in range(top - th + 3, top - 2, 4):
                    p.set(x + 1, wy, base_col)
                p.rect(x, top - th, 2, 3, CLEAR) if rnd.random() < 0.5 else None
            elif kind == "pylon":
                p.vline(x, top - 20, 20, sil); p.vline(x + 5, top - 20, 20, sil)
                p.line(x, top - 20, x + 5, top - 10, sil); p.line(x + 5, top - 20, x, top - 10, sil)
                p.hline(x - 2, top - 21, 10, sil)
            elif kind == "pipe":
                p.rect(x, top - 9, 3, 9, sil)
                p.rect(x, top - 9, 12, 3, sil)
            else:
                p.rect(x, top - 10, 8, 10, sil)
                p.ellipse(x + 4, top - 10, 4, 2, sil)
                p.rect(x + 3, top - 15, 2, 5, sil)
    return p


def dunes():
    p = Px(W, 30)
    a = hexc("e2ae62"); b = hexc("c98f4a"); c = hexc("f0c47c")
    for x in range(W):
        v = per(x, 3, 1.0) * 0.5 + per(x, 7, 2.0) * 0.25 + per(x, 13, 0.5) * 0.1
        top = int(11 + v * 8)
        for y in range(top, 30):
            p.set(x, y, a)
        # 日の当たる稜線と影
        p.set(x, top, c)
        for y in range(top + 1, min(30, top + 4 + int((per(x, 3, 1.0) + 1) * 2))):
            if (x + y) % 2 == 0:
                p.set(x, y, b)
    return p


def ground():
    p = Px(W, 46)
    base = hexc("e6b466"); dk = hexc("cf9a50"); dkk = hexc("b98240"); lt = hexc("f3c97e")
    for y in range(46):
        for x in range(W):
            p.set(x, y, base)
    # 手前ほど濃くなるディザ
    for y in range(46):
        lvl = 0 if y < 4 else (1 if y < 18 else (2 if y < 32 else 3))
        for x in range(W):
            if lvl and ((x + y) % 2 == 0 if lvl >= 2 else (x % 2 == 0 and y % 2 == 0)):
                p.set(x, y, dk)
    # 奥の縁（ハイライト）
    p.hline(0, 0, W, dkk)
    p.hline(0, 1, W, lt)
    rnd = random.Random(3)
    # 砂のさざなみ
    for i in range(70):
        x = rnd.randint(0, W - 1); y = rnd.randint(4, 44); ln = rnd.randint(4, 12)
        for k in range(ln):
            p.set((x + k) % W, y, dkk if k % 2 == 0 else dk)
    # 小石
    for i in range(24):
        x = rnd.randint(0, W - 1); y = rnd.randint(6, 43)
        p.set(x, y, hexc("8a6a48")); p.set((x + 1) % W, y, hexc("a98460")); p.set(x, y - 1, hexc("c9a070"))
    # わだち
    for x in range(W):
        if x % 3 != 0:
            p.set(x, 42, dkk)
    return p


def props():
    """地面の奥の縁に流れる小物（サボテン・岩・骨・杭）"""
    p = Px(W, 26)
    rnd = random.Random(11)
    def cactus_at(x, hh):
        g = hexc("4f9a4a"); gl = hexc("7fc46a"); gd = hexc("2f6a3a")
        p.rect(x, 26 - hh, 3, hh, g); p.vline(x, 26 - hh, hh, gl); p.vline(x + 2, 26 - hh, hh, gd)
        p.rect(x - 3, 26 - hh + 4, 2, 5, g); p.rect(x - 3, 26 - hh + 8, 5, 2, g)
        p.rect(x + 4, 26 - hh + 2, 2, 4, g); p.rect(x + 3, 26 - hh + 5, 3, 2, g)
        p.set(x + 1, 26 - hh - 1, hexc("f07aa0"))
    def rock_at(x, r):
        p.ellipse(x, 25 - r * 0.6, r, r * 0.7, hexc("a67c52"))
        p.ellipse(x - r * 0.3, 25 - r * 0.9, r * 0.6, r * 0.35, hexc("c99a6a"))
        p.hline(int(x - r), 25, int(r * 2), hexc("7d5a3a"))
    def bones_at(x):
        w = hexc("efe7d2")
        p.hline(x, 24, 8, w); p.set(x - 1, 23, w); p.set(x - 1, 25, w); p.set(x + 8, 23, w); p.set(x + 8, 25, w)
        p.ellipse(x + 13, 22, 4, 3, w); p.set(x + 12, 21, hexc("2a1c1a")); p.set(x + 15, 21, hexc("2a1c1a"))
    def post_at(x):
        p.vline(x, 12, 14, hexc("7a5230")); p.rect(x - 2, 12, 5, 2, hexc("946a41"))
        p.line(x + 3, 14, x + 9, 20, hexc("5c3d22"))
    xs = sorted(rnd.sample(range(10, W - 30, 30), 8))
    kinds = ["cactus", "rock", "post", "cactus", "bones", "rock", "cactus", "post"]
    for x, k in zip(xs, kinds):
        if k == "cactus": cactus_at(x, rnd.randint(12, 18))
        elif k == "rock": rock_at(x, rnd.randint(5, 8))
        elif k == "bones": bones_at(x)
        else: post_at(x)
    return p.outline(hexc("2a1c1a"))


def build():
    return dict(sky=sky(), clouds=clouds(),
                mesa_far=mesa(46, hexc("d09a5c"), hexc("f0c88a"), 1.3, step=5, amp=0.62),
                mesa_mid=mesa(42, hexc("b0703c"), hexc("d99a5c"), 2.1, step=4, amp=0.45, ruin=True),
                dunes=dunes(), ground=ground(), props=props())


if __name__ == "__main__":
    import os
    os.makedirs("/tmp/pxprev", exist_ok=True)
    L = build()
    scene = Px(W, 180, hexc("f8d68e"))
    scene.im.alpha_composite(L["sky"].im, (0, 0))
    scene.im.alpha_composite(L["clouds"].im, (0, 20))
    scene.im.alpha_composite(L["mesa_far"].im, (0, 60))
    scene.im.alpha_composite(L["mesa_mid"].im, (0, 85))
    scene.im.alpha_composite(L["dunes"].im, (0, 110))
    scene.im.alpha_composite(L["ground"].im, (0, 134))
    scene.im.alpha_composite(L["props"].im, (0, 118))
    scene.save("/tmp/pxprev/env.png", 4)
