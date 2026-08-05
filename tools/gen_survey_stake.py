#!/usr/bin/env python3
"""Generate graphics/survey-stake.png — the corner stake marker drawn at
frontier vertices (the mod's visual signature). Drawn in white/grey so the
runtime tint carries the force or planet color.

Run from the repo root:  python3 tools/gen_survey_stake.py
"""

from PIL import Image, ImageDraw

SIZE = 64


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = SIZE // 2

    # Diamond head (rotated square), white fill for tinting, dark outline.
    r = 18
    diamond = [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]
    d.polygon(diamond, fill=(255, 255, 255, 235), outline=(40, 40, 40, 255))
    r2 = 11
    d.polygon([(c, c - r2), (c + r2, c), (c, c + r2), (c - r2, c)],
              outline=(90, 90, 90, 200))
    # Center peg dot.
    d.ellipse([c - 3, c - 3, c + 3, c + 3], fill=(40, 40, 40, 255))

    out = __file__.rsplit("/", 2)[0] + "/graphics/survey-stake.png"
    img.save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
