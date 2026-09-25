"""人間の仲間キャラの24x24版（試作。ゲームにはまだ使っていない）。すべてオリジナルのドット絵をコードで描く（PILのみ）。
出力: assets/characters/crew24_<key>.png … 24x24 のコマを横に13コマ並べた1枚（コマの順番は 16x16 版・scripts/character.gd の F_* と同じ）。
   0-1 待機 / 2-5 歩き / 6 かがむ(拾う・掘る) / 7-8 作業(道具を振る) / 9-10 はしご / 11 睡眠 / 12 荷物を抱える
向きは右向き（ゲーム側で左右反転する）。足元は下から2行目(22)、最下行(23)は輪郭。色は art_chars.PALETTES を使う（6種類）。
使い方: python tools/art_chars24.py            … assets/ に書き出す
        python tools/art_chars24.py --preview  … tools/_preview_chars24.png に拡大した確認用の画像を書く"""
import os
import sys
from pxlib import *
import art_chars

S = 24
OUT = hexc("2a1c1a")
EYE = hexc("1c1414")
METAL = hexc("9aa3ad")
METAL_L = hexc("dfe5ea")
METAL_D = hexc("6d757d")
WOOD = hexc("8b5a32")
LENS = hexc("f6d36a")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
FRAMES = 13


def shade(c, k):
    return (int(c[0] * k), int(c[1] * k), int(c[2] * k), c[3])


def blush(c):
    return (min(255, c[0] + 6), int(c[1] * 0.86), int(c[2] * 0.84), 255)


# ---------------------------------------------------------------- 部品
def head(p, pal, s=0, dx=0):
    """横向きの頭（右向き）。10x10。s = 体を下げる量、dx = 前へ出す量。"""
    sk, skd, hair = pal["skin"], pal["skin_d"], pal["hair"]
    x, y = 8 + dx, 1 + s
    p.rect(x + 1, y, 8, 1, sk)
    p.rect(x, y + 1, 10, 8, sk)
    p.rect(x + 1, y + 9, 8, 1, sk)
    p.set(x + 10, y + 6, sk)                            # 鼻
    p.hline(x + 2, y + 9, 5, skd)                       # あごの影
    p.rect(x + 2, y + 5, 1, 2, skd)                     # 耳
    p.rect(x + 7, y + 5, 1, 2, EYE)                     # 目
    p.set(x + 8, y + 7, blush(sk))                      # ほお
    p.rect(x + 7, y + 8, 2, 1, skd)                     # 口
    style = pal["style"]
    if style == "hat":
        jk, jd = pal["jacket"], pal["jacket_d"]
        p.rect(x + 2, y, 6, 1, jk)
        p.rect(x + 1, y + 1, 8, 2, jk)
        p.hline(x + 1, y + 2, 8, jd)                    # 帽子のバンド
        p.rect(x - 2, y + 3, 14, 1, jd)                 # つば
        p.hline(x - 1, y + 3, 12, shade(jd, 1.15))
        p.rect(x, y + 4, 2, 3, hair)                    # 後ろ髪
        return
    p.rect(x + 1, y, 8, 1, hair)
    p.rect(x, y + 1, 10, 2, hair)
    p.rect(x, y + 3, 10, 1, hair)                       # 前髪
    p.rect(x, y + 4, 3, 3, hair)                        # 後ろ髪
    p.set(x + 9, y + 4, hair)
    p.hline(x + 2, y + 1, 5, shade(hair, 1.25))         # つや
    gear = pal["gear"]
    if gear == "goggles":
        p.hline(x, y + 3, 10, hexc("6a5a3a"))           # ストラップ
        p.rect(x + 6, y + 1, 4, 3, hexc("6a5a3a"))      # 枠
        p.rect(x + 7, y + 2, 2, 1, LENS)
        p.set(x + 8, y + 2, hexc("fff2b0"))
        p.set(x + 7, y + 3, hexc("c89a30"))
    elif gear == "bandana":
        p.hline(x, y + 3, 10, pal["scarf"])
        p.rect(x - 2, y + 3, 2, 3, pal["scarf"])        # 結び目
        p.set(x - 3, y + 5, pal["scarf"])


def back_hair(p, pal, s=0, dx=0):
    """胴より奥に描く髪（長髪・ポニーテール）。"""
    x, y = 8 + dx, 1 + s
    hair = pal["hair"]
    if pal["style"] == "long":
        p.rect(x - 2, y + 3, 5, 11, hair)
        p.vline(x - 2, y + 3, 11, shade(hair, 0.8))
        p.vline(x, y + 8, 6, shade(hair, 1.15))
    elif pal["style"] == "ponytail":
        p.rect(x - 3, y + 3, 3, 2, hair)
        p.rect(x - 4, y + 5, 2, 7, hair)
        p.set(x - 3, y + 3, pal["scarf"])
        p.vline(x - 4, y + 5, 7, shade(hair, 0.8))


def leg(p, lx, lift, pants, boot):
    """脚。lx = 左端x、lift = 持ち上げ量。足元は行22。"""
    bottom = 22 - lift
    top = 17
    if bottom - 2 >= top:
        p.rect(lx, top, 3, bottom - 1 - top, pants)
    p.rect(lx, bottom - 1, 3, 2, boot)
    p.set(lx + 3, bottom, boot)                         # つま先
    p.set(lx, bottom - 1, shade(boot, 1.3))


def torso(p, pal, s=0, lean=0):
    jk, jd = pal["jacket"], pal["jacket_d"]
    x, y0 = 8 + lean, 11 + s
    h = 17 - y0
    p.rect(x, y0, 8, h, jk)
    p.vline(x, y0, h, jd)                               # 背中側の影
    p.vline(x + 1, y0 + 1, max(0, h - 1), shade(jk, 0.92))
    p.hline(x, 16, 8, pal["pants"])                     # ベルト
    p.set(x + 5, 16, METAL)
    if h >= 5:
        p.rect(x + 4, y0 + 2, 3, 2, jd)                 # ポケット
        p.hline(x + 4, y0 + 2, 3, shade(jd, 1.2))
    sc = pal["scarf"]                                   # スカーフ
    p.rect(x, y0, 8, 2, sc)
    p.rect(x - 2, y0 + 1, 2, 3, sc)
    p.hline(x + 1, y0, 6, shade(sc, 1.2))


def arm(p, sh, hand, sleeve, skin):
    """腕。肩 sh から手 hand まで。手は 2x2。"""
    dx, dy = abs(hand[0] - sh[0]), abs(hand[1] - sh[1])
    p.line(sh[0], sh[1], hand[0], hand[1], sleeve)
    if dy >= dx:
        p.line(sh[0] + 1, sh[1], hand[0] + 1, hand[1], sleeve)
    else:
        p.line(sh[0], sh[1] + 1, hand[0], hand[1] + 1, sleeve)
    p.rect(hand[0], hand[1], 2, 2, skin)


def tool(p, hand, tip):
    """手から先まで、木の柄と金属の頭のある道具（ハンマー/つるはしのような形）。"""
    p.line(hand[0] + 1, hand[1] + 1, tip[0], tip[1], WOOD)
    p.rect(tip[0] - 2, tip[1] - 1, 5, 3, METAL)
    p.hline(tip[0] - 2, tip[1] - 1, 5, METAL_L)
    p.hline(tip[0] - 2, tip[1] + 1, 5, METAL_D)


def figure(pal, s=0, lean=0, hdx=0, legs=(9, 12), lift=(0, 0), front=(0, 6), back=(0, 6), wield=None):
    """立ち姿・歩き・作業など。front / back = 手の位置（肩からの差）。wield = 道具の先の位置（肩からの差）。"""
    p = Px(S, S)
    x, y0 = 8 + lean, 11 + s
    pants = pal["pants"]
    leg(p, legs[0], lift[0], shade(pants, 0.72), shade(pal["boots"], 0.8))
    leg(p, legs[1], lift[1], pants, pal["boots"])
    # 奥の腕（暗い）
    bs = (x + 2, y0 + 2)
    arm(p, bs, (bs[0] + back[0], bs[1] + back[1] - 1), shade(pal["jacket"], 0.7), shade(pal["skin"], 0.85))
    torso(p, pal, s, lean)
    back_hair(p, pal, s, lean + hdx)
    fs = (x + 4, y0 + 2)
    fh = (fs[0] + front[0], fs[1] + front[1] - 1)
    arm(p, fs, fh, shade(pal["jacket"], 1.14), pal["skin"])       # 手前の腕（胴より少し明るい）。上げた腕が顔を隠さないよう頭より先に描く
    head(p, pal, s, lean + hdx)
    if wield is not None:
        tool(p, fh, (fs[0] + wield[0], fs[1] + wield[1]))
    return p


def sleeping(pal):
    """横になって寝ている姿（ゲーム側でベッドの上に持ち上げて描く）。頭が右。"""
    p = Px(S, S)
    sk, hair = pal["skin"], pal["hair"]
    bl, bld = pal["scarf"], shade(pal["scarf"], 0.75)
    p.rect(1, 17, 15, 5, bl)                            # 毛布
    p.hline(1, 17, 15, shade(bl, 1.2))
    p.hline(1, 21, 15, bld)
    for xx in (5, 10):
        p.vline(xx, 18, 3, bld)
    p.rect(0, 20, 2, 2, pal["boots"])                   # 足先
    p.rect(15, 14, 8, 8, hexc("efe7d2"))                # まくら
    p.hline(15, 14, 8, hexc("ffffff"))
    p.rect(16, 13, 6, 8, sk)                            # 頭
    p.rect(17, 12, 4, 1, sk)
    p.rect(16, 12, 6, 3, hair)
    p.rect(16, 15, 2, 4, hair)
    p.set(20, 16, EYE); p.set(21, 16, EYE)              # とじた目
    p.set(21, 18, pal["skin_d"])
    if pal["style"] == "hat":
        p.rect(14, 10, 6, 2, pal["jacket"])
        p.hline(13, 12, 9, pal["jacket_d"])
    return p


def frames(pal):
    f = []
    # 0-1 待機
    f.append(figure(pal, front=(0, 3), back=(0, 3)))
    f.append(figure(pal, s=1, front=(0, 3), back=(0, 3)))
    # 2-5 歩き（接地→通過→接地→通過）
    f.append(figure(pal, s=1, legs=(7, 13), front=(-3, 3), back=(3, 3)))
    f.append(figure(pal, s=0, legs=(10, 10), lift=(2, 0), front=(-1, 4), back=(1, 4)))
    f.append(figure(pal, s=1, legs=(13, 7), front=(3, 3), back=(-3, 3)))
    f.append(figure(pal, s=0, legs=(10, 10), lift=(0, 2), front=(1, 4), back=(-1, 4)))
    # 6 かがんで拾う・掘る
    f.append(figure(pal, s=4, lean=2, hdx=1, legs=(7, 12), front=(5, 4), back=(3, 4)))
    # 7-8 作業（道具を振り上げる→振り下ろす）
    f.append(figure(pal, s=0, lean=1, legs=(8, 12), front=(4, -4), back=(3, -2), wield=(7, -9)))
    f.append(figure(pal, s=1, lean=2, legs=(8, 12), front=(6, 6), back=(5, 5), wield=(10, 9)))
    # 9-10 はしごをのぼる（手を上へ、足を交互に）
    f.append(figure(pal, s=0, legs=(9, 12), lift=(0, 3), front=(6, -8), back=(4, -3)))
    f.append(figure(pal, s=0, legs=(9, 12), lift=(3, 0), front=(5, -3), back=(5, -8)))
    # 11 睡眠
    f.append(sleeping(pal))
    # 12 荷物を抱える（荷物の絵はゲーム側が頭の上に描く）
    f.append(figure(pal, s=0, lean=-1, front=(6, 3), back=(5, 2)))
    return [q.outline(OUT) for q in f]


def build_sheet(key):
    sheet = Px(S * FRAMES, S)
    for i, fr in enumerate(frames(art_chars.PALETTES[key])):
        sheet.im.alpha_composite(fr.im, (i * S, 0))
    return sheet


def write_all(root=ROOT, keys=None):
    d = os.path.join(root, "characters")
    os.makedirs(d, exist_ok=True)
    for k in (keys or list(art_chars.PALETTES.keys())):
        sh = build_sheet(k)
        sh.save(os.path.join(d, f"crew24_{k}.png"))
        print("wrote characters", f"crew24_{k}.png", sh.w, "x", sh.h)


def preview(path, keys=None, scale=6):
    keys = keys or list(art_chars.PALETTES.keys())
    bg = hexc("d9a95f")
    pad = 2
    W = (S + pad) * FRAMES + pad
    H = (S + pad) * len(keys) + pad
    big = Px(W, H, bg)
    for r, k in enumerate(keys):
        sh = build_sheet(k)
        for i in range(FRAMES):
            fr = Px(S, S)
            fr.im.paste(sh.im.crop((i * S, 0, (i + 1) * S, S)))
            big.im.alpha_composite(fr.im, (pad + i * (S + pad), pad + r * (S + pad)))
    big.save(path, scale)


if __name__ == "__main__":
    if "--preview" in sys.argv:
        out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_preview_chars24.png")
        preview(out)
        print("preview:", out)
    else:
        write_all()
