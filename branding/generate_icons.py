#!/usr/bin/env python3
"""Rebuild every SimpleDesk icon from branding/icon.svg.

Needs Inkscape (renders the SVG) and Pillow (builds the ICO files):

    pip install pillow
    python branding/generate_icons.py [--inkscape PATH]
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "branding" / "icon.svg"

ICO_SIZES = [256, 128, 64, 48, 40, 32, 24, 20, 16]
TRAY_SIZES = [32, 24, 20, 16]

PNGS = {
    "res/icon.png": 1024,
    "res/32x32.png": 32,
    "res/64x64.png": 64,
    "res/128x128.png": 128,
    "res/128x128@2x.png": 256,
    "branding/icon-32.png": 32,
    "branding/icon-180.png": 180,
    "branding/icon-512.png": 512,
}

ICOS = {
    "res/icon.ico": ICO_SIZES,
    "flutter/windows/runner/resources/app_icon.ico": ICO_SIZES,
    "res/tray-icon.ico": TRAY_SIZES,
}

SVG_COPIES = ["res/scalable.svg", "flutter/assets/icon.svg"]


def find_inkscape(arg):
    candidates = [arg] if arg else []
    candidates += [
        shutil.which("inkscape"),
        r"C:\Program Files\Inkscape\bin\inkscape.com",
        "/Applications/Inkscape.app/Contents/MacOS/inkscape",
    ]
    for c in candidates:
        if c and Path(c).exists():
            return c
    sys.exit("Inkscape not found, pass --inkscape PATH")


def render(inkscape, size, tmp):
    out = Path(tmp) / f"{size}.png"
    if not out.exists():
        subprocess.run(
            [inkscape, str(SVG), "--export-type=png", f"--export-filename={out}",
             "-w", str(size), "-h", str(size)],
            check=True, capture_output=True)
    with Image.open(out) as im:
        return im.convert("RGBA")


def save_ico(path, images):
    images[0].save(path, format="ICO", sizes=[im.size for im in images],
                   append_images=images[1:])


# The macOS tray takes a template image: only the alpha counts, so keep the
# white screen frames and drop the tile and the screen colours.
def mac_template(icon, size, rgb):
    r, g, b, a = icon.split()
    whiteness = ImageChops.darker(ImageChops.darker(r, g), b)
    alpha = whiteness.point(lambda v: max(0, min(255, (v - 190) * 255 // 65)))
    glyph = Image.new("RGBA", icon.size, rgb + (0,))
    glyph.putalpha(ImageChops.multiply(alpha, a))
    return glyph.resize((size, size), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inkscape", help="path to the Inkscape executable")
    inkscape = find_inkscape(parser.parse_args().inkscape)

    with tempfile.TemporaryDirectory() as tmp:
        for rel, size in PNGS.items():
            render(inkscape, size, tmp).save(ROOT / rel, optimize=True)
        for rel, sizes in ICOS.items():
            save_ico(ROOT / rel, [render(inkscape, s, tmp) for s in sizes])

        mac = Image.new("RGBA", (1024, 1024))
        mac.alpha_composite(render(inkscape, 824, tmp), (100, 100))
        mac.save(ROOT / "res/mac-icon.png", optimize=True)

        big = render(inkscape, 960, tmp)
        mac_template(big, 60, (26, 26, 26)).save(ROOT / "res/mac-tray-dark-x2.png", optimize=True)
        mac_template(big, 48, (255, 255, 255)).save(ROOT / "res/mac-tray-light-x2.png", optimize=True)

    for rel in SVG_COPIES:
        shutil.copyfile(SVG, ROOT / rel)
    print("done")


if __name__ == "__main__":
    main()
