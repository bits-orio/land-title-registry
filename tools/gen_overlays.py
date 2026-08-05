#!/usr/bin/env python3
"""Generate the per-state cell overlays drawn by the blocker entities
(ADR-0009): wilderness (red ribbons), trail (steel-blue lanes, opposite
diagonal), rampart (amber crosshatch). Deed cells have no blocker and stay
visually clear.

Each sprite is 1024x1024 px; the data stage scales it to the configured cell
size (fh-cell-size * 32 px per cell). Stripe periods divide 1024, so patterns
continue seamlessly across adjacent same-state cells; the cell-edge border is
what makes individual cells readable.

Run from the repo root:  python3 tools/gen_overlays.py
"""

from PIL import Image

SIZE = 1024
PERIOD = 128


def clamp_border(x, y):
    return min(x, y, SIZE - 1 - x, SIZE - 1 - y)


def make(name, pixel):
    img = Image.new("RGBA", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = pixel(x, y)
    out = __file__.rsplit("/", 2)[0] + f"/graphics/{name}.png"
    img.save(out, optimize=True)
    print(f"wrote {out}")


def wilderness(x, y):
    RED, DARK = (214, 48, 38), (150, 22, 18)
    b = clamp_border(x, y)
    if b < 4: return (*DARK, 120)
    if b < 6: return (*RED, 60)
    d = (x + y) % PERIOD
    if d < 30:
        if d < 4 or d >= 26: return (*DARK, 96)
        return (*RED, 54)
    return (*RED, 12)


def trail(x, y):
    BLUE, DARK = (92, 132, 172), (52, 76, 104)
    b = clamp_border(x, y)
    if b < 3: return (*DARK, 80)
    if b < 5: return (*BLUE, 40)
    d = (x - y) % PERIOD  # opposite diagonal to wilderness
    if d < 16:
        if d < 3 or d >= 13: return (*DARK, 52)
        return (*BLUE, 30)
    return (*BLUE, 6)


def rampart(x, y):
    AMBER, DARK = (196, 144, 58), (128, 88, 30)
    b = clamp_border(x, y)
    if b < 3: return (*DARK, 88)
    if b < 5: return (*AMBER, 44)
    d1 = (x + y) % PERIOD
    d2 = (x - y) % PERIOD
    hit1, hit2 = d1 < 14, d2 < 14
    if hit1 and hit2: return (*DARK, 64)
    if hit1 or hit2: return (*AMBER, 32)
    return (*AMBER, 7)


def main():
    make("wilderness-overlay", wilderness)
    make("trail-overlay", trail)
    make("rampart-overlay", rampart)


if __name__ == "__main__":
    main()
