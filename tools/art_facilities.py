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


CRATE = hexc("8b5a32"); CRATE_L = hexc("c99a5c"); CRATE_D = hexc("5a3a1e")
SACK = hexc("cbb27a"); SACK_D = hexc("a4894f")


def supply_cache():
    """物資庫（幅8・高さ10。修理資材でつくる棚。data/facilities.gd の supply_cache。仲間の疲労度の蓄積を減らす）。
    加工室が狭い（ワークベンチ・加工機と場所を分け合う）ため、幅を詰めた仮のドット絵。修理資材の小箱・瓶を並べただけ。"""
    p = Px(8, 10)
    p.vline(0, 1, 9, WOOD_D); p.vline(7, 1, 9, WOOD_D)       # 支柱
    p.hline(0, 1, 8, WOOD_L)                                  # 上端
    p.hline(0, 5, 8, WOOD); p.hline(0, 5, 8, WOOD_L)          # 中段の棚板
    p.hline(0, 9, 8, C["steel_d"])                            # 床
    # 上段: 修理資材の小箱
    p.rect(1, 2, 5, 2, C["rust_l"]); p.hline(1, 2, 5, C["copper"])
    # 下段: 瓶・工具
    p.rect(1, 6, 2, 3, hexc("cbb27a")); p.set(1, 6, hexc("efe7d2"))
    p.rect(4, 6, 3, 2, C["steel_m"]); p.hline(4, 6, 3, C["steel_l"])
    return p


def cargo_rack(i):
    """荷台の増設（幅12・高さ9。倉庫の重量制の積載量を増やす設備。data/cargo.gd の capacity_bonus）。
    i = 0..2 で積んである木箱・袋の並びが変わる（置き場所ごとに見た目を変えるだけ。仮の絵）。"""
    p = Px(12, 9)
    p.hline(0, 8, 12, C["steel_d"])                        # 床板
    if i == 0:
        p.rect(1, 3, 5, 5, CRATE); p.hline(1, 3, 5, CRATE_L); p.hline(1, 7, 5, CRATE_D)
        p.rect(7, 4, 4, 4, CRATE); p.hline(7, 4, 4, CRATE_L)
    elif i == 1:
        p.rect(2, 5, 5, 3, CRATE); p.hline(2, 5, 5, CRATE_L)
        p.rect(3, 1, 4, 4, CRATE); p.hline(3, 1, 4, CRATE_L); p.hline(3, 4, 4, CRATE_D)
        p.rect(8, 4, 3, 4, CRATE); p.hline(8, 4, 3, CRATE_L)
    else:
        p.rect(1, 4, 4, 4, CRATE); p.hline(1, 4, 4, CRATE_L)
        p.ellipse(8, 6, 3, 2, SACK); p.hline(6, 5, 5, SACK_D)
        p.rect(5, 2, 3, 3, CRATE); p.hline(5, 2, 3, CRATE_L)
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
    for i in range(3):
        l.append(("base", f"cargo_rack_{i}.png", cargo_rack(i)))
    l.append(("base", "supply_cache.png", supply_cache()))
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
