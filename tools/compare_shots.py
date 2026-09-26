"""2つのフォルダの同名のPNGを画素単位で比べる（tools/shot_dpu.gd の出力用）。
使い方: python tools/compare_shots.py <フォルダA> <フォルダB> [差分画像の出力フォルダ]
  … 同じ名前の画像ごとに、大きさ・違う画素の数・最大の色差を出す。全部一致なら終了コード 0。"""
import os
import sys
from PIL import Image, ImageChops


def main():
    a, b = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else None
    names = sorted(f for f in os.listdir(a) if f.endswith(".png") and os.path.exists(os.path.join(b, f)))
    bad = 0
    for n in names:
        ia = Image.open(os.path.join(a, n)).convert("RGB")
        ib = Image.open(os.path.join(b, n)).convert("RGB")
        if ia.size != ib.size:
            print(f"{n}: 大きさが違う {ia.size} / {ib.size}")
            bad += 1
            continue
        diff = ImageChops.difference(ia, ib)
        bbox = diff.getbbox()
        if bbox is None:
            print(f"{n}: 一致（{ia.size[0]}x{ia.size[1]}）")
            continue
        px = diff.load()
        cnt = 0
        mx = 0
        for y in range(diff.height):
            for x in range(diff.width):
                d = max(px[x, y])
                if d:
                    cnt += 1
                    mx = max(mx, d)
        print(f"{n}: 違う画素 {cnt}（最大の色差 {mx}）範囲 {bbox}")
        bad += 1
        if out:
            os.makedirs(out, exist_ok=True)
            enhanced = diff.point(lambda v: 255 if v else 0)
            enhanced.save(os.path.join(out, "diff_" + n))
    print("== 結果:", "すべて一致" if bad == 0 else f"{bad} 枚が違う", "==")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
