#!/usr/bin/env python3
"""Generate the per-state cell overlays drawn by the blocker entities
(ADR-0009). One shared ribbon pattern; the states differ only in color and
transparency, forming a busy-to-calm gradient that matches raising land one
rung at a time:

    wilderness  red     (full strength)
    trail       orange  (more transparent)
    rampart     yellow  (more transparent still)
    deed        —       (no blocker, fully clear)

Each sprite is 1024x1024 px; the data stage scales it to the configured cell
size. The stripe period divides 1024, so patterns continue seamlessly across
adjacent same-state cells; the cell-edge border keeps individual cells
readable.

Run from the repo root:  python3 tools/gen_overlays.py
"""

from PIL import Image

SIZE = 1024
PERIOD = 128
RIBBON = 30
EDGE = 4
BORDER = 4
INNER = 2

# Base alphas at full strength (wilderness).
A = {
    "border": 120,
    "inner": 60,
    "ribbon_edge": 96,
    "ribbon_core": 54,
    "wash": 12,
}

STATES = {
    # name: (main color, dark accent, alpha scale)
    "wilderness": ((214, 48, 38), (150, 22, 18), 1.00),
    "trail": ((222, 126, 38), (158, 84, 16), 0.72),
    "rampart": ((224, 186, 48), (160, 128, 20), 0.52),
}


def make(name, color, dark, alpha_scale):
    def a(key):
        return max(1, round(A[key] * alpha_scale))

    img = Image.new("RGBA", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            b = min(x, y, SIZE - 1 - x, SIZE - 1 - y)
            if b < BORDER:
                px[x, y] = (*dark, a("border"))
            elif b < BORDER + INNER:
                px[x, y] = (*color, a("inner"))
            else:
                d = (x + y) % PERIOD
                if d < RIBBON:
                    if d < EDGE or d >= RIBBON - EDGE:
                        px[x, y] = (*dark, a("ribbon_edge"))
                    else:
                        px[x, y] = (*color, a("ribbon_core"))
                else:
                    px[x, y] = (*color, a("wash"))
    out = __file__.rsplit("/", 2)[0] + f"/graphics/{name}-overlay.png"
    img.save(out, optimize=True)
    print(f"wrote {out}")


def main():
    for name, (color, dark, scale) in STATES.items():
        make(name, color, dark, scale)


if __name__ == "__main__":
    main()
