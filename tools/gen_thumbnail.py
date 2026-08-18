#!/usr/bin/env python3
"""Generate thumbnail.png — the mod-portal card, in the house style shared
with Multi-Team Support and Open Discord Bridge: 512x512, charcoal ground,
a thin square frame, the three-letter mark, and a grey subtitle in caps.

The letters carry this mod's own state palette rather than arbitrary brand
colors, so the card reads as the same gradient the map does:

    L   wilderness  red     unclaimed
    T   rampart     yellow  midway up the ladder
    R   deed        green   held outright

Colors are parsed from scripts/state_colors.lua (the single source of truth,
same as tools/gen_overlays.py), so retinting the ladder retints the card.

Run from the repo root:  python3 tools/gen_thumbnail.py
"""

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 512
BG = (43, 43, 43)
FRAME = (64, 64, 64)
FRAME_INSET = 14
FRAME_WIDTH = 8
SUBTITLE_FILL = (154, 160, 166)

# A white halo behind the mark, centred (no offset) rather than cast to one
# side. The card underlays the wilderness stripes, and wilderness red is
# also the L's own color -- so wherever a stripe fell behind the L the
# letter dissolved into it. The halo separates every letter from whatever
# is under it without changing the letters themselves, which have to stay
# on the state palette. Strength lifts the blur's midtones so the halo
# reads as a rim rather than a faint smudge; it clips at full white close
# to the glyph, which is exactly where the contrast is needed.
GLOW = (255, 255, 255)
# Two passes, drawn widest first. The tight rim is what makes the letters
# legible against a stripe; the wide, weak bloom underneath does nothing
# for legibility and everything for depth -- it lifts the mark off the
# striped ground so it reads as floating above the card rather than
# printed on it. Keep the wide pass unboosted: at strength 1.0 a radius-26
# blur is already a thin veil, and lifting it turns the halo into a solid
# blob that closes the counters of the R.
GLOW_PASSES = ((26, 1.0), (5, 2.2))

LETTERS = "LTR"
SUBTITLE = "LAND RIGHTS"
LETTER_STATES = ("wilderness", "rampart", "deed")

# Cap-height centre of the letter block, and the subtitle baseline centre.
# Both sit where MTS and ODB put theirs, so the three cards line up in a row.
LETTERS_CENTRE_Y = 220
SUBTITLE_CENTRE_Y = 426

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
LETTER_SIZE = 185
SUBTITLE_SIZE = 44

# The wilderness overlay as a background underlay: the card wears the
# texture the map wears, at the artwork's own strength — the card adds no
# transparency of its own (playtest call), so retuning the stripes retunes
# the card. It reads the PNG rather than redrawing the pattern, which is
# why 0.1.10's wider, more see-through stripes arrived here for free.


def load_state_colors():
    text = (Path(__file__).resolve().parent.parent / "scripts/state_colors.lua").read_text()
    colors = {}
    for m in re.finditer(r"(\w+)\s*=\s*\{\s*r\s*=\s*(\d+),\s*g\s*=\s*(\d+),\s*b\s*=\s*(\d+)", text):
        colors[m.group(1)] = tuple(int(m.group(i)) for i in (2, 3, 4))
    return colors


def draw_letters(colors):
    """Render the mark on its own layer so it can be centred by its INKED
    bounding box. Centring on advance widths instead leaves the block a few
    pixels off, because L and R carry different side bearings."""
    layer = Image.new("RGBA", (SIZE * 2, SIZE * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT, LETTER_SIZE)

    x = SIZE / 2
    for ch, state in zip(LETTERS, LETTER_STATES):
        d.text((x, SIZE / 2), ch, font=font, fill=colors[state])
        x += d.textlength(ch, font=font)

    return layer, layer.getbbox()


def glow_for(layer, radius, strength):
    """A blurred white copy of `layer`'s coverage, to sit directly behind it."""
    alpha = layer.getchannel("A").filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        alpha = alpha.point(lambda v: min(255, int(v * strength)))
    halo = Image.new("RGBA", layer.size, GLOW + (0,))
    halo.putalpha(alpha)
    return halo


def wilderness_underlay(root):
    """The wilderness stripes, cropped of their baked cell border and sized
    to the card's inner area (inside the frame), at full artwork strength."""
    src = Image.open(root / "graphics/wilderness-overlay.png").convert("RGBA")
    crop = 10  # the artwork's cell-edge border + inner line
    src = src.crop((crop, crop, src.width - crop, src.height - crop))
    inner = SIZE - 2 * (FRAME_INSET + FRAME_WIDTH)
    return src.resize((inner, inner), Image.LANCZOS)


def build():
    root = Path(__file__).resolve().parent.parent
    colors = load_state_colors()
    img = Image.new("RGB", (SIZE, SIZE), BG)
    d = ImageDraw.Draw(img)

    under = wilderness_underlay(root)
    img.paste(under, (FRAME_INSET + FRAME_WIDTH, FRAME_INSET + FRAME_WIDTH), under)

    far = SIZE - 1 - FRAME_INSET
    d.rectangle([FRAME_INSET, FRAME_INSET, far, far], outline=FRAME, width=FRAME_WIDTH)

    layer, bbox = draw_letters(colors)
    left, top, right, bottom = bbox
    offset = (
        round(SIZE / 2 - (left + right) / 2),
        round(LETTERS_CENTRE_Y - (top + bottom) / 2),
    )
    # Halos first, letters over them: the glow only ever shows outside the
    # glyphs, so it never washes out the palette colors it is protecting.
    for radius, strength in GLOW_PASSES:
        halo = glow_for(layer, radius, strength)
        img.paste(halo, offset, halo)
    img.paste(layer, offset, layer)

    font = ImageFont.truetype(FONT, SUBTITLE_SIZE)
    d.text((SIZE / 2, SUBTITLE_CENTRE_Y), SUBTITLE, font=font,
           fill=SUBTITLE_FILL, anchor="mm")

    return img


def main():
    root = Path(__file__).resolve().parent.parent
    out = root / "thumbnail.png"
    build().save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
