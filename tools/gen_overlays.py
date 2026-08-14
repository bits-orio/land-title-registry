#!/usr/bin/env python3
"""Generate the per-state cell overlays drawn by the blocker entities
(ADR-0009). One shared ribbon pattern; the states differ in color and
stripe strength (playtest call, 0.1.8: the original full-strength red
pattern reads as "fortified, not yet fully yours" and now marks RAMPART;
wilderness escalates the same artwork to fully opaque red stripes,
unmistakable at any zoom):

    wilderness  red, stripes 100% opaque   (hard no)
    trail       orange at ~half strength   (transit corridor)
    rampart     red, the original pattern  (one rung from Deed)
    deed        —                          (no blocker, fully clear)

Stripe weight tracks how much the rung forbids, so the ladder reads as a
gradient from loud to silent even before the colors register.

Each sprite is 1024x1024 px; the data stage scales it to the configured cell
size. The stripe period divides 1024, so patterns continue seamlessly across
adjacent same-state cells; the cell-edge border keeps individual cells
readable.

Run from the repo root:  python3 tools/gen_overlays.py
"""

from PIL import Image
import numpy as np

SIZE = 1024
PERIOD = 128
# 16px of 128 (12.5% coverage, half the original 30): thin enough that map
# terrain stays readable under the stripes (playtest call), same artwork
# in the world so both views speak one language.
RIBBON = 16
EDGE = 3
BORDER = 4
INNER = 2

# Supersampling factor: the pattern is computed at SIZE*SS and downscaled
# with Lanczos, anti-aliasing every diagonal edge. The hard per-pixel
# thresholds looked fine at the old translucent alphas but turned into
# staircases once the wilderness stripes went fully opaque (playtest
# report: "as if anti-aliasing isn't happening" — it wasn't).
SS = 4

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
# moved down a rung, it was not left behind by accident.
#
# The last field overrides individual alphas from A. Stripe strength is set
# per state rather than scaled globally, because alpha_scale also dims the
# cell border and wash — and the states want different stripe weights while
# sharing everything else. The weights encode the ladder: the more a rung
# forbids, the louder it argues.
#
#   wilderness  opaque       a hard no, unmissable at any zoom
#   trail       ~half        visible over any terrain, still see-through
#   rampart     base (~1/3)  the quietest marked rung, one step from Deed
#   deed        —            no blocker, no overlay: clear ground is owned
#
# Trail's boost is a playtest call: at the base alphas its orange read as
# ~19% over dirt and effectively vanished (screenshot), and halving the
# ribbon width for anti-aliasing had made it fainter still.
RED = COLORS["wilderness"]
STATES = {
    "wilderness": (RED, darken(RED), 1.00, {"ribbon_edge": 255, "ribbon_core": 255}),
    "trail": (COLORS["trail"], darken(COLORS["trail"]), 0.90,
              {"ribbon_edge": 190, "ribbon_core": 125, "inner": 90}),
    "rampart": (RED, darken(RED), 1.00, {}),
}


def make(name, color, dark, alpha_scale, overrides, suffix="", wash=True):
    def a(key):
        override = overrides.get(key)
        if override is not None:
            return override
        return max(1, round(A[key] * alpha_scale))

    # Compute at SIZE*SS, downscale with Lanczos — the anti-aliasing pass.
    # Out-of-stripe pixels carry the stripe RGB at alpha 0 (not black), so
    # the downscale ramps alpha along edges without darkening the hue.
    big = SIZE * SS
    ys, xs = np.mgrid[0:big, 0:big]
    b = np.minimum.reduce([xs, ys, big - 1 - xs, big - 1 - ys])
    d = (xs + ys) % (PERIOD * SS)

    in_border = b < BORDER * SS
    in_inner = (~in_border) & (b < (BORDER + INNER) * SS)
    body = ~in_border & ~in_inner
    in_ribbon = body & (d < RIBBON * SS)
    ribbon_edge = in_ribbon & ((d < EDGE * SS) | (d >= (RIBBON - EDGE) * SS))
    ribbon_core = in_ribbon & ~ribbon_edge
    outside = body & ~in_ribbon

    rgba = np.empty((big, big, 4), dtype=np.uint8)
    rgba[..., 0:3] = color
    rgba[..., 3] = 0
    for mask, rgb, alpha in (
        (in_border, dark, a("border")),
        (in_inner, color, a("inner")),
        (ribbon_edge, dark, a("ribbon_edge")),
        (ribbon_core, color, a("ribbon_core")),
        (outside, color, a("wash") if wash else 0),
    ):
        rgba[mask, 0:3] = rgb
        rgba[mask, 3] = alpha

    img = Image.fromarray(rgba, "RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    out = __file__.rsplit("/", 2)[0] + f"/graphics/{name}-overlay{suffix}.png"
    img.save(out, optimize=True)
    print(f"wrote {out}")


def main():
    for name, (color, dark, scale, overrides) in STATES.items():
        make(name, color, dark, scale, overrides)
    # Chart variants for every blocker state (drawn by scripts/render.lua
    # in map view): identical stripes and cell border, but the
    # between-stripes wash is fully transparent — on the chart the wash
    # reads as a solid background block over the terrain (playtest
    # report), while in the world it sits invisibly on actual ground.
    # Terrain keeps its natural chart colors everywhere; the map carries
    # stripes, never tints (two tint experiments were reverted by
    # playtest: any area recoloring makes the OTHER side of the boundary
    # read as tinted by contrast).
    for name in ("wilderness", "trail", "rampart"):
        color, dark, scale, overrides = STATES[name]
        make(name, color, dark, scale, overrides, suffix="-chart", wash=False)


if __name__ == "__main__":
    main()
