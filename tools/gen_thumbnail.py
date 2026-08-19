#!/usr/bin/env python3
"""Generate thumbnail.png — the mod-portal card, in the house style shared
with Multi-Team Support and Open Discord Bridge: 512x512, charcoal ground,
a thin square frame, the three-letter mark, and a grey subtitle in caps.

The letters carry this mod's own state palette rather than arbitrary brand
colors, so the card reads as the same gradient the map does:

    L   wilderness  red     unclaimed
    T   rampart     yellow  midway up the ladder
    R   deed        green   held outright

Below the mark, the ladder itself: four cells wearing the real in-game
overlay artwork, left to right, Wilderness -> Trail -> Rampart -> Deed. The
last cell is empty on purpose. A Deed cell carries no blocker and no
overlay — absence IS the full grant — so the strip resolves from loud red
hatching to clear ground, which is the whole mod in one line.

The strip also does the composition's real work. An earlier card underlaid
the wilderness stripes full-bleed, which put wilderness red directly behind
the wilderness-red L and needed escalating halos to rescue it. Confining
the texture to a strip means the mark sits on flat charcoal and needs no
glow at all; the artwork gets a place where it is the subject rather than
interference.

Colors are parsed from scripts/state_colors.lua (the single source of truth,
same as tools/gen_overlays.py), so retinting the ladder retints the card.

Run from the repo root:  python3 tools/gen_thumbnail.py
"""

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 512
BG = (43, 43, 43)
FRAME = (64, 64, 64)
FRAME_INSET = 14
FRAME_WIDTH = 8
SUBTITLE_FILL = (154, 160, 166)

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

# The ladder strip, centred in the gap between the mark and the subtitle.
LADDER = ("wilderness", "trail", "rampart", "deed")
LADDER_TOP = 316
LADDER_H = 64
LADDER_CELL_W = 92
LADDER_GAP = 4
# Every rung sits on the same patch of ground. The overlays are designed to
# be seen over lit terrain, and over bare charcoal trail's orange and
# rampart's yellow both collapse into the same murky brown -- the hues only
# separate against something to tint. Giving all four cells one neutral
# ground also makes the Deed cell argue for itself: identical land, no
# hatching over it, which is exactly what holding the deed means.
GROUND = (104, 94, 76)
# The Deed cell is drawn as an outline rather than a fill: it has to read as
# "cleared and held", not as "nothing here yet".
DEED_OUTLINE_W = 2


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


def state_swatch(root, state):
    """One ladder cell's worth of a state's overlay artwork.

    The source is scaled to a SQUARE first and the cell cropped out of it.
    Resizing straight to the cell's aspect would shear the 45-degree hatching
    to some other angle, and differently per cell — the stripes have to meet
    the eye at the same angle and width they do in game, including rampart's
    mirrored lean, or the strip stops being a legend for what is on the map.
    """
    src = Image.open(root / f"graphics/{state}-overlay.png").convert("RGBA")
    crop = 10  # the artwork's own cell-edge border + inner line
    src = src.crop((crop, crop, src.width - crop, src.height - crop))
    square = max(LADDER_CELL_W, LADDER_H)
    src = src.resize((square, square), Image.LANCZOS)
    left = (square - LADDER_CELL_W) // 2
    top = (square - LADDER_H) // 2
    return src.crop((left, top, left + LADDER_CELL_W, top + LADDER_H))


def draw_ladder(img, d, root, colors):
    total = len(LADDER) * LADDER_CELL_W + (len(LADDER) - 1) * LADDER_GAP
    x = (SIZE - total) // 2
    for state in LADDER:
        box = [x, LADDER_TOP, x + LADDER_CELL_W - 1, LADDER_TOP + LADDER_H - 1]
        d.rectangle(box, fill=GROUND)
        if state == "deed":
            d.rectangle(box, outline=colors["deed"], width=DEED_OUTLINE_W)
        else:
            swatch = state_swatch(root, state)
            img.paste(swatch, (x, LADDER_TOP), swatch)
        x += LADDER_CELL_W + LADDER_GAP


def build():
    root = Path(__file__).resolve().parent.parent
    colors = load_state_colors()
    img = Image.new("RGB", (SIZE, SIZE), BG)
    d = ImageDraw.Draw(img)

    far = SIZE - 1 - FRAME_INSET
    d.rectangle([FRAME_INSET, FRAME_INSET, far, far], outline=FRAME, width=FRAME_WIDTH)

    layer, bbox = draw_letters(colors)
    left, top, right, bottom = bbox
    offset = (
        round(SIZE / 2 - (left + right) / 2),
        round(LETTERS_CENTRE_Y - (top + bottom) / 2),
    )
    img.paste(layer, offset, layer)

    draw_ladder(img, d, root, colors)

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
