#!/usr/bin/env python3
"""Generate graphics/survey-tool.png — a planner-style tool card icon:
parchment card, green diagonal band, 2x2 cell grid with one deeded (gold)
cell and a stake dot. 64x64, distinct at shortcut-bar size.

Run from the repo root:  python3 tools/gen_survey_icon.py
"""

from PIL import Image, ImageDraw

S = 64  # base art size; build(S) renders at any square size


def rounded_rect(d, box, r, **kw):
    d.rounded_rectangle(box, radius=r, **kw)


def build(S=64):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Card: parchment with dark edge (planner-family look).
    rounded_rect(d, [4, 4, 59, 59], 9, fill=(226, 214, 181, 255), outline=(52, 46, 36, 255), width=3)

    # Green diagonal band across the top-left corner (the "planner stripe").
    band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    bd.polygon([(4, 22), (22, 4), (34, 4), (4, 34)], fill=(88, 148, 76, 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([4, 4, 59, 59], radius=9, fill=255)
    img.paste(band, (0, 0), Image.composite(band.split()[3], Image.new("L", (S, S), 0), mask))
    d = ImageDraw.Draw(img)

    # 2x2 cell grid, lower-right area.
    x0, y0, x1, y1 = 18, 18, 52, 52
    mx, my = (x0 + x1) // 2, (y0 + y1) // 2
    # One deeded (gold) cell.
    d.rectangle([mx + 1, my + 1, x1 - 1, y1 - 1], fill=(212, 175, 84, 255))
    for a, b in [((x0, y0), (x1, y0)), ((x0, my), (x1, my)), ((x0, y1), (x1, y1)),
                 ((x0, y0), (x0, y1)), ((mx, y0), (mx, y1)), ((x1, y0), (x1, y1))]:
        d.line([a, b], fill=(72, 62, 48, 255), width=3)

    # Stake dot at the grid's center vertex.
    d.ellipse([mx - 4, my - 4, mx + 4, my + 4], fill=(190, 52, 40, 255), outline=(52, 46, 36, 255))

    return img


def main():
    root = __file__.rsplit("/", 2)[0]
    icon = build(64)
    icon.save(root + "/graphics/survey-tool.png", optimize=True)
    print(f"wrote {root}/graphics/survey-tool.png")
    # The mod-portal thumbnail is NOT built from this mark. It follows the
    # house style shared with Multi-Team Support and Open Discord Bridge —
    # see tools/gen_thumbnail.py, which owns thumbnail.png.


if __name__ == "__main__":
    main()
