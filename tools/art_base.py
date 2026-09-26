import math, random
from pxlib import *

C = dict(
    steel_d=hexc("1c1f25"), steel=hexc("2c3038"), steel_m=hexc("434955"), steel_l=hexc("636b7a"), steel_h=hexc("8f98a9"),
    rust=hexc("7f4626"), rust_l=hexc("b5652e"), wall=hexc("5b4736"), wall_d=hexc("43352a"), wall_l=hexc("715a42"),
    lamp=hexc("f6d36a"), lamp_g=hexc("fff0a8"), copper=hexc("c8783c"), copper_d=hexc("8a4a24"), green=hexc("3f8f76"),
    yellow=hexc("e8b530"), black=hexc("15171b"), red=hexc("d8452e"), blue=hexc("4aa8d8"), sand=hexc("e2ae62"),
)

IW, IH = 184, 80
R0 = 10           # 車体の上端行
UP_TOP, UP_FEET = 16, 40      # 上の階: 部屋の上端 / 床(足元)
LO_TOP, LO_FEET = 43, 72      # 下の階

# 部屋を入れ替えられる区画（スロット）。x0..x1 は部屋の内側の列、top..feet は上端行と床(足元)の行。
# scripts / data/rooms.gd の SLOTS と同じ値にすること（tools/selftest.gd が食い違いを検出する）。
SLOTS = {
    "u1": dict(x0=8,  x1=71,  top=UP_TOP, feet=UP_FEET),
    "u2": dict(x0=82, x1=137, top=UP_TOP, feet=UP_FEET),
    "l1": dict(x0=8,  x1=71,  top=LO_TOP, feet=LO_FEET),
    "l2": dict(x0=82, x1=149, top=LO_TOP, feet=LO_FEET),
}
SLOT_ORDER = ("u1", "u2", "l1", "l2")
DEFAULT_LAYOUT = {"u1": "workshop", "u2": "bedroom", "l1": "engine", "l2": "storage"}
# 部屋の種類ごとに置ける階（u = 上の階 / l = 下の階）。data/rooms.gd の "floors" と同じにすること。
ROOM_FLOORS = {
    "workshop": "ul", "bedroom": "ul", "engine": "l", "storage": "l",
    "infirmary": "ul", "mess": "ul", "training": "ul", "empty": "ul",
}
# 見た目の系統。将来サイバーパンクなどを足すときは、系統ごとに配色を変えて出力する。
STYLE = "desert"


def rivets(p, x0, x1, y, step=6, col=None):
    for x in range(x0, x1, step):
        p.set(x, y, col or C["steel_h"])


def hull_shell(p):
    # 車体の外殻
    p.rect(2, R0, 180, IH - R0, C["steel"])
    p.hline(2, R0, 180, C["steel_h"])
    p.hline(2, R0 + 1, 180, C["steel_l"])
    p.vline(2, R0, IH - R0, C["steel_l"])
    p.vline(181, R0, IH - R0, C["steel_d"])
    # 角を丸める
    for (x, y) in ((2, R0), (3, R0), (2, R0 + 1)):
        p.set(x, y, CLEAR)
    for (x, y) in ((181, R0), (180, R0), (181, R0 + 1)):
        p.set(x, y, CLEAR)
    # 天井パネルと通気口
    p.rect(2, R0 + 2, 180, 4, C["steel_m"])
    for x in range(12, 170, 22):
        p.rect(x, R0 + 3, 8, 2, C["steel_d"])
        p.hline(x, R0 + 5, 8, C["steel_l"])
    rivets(p, 6, 178, R0 + 2)
    # 下部装甲
    p.rect(2, LO_FEET, 180, IH - LO_FEET, C["steel_m"])
    p.hline(2, LO_FEET, 180, C["steel_l"])
    p.hline(2, IH - 1, 180, C["steel_d"])
    p.hline(2, IH - 2, 180, C["steel"])
    rivets(p, 6, 178, LO_FEET + 2)
    # ハザード帯（黄黒）
    for x in range(10, 172):
        if (x // 4) % 2 == 0:
            p.hline(x, LO_FEET + 5, 1, C["yellow"])
            p.hline(x, LO_FEET + 6, 1, C["yellow"])
        else:
            p.hline(x, LO_FEET + 5, 1, C["black"])
            p.hline(x, LO_FEET + 6, 1, C["black"])
    # 錆
    rnd = random.Random(5)
    for i in range(60):
        x = rnd.randint(3, 180); y = rnd.choice([rnd.randint(R0 + 6, 20), rnd.randint(LO_FEET + 1, LO_FEET + 4)])
        p.set(x, y, C["rust"])
        if rnd.random() < 0.5:
            p.set(x + 1, y, C["rust_l"])


def room_bg(p, x0, x1, y0, y1, wall=None, lit=None, dark=None, light=None):
    wall = wall or C["wall"]
    dark = dark or C["wall_d"]
    light = light or C["wall_l"]
    p.rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1, wall)
    # 縦の板目
    for x in range(x0 + 3, x1, 6):
        p.vline(x, y0, y1 - y0 + 1, dark)
    # 腰壁
    p.rect(x0, y1 - 5, x1 - x0 + 1, 6, dark)
    p.hline(x0, y1 - 5, x1 - x0 + 1, light)
    # 天井
    p.rect(x0, y0, x1 - x0 + 1, 2, C["steel_m"])
    p.hline(x0, y0 + 2, x1 - x0 + 1, C["steel_d"])


def lamp(p, x, y):
    p.vline(x, y - 4, 4, C["steel_l"]) if y > 4 else None
    p.rect(x - 2, y, 5, 2, C["steel_h"])
    p.rect(x - 1, y + 2, 3, 1, C["lamp"])
    p.set(x, y + 2, C["lamp_g"])


def floors(p):
    for (top, x0, x1) in ((UP_FEET, 8, 175), (LO_FEET, 8, 175)):
        p.rect(x0, top, x1 - x0 + 1, 3, C["steel_m"])
        p.hline(x0, top, x1 - x0 + 1, C["steel_h"])
        p.hline(x0, top + 2, x1 - x0 + 1, C["steel_d"])
        rivets(p, x0 + 3, x1, top + 1, 8, C["steel_l"])
    # 上の階の床にハシゴの開口部
    p.rect(75, UP_FEET, 5, 3, C["wall_d"])


def ladder(p):
    # ハシゴのシャフト（2階分）
    p.rect(74, UP_TOP, 7, LO_FEET - UP_TOP, C["wall_d"])
    p.vline(75, UP_TOP, LO_FEET - UP_TOP, C["steel_l"])
    p.vline(79, UP_TOP, LO_FEET - UP_TOP, C["steel_l"])
    for y in range(UP_TOP + 2, LO_FEET - 1, 3):
        p.hline(76, y, 3, C["copper"])
    # 上階の床の穴を通る
    p.rect(75, UP_FEET, 5, 3, C["wall_d"])
    for y in range(UP_FEET, UP_FEET + 3):
        p.hline(76, y, 3, C["copper"]) if (y % 3 == 0) else None
    p.vline(75, UP_FEET, 3, C["steel_l"]); p.vline(79, UP_FEET, 3, C["steel_l"])


def partition(p, x, top, feet, door_h=19):
    p.rect(x, top, 2, feet - top, C["steel_m"])
    p.vline(x, top, feet - top, C["steel_l"])
    # 出入口（アーチ）
    p.rect(x, feet - door_h, 2, door_h, C["wall_d"])
    p.rect(x - 1, feet - door_h - 1, 4, 1, C["steel_h"])


def pipes(p, x0, x1, y, col=None):
    col = col or C["copper"]
    p.hline(x0, y, x1 - x0, col)
    p.hline(x0, y + 1, x1 - x0, C["copper_d"])
    for x in range(x0 + 4, x1, 12):
        p.vline(x, y - 1, 4, C["steel_h"])


def gauge(p, x, y):
    p.ellipse(x, y, 3, 3, C["steel_h"])
    p.ellipse(x, y, 2, 2, hexc("efe7d2"))
    p.line(x, y, x + 1, y - 1, C["red"])


def crate(p, x, y, w=7, h=6, col=None):
    col = col or hexc("8b5a32")
    p.rect(x, y, w, h, col)
    p.rect(x, y, w, 1, hexc("b8834a"))
    p.rect(x, y + h - 1, w, 1, hexc("5c3d22"))
    p.line(x, y, x + w - 1, y + h - 1, hexc("6e4726"))
    p.vline(x, y, h, hexc("6e4726")); p.vline(x + w - 1, y, h, hexc("6e4726"))


def barrel(p, x, y, col=None):
    col = col or C["rust_l"]
    p.rect(x, y, 6, 8, col)
    p.hline(x, y + 2, 6, C["steel_l"]); p.hline(x, y + 5, 6, C["steel_l"])
    p.vline(x, y, 8, C["rust"]); p.hline(x, y, 6, C["copper"])


# ---------------- 建設で増える家具（ベッド・ワークベンチ）----------------
# 車体の絵（hull.png）には、建設で増える家具は描かない（furnish=False）。家具は art_facilities.py が別の絵にして、
# ゲームが「建てた分だけ」重ねて描く。build_hull() を引数なしで呼ぶと、従来どおり家具つきの絵になる。
FURNISH = True
BED_BLANKETS = (C["red"], hexc("2fa3a0"), C["yellow"])       # 毛布の色は仲間のスカーフの色


def draw_bed(p, bx, feet, blanket):
    """ベッド1つ（幅14・高さ9）。bx は左端の列、feet は床の行。"""
    p.rect(bx, feet - 6, 14, 2, C["steel_m"])            # フレーム
    p.vline(bx, feet - 8, 8, C["steel_l"]); p.vline(bx + 13, feet - 7, 7, C["steel_l"])
    p.rect(bx + 1, feet - 8, 12, 2, hexc("efe7d2"))      # マットレス
    p.rect(bx + 5, feet - 8, 8, 2, blanket)              # 毛布
    p.rect(bx + 1, feet - 9, 4, 1, hexc("fff6e0"))       # 枕
    p.hline(bx, feet - 4, 14, C["steel_d"])


# ---------------- 各部屋 ----------------
# 入れ替え可能な部屋は room_xxx(p, s) の形。s は SLOTS の1区画（x0, x1, top, feet）。
# 左側の物は x0 からの相対、右側の物は x1 からの相対、床の物は feet からの相対、壁の物は top からの相対で置く。
# こうすると、どの区画（幅56〜68・上下どちらの階）でもはみ出さずに置ける。
def room_workshop(p, s):
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1)
    lamp(p, x0 + 14, top + 2); lamp(p, x0 + 48, top + 2)
    pipes(p, x0, x1, top + 5)
    # 壁の工具かけ
    p.rect(x0 + 2, top + 10, 16, 1, C["steel_l"])
    for i, tx in enumerate((x0 + 4, x0 + 8, x0 + 12, x0 + 16)):
        p.vline(tx, top + 11, 4 + (i % 2) * 2, C["steel_h"]); p.set(tx, top + 11, C["copper"])
    # 歯車の壁飾り
    gx, gy = x1 - 9, top + 10
    p.ellipse(gx, gy, 5, 5, C["steel_m"]); p.ellipse(gx, gy, 2, 2, C["wall_d"])
    for a in range(8):
        p.set(int(gx + 6 * math.cos(a * math.pi / 4)), int(gy + 6 * math.sin(a * math.pi / 4)), C["steel_m"])
    gauge(p, x0 + 24, top + 8)
    # 作業台（建設するワークベンチは別の絵 art_facilities.py。furnish=False の車体には描かない）
    if FURNISH:
        p.rect(x0 + 1, feet - 7, 14, 2, hexc("8b5a32")); p.vline(x0 + 2, feet - 5, 5, C["wall_d"]); p.vline(x0 + 13, feet - 5, 5, C["wall_d"])
        p.rect(x0 + 4, feet - 10, 3, 3, C["steel_l"]); p.rect(x0 + 9, feet - 9, 4, 2, C["red"])
    # 加工機のための影（機械本体は別スプライト。中心は x0+33）
    p.rect(x0 + 22, feet - 2, 24, 2, C["wall_d"])


def room_bedroom(p, s):
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1, wall=hexc("5a4a45"))
    lamp(p, x0 + 14, top + 2); lamp(p, x0 + 42, top + 2)
    # 丸窓
    wx, wy = x0 + 28, top + 8
    p.ellipse(wx, wy, 5, 5, C["steel_h"]); p.ellipse(wx, wy, 4, 4, hexc("f0b878"))
    p.hline(wx - 4, wy + 1, 9, hexc("fbe0a8")); p.vline(wx, wy - 4, 9, C["steel_m"]); p.hline(wx - 4, wy, 9, C["steel_m"])
    # ベッド3つ（毛布の色は仲間のスカーフの色）。ベッドの間隔は15、先頭は x0+2
    # furnish=False の車体には描かない（ベッドは建設で増える。art_facilities.py が同じ絵を1つずつ出力する）
    if FURNISH:
        for i in range(3):
            draw_bed(p, x0 + 2 + 15 * i, feet, BED_BLANKETS[i])
    # 服・洗濯ロープ
    p.line(x0 + 2, top + 4, x0 + 26, top + 5, hexc("b8a890"))
    p.rect(x0 + 8, top + 5, 3, 4, C["red"]); p.rect(x0 + 14, top + 5, 3, 3, hexc("efe7d2"))
    p.rect(x0 + 46, feet - 14, 6, 8, hexc("6a5a50")); p.hline(x0 + 46, feet - 11, 6, C["steel_m"]); p.set(x0 + 49, feet - 13, C["yellow"])


def room_engine(p, s):
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1, wall=hexc("4a3d38"))
    lamp(p, x0 + 22, top + 2); lamp(p, x0 + 50, top + 2)
    pipes(p, x0, x1, top + 5, C["green"])
    by = feet - 18
    # ボイラータンク
    p.rect(x0 + 4, by, 22, 14, C["steel_m"]); p.hline(x0 + 4, by, 22, C["steel_h"]); p.hline(x0 + 4, feet - 5, 22, C["steel_d"])
    p.ellipse(x0 + 4, feet - 11, 3, 7, C["steel_l"]); p.ellipse(x0 + 25, feet - 11, 3, 7, C["steel_m"])
    for x in range(x0 + 8, x0 + 24, 5):
        p.vline(x, by + 1, 12, C["steel_l"])
    gauge(p, x0 + 15, top + 5)
    # 炉の火
    p.rect(x0 + 30, feet - 13, 9, 9, C["steel_d"]); p.rect(x0 + 32, feet - 11, 5, 5, hexc("f08a30")); p.rect(x0 + 33, feet - 9, 3, 3, hexc("ffd060"))
    p.vline(x0 + 34, top + 7, 9, C["steel_l"]); p.rect(x0 + 32, top + 6, 5, 2, C["steel_h"])
    # 大きな歯車（右側は x1 基準）
    for gx, gy, r in ((x1 - 15, feet - 8, 6), (x1 - 5, feet - 14, 4)):
        p.ellipse(gx, gy, r, r, C["steel_l"]); p.ellipse(gx, gy, r - 2, r - 2, C["steel_m"]); p.set(gx, gy, C["steel_d"])
        for a in range(8):
            p.set(int(gx + (r + 1) * math.cos(a * math.pi / 4)), int(gy + (r + 1) * math.sin(a * math.pi / 4)), C["steel_l"])
    barrel(p, x1 - 21, feet - 8, C["rust_l"])


def room_storage(p, s):
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1, wall=hexc("574332"))
    lamp(p, x0 + 18, top + 2); lamp(p, x0 + 50, top + 2)
    # 棚（上段=素材を置く）。下段は床に加工品の山を置く。棚の中心は x0+34
    p.rect(x0 + 4, feet - 14, 60, 2, hexc("7a5230")); p.hline(x0 + 4, feet - 14, 60, hexc("a87a48")); p.hline(x0 + 4, feet - 13, 60, hexc("5c3d22"))
    for bx in (x0 + 4, x0 + 63):
        p.vline(bx, top + 2, 27, hexc("5c3d22")); p.vline(bx + 1, top + 2, 27, hexc("7a5230"))


def room_infirmary(p, s):
    """医務室: 白い十字の看板、ベッド2つ、点滴、薬棚。休憩の回復が早くなる部屋。"""
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1, wall=hexc("4f6663"), dark=hexc("3a4d4b"), light=hexc("6f8d89"))
    lamp(p, x0 + 14, top + 2); lamp(p, x0 + 44, top + 2)
    cx, cy = x0 + 28, top + 8
    p.rect(cx - 4, cy - 4, 9, 9, hexc("efe7d2"))
    p.rect(cx - 1, cy - 3, 3, 7, C["red"]); p.rect(cx - 3, cy - 1, 7, 3, C["red"])
    for bx in (x0 + 2, x0 + 36):
        p.rect(bx, feet - 6, 16, 2, C["steel_m"])
        p.vline(bx, feet - 8, 8, C["steel_l"]); p.vline(bx + 15, feet - 8, 8, C["steel_l"])
        p.rect(bx + 1, feet - 8, 14, 2, hexc("efe7d2"))
        p.rect(bx + 1, feet - 9, 4, 1, hexc("fff6e0"))
        p.rect(bx + 8, feet - 8, 7, 2, hexc("9fd6c8"))
        p.hline(bx, feet - 4, 16, C["steel_d"])
    # 点滴スタンド
    p.vline(x0 + 21, feet - 17, 11, C["steel_h"]); p.rect(x0 + 19, feet - 17, 5, 1, C["steel_h"])
    p.rect(x0 + 20, feet - 16, 3, 4, hexc("bfe8ff")); p.set(x0 + 21, feet - 12, C["red"])
    # 薬棚（腰壁の高さ。看板と重ならない）
    p.rect(x0 + 26, feet - 11, 8, 6, C["steel_m"]); p.hline(x0 + 26, feet - 11, 8, C["steel_h"])
    p.vline(x0 + 30, feet - 10, 5, C["steel_d"])
    p.set(x0 + 28, feet - 9, C["red"]); p.set(x0 + 32, feet - 9, C["green"]); p.set(x0 + 28, feet - 7, C["yellow"]); p.set(x0 + 32, feet - 7, C["blue"])


def room_mess(p, s):
    """食堂: 吊るした鍋、コンロ、長テーブル。仲間が疲れにくくなる部屋。"""
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1, wall=hexc("6b5638"), dark=hexc("4d3b26"), light=hexc("8a7048"))
    lamp(p, x0 + 14, top + 2); lamp(p, x0 + 44, top + 2)
    # 吊り鍋
    for x in (x0 + 6, x0 + 13, x0 + 20):
        p.vline(x, top + 3, 5, C["steel_l"])
        p.ellipse(x, top + 10, 3, 2, C["copper"]); p.hline(x - 2, top + 9, 5, C["copper_d"])
    # 棚と缶詰
    p.rect(x0 + 32, top + 8, 18, 1, C["steel_l"])
    for i, col in enumerate((C["red"], C["yellow"], C["blue"], C["green"])):
        p.rect(x0 + 34 + i * 4, top + 5, 3, 3, col)
    # コンロと鍋、湯気
    p.rect(x0 + 38, feet - 10, 14, 10, C["steel_m"]); p.hline(x0 + 38, feet - 10, 14, C["steel_h"])
    p.rect(x0 + 41, feet - 14, 8, 4, C["copper"]); p.hline(x0 + 41, feet - 14, 8, C["copper_d"])
    p.rect(x0 + 41, feet - 6, 8, 3, hexc("f08a30")); p.rect(x0 + 43, feet - 5, 4, 2, hexc("ffd060"))
    for (dx, dy) in ((0, 17), (1, 19), (-1, 21)):
        p.set(x0 + 45 + dx, feet - dy, hexc("e6e0d0"))
    # 長テーブルとベンチ
    p.rect(x0 + 3, feet - 9, 28, 2, hexc("8b5a32")); p.vline(x0 + 5, feet - 7, 7, C["wall_d"]); p.vline(x0 + 28, feet - 7, 7, C["wall_d"])
    p.rect(x0 + 2, feet - 5, 30, 2, hexc("6e4726"))
    for px_ in (x0 + 7, x0 + 15, x0 + 23):
        p.rect(px_, feet - 11, 4, 2, hexc("efe7d2")); p.set(px_ + 1, feet - 12, C["yellow"])


def room_training(p, s):
    """訓練室: サンドバッグ、的、ダンベル。訓練で得られる経験値が増える部屋。"""
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1, wall=hexc("454a5c"), dark=hexc("30343f"), light=hexc("60677c"))
    lamp(p, x0 + 20, top + 2); lamp(p, x0 + 46, top + 2)
    # サンドバッグ
    p.vline(x0 + 10, top + 3, 7, C["steel_l"])
    p.rect(x0 + 7, top + 10, 7, 12, C["rust_l"]); p.hline(x0 + 7, top + 10, 7, C["copper"]); p.hline(x0 + 7, top + 15, 7, C["rust"])
    p.vline(x0 + 7, top + 10, 12, C["rust"]); p.hline(x0 + 7, top + 21, 7, C["copper_d"])
    # 的
    tx, ty = x0 + 30, top + 10
    p.ellipse(tx, ty, 6, 6, hexc("efe7d2")); p.ellipse(tx, ty, 4, 4, C["red"]); p.ellipse(tx, ty, 2, 2, hexc("efe7d2")); p.set(tx, ty, C["red"])
    # ダンベルラック
    p.rect(x0 + 38, feet - 9, 14, 2, C["steel_m"]); p.vline(x0 + 39, feet - 7, 7, C["steel_l"]); p.vline(x0 + 50, feet - 7, 7, C["steel_l"])
    for i in range(3):
        bx = x0 + 40 + i * 4
        p.rect(bx, feet - 12, 3, 3, C["steel_h"]); p.set(bx, feet - 11, C["black"]); p.set(bx + 2, feet - 11, C["black"])
    # マット
    p.rect(x0 + 2, feet - 3, 32, 2, C["green"]); p.hline(x0 + 2, feet - 3, 32, hexc("6ec4a4"))


def room_empty(p, s):
    """空き部屋: 何も置いていない、がらんとした部屋。"""
    x0, x1, top, feet = s["x0"], s["x1"], s["top"], s["feet"]
    room_bg(p, x0, x1, top, feet - 1, wall=hexc("4b3f33"), dark=hexc("362d24"), light=hexc("5f5041"))
    lamp(p, x0 + 30, top + 2)
    crate(p, x0 + 3, feet - 11, 7, 6)
    barrel(p, x0 + 46, feet - 14, C["rust"])


# 前面のコックピットと搬入口は入れ替えできない（固定）
def room_cockpit(p):
    x0, x1 = 140, 175
    room_bg(p, x0, x1, UP_TOP, UP_FEET - 1, wall=hexc("3f4652"))
    # 大きな前面窓（外の砂漠が見える）
    p.poly([(158, 18), (175, 18), (175, 34), (162, 34)], C["steel_d"])
    p.poly([(160, 19), (174, 19), (174, 33), (163, 33)], hexc("f4c986"))
    for y in range(19, 34):
        c = hexc("f4c986") if y < 26 else hexc("e6b466")
        for x in range(160, 175):
            if p.get(x, y)[3] and p.get(x, y) != C["steel_d"]:
                p.set(x, y, c)
    p.vline(168, 19, 15, C["steel_d"])
    # 操縦席
    p.rect(146, 32, 6, 8, C["steel_l"]); p.rect(146, 30, 2, 4, C["steel_m"])
    p.rect(150, 34, 3, 2, C["rust_l"])
    # 計器盤
    p.rect(153, 28, 10, 8, C["steel_d"]); p.rect(154, 29, 8, 4, hexc("4ad8a0"))
    p.hline(155, 31, 4, hexc("15564a")); p.set(160, 30, C["yellow"])
    for i in range(3):
        p.set(155 + i * 3, 34, [C["red"], C["yellow"], C["blue"]][i])
    lamp(p, 150, UP_TOP + 2)
    # ハンドル
    p.line(149, 29, 152, 31, C["copper"])


def room_bay(p):
    x0, x1 = 152, 175
    room_bg(p, x0, x1, LO_TOP, LO_FEET - 1, wall=hexc("3d434d"))
    lamp(p, 164, LO_TOP + 2)
    # クレーン
    p.hline(154, 48, 20, C["steel_l"]); p.vline(174, 46, 4, C["steel_l"])
    p.vline(160, 48, 10, hexc("c8b088")); p.rect(158, 58, 5, 2, C["steel_h"])
    # 警告灯
    p.rect(168, 54, 3, 3, C["red"]); p.set(169, 55, hexc("ffb0a0"))
    # 出入口の縁取り
    p.rect(176, 50, 6, 2, C["yellow"])
    for y in range(52, LO_FEET):
        p.set(176, y, C["yellow"] if (y // 3) % 2 == 0 else C["black"])
        p.set(177, y, C["yellow"] if (y // 3) % 2 == 0 else C["black"])
    p.rect(178, 52, 4, LO_FEET - 52, CLEAR)


def roof_details(p):
    # 車体の上に載る装備（アンテナ・排気筒・レーダー・タンク・砂袋）
    # アンテナ
    p.vline(30, 1, 9, C["steel_l"]); p.set(30, 0, C["red"]); p.line(26, 5, 30, 3, C["steel_l"]); p.line(34, 5, 30, 3, C["steel_l"])
    # 排気筒2本
    for x in (120, 128):
        p.rect(x, 2, 5, 8, C["steel_m"]); p.hline(x - 1, 2, 7, C["steel_h"]); p.rect(x + 3, 3, 1, 7, C["steel_d"])
        p.rect(x, 7, 5, 1, C["rust"])
    # 水タンク
    p.rect(50, 2, 16, 8, hexc("4b6b78")); p.hline(50, 2, 16, hexc("7aa3b3")); p.hline(50, 9, 16, C["steel_d"])
    p.vline(54, 2, 8, C["steel_d"]); p.vline(62, 2, 8, C["steel_d"])
    # レーダー
    p.rect(88, 5, 2, 5, C["steel_l"]); p.ellipse(89, 3, 6, 2, C["steel_h"]); p.hline(83, 3, 12, C["steel_d"])
    # 砂袋・ドラム缶
    for x in (140, 148, 156):
        p.ellipse(x, 8, 4, 2, hexc("c9a877")); p.hline(x - 3, 9, 7, hexc("8f7250"))
    # 旗
    p.vline(8, 0, 10, hexc("6a4a2a")); p.poly([(9, 0), (16, 1), (9, 4)], C["red"])


ROOM_FUNCS = {
    "workshop": room_workshop, "bedroom": room_bedroom, "engine": room_engine, "storage": room_storage,
    "infirmary": room_infirmary, "mess": room_mess, "training": room_training, "empty": room_empty,
}


def build_hull(layout=None, furnish=True, roof=True):
    """車体の絵。layout は {区画: 部屋の種類}。省略すると初期配置（従来の hull.png と同じ絵）。
    furnish=False にすると、建設で増える家具（ワークベンチ・ベッド）を描かない（ゲームで使う hull.png はこちら）。
    roof=False にすると、屋根の上の物（アンテナ・排気筒・タンクなど）を描かない。ゲームでは、屋根の上の物は外装パーツ
    （tools/art_exterior.py の roof_parts.png。ゲームの進み具合で増える）として、外装でも内装の断面図の上でも同じ絵を重ねて描く。"""
    global FURNISH
    FURNISH = furnish
    lay = dict(DEFAULT_LAYOUT)
    lay.update(layout or {})
    p = Px(IW, IH)
    hull_shell(p)
    ROOM_FUNCS[lay["u1"]](p, SLOTS["u1"]); ROOM_FUNCS[lay["u2"]](p, SLOTS["u2"]); room_cockpit(p)
    ROOM_FUNCS[lay["l1"]](p, SLOTS["l1"]); ROOM_FUNCS[lay["l2"]](p, SLOTS["l2"]); room_bay(p)
    floors(p)
    ladder(p)
    partition(p, 72, UP_TOP + 2, UP_FEET, 20); partition(p, 81, UP_TOP + 2, UP_FEET, 20)
    partition(p, 138, UP_TOP + 2, UP_FEET, 19)
    partition(p, 72, LO_TOP + 2, LO_FEET, 22); partition(p, 81, LO_TOP + 2, LO_FEET, 22)
    partition(p, 150, LO_TOP + 2, LO_FEET, 22)
    if roof:
        roof_details(p)
    return p


def slot_crop_rect(slot):
    """区画の上に重ねる絵の範囲（車体の絵の中のピクセル座標）。天井の照明の吊り金具ぶん、上に2行広げる。"""
    s = SLOTS[slot]
    return (s["x0"], s["top"] - 2, s["x1"] + 1, s["feet"])     # (left, top, right, bottom)


def room_overlays(furnish=False):
    """入れ替えできる全ての（区画, 部屋の種類）について、その区画に重ねる絵を作る。
    その部屋だけを置いた車体を描いて、区画の範囲を切り出す（隔壁やハシゴの一部も含むので、そのまま重ねられる）。
    furnish=False（ゲームで使う版）は、建設で増える家具（ワークベンチ・ベッド）を描かない（hull.png と同じ扱い）。
    furnish=True は、旧版の重ね絵（家具つき）と同じ絵になる。"""
    out = []
    for slot in SLOT_ORDER:
        for rtype, floors_ok in ROOM_FLOORS.items():
            if slot[0] not in floors_ok:
                continue
            hull = build_hull({slot: rtype}, furnish=furnish)
            l, t, r, b = slot_crop_rect(slot)
            crop = Px(r - l, b - t)
            crop.im.paste(hull.im.crop((l, t, r, b)), (0, 0))
            out.append((slot, rtype, crop))
    return out


def wheel(frame, n=4, R=13):
    p = Px(R * 2 + 2, R * 2 + 2)
    cx = cy = R
    p.ellipse(cx, cy, R, R, C["black"])
    p.ellipse(cx, cy, R - 3, R - 3, hexc("3a3f4a"))
    # タイヤの溝（回転で動く）
    for i in range(12):
        a = i * math.tau / 12 + frame * (math.tau / 12) / n
        p.set(int(round(cx + (R - 1) * math.cos(a))), int(round(cy + (R - 1) * math.sin(a))), hexc("3a3f4a"))
    p.ellipse(cx, cy, R - 6, R - 6, C["steel_m"])
    for i in range(6):
        a = i * math.tau / 6 + frame * (math.tau / 6) / n
        p.line(cx, cy, int(round(cx + (R - 4) * math.cos(a))), int(round(cy + (R - 4) * math.sin(a))), C["steel_h"])
    p.ellipse(cx, cy, 3, 3, C["rust_l"]); p.set(cx, cy, C["steel_d"])
    return p.outline(hexc("15171b"))


def wheels_sheet():
    n = 4
    S = 13 * 2 + 2 + 2
    sheet = Px(S * n, S)
    for f in range(n):
        w = wheel(f, n)
        sheet.im.alpha_composite(w.im, (f * S + 0, 0))
    return sheet, S


def ramp():
    p = Px(24, 18)
    # 斜路
    p.poly([(0, 0), (23, 15), (23, 17), (0, 3)], hexc("8b5a32"))
    p.poly([(0, 0), (23, 15), (23, 15), (0, 1)], hexc("c99a5c"))
    for i in range(3, 22, 4):
        p.line(i, i * 15 // 23, i, i * 15 // 23 + 3, hexc("5c3d22"))
    p.vline(0, 3, 6, C["steel_l"]); p.vline(22, 16, 2, C["steel_l"])
    p.line(1, 4, 21, 17, C["steel_m"])
    return p.outline(hexc("15171b"))


if __name__ == "__main__":
    import os
    os.makedirs("/tmp/pxprev", exist_ok=True)
    h = build_hull()
    bg = Px(IW, IH, hexc("f0c47c"))
    bg.im.alpha_composite(h.im)
    bg.save("/tmp/pxprev/hull.png", 6)
    sh, S = wheels_sheet()
    b2 = Px(sh.w, sh.h, hexc("f0c47c")); b2.im.alpha_composite(sh.im); b2.save("/tmp/pxprev/wheels.png", 6)
    r = ramp(); b3 = Px(r.w, r.h, hexc("f0c47c")); b3.im.alpha_composite(r.im); b3.save("/tmp/pxprev/ramp.png", 8)
