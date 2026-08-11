#!/usr/bin/env python3
"""Generate the per-state cell overlays drawn by the blocker entities
(ADR-0009). One shared ribbon pattern; the states differ in color and
stripe strength (playtest call, 0.1.8: the original full-strength red
pattern reads as "fortified, not yet fully yours" and now marks RAMPART;
wilderness escalates the same artwork to fully opaque red stripes,
unmistakable at any zoom):

    wilderness  red, stripes 100% opaque   (hard no)
    trail       orange, calmer             (transit corridor)
    rampart     red, the original pattern  (one rung from Deed)
    deed        —                          (no blocker, fully clear)

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


# Per-state look. Rampart deliberately wears the WILDERNESS palette entry —
# if that line looks wrong, read the module docstring: the red pattern
# moved down a rung, it was not left behind by accident. Only wilderness
# sets opaque_ribbon, which lifts the two stripe elements (edge + core) to
# alpha 255 while border, inner line, and wash keep their usual strengths.
RED = COLORS["wilderness"]
STATES = {
    "wilderness": (RED, darken(RED), 1.00, True),
    "trail": (COLORS["trail"], darken(COLORS["trail"]), 0.90, False),
    "rampart": (RED, darken(RED), 1.00, False),
}


def make(name, color, dark, alpha_scale, opaque_ribbon, suffix="", wash=True):
    def a(key):
        if opaque_ribbon and key in ("ribbon_edge", "ribbon_core"):
            return 255
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
                elif wash:
                    px[x, y] = (*color, a("wash"))
                else:
                    px[x, y] = (0, 0, 0, 0)
    out = __file__.rsplit("/", 2)[0] + f"/graphics/{name}-overlay{suffix}.png"
    img.save(out, optimize=True)
    print(f"wrote {out}")


def main():
    for name, (color, dark, scale, opaque_ribbon) in STATES.items():
        make(name, color, dark, scale, opaque_ribbon)
    # Chart variants for the claimed states (drawn by scripts/render.lua in
    # map view): identical translucent stripes and cell border, but the
    # between-stripes wash is fully transparent — on the chart the wash
    # reads as a solid background block over the terrain (playtest report),
    # while in the world it sits invisibly on actual ground. An opaque-
    # stripe experiment was reverted by the same playtester: the "green
    # tint" it chased turned out to be the wilderness map tint recoloring
    # everything EXCEPT the territory (see prototypes/blockers.lua).
    for name in ("trail", "rampart"):
        color, dark, scale, opaque_ribbon = STATES[name]
        make(name, color, dark, scale, opaque_ribbon, suffix="-chart", wash=False)


if __name__ == "__main__":
    main()
