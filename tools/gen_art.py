"""全ドット絵素材を生成して ../assets に書き出す。
使い方: python3 tools/gen_art.py   （PIL が必要。生成済みPNGを使うだけなら実行不要）"""
import os
from pxlib import *
import art_chars, art_items, art_env, art_base, art_machine, art_creatures, art_gather, art_facilities, art_ui, art_exterior

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


def out(sub, name, px):
    d = os.path.join(ROOT, sub)
    os.makedirs(d, exist_ok=True)
    px.save(os.path.join(d, name))
    print("wrote", sub, name, px.w, "x", px.h)


for n in art_chars.PALETTES:
    out("characters", f"mouse_{n}.png", art_chars.build_mouse(n))
for k, fn in art_items.ITEMS.items():
    out("resources", f"item_{k}.png", fn())
env = art_env.build()
for k, px in env.items():
    out("environment", f"{k}.png", px)
art_ui.write_all(ROOT)            # UIのアイコンゲージ（重り。assets/ui/）
art_facilities.write_all(ROOT)    # 車体（ベッド・作業台・屋根の上の物を描かない版。hull.png）と、建設で増える設備（ワークベンチ・ベッド）
art_exterior.write_all(ROOT)      # 外装（外から見た車体・屋根や壁の外装パーツ・装甲。assets/base/exterior/）
sh, S = art_base.wheels_sheet()
out("base", "wheels.png", sh)
out("base", "ramp.png", art_base.ramp())
out("base", "machine.png", art_machine.build_machine_sheet())
for k, (fn, w, h) in art_creatures.CREATURES.items():
    out("creatures", f"{k}.png", art_creatures.sheet(fn, w, h))
art_gather.write_all(ROOT)        # 採取ポイント（岩場・鉱床・枯れ木）と採取の道具のアイコン
