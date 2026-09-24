"""ドット絵生成用の小さなヘルパー（PILのみ使用）。
すべてオリジナルのドット絵をコードで描く。素材は assets/ に出力される。"""
from PIL import Image

def hexc(s, a=255):
    s = s.lstrip('#')
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)

CLEAR = (0, 0, 0, 0)


class Px:
    def __init__(self, w, h, fill=CLEAR):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w, h), fill)
        self.p = self.im.load()

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.p[x, y] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.p[x, y]
        return CLEAR

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def hline(self, x, y, w, c):
        self.rect(x, y, w, 1, c)

    def vline(self, x, y, h, c):
        self.rect(x, y, 1, h, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x - cx) / max(rx, 0.01)) ** 2 + ((y - cy) / max(ry, 0.01)) ** 2 <= 1.0:
                    self.set(x, y, c)

    def poly(self, pts, c):
        # 走査線塗りつぶし
        ys = [p[1] for p in pts]
        for y in range(min(ys), max(ys) + 1):
            xs = []
            n = len(pts)
            for i in range(n):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % n]
                if y0 == y1:
                    continue
                if min(y0, y1) <= y < max(y0, y1):
                    xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(round(xs[i])), int(round(xs[i + 1])) + 1):
                    self.set(x, y, c)

    def paste(self, other, x, y, flip=False):
        src = other.im.transpose(Image.FLIP_LEFT_RIGHT) if flip else other.im
        self.im.alpha_composite(src, (x, y)) if (x >= 0 and y >= 0) else self._paste_clip(src, x, y)

    def _paste_clip(self, src, x, y):
        for yy in range(src.height):
            for xx in range(src.width):
                c = src.getpixel((xx, yy))
                if c[3] > 0:
                    self.set(x + xx, y + yy, c)

    def outline(self, c, only_bottom=False):
        """透明部との境界に1pxの輪郭を追加した新しい Px を返す。"""
        out = Px(self.w, self.h)
        out.im.alpha_composite(self.im)
        for y in range(self.h):
            for x in range(self.w):
                if self.p[x, y][3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        if self.get(x + dx, y + dy)[3] > 0:
                            out.set(x, y, c)
                            break
        return out

    def save(self, path, scale=1):
        im = self.im if scale == 1 else self.im.resize((self.w * scale, self.h * scale), Image.NEAREST)
        im.save(path)


def dither(px, x0, y0, w, h, c1, c2, level):
    """2色の格子ディザ塗り。level 0..4"""
    pats = [
        [[0, 0], [0, 0]],
        [[1, 0], [0, 0]],
        [[1, 0], [0, 1]],
        [[1, 1], [0, 1]],
        [[1, 1], [1, 1]],
    ]
    pat = pats[level]
    for y in range(h):
        for x in range(w):
            px.set(x0 + x, y0 + y, c2 if pat[y % 2][x % 2] else c1)
