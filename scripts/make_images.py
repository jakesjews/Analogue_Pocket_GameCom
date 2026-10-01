#!/usr/bin/env python3
"""Convert the PNG art in dist/art to the Pocket's .bin graphics (needs Pillow).

Pocket graphics (Analogue docs, "Graphical Asset Formats") are 16 bits per
pixel, stored rotated 90 degrees counter-clockwise. The first byte of each
pixel holds the level and the second byte is always 0 (0xFF00, "fully on",
when read as the spec's big-endian word). Levels are inverted relative to how
the Pocket, the openFPGA library and Pocket Sync display them: 0x00 shows as
white and 0xFF as black. The PNGs here are kept as they should look on screen.

    make_images.py                         rebuild both .bin files from dist/art
    make_images.py --decode IN.bin OUT.png decode a .bin back to a PNG to check it
"""
from pathlib import Path
import argparse

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SIZES = [(521, 165), (36, 36)]  # platform image, core icon
TARGETS = {
    ROOT / "dist/art/gamecom_platform.png": ROOT / "dist/platforms/_images/gamecom.bin",
    ROOT / "dist/art/gamecom_icon.png": ROOT / "dist/icon.bin",
}


def encode(png, dest):
    image = Image.open(png).convert("L")
    if image.size not in SIZES:
        raise SystemExit(f"{png} is {image.size[0]}x{image.size[1]}; expected 521x165 or 36x36")
    levels = ImageOps.invert(image).transpose(Image.Transpose.ROTATE_90).tobytes()
    data = bytearray(2 * len(levels))
    data[0::2] = levels
    dest.write_bytes(data)
    print(f"{png} -> {dest} ({len(data)} bytes)")


def decode(path):
    data = path.read_bytes()
    sizes = {w * h * 2: (w, h) for w, h in SIZES}
    if len(data) not in sizes:
        raise SystemExit(f"{path} is {len(data)} bytes; not a platform image or icon")
    width, height = sizes[len(data)]
    stored = Image.frombytes("L", (height, width), bytes(data[0::2]))
    return ImageOps.invert(stored.transpose(Image.Transpose.ROTATE_270))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decode", nargs=2, type=Path, metavar=("BIN", "PNG"))
    args = parser.parse_args()
    if args.decode:
        source, dest = args.decode
        decode(source).save(dest)
        print(f"{source} -> {dest}")
        return
    for png, dest in TARGETS.items():
        encode(png, dest)


if __name__ == "__main__":
    main()
