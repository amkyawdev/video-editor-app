#!/usr/bin/env python3
"""Regenerate the Android launcher PNGs from the same geometry as
assets/branding/icon.svg. Requires Pillow. Run from the repo root:

    python3 tool/generate_icons.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"
BRANDING = ROOT / "assets" / "branding"

INK_TOP = (20, 23, 30)
INK_BOTTOM = (7, 8, 11)
AMBER_LIGHT = (255, 215, 154)
AMBER = (242, 178, 74)
AMBER_DEEP = (233, 138, 43)
GLYPH = (23, 18, 10)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size, c0, c1):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = lerp(c0, c1, t)
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_glyph(draw, size, inset, color=GLYPH):
    """Amber chip with a dark play/cut mark, matching the SVG geometry."""
    chip = (inset, inset, size - inset, size - inset)
    draw.rounded_rectangle(
        chip,
        radius=int((size - 2 * inset) * 0.282),
        fill=color,
    )


def build_full_icon(size):
    ss = 4
    big = size * ss
    base = diagonal_gradient(big, INK_TOP, INK_BOTTOM).convert("RGBA")
    glow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    for i in range(30, 0, -1):
        r = int(big * 0.52 * i / 30)
        alpha = int(7 * (1 - i / 30))
        gdraw.ellipse(
            (big * 0.08 - r, big * -0.30 - r, big * 0.08 + r, big * -0.30 + r),
            fill=(242, 178, 74, alpha),
        )
    base.alpha_composite(glow)

    amber_layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    adraw = ImageDraw.Draw(amber_layer)
    inset = int(big * 0.209)
    chip = (inset, inset, big - inset, big - inset)
    adraw.rounded_rectangle(
        chip,
        radius=int((big - 2 * inset) * 0.282),
        fill=(*AMBER, 255),
    )
    # Two dark cut slits and a play triangle.
    slit_w = int(big * 0.045)
    for cx, angle in ((int(big * 0.333), -18), (int(big * 0.667), 18)):
        length = int(big * 0.246)
        rad = math.radians(angle)
        dx, dy = math.cos(rad) * length / 2, math.sin(rad) * length / 2
        adraw.line(
            [(cx - dx, big * 0.5 - dy), (cx + dx, big * 0.5 + dy)],
            fill=GLYPH,
            width=slit_w,
        )
    tri = [
        (big * 0.436, big * 0.366),
        (big * 0.436, big * 0.658),
        (big * 0.574, big * 0.512),
    ]
    adraw.polygon(tri, fill=GLYPH)
    adraw.polygon(
        [
            (big * 0.596, big * 0.366),
            (big * 0.596, big * 0.512),
            (big * 0.458, big * 0.512),
        ],
        fill=(23, 18, 10, 90),
    )
    base.alpha_composite(amber_layer)

    mask = rounded_mask(big, int(big * 0.219))
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def build_foreground(size):
    ss = 4
    big = size * ss
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    # Safe zone: glyph inside the middle 66% of the adaptive canvas.
    glyph_size = int(big * 0.56)
    offset = (big - glyph_size) // 2
    amber = diagonal_gradient(glyph_size, AMBER_LIGHT, AMBER_DEEP).convert("RGBA")
    amber.putalpha(rounded_mask(glyph_size, int(glyph_size * 0.282)))
    draw_glyph_mask = ImageDraw.Draw(amber)
    tri = [
        (glyph_size * 0.40, glyph_size * 0.30),
        (glyph_size * 0.40, glyph_size * 0.70),
        (glyph_size * 0.60, glyph_size * 0.50),
    ]
    draw_glyph_mask.polygon(tri, fill=GLYPH)
    for cx, angle in ((glyph_size * 0.24, -18), (glyph_size * 0.76, 18)):
        length = glyph_size * 0.44
        rad = math.radians(angle)
        dx, dy = math.cos(rad) * length / 2, math.sin(rad) * length / 2
        draw_glyph_mask.line(
            [(cx - dx, glyph_size * 0.5 - dy), (cx + dx, glyph_size * 0.5 + dy)],
            fill=GLYPH,
            width=int(glyph_size * 0.075),
        )
    layer.alpha_composite(amber, (offset, offset))
    return layer.resize((size, size), Image.LANCZOS)


def main():
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    fg_sizes = {
        "mipmap-mdpi": 108,
        "mipmap-hdpi": 162,
        "mipmap-xhdpi": 216,
        "mipmap-xxhdpi": 324,
        "mipmap-xxxhdpi": 432,
    }
    for folder, size in densities.items():
        dest = RES / folder
        dest.mkdir(parents=True, exist_ok=True)
        icon = build_full_icon(size)
        icon.save(dest / "ic_launcher.png")
        round_mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(round_mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        rounded = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        rounded.paste(icon, (0, 0), round_mask)
        rounded.save(dest / "ic_launcher_round.png")
        build_foreground(fg_sizes[folder]).save(
            dest / "ic_launcher_foreground.png"
        )

    BRANDING.mkdir(parents=True, exist_ok=True)
    build_full_icon(512).save(BRANDING / "icon-512.png")
    build_foreground(432).save(BRANDING / "icon-foreground-432.png")
    print("Launcher icons regenerated.")


if __name__ == "__main__":
    main()
