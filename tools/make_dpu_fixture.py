"""絵の細かさの差し替えの動作確認用データを作る（ゲームには含めない）。
使い方: python tools/make_dpu_fixture.py <出力フォルダ> [倍率=2] [グループ,グループ,…]
  assets/ の絵を、最近傍で倍率ぶん拡大した「高精細な絵（を模したもの）」を <出力フォルダ> に、assets/ と同じ相対パスで書く。
  外装の parts.json は、絵の切り出し（frames。画像のピクセル）だけ倍率をかける（置き場所・units はユニットなので変えない）。
  グループを指定すると、そのグループの絵だけを拡大する（ほかは元の絵のまま＝段階的な高精細化の確認用）。
  グループ: characters creatures items gather environment ui rooms exterior base（車体・車輪・斜路・加工機・設備）
  ゲームには、コマンドラインの `--art-root=<出力フォルダ>` で渡す（data/art_spec.gd）。拡大しただけなので、細かさ以外の見た目は同じになるはず。"""
import json
import os
import sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


def group_of(rel):
    rel = rel.replace("\\", "/")
    if rel.startswith("characters/"): return "characters"
    if rel.startswith("creatures/"): return "creatures"
    if rel.startswith("resources/"): return "items"
    if rel.startswith("gather/"): return "gather"
    if rel.startswith("environment/"): return "environment"
    if rel.startswith("ui/"): return "ui"
    if rel.startswith("base/rooms/"): return "rooms"
    if rel.startswith("base/exterior/"): return "exterior"
    if rel.startswith("base/"): return "base"
    return "other"


def main():
    out = sys.argv[1]
    factor = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    only = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else None
    n = 0
    for dp, _, files in os.walk(ROOT):
        for f in files:
            rel = os.path.relpath(os.path.join(dp, f), ROOT)
            g = group_of(rel)
            if only is not None and g not in only:
                continue
            src = os.path.join(dp, f)
            dst = os.path.join(out, rel)
            if f.endswith(".png"):
                im = Image.open(src).convert("RGBA")
                big = im.resize((im.width * factor, im.height * factor), Image.NEAREST)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                big.save(dst)
                n += 1
            elif f == "parts.json":
                geo = json.load(open(src, encoding="utf-8"))
                for sh in geo["sheets"].values():
                    for k, v in sh["frames"].items():
                        sh["frames"][k] = [x * factor for x in v]
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, "w", encoding="utf-8", newline="\n") as fh:
                    json.dump(geo, fh, ensure_ascii=False, indent=1, sort_keys=True)
                n += 1
    print("wrote", n, "files to", out, "(x%d)" % factor, ("groups: " + ",".join(sorted(only))) if only else "(all groups)")


if __name__ == "__main__":
    main()
