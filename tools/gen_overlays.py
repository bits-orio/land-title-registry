#!/usr/bin/env python3
"""Generate the per-state cell overlays drawn by the blocker entities
(ADR-0009). One shared ribbon pattern; the states differ in color and
stripe strength (playtest call, 0.1.8: the original full-strength red
pattern reads as "fortified, not yet fully yours" and now marks RAMPART;
wilderness escalates the same artwork to fully opaque red stripes,
unmistakable at any zoom):

    wilderness  red, the widest stripes   (hard no)
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
# The pattern is deliberately COARSE. A stripe has to survive map view,
# where the engine minifies these 1024 px textures by 10-40x, and no
# filtering can rescue a feature narrower than a screen pixel. Measured
# against the zoom range in a real save (cells landing at 40-110 px on
# screen, so 1.7-4.6 px per tile):
#
#     ribbon  16 / period 128   stripe 0.38 tiles ->  0.6-1.5 px   aliases
#     ribbon  64 / period 256   stripe 1.50 tiles ->  2.5-6.0 px   holds
#     ribbon 128 / period 256   stripe 3.00 tiles -> 5.0-13.8 px   current
#
# At sub-pixel width, whether a screen pixel lands on a stripe or a gap
# comes down to zoom phase, not to the art: the stripes read bold at one
# zoom, break up at the next, and vanish entirely at a third (playtest
# report, with screenshots at five zoom steps).
#
# Note this is NOT fixable with mipmap_count -- the prototype docs restrict
# that field to icons ("only loaded if this is an icon, that is it has the
# flag group=icon or group=gui"), so a mip chain on a world sprite is
# silently ignored. Feature size is the only lever that works.
#
# Both numbers must divide SIZE so the diagonal pattern stays seamless
# across adjacent same-state cells; 256 gives four periods per cell.
# Ribbon equals half the period, so stripes and gaps come out the same
# width. Ink coverage doubles to 50% at this width, which is paid for by
# roughly halving the stripe alphas below: the same amount of red, spread
# twice as wide at half the density, which is what survives minification.
PERIOD = 256
RIBBON = 128
# The stripe's darker rim, and deliberately NOT scaled with RIBBON. It is
# not a design element with a proportion to preserve -- it exists to stop
# the stripe bleeding into the terrain underneath and to give the diagonal
# something to anti-alias against. Both jobs are done by a few pixels
# regardless of how wide the stripe itself gets, and scaling it up just
# eats the stripe's interior with dark trim.
EDGE = 4
BORDER = 4
INNER = 2

# Supersampling factor: the pattern is computed at SIZE*SS and downscaled
# with Lanczos, anti-aliasing every diagonal edge. The hard per-pixel
# thresholds looked fine at the old translucent alphas but turned into
# staircases once the wilderness stripes went fully opaque (playtest
# report: "as if anti-aliasing isn't happening" — it wasn't).
SS = 4

# Base alphas at full strength (wilderness). Only RAMPART reads the ribbon
# pair directly -- wilderness and trail override both below -- so those two
# numbers are effectively rampart's dial, and they are NOT halved the way
# the other states were when ribbon went 64 -> 128. Halving them was a
# mistake: rampart is already the faintest rung, and taking the
# coverage-doubling discount on top of that put it at mean alpha 19, which
# playtest could not see in either view. Being the quietest rung still
# means being visible.
A = {
    "border": 120,
    "inner": 60,
    "ribbon_edge": 110,
    "ribbon_core": 72,
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
#   wilderness  mean a 67   a hard no, unmissable at any zoom
#   trail       mean a 48    visible over any terrain, still see-through
#   rampart     mean a 39    the quietest marked rung, one step from Deed
#   deed        —            no blocker, no overlay: clear ground is owned
#
# Trail's boost is a playtest call: at the base alphas its orange read as
# ~19% over dirt and effectively vanished (screenshot), and halving the
# ribbon width for anti-aliasing had made it fainter still.
RED = COLORS["wilderness"]
STATES = {
    "wilderness": (RED, darken(RED), 1.00, {"ribbon_edge": 170, "ribbon_core": 130}),
    "trail": (COLORS["trail"], darken(COLORS["trail"]), 0.90,
              {"ribbon_edge": 125, "ribbon_core": 90, "inner": 90}),
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
