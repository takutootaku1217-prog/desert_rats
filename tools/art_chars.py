from pxlib import *

# 仲間（人間）のドット絵。16x16 のコマを横に13コマ並べた1枚（assets/characters/crew_<key>.png）。
# コマの順番は scripts/character.gd の F_* と同じにすること（FRAME_INDEX 参照）。
# 向きは右向き（ゲーム側で左右反転する）。足元は最下行(15)。

OUT = hexc("2a1c1a")
EYE = hexc("1c1414")
METAL = hexc("9aa3ad")
WOOD = hexc("8b5a32")
LENS = hexc("f6d36a")

# key はセーブデータにも入る名前なので、既存の grey / tan / pink は変えないこと。
# style: short(短髪) / long(長髪) / ponytail(ポニーテール) / hat(つば広の帽子)
# gear: none / goggles(ゴーグル) / bandana(バンダナ)
PALETTES = {
    "grey":  dict(skin=hexc("f0c8a0"), skin_d=hexc("d4a07c"), hair=hexc("3a2a22"), jacket=hexc("7a8a6a"), jacket_d=hexc("5c6b50"),
                  pants=hexc("4a4f5c"), boots=hexc("3a2a22"), scarf=hexc("d8452e"), style="short", gear="goggles"),
    "tan":   dict(skin=hexc("d9a87a"), skin_d=hexc("b98456"), hair=hexc("6a4326"), jacket=hexc("c9a877"), jacket_d=hexc("9c7d52"),
                  pants=hexc("5a4a3a"), boots=hexc("3a2a22"), scarf=hexc("2fa3a0"), style="hat", gear="none"),
    "pink":  dict(skin=hexc("f6d6bc"), skin_d=hexc("dcb094"), hair=hexc("e08aa0"), jacket=hexc("efe3cc"), jacket_d=hexc("c2b096"),
                  pants=hexc("5a4a68"), boots=hexc("3a2a3a"), scarf=hexc("e8b530"), style="long", gear="none"),
    "blue":  dict(skin=hexc("a8703c"), skin_d=hexc("865526"), hair=hexc("1c1a1e"), jacket=hexc("4a78a8"), jacket_d=hexc("35577c"),
                  pants=hexc("3a3f4a"), boots=hexc("2a2226"), scarf=hexc("e8802e"), style="short", gear="bandana"),
    "green": dict(skin=hexc("e0b088"), skin_d=hexc("c08c62"), hair=hexc("9c4a26"), jacket=hexc("6f8f4a"), jacket_d=hexc("52703a"),
                  pants=hexc("5a4632"), boots=hexc("3a2a22"), scarf=hexc("8a5ac8"), style="ponytail", gear="none"),
    "red":   dict(skin=hexc("e8bc94"), skin_d=hexc("cc9a72"), hair=hexc("c9c4bc"), jacket=hexc("b8503a"), jacket_d=hexc("8a3a2a"),
                  pants=hexc("3a3038"), boots=hexc("2a2226"), scarf=hexc("efe7d2"), style="hat", gear="goggles"),
}


def _head_side(p, pal, s, dx=0):
    """横向きの頭（右向き）。s = 体を下げる量。"""
    sk, hair = pal["skin"], pal["hair"]
    x = dx
    p.rect(5 + x, 2 + s, 6, 4, sk)
    p.rect(6 + x, 1 + s, 4, 1, sk)
    p.rect(6 + x, 6 + s, 4, 1, sk)
    p.set(11 + x, 4 + s, sk)                      # 鼻
    p.set(8 + x, 6 + s, pal["skin_d"])            # あごの影
    p.set(9 + x, 4 + s, EYE)                      # 目
    style = pal["style"]
    if style == "hat":
        p.rect(4 + x, 2 + s, 8, 1, pal["jacket_d"])       # つば
        p.rect(6 + x, 0 + s, 4, 2, pal["jacket"])          # 帽子の頭
        p.hline(6 + x, 1 + s, 4, pal["jacket_d"])
        p.rect(5 + x, 3 + s, 1, 2, hair)                   # 後ろ髪
    else:
        p.rect(5 + x, 1 + s, 5, 2, hair)                   # 前髪と頭頂
        p.rect(5 + x, 3 + s, 2, 2, hair)                   # 後ろ髪
        p.set(10 + x, 2 + s, hair)
        if style == "long":
            p.rect(4 + x, 3 + s, 2, 6, hair)
        elif style == "ponytail":
            p.rect(3 + x, 3 + s, 2, 1, hair)
            p.rect(3 + x, 4 + s, 1, 4, hair)
    gear = pal["gear"]
    if gear == "goggles":
        p.hline(5 + x, 2 + s, 6, hexc("6a5a3a"))
        p.rect(9 + x, 2 + s, 2, 2, LENS)
        p.set(9 + x, 3 + s, hexc("c89a30"))
    elif gear == "bandana":
        p.hline(5 + x, 2 + s, 6, pal["scarf"])
        p.set(4 + x, 3 + s, pal["scarf"])
        p.set(4 + x, 4 + s, pal["scarf"])


def side(pal, s=0, legs=(6, 8), lift=(0, 0), arm=(0, 0), tool=None, reach=None, carry=False, head_dx=0):
    """横向きの立ち姿。s = 体（頭と胴）を下げる量、legs = 足の左端x、lift = 足の持ち上げ、
    arm = 腕の(dx, dy)、tool = (手x, 手y, 先x, 先y)、reach = 手を伸ばす先(x, y)、carry = 荷物を抱える。"""
    p = Px(16, 16)
    jk, jd = pal["jacket"], pal["jacket_d"]
    # 脚（奥の脚は暗く）
    for i, lx in enumerate(legs):
        bottom = 15 - lift[i]
        top = 12 + s
        col = pal["pants"]
        if i == 0:
            col = hexc("2f3440") if pal["pants"] == hexc("4a4f5c") else pal["pants"]
        if bottom > top:
            p.rect(lx, top, 2, bottom - top, col)
        p.rect(lx, bottom, 3, 1, pal["boots"])
    # 胴
    p.rect(6, 8 + s, 4, 4, jk)
    p.vline(6, 8 + s, 3, jd)
    p.hline(6, 11 + s, 4, pal["pants"])           # ベルト
    p.set(8, 11 + s, METAL)
    # スカーフ
    p.rect(6, 7 + s, 5, 1, pal["scarf"])
    p.set(5, 8 + s, pal["scarf"])
    p.set(4, 9 + s, pal["scarf"])
    # 頭
    _head_side(p, pal, s, head_dx)
    # 腕
    ax, ay = arm
    if reach is not None:
        rx, ry = reach
        p.line(8, 9 + s, rx, ry, jd)
        p.set(rx, ry, pal["skin"])
    elif tool is not None:
        hx0, hy0, hx1, hy1 = tool
        p.line(8, 9 + s, hx0, hy0, jd)
        p.set(hx0, hy0, pal["skin"])
        p.line(hx0, hy0, hx1, hy1, WOOD)
        p.rect(hx1 - 1, hy1 - 1, 3, 2, METAL)
    elif carry:
        p.rect(8, 9 + s, 3, 2, jd)
        p.set(11, 9 + s, pal["skin"])
        p.set(11, 10 + s, pal["skin"])
    else:
        p.rect(7 + ax, 8 + s + ay, 2, 3, jd)
        p.set(8 + ax, 11 + s + ay, pal["skin"])
    return p


def back(pal, arms=(0, 1), legs=(0, 1)):
    """後ろ向き（ハシゴを登る）。arms / legs は左右の上下位置（0 か 1）。"""
    p = Px(16, 16)
    jk, jd, sk, hair = pal["jacket"], pal["jacket_d"], pal["skin"], pal["hair"]
    # 脚
    for lx, lg in ((5, legs[0]), (9, legs[1])):
        p.rect(lx, 12 + lg, 2, 3 - lg, pal["pants"])
        p.rect(lx, 15, 2, 1, pal["boots"])
    # 胴
    p.rect(5, 7, 6, 5, jk)
    p.vline(8, 8, 3, jd)
    p.hline(5, 11, 6, pal["pants"])
    p.rect(5, 7, 6, 1, pal["scarf"])
    # 頭（後頭部）
    p.rect(5, 1, 6, 5, hair)
    p.rect(6, 6, 4, 1, sk)
    if pal["style"] == "hat":
        p.rect(4, 2, 8, 1, jd)
        p.rect(6, 0, 4, 2, jk)
    elif pal["style"] == "long":
        p.rect(5, 6, 6, 3, hair)
    elif pal["style"] == "ponytail":
        p.rect(7, 6, 2, 3, hair)
    if pal["gear"] == "bandana":
        p.hline(5, 2, 6, pal["scarf"])
    elif pal["gear"] == "goggles":
        p.hline(5, 2, 6, hexc("6a5a3a"))
    # 腕（ハシゴを握る）
    for ax, ar in ((3, arms[0]), (11, arms[1])):
        p.rect(ax, 3 + ar * 3, 2, 4, jd)
        p.set(ax, 2 + ar * 3, sk)
        p.set(ax + 1, 2 + ar * 3, sk)
    return p


def sleep(pal):
    """あお向けに寝る。頭は左（ベッドの枕の側）。"""
    p = Px(16, 16)
    jk, jd, sk, hair = pal["jacket"], pal["jacket_d"], pal["skin"], pal["hair"]
    # 脚
    p.rect(11, 10, 4, 3, pal["pants"])
    p.rect(15, 10, 1, 3, pal["boots"])
    # 胴
    p.rect(5, 9, 6, 4, jk)
    p.hline(5, 9, 6, jd)
    p.rect(6, 9, 1, 4, pal["scarf"])
    # 頭
    p.rect(1, 9, 5, 4, sk)
    p.rect(1, 8, 5, 2, hair)
    p.rect(0, 9, 1, 3, hair)
    if pal["style"] == "hat":
        p.rect(1, 6, 4, 2, pal["jacket"])
        p.rect(0, 8, 6, 1, pal["jacket_d"])
    elif pal["style"] == "long":
        p.rect(0, 12, 3, 1, hair)
    p.hline(3, 11, 2, EYE)                        # 閉じた目
    # 腕
    p.rect(7, 12, 4, 1, jd)
    return p


def build_human(name):
    pal = PALETTES[name]
    frames = []
    frames.append(side(pal))                                                        # 0 idle0
    frames.append(side(pal, s=1))                                                   # 1 idle1（息をするように少し沈む）
    frames.append(side(pal, legs=(4, 9), arm=(-1, 0)))                              # 2 walk0
    frames.append(side(pal, legs=(6, 7), lift=(1, 0), s=1, arm=(0, 0)))             # 3 walk1
    frames.append(side(pal, legs=(9, 4), arm=(1, 0)))                               # 4 walk2
    frames.append(side(pal, legs=(6, 7), lift=(0, 1), s=1, arm=(0, 0)))             # 5 walk3
    frames.append(side(pal, s=2, legs=(4, 8), head_dx=1, reach=(12, 14)))           # 6 pick（かがんで拾う）
    frames.append(side(pal, tool=(11, 9, 14, 5)))                                   # 7 work0
    frames.append(side(pal, tool=(11, 9, 14, 12)))                                  # 8 work1
    frames.append(back(pal, arms=(0, 1), legs=(0, 1)))                              # 9 climb0
    frames.append(back(pal, arms=(1, 0), legs=(1, 0)))                              # 10 climb1
    frames.append(sleep(pal))                                                       # 11 sleep
    frames.append(side(pal, carry=True))                                            # 12 carry
    sheet = Px(16 * len(frames), 16)
    for i, fr in enumerate(frames):
        o = fr.outline(OUT)
        sheet.im.alpha_composite(o.im, (i * 16, 0))
    return sheet


FRAME_INDEX = dict(idle0=0, idle1=1, walk0=2, walk1=3, walk2=4, walk3=5, pick=6,
                   work0=7, work1=8, climb0=9, climb1=10, sleep=11, carry=12)


if __name__ == "__main__":
    import os, tempfile
    d = os.path.join(tempfile.gettempdir(), "pxprev")
    os.makedirs(d, exist_ok=True)
    sheets = [build_human(n) for n in PALETTES]
    big = Px(16 * 13, 17 * len(sheets))
    for i, s in enumerate(sheets):
        big.im.alpha_composite(s.im, (0, i * 17))
    bg = Px(big.w, big.h, hexc("d9a95f"))
    bg.im.alpha_composite(big.im)
    bg.save(os.path.join(d, "crew.png"), 6)
    print("wrote", os.path.join(d, "crew.png"))
