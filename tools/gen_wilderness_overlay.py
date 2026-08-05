#!/usr/bin/env python3
"""Generate graphics/wilderness-overlay.png — the translucent red-ribbon
pattern drawn by the fh-cell-wilderness blocker over unclaimed cells.

1024x1024 px = one 32-tile cell at normal resolution (32 px/tile, sprite
scale 1). The diagonal stripe period divides 1024, so the pattern continues
seamlessly across adjacent wilderness cells; the cell-edge border is what
makes individual cells readable.

Run from the repo root:  python3 tools/gen_wilderness_overlay.py
"""

from PIL import Image

SIZE = 1024
RED = (214, 48, 38)
DARK = (150, 22, 18)

PERIOD = 128        # diagonal stripe period; divides SIZE for seamless tiling
RIBBON = 30         # ribbon width along the diagonal
EDGE = 4            # darker edge band on each side of a ribbon
WASH_A = 12         # faint wash between ribbons
CORE_A = 54         # ribbon core alpha
EDGE_A = 96         # ribbon edge alpha
BORDER = 4          # cell-edge border thickness
BORDER_A = 120      # cell-edge border alpha
INNER = 2           # subtle inner border line
INNER_A = 60


def pixel(x, y):
    # Cell-edge border (strongest cue: where cells begin and end).
    b = min(x, y, SIZE - 1 - x, SIZE - 1 - y)
    if b < BORDER:
        return (*DARK, BORDER_A)
    if b < BORDER + INNER:
        return (*RED, INNER_A)

    d = (x + y) % PERIOD
    if d < RIBBON:
        if d < EDGE or d >= RIBBON - EDGE:
            return (*DARK, EDGE_A)
        return (*RED, CORE_A)
    return (*RED, WASH_A)


def main():
    img = Image.new("RGBA", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = pixel(x, y)
    out = __file__.rsplit("/", 2)[0] + "/graphics/wilderness-overlay.png"
    img.save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
