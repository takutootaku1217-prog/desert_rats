"""UIのアイコンゲージ用のドット絵（16x16。オリジナル。PILのみ）。
使い方: python tools/art_ui.py                 … assets/ui/ に書き出す（gen_art.py からも呼ぶ）
        python tools/art_ui.py --preview 出力.png … 充填率ごとの見え方を拡大して並べた確認用の画像を書く（assets/ は変えない）
アイコンゲージ（ui/icon_gauge.gd）は、1つのアイコンを2枚の絵で持つ:
  <name>.png       … 枠（輪郭・縁）。内側は透明。ゲージの上に重ねて描く。
  <name>_mask.png  … 充填してよい範囲。不透明のドットだけ。下の行から順に、割合ぶんだけ埋める（実際のドットの面積が基準）。
絵を差し替えるだけで、盾・しずく・ハートなど別の形のゲージになる。"""
import os
import sys
from pxlib import *

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

OUT = hexc("1c1f25")        # 輪郭
RIM = hexc("9aa3b2")        # 縁（明るい金属）
RING = hexc("6b7482")       # 持ち手の輪
SIZE = 16


def weight_shapes():
    """重り（分銅）。上に小さな持ち手の輪、下が広い台形の胴。底が広く上が細い形。
    戻り値: (frame, mask)。胴の内側（縁を1ドット除いた所）が充填範囲。"""
    body = Px(SIZE, SIZE)
    # 胴: 上の幅10・下の幅14の台形（行5〜14）。底の角を1ドット丸める
    body.poly([(3, 5), (12, 5), (14, 15), (1, 15)], RIM)
    body.set(1, 14, CLEAR)
    body.set(14, 14, CLEAR)
    # 内側 = 胴のドットのうち、上下左右がすべて胴のもの（縁を1ドット残す）
    interior = Px(SIZE, SIZE)
    for y in range(SIZE):
        for x in range(SIZE):
            if body.get(x, y)[3] == 0:
                continue
            if all(body.get(x + dx, y + dy)[3] > 0 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                interior.set(x, y, (255, 255, 255, 255))
    # 持ち手（低くて幅広い。胴の肩と同じ幅にして、錠前（細くて高い輪）ではなく重りに見えるようにする）
    ring = Px(SIZE, SIZE)
    ring.ellipse(7.5, 3.0, 4.6, 2.4, RING)
    ring.ellipse(7.5, 3.7, 2.8, 1.2, CLEAR)
    # 枠 = 輪 ＋ 胴（内側は透明にする）。その外側に1ドットの輪郭
    sil = Px(SIZE, SIZE)
    sil.paste(ring, 0, 0)
    for y in range(SIZE):
        for x in range(SIZE):
            if body.get(x, y)[3] > 0 and interior.get(x, y)[3] == 0:
                sil.set(x, y, RIM)
    # 輪郭は「輪＋胴」全体の外側と、胴の内側（充填範囲）との境目、輪の穴の中にも付ける
    full = Px(SIZE, SIZE)
    full.paste(ring, 0, 0)
    for y in range(SIZE):
        for x in range(SIZE):
            if body.get(x, y)[3] > 0:
                full.set(x, y, RIM)
    edged = full.outline(OUT)
    frame = Px(SIZE, SIZE)
    for y in range(SIZE):
        for x in range(SIZE):
            if interior.get(x, y)[3] > 0:
                continue                      # 充填範囲は透明のまま
            c = edged.get(x, y)
            if c[3] > 0:
                frame.set(x, y, sil.get(x, y) if sil.get(x, y)[3] > 0 else c)
    # 胴の縁のすぐ内側に、充填範囲との境目の暗い線を1ドット入れる（充填した色が縁に馴染みすぎないように）
    for y in range(SIZE):
        for x in range(SIZE):
            if interior.get(x, y)[3] > 0:
                continue
            if body.get(x, y)[3] > 0 and any(interior.get(x + dx, y + dy)[3] > 0 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                frame.set(x, y, hexc("5c6472"))
    return frame, interior


ICONS = {"weight": weight_shapes}


def all_images():
    """(フォルダ, ファイル名, 絵) の一覧"""
    l = []
    for name, fn in ICONS.items():
        frame, mask = fn()
        l.append(("ui", f"{name}.png", frame))
        l.append(("ui", f"{name}_mask.png", mask))
    return l


def write_all(root=ROOT):
    for sub, name, px in all_images():
        d = os.path.join(root, sub)
        os.makedirs(d, exist_ok=True)
        px.save(os.path.join(d, name))
        print("wrote", sub, name, px.w, "x", px.h)


def fill_order(mask):
    """充填する順（ui/icon_gauge.gd と同じ規則）: 下の行から、行の中では中心から左右へ。"""
    rows = {}
    for y in range(mask.h):
        xs = [x for x in range(mask.w) if mask.get(x, y)[3] > 0]
        if xs:
            rows[y] = xs
    order = []
    for y in sorted(rows, reverse=True):
        xs = rows[y]
        cx = (min(xs) + max(xs)) / 2.0
        order += [(x, y) for x in sorted(xs, key=lambda v: (abs(v - cx), v))]
    return order


# 充填の色（ui/ui_kit.gd の GAUGE_STAGES_LOAD と同じ。確認用）
STAGES = [(0.25, "e6dcb4"), (0.50, "e3c072"), (0.75, "d99a3a"), (0.90, "c2691f"), (1.01, "9c3512")]


def render(frame, mask, ratio):
    """確認用: 充填した見た目（背景に暗い空の色）を1枚にする。"""
    order = fill_order(mask)
    n = int(round(ratio * len(order)))
    if ratio > 0 and n == 0:
        n = 1
    col = next(hexc(c) for u, c in STAGES if ratio <= u)
    p = Px(SIZE, SIZE, hexc("2a2f38"))
    for i, (x, y) in enumerate(order):
        p.set(x, y, col if i < n else hexc("12141a"))
    p.paste(frame, 0, 0)
    return p


def preview(path):
    from PIL import Image
    frame, mask = weight_shapes()
    ratios = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
    S = 8
    sheet = Image.new("RGBA", (len(ratios) * (SIZE * S + 12) + 12, SIZE * S + 24), (30, 30, 30, 255))
    for i, r in enumerate(ratios):
        img = render(frame, mask, r).im.resize((SIZE * S, SIZE * S), Image.NEAREST)
        sheet.alpha_composite(img, (12 + i * (SIZE * S + 12), 12))
    sheet.save(path)
    print("preview:", path, " 充填範囲のドット数:", len(fill_order(mask)))


if __name__ == "__main__":
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
    else:
        write_all()
