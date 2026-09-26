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


# ---------------------------------------------------------------- 仲間のステータス（HP・スタミナ・満腹度・疲労度）のアイコン
# どれも「シルエット」から作る: 内側（縁を1ドット除いた所）が充填範囲、縁と外側の輪郭が枠。形は仮（差し替えできる）。
STATUS_RIM = {"hp": hexc("d8848c"), "stamina": hexc("e8d27a"), "hunger": hexc("d9a066"), "fatigue": hexc("a9b7d0")}
BONE = hexc("ece3cf")       # 骨（充填しない部分）
BONE_SH = hexc("b8ad94")


def silhouette_icon(sil, rim, extra=None):
    """シルエット sil（不透明 = 体）から (frame, mask) を作る。内側 = 体のうち、上下左右がすべて体のドット（充填範囲）。
    枠 = 体の縁（rim）＋ その外側の輪郭。extra は枠の上に足す絵（骨など。充填範囲の外に置く）。"""
    interior = Px(SIZE, SIZE)
    for y in range(SIZE):
        for x in range(SIZE):
            if sil.get(x, y)[3] == 0:
                continue
            if all(sil.get(x + dx, y + dy)[3] > 0 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                interior.set(x, y, (255, 255, 255, 255))
    ring = Px(SIZE, SIZE)
    for y in range(SIZE):
        for x in range(SIZE):
            if sil.get(x, y)[3] > 0 and interior.get(x, y)[3] == 0:
                ring.set(x, y, rim)
    whole = Px(SIZE, SIZE)
    whole.paste(sil, 0, 0)
    if extra is not None:
        whole.paste(extra, 0, 0)
    edged = whole.outline(OUT)
    frame = Px(SIZE, SIZE)
    for y in range(SIZE):
        for x in range(SIZE):
            if interior.get(x, y)[3] > 0:
                continue                                  # 充填範囲は透明のまま
            c = edged.get(x, y)
            if c[3] > 0:
                frame.set(x, y, c)
    frame.paste(ring, 0, 0)
    if extra is not None:
        for y in range(SIZE):
            for x in range(SIZE):
                if extra.get(x, y)[3] > 0 and interior.get(x, y)[3] == 0:
                    frame.set(x, y, extra.get(x, y))
    return frame, interior


def hp_shapes():
    """HP: ハート。"""
    s = Px(SIZE, SIZE)
    s.ellipse(4.6, 5.4, 3.7, 3.5, RIM)
    s.ellipse(10.4, 5.4, 3.7, 3.5, RIM)
    s.poly([(1, 6), (14, 6), (8, 14), (7, 14)], RIM)
    return silhouette_icon(s, STATUS_RIM["hp"])


def stamina_shapes():
    """スタミナ: 稲妻（ずんぐりした形。細いと充填範囲が取れない）。"""
    s = Px(SIZE, SIZE)
    s.poly([(11, 0), (1, 9), (6, 9), (4, 15), (14, 6), (9, 6), (13, 0)], RIM)
    return silhouette_icon(s, STATUS_RIM["stamina"])


def hunger_shapes():
    """満腹度: 骨つき肉。肉の部分だけが充填範囲、骨は枠の側に描く。"""
    s = Px(SIZE, SIZE)
    s.ellipse(6.2, 6.2, 5.6, 5.0, RIM)
    bone = Px(SIZE, SIZE)
    bone.line(9, 9, 13, 13, BONE)
    bone.line(10, 9, 14, 13, BONE)
    bone.ellipse(13.0, 11.6, 1.5, 1.4, BONE)
    bone.ellipse(11.6, 13.2, 1.5, 1.4, BONE)
    bone.set(14, 12, BONE_SH)
    bone.set(12, 14, BONE_SH)
    return silhouette_icon(s, STATUS_RIM["hunger"], bone)


def fatigue_shapes():
    """疲労度: 雲（眠そうな、どんよりした雲）。右上に小さな「z」（充填しない部分）。"""
    s = Px(SIZE, SIZE)
    s.ellipse(4.2, 10.4, 3.2, 3.0, RIM)
    s.ellipse(7.8, 8.0, 3.8, 3.6, RIM)
    s.ellipse(11.4, 10.4, 3.4, 3.0, RIM)
    s.rect(4, 10, 8, 4, RIM)
    z = Px(SIZE, SIZE)
    zc = hexc("cfe6ff")
    z.hline(11, 0, 4, zc)
    z.set(13, 1, zc)
    z.set(12, 2, zc)
    z.hline(11, 3, 4, zc)
    return silhouette_icon(s, STATUS_RIM["fatigue"], z)


# ---------------------------------------------------------------- 精神状態の顔（5段階。色は色分け用に、白っぽく描いて画面側で染める）
FACE = hexc("f4f4f4")
FACE_SH = hexc("c9c9c9")
INK = hexc("1c1f25")


def face(kind):
    """kind: good / normal / anxious / bad / limit。16x16。顔そのものが枠（充填はしない）。"""
    p = Px(SIZE, SIZE)
    p.ellipse(7.5, 7.5, 6.4, 6.4, FACE)
    p.ellipse(7.5, 9.0, 5.6, 5.0, FACE_SH)
    p.ellipse(7.5, 7.0, 5.6, 5.4, FACE)
    if kind == "good":                      # にっこり（目は弧、口は大きい笑い）
        p.hline(4, 6, 2, INK); p.set(4, 7, INK); p.set(5, 5, INK)
        p.hline(9, 6, 2, INK); p.set(11, 7, INK); p.set(10, 5, INK)
        p.hline(5, 10, 6, INK); p.set(4, 9, INK); p.set(11, 9, INK)
    elif kind == "normal":                  # 無表情（点の目・一文字の口）
        p.rect(5, 6, 2, 2, INK); p.rect(9, 6, 2, 2, INK)
        p.hline(5, 10, 6, INK)
    elif kind == "anxious":                 # 不安（縦長の目・小さな波の口）
        p.rect(5, 5, 2, 3, INK); p.rect(9, 5, 2, 3, INK)
        p.set(5, 11, INK); p.set(6, 10, INK); p.set(7, 11, INK); p.set(8, 10, INK); p.set(9, 11, INK); p.set(10, 10, INK)
    elif kind == "bad":                     # 不調（目が細く、口がへの字。汗のしずく）
        p.hline(4, 7, 3, INK); p.hline(9, 7, 3, INK)
        p.hline(5, 11, 6, INK); p.set(4, 12, INK); p.set(11, 12, INK)
    else:                                   # 限界（目がぐるぐる・口が開く）
        p.rect(4, 5, 3, 3, INK); p.rect(9, 5, 3, 3, INK)
        p.set(5, 6, FACE); p.set(10, 6, FACE)
        p.rect(6, 10, 4, 3, INK)
    return p.outline(OUT)


ICONS = {"weight": weight_shapes, "hp": hp_shapes, "stamina": stamina_shapes, "hunger": hunger_shapes, "fatigue": fatigue_shapes}
FACES = ["good", "normal", "anxious", "bad", "limit"]

def all_images():
    """(フォルダ, ファイル名, 絵) の一覧"""
    l = []
    for name, fn in ICONS.items():
        frame, mask = fn()
        l.append(("ui", f"{name}.png", frame))
        l.append(("ui", f"{name}_mask.png", mask))
    for k in FACES:
        l.append(("ui", f"mental_{k}.png", face(k)))
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
