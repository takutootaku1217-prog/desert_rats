"""生成結果が今の assets/ と同じかどうかだけを確かめる（何も書き出さない）。
使い方: python tools/check_art.py
  - 絵を作るコードを直したあと、「既存の絵が変わっていないか」の確認に使う。
  - assets/ に無いファイル（新しく増える絵）は NEW と表示する。gen_art.py で書き出すと増える。"""
import os, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_art

same = new = diff = 0
for sub, name, px in gen_art.all_images():
    path = os.path.join(gen_art.ROOT, sub, name)
    if not os.path.exists(path):
        new += 1
        print("NEW ", sub, name)
        continue
    old = Image.open(path).convert("RGBA")
    if old.size == px.im.size and old.tobytes() == px.im.tobytes():
        same += 1
    else:
        diff += 1
        print("DIFF", sub, name, old.size, px.im.size)
print(f"同じ={same} 違う={diff} 新規={new}")
sys.exit(1 if diff else 0)
