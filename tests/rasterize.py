#!/usr/bin/env python3
"""Rasterize the draw lists written by tests/screenshots.lua.

Each line is either a solid rectangle or an atlas quad:

    R x y w h r g b a
    T x y w h u0 v0 u1 v1 r g b a

Coordinates are already in screen pixels (the renderer applied its integer
scale), so all this does is crop the tile out of tiles.tga, tint it, and blit
it with nearest-neighbour sampling. That is exactly what the client does with
NEAREST filtering.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ATLAS = Image.open(ROOT / "BirdBlocks" / "tiles.tga").convert("RGBA")
SIZE = ATLAS.width


def color(values, alpha=True):
    return tuple(int(max(0.0, min(1.0, v)) * 255 + 0.5) for v in values)


def draw(path: Path, out: Path):
    canvas = None
    lines = path.read_text().splitlines()
    for line in lines:
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "SIZE":
            w, h = int(parts[1]), int(parts[2])
            canvas = Image.new("RGBA", (w, h), (0, 0, 0, 255))
            continue
        if canvas is None:
            raise SystemExit("draw list has no SIZE line: " + str(path))

        if parts[0] == "R":
            x, y, w, h = (float(v) for v in parts[1:5])
            fill = color([float(v) for v in parts[5:9]])
            if fill[3] > 0:
                box = Image.new("RGBA", (max(1, round(w)), max(1, round(h))), fill)
                canvas.alpha_composite(box, (round(x), round(y)))
        else:
            x, y, w, h = (float(v) for v in parts[1:5])
            u0, v0, u1, v1 = (float(v) for v in parts[5:9])
            tint = color([float(v) for v in parts[9:13]])
            if width := round(w):
                crop = ATLAS.crop(
                    (
                        round(u0 * SIZE),
                        round(v0 * SIZE),
                        round(u1 * SIZE),
                        round(v1 * SIZE),
                    )
                )
                if crop.size != (width, round(h)):
                    crop = crop.resize((width, round(h)), Image.NEAREST)
                if tint != (255, 255, 255, 255):
                    px = crop.load()
                    for yy in range(crop.height):
                        for xx in range(crop.width):
                            r, g, b, a = px[xx, yy]
                            px[xx, yy] = (
                                r * tint[0] // 255,
                                g * tint[1] // 255,
                                b * tint[2] // 255,
                                a * tint[3] // 255,
                            )
                canvas.alpha_composite(crop, (round(x), round(y)))

    canvas.convert("RGB").save(out)
    print("wrote", out)


def main():
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "tests" / "out")
    for txt in sorted(folder.glob("*.txt")):
        draw(txt, txt.with_suffix(".png"))


if __name__ == "__main__":
    main()
