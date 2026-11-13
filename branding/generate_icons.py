#!/usr/bin/env python3
"""Rebuild every SimpleDesk icon from branding/icon.svg.

Needs Inkscape (renders the SVG) and Pillow (builds the ICO files):

    pip install pillow
    python branding/generate_icons.py [--inkscape PATH]
"""

import argparse
import re
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

ANDROID_RES = ROOT / "flutter/android/app/src/main/res"
ANDROID_DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
# Middle of the glyph (everything in icon.svg but the tile).
GLYPH_CENTER = (131, 130)


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


def render_text(inkscape, name, svg, size, tmp):
    src = Path(tmp) / f"{name}.svg"
    src.write_text(svg, encoding="utf-8")
    out = Path(tmp) / f"{name}-{size}.png"
    subprocess.run(
        [inkscape, str(src), "--export-type=png", f"--export-filename={out}",
         "-w", str(size), "-h", str(size)],
        check=True, capture_output=True)
    with Image.open(out) as im:
        return im.convert("RGBA")


def android_variants():
    text = SVG.read_text(encoding="utf-8")
    tile = re.search(r'<rect width="256" height="256"[^>]*fill="(#[0-9A-Fa-f]{6})"[^>]*/>', text)
    body = re.search(r"<svg[^>]*>(.*)</svg>", text, re.S)
    if not tile or not body:
        sys.exit("icon.svg: tile or body not found")
    glyph = body.group(1).replace(tile.group(0), "")
    cx, cy = GLYPH_CENTER

    def wrap(view, under, x, y, scale):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{view}" height="{view}" '
                f'viewBox="0 0 {view} {view}">{under}<g transform="translate({x} {y}) '
                f'scale({scale}) translate({-cx} {-cy})">{glyph}</g></svg>')

    color = tile.group(1)
    round_icon = wrap(256, f'<circle cx="128" cy="128" r="128" fill="{color}"/>', 128, 128, 0.8)
    # Adaptive icons are 108dp, but launchers may cut away everything outside
    # the middle circle of 66dp.
    foreground = wrap(108, "", 54, 54, 0.235)
    return color, round_icon, foreground


def rounded_rect_path(x, y, w, h, r):
    if not r:
        return f"M{x},{y}H{x + w}V{y + h}H{x}Z"
    return (f"M{x + r},{y}H{x + w - r}A{r},{r} 0 0 1 {x + w},{y + r}V{y + h - r}"
            f"A{r},{r} 0 0 1 {x + w - r},{y + h}H{x + r}A{r},{r} 0 0 1 {x},{y + h - r}"
            f"V{y + r}A{r},{r} 0 0 1 {x + r},{y}Z")


# icon.svg is made of rects only, so it maps 1:1 onto an Android vector.
def vector_drawable(size_dp):
    lines = [
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        f'    android:width="{size_dp}dp" android:height="{size_dp}dp"',
        '    android:viewportWidth="256" android:viewportHeight="256">',
    ]
    for attrs in re.findall(r"<rect([^>]*)/>", SVG.read_text(encoding="utf-8")):
        a = dict(re.findall(r'([\w-]+)="([^"]*)"', attrs))

        def num(key):
            v = float(a.get(key, "0"))
            return int(v) if v.is_integer() else v

        path = rounded_rect_path(num("x"), num("y"), num("width"), num("height"), num("rx"))
        line = f'    <path android:fillColor="{a["fill"]}" android:pathData="{path}"'
        if "stroke" in a:
            line += f' android:strokeColor="{a["stroke"]}" android:strokeWidth="{num("stroke-width")}"'
        lines.append(line + "/>")
    lines.append("</vector>")
    return "\n".join(lines) + "\n"


def android_icons(inkscape, tmp):
    color, round_icon, foreground = android_variants()
    big_icon = render(inkscape, 960, tmp)
    big_foreground = render_text(inkscape, "foreground", foreground, 1080, tmp)
    white = (255, 255, 255)
    for density, scale in ANDROID_DENSITIES.items():
        folder = ANDROID_RES / f"mipmap-{density}"

        def px(dp):
            return round(dp * scale)

        render(inkscape, px(48), tmp).save(folder / "ic_launcher.png", optimize=True)
        render_text(inkscape, "round", round_icon, px(48), tmp).save(
            folder / "ic_launcher_round.png", optimize=True)
        render_text(inkscape, "foreground", foreground, px(108), tmp).save(
            folder / "ic_launcher_foreground.png", optimize=True)
        # Themed launcher icons and notification icons use only the alpha too.
        mac_template(big_foreground, px(108), white).save(
            folder / "ic_launcher_monochrome.png", optimize=True)
        mac_template(big_icon, px(24), white).save(folder / "ic_stat_logo.png", optimize=True)

    (ANDROID_RES / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{color}</color>\n</resources>\n',
        encoding="utf-8")
    (ANDROID_RES / "drawable/floating_window.xml").write_text(vector_drawable(320), encoding="utf-8")


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

        android_icons(inkscape, tmp)

    for rel in SVG_COPIES:
        shutil.copyfile(SVG, ROOT / rel)
    print("done")


if __name__ == "__main__":
    main()
