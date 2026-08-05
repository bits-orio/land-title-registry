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

# Main colors come from scripts/state_colors.lua — the single source of
# truth shared with runtime edge rendering. Dark accents are derived.
import re
from pathlib import Path


def load_state_colors():
    text = (Path(__file__).resolve().parent.parent / "scripts/state_colors.lua").read_text()
    colors = {}
    for m in re.finditer(r"(\w+)\s*=\s*\{\s*r\s*=\s*(\d+),\s*g\s*=\s*(\d+),\s*b\s*=\s*(\d+)", text):
        colors[m.group(1)] = tuple(int(m.group(i)) for i in (2, 3, 4))
    return colors


COLORS = load_state_colors()


def darken(c, f=0.66):
    return tuple(round(v * f) for v in c)


ALPHA_SCALE = {
    "wilderness": 1.00,
    "trail": 0.90,
    "rampart": 0.80,
}

STATES = {
    name: (COLORS[name], darken(COLORS[name]), scale)
    for name, scale in ALPHA_SCALE.items()
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
