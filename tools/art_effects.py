"""効果（エフェクト）のコマ絵（オリジナル。PILのみ）。今は仮素材で、完成した画像素材へ差し替える前提。
使い方: python tools/art_effects.py                 … assets/effects/ に書き出す（gen_art.py からも呼ぶ）
        python tools/art_effects.py --preview 出力.png … 各効果のコマを拡大して並べた確認用の画像を書く（assets/ は変えない）
効果は「コマが横に並んだ1枚の絵」＋ data/effects.gd（EffectDB）の表（基準の大きさ・コマ数・速さ・ループ）で決まる。
scripts/fx_sprite.gd（FxSprite）が、その絵を再生するだけで、図形はコードで描かない。
絵を高精細にするときは、同じ基準の大きさ（ユニット）で幅が整数倍の画像に差し替えるだけでよい（ゲーム側は変えない）。"""
import os
import sys
from pxlib import *

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

STEAM = (226, 230, 238)
DUST = (214, 190, 150)
SPARK = (255, 236, 140)
SPARK_HOT = (255, 255, 235)


def _rgba(c, a):
    return (c[0], c[1], c[2], max(0, min(255, int(a))))


def sheet(cell_w, cell_h, frames):
    return Px(cell_w * frames, cell_h)


def disc(w, h, cx, cy, r, color, a):
    """丸い粒（中心が濃く、縁が薄い）。半透明のドットを重ねるため、1枚ずつ別の絵に描いて、あとで重ねる。"""
    f = Px(w, h)
    for y in range(h):
        for x in range(w):
            d = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
            if d <= r:
                edge = 1.0 if d <= r - 0.9 else 0.55
                f.set(x, y, _rgba(color, a * edge))
    return f


def steam():
    """加工設備の煙突から出る湯気。8x8ユニット×6コマ。下から上へ立ちのぼり、広がって薄くなる。ループ。"""
    W, H, N = 8, 8, 6
    s = sheet(W, H, N)
    blobs = [(4.0, 0.0), (5.2, 0.4), (3.0, 0.75)]
    for k in range(N):
        t = k / float(N)
        f = Px(W, H)
        for cx, ph in blobs:
            u = (t + ph) % 1.0
            cy = 6.6 - 5.4 * u
            r = 1.3 + 1.6 * u
            a = 235.0 * (1.0 - u) ** 1.3
            f.paste(disc(W, H, cx + 0.8 * u * (1 if cx > 3.5 else -1), cy, r, STEAM, a), 0, 0)
        s.paste(f, k * W, 0)
    return s


def drop():
    """材料が加工設備の投入口へ落ちたときの、小さな砂ぼこり。10x6ユニット×5コマ。1回だけ。"""
    W, H, N = 10, 6, 5
    s = sheet(W, H, N)
    for k in range(N):
        f = Px(W, H)
        a = 240.0 * (1.0 - k / float(N)) ** 1.1
        r = 1.5 + 0.7 * k
        f.paste(disc(W, H, 5.0, 4.4 - 0.25 * k, r, DUST, a * 0.9), 0, 0)
        for sgn in (-1, 1):
            f.set(int(4.5 + sgn * (1.5 + 1.2 * k)), 4, _rgba(DUST, a))
            f.set(int(4.5 + sgn * (2.5 + 1.2 * k)), 5, _rgba(DUST, a * 0.7))
        s.paste(f, k * W, 0)
    return s

def done():
    """加工が終わったときの、きらり。8x8ユニット×6コマ。1回だけ。"""
    W, H, N = 8, 8, 6
    s = sheet(W, H, N)
    arms = [1, 2, 3, 3, 2, 1]
    for k in range(N):
        f = Px(W, H)
        a = 255.0 * (1.0 - 0.55 * k / float(N - 1))
        col = _rgba(SPARK, a)
        L = arms[k]
        for d in range(1, L + 1):
            f.set(4 - d, 4, col)
            f.set(3 + d, 4, col)
            f.set(4, 4 - d, col)
            f.set(4, 3 + d, col)
        for d in range(1, max(0, L - 1) + 1):
            f.set(4 - d, 4 - d, _rgba(SPARK, a * 0.75))
            f.set(3 + d, 4 - d, _rgba(SPARK, a * 0.75))
            f.set(4 - d, 3 + d, _rgba(SPARK, a * 0.75))
            f.set(3 + d, 3 + d, _rgba(SPARK, a * 0.75))
        f.rect(3, 3, 2, 2, _rgba(SPARK_HOT, a))
        s.paste(f, k * W, 0)
    return s


EFFECTS = {"proc_steam": steam, "proc_drop": drop, "proc_done": done}


def all_images():
    return [("effects", f"{name}.png", fn()) for name, fn in EFFECTS.items()]


def write_all(root=ROOT):
    for sub, name, px in all_images():
        d = os.path.join(root, sub)
        os.makedirs(d, exist_ok=True)
        px.save(os.path.join(d, name))
        print("wrote", sub, name, px.w, "x", px.h)


def preview(path):
    from PIL import Image
    imgs = all_images()
    S = 8
    w = max(px.w for _, _, px in imgs) * S + 24
    h = sum(px.h * S + 12 for _, _, px in imgs) + 12
    sheet_img = Image.new("RGBA", (w, h), (70, 60, 52, 255))
    y = 12
    for _, name, px in imgs:
        sheet_img.alpha_composite(px.im.resize((px.w * S, px.h * S), Image.NEAREST), (12, y))
        y += px.h * S + 12
    sheet_img.save(path)
    print("preview:", path)


if __name__ == "__main__":
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
    else:
        write_all()
