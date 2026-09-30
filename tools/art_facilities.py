"""建設で増える設備（ワークベンチ・ベッド）の絵と、それを外した車体（hull.png）を生成する（オリジナルのドット絵。PILのみ）。
使い方: python tools/art_facilities.py                 … assets/base/ に書き出す（gen_art.py からも同じ関数を呼ぶ）
        python tools/art_facilities.py --preview 出力.png … 拡大した確認用の画像を書く（assets/ は変えない）
絵の大きさ: ワークベンチ 16x9 が3コマ（0=待機 1・2=作業中。コマの間隔は18）／ベッド 14x9 が1枚ずつ（bed_0..2。毛布の色が違う）。
どれも足元が下端。車体の絵の中の置き場所（上の階の床＝足元の行 40）は data/facilities.gd の spots と合わせる。"""
import os
import sys
from pxlib import *
import art_base
from art_base import C

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

FRAME_W, FRAME_H, STRIDE = 16, 9, 18       # ワークベンチ
WOOD_L = hexc("c99a5c"); WOOD = hexc("8b5a32"); WOOD_D = hexc("5a3a1e")


def workbench(frame=0):
    """ワークベンチ。frame 0 = 待機（ハンマーが置いてある） / 1 = ハンマーを振り上げる / 2 = 打ち下ろす（火花）。"""
    p = Px(FRAME_W, FRAME_H)
    # 天板・前板・脚・下の棚
    p.hline(0, 4, 16, WOOD_L)
    p.hline(0, 5, 16, WOOD)
    p.hline(1, 6, 14, WOOD_D)
    for x in (1, 13):
        p.rect(x, 6, 2, 3, WOOD_D)
        p.vline(x, 6, 3, WOOD)
    p.hline(3, 7, 10, WOOD)
    p.hline(3, 8, 10, C["wall_d"])
    p.rect(4, 6, 3, 2, C["steel_m"])            # 棚の上の部品箱
    p.hline(4, 6, 3, C["steel_l"])
    # 天板の上: 万力（左）と、部品の山（中）
    p.rect(1, 2, 4, 2, C["steel_l"]); p.hline(1, 2, 4, C["steel_h"]); p.set(0, 3, C["steel_m"])
    p.rect(1, 1, 1, 1, C["steel_m"]); p.set(4, 3, C["steel_m"])
    p.rect(6, 3, 3, 1, C["rust_l"]); p.set(7, 2, C["copper"])
    # ハンマー（右）
    if frame == 0:                                   # 置いてある
        p.hline(9, 3, 5, WOOD); p.hline(9, 3, 1, WOOD_D)
        p.rect(12, 2, 2, 2, C["steel_h"]); p.hline(12, 2, 2, C["steel_l"])
    elif frame == 1:                                 # 振り上げる
        p.line(10, 3, 12, 0, WOOD)
        p.rect(12, 0, 3, 2, C["steel_h"]); p.hline(12, 0, 3, C["steel_l"]); p.set(14, 1, C["steel_m"])
    else:                                            # 打ち下ろす
        p.line(11, 1, 9, 3, WOOD)
        p.rect(6, 2, 3, 2, C["steel_h"]); p.hline(6, 2, 3, C["steel_l"])
        p.set(5, 1, C["lamp_g"]); p.set(9, 1, C["lamp"]); p.set(6, 0, C["lamp"])
    return p


def workbench_sheet():
    sh = Px(STRIDE * 3, FRAME_H)
    for f in range(3):
        sh.paste(workbench(f), f * STRIDE, 0)
    return sh


def bed(i):
    """ベッド（幅14・高さ9）。i = 0..2 で毛布の色が変わる（hull.png に描いていた3つと同じ絵）。"""
    p = Px(14, 9)
    art_base.draw_bed(p, 0, 9, art_base.BED_BLANKETS[i])
    return p


def wood_cargo():
    """木製荷台（幅8・高さ10）。丸太を積んだ荷台。実装指示書: 拠点の最大重量を増やす設備（仮のドット絵）。"""
    p = Px(8, 10)
    p.hline(0, 8, 8, WOOD_D)                      # 台の脚
    p.rect(0, 6, 8, 2, WOOD)                      # 台の板
    p.hline(0, 6, 8, WOOD_L)
    for i, y in enumerate((2, 4)):                # 丸太を2段
        ox = 0 if i == 0 else 1
        for x in range(ox, 8, 3):
            p.ellipse(x + 1, y, 1, 1, WOOD_L)
            p.set(x, y, WOOD)
            p.set(x + 2, y, WOOD_D)
    p.vline(1, 1, 7, C["rust_l"])                  # 縛った縄
    p.vline(6, 1, 7, C["rust_l"])
    return p


def tool_rack(frame=None):
    """道具棚（幅8・高さ10）。壁掛けの板に、道具が2つ掛かる。実装指示書: 採取道具を個体へ割り当てる入口（仮のドット絵）。"""
    p = Px(8, 10)
    p.rect(0, 1, 8, 2, WOOD)                       # 壁掛けの板
    p.hline(0, 1, 8, WOOD_L)
    p.hline(0, 2, 8, WOOD_D)
    p.set(1, 0, C["steel_h"]); p.set(6, 0, C["steel_h"])   # 掛けるフック
    # ハンマー（左）
    p.vline(2, 3, 4, WOOD)
    p.rect(1, 3, 3, 2, C["steel_l"]); p.hline(1, 3, 3, C["steel_h"])
    # ピッケル（右）
    p.vline(5, 3, 5, WOOD)
    p.line(4, 4, 7, 4, C["steel_l"])
    p.set(4, 3, C["steel_h"]); p.set(7, 5, C["steel_h"])
    return p


def hull():
    # 屋根の上の物は焼き込まない（外装パーツ art_exterior.py が、外装でも内装の断面図の上でも同じ絵を重ねる）
    return art_base.build_hull(furnish=False, roof=False)


def room_images():
    """部屋の変更（data/rooms.gd）で区画に重ねる絵。hull.png と同じく、ワークベンチ・ベッドは描かない（建設で増える）。
    絵の中身は、部屋の重ね絵を作る art_base.room_overlays() のまま（家具を描かない指定だけ）。"""
    return [(f"base/rooms/{art_base.STYLE}", f"room_{slot}_{rtype}.png", px) for slot, rtype, px in art_base.room_overlays(furnish=False)]


def all_images():
    """(フォルダ, ファイル名, 絵) の一覧"""
    l = [("base", "hull.png", hull()), ("base", "workbench.png", workbench_sheet())]
    for i in range(3):
        l.append(("base", f"bed_{i}.png", bed(i)))
    l.append(("base", "wood_cargo.png", wood_cargo()))
    l.append(("base", "tool_rack.png", tool_rack()))
    return l + room_images()


def write_all(root=ROOT):
    for sub, name, px in all_images():
        d = os.path.join(root, sub)
        os.makedirs(d, exist_ok=True)
        px.save(os.path.join(d, name))
        print("wrote", sub, name, px.w, "x", px.h)


def preview(path):
    """確認用: 車体（家具なし）に、ワークベンチ・ベッドを置いた絵と、3コマを大きく並べる。"""
    from PIL import Image
    h = hull()
    full = Px(h.w, h.h)
    full.paste(h, 0, 0)
    feet = art_base.UP_FEET
    x0u1 = art_base.SLOTS["u1"]["x0"]
    x0u2 = art_base.SLOTS["u2"]["x0"]
    full.paste(workbench(0), x0u1 + 1, feet - FRAME_H + 1)
    for i in range(3):
        full.paste(bed(i), x0u2 + 2 + 15 * i, feet - 9)
    S = 6
    big = full.im.crop((0, 8, h.w, 80)).resize((h.w * S, 72 * S), Image.NEAREST)
    frames = Image.new("RGBA", (STRIDE * 3 * 10 + 40, 9 * 10 + 20), (40, 34, 30, 255))
    sh = workbench_sheet().im.resize((STRIDE * 3 * 10, 90), Image.NEAREST)
    frames.alpha_composite(sh, (20, 10))
    out = Image.new("RGBA", (max(big.width, frames.width), big.height + frames.height), (30, 30, 30, 255))
    out.alpha_composite(big, (0, 0))
    out.alpha_composite(frames, (0, big.height))
    out.save(path)
    print("preview:", path)


if __name__ == "__main__":
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
    else:
        write_all()
