#!/usr/bin/env python3
"""Builds every sprite the game uses into res://art/.

Inputs  : the user's uploaded sprites (path via UPLOADS env var) - used as-is wherever they exist.
Outputs : art/characters/<id>.png  horizontal strip, 64x64 cells, 6 frames: idle0 idle1 run0 run1 run2 run3
          (harpy: 8 frames, appends fly0 fly1 used while airborne)
          art/enemies/<id>.png     horizontal strip, 48x48 cells, 4 frames (walk cycle)
          art/fx/*.png             lightning strip, skull projectile strip

Characters/enemies with no provided art are drawn procedurally (placeholder quality, consistent
outline + rim shading so they read as one set). Swap any PNG for hand-made art of the same layout
and nothing else has to change.
"""
import os, sys, colorsys
from PIL import Image, ImageDraw
import numpy as np

UP = os.environ.get("UPLOADS", "/mnt/user-data/uploads")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = lambda *p: os.path.join(ROOT, *p)
CELL = 64
OUTLINE = (24, 16, 28, 255)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


# --------------------------------------------------------------------------- procedural painter
class Canvas:
    def __init__(self, w=48, h=48):
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        self.w, self.h = w, h

    def ell(self, cx, cy, rx, ry, col):
        self.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=col + (255,))

    def rect(self, x0, y0, x1, y1, col):
        self.d.rectangle([x0, y0, x1, y1], fill=col + (255,))

    def poly(self, pts, col):
        self.d.polygon(pts, fill=col + (255,))

    def line(self, pts, col, w=1):
        self.d.line(pts, fill=col + (255,), width=w)

    def px(self, x, y, col):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.im.putpixel((int(x), int(y)), col + (255,))

    def finish(self):
        """Rim-light top/left edges, shade bottom/right edges, then add a 1px dark outline."""
        a = np.array(self.im)
        op = a[:, :, 3] > 0
        pad = np.pad(op, 1)
        up, dn = ~pad[:-2, 1:-1], ~pad[2:, 1:-1]
        lf, rt = ~pad[1:-1, :-2], ~pad[1:-1, 2:]
        out = a.copy()
        hi = op & (up | lf)
        lo = op & (dn | rt) & ~hi
        out[hi, :3] = np.clip(a[hi, :3].astype(int) * 1.28 + 6, 0, 255)
        out[lo, :3] = np.clip(a[lo, :3].astype(int) * 0.72, 0, 255)
        # outline
        edge = ~op & (np.pad(op, 1)[:-2, 1:-1] | np.pad(op, 1)[2:, 1:-1] | np.pad(op, 1)[1:-1, :-2] | np.pad(op, 1)[1:-1, 2:])
        out[edge] = OUTLINE
        return Image.fromarray(out.astype(np.uint8), "RGBA")


def legs(c, phase, col, boot, y0=37, spread=5, w=5, thick=0):
    lift = [(0, 0), (2, 0), (0, 0), (0, 2)][phase % 4]
    for i, (x, lf) in enumerate(((24 - spread - w // 2, lift[0]), (24 + spread - w // 2, lift[1]))):
        c.rect(x, y0, x + w, 44 - lf, col)
        c.rect(x - 1, 42 - lf, x + w + 1, 44 - lf, boot)


def eyes(c, y, dx=4, col=(255, 255, 255), pupil=(20, 16, 24)):
    for s in (-1, 1):
        c.rect(24 + s * dx - 1, y, 24 + s * dx + 1, y + 1, col)
        c.px(24 + s * dx, y + 1, pupil)


def draw_cowboy(c, ph, bob):
    legs(c, ph, (58, 82, 134), (70, 44, 28))
    c.ell(24, 33 + bob, 10, 8, (150, 96, 54))                       # duster coat
    c.rect(14, 37 + bob, 34, 39 + bob, (110, 70, 40))                # coat hem
    c.rect(17, 34 + bob, 31, 36 + bob, (60, 40, 30)); c.rect(22, 34 + bob, 26, 36 + bob, (232, 190, 60))  # belt+buckle
    c.ell(10, 32 + bob - (ph % 2), 3, 4, (150, 96, 54)); c.ell(38, 32 + bob + (ph % 2), 3, 4, (150, 96, 54))
    c.poly([(19, 27 + bob), (24, 31 + bob), (29, 27 + bob)], (196, 52, 48))  # neckerchief
    c.ell(24, 19 + bob, 8, 8, (232, 180, 140))                        # head
    c.ell(24, 25 + bob, 6, 4, (110, 70, 40))                          # beard
    c.rect(15, 15 + bob, 17, 24 + bob, (96, 60, 34)); c.rect(31, 15 + bob, 33, 24 + bob, (96, 60, 34))  # curls
    eyes(c, 18 + bob, 3)
    c.ell(24, 11 + bob, 15, 3, (206, 160, 92))                        # wide brim
    c.rect(17, 3 + bob, 31, 11 + bob, (196, 150, 84)); c.rect(17, 9 + bob, 31, 10 + bob, (110, 60, 40))
    c.line([(28, 6 + bob), (34, 0 + bob)], (220, 60, 60), 2)         # feather
    c.rect(29, 24 + bob, 33, 24 + bob, (240, 230, 200))               # toothpick


def draw_pirate(c, ph, bob):
    legs(c, ph, (44, 40, 60), (40, 28, 24), spread=6, w=6)
    c.ell(24, 32 + bob, 13, 9, (232, 232, 236))                       # striped shirt
    for y in range(26, 40, 4): c.rect(11, y + bob, 37, y + 1 + bob, (196, 48, 52))
    c.rect(12, 34 + bob, 36, 36 + bob, (88, 52, 30)); c.rect(22, 34 + bob, 26, 36 + bob, (232, 190, 60))
    c.ell(9, 33 + bob - (ph % 2), 4, 4, (232, 180, 140)); c.ell(39, 33 + bob + (ph % 2), 4, 4, (232, 180, 140))
    c.rect(36, 30 + bob, 46, 34 + bob, (52, 52, 60)); c.rect(44, 29 + bob, 46, 35 + bob, (30, 30, 36))  # hand cannon
    c.ell(24, 19 + bob, 8, 8, (232, 180, 140))
    c.ell(24, 25 + bob, 5, 3, (70, 44, 30))
    eyes(c, 18 + bob, 3); c.rect(26, 16 + bob, 31, 20 + bob, (24, 20, 28))                      # eyepatch
    c.line([(15, 12 + bob), (33, 12 + bob)], (24, 20, 28), 1)
    c.poly([(11, 13 + bob), (24, 1 + bob), (37, 13 + bob)], (36, 32, 44))                        # tricorn
    c.line([(11, 13 + bob), (37, 13 + bob)], (232, 190, 60), 1)
    c.rect(23, 6 + bob, 25, 8 + bob, (240, 240, 240))                                            # skull dot


def draw_paladin(c, ph, bob):
    legs(c, ph, (170, 176, 190), (120, 124, 140), spread=5, w=6)
    c.ell(24, 32 + bob, 11, 9, (188, 194, 208))
    c.rect(22, 27 + bob, 26, 38 + bob, (240, 200, 70)); c.rect(18, 30 + bob, 30, 32 + bob, (240, 200, 70))  # gold cross
    c.ell(11, 28 + bob, 5, 4, (220, 224, 236)); c.ell(37, 28 + bob, 5, 4, (220, 224, 236))    # pauldrons
    c.ell(9, 34 + bob - (ph % 2), 3, 4, (170, 176, 190)); c.ell(39, 34 + bob + (ph % 2), 3, 4, (170, 176, 190))
    c.rect(41, 14 + bob, 43, 36 + bob, (210, 214, 224)); c.rect(38, 30 + bob, 46, 32 + bob, (240, 200, 70))  # greatsword
    c.ell(24, 17 + bob, 8, 9, (200, 206, 220))                        # helm
    c.rect(18, 17 + bob, 30, 19 + bob, (30, 26, 40)); c.rect(23, 17 + bob, 25, 24 + bob, (30, 26, 40))
    c.poly([(22, 8 + bob), (26, 8 + bob), (30, 1 + bob), (24, 3 + bob)], (200, 50, 60))          # plume
    c.rect(20, 5 + bob, 28, 8 + bob, (240, 200, 70))


def draw_wizard(c, ph, bob):
    c.poly([(11, 44), (37, 44), (33, 26 + bob), (15, 26 + bob)], (60, 80, 190))                  # robe
    c.rect(11, 42, 37, 44, (44, 60, 150))
    legs(c, ph, (40, 56, 140), (40, 56, 140), y0=42, spread=4, w=4)
    c.ell(9, 33 + bob - (ph % 2), 3, 4, (60, 80, 190)); c.ell(39, 33 + bob + (ph % 2), 3, 4, (60, 80, 190))
    c.rect(35, 31 + bob, 43, 39 + bob, (120, 60, 40)); c.rect(37, 33 + bob, 41, 37 + bob, (240, 220, 120))  # Merlin's book
    c.ell(24, 20 + bob, 7, 7, (232, 180, 140))
    c.poly([(17, 22 + bob), (31, 22 + bob), (24, 38 + bob)], (236, 236, 244))                    # long beard
    eyes(c, 19 + bob, 3)
    c.ell(24, 13 + bob, 12, 3, (48, 66, 168))
    c.poly([(15, 13 + bob), (33, 13 + bob), (29, 0 + bob), (24, -2 + bob)], (60, 80, 190))       # hat
    c.rect(15, 11 + bob, 33, 12 + bob, (240, 200, 70)); c.px(24, 6 + bob, (250, 240, 120))


def draw_spider(c, ph, bob):
    L = (52, 30, 88)
    sw = [0, 2, 0, -2][ph % 4]
    for s in (-1, 1):
        for i, (dy, ex, ey) in enumerate(((22, 20, 12), (27, 23, 27), (31, 22, 36), (35, 17, 44))):
            wig = sw if i % 2 == 0 else -sw
            c.line([(24 + s * 6, dy + bob), (24 + s * (ex - 4), dy - 6 + bob), (24 + s * ex, ey + wig)], L, 2)
    c.ell(24, 33 + bob, 10, 8, (70, 40, 116))                        # abdomen
    c.poly([(24, 29 + bob), (28, 34 + bob), (24, 39 + bob), (20, 34 + bob)], (220, 50, 60))      # hourglass
    c.ell(24, 21 + bob, 7, 6, (88, 52, 140))
    for x, y in ((21, 19), (27, 19), (19, 21), (29, 21), (22, 17), (26, 17)): c.px(x, y + bob, (255, 80, 90))
    c.rect(21, 26 + bob, 22, 28 + bob, (240, 240, 240)); c.rect(26, 26 + bob, 27, 28 + bob, (240, 240, 240))  # fangs


def draw_minotaur(c, ph, bob):
    legs(c, ph, (100, 62, 40), (50, 34, 28), spread=6, w=7)
    c.ell(24, 30 + bob, 15, 10, (120, 76, 48))                        # huge torso
    c.rect(14, 36 + bob, 34, 41 + bob, (70, 46, 34))                  # loincloth
    c.ell(8, 32 + bob - (ph % 2), 5, 6, (110, 68, 44)); c.ell(40, 32 + bob + (ph % 2), 5, 6, (110, 68, 44))
    c.ell(24, 15 + bob, 9, 8, (128, 82, 52))                          # head
    c.ell(24, 20 + bob, 5, 3, (196, 150, 120)); c.px(22, 21 + bob, (30, 20, 20)); c.px(26, 21 + bob, (30, 20, 20))
    c.line([(22, 23 + bob), (26, 23 + bob)], (240, 200, 70), 1)      # nose ring
    eyes(c, 13 + bob, 4, col=(255, 220, 200), pupil=(200, 30, 30))
    for s in (-1, 1):                                                   # horns
        c.poly([(24 + s * 7, 10 + bob), (24 + s * 12, 4 + bob), (24 + s * 17, 0 + bob), (24 + s * 14, 8 + bob), (24 + s * 10, 12 + bob)], (238, 226, 190))
    c.ell(24, 7 + bob, 4, 3, (96, 60, 38))


def draw_harpy(c, ph, bob):
    flap = [0, -3, -5, -2][ph % 4]
    for s in (-1, 1):                                                   # spread wings
        c.poly([(24 + s * 6, 22 + bob), (24 + s * 22, 14 + bob + flap), (24 + s * 23, 24 + bob + flap), (24 + s * 16, 34 + bob), (24 + s * 6, 34 + bob)], (92, 64, 44))
        for i in range(4): c.rect(24 + s * (14 + i * 2) - (1 if s < 0 else 0), 24 + bob + flap + i, 24 + s * (15 + i * 2), 30 + bob + flap + i * 2, (216, 200, 170))
    c.ell(24, 30 + bob, 8, 9, (70, 50, 38))
    c.ell(24, 28 + bob, 5, 6, (232, 226, 214))                        # pale chest
    c.rect(20, 38 + bob, 22, 43 + bob, (240, 200, 70)); c.rect(26, 38 + bob, 28, 43 + bob, (240, 200, 70))  # talons
    c.ell(24, 17 + bob, 7, 7, (170, 176, 184))                        # grey head
    for x0, x1 in ((17, 14), (20, 17), (28, 31), (31, 34)): c.line([(x0, 13 + bob), (x1, 5 + bob)], (30, 28, 34), 2)  # crest
    c.poly([(22, 18 + bob), (26, 18 + bob), (24, 25 + bob)], (250, 200, 60))                     # hooked beak
    for s in (-1, 1): c.rect(24 + s * 4 - 1, 15 + bob, 24 + s * 4 + 1, 16 + bob, (250, 250, 250)); c.px(24 + s * 4, 16 + bob, (20, 16, 24))


def draw_goose(c, ph, bob):
    for s in (-1, 1): c.rect(24 + s * 4 - 1, 39, 24 + s * 4 + 1, 44 - (ph % 2 if s > 0 else 0), (250, 150, 40)); c.rect(24 + s * 4 - 3, 43 - (ph % 2 if s > 0 else 0), 24 + s * 4 + 3, 44 - (ph % 2 if s > 0 else 0), (250, 150, 40))
    c.ell(24, 33 + bob, 11, 8, (246, 246, 250))
    c.ell(10, 32 + bob - (ph % 2) * 2, 4, 5, (226, 228, 240)); c.ell(38, 32 + bob + (ph % 2) * 2, 4, 5, (226, 228, 240))
    c.rect(22, 15 + bob, 26, 29 + bob, (246, 246, 250))               # neck
    c.ell(24, 13 + bob, 6, 5, (250, 250, 252))
    c.poly([(19, 15 + bob), (29, 15 + bob), (24, 21 + bob)], (250, 150, 40))                     # beak
    c.rect(20, 11 + bob, 22, 12 + bob, (20, 16, 24)); c.rect(26, 11 + bob, 28, 12 + bob, (20, 16, 24))
    c.rect(19, 10 + bob, 23, 10 + bob, (60, 60, 70)); c.rect(25, 10 + bob, 29, 10 + bob, (60, 60, 70))  # smug lids


# enemies ----------------------------------------------------------------------------------
def draw_skeleton(c, ph, bob):
    B = (232, 226, 206)
    legs(c, ph, B, (200, 194, 174), spread=4, w=3)
    c.rect(18, 27 + bob, 30, 37 + bob, (60, 56, 64))
    for y in (28, 31, 34): c.rect(19, y + bob, 29, y + bob, B)
    c.rect(23, 27 + bob, 25, 37 + bob, B)
    c.rect(10, 28 + bob - (ph % 2), 12, 38 + bob, B); c.rect(36, 28 + bob + (ph % 2), 38, 38 + bob, B)
    c.ell(24, 17 + bob, 8, 8, B); c.rect(19, 23 + bob, 29, 26 + bob, B)
    c.rect(18, 15 + bob, 22, 19 + bob, (24, 20, 28)); c.rect(26, 15 + bob, 30, 19 + bob, (24, 20, 28))
    c.px(20, 17 + bob, (255, 70, 70)); c.px(28, 17 + bob, (255, 70, 70)); c.rect(23, 20 + bob, 25, 21 + bob, (24, 20, 28))


def draw_bat(c, ph, bob):
    flap = [-6, -2, 4, 0][ph % 4]
    for s in (-1, 1):
        c.poly([(24 + s * 4, 20 + bob), (24 + s * 22, 12 + bob + flap), (24 + s * 18, 22 + bob + flap // 2), (24 + s * 14, 20 + bob + flap // 2),
                (24 + s * 10, 28 + bob), (24 + s * 4, 30 + bob)], (108, 60, 150))
    c.ell(24, 25 + bob, 6, 7, (78, 44, 108)); c.ell(24, 18 + bob, 6, 5, (92, 52, 126))
    c.poly([(19, 15 + bob), (19, 9 + bob), (23, 13 + bob)], (92, 52, 126)); c.poly([(29, 15 + bob), (29, 9 + bob), (25, 13 + bob)], (92, 52, 126))
    c.px(22, 18 + bob, (255, 220, 80)); c.px(26, 18 + bob, (255, 220, 80)); c.rect(23, 22 + bob, 23, 23 + bob, (250, 250, 250)); c.rect(25, 22 + bob, 25, 23 + bob, (250, 250, 250))


def draw_raptor(c, ph, bob):
    G = (86, 150, 70)
    for s, lf in ((-1, [0, 3, 0, 0][ph % 4]), (1, [0, 0, 0, 3][ph % 4])):
        c.rect(24 + s * 4 - 1, 34, 24 + s * 4 + 2, 43 - lf, (66, 116, 56)); c.rect(24 + s * 4 - 2, 42 - lf, 24 + s * 4 + 4, 44 - lf, (240, 220, 160))
    c.poly([(24, 28 + bob), (44, 36 + bob), (46, 40 + bob), (34, 36 + bob)], G)                  # tail
    c.ell(22, 30 + bob, 10, 8, G); c.ell(24, 34 + bob, 6, 3, (200, 210, 140))
    c.ell(12, 18 + bob, 6, 5, G); c.poly([(2, 18 + bob), (12, 16 + bob), (12, 24 + bob), (4, 22 + bob)], G)   # head+snout
    c.rect(9, 24 + bob, 12, 26 + bob, (240, 240, 240)); c.rect(4, 22 + bob, 7, 23 + bob, (240, 240, 240))
    c.rect(11, 22 + bob, 15, 30 + bob, G); c.px(11, 16 + bob, (255, 200, 40)); c.rect(9, 30 + bob, 11, 32 + bob, (240, 240, 240))
    c.line([(20, 26 + bob), (28, 24 + bob)], (60, 100, 50), 1)


def draw_whelp(c, ph, bob):
    flap = [-5, -1, 5, 1][ph % 4]
    R = (200, 60, 50)
    for s in (-1, 1):
        c.poly([(24 + s * 4, 22 + bob), (24 + s * 23, 8 + bob + flap), (24 + s * 21, 20 + bob + flap), (24 + s * 14, 18 + bob + flap // 2),
                (24 + s * 12, 30 + bob), (24 + s * 4, 32 + bob)], (150, 40, 60))
    c.ell(24, 28 + bob, 8, 9, R); c.ell(24, 32 + bob, 5, 6, (240, 190, 100))
    c.poly([(24, 36 + bob), (36, 44 + bob), (30, 34 + bob)], R)
    c.ell(24, 17 + bob, 7, 6, R); c.ell(24, 22 + bob, 4, 3, (224, 90, 70))
    for s in (-1, 1): c.poly([(24 + s * 5, 12 + bob), (24 + s * 9, 5 + bob), (24 + s * 8, 13 + bob)], (240, 226, 190)); c.px(24 + s * 3, 16 + bob, (255, 230, 80)); c.px(24 + s * 2, 22 + bob, (30, 20, 20))


PROC_CHARS = dict(cowboy=draw_cowboy, pirate=draw_pirate, paladin=draw_paladin, wizard=draw_wizard,
                  spider=draw_spider, minotaur=draw_minotaur, harpy=draw_harpy, goose=draw_goose)
PROC_ENEMIES = dict(skeleton=draw_skeleton, bat=draw_bat, raptor=draw_raptor, dragon_whelp=draw_whelp)
IDLE = [(0, 0), (0, -1)]
RUN = [(0, -1), (1, 0), (2, -1), (3, 0)]
FLY = [(0, -8), (2, -10)]


def cell_paste(strip, i, img, cell, anchor_x=None):
    """Paste img into cell i, bottom-centred (feet at y = cell-2)."""
    bb = img.getbbox()
    if not bb: return
    x = i * cell + (cell - img.width) // 2
    y = cell - 2 - bb[3]
    strip.alpha_composite(img, (x, y))


def proc_strip(fn, cell, frames):
    strip = Image.new("RGBA", (cell * len(frames), cell), (0, 0, 0, 0))
    for i, (ph, bob) in enumerate(frames):
        c = Canvas(); fn(c, ph, bob); cell_paste(strip, i, c.finish(), cell)
    return strip


# --------------------------------------------------------------------------- provided art
def key_bg(img, thresh=40):
    """Flood-fill the (white) background from the corners and make it transparent."""
    rgb = img.convert("RGB")
    for pt in ((0, 0), (rgb.width - 1, 0), (0, rgb.height - 1), (rgb.width - 1, rgb.height - 1)):
        if rgb.getpixel(pt)[0] > 200:
            ImageDraw.floodfill(rgb, pt, (255, 0, 255), thresh=thresh)
    a = np.array(rgb); out = np.array(img.convert("RGBA"))
    out[(a[:, :, 0] == 255) & (a[:, :, 1] == 0) & (a[:, :, 2] == 255), 3] = 0
    return Image.fromarray(out)


def resize_px(img, target_h, colors=24):
    """Resample to target height, then re-quantise so it still reads as pixel art."""
    bb = img.getbbox(); f = img.crop(bb)
    sc = target_h / f.height
    f = f.resize((max(1, round(f.width * sc)), target_h), Image.LANCZOS)
    a = np.array(f); a[:, :, 3] = np.where(a[:, :, 3] > 110, 255, 0)
    q = Image.fromarray(a).quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGBA")
    qa = np.array(q); qa[:, :, 3] = a[:, :, 3]
    return Image.fromarray(qa)


def ninja_strip():
    g = Image.open(os.path.join(UP, "Ninja.gif"))
    frames = []
    for i in range(g.n_frames):
        g.seek(i); frames.append(g.convert("RGBA"))
    strip = Image.new("RGBA", (CELL * 6, CELL), (0, 0, 0, 0))
    pick = [0, 4, 19, 21, 23, 25]                                  # idle, idle, 4x run (no slash arcs)
    for i, fi in enumerate(pick):
        f = resize_px(frames[fi].crop((26, 0, 74, 34)), 42, 20)     # ~32px source -> 42px to match the set
        cell_paste(strip, i, f, CELL)
    return strip


def necro_strip():
    s = Image.open(os.path.join(UP, "IMG_2166.png")).convert("RGBA")
    f0, f1 = key_bg(s.crop((0, 0, 64, 64))), key_bg(s.crop((64, 0, 128, 64)))
    strip = Image.new("RGBA", (CELL * 6, CELL), (0, 0, 0, 0))
    ref = f0.getbbox()
    for i, f in enumerate([f0, f1, f0, f1, f0, f1]):
        r = resize_px(f, 48, 28); cell_paste(strip, i, r, CELL)
    return strip


def skull_strip():
    s = Image.open(os.path.join(UP, "wailing-skull-front-spritesheet.png")).convert("RGBA")
    out = Image.new("RGBA", s.size, (0, 0, 0, 0))
    for i in range(2): out.alpha_composite(key_bg(s.crop((i * 64, 0, i * 64 + 64, 64)), 60), (i * 64, 0))
    return out


def lightning_strip():
    g = Image.open(os.path.join(UP, "Wizard_lightning.gif"))
    strip = Image.new("RGBA", (52 * g.n_frames, 127), (0, 0, 0, 0))
    for i in range(g.n_frames):
        g.seek(i); strip.alpha_composite(g.convert("RGBA"), (i * 52, 0))
    return strip


def hue_shift(img, deg, sat=1.0, val=1.0):
    a = np.array(img); rgb = a[:, :, :3].astype(float) / 255
    out = a.copy()
    h, w = a.shape[:2]
    for y in range(h):
        for x in range(w):
            if a[y, x, 3] == 0: continue
            hh, ss, vv = colorsys.rgb_to_hsv(*rgb[y, x])
            hh = (hh + deg / 360.0) % 1.0
            r, g, b = colorsys.hsv_to_rgb(hh, min(1, ss * sat), min(1, vv * val))
            out[y, x, :3] = (int(r * 255), int(g * 255), int(b * 255))
    return Image.fromarray(out)


def goblin_strips():
    s = Image.open(os.path.join(UP, "Walk_zombie_gob.png")).convert("RGBA")
    row = 1                                                          # left-facing row of the 3x4 sheet
    fr = [s.crop((c * 48, row * 48, c * 48 + 48, row * 48 + 48)) for c in range(3)]
    order = [0, 1, 2, 1]
    def mk(img_fn):
        st = Image.new("RGBA", (48 * 4, 48), (0, 0, 0, 0))
        for i, k in enumerate(order): st.alpha_composite(img_fn(fr[k]), (i * 48, 0))
        return st
    return mk(lambda f: f), mk(lambda f: hue_shift(f, -150, 0.9, 0.85)), mk(lambda f: hue_shift(f, 110, 1.1, 0.95))


def assassin_strip():
    s = Image.open(os.path.join(UP, "Zombie_gob_walk.png")).convert("RGBA")
    wins = [(30, 270), (270, 610), (610, 960), (960, 1250), (1250, 1520)]
    frames = []
    for x0, x1 in wins:
        f = s.crop((x0, 190, x1, 450))                               # front row, body only
        bb = f.getbbox(); f = f.crop(bb)
        sc = 42.0 / f.height
        f = f.resize((max(1, round(f.width * sc)), 42), Image.LANCZOS)
        a = np.array(f); a[:, :, 3] = np.where(a[:, :, 3] > 120, 255, 0)
        f = Image.fromarray(a).quantize(colors=28, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGBA")
        a = np.array(f); f = Image.fromarray(a)
        frames.append(f)
    return frames


def main():
    for d in ("art/characters", "art/enemies", "art/fx"): os.makedirs(OUT(d), exist_ok=True)
    ninja_strip().save(OUT("art/characters/ninja.png"))
    necro_strip().save(OUT("art/characters/necromancer.png"))
    for cid, fn in PROC_CHARS.items():
        if cid == "goose" and os.path.exists(OUT("art/characters/goose.png")):
            continue  # custom goose art is single source - do not overwrite
        frames = IDLE + RUN + FLY if cid == "harpy" else IDLE + RUN
        proc_strip(fn, CELL, frames).save(OUT(f"art/characters/{cid}.png"))
    for eid, fn in PROC_ENEMIES.items():
        proc_strip(fn, 48, RUN).save(OUT(f"art/enemies/{eid}.png"))
    g, z, b = goblin_strips()
    g.save(OUT("art/enemies/goblin.png")); b.save(OUT("art/enemies/goblin_brute.png"))  # zombie_goblin retired: zombie.png is user-supplied, do not regenerate here
    fr = assassin_strip()
    st = Image.new("RGBA", (48 * 4, 48), (0, 0, 0, 0))
    for i, k in enumerate([0, 4, 0, 4]):
        f = fr[k]; st.alpha_composite(f, (i * 48 + (48 - f.width) // 2, 47 - f.height))
    st.save(OUT("art/enemies/goblin_assassin.png"))
    # attack frames kept for the charger wind-up visual
    at = Image.new("RGBA", (64 * 3, 48), (0, 0, 0, 0))
    for i, k in enumerate([1, 2, 3]):
        f = fr[k].crop(fr[k].getbbox()); at.alpha_composite(f.crop((0, 0, min(64, f.width), 42)), (i * 64, 47 - min(42, f.height)))
    at.save(OUT("art/enemies/goblin_assassin_attack.png"))
    skull_strip().save(OUT("art/fx/skull_projectile.png"))
    lightning_strip().save(OUT("art/fx/lightning.png"))
    print("assets built ->", OUT("art"))


if __name__ == "__main__":
    main()
