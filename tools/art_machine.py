import math
from pxlib import *
from art_base import C

MW, MH = 28, 24


def machine(frame):
    p = Px(MW, MH)
    # 脚と本体
    p.rect(2, 21, 24, 3, C["steel_d"])
    p.rect(2, 8, 20, 14, C["steel_h"])
    p.hline(2, 8, 20, hexc("c4ccd8")); p.vline(2, 8, 14, C["steel_l"])
    p.rect(3, 9, 18, 12, C["steel_l"])
    for x in (5, 19):
        p.vline(x, 9, 12, C["steel_h"])
    for (x, y) in ((4, 10), (20, 10), (4, 20), (20, 20)):
        p.set(x, y, C["steel_h"])
    # 錆
    for (x, y) in ((7, 19), (8, 20), (16, 10), (17, 11)):
        p.set(x, y, C["rust"])
    # 投入ホッパー（左上）
    p.poly([(0, 0), (11, 0), (9, 8), (2, 8)], C["steel_l"])
    p.poly([(1, 1), (10, 1), (8, 7), (3, 7)], C["steel_m"])
    p.hline(0, 0, 12, C["steel_h"])
    # 煙突
    p.rect(17, 0, 4, 9, C["steel_m"]); p.hline(16, 0, 6, C["steel_h"]); p.rect(17, 5, 4, 1, C["rust"])
    # 歯車（回転）
    cx, cy, r = 12, 15, 5
    p.ellipse(cx, cy, r, r, C["steel_h"]); p.ellipse(cx, cy, r - 2, r - 2, C["steel_m"]); p.set(cx, cy, C["steel_d"])
    for k in range(8):
        a = k * math.pi / 4 + frame * (math.pi / 8)
        if frame == 0:
            a = k * math.pi / 4
        p.rect(int(round(cx + (r + 0.6) * math.cos(a))), int(round(cy + (r + 0.6) * math.sin(a))), 1, 1, hexc("e8edf5"))
    # ランプ（待機=赤 / 稼働=緑）
    p.rect(19, 13, 2, 2, C["red"] if frame == 0 else hexc("4ad88a"))
    # 出力シュートとトレイ
    p.rect(22, 16, 5, 2, C["steel_l"]); p.rect(24, 18, 3, 4, C["steel_m"]); p.rect(23, 21, 5, 1, C["steel_h"])
    # 炉の火（稼働時）
    if frame != 0:
        p.rect(7, 11, 3, 2, hexc("f08a30") if frame == 1 else hexc("ffd060"))
    return p.outline(hexc("15171b"))


def build_machine_sheet():
    sheet = Px((MW + 2) * 3, MH + 2)
    for f in range(3):
        sheet.im.alpha_composite(machine(f).im, (f * (MW + 2), 0))
    return sheet


if __name__ == "__main__":
    import os
    os.makedirs("/tmp/pxprev", exist_ok=True)
    s = build_machine_sheet()
    b = Px(s.w, s.h, hexc("574332")); b.im.alpha_composite(s.im); b.save("/tmp/pxprev/machine.png", 8)
